#!/usr/bin/env bash
#
# run-apex-tests.sh — Phase 4 / sf-apex-change validate step
#
# Runs Apex tests against the scratch org created by deploy-to-scratch.sh
# and enforces the per-class coverage gate from engagement.yaml.
# Per ADR-0009 §2 and §5.
#
# Usage:
#   ./run-apex-tests.sh <scratch-alias> <test-classes-csv>
#
#   scratch-alias       — typically "<engagement_alias>-scratch-current"
#                         (the alias deploy-to-scratch.sh created or reused)
#   test-classes-csv    — comma-separated list of test class names, no spaces
#                         (e.g., "RenewalCalculator_Test,AccountTrigger_Test")
#                         Empty string means "run no tests" — script fails.
#
# Reads from engagement.yaml at repo root:
#   salesforce.coverage.per_class_target  (default 75 if missing)
#
# Outputs:
#   $ARTIFACTS_DIR/run-apex-tests.json — structured result
#   stdout — human-readable progress
#
# Exit codes:
#   0 — all tests passed AND every modified non-test class meets coverage_threshold
#   1 — invalid invocation
#   2 — test execution failure (one or more tests failed)
#   3 — coverage gate failure (tests passed but some class is below threshold)
#   4 — engagement.yaml problem
#
# A note on coverage scope: this script only measures coverage of classes that
# were actually modified by the workflow run. The caller (sf-apex-change-validate)
# tells the script which classes are "modified non-test" via env var
# MODIFIED_NON_TEST_CLASSES (comma-separated). If unset, the script falls back
# to checking coverage of every class with results — preserving the gate but
# possibly flagging unrelated coverage drops.

set -euo pipefail

# ─── prerequisites ────────────────────────────────────────────────────

command -v sf >/dev/null 2>&1 || { echo "error: 'sf' not on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not on PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: 'python3' not on PATH" >&2; exit 1; }

if [ $# -ne 2 ]; then
  echo "usage: $0 <scratch-alias> <test-classes-csv>" >&2
  exit 1
fi

SCRATCH_ALIAS="$1"
TEST_CLASSES_CSV="$2"

if [ -z "$TEST_CLASSES_CSV" ]; then
  echo "error: no test classes selected; the workflow may have misclassified the change" >&2
  exit 1
fi

ARTIFACTS_DIR="${ARTIFACTS_DIR:-.archon/run-artifacts}"
mkdir -p "$ARTIFACTS_DIR"
RESULT_FILE="$ARTIFACTS_DIR/run-apex-tests.json"
TEST_JSON="$ARTIFACTS_DIR/sf-apex-test.json"

# ─── coverage threshold from engagement.yaml ──────────────────────────

read_yaml_int() {
  python3 -c "
import yaml
with open('engagement.yaml') as f:
    d = yaml.safe_load(f)
keys = '$1'.split('.')
for k in keys:
    d = d.get(k) if isinstance(d, dict) else None
print(int(d) if d is not None else '$2')
"
}

THRESHOLD=$(read_yaml_int "salesforce.coverage.per_class_target" "75")

# ─── run tests ────────────────────────────────────────────────────────

echo "→ Running tests against $SCRATCH_ALIAS"
echo "  Test classes: $TEST_CLASSES_CSV"
echo "  Coverage threshold (per-class): $THRESHOLD%"

TEST_EXIT=0
sf apex run test \
  --target-org "$SCRATCH_ALIAS" \
  --tests "$TEST_CLASSES_CSV" \
  --code-coverage \
  --synchronous \
  --wait 30 \
  --result-format json \
  > "$TEST_JSON" 2>&1 || TEST_EXIT=$?

# sf apex run test exits non-zero on test failures, but we still want to
# parse the JSON for structured reporting. Re-check via JSON.

TOTAL_TESTS=$(jq '.result.summary.testsRan // 0' "$TEST_JSON" 2>/dev/null || echo 0)
PASSING_TESTS=$(jq '.result.summary.passing // 0' "$TEST_JSON" 2>/dev/null || echo 0)
FAILING_TESTS=$(jq '.result.summary.failing // 0' "$TEST_JSON" 2>/dev/null || echo 0)

# ─── per-class coverage gate ──────────────────────────────────────────

# MODIFIED_NON_TEST_CLASSES is comma-separated; convert to a jq filter.
# Empty → check every class in the coverage report.
MODIFIED_LIST="${MODIFIED_NON_TEST_CLASSES:-}"

if [ -n "$MODIFIED_LIST" ]; then
  # Build a jq array of class names
  jq_filter=$(echo "$MODIFIED_LIST" | python3 -c "
import sys, json
names = [n.strip() for n in sys.stdin.read().split(',') if n.strip()]
print(json.dumps(names))
")
  BELOW_THRESHOLD=$(jq \
    --argjson modified "$jq_filter" \
    --argjson threshold "$THRESHOLD" \
    '[
      .result.coverage.coverage[]?
      | select(.name as $n | $modified | index($n))
      | select(.coveredPercent < $threshold)
      | { class: .name, coverage: .coveredPercent }
    ]' \
    "$TEST_JSON")
else
  BELOW_THRESHOLD=$(jq \
    --argjson threshold "$THRESHOLD" \
    '[
      .result.coverage.coverage[]?
      | select(.coveredPercent < $threshold)
      | { class: .name, coverage: .coveredPercent }
    ]' \
    "$TEST_JSON")
fi

PER_CLASS_LIST=$(jq '
  [
    .result.coverage.coverage[]?
    | { class: .name, coverage: .coveredPercent }
  ]
' "$TEST_JSON")

BELOW_COUNT=$(echo "$BELOW_THRESHOLD" | jq 'length')

# ─── determine overall result ─────────────────────────────────────────

if [ "$FAILING_TESTS" -gt 0 ]; then
  STATUS="fail"
  REASON="tests_failed"
  EXIT=2
elif [ "$BELOW_COUNT" -gt 0 ]; then
  STATUS="fail"
  REASON="coverage_below_threshold"
  EXIT=3
else
  STATUS="pass"
  REASON=""
  EXIT=0
fi

# ─── structured result ────────────────────────────────────────────────

jq -n \
  --arg status "$STATUS" \
  --arg reason "$REASON" \
  --argjson total "$TOTAL_TESTS" \
  --argjson passing "$PASSING_TESTS" \
  --argjson failing "$FAILING_TESTS" \
  --argjson threshold "$THRESHOLD" \
  --argjson per_class "$PER_CLASS_LIST" \
  --argjson below "$BELOW_THRESHOLD" \
  --arg artifact "$TEST_JSON" \
  '{
    result: $status,
    failure_reason: $reason,
    total_tests: $total,
    passing_tests: $passing,
    failing_tests: $failing,
    coverage_threshold: $threshold,
    per_class_coverage: $per_class,
    classes_below_threshold: $below,
    tests_artifact: $artifact
  }' > "$RESULT_FILE"

echo "→ Tests: $PASSING_TESTS/$TOTAL_TESTS passed ($FAILING_TESTS failing)"
echo "→ Coverage: $BELOW_COUNT class(es) below ${THRESHOLD}% threshold"
echo "→ Result: $STATUS"
echo "  Detail: $RESULT_FILE"

exit $EXIT
