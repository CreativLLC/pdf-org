# `sf-apex-change-plan`

You are producing the structured plan for an Apex change. The plan is what the in-workflow gate (when triggered) displays to the engineer, and what the execute step implements against. **No code changes happen here** — this step is plan-only.

## Inputs

- `$pull-jira-context.output` — the ticket
- `$classify-sub-type.output` — sub_type, scope, touches_soql_dml, etc.
- `$smoke-validate-claims.output` — accuracy of ticket claims
- `$verify-org-context.output` — org context
- `$load-engagement-context.output` — patterns/standards/object docs in scope

## Tools

File reads, Glob, Grep against the engagement repo. Specifically `force-app/main/default/classes/`, `force-app/main/default/triggers/`, and the loaded `docs/`. No file writes. No git operations. No SF CLI. No Jira writes.

## Task

1. **Re-read the ticket's acceptance criteria.** The plan must satisfy every AC, or explicitly flag which ones are out of scope.
2. **Map sub_type to plan template:**

   | sub_type | Plan must specify |
   |---|---|
   | `create-class` | New file path, public API (methods + visibility), test class path, fixture/factory approach |
   | `modify-class` | File path, methods touched, signature changes (if any), regression risk to callers |
   | `add-method-to-class` | File path, new method signature, where it inserts, test coverage approach |
   | `delete-class` | File path, caller-impact list (grep all references), the destructive-deploy manifest delta |
   | `create-trigger` | Trigger file path, handler class path, events handled, bulk pattern adherence |
   | `modify-trigger` | Trigger file path, events affected, bulk/governor impact, regression tests |
   | `create-test` | Test class path, methods, fixture data approach, classes under test |
   | `modify-test` | Test class path, methods touched, what behavior change is covered |
   | `rename-apex-symbol` | Old name, new name, full file list grep'd for callers, deploy/refactor ordering |

3. **Identify the file changes.** List every file the change will touch with full path and an annotation:
   - `add` — new file
   - `modify` — existing file changed
   - `delete` — file removed
   - `rename` — file moved/renamed
4. **Identify the test strategy.**
   - List the test classes that must be modified or created.
   - List existing test classes that grep-reference any class in (3) — they will run during validate.
   - If `$load-engagement-context.output.engagement.regression_suite` is non-empty, append those.
5. **Identify standards and patterns that apply.** For each pattern listed in `$load-engagement-context.output.patterns_in_scope`, state in one sentence how the change will adhere to it. If the change *can't* adhere to a pattern, name the exception and the justification.
6. **Identify documentation outputs.** Per ADR-0009 §8: always a changelog entry; object docs for trigger changes; no team-canon pattern changes (those need a separate harness-repo PR). List the exact file paths the document step will produce.
7. **Identify risk surface.** Note any of:
   - Public API changes (would break LWC/Aura/external integrations)
   - Trigger ordering changes (may interact with existing automation)
   - Governor-limit exposure (if the change adds DML or SOQL in a loop)
   - Concurrent-DML risk (if the change interacts with platform events / async)
   These don't block the workflow but they're displayed at the gate and embedded in the changelog entry.

## Output

Write the structured plan to `$ARTIFACTS_DIR/plan.md` as readable markdown. Also emit a JSON summary on stdout for the gate node to display:

```json
{
  "summary": "Add renewal_date field-aware logic to RenewalCalculator; covered by RenewalCalculator_Test new method test_renewalDate_isRespected.",
  "sub_type": "modify-class",
  "scope": "small",
  "files_changed": [
    {"path": "force-app/main/default/classes/RenewalCalculator.cls", "operation": "modify"},
    {"path": "force-app/main/default/classes/RenewalCalculator_Test.cls", "operation": "modify"}
  ],
  "test_classes": ["RenewalCalculator_Test"],
  "regression_tests_added": ["AccountTriggerHandler_Test"],
  "patterns_followed": ["fls-crud-enforcement", "testdatafactory-usage"],
  "doc_outputs": [
    "docs/changelog/2026-05/ACME-101.md"
  ],
  "risks": [
    "RenewalCalculator.calculateNext() is called by 2 Flows; method signature is unchanged so callers are safe."
  ],
  "out_of_scope_acceptance_criteria": []
}
```

The full plan goes to the artifact file; the JSON is the structured summary that the gate node and the execute node read.
