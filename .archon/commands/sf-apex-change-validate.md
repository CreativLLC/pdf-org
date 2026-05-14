# `sf-apex-change-validate`

You are orchestrating the validation gates for the change executed in the previous step. This command does NOT itself deploy or test — it calls the four supporting scripts and aggregates their results. The scripts are the source of truth for what passes; this command rolls them up.

## Inputs

- `$execute.output` — list of files actually changed
- `$classify-sub-type.output` — `sub_type`, `touches_soql_dml`
- `$load-engagement-context.output` — `coverage_threshold`, `regression_suite`
- `$verify-org-context.output` — `target_org_alias`, `is_scratch_org`, `scratch_org_def_path`

## Tools

Bash only. The four supporting scripts live at `.archon/scripts/`:

- `deploy-to-scratch.sh` — creates a scratch org from `scratch_org_def_path` (if not already running for this engagement) and deploys the changed `force-app/main/default/` files. Returns 0 on success.
- `run-apex-tests.sh` — runs the test set (modified test classes + grep-referencing tests + engagement regression_suite) against the scratch org. Returns 0 only if every test passes AND every modified non-test class meets `coverage_threshold`.
- `check-destructive-changes.sh` — static AST-aware diff over the working tree's Apex files. Returns 0 if no destructive change; 1 if destructive changes detected (with a structured issue list).
- `check-fls-crud.sh` — regex-based static check for `WITH USER_MODE` on SOQL and `Security.stripInaccessible` on DML in modified classes. Returns 0 if pass; 1 if issues found.

## Task

Run the scripts in order. Capture each script's exit code and the structured output it writes to `$ARTIFACTS_DIR/<script-name>.json`. After all four run, aggregate.

1. **Always run `deploy-to-scratch.sh`** with the org alias and the file list from `$execute.output`. If deploy fails, the workflow can't continue — emit `overall_result: fail` and stop.
2. **Run `run-apex-tests.sh`** with the org alias, the test class list, and `coverage_threshold`. The script handles test selection (modified + grep-referencing + regression). Capture pass/fail and per-class coverage. The script enforces the coverage gate internally and returns non-zero if any modified non-test class is below threshold.
3. **Run `check-destructive-changes.sh`** with the file list. Static check, no org dependency — runs in parallel with deploy/tests conceptually but for simplicity run it after tests here (cheap).
4. **Run `check-fls-crud.sh`** with the file list, **only if** `$classify-sub-type.output.touches_soql_dml == "true"`. If the flag is false, skip this check and record `fls_crud_result: skipped`.
5. **Aggregate.** `overall_result` is:
   - `pass` only if: deploy succeeded, tests passed (including coverage), destructive_result is `pass` OR the pre-execute gate approved a destructive change (check `$gate-pre-execute.output.proceed == 'true'` from the workflow state), and FLS/CRUD is `pass` or `skipped`.
   - `fail` otherwise.

A destructive change that was approved at the pre-execute gate is still legitimately destructive; `destructive_result` stays `fail` but `overall_result` can still be `pass` because the human already confirmed it. The post-validate gate doesn't re-fire in that case.

## Output

```json
{
  "deploy_result": "pass",
  "deploy_artifact": "$ARTIFACTS_DIR/deploy-to-scratch.json",
  "tests_result": "pass",
  "tests_artifact": "$ARTIFACTS_DIR/run-apex-tests.json",
  "coverage_threshold": 75,
  "per_class_coverage": [
    {"class": "RenewalCalculator", "coverage": 87}
  ],
  "destructive_result": "pass",
  "destructive_artifact": "$ARTIFACTS_DIR/check-destructive-changes.json",
  "destructive_approved_at_pre_gate": false,
  "fls_crud_result": "pass",
  "fls_crud_artifact": "$ARTIFACTS_DIR/check-fls-crud.json",
  "overall_result": "pass",
  "duration_seconds": 252
}
```

On any non-pass result, the JSON also includes a `failure_reason` array of strings (one per failing check) so the post-validate gate can display them.
