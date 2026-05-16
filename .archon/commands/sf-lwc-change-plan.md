# `sf-lwc-change-plan`

You are producing the structured plan for an LWC change. The plan is what the in-workflow gate (when triggered) displays to the engineer, and what the execute step implements against. **No code changes happen here** — this step is plan-only.

LWC's defining characteristic for the planner: **file-surface area**. A single LWC routinely involves four to five files (`<Name>.js`, `<Name>.html`, optional `<Name>.css`, `<Name>.js-meta.xml`, optional `<Name>.svg`), plus a backing Apex controller, plus a Jest test, plus the Apex test for the controller. The plan must inventory every file the change will touch with operation type (add / modify / delete / rename).

## Inputs

- `$pull-jira-context.output` — the ticket
- `$classify-sub-type.output` — sub_type, scope, side flags (`breaks_controller_contract`, `meta_orphaning_change`, etc.)
- `$smoke-validate-claims.output` — accuracy of ticket claims
- `$verify-org-context.output` — org context (api_version)
- `$load-engagement-context.output` — patterns/standards/object docs in scope

## Tools

Read, Glob, Grep against the engagement repo. Specifically `force-app/main/default/lwc/`, `force-app/main/default/classes/`, and the loaded `docs/`. **No file writes.** No git operations. No SF CLI. No Jira writes.

## Task

1. **Re-read the ticket's acceptance criteria.** The plan must satisfy every AC, or explicitly flag which ones are out of scope.

2. **Identify the LWC(s) and controller(s) in scope.** From the ticket + classifier output, identify:
   - LWC component name(s) (the `lwc/<componentName>/` directory).
   - Apex controller name(s) (conventionally `<ComponentName>Controller.cls`, but check — engagements may use other conventions). Grep the LWC's `.js` file for `import <name> from '@salesforce/apex/<Controller>.<method>'` lines to discover the *actual* controller(s) it uses.
   - Existing Jest test path, if any: `force-app/main/default/lwc/<componentName>/__tests__/<componentName>.test.js`.

3. **Map sub_type to plan template:**

   | sub_type | Plan must specify |
   |---|---|
   | `create-lwc` | New `lwc/<Name>/` directory, files to create (`.js`, `.html`, optional `.css`, `.js-meta.xml`, optional `.svg`), `<target>` entries, exposed-to-App-Builder design properties, paired controller (new or existing), initial Jest test plan |
   | `modify-lwc` | LWC name, files modified, what behavior changes, controller methods used (verify all are present), regression risk to pages that embed the LWC |
   | `delete-lwc` | LWC name, **layout-impact list** (grep `flexipages/`, `aura/`, `applications/`, `experiences/` for references), destructive-deploy manifest delta |
   | `create-lwc-apex-controller` | Controller path, `@AuraEnabled` methods (signatures + return types), `with sharing` posture, FLS/CRUD approach, test class path |
   | `modify-lwc-apex-controller` | Controller path, methods touched, signature changes, **caller-impact list** (grep all LWCs and Aura components for `@salesforce/apex/<Controller>.<method>` imports), regression tests |
   | `add-method-to-lwc-controller` | Controller path, new method signature, FLS/CRUD approach, test coverage approach |
   | `delete-lwc-apex-controller` | Controller path, **caller-impact list** (every LWC / Aura / Flow / REST consumer of this controller), destructive-deploy manifest delta |
   | `create-lwc-jest-test` | Jest test path, scenarios covered, mock approach for `@salesforce/apex/*` imports |
   | `modify-lwc-jest-test` | Jest test path, scenarios added / removed / changed, what behavior change is covered |
   | `modify-lwc-meta` | Meta-XML path, fields changed (API version, `<target>` additions/removals, `<isExposed>`, design properties), **layout-impact list if any target removed or `<isExposed>` flipped false** |

4. **Verify the LWC ↔ controller contract.** For every LWC in scope (not just the one being modified — sibling LWCs that import the same controller are affected by controller changes too):
   - Parse the LWC's JS for `import <name> from '@salesforce/apex/<Controller>.<method>'` lines.
   - For each imported method, confirm it exists in the controller's `.cls` with the `@AuraEnabled` annotation.
   - If `sub_type == modify-lwc-apex-controller` and the planned change removes or renames a method, set `breaks_controller_contract: "true"` in the plan output AND list every LWC that imports the affected method.
   - If `sub_type == create-lwc` or `modify-lwc` and the LWC imports a method that doesn't exist (or isn't `@AuraEnabled`), the plan flags this as a blocking gap that execute must resolve.

5. **Verify meta-XML target / visibility changes.** For `modify-lwc-meta`:
   - Compare the planned `<target>` set to the current set. If any target is being removed, set `meta_orphaning_change: "true"` AND grep `force-app/main/default/flexipages/`, `force-app/main/default/applications/`, and `force-app/main/default/experiences/` for references to the LWC. List them as the **layout-impact list** in the plan.
   - If `<isExposed>` is flipping from `true` to `false`, same — flag as orphaning and list referencing layouts.

6. **Identify the file changes.** List every file the change will touch with full path and an annotation:
   - `add` — new file
   - `modify` — existing file changed
   - `delete` — file removed
   - `rename` — file moved/renamed

   For an LWC change, this routinely produces 4–8 entries (`.js`, `.html`, `.css`, `.js-meta.xml` per LWC, plus controller + controller-test + Jest-test).

7. **Identify the test strategy.**
   - **Apex side:** test classes that must be modified or created for the controller; existing test classes that grep-reference the controller; engagement `regression_suite` if non-empty.
   - **Jest side:** test path for the LWC. Check whether the engagement has Jest configured: `package.json` at the engagement root mentions `jest` (script or devDependency). Record `jest_configured: "true" | "false"` in the plan output. If false, the validate phase skips Jest gracefully; the plan still describes what the test *would* cover for the engineer's future Jest adoption.

8. **Identify standards and patterns that apply.** For each pattern in `$load-engagement-context.output.patterns_in_scope`, state in one sentence how the change adheres. Specifically:
   - LWC controllers MUST follow `fls-crud-enforcement.md` (the FLS/CRUD check on the controller is non-optional for LWC per ADR-0021 §7).
   - LWC controllers reading multi-row data MUST follow `bulkified-soql-update.md`.
   - LWC test classes MUST use `testdatafactory-usage.md` for fixture data.

9. **Identify documentation outputs.** Per ADR-0010 / ADR-0021 §9: object docs for any SObject the controller reads/writes; feature docs for the LWC's feature(s); optionally a `docs/components/<LWCName>.md` if the LWC is significant enough (your judgment — default to NO unless it's a major user-facing surface like a record-page hero component or a community landing page). List the exact file paths the document step will produce.

10. **Identify risk surface.** Note any of:
    - LWC ↔ controller contract changes (would break runtime)
    - Meta-XML target / visibility changes (would orphan from layouts)
    - Public API changes to the controller (would break sibling LWCs)
    - Page-render impact (LWC is on a high-traffic record page)
    - Cross-component dependencies (the LWC uses or is used by another LWC)
    - Governor-limit exposure in the controller (DML or SOQL in a loop)

    These don't block the workflow but they're displayed at the gate.

## Output

Write the structured plan to `$ARTIFACTS_DIR/plan.md` as readable markdown. Also emit a JSON summary on stdout for the gate node and execute node to read:

```json
{
  "summary": "Add Stripe invoice URL display to renewalSummary LWC; new @AuraEnabled getStripeInvoiceUrl on RenewalSummaryController; Jest test for the new state.",
  "sub_type": "modify-lwc",
  "scope": "small",
  "lwc_names": ["renewalSummary"],
  "controller_names": ["RenewalSummaryController"],
  "files_changed": [
    {"path": "force-app/main/default/lwc/renewalSummary/renewalSummary.js", "operation": "modify"},
    {"path": "force-app/main/default/lwc/renewalSummary/renewalSummary.html", "operation": "modify"},
    {"path": "force-app/main/default/classes/RenewalSummaryController.cls", "operation": "modify"},
    {"path": "force-app/main/default/classes/RenewalSummaryController_Test.cls", "operation": "modify"},
    {"path": "force-app/main/default/lwc/renewalSummary/__tests__/renewalSummary.test.js", "operation": "modify"}
  ],
  "apex_test_classes": ["RenewalSummaryController_Test"],
  "regression_tests_added": [],
  "jest_configured": "true",
  "jest_test_paths": ["force-app/main/default/lwc/renewalSummary/__tests__/renewalSummary.test.js"],
  "patterns_followed": ["fls-crud-enforcement", "testdatafactory-usage"],
  "breaks_controller_contract": "false",
  "meta_orphaning_change": "false",
  "controller_callers": [
    {"controller": "RenewalSummaryController", "method": "getRenewalSummary", "callers": ["lwc/renewalSummary", "lwc/renewalDashboard"]}
  ],
  "layout_impact": [],
  "doc_outputs": [
    "docs/objects/Renewal__c.md",
    "docs/features/renewal-pipeline.md"
  ],
  "risks": [
    "renewalSummary is on the Renewal__c record page Lightning App Builder layout; a deploy failure would break that page until rollback."
  ],
  "out_of_scope_acceptance_criteria": []
}
```

The full plan goes to the artifact file; the JSON is the structured summary that the pre-execute gate and the execute node read. The gate's `when:` expression references `$plan.output.breaks_controller_contract` and `$plan.output.meta_orphaning_change` — set those carefully based on the verification you performed in steps 4 and 5.
