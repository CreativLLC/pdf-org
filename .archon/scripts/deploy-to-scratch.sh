#!/usr/bin/env bash
#
# deploy-to-scratch.sh — Phase 4 / sf-apex-change validate step
#
# Creates (or reuses) a scratch org for this engagement and deploys the
# changed Apex files to it. Called by sf-apex-change-validate.md.
#
# Usage:
#   ./deploy-to-scratch.sh [<file-path> ...]
#
#   With no args: deploys all changes in `force-app/main/default/` per
#   `sf project deploy start` defaults.
#
#   With args: deploys only the named paths (faster for small changes).
#
# Reads from environment (typically auto-loaded by direnv per ADR-0008):
#   None directly. Engagement context comes from `engagement.yaml` via jq.
#
# Reads from engagement.yaml at repo root:
#   salesforce.scratch_org_def_path
#   salesforce.api_version  (informational; sf inherits from def file)
#   engagement_alias        (used in scratch org alias naming)
#
# Outputs:
#   $ARTIFACTS_DIR/deploy-to-scratch.json — structured result
#   stdout — human-readable progress
#   exit code 0 on success; non-zero on failure (see below)
#
# Exit codes:
#   0 — deploy succeeded
#   1 — invalid invocation, prerequisites missing
#   2 — scratch org creation failed
#   3 — deploy failed (compile errors, manifest issues, etc.)
#   4 — engagement.yaml missing or malformed

set -euo pipefail

# ─── prerequisites ────────────────────────────────────────────────────

command -v sf >/dev/null 2>&1 || {
  echo "error: 'sf' (Salesforce CLI) not found on PATH. Run harness-machine-setup.sh." >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "error: 'jq' not found on PATH. Run harness-machine-setup.sh." >&2
  exit 1
}

ENGAGEMENT_YAML="engagement.yaml"
if [ ! -f "$ENGAGEMENT_YAML" ]; then
  echo "error: engagement.yaml not found in $(pwd). Run from engagement repo root." >&2
  exit 4
fi

ARTIFACTS_DIR="${ARTIFACTS_DIR:-.archon/run-artifacts}"
mkdir -p "$ARTIFACTS_DIR"
RESULT_FILE="$ARTIFACTS_DIR/deploy-to-scratch.json"

# ─── read engagement.yaml ─────────────────────────────────────────────

# We use a tiny Python helper for YAML parsing — yq isn't reliably installed.
# Python 3 is verified by harness-machine-setup.sh.
read_yaml() {
  python3 -c "
import yaml, sys
with open('$ENGAGEMENT_YAML') as f:
    d = yaml.safe_load(f)
keys = '$1'.split('.')
for k in keys:
    d = d.get(k) if isinstance(d, dict) else None
print(d if d is not None else '')
"
}

SCRATCH_DEF=$(read_yaml "salesforce.scratch_org_def_path")
ENGAGEMENT_ALIAS=$(read_yaml "engagement_alias")
API_VERSION=$(read_yaml "salesforce.api_version")

if [ -z "$SCRATCH_DEF" ] || [ ! -f "$SCRATCH_DEF" ]; then
  echo "error: salesforce.scratch_org_def_path ('$SCRATCH_DEF') is missing or not found." >&2
  exit 4
fi

# ─── ensure a scratch org exists for this engagement ──────────────────
#
# Demo / no-DevHub deviation: if HARNESS_SKIP_SCRATCH=1 is set in the env
# (typically via the engagement's .envrc), skip scratch creation entirely
# and deploy to the engagement's `salesforce.target_org_alias` directly.
# This is an explicit deviation from ADR-0009 §4 ("scratch only deployment
# scope for v1"). Use only when the team genuinely lacks a DevHub or when
# demoing against a disposable sandbox. A proper engagement with a DevHub
# should leave HARNESS_SKIP_SCRATCH unset and run the workflow as designed.

if [ "${HARNESS_SKIP_SCRATCH:-0}" = "1" ]; then
  SCRATCH_ALIAS=$(read_yaml "salesforce.target_org_alias")
  if [ -z "$SCRATCH_ALIAS" ]; then
    echo "error: HARNESS_SKIP_SCRATCH=1 but salesforce.target_org_alias is empty in engagement.yaml" >&2
    exit 4
  fi
  echo "→ HARNESS_SKIP_SCRATCH=1 — deploying directly to target org '$SCRATCH_ALIAS' (ADR-0009 §4 deviation)"
else
  SCRATCH_ALIAS="${ENGAGEMENT_ALIAS}-scratch-current"

  # Check whether the scratch is already authorized + valid
  if sf org display --target-org "$SCRATCH_ALIAS" --json >/dev/null 2>&1; then
    echo "→ Reusing existing scratch org: $SCRATCH_ALIAS"
  else
    echo "→ Creating scratch org from $SCRATCH_DEF (alias $SCRATCH_ALIAS, 7-day duration)"
    if ! sf org create scratch \
          --definition-file "$SCRATCH_DEF" \
          --alias "$SCRATCH_ALIAS" \
          --duration-days 7 \
          --wait 10 \
          --json > "$ARTIFACTS_DIR/scratch-create.json"; then
      echo "error: scratch org creation failed. See $ARTIFACTS_DIR/scratch-create.json." >&2
      jq -r '.message // empty' "$ARTIFACTS_DIR/scratch-create.json" >&2 || true
      exit 2
    fi
  fi
fi

# ─── deploy ────────────────────────────────────────────────────────────

DEPLOY_ARGS=(--target-org "$SCRATCH_ALIAS" --wait 30 --json)
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    DEPLOY_ARGS+=(--source-dir "$f")
  done
else
  DEPLOY_ARGS+=(--source-dir force-app/main/default)
fi

echo "→ Deploying to $SCRATCH_ALIAS"
DEPLOY_JSON="$ARTIFACTS_DIR/sf-deploy.json"
if sf project deploy start "${DEPLOY_ARGS[@]}" > "$DEPLOY_JSON"; then
  STATUS="pass"
  EXIT=0
else
  STATUS="fail"
  EXIT=3
fi

# ─── structured result ────────────────────────────────────────────────

NUM_COMPONENTS=$(jq '.result.numberComponentsDeployed // 0' "$DEPLOY_JSON")
NUM_ERRORS=$(jq '.result.numberComponentErrors // 0' "$DEPLOY_JSON")
FIRST_ERROR=$(jq -r '.result.details.componentFailures[0].problem // ""' "$DEPLOY_JSON")
INSTANCE_URL=$(sf org display --target-org "$SCRATCH_ALIAS" --json 2>/dev/null | jq -r '.result.instanceUrl // ""')

jq -n \
  --arg status "$STATUS" \
  --arg alias "$SCRATCH_ALIAS" \
  --arg instance "$INSTANCE_URL" \
  --argjson components "$NUM_COMPONENTS" \
  --argjson errors "$NUM_ERRORS" \
  --arg first_error "$FIRST_ERROR" \
  --arg artifact "$DEPLOY_JSON" \
  '{
    result: $status,
    scratch_org_alias: $alias,
    scratch_instance_url: $instance,
    components_deployed: $components,
    component_errors: $errors,
    first_error: $first_error,
    deploy_artifact: $artifact
  }' > "$RESULT_FILE"

echo "→ Result: $STATUS  ($NUM_COMPONENTS components, $NUM_ERRORS errors)"
echo "  Detail: $RESULT_FILE"

exit $EXIT
