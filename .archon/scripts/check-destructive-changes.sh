#!/usr/bin/env bash
#
# check-destructive-changes.sh — Phase 4 / sf-apex-change validate step
#
# Static check for destructive Apex changes per ADR-0009 §3. Operates on the
# diff between the workflow's working tree and `git diff HEAD` — so the
# engagement repo must be a git repo and the changes must NOT yet be
# committed. (Which is the normal state during a workflow run.)
#
# Detected destructive changes:
#   - Deletion of a `.cls` or `.trigger` file
#   - Removal of a `public` or `global` method from a non-test class
#   - Signature change of a `public` or `global` method
#   - Visibility downgrade (`global` → `public`, `public` → `private`)
#   - Removal of `@AuraEnabled` annotation
#   - Removal of `@InvocableMethod` annotation
#
# Detection is regex-based on the git diff. Not a full Apex parser. False
# positives are expected and surface at the in-workflow confirm gate where
# the engineer can override with "CONFIRM" per ADR-0009 §3.
#
# Usage:
#   ./check-destructive-changes.sh
#     (operates on `git diff HEAD --name-only` and `git diff HEAD --` to
#      detect destructive changes in the current working tree)
#
# Outputs:
#   $ARTIFACTS_DIR/check-destructive-changes.json — structured result
#   stdout — human-readable summary
#
# Exit codes:
#   0 — no destructive changes detected
#   1 — invalid invocation / not a git repo
#   2 — destructive changes detected (the workflow's gate decides what to do)

set -euo pipefail

command -v git >/dev/null 2>&1 || { echo "error: 'git' not on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not on PATH" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "error: not a git repository" >&2
  exit 1
}

ARTIFACTS_DIR="${ARTIFACTS_DIR:-.archon/run-artifacts}"
mkdir -p "$ARTIFACTS_DIR"
RESULT_FILE="$ARTIFACTS_DIR/check-destructive-changes.json"

# ─── collect Apex files in the diff ───────────────────────────────────

CHANGED_APEX=$(git diff HEAD --name-only --diff-filter=AMRD 2>/dev/null \
  | grep -E '\.(cls|trigger)$' || true)

DELETED_APEX=$(git diff HEAD --name-only --diff-filter=D 2>/dev/null \
  | grep -E '\.(cls|trigger)$' || true)

DESTRUCTIVE_ISSUES=()

# ─── rule 1: file deletions ───────────────────────────────────────────

if [ -n "$DELETED_APEX" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    DESTRUCTIVE_ISSUES+=("$(jq -n --arg file "$f" \
      '{type: "file_deletion", file: $file, severity: "destructive"}')")
  done <<<"$DELETED_APEX"
fi

# ─── rules 2–6: per-file diff analysis ────────────────────────────────

# For each modified (non-deleted) Apex file, get the diff and grep for
# patterns matching destructive changes. We look at lines starting with `-`
# (in the diff) that match destructive patterns.

if [ -n "$CHANGED_APEX" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue

    # Skip if file no longer exists (it's a deletion, already counted)
    [ ! -f "$f" ] && continue

    # Skip test classes for the public-API-removal rules (test classes don't
    # have stable public APIs that callers depend on)
    if grep -q '@IsTest' "$f" 2>/dev/null; then
      IS_TEST=true
    else
      IS_TEST=false
    fi

    DIFF=$(git diff HEAD -- "$f")

    # Rule 2: removed public/global method
    if [ "$IS_TEST" = false ]; then
      REMOVED_METHODS=$(echo "$DIFF" \
        | grep -E '^-[[:space:]]*(public|global)[[:space:]]+(static[[:space:]]+)?[A-Za-z<>,_]+[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' \
        | sed 's/^-//' \
        | sed 's/^[[:space:]]*//' || true)
      if [ -n "$REMOVED_METHODS" ]; then
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          DESTRUCTIVE_ISSUES+=("$(jq -n --arg file "$f" --arg line "$line" \
            '{type: "public_method_removed", file: $file, signature: $line, severity: "destructive"}')")
        done <<<"$REMOVED_METHODS"
      fi
    fi

    # Rule 3 (signature change) is hard to detect from a regex on - lines
    # alone — a signature change appears as removed-line + added-line. We
    # flag any change to a `public`/`global` method declaration line and
    # leave the engineer to assess at the gate.
    if [ "$IS_TEST" = false ]; then
      CHANGED_SIGNATURES=$(echo "$DIFF" \
        | grep -cE '^[-+][[:space:]]*(public|global)[[:space:]]+(static[[:space:]]+)?[A-Za-z<>,_]+[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' || true)
      # If we have both - and + lines matching, it's a likely signature change
      # already-removed methods are counted as rule 2; this catches mods.
      # Heuristic: any change >=2 lines could be a signature change.
      if [ "${CHANGED_SIGNATURES:-0}" -ge 2 ]; then
        DESTRUCTIVE_ISSUES+=("$(jq -n --arg file "$f" \
          '{type: "possible_signature_change", file: $file, severity: "destructive", note: "Two or more public/global method declarations changed; verify at gate."}')")
      fi
    fi

    # Rule 4: visibility downgrade — global→public or public→private
    # Heuristic: removed `global ...method(` paired with added `public ...method(` (or similar)
    # We flag any removal of a `global` line, which is rare enough to inspect.
    REMOVED_GLOBALS=$(echo "$DIFF" \
      | grep -cE '^-[[:space:]]*global[[:space:]]' || true)
    if [ "${REMOVED_GLOBALS:-0}" -gt 0 ]; then
      DESTRUCTIVE_ISSUES+=("$(jq -n --arg file "$f" \
        '{type: "visibility_downgrade_possible", file: $file, severity: "destructive", note: "Lines starting with `global` were removed; managed-package consumers may break."}')")
    fi

    # Rule 5: removed @AuraEnabled annotation
    REMOVED_AURA=$(echo "$DIFF" \
      | grep -cE '^-[[:space:]]*@AuraEnabled' || true)
    if [ "${REMOVED_AURA:-0}" -gt 0 ]; then
      DESTRUCTIVE_ISSUES+=("$(jq -n --arg file "$f" \
        '{type: "aura_enabled_removed", file: $file, severity: "destructive", note: "@AuraEnabled annotation removed; LWC/Aura callers may break."}')")
    fi

    # Rule 6: removed @InvocableMethod annotation
    REMOVED_INVOCABLE=$(echo "$DIFF" \
      | grep -cE '^-[[:space:]]*@InvocableMethod' || true)
    if [ "${REMOVED_INVOCABLE:-0}" -gt 0 ]; then
      DESTRUCTIVE_ISSUES+=("$(jq -n --arg file "$f" \
        '{type: "invocable_method_removed", file: $file, severity: "destructive", note: "@InvocableMethod annotation removed; Flow callers may break."}')")
    fi

  done <<<"$CHANGED_APEX"
fi

# ─── structured result ────────────────────────────────────────────────

ISSUE_COUNT=${#DESTRUCTIVE_ISSUES[@]}

if [ "$ISSUE_COUNT" -gt 0 ]; then
  ISSUES_JSON=$(printf '%s\n' "${DESTRUCTIVE_ISSUES[@]}" | jq -s '.')
  STATUS="fail"
  EXIT=2
else
  ISSUES_JSON='[]'
  STATUS="pass"
  EXIT=0
fi

jq -n \
  --arg status "$STATUS" \
  --argjson issues "$ISSUES_JSON" \
  --argjson count "$ISSUE_COUNT" \
  '{
    result: $status,
    destructive_issue_count: $count,
    destructive_issues: $issues
  }' > "$RESULT_FILE"

echo "→ Destructive change check: $STATUS ($ISSUE_COUNT issue(s))"
[ "$ISSUE_COUNT" -gt 0 ] && echo "  Detail: $RESULT_FILE"

exit $EXIT
