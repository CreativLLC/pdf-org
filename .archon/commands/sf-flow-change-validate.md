# `sf-flow-change-validate`

You are orchestrating the validation gates for the Flow change executed in the previous step. This command does NOT itself deploy, activate, or run tests — it calls the supporting scripts, runs the activation verification, and aggregates results. The scripts are the source of truth for what passes; this command rolls them up.

## Inputs

- `$execute.output` — files actually changed, `status_changes`, fault-path coverage
- `$classify-sub-type.output` — `sub_type`, `currently_active`, `touches_invocable_apex`, `affected_flow_names`
- `$load-engagement-context.output` — `coverage_threshold`, `regression_suite`, `tests.flows` mapping (per-flow explicit tests)
- `$verify-org-context.output` — `target_org_alias`, `is_scratch_org`, `scratch_org_def_path`

## Tools

Bash + SF CLI. The supporting scripts live at `.archon/scripts/`:

- `deploy-to-scratch.sh` — creates a scratch org from `scratch_org_def_path` (if not already running for this engagement) and deploys the changed `force-app/main/default/` files. Returns 0 on success.
- `check-flow-references.sh` — static check against each changed `.flow-meta.xml`: extracts `<actionCalls type="apex"><apexClass>`, `<subflows><flowName>`, `<recordUpdates><object>` / `<recordCreates><object>` / `<recordDeletes><object>`, every field referenced in `<inputAssignments>` / `<filters>` / `<outputAssignments>`. Verifies each exists in the local `force-app/`. Returns 0 if all references resolve; 1 if any are missing. *(New for this family — see ADR-0019 §4.)*
- `run-apex-tests.sh` — runs the test set (per-flow explicit mapping + grep-referencing tests + engagement regression_suite) against the scratch org. Returns 0 only if every test passes AND coverage of any incidentally-touched Apex classes meets `coverage_threshold`.

Plus direct `sf data query` calls for the activation verification (no script — small enough to inline).

## Task

Run in order. Capture each script's exit code and the structured output it writes to `$ARTIFACTS_DIR/<script-name>.json`. After all run, aggregate.

1. **Always run `deploy-to-scratch.sh`** with the file list from `$execute.output.files_changed_actual`. If deploy fails, the workflow can't continue — emit `overall_result: fail` and stop. The scratch org's `target_org_alias` is exported for the subsequent steps via `$ARTIFACTS_DIR/deploy-to-scratch.json:scratch_org_alias`.

2. **Verify activation state via `FlowDefinitionView` query** — only when the sub_type changes activation state.

   Sub-types that require activation verification:
   - `create-*-flow` where `$execute.output.status_changes` shows `to: "Active"`
   - `activate-flow`
   - `deactivate-flow`

   For each Flow in `$classify-sub-type.output.affected_flow_names`:
   ```bash
   sf data query \
     --target-org "$SCRATCH_ORG_ALIAS" \
     --query "SELECT ApiName, Status, VersionNumber FROM FlowDefinitionView WHERE ApiName = '<FlowName>'" \
     --json
   ```

   Verify the returned `Status` matches the intended `to` from `$execute.output.status_changes`:
   - Intended `Active` → returned `Active` → `activation_result: pass`
   - Intended `Obsolete` → returned `Obsolete` → `activation_result: pass`
   - Mismatch (Salesforce deployed structurally but didn't flip status as expected) → `activation_result: fail` with `activation_detail` describing the mismatch.

   For sub-types that don't change `<status>` (`modify-flow` of an already-Active Flow when no status field changed, `create-subflow` shipped as Draft, etc.), skip this step and set `activation_result: skipped`.

3. **Always run `check-flow-references.sh`** with the file list from `$execute.output.files_changed_actual`. Capture pass/fail and the structured `missing_references` list:
   ```json
   {
     "missing_invocable_apex": ["RenewalCalculator"],
     "missing_subflows": [],
     "missing_objects": [],
     "missing_fields": ["Renewal__c.NonExistent_Field__c"]
   }
   ```

   Each category maps to a distinct severity at the post-validate gate (per ADR-0019 §8 / the gate prompt): missing invocable Apex or missing custom object is most serious; missing field is often a managed-package whitelist gap and can be overridden.

4. **Always run `run-apex-tests.sh`** with the test set:
   ```
   test_set := { test classes that grep-match any name in $classify-sub-type.output.affected_flow_names }
            ∪ { engagement.yaml.tests.flows.<FlowName> for each affected Flow, if defined }
            ∪ { test classes also modified this run }
            ∪ engagement.yaml.tests.regression_suite (if defined)
   ```

   If `test_set` is empty AND `$classify-sub-type.output.sub_type` != `create-screen-flow`, emit `tests_result: warning` with `tests_detail: "no tests selected to exercise the changed Flow"`. Engineer sees this at the post-validate gate.

   If `test_set` is empty AND `$classify-sub-type.output.sub_type == 'create-screen-flow'`, emit `tests_result: skipped` with no warning (screen flows often genuinely lack automated coverage per ADR-0019 §7).

   Otherwise the script enforces test results and any coverage gate on incidentally-touched Apex classes and returns non-zero if any test fails.

5. **Compute fault-path coverage.** For each `.flow-meta.xml` in `$execute.output.files_changed_actual` (operation `add` or `modify`), grep for `<actionCalls>` elements. For each, check whether a `<faultConnector>` is present anywhere in the element OR an entry exists in `$execute.output.fault_paths` with `fault_covered: false` AND a justification in `$ARTIFACTS_DIR/implementation.md`.

   - All `<actionCalls>` covered by fault paths or justified → `fault_paths_result: pass`
   - One or more `<actionCalls>` lacks a fault path AND no justification → `fault_paths_result: warning` (NOT `fail` — this is informational; engineer decides at post-validate gate per ADR-0019 §8)
   - No `<actionCalls>` in any changed Flow → `fault_paths_result: skipped`

6. **Aggregate.** `overall_result` is:
   - `pass` only if: deploy succeeded, `activation_result` is `pass` or `skipped`, `references_result` is `pass` OR the post-validate gate approves the override (check `$gate-post-validate.output.proceed == 'true'` from the workflow state — but at this point in the run, the post-validate gate hasn't fired yet; this check applies on re-run), `tests_result` is `pass` or `skipped`, and `fault_paths_result` is `pass`, `skipped`, or `warning`.
   - `fail` otherwise.

   `fault_paths_result: warning` does NOT fail `overall_result` on its own — it triggers the post-validate gate, which then drives the workflow's continuation decision.

## Output

```json
{
  "deploy_result": "pass",
  "deploy_artifact": "$ARTIFACTS_DIR/deploy-to-scratch.json",
  "activation_result": "pass",
  "activation_detail": "Renewal_Auto_Create: Status=Active VersionNumber=1",
  "references_result": "pass",
  "references_artifact": "$ARTIFACTS_DIR/check-flow-references.json",
  "missing_references": {
    "missing_invocable_apex": [],
    "missing_subflows": [],
    "missing_objects": [],
    "missing_fields": []
  },
  "tests_result": "pass",
  "tests_artifact": "$ARTIFACTS_DIR/run-apex-tests.json",
  "fault_paths_result": "pass",
  "fault_paths_detail": "1 action call covered",
  "overall_result": "pass",
  "duration_seconds": 195
}
```

On any non-pass result, the JSON also includes a `failure_reason` array of strings (one per failing check) so the post-validate gate can display them.
