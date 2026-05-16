# `sf-metadata-change-plan`

You are producing the structured plan for a Salesforce metadata change. The plan is what the in-workflow pre-execute gate (when triggered) displays to the engineer, and what the execute step implements against. **No metadata changes happen here** — this step is plan-only.

## Inputs

- `$pull-jira-context.output` — the ticket
- `$classify-sub-type.output` — sub_type, scope, side flags (`touches_fls`, `is_destructive_modify_field`, `affects_picklist_data`)
- `$smoke-validate-claims.output` — accuracy of ticket claims, `affects_existing_records` flag
- `$verify-org-context.output` — org context (api_version, target_org_alias, etc.)
- `$load-engagement-context.output` — patterns/standards/object docs in scope

## Tools

File reads, Glob, Grep against the engagement repo. Specifically `force-app/main/default/objects/`, `force-app/main/default/classes/`, `force-app/main/default/triggers/`, `force-app/main/default/flows/`, `force-app/main/default/lwc/`, and the loaded `docs/`. No file writes. No git operations. No SF CLI. No Jira writes.

## Task

1. **Re-read the ticket's acceptance criteria.** The plan must satisfy every AC, or explicitly flag which ones are out of scope.

2. **Map sub_type to plan template:**

   | sub_type | Plan must specify |
   |---|---|
   | `create-custom-object` | New object API name + label + plural label, sharing model, fields to create as part of this ticket (or "fields added in follow-up"), record types if any, plan-level FLS posture (which profiles read/edit) |
   | `modify-custom-object` | File path, fields of object metadata changed (label, sharing model, history tracking, etc.), regression risk to referencing Apex/Flows |
   | `create-field` | Object, field API name, type, length/precision, required, default, picklist values (if applicable), proposed FLS posture per profile/PS |
   | `modify-field` | Object, field API name, what's changing (type / length / required / default / picklist values), data-coercion concerns, downstream code/Flow references |
   | `delete-field` | Object, field API name, full reference scan (classes/triggers/flows/lwc/aura), destructive-deploy manifest delta |
   | `create-validation-rule` | Object, rule API name, formula, error message location, active state |
   | `modify-validation-rule` | Object, rule API name, what's changing in formula or active state |
   | `delete-validation-rule` | Object, rule API name, references in classes/flows/lwc that handle the rule's error |
   | `create-record-type` | Object, record type API name, label, picklist filters, layout assignment |
   | `modify-record-type` | Object, record type API name, what's changing |
   | `create-page-layout` | Object, layout name, field/section structure |
   | `modify-page-layout` | Object, layout name, fields/sections added or removed |
   | `create-picklist-value` | Object, field, new value, default? Active? |
   | `delete-picklist-value` | Object, field, value being removed, references in classes/flows/lwc that hardcode the value, data-strand risk |

3. **Identify the file changes.** List every file the change will touch with full path and an annotation:
   - `add` — new metadata XML
   - `modify` — existing metadata XML changed
   - `delete` — metadata removed (the execute step will also update `manifest/destructiveChanges.xml`)
   - For `modify-field` rename: both `modify` (the renamed file) and a `delete` entry for the old name in `manifest/destructiveChanges.xml`

4. **Run a reference-impact preview.** For any sub_type in `{delete-field, delete-validation-rule, delete-picklist-value}` OR any `modify-field` that renames the field, grep the engagement repo and list every match:
   ```
   grep -rln "<FieldAPIName>" force-app/main/default/classes/ force-app/main/default/triggers/ force-app/main/default/flows/ force-app/main/default/lwc/ force-app/main/default/aura/ 2>/dev/null
   ```
   Include the file paths in the plan output. The validate step will run the authoritative grep; this is the preview the gate displays.

5. **Identify FLS posture (when `create-field` or `touches_fls == "true"`).** State, per profile or permission set already documented in `docs/security/`:
   - Which profiles/PSs should READ this field, and why
   - Which profiles/PSs should EDIT this field, and why
   - Whether the field is sensitive (PII, financial) and whether masking applies
   - Whether the existing `docs/security/profiles/*.md` files describe the relevant profiles. If a profile is mentioned in the plan but has no doc, flag it as a gap.
   
   The actual profile/PS XML changes happen in a separate `sf-permission-change` run. The plan only **declares** the posture; the document step records it in `docs/objects/<Object>.md` and notes the security follow-up.

6. **Identify standards and patterns that apply.** For each pattern in `$load-engagement-context.output.patterns_in_scope`, state in one sentence how the plan adheres to it. Specifically [`fls-crud-enforcement.md`](../patterns/fls-crud-enforcement.md) applies to any `create-field` (the proposed FLS posture must be consistent with the pattern's principles — explicit, narrow, with rationale).

7. **Identify documentation outputs.** Per ADR-0018 §8, every metadata change updates the object doc; some also update feature docs and security docs. List the exact file paths the document step will produce.

8. **Identify risk surface.** Note any of:
   - **Existing-data risk:** field becomes required, picklist value removed, type change with non-coercing values (Text → Number on a populated field)
   - **Reference breakage:** classes/triggers/flows/lwc reference the affected field/rule
   - **FLS-strand risk:** new field is read or written by existing Apex without a corresponding FLS grant in any profile or permission set documented
   - **Sharing-model change:** object's OWD changing (Public → Private, etc.) — affects every user's record visibility
   - **Cross-family followups:** the change implies follow-up work in `sf-apex-change` (populate the new field on insert) or `sf-permission-change` (grant FLS) — note these for the orchestrator or the engineer
   
   These don't block the workflow but they're displayed at the gate and embedded in the documentation updates.

## Output

Write the structured plan to `$ARTIFACTS_DIR/plan.md` as readable markdown. Also emit a JSON summary on stdout for the gate node to display:

```json
{
  "summary": "Add Revenue_Tier__c picklist field to Account. Values: Bronze, Silver, Gold, Platinum. Read for Sales, Read+Edit for Sales Manager.",
  "sub_type": "create-field",
  "scope": "small",
  "files_changed": [
    {"path": "force-app/main/default/objects/Account/fields/Revenue_Tier__c.field-meta.xml", "operation": "add"}
  ],
  "reference_impact_preview": {
    "affected_artifacts": [],
    "scan_scope": ["classes", "triggers", "flows", "lwc", "aura"]
  },
  "fls_posture": {
    "field": "Account.Revenue_Tier__c",
    "read": ["Sales", "Sales Manager", "System Administrator"],
    "edit": ["Sales Manager", "System Administrator"],
    "sensitive": false,
    "rationale": "Tier is shown on Account detail pages for all sales personas; only managers can adjust it to reflect contract negotiation outcomes."
  },
  "patterns_followed": ["fls-crud-enforcement"],
  "doc_outputs": [
    "docs/objects/Account.md",
    "docs/security/profiles/Sales.md",
    "docs/security/profiles/Sales_Manager.md",
    "docs/index.md"
  ],
  "risks": [
    "Revenue_Tier__c is referenced by zero existing classes/flows; safe to add.",
    "FLS posture must be granted by a follow-up sf-permission-change run before the field is usable in the UI."
  ],
  "cross_family_followups": [
    "sf-permission-change: grant Read for Sales/Sales Manager, Edit for Sales Manager."
  ],
  "out_of_scope_acceptance_criteria": []
}
```

The full plan goes to the artifact file; the JSON is the structured summary that the gate node and the execute node read.
