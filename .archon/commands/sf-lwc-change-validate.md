# `sf-lwc-change-validate`

You are orchestrating the validation gates for the LWC change executed in the previous step. This command does NOT itself deploy, run tests, or modify files — it calls the supporting scripts (and one inline a11y heuristic), then aggregates results.

LWC validation is the most complex of any Phase 7 family because LWC has **two test surfaces**: Jest (JavaScript unit tests) AND Apex (controller tests). Both run when present; the workflow degrades gracefully when Jest isn't configured per ADR-0021 §5.

## Inputs

- `$execute.output` — list of files actually changed
- `$plan.output` — `lwc_names`, `controller_names`, `jest_configured` flag, `controller_callers`
- `$classify-sub-type.output` — `sub_type`, `touches_soql_dml`
- `$load-engagement-context.output` — `coverage_threshold`, `regression_suite`
- `$verify-org-context.output` — `target_org_alias`, `is_scratch_org`, `scratch_org_def_path`

## Tools

Bash, Read, Grep. The supporting scripts live at `.archon/scripts/`:

- `deploy-to-scratch.sh` — creates/reuses a scratch org and deploys the changed `force-app/main/default/` files (LWC + controller + tests). Returns 0 on success.
- `run-apex-tests.sh` — runs the Apex test set (modified test classes + grep-referencing tests + engagement `regression_suite`) against the scratch org. Returns 0 only if every test passes AND every modified non-test class meets `coverage_threshold`.
- `check-fls-crud.sh` — regex-based static check for `WITH USER_MODE` on SOQL and `Security.stripInaccessible` (or `AccessLevel.USER_MODE`) on DML in modified classes. Returns 0 if pass; non-zero if issues found.
- `check-lwc-controller-contract.sh` — parses every modified LWC's JS for `import <name> from '@salesforce/apex/<Controller>.<method>'`, confirms each method exists in the (deployed) controller with `@AuraEnabled`. Returns 0 if pass; non-zero if a missing or contract-broken import is found. (If this script isn't present in the engagement yet, perform the equivalent check inline — see step 6.)

Jest is invoked directly via `npm test` (no dedicated harness script — Jest is engagement-specific).

## Task

Run the steps in order. Capture each script's exit code and structured output. After all steps run, aggregate. **A failing Apex test fails the workflow outright (no override path).** All other failures route to `gate-post-validate`.

### Step 1: Deploy to scratch (always)

```bash
bash .archon/scripts/deploy-to-scratch.sh \
  --org-alias "$verify-org-context.output.target_org_alias" \
  --files "<comma-separated paths from $execute.output.files_changed_actual>"
```

Capture exit code → `deploy_result` (`pass` / `fail`). If deploy fails, the workflow can't continue — set `overall_result: fail` and stop running subsequent steps (still emit the JSON).

### Step 2: Run Apex tests (always)

```bash
bash .archon/scripts/run-apex-tests.sh \
  --org-alias "$verify-org-context.output.target_org_alias" \
  --classes "<comma-separated $plan.output.apex_test_classes>" \
  --coverage-threshold "$load-engagement-context.output.coverage_threshold"
```

The script handles test selection (modified + grep-referencing + regression) and enforces the coverage gate. Capture exit code → `apex_tests_result` (`pass` / `fail`). Capture per-class coverage from the script's JSON output.

**A failing Apex test (or coverage below threshold) is NOT override-able.** Set `overall_result: fail` and the post-validate gate's `when:` expression will not match — the workflow routes straight to `update-jira-failure`.

### Step 3: Jest tests (conditional)

Detect whether Jest is configured. The engagement has Jest if:

```bash
test -f package.json && \
  ( grep -q '"jest"' package.json || grep -q '"@salesforce/sfdx-lwc-jest"' package.json )
```

OR more permissively, if `npx jest --version` succeeds in the engagement directory.

**If Jest is NOT configured:**

- Set `jest_tests_result: "skipped"`.
- Set `jest_skip_reason: "Jest not configured in this engagement (no package.json or no jest dependency). Add @salesforce/sfdx-lwc-jest to enable LWC Jest tests."` so it's visible in the output (and ultimately in the Jira write-back comment).
- DO NOT fail the workflow.

**If Jest IS configured:**

For each LWC in `$plan.output.lwc_names`, run:

```bash
npm test -- --testPathPattern="<lwcName>" --json --outputFile="$ARTIFACTS_DIR/jest-<lwcName>.json"
```

Capture exit code. The Jest JSON output gives `numPassedTests`, `numFailedTests`, `coverageMap` (if `--coverage` flag set — opt-in per engagement; check `package.json: scripts.test`).

Aggregate:

- `jest_tests_result`: `pass` if every LWC's Jest run had exit 0 and `numFailedTests == 0`; `fail` if any failed.
- `jest_test_count`: total tests run across all LWCs.
- `jest_failure_summary`: list of `{lwc, test_name, error}` for failures.

A Jest failure is **override-able** at `gate-post-validate` (`y` / `yes`) — the engineer may judge the failure is a test-only issue.

### Step 4: Accessibility heuristic (inline, non-blocking)

For each modified `.html` file in `$execute.output.files_changed_actual`, grep for common a11y misses:

```bash
# Images without alt= attribute
grep -nE '<img\b(?![^>]*\balt=)' "<path>" || true

# Buttons without text content AND without aria-label
# (Two-pass — first find <button> tags, then check each for label)
grep -nE '<button\b(?![^>]*\baria-label=)' "<path>" \
  | while IFS= read -r line; do
      # naive: if the matching <button> line doesn't also contain a closing > with text after, flag it
      # (a real check would parse the HTML; this is the regex stand-in per ADR-0021 §A11y option B)
      echo "$line"
    done
```

Note: the LWC platform's `<lightning-button>` component handles its own accessibility — exclude lines that match `<lightning-button`. The check is targeted at plain `<button>` and `<img>` tags.

Surface findings as a list:

- `a11y_findings`: array of `{file, line, issue}` objects (e.g., `{"file": "lwc/x/x.html", "line": 14, "issue": "<img> without alt= attribute"}`).
- `a11y_finding_count`: integer.

**This is informational only.** It does NOT fire the post-validate gate. It does NOT contribute to `overall_result`. It surfaces in the validate output for the engineer's awareness and lands in the Jira write-back comment.

### Step 5: FLS/CRUD check on the controller (always when any LWC controller was touched)

```bash
bash .archon/scripts/check-fls-crud.sh "<path to controller .cls file>"
```

**This step runs unconditionally for LWC controllers** per ADR-0021 §7, regardless of `$classify-sub-type.output.touches_soql_dml`. The rationale: LWC controllers are user-facing by default; the cost of a missed FLS check is materially higher than on non-LWC Apex.

Skip this step ONLY when the sub-type involves no Apex controller change (`create-lwc-jest-test`, `modify-lwc-jest-test`, `modify-lwc-meta`, `modify-lwc` without controller modification). For those, set `fls_crud_result: "skipped"` and `fls_crud_skip_reason: "no LWC controller changes in this run"`.

Capture exit code → `fls_crud_result` (`pass` / `fail` / `skipped`). FLS/CRUD failures are override-able at `gate-post-validate` (`y` / `yes`) — the override path established in ADR-0009 §7.

### Step 6: LWC ↔ controller contract check (when any LWC or controller was touched)

```bash
bash .archon/scripts/check-lwc-controller-contract.sh \
  --lwcs "<comma-separated $plan.output.lwc_names>" \
  --controllers "<comma-separated $plan.output.controller_names>"
```

The script parses each LWC's `.js` for `import <name> from '@salesforce/apex/<Controller>.<method>'` lines and verifies each `<method>` exists in the deployed controller with `@AuraEnabled`. It also detects the inverse — `@AuraEnabled` methods on the controller that no LWC imports — and surfaces those as orphans (informational, not a failure).

**If the script isn't present in the engagement yet** (Phase 7 deliverable, may not have shipped to all engagements): perform the equivalent check inline:

```bash
# For each LWC in scope:
for lwc in $LWC_NAMES; do
  js_file="force-app/main/default/lwc/${lwc}/${lwc}.js"
  [ -f "$js_file" ] || continue
  # Extract imported method names
  grep -oE "from '@salesforce/apex/[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*'" "$js_file" \
    | sed -E "s|.*@salesforce/apex/([^.]+)\.([^']+).*|\1 \2|" \
    | while read controller method; do
        cls="force-app/main/default/classes/${controller}.cls"
        if ! grep -qE "@AuraEnabled[^)]*\)[[:space:]]*public[[:space:]]+[A-Za-z<>,_[:space:]]+[[:space:]]+${method}\b" "$cls"; then
          echo "BROKEN: ${lwc} imports ${controller}.${method} but no @AuraEnabled method matches"
        fi
      done
done
```

Capture → `controller_contract_result` (`pass` / `fail`). A failure is override-able at `gate-post-validate` but requires the literal `CONFIRM` form (per ADR-0021 §6 — post-execute contract drift means the engineer's change broke the contract AFTER plan/execute predicted it wouldn't).

### Step 7: Aggregate

`overall_result` is:

- `pass` only if:
  - `deploy_result == pass`
  - `apex_tests_result == pass`
  - `jest_tests_result ∈ {pass, skipped}`
  - `fls_crud_result ∈ {pass, skipped}` OR a CONFIRM was provided at a future gate (deferred to gate-post-validate's evaluation)
  - `controller_contract_result ∈ {pass, skipped}` OR a CONFIRM was provided at gate-post-validate
- `fail` otherwise.

A11y findings do NOT affect `overall_result`.

## Output

```json
{
  "deploy_result": "pass",
  "deploy_artifact": "$ARTIFACTS_DIR/deploy-to-scratch.json",
  "apex_tests_result": "pass",
  "apex_tests_artifact": "$ARTIFACTS_DIR/run-apex-tests.json",
  "coverage_threshold": 75,
  "per_class_coverage": [
    {"class": "RenewalSummaryController", "coverage": 89}
  ],
  "jest_tests_result": "pass",
  "jest_skip_reason": null,
  "jest_test_count": 8,
  "jest_failure_summary": [],
  "a11y_findings": [],
  "a11y_finding_count": 0,
  "fls_crud_result": "pass",
  "fls_crud_artifact": "$ARTIFACTS_DIR/check-fls-crud.json",
  "controller_contract_result": "pass",
  "controller_contract_artifact": "$ARTIFACTS_DIR/check-lwc-controller-contract.json",
  "overall_result": "pass",
  "duration_seconds": 312,
  "failure_reason": []
}
```

On any non-pass result, populate `failure_reason` with one string per failing check (e.g., `"Jest: 2 tests failed in renewalSummary.test.js"`, `"FLS/CRUD: SOQL on Renewal__c lacks WITH USER_MODE at RenewalSummaryController.cls:42"`, `"Controller contract: renewalSummary imports getStripeInvoiceUrl but no @AuraEnabled method matches in RenewalSummaryController.cls"`). The post-validate gate reads `failure_reason` to render its display.
