# `sf-permission-change-execute`

You are implementing the permission/security change against the engagement repo's working tree, following the plan produced by `sf-permission-change-plan`. **You do not deploy, run static checks, or update Jira here** — those are downstream.

## Inputs

- `$ARTIFACTS_DIR/plan.md` — the full plan
- `$plan.output` — the JSON summary (including `files_changed`, `removed_breakdown`, `added_breakdown`)
- `$load-engagement-context.output` — engagement metadata, patterns
- `$verify-org-context.output` — org info (api_version)
- `$classify-sub-type.output` — sub_type, side flags

## Tools

Read, Edit, Write, Glob, Grep, Bash (for `git status`, `git diff` only — no commits). No SF CLI. No Jira writes. No network.

## Task

1. **Read the full plan** from `$ARTIFACTS_DIR/plan.md`. Treat it as authoritative.

2. **Implement the XML changes** per the plan's `files_changed` list:
   - For `add` operations: Write the new `.permissionset-meta.xml` / `.permissionsetgroup-meta.xml` / `.sharingRules-meta.xml` / `.restrictionRule-meta.xml` with content matching the plan. Use the engagement's `api_version` from `$verify-org-context.output` for the `<Package xmlns>` root version field (or the per-file `xmlns="http://soap.sforce.com/2006/04/metadata"` namespace).
   - For `modify` operations: Edit the existing file with surgical XML element insertions/removals. Preserve all unrelated elements, attribute order, and whitespace. Profile XMLs in particular are large; do not reformat.
   - For `delete` operations: Remove the file. The engagement's `dev_model` (from `$load-engagement-context.output.engagement.dev_model`) determines whether you also update `manifest/destructiveChanges.xml`:
     - `source_tracked` → update or create `manifest/destructiveChanges.xml` with the appropriate `<types>` entry (e.g., `<members>Renewal_Approver_PS</members><name>PermissionSet</name>`).
     - `org_development` → leave the destructive manifest to the deploy step.

3. **Sub-type-specific implementation notes**:

   ### `modify-profile`
   - Profile XMLs are sorted alphabetically by element type, then alphabetically by target. **Maintain alphabetical sort order** when adding entries — Salesforce metadata retrieves always re-sort, so any deviation will show up as spurious noise on the next pull.
   - Adding a `<fieldPermissions>` entry: must include all of `<editable>`, `<field>` (in `Object.Field` form), `<readable>`. Omitting `<editable>` or `<readable>` is invalid.
   - Adding an `<objectPermissions>` entry: must include all six boolean fields (`<allowCreate>`, `<allowDelete>`, `<allowEdit>`, `<allowRead>`, `<modifyAllRecords>`, `<viewAllRecords>`) plus `<object>`. Setting `<modifyAllRecords>true</modifyAllRecords>` implies all CRUD; for clarity, set those explicitly too.
   - System permissions in `<userPermissions>`: each has `<enabled>` and `<name>`. The platform rejects disabled-stock permissions silently in some cases; only emit `<userPermissions>` entries that are enabled.

   ### `modify-permission-set` / `create-permission-set`
   - PS XMLs follow the same element-sort discipline as profiles.
   - `<hasActivationRequired>` defaults to `false`; only emit when `true`.
   - `<license>` is omitted when the PS does not require a permission set license.
   - `<customPermissions>` entries grant the custom permission to the assignee; each has `<enabled>true</enabled>` and `<name>`.

   ### `modify-owd`
   - The change is to `force-app/main/default/objects/<Object>/<Object>.object-meta.xml`, NOT to a separate sharing-rules file. The element is `<sharingModel>` (and `<externalSharingModel>` for external OWD).
   - Valid values: `Private`, `Read`, `ReadSelect`, `ReadWrite`, `ReadWriteTransfer`, `FullAccess`, `ControlledByParent`.
   - For Activity objects (`Task`, `Event`) the OWD field is `<sharingModel>` but only certain values are valid (`Private`, `ControlledByParent`).
   - **DO NOT touch any other element in the object metadata file.** The blast radius of an OWD change is enough; collateral changes to `<label>`, `<pluralLabel>`, etc., make the diff harder to review.

   ### `create-sharing-rule` / `modify-sharing-rule` / `delete-sharing-rule`
   - Sharing rules live in `force-app/main/default/sharingRules/<Object>.sharingRules-meta.xml` (one file per object, multiple rules per file).
   - Each rule is either `<sharingCriteriaRules>` (criteria-based) or `<sharingOwnerRules>` (ownership-based).
   - Required elements per rule: `<fullName>`, `<accessLevel>` (`Read` or `Edit`), `<description>` (optional but recommended for documentation), `<label>`, `<sharedTo>` (the recipient — public group / role / queue), and either `<criteriaItems>` (for criteria-based) or `<sharedFrom>` (for ownership-based).
   - `<sharedTo>` types: `<group>`, `<role>`, `<roleAndSubordinates>`, `<roleAndSubordinatesInternal>`, `<allInternalUsers>`, `<allCustomerPortalUsers>`.
   - For delete: remove the entire `<sharingCriteriaRules>` or `<sharingOwnerRules>` block; if it was the last rule on the object, leave the wrapping `<SharingRules>` element with empty content (or delete the whole file if `dev_model == source_tracked`).

   ### `create-restriction-rule` / `modify-restriction-rule` / `delete-restriction-rule`
   - Restriction rules live in `force-app/main/default/objects/<Object>/restrictionRules/<RuleName>.restrictionRule-meta.xml` (one file per rule).
   - Required elements: `<active>`, `<description>`, `<masterLabel>`, `<recordFilter>` (the SOQL-like predicate defining what records to restrict), `<userCriteria>` (which users the restriction applies to — typically a permission set or formula).
   - For delete: remove the file.

4. **Adhere to the patterns in scope.** Specifically:
   - Maintain element sort order in profile / PS XMLs (mentioned above).
   - For sharing rules referencing a Public Group / Role / Queue, verify the recipient exists in `force-app/main/default/{groups,roles}/`. If the plan flagged a dangling recipient, do NOT proceed silently — record a deviation in the plan and stop.
   - If a Custom Permission grant is added to a profile/PS, check whether the corresponding `force-app/main/default/customPermissions/<name>.customPermission-meta.xml` exists. If not, the deploy will fail. Either the engineer needs to also create the Custom Permission (in which case the plan should have called this out) OR this is a mistake.

5. **If you encounter a situation the plan didn't anticipate**, add the variation to the plan first (append a new section to `$ARTIFACTS_DIR/plan.md`), THEN implement. Do not silently deviate.

6. **Do not modify unrelated files.** If you find an issue elsewhere (a different profile with a similar gap, an orphaned PS that the plan didn't mention), record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate ticket — don't fix it here.

7. **Stage the changes for review.** Run `git status` and capture the file list. Do NOT `git add` or `git commit` — the engineer commits after the workflow completes successfully.

8. **Write an implementation summary** to `$ARTIFACTS_DIR/implementation.md` describing:
   - Files actually changed (vs. what the plan predicted)
   - Any plan deviations and their justification
   - Pre-deploy concerns the engineer should be aware of (dangling references, orphan candidates, alphabetical-sort discipline)

## Output

Emit a structured JSON summary on stdout:

```json
{
  "files_changed_actual": [
    {"path": "force-app/main/default/permissionsets/Custom_Sales_Manager_PS.permissionset-meta.xml", "operation": "modify", "lines_added": 6, "lines_removed": 6},
    {"path": "force-app/main/default/objects/Renewal__c/Renewal__c.object-meta.xml", "operation": "modify", "lines_added": 1, "lines_removed": 1}
  ],
  "plan_deviations": [],
  "follow_ups_recorded": false,
  "implementation_artifact": "$ARTIFACTS_DIR/implementation.md"
}
```

## Why this node uses `opus[1m]`

Per ADR-0020 §9, the typical run uses opus[1m] for this node only when the changed artifact is a large profile XML (some stock-customized profiles are 5K+ lines) or a complex multi-PSG composition. Sonnet handles the common case fine; opus[1m] is reserved for the large-context cases.
