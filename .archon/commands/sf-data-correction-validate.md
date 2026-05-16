# `sf-data-correction-validate`

You are orchestrating the **two-phase** validation per [ADR-0023](../decisions/0023-sf-data-correction-scope-and-gates.md) §3. Phase 1 runs the dry-run Apex (read-only) against the target org and reports what would be affected. Phase 2 runs the LIVE Apex — but ONLY after the engineer has reviewed the dry-run results at `gate-post-validate` and approved.

This command is the central safety mechanism of the `sf-data-correction` family. It is responsible for ensuring no DML happens against the target org until the engineer has seen exactly which records will be affected.

## Inputs

- `$execute.output` — `dry_run_artifact`, `live_artifact`, `sub_type`, `fls_posture_in_artifacts`
- `$plan.output` — `expected_reach`, `expected_distinct_accounts`, `expected_distinct_owners`, `expected_distinct_record_types`, `touches_restricted_object_per_engagement`, `fls_posture`
- `$classify-sub-type.output` — `sub_type`, `estimated_record_count`, `touches_restricted_object`
- `$verify-org-context.output` — `target_org_alias`, `is_scratch_org`
- `$gate-post-validate.output` — present only if the post-validate gate fired (after phase 1). Contains `proceed` and `confirmation_form`.
- `$load-engagement-context.output` — `salesforce.data_corrections.restricted_objects`

## Tools

Bash (for `sf apex run --file ...`, debug-log parsing, `AsyncApexJob` polling for batch sub-types). Read/Write for artifact JSON. No git operations.

## Task

### Phase 1 — Dry-run (always runs)

#### Step 1.1 — FLS posture re-check

Before running anything against the org, re-grep both Apex artifacts. Per ADR-0023 §3 and ADR-0009 §7:

- If `$plan.output.fls_posture == "USER_MODE"`:
  - `correction-dry-run.apex` must contain `WITH USER_MODE` in every SELECT.
  - `correction.apex` must contain `WITH USER_MODE` in every SELECT AND `AccessLevel.USER_MODE` in every DML call.
- If `$plan.output.fls_posture == "SYSTEM_MODE"`:
  - The plan's `system_mode_justification` must be non-null. (The execute step already checked; this is defense-in-depth.)
  - Otherwise no USER_MODE qualifier check.

If FLS posture check fails:

- Output `fls_posture_violation: "true"`.
- Set `overall_result: "fail"`.
- Do NOT run anything against the org.
- The post-validate gate will fire and offer ABORT-ONLY (no proceed path for FLS violations).
- Stop. Skip the rest of phase 1.

#### Step 1.2 — Run the dry-run Apex

For `data-update-anonymous-apex`, `data-delete-anonymous`, `data-insert` (anonymous form), `data-undelete`, `data-merge`:

```bash
sf apex run \
    --target-org "$TARGET_ORG_ALIAS" \
    --file "$ARTIFACTS_DIR/correction-dry-run.apex" \
    --json \
    > "$ARTIFACTS_DIR/dry-run-cli-output.json"
```

For `data-update-batch`, `data-delete-batch`: the dry-run is a class. First deploy the class to the target org as a temporary artifact (use `sf project deploy start --metadata <ClassName>DryRun --target-org "$TARGET_ORG_ALIAS"`), then invoke it via a small anonymous block:

```bash
sf apex run \
    --target-org "$TARGET_ORG_ALIAS" \
    --apex-code "Database.executeBatch(new <CorrectionName>DryRun(), 200);" \
    --json
```

Poll `AsyncApexJob` until status is `Completed`. Read the debug log via `sf apex log get` and parse for the `DRY_RUN_*` lines.

The dry-run is read-only — no DML runs. If the dry-run fails to compile or execute, capture the error and surface it via `dry_run_status: "failed"`. The post-validate gate fires with the failure detail; the engineer re-plans.

#### Step 1.3 — Parse dry-run results

Grep the debug log (or the CLI JSON output) for the emitted `DRY_RUN_*` lines:

- `DRY_RUN_COUNT=<N>` → `dry_run_count: <N>`
- `DRY_RUN_SAMPLE_IDS=<JSON-array>` → `sample_record_ids: <array>` (first 10 IDs)
- `DRY_RUN_DISTINCT_ACCOUNTS=<N>` → `distinct_accounts: <N>`
- `DRY_RUN_DISTINCT_OWNERS=<N>` → `distinct_owners: <N>`
- `DRY_RUN_DISTINCT_RECORD_TYPES=<N>` → `distinct_record_types: <N>`

Write to `$ARTIFACTS_DIR/data-correction-dry-run.json`:

```json
{
  "ts": "<UTC ISO 8601>",
  "ticket": "<TICKET-KEY>",
  "sub_type": "<sub_type>",
  "dry_run_count": 234,
  "sample_record_ids": ["<RECORD-ID-1>", "<RECORD-ID-2>", "..."],
  "distinct_accounts": 1,
  "distinct_owners": 3,
  "distinct_record_types": 1,
  "total_estimated_reach": 234,
  "dry_run_duration_seconds": 8.4
}
```

#### Step 1.4 — Hard-stop on 0 affected records

Per ADR-0023 §3: if `dry_run_count == 0`, ABORT the workflow with an error:

```
The correction has NO effect — likely a scope mistake.
Possible causes:
  - The SOQL WHERE clause matches no records.
  - The target records are already in the desired state.
  - The WHERE clause has a typo (case-sensitive value, wrong field API name).
Re-plan and re-run with a corrected WHERE clause.
```

Set `overall_result: "fail"`, `failure_reason: "dry_run_zero_affected"`. The post-validate gate does NOT fire (this is a hard stop). The workflow's update-jira-failure node handles the Jira write-back.

#### Step 1.5 — Compute scope-creep and segmentation-creep flags

Set these flags for the post-validate gate to read:

- `dry_run_count_exceeded_estimate`: `"true"` if `dry_run_count > $plan.output.expected_reach * 1.10`. The dry-run found >10% more records than the plan predicted.
- `dry_run_vs_estimate_pct`: `((dry_run_count - expected_reach) / expected_reach) * 100`, rounded to 1 decimal. Surfaced in the gate display.
- `segmentation_creep_detected`: `"true"` if ANY of:
  - `distinct_accounts > $plan.output.expected_distinct_accounts`
  - `distinct_owners > $plan.output.expected_distinct_owners`
  - `distinct_record_types > $plan.output.expected_distinct_record_types`
- `segmentation_matches_plan`: `"true"` if all three counts are <= plan's expectations (the negation of `segmentation_creep_detected`).

#### Step 1.6 — Restricted-object check

Read `$load-engagement-context.output.salesforce.data_corrections.restricted_objects` (default empty list). If the plan's `target_object` appears in the list, set `restricted_object_touched: "true"`. The post-validate gate fires unconditionally for this case.

#### Step 1.7 — Signal phase-1 complete

Write the phase-1 results to the validate output structure. The post-validate gate will read these and decide whether to fire. The workflow's DAG runner pauses validate here until the gate either passes (engineer approves) or skips (no triggering condition fired).

If NONE of `dry_run_count_exceeded_estimate`, `segmentation_creep_detected`, `restricted_object_touched`, `fls_posture_violation` are true → the post-validate gate is skipped (per its `when:` clause); proceed directly to Phase 2.

If ANY are true → the post-validate gate fires. The engineer reviews. If `proceed: "true"`, continue to Phase 2. If `proceed: "false"`, set `overall_result: "fail"`, `failure_reason: "gate_post_validate_aborted"`, stop.

### Phase 2 — Live DML (only after post-validate gate passes or is skipped)

#### Step 2.1 — Verify gate disposition

If `$gate-post-validate.output.proceed == "false"`: do NOT run phase 2. The gate aborted. Set `overall_result: "fail"`, `failure_reason: "gate_post_validate_aborted"`. Stop.

If `$gate-post-validate.output` is absent (gate was skipped — no triggering condition fired): proceed.

If `$gate-post-validate.output.proceed == "true"`: proceed.

#### Step 2.2 — Run the LIVE Apex

For anonymous-block sub-types (`data-update-anonymous-apex`, `data-delete-anonymous`, anonymous `data-insert`, `data-undelete`, `data-merge`):

```bash
sf apex run \
    --target-org "$TARGET_ORG_ALIAS" \
    --file "$ARTIFACTS_DIR/correction.apex" \
    --json \
    > "$ARTIFACTS_DIR/live-cli-output.json"
```

For batch sub-types: deploy the live class (with the LIVE name, not the DryRun name), invoke `Database.executeBatch(new <CorrectionName>(), <scope>);`, poll `AsyncApexJob` until `Completed`, read the debug log.

If the live Apex throws an unhandled exception, capture the exception details. Set `actual_count` to whatever the partial-success DML achieved (read from the `Database.SaveResult[]` / `DeleteResult[]` in the debug log). Set `overall_result: "fail"`, `failure_reason: "live_dml_exception"`, include the exception detail.

#### Step 2.3 — Parse live results

Grep the debug log for:

- `ACTUAL_COUNT=<N>` → `actual_count: <N>`
- `ACTUAL_SAMPLE_IDS=<JSON>` → `actual_sample_ids`
- For deletes: `ACTUAL_DELETED_IDS=<JSON>` → captured to `$ARTIFACTS_DIR/data-correction-deleted-ids.json`

Per-record DML failures (when `Database.update(records, false, ...)` is used in partial-success mode): the live Apex's debug log includes the `Database.SaveResult[]` array with per-record success/failure detail. Parse and record:

- `successful_records: <N>`
- `failed_records: <N>`
- `failure_details: [{record_id, error}]` (truncated to first 20 for the artifact)

#### Step 2.4 — Delta check (dry-run vs actual)

Per ADR-0023 §3 phase 2:

- `dry_run_actual_delta_pct`: `((actual_count - dry_run_count) / dry_run_count) * 100`, rounded to 1 decimal.
- If `|dry_run_actual_delta_pct| > 2` AND `actual_count != 0`: log a structured warning to the validate output. This typically means concurrent inserts/updates touched matching records between the dry-run and live phases. Not a failure (the DML still ran against whatever matched at live-run time), but the Jira comment flags it.

#### Step 2.5 — Capture deleted IDs (delete sub-types only)

For `data-delete-anonymous` and `data-delete-batch`: write `$ARTIFACTS_DIR/data-correction-deleted-ids.json`:

```json
{
  "ts": "<UTC ISO 8601>",
  "ticket": "<TICKET-KEY>",
  "sub_type": "data-delete-anonymous",
  "deleted_ids": ["<RECORD-ID-1>", "<RECORD-ID-2>", "..."],
  "deleted_count": 234,
  "recycle_bin_retention_days": 15,
  "recovery_instructions": "Records may be undeleted via the recycle bin or via a follow-up sf-data-correction run with sub_type=data-undelete within 15 days."
}
```

This is the recovery surface. Engineers reference it if the deletion turns out to be wrong.

### Aggregate output

Roll up phase 1 + phase 2 into one structured output. The workflow's document and update-jira nodes read this.

## Output

```json
{
  "fls_posture_violation": "false",
  "fls_posture_in_artifacts": "USER_MODE",

  "dry_run_status": "pass",
  "dry_run_count": 234,
  "sample_record_ids": ["<RECORD-ID-1>", "<RECORD-ID-2>", "..."],
  "distinct_accounts": 1,
  "distinct_owners": 3,
  "distinct_record_types": 1,
  "dry_run_count_exceeded_estimate": "false",
  "dry_run_vs_estimate_pct": 0.0,
  "segmentation_creep_detected": "false",
  "segmentation_matches_plan": "true",
  "restricted_object_touched": "false",
  "dry_run_artifact": "$ARTIFACTS_DIR/data-correction-dry-run.json",

  "actual_count": 234,
  "actual_sample_ids": ["<RECORD-ID-1>", "<RECORD-ID-2>", "..."],
  "successful_records": 234,
  "failed_records": 0,
  "failure_details": [],
  "dry_run_actual_delta_pct": 0.0,
  "deleted_ids_artifact": null,

  "overall_result": "pass",
  "failure_reason": null,
  "duration_seconds": 28
}
```

For delete sub-types, `deleted_ids_artifact` is set to the path of `data-correction-deleted-ids.json`.

For failure cases, `overall_result: "fail"` and `failure_reason` is one of:
- `fls_posture_violation` — Apex lacks USER_MODE enforcement; phase 2 did not run.
- `dry_run_zero_affected` — hard stop; the WHERE clause matches nothing.
- `dry_run_compile_error` — the dry-run Apex didn't compile; phase 2 did not run.
- `gate_post_validate_aborted` — engineer aborted at the post-validate gate; phase 2 did not run.
- `live_dml_exception` — phase 2 ran but threw; partial DML state recorded.

The structured output drives the workflow's document and Jira phases. Anything other than `overall_result: "pass"` short-circuits to the failure path.
