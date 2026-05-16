# `sf-permission-change-validate`

You are orchestrating the validation gates for the permission change executed in the previous step. This command does NOT itself deploy or run org-side checks — it calls the supporting script(s) and performs the inline static analyses, then aggregates.

## Inputs

- `$execute.output` — list of files actually changed
- `$plan.output` — the JSON plan (including `removed_breakdown`, `added_breakdown`, `caller_impact`, `orphan_candidates`)
- `$classify-sub-type.output` — `sub_type`, `affects_admin_profile`, `affects_critical_object`, `removes_custom_permission_grant`
- `$load-engagement-context.output` — engagement metadata
- `$verify-org-context.output` — `target_org_alias`, `is_scratch_org`, `scratch_org_def_path`

## Tools

Bash for the supporting script and inline checks (`git show`, `grep`, XML parsing via `xmllint`). Read for cross-referencing engagement docs. No file writes. No SF CLI directly (the deploy script wraps it).

The supporting script lives at `.archon/scripts/`:

- `deploy-to-scratch.sh` — creates a scratch org from `scratch_org_def_path` (if not already running) and deploys the changed metadata. Returns 0 on success.

The other four checks (blast-radius diff, orphan check, OWD direction, recipient existence) run inline in this command — they're parse-and-grep operations that don't warrant separate scripts and would otherwise multiply this family's script count.

## Task — five-step validate

### Step 1: Deploy to scratch (always)

```bash
bash .archon/scripts/deploy-to-scratch.sh "$target_org_alias" force-app/main/default/
```

Capture exit code and structured output. If deploy fails, the workflow can't continue — set `overall_result: "fail"`, set `failure_reasons` to the deploy error, stop.

**Critical caveat to surface:** scratch orgs do NOT faithfully validate sharing or OWD behavior. They typically have one seeded user, no record volume, and no role hierarchy. Deploy success means "this metadata is structurally valid"; it does NOT mean "this sharing change behaves correctly in production." This caveat must be in the structured output's `caveats[]` field and is repeated by the document step in the sharing-model doc updates.

### Step 2: Static blast-radius diff (inline)

For each modified `.profile-meta.xml`, `.permissionset-meta.xml`, `.permissionsetgroup-meta.xml`:

```bash
git show "HEAD:$path" > /tmp/before-${RANDOM}.xml 2>/dev/null || echo "" > /tmp/before-${RANDOM}.xml
# Parse both versions structurally, NOT raw textual diff.
# Use xmllint --c14n to canonicalize, then compare element-by-element.
```

Compute, per category (`<objectPermissions>`, `<fieldPermissions>`, `<applicationVisibilities>`, `<tabSettings>`, `<userPermissions>`, `<classAccesses>`, `<pageAccesses>`, `<connectedAppAccesses>`, `<customPermissions>`):

- `added_count`: entries in working tree not in HEAD.
- `removed_count`: entries in HEAD not in working tree.
- `removed_breakdown[]`: list of `{category, target}` for each removed entry.

Aggregate per artifact and across all artifacts. The plan's `removed_count` should match this measurement (cross-check; if they diverge, the plan was wrong — flag a deviation in the structured output).

This step **does not gate** (the pre-execute gate already used these numbers via the plan); it's recorded in the structured output for the document step and the Jira comment.

### Step 3: Custom Permission orphan check (conditional)

Fires when `$classify-sub-type.output.removes_custom_permission_grant == "true"` OR the blast-radius diff detected any removed `<customPermissions>` entries.

For each removed custom permission grant:

1. Check if any OTHER profile/PS still grants it:
   ```bash
   grep -rln "<name>${CUSTOM_PERM_NAME}</name>" force-app/main/default/profiles/ force-app/main/default/permissionsets/ | grep -v "<file currently being modified>" || true
   ```
   If a match exists (and the match is "still granted" — `<enabled>true</enabled>` nearby), the permission is NOT orphaned by this change.

2. If no other profile/PS still grants it, the permission is now orphaned. Grep for usages:
   ```bash
   grep -rln "FeatureManagement\.checkPermission(['\"]${CUSTOM_PERM_NAME}['\"])" \
     force-app/main/default/classes/ \
     force-app/main/default/triggers/ \
     force-app/main/default/flows/ 2>/dev/null || true
   ```

3. If usages exist: set `orphan_result: "warn"`. The post-validate gate will fire and the engineer either confirms the orphan is intentional or aborts.
4. If no usages: set `orphan_result: "clean"`. The Custom Permission is genuinely unused and removing the grants is fine; the engineer may also want to delete the Custom Permission definition file in a follow-up (record this in `$ARTIFACTS_DIR/follow-ups.md`).
5. If no custom permission grants were removed: set `orphan_result: "n/a"`.

### Step 4: OWD downgrade direction (conditional)

Fires when `$classify-sub-type.output.sub_type == "modify-owd"`.

Already computed in the plan's `owd_direction` field. This step verifies the plan's computation against the actual deployed XML:

```bash
git show "HEAD:$object_path" | xmllint --xpath "//sharingModel/text()" - 2>/dev/null
xmllint --xpath "//sharingModel/text()" "$object_path" 2>/dev/null
```

Compute direction (widening / narrowing / cbp-transition / no-change) from before vs after. Cross-check against `$plan.output.owd_direction`; if they disagree, the plan was wrong (the engineer modified XML differently from the plan, OR the plan got the comparison wrong) — surface this in the structured output's `failure_reasons`.

Direction is informational here (the gate already accepted the change at pre-execute). The document step uses the direction to write appropriate language in `docs/security/sharing-model.md` and the object's doc.

For `cbp-transition`: flag a `warn` requiring engineer review (Controlled by Parent has different semantics than the other OWD values and should be reviewed by hand even if the deploy succeeded). The post-validate gate does NOT auto-fire on this — the engineer was supposed to review it at pre-execute — but the structured output records the warning for the Jira comment.

### Step 5: Sharing rule recipient existence (conditional)

Fires when `$classify-sub-type.output.sub_type ∈ {"create-sharing-rule", "modify-sharing-rule"}`.

For each rule in the modified `.sharingRules-meta.xml`:

1. Parse `<sharedTo>` element. Determine type and name:
   - `<group>X</group>` → expect `force-app/main/default/groups/X.group-meta.xml`
   - `<queue>X</queue>` → expect `force-app/main/default/groups/X.group-meta.xml` with `<type>Queue</type>`
   - `<role>X</role>` or `<roleAndSubordinates>X</roleAndSubordinates>` → expect `force-app/main/default/roles/X.role-meta.xml`
   - `<allInternalUsers/>` / `<allCustomerPortalUsers/>` → no file check needed.

2. If the expected file doesn't exist, the deploy will fail (it already may have, but this gives early detection). Set `recipient_result: "fail"` with the dangling reference name.

3. For ownership-based rules, also verify `<sharedFrom>` resolves the same way.

If `recipient_result == "fail"`: the workflow's `overall_result` is `fail` — the deploy did NOT actually succeed (the script returned 0 but Salesforce will reject this on deploy to a real org, OR the scratch deploy already failed and we're seeing the same root cause). The engineer fixes the recipient reference and re-runs.

### Step 6: Admin lockout paranoia check (conditional)

Fires when `$classify-sub-type.output.affects_admin_profile == "true"` AND `$plan.output.removes_access == "true"`.

For the changed `System Administrator`-class profile (heuristic: profile's `<userLicense>` is `Salesforce` AND profile name contains `Admin` OR the profile already had `<viewAllRecords>true</viewAllRecords>` AND `<modifyAllRecords>true</modifyAllRecords>` on every custom object in HEAD):

1. Check if the change removes `viewAllRecords` or `modifyAllRecords` from any object.
2. Check if the change removes the `ModifyAllData` or `ViewAllData` system permission.
3. If either, set `admin_lockout_result: "fail"`. The post-validate gate fires.

If none of those conditions: set `admin_lockout_result: "pass"`.
If `affects_admin_profile == "false"`: set `admin_lockout_result: "n/a"`.

### Aggregation

```
overall_result = "pass" if and only if:
  - deploy_result == "pass" (or "pass-with-caveats" — see Step 1)
  - recipient_result == "pass" or "n/a"
  - admin_lockout_result != "fail" OR gate-post-validate.proceed == "true"
  - orphan_result != "warn" OR gate-post-validate.proceed == "true"

  (The post-validate gate's proceed isn't known at validate time, so
   validate emits the warn / fail; the workflow YAML conditions
   gate-post-validate on validate's output AND conditions document on
   gate-post-validate.proceed.)

overall_result = "fail" otherwise.
```

## Output

```json
{
  "deploy_result": "pass-with-caveats",
  "deploy_artifact": "$ARTIFACTS_DIR/deploy-to-scratch.json",
  "caveats": [
    "scratch orgs do not faithfully validate sharing/OWD; deploy success = structural validity only"
  ],
  "blast_radius_summary": {
    "added_count": 1,
    "removed_count": 1,
    "per_category": {
      "customPermissions": {"added": 1, "removed": 1}
    }
  },
  "removed_breakdown": [
    {"file": "force-app/main/default/permissionsets/Custom_Sales_Manager_PS.permissionset-meta.xml", "category": "customPermissions", "target": "ManageRenewals"}
  ],
  "orphan_result": "warn",
  "orphans_found": [
    {"custom_permission": "ManageRenewals", "still_granted_by": [], "apex_callers": ["force-app/main/default/classes/RenewalApprovalHandler.cls"]}
  ],
  "owd_direction": "n/a",
  "recipient_result": "n/a",
  "admin_lockout_result": "n/a",
  "overall_result": "fail",
  "failure_reasons": [
    "custom permission ManageRenewals is now orphaned but RenewalApprovalHandler.cls still calls FeatureManagement.checkPermission for it"
  ],
  "duration_seconds": 78
}
```

The post-validate gate (in the workflow YAML) fires on `orphan_result == "warn"` or `admin_lockout_result == "fail"`, displays the issues, and accepts `CONFIRM` to proceed.

## Inline-check rationale

The blast-radius diff, orphan check, OWD direction, recipient existence, and admin lockout checks are inline here rather than separate scripts because:

- Each is a parse-and-grep operation that runs in seconds.
- Separate scripts would multiply this family's script count to 5+, complicating maintenance.
- The checks are tightly coupled to this validate step's output schema; an external script would have to round-trip JSON to communicate, adding indirection.

Only `deploy-to-scratch.sh` warrants script-level extraction because it's reused by every Phase 7 family workflow (per the existing convention).
