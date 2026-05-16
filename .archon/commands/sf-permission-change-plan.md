# `sf-permission-change-plan`

You are producing the structured plan for a permission/security change. The plan is what the pre-execute gate displays to the engineer, and what the execute step implements against. **No metadata is changed here** — this step is plan-only.

This family has the highest blast radius of any Salesforce task family — per [ADR-0020](../decisions/0020-sf-permission-change-scope-and-gates.md). The plan step's critical responsibility is computing the `removes_access` / `narrows_access` / `tightens` flags that drive the pre-execute gate's choice of confirmation literal (`CONFIRM-OWD` vs `CONFIRM` vs `y`/`yes`). Get this wrong and the engineer is asked the wrong question.

## Inputs

- `$pull-jira-context.output` — the ticket
- `$classify-sub-type.output` — sub_type, scope, side flags
- `$smoke-validate-claims.output` — accuracy of ticket claims
- `$verify-org-context.output` — org context
- `$load-engagement-context.output` — engagement.yaml, patterns/standards, object docs, existing security docs

## Tools

File reads, Glob, Grep against the engagement repo. Specifically:
- `force-app/main/default/profiles/`
- `force-app/main/default/permissionsets/`
- `force-app/main/default/permissionsetgroups/`
- `force-app/main/default/sharingRules/`
- `force-app/main/default/objects/*/`*.object-meta.xml` (for OWD)
- `force-app/main/default/objects/*/restrictionRules/`
- `force-app/main/default/customPermissions/`
- `force-app/main/default/groups/`, `roles/` (for sharing rule recipient validation)
- `docs/security/`, `docs/objects/` (for cross-referencing)

Bash for `git show HEAD:<path>` to diff staged-but-uncommitted against HEAD. No file writes. No SF CLI. No Jira writes.

## Task

1. **Re-read the ticket's acceptance criteria.** The plan must satisfy every AC, or explicitly flag which ones are out of scope.

2. **Map sub_type to plan content.** Per ADR-0020 §1:

   | sub_type | Plan must specify |
   |---|---|
   | `create-permission-set` | New `.permissionset-meta.xml` path, granted permissions inventory (objects + fields + system perms + custom perms + class/page/app accesses), target assignees (which profiles/PSGs reference it), license requirement |
   | `modify-permission-set` | PS path, the full diff of added vs removed permissions per category, **`removes_access` flag** |
   | `delete-permission-set` | PS path, every profile/PSG that assigns this PS, every user impact (estimated from license count if known), what was previously granted (caller-impact analysis) |
   | `create-permission-set-group` | New `.permissionsetgroup-meta.xml` path, composed PSs, intended assignees |
   | `modify-permission-set-group` | PSG path, PSs added or removed from composition |
   | `delete-permission-set-group` | PSG path, every user impacted, every composed PS that becomes effectively un-assigned-via-group |
   | `modify-profile` | Profile path, the full diff per category, **`removes_access` flag**, every user with this profile (count if known) |
   | `create-sharing-rule` | Rule path, object, criterion, recipient, access level, recipient existence verification |
   | `modify-sharing-rule` | Rule path, the diff of criterion / recipient / access level, **`narrows_access` flag** |
   | `delete-sharing-rule` | Rule path, recipients who lose access, what records they used to see |
   | `modify-owd` | Object path, old `<sharingModel>` value, new value, **`owd_direction` (`widening` / `narrowing` / `cbp-transition`)**, every dependent sharing rule on this object that becomes effectively no-op or newly-necessary |
   | `create-restriction-rule` | Rule path, object, condition, what gets restricted from whom |
   | `modify-restriction-rule` | Rule path, the diff of condition / restricted-to, **`tightens` flag** |
   | `delete-restriction-rule` | Rule path, what restriction is being removed (i.e., what access is being un-restricted) |

3. **Compute the destructive flags by structural diff.** For each modified XML file:
   - Run `git show HEAD:<path> > /tmp/before.xml` (use `/dev/null` if newly added).
   - Parse both versions structurally (NOT raw textual diff — whitespace and attribute order shifts will produce false positives).
   - Count permissions added (in working tree but not in HEAD) and removed (in HEAD but not in working tree) across every category: `<objectPermissions>`, `<fieldPermissions>`, `<applicationVisibilities>`, `<tabSettings>`/`<tabVisibilities>`, `<userPermissions>`, `<classAccesses>`, `<pageAccesses>`, `<connectedAppAccesses>`, `<customPermissions>`.
   - Set `removes_access: "true"` if `removed_count > 0` in any category.
   - For `modify-sharing-rule`: compute `narrows_access` by comparing recipient (smaller group = narrower), access level (Read < Read/Write), and criterion (more restrictive criterion narrows). If any dimension narrowed, set `narrows_access: "true"`.
   - For `modify-restriction-rule`: a restriction rule with a broader `<recordFilter>` condition (more records hidden) OR a narrower `<userCriteria>` (fewer exempt users) means `tightens: "true"`.
   - For `modify-owd`: compute direction:
     - Private → Public Read = widening
     - Private → Public Read/Write = widening
     - Public Read → Public Read/Write = widening
     - Public Read/Write → Public Read = narrowing
     - Public Read → Private = narrowing
     - Public Read/Write → Private = narrowing
     - any → Controlled by Parent = cbp-transition (manual review)

4. **Caller-impact analysis for destructive operations:**
   - `delete-permission-set`: grep every `force-app/main/default/profiles/*.profile-meta.xml` for the PS name (unusual but possible if a profile references PS-style entitlements); grep every PSG XML for `<permissionSets><permissionSetName>X</permissionSetName>`. Record the list.
   - `delete-permission-set-group`: there's no source-side reference to PSGs (assignments are user-side), so caller-impact is "estimated users via PSG" — note that we can't enumerate without org access.
   - `modify-profile` with `removes_access: true`: list every user-permission removed; note that we can't enumerate affected users without org access (estimated from profile XML's license count if `engagement.yaml` records it).
   - `delete-sharing-rule`: identify the recipient (Public Group / Role / Queue) and the access it granted; the recipients lose that access.
   - `modify-owd` to a narrower setting: identify dependent sharing rules — they may become newly necessary to preserve access for groups that previously got it via the broader OWD.
   - `delete-restriction-rule`: the restricted access is unblocked — list who now has access they previously didn't.

5. **Recipient existence pre-check** (for `create-sharing-rule` / `modify-sharing-rule`):
   - Parse the rule's `<sharedTo>` element.
   - For each referenced public group: verify `force-app/main/default/groups/<name>.group-meta.xml` exists.
   - For each referenced role: verify `force-app/main/default/roles/<name>.role-meta.xml` exists.
   - For each referenced queue: same path as groups with `<type>Queue</type>`.
   - If any reference is dangling, flag it in the plan; the deploy will fail otherwise.

6. **Custom Permission orphan pre-check** (for `modify-profile` / `modify-permission-set` that drop a `<customPermissions>` entry):
   - For each removed grant, check if any OTHER profile/PS in the engagement still grants it.
   - If none does, the custom permission is about to be orphaned. Grep `force-app/` for usages:
     ```
     grep -rln "FeatureManagement\.checkPermission('<name>')\|FeatureManagement\.checkPermission(\"<name>\")" force-app/
     ```
   - Record orphan candidates in the plan; the validate step re-confirms.

7. **Identify documentation outputs.** Per ADR-0020 §6, the document step writes to:
   - Every changed profile → `docs/security/profiles/<Profile_Name>.md`
   - Every changed PS → `docs/security/permission-sets/<PS_Name>.md`
   - If PSG composition changed → `docs/security/permission-set-groups.md`
   - If OWD / sharing rule / restriction rule changed → `docs/security/sharing-model.md`
   - If custom permission grants changed → `docs/security/custom-permissions.md`
   - For each object whose OWD changed → `docs/objects/<Object>.md` "Sharing model" subsection
   - Posture-shift heuristic triggers → draft engagement-ADR in `docs/decisions/`

8. **Identify the engagement-ADR draft trigger.** A change is a "significant posture shift" if ANY:
   - `sub_type == 'modify-owd'` (always — every OWD change is posture-shifting)
   - `sub_type == 'delete-sharing-rule'` AND the rule's name suggests business-meaningful access (e.g., contains words like `Council`, `Approvers`, `Executive`, `Audit`)
   - `sub_type == 'modify-profile'` AND the plan removes `viewAllRecords` or `modifyAllRecords` from any object
   - `sub_type == 'create-restriction-rule'` AND the object had no restriction rules previously

9. **Identify risk surface.** Note any of:
   - **High-volume profile**: profile has a stated license-count > 50 (from `engagement.yaml` or docs).
   - **Cross-cutting change**: multiple profiles or PSs touched (the change reverberates across user populations).
   - **Custom permission orphan risk**: a grant being removed AND Apex code still references the permission.
   - **Recipient dangling**: a sharing rule references a Public Group / Role / Queue that doesn't exist.
   - **OWD downstream effects**: narrowing an OWD may break existing role-hierarchy-based assumptions.
   - **Admin profile touched**: removing access from a `System Administrator`-class profile.

   These are surfaced at the gate and embedded in the doc updates.

## Output

Write the structured plan to `$ARTIFACTS_DIR/plan.md` as readable markdown. Also emit a JSON summary on stdout for the gate node:

```json
{
  "summary": "Remove ManageRenewals from Custom_Sales_Manager_PS; replace with finer-grained ApproveRenewalDiscount custom permission grant.",
  "sub_type": "modify-permission-set",
  "scope": "small",
  "files_changed": [
    {"path": "force-app/main/default/permissionsets/Custom_Sales_Manager_PS.permissionset-meta.xml", "operation": "modify"}
  ],
  "added_count": 1,
  "removed_count": 1,
  "removed_breakdown": [
    {"category": "customPermissions", "target": "ManageRenewals"}
  ],
  "added_breakdown": [
    {"category": "customPermissions", "target": "ApproveRenewalDiscount"}
  ],
  "removes_access": "true",
  "narrows_access": "false",
  "tightens": "false",
  "owd_direction": "n/a",
  "caller_impact": {
    "profiles_referencing_ps": ["Custom_Sales_Manager_Profile"],
    "psgs_referencing_ps": ["Sales_Manager_PSG"]
  },
  "recipient_existence_check": "n/a",
  "orphan_candidates": [
    {"custom_permission": "ManageRenewals", "still_granted_by": [], "apex_callers": ["RenewalApprovalHandler.cls"]}
  ],
  "posture_shift_triggers_adr_draft": false,
  "doc_outputs": [
    "docs/security/permission-sets/Custom_Sales_Manager_PS.md",
    "docs/security/custom-permissions.md"
  ],
  "risks": [
    "Custom permission ManageRenewals is referenced by RenewalApprovalHandler.cls; removing the grant breaks the feature unless the code is updated in the same release."
  ],
  "out_of_scope_acceptance_criteria": []
}
```

The full plan goes to the artifact file (with the per-artifact diffs spelled out in markdown tables); the JSON is the structured summary the gate node reads to choose the confirmation literal.

## Critical: getting `removes_access` right

The pre-execute gate keys its confirmation form off this single field for `modify-permission-set` and (implicitly via the per-category breakdown) for `modify-profile`. Wrong here = wrong gate = either spurious `CONFIRM` for an additive change (engineer annoyed) OR easy `y`/`yes` for a destructive change (engineer rubber-stamps real access removal). Get the diff right.

Don't infer `removes_access` from the ticket description alone — always run the structural diff against `git show HEAD:<path>`. The ticket is a description; the XML diff is the truth.
