# `sf-flow-change-plan`

You are producing the structured plan for a Flow change. The plan is what the in-workflow gate (when triggered) displays to the engineer, and what the execute step implements against. **No XML changes happen here** — this step is plan-only.

## Inputs

- `$pull-jira-context.output` — the ticket
- `$classify-sub-type.output` — sub_type, scope, `currently_active`, `touches_dml_elements`, `touches_invocable_apex`, `touches_subflow_relationships`, `affected_flow_names`
- `$smoke-validate-claims.output` — claim accuracy + caller-impact (for destructive sub-types, written to `$ARTIFACTS_DIR/caller-impact.txt`)
- `$verify-org-context.output` — org context (api_version, etc.)
- `$load-engagement-context.output` — patterns/standards/object docs in scope

## Tools

File reads, Glob, Grep against the engagement repo. Specifically `force-app/main/default/flows/`, `force-app/main/default/classes/`, `force-app/main/default/objects/`, and the loaded `docs/`. No file writes outside `$ARTIFACTS_DIR/`. No git operations. No SF CLI. No Jira writes.

## Task

1. **Re-read the ticket's acceptance criteria.** The plan must satisfy every AC, or explicitly flag which ones are out of scope.
2. **Map sub_type to plan template:**

   | sub_type | Plan must specify |
   |---|---|
   | `create-record-triggered-flow` | New `.flow-meta.xml` path, `<processType>`, triggering object, `<recordTriggerType>` (Create / Update / etc.), entry-criteria filters, before-save vs after-save, listed `<actionCalls>` / `<recordUpdates>` / etc., test approach, ship-active vs ship-draft |
   | `create-scheduled-flow` | New flow path, `<schedule>` element (start time, frequency), the query for records to process, downstream actions, test approach |
   | `create-screen-flow` | New flow path, screen sequence, fields exposed per screen, navigation logic, the controller invocation if any, audience/permission considerations |
   | `create-autolaunched-flow` | New flow path, callers (Apex method names that will invoke it), input/output variables, test approach |
   | `create-subflow` | New flow path, parent Flow(s) that will invoke it, input/output variable contract, test approach |
   | `modify-flow` | Flow file path, elements touched (decisions / assignments / record-updates / etc.), DML elements added/removed/modified, regression risk to existing callers, ship-active vs ship-as-currently-is |
   | `activate-flow` | Flow file path, current `<status>`, target `<status>Active</status>`, the static reference check expectation (any references to verify before activation) |
   | `deactivate-flow` | Flow file path, current `<status>`, target `<status>Obsolete</status>`, caller-impact summary (read from `$ARTIFACTS_DIR/caller-impact.txt`), the destructive-deploy manifest delta if applicable |
   | `delete-flow` | Flow file path, caller-impact, the destructive-deploy manifest delta, references that must be cleaned up in callers (a subsequent ticket or in-scope here) |

3. **Identify the file changes.** List every file the change will touch with full path and an annotation:
   - `add` — new `.flow-meta.xml` file
   - `modify` — existing `.flow-meta.xml` changed
   - `delete` — `.flow-meta.xml` removed
   - `modify (caller)` — an Apex class or other Flow that references the affected Flow and needs updating (e.g., when deleting a Flow, the caller has to be updated too)
4. **Identify the references the Flow will hold** (so validate's static reference check can verify them):
   - **Invocable Apex** — every `<actionCalls type="apex">` `<apexClass>`. For each, name the class and its expected `@InvocableMethod` signature.
   - **Subflows** — every `<subflows>` `<flowName>`. For each, name the subflow.
   - **Objects touched** — every `<recordUpdates>` / `<recordCreates>` / `<recordDeletes>` `<object>`, and the fields it sets/filters on.
   - **Custom fields** — every field referenced in `<inputAssignments>` / `<filters>` / `<outputAssignments>` that lives on a custom object.
5. **Identify the test strategy.**
   - List the test classes that must be modified or created (Apex tests that exercise the Flow via `Test.startFlow()` or by triggering records).
   - List existing test classes that grep-reference the affected Flow names — they will run during validate.
   - If `engagement.yaml.tests.flows.<FlowName>` is defined for any affected Flow, include the mapped tests explicitly.
   - If `$load-engagement-context.output.engagement.regression_suite` is non-empty, append those.
   - For `create-screen-flow` with no automated coverage, explicitly note "no automated test coverage" as the plan position — manual test plan is acceptable for screen flows.
6. **Identify standards and patterns that apply.** For each pattern listed in `$load-engagement-context.output.patterns_in_scope` that's relevant to Flows (`bulkified-soql-update.md` is the most common — bulkification applies to Flow `<recordUpdates>` no less than to Apex DML), state in one sentence how the Flow will adhere to it.
7. **Identify documentation outputs.** Per ADR-0019 §9: always `docs/flows/<Flow_API_Name>.md`; every `docs/objects/<Object>.md` whose object is touched; parent/child flow docs when subflow relationships changed. List the exact file paths the document step will produce.
8. **Identify risk surface.** Note any of:
   - **Activation risk** — the Flow ships Active and is unversioned (no prior version to fall back to); a runtime failure on the first record manifests as a Flow error visible to users.
   - **Caller impact** — for `deactivate-flow` / `delete-flow`, summarize the count and category of callers (read `$ARTIFACTS_DIR/caller-impact.txt`).
   - **Governor-limit exposure** — `<recordUpdates>` inside a loop element is the Flow equivalent of DML in a loop; flag it as a risk for the engineer to address in execute.
   - **Subflow ordering** — modifying a subflow whose contract changed affects every parent; identify the parents in scope.

## Output

Write the structured plan to `$ARTIFACTS_DIR/plan.md` as readable markdown. Also emit a JSON summary on stdout for the gate node to display:

```json
{
  "summary": "Add Renewal_Auto_Create record-triggered Flow on Renewal__c (after-save), invokes RenewalCalculator.calculateNext as <actionCalls>; covered by Renewal_Auto_Create_Test new method test_autoCreate_OnInsert.",
  "sub_type": "create-record-triggered-flow",
  "scope": "small",
  "ship_active": true,
  "files_changed": [
    {"path": "force-app/main/default/flows/Renewal_Auto_Create.flow-meta.xml", "operation": "add"},
    {"path": "force-app/main/default/classes/Renewal_Auto_Create_Test.cls", "operation": "add"}
  ],
  "references": {
    "invocable_apex": ["RenewalCalculator"],
    "subflows": [],
    "objects_touched": ["Renewal__c", "Account"],
    "custom_fields": ["Renewal__c.Next_Date__c", "Renewal__c.Stage__c"]
  },
  "test_classes": ["Renewal_Auto_Create_Test"],
  "regression_tests_added": ["AccountTriggerHandler_Test"],
  "patterns_followed": ["bulkified-soql-update"],
  "doc_outputs": [
    "docs/flows/Renewal_Auto_Create.md",
    "docs/objects/Renewal__c.md",
    "docs/objects/Account.md",
    "docs/index.md"
  ],
  "risks": [
    "Flow ships Active on first deploy; first-record failure would surface as a Flow error.",
    "Flow invokes RenewalCalculator.calculateNext which is also called by 1 trigger — caller surface is shared but additive."
  ],
  "caller_impact_summary": null,
  "out_of_scope_acceptance_criteria": []
}
```

For destructive sub-types (`deactivate-flow`, `delete-flow`), `caller_impact_summary` is non-null and contains:

```json
"caller_impact_summary": {
  "total_callers": 5,
  "by_category": {"apex_classes": 3, "other_flows": 2, "test_classes": 1},
  "artifact": "$ARTIFACTS_DIR/caller-impact.txt"
}
```

The full plan goes to the artifact file; the JSON is the structured summary that the gate node and the execute node read.
