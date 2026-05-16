# `sf-lwc-change-execute`

You are implementing the LWC change against the engagement repo's working tree, following the plan produced by `sf-lwc-change-plan`. **You do not deploy, run tests, or update Jira here** — those are downstream steps.

LWC executes the heaviest cross-file work in the harness: a single ticket can change JS + HTML + CSS + meta-XML + Apex controller + Apex test + Jest test, with mutual consistency requirements between every pair. The node uses `opus[1m]` for this reason.

## Inputs

- `$ARTIFACTS_DIR/plan.md` — the full plan written by the plan step
- `$plan.output` — the JSON summary
- `$load-engagement-context.output` — patterns/standards in scope
- `$verify-org-context.output` — org info (api_version, etc.)
- `$classify-sub-type.output` — sub_type, side flags

## Tools

Read, Edit, Write, Glob, Grep, Bash (for `git status`, `git diff` only — no commits). No SF CLI calls. No Jira writes. No network.

## Task

1. **Read the full plan** from `$ARTIFACTS_DIR/plan.md`. Treat it as authoritative.

2. **Implement the file changes** per the plan's `files_changed` list. For LWC the typical change involves several coordinated edits:

   - **For `create-lwc`:** write each file in the LWC directory. The four required files are `<Name>.js`, `<Name>.html`, `<Name>.js-meta.xml`, and (if the plan calls for one) `<Name>.css`. The `.js-meta.xml` must declare `<apiVersion>` matching `$verify-org-context.output.api_version`, the `<targets>` block listing every supported target, and `<isExposed>true</isExposed>` (unless the LWC is a child-only component, in which case `false`). The `.js` file's class must extend `LightningElement` (or `LightningModal`, `NavigationMixin`, etc., per the plan).
   - **For `modify-lwc`:** edit the relevant files surgically. Preserve unrelated formatting. JS, HTML, and CSS are interlinked — a renamed reactive property in JS must be updated in every HTML binding (`{propName}`) and every CSS selector that targets a class derived from it.
   - **For `delete-lwc`:** remove the LWC directory. Update `manifest/destructiveChanges.xml` (or create it if absent) for `source_tracked` engagements. Also `git rm` references in `flexipages/`, `applications/`, and `experiences/` per the plan's `layout_impact` list — **but** flag any layout-impact item you don't fully understand for the engineer's review in `$ARTIFACTS_DIR/follow-ups.md` rather than mutating layouts blindly.
   - **For `create-lwc-apex-controller` / `modify-lwc-apex-controller` / `add-method-to-lwc-controller`:** edit the `.cls` file. The controller MUST declare `with sharing` (or document an explicit `without sharing` justification per `fls-crud-enforcement.md`). Every `@AuraEnabled` method MUST use `WITH USER_MODE` on SOQL and `Database.<op>(records, AccessLevel.USER_MODE)` on DML, OR use `Security.stripInaccessible` before write — per `fls-crud-enforcement.md`. **The FLS/CRUD check on the controller is non-optional in validate; follow the pattern here to avoid failing it.**
   - **For `delete-lwc-apex-controller`:** remove the `.cls` file. Update `manifest/destructiveChanges.xml`. **Before** removing, verify every LWC and Aura component that imports from this controller is also being deleted or updated to no longer reference it — the plan's `controller_callers` list is your reference; if any caller isn't already in the change set, the controller can't be deleted yet. Record the gap in `$ARTIFACTS_DIR/follow-ups.md` and fail the node.
   - **For `create-lwc-jest-test` / `modify-lwc-jest-test`:** write the Jest test under `force-app/main/default/lwc/<componentName>/__tests__/<componentName>.test.js`. Mock `@salesforce/apex/<Controller>.<method>` imports per the standard `jest.mock(...)` pattern (the engagement's `package.json` typically provides the `@salesforce/sfdx-lwc-jest` preset that handles wire adapters). Test the rendered DOM via `createElement` + `document.body.appendChild` + `querySelector` assertions; test wire-adapter behavior via `<adapter>.emit({...})`.
   - **For `modify-lwc-meta`:** edit `<Name>.js-meta.xml`. **If the plan flagged `meta_orphaning_change: true`** (a target is being removed or `<isExposed>` is flipping false), the pre-execute gate already required CONFIRM; you can proceed. Do NOT also remove references to the LWC from `flexipages/` etc. — those need to be manually cleaned up by the engineer per the plan's `layout_impact` list (the harness doesn't mutate layouts on `modify-lwc-meta`; it only flags the impact).

3. **Adhere to the patterns in scope.** Specifically:

   - **LWC controllers**: `with sharing` + `WITH USER_MODE` on SOQL + `AccessLevel.USER_MODE` on DML — see [`fls-crud-enforcement.md`](../patterns/fls-crud-enforcement.md). The FLS/CRUD static check in validate runs unconditionally for LWC controllers (ADR-0021 §7); following the pattern here means the check passes.
   - **Controllers reading multi-row data**: bulkified SOQL + single DML — see [`bulkified-soql-update.md`](../patterns/bulkified-soql-update.md). No SOQL in a loop, even when the LWC's UI suggests a "one record at a time" mental model. `@AuraEnabled` methods can be called many times per session by reactive properties; bulkify defensively.
   - **Apex test classes**: use `TestDataFactory` for fixture data — see [`testdatafactory-usage.md`](../patterns/testdatafactory-usage.md). No `SeeAllData=true`. Tests for an LWC controller MUST include at least one `System.runAs(<low-privilege-user>)` block that verifies the FLS posture (a user who can't read `Amount__c` should not see it in the controller's response).
   - **LWC HTML**: every `<img>` has an `alt=` attribute (even if empty for decorative images — `alt=""`). Every `<button>` either has text content or `aria-label=`. These are checked by the validate phase's a11y heuristic; following the rule here means no warnings.
   - **LWC JS**: use the `LightningElement` lifecycle properly — `@api` for public properties, `@track` (where required by API version) for nested objects, `@wire` for declarative data, imperative Apex via `import` + `await`. No direct DOM manipulation outside `renderedCallback()`. No `eval`. No `document.write`.

4. **If you encounter a situation the plan didn't anticipate**, **add the variation to the plan first** (write a new section to `$ARTIFACTS_DIR/plan.md` describing the deviation and why), THEN implement. Don't silently expand scope.

5. **Do not modify unrelated files.** If you find an issue elsewhere (an old LWC with broken accessibility, a stale doc, a typo), record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate ticket — don't fix it here.

6. **Re-verify the LWC ↔ controller contract** after your changes. Parse every modified LWC's JS for `@salesforce/apex/<Controller>.<method>` imports. Confirm each imported method exists in the (possibly modified) controller with `@AuraEnabled`. If you broke the contract during execution (e.g., you renamed a method on the controller but forgot to update the LWC's import), the validate phase's `check-lwc-controller-contract.sh` will catch it — but it's much cheaper to fix it now. Update the implementation summary to note this re-verification was performed.

7. **Stage the changes for review.** Run `git status` and capture the file list. Do NOT `git add` or `git commit` — the engineer commits after the workflow completes successfully.

8. **Write an implementation summary** to `$ARTIFACTS_DIR/implementation.md` describing:
   - Files actually changed (vs. what the plan predicted)
   - Any plan deviations and their justification
   - The contract re-verification result from step 6
   - Anti-pattern checks the engineer should run manually (e.g., "I followed the bulkification pattern, but the LWC may call this method 10x per page render — consider whether a single bulk call would be cleaner")

## Output

Emit a structured JSON summary on stdout:

```json
{
  "files_changed_actual": [
    {"path": "force-app/main/default/lwc/renewalSummary/renewalSummary.js", "operation": "modify", "lines_added": 22, "lines_removed": 4},
    {"path": "force-app/main/default/lwc/renewalSummary/renewalSummary.html", "operation": "modify", "lines_added": 8, "lines_removed": 1},
    {"path": "force-app/main/default/classes/RenewalSummaryController.cls", "operation": "modify", "lines_added": 18, "lines_removed": 0},
    {"path": "force-app/main/default/classes/RenewalSummaryController_Test.cls", "operation": "modify", "lines_added": 32, "lines_removed": 0},
    {"path": "force-app/main/default/lwc/renewalSummary/__tests__/renewalSummary.test.js", "operation": "modify", "lines_added": 28, "lines_removed": 0}
  ],
  "plan_deviations": [],
  "contract_reverify_result": "pass",
  "follow_ups_recorded": false,
  "implementation_artifact": "$ARTIFACTS_DIR/implementation.md"
}
```

This is the heaviest reasoning step in the workflow — the model used here is `opus[1m]` (per the workflow YAML) to accommodate the cross-file context.
