# `sf-metadata-change-validate`

You are orchestrating the validation checks for the metadata change executed in the previous step. This command runs the deploy script, then a reference-impact grep, then (when relevant) an FLS-coverage cross-check, and aggregates the results. The scripts and inline checks are the source of truth for what passes; this command rolls them up.

## Inputs

- `$execute.output` — list of files actually changed, destructive-manifest status
- `$classify-sub-type.output` — `sub_type`, `touches_fls`, `is_destructive_modify_field`, `affects_picklist_data`
- `$load-engagement-context.output` — `dev_model`, security docs in scope
- `$verify-org-context.output` — `target_org_alias`, `is_scratch_org`, `scratch_org_def_path`
- `$plan.output` — proposed FLS posture (for `create-field` cross-check)

## Tools

Bash (for the deploy script and grep), Read, Grep. The deploy script lives at `.archon/scripts/`:

- `deploy-to-scratch.sh` — creates a scratch org from `scratch_org_def_path` (if not already running for this engagement) and deploys the changed metadata files. Honors `HARNESS_SKIP_SCRATCH=1` by deploying to `target_org_alias` instead. Returns 0 on success.

Reference-impact and FLS-coverage checks are run inline in this command — no new scripts. The grep tool is the harness's standard `Grep` tool (ripgrep underneath).

## Task

Run the checks in order. Capture each result. After all run, aggregate.

1. **Always run `deploy-to-scratch.sh`** with the org alias and the file list from `$execute.output.files_changed_actual`. If deploy fails, the workflow can't continue — emit `overall_result: fail` and stop. The deploy script handles `manifest/destructiveChanges.xml` automatically for `source_tracked` engagements.

2. **Run the reference-impact grep** for any destructive or rename operation:
   - For each file in `$execute.output.files_changed_actual` with `operation == "delete"`: extract the metadata API name from the file path (e.g., `force-app/main/default/objects/Account/fields/Old_Field__c.field-meta.xml` → `Old_Field__c`). Then grep for that name across:
     ```
     force-app/main/default/classes/
     force-app/main/default/triggers/
     force-app/main/default/flows/
     force-app/main/default/lwc/
     force-app/main/default/aura/
     ```
     Use a literal-string grep (not regex) to avoid false positives.
   - For each rename recorded in `$execute.output.rename_references_deferred`: grep the same scope for the OLD API name.
   - For `delete-picklist-value`: the value itself was deleted, not a field. Grep for the literal value string (e.g., `'Gold'` or `"Gold"`) in classes/triggers/flows/lwc/aura, plus any `validationRule-meta.xml` that hardcodes the value in its formula.
   - Aggregate: each match is a "broken reference candidate." Record file:line for each.
   - **Result:** `pass` if zero matches; `fail` if any match (the engineer will see them at the post-validate gate).
   - **Skip case:** If the sub_type is not in `{delete-field, delete-validation-rule, delete-picklist-value}` and there are no rename operations, the reference-impact check is `skipped`.

3. **Run the FLS-coverage cross-check** (only when `$classify-sub-type.output.touches_fls == "true"` AND `sub_type == "create-field"`):
   - Read `$plan.output.fls_posture` — the proposed read/edit profile and PS lists.
   - For each profile in `fls_posture.read` and `fls_posture.edit`: check whether `docs/security/profiles/<Profile>.md` exists. If it doesn't, the FLS posture references an undocumented profile — flag this as an FLS-coverage gap.
   - For each PS in the lists: same check against `docs/security/permission-sets/<PS>.md`.
   - **Result:** `pass` if every profile/PS in the posture has an existing security doc; `fail` if any are missing. The post-validate gate surfaces the gap; the document step will record it.
   - **Skip case:** When `touches_fls == "false"` OR sub_type is not `create-field`, this check is `skipped`.

4. **Aggregate `overall_result`.** `overall_result` is the raw truth of the validation checks; the workflow's `when:` clauses decide what to do with it.
   - `pass` if: deploy succeeded, reference-impact is `pass` or `skipped`, FLS-coverage is `pass` or `skipped`.
   - `fail` if ANY individual check failed.

   When `overall_result` is `fail`, the workflow's post-validate gate fires. The gate gives the engineer a chance to acknowledge and `CONFIRM` (for broken references) or accept `y` (for FLS-coverage gaps) — that's the workflow's job, not this command's. The `document` node's `when:` clause depends on BOTH `overall_result == 'pass'` AND `gate-post-validate.output.proceed != 'false'`, so when the engineer overrides via `CONFIRM`, the workflow proceeds despite this command reporting `fail`.

   Concrete: when deploy fails, no recovery is possible — the metadata didn't land. When reference-impact fails, the engineer can `CONFIRM` and follow up in `sf-apex-change`. When FLS-coverage fails, the engineer accepts `y` and the document step records the gap. Set `overall_result` to `pass` only when every individual check is `pass` or `skipped`; set `fail` otherwise.

5. **Skip behavior under `HARNESS_SKIP_SCRATCH=1`.** When the environment variable is set, `deploy-to-scratch.sh` targets `target_org_alias` instead of a scratch org. The reference-impact and FLS-coverage checks run identically — they're static, org-independent. Record the deploy target in the output JSON for transparency.

## Output

```json
{
  "deploy_result": "pass",
  "deploy_artifact": "$ARTIFACTS_DIR/deploy-to-scratch.json",
  "reference_impact_result": "pass",
  "reference_impact_artifact": "$ARTIFACTS_DIR/reference-impact.json",
  "broken_references": [],
  "fls_coverage_result": "skipped",
  "fls_coverage_artifact": "$ARTIFACTS_DIR/fls-coverage.json",
  "missing_security_docs": [],
  "overall_result": "pass",
  "duration_seconds": 87
}
```

On any non-pass result, the JSON also includes a `failure_reason` array of strings (one per failing check) so the post-validate gate can display them. For `reference_impact_result == "fail"`, the `broken_references` array lists `{file, line, matched_name}` entries; for `fls_coverage_result == "fail"`, the `missing_security_docs` array lists the missing profile/PS doc paths.
