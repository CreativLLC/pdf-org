#!/usr/bin/env bash
#
# check-fls-crud.sh — Phase 4 / sf-apex-change validate step
#
# Regex-based static check for FLS/CRUD enforcement in modified Apex per
# ADR-0009 §7. Per the team-canon pattern in patterns/fls-crud-enforcement.md,
# user-data SOQL must use `WITH USER_MODE` (or `WITH SECURITY_ENFORCED`), and
# user-data DML must be preceded by `Security.stripInaccessible(...)`.
#
# This check is intentionally regex-based, not AST-aware. False positives
# are expected; the workflow's post-validate gate surfaces them so the
# engineer can override with "y" if the flagged line is legitimately fine
# (e.g., the method runs in system context, the SOQL is on a non-user
# object like a Custom Setting, etc.). False negatives we accept too —
# this is a safety net, not a guarantee.
#
# Usage:
#   ./check-fls-crud.sh [<apex-file-path> ...]
#
#   With no args: checks all changed Apex files in `git diff HEAD`.
#   With args: checks only the named files (must be .cls or .trigger).
#
# Outputs:
#   $ARTIFACTS_DIR/check-fls-crud.json — structured result
#
# Exit codes:
#   0 — no issues found, OR no modified files do SOQL/DML
#   1 — invalid invocation
#   2 — issues found (the workflow's gate decides what to do)

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not on PATH" >&2; exit 1; }

ARTIFACTS_DIR="${ARTIFACTS_DIR:-.archon/run-artifacts}"
mkdir -p "$ARTIFACTS_DIR"
RESULT_FILE="$ARTIFACTS_DIR/check-fls-crud.json"

# ─── collect files to check ───────────────────────────────────────────

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  # Default: every changed Apex file in the working tree
  mapfile -t FILES < <(git diff HEAD --name-only --diff-filter=AM 2>/dev/null \
    | grep -E '\.(cls|trigger)$' || true)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  jq -n '{result: "pass", issue_count: 0, issues: [], note: "no Apex files to check"}' > "$RESULT_FILE"
  echo "→ FLS/CRUD check: pass (no Apex files in scope)"
  exit 0
fi

# ─── inspect each file ────────────────────────────────────────────────

ISSUES=()

for f in "${FILES[@]}"; do
  [ ! -f "$f" ] && continue

  # Skip test classes — security context is artificial in tests, and the
  # team's testdatafactory-usage.md pattern covers the right approach.
  if grep -q '@IsTest' "$f" 2>/dev/null; then
    continue
  fi

  # ─── Rule A: SOQL lacking WITH USER_MODE or WITH SECURITY_ENFORCED ──

  # A SOQL inline query in Apex is `[ SELECT ... FROM ... ]`. We grep for
  # lines containing `[SELECT ` (case-insensitive — Apex SOQL keywords are
  # case-insensitive) followed eventually by `FROM <something>` on the same
  # line. We flag lines that do NOT also contain `WITH USER_MODE` or
  # `WITH SECURITY_ENFORCED`.
  #
  # Limitation: multi-line SOQL won't be matched on a single grep line. The
  # engineer's pattern doc (fls-crud-enforcement.md) recommends single-line
  # or terminating-line WITH clauses, and we accept the false-negative on
  # heavily-wrapped multi-line SOQL.

  while IFS=: read -r line_no line_content; do
    [ -z "$line_no" ] && continue
    # Check the same line for WITH USER_MODE or WITH SECURITY_ENFORCED
    if ! echo "$line_content" | grep -qiE 'WITH[[:space:]]+(USER_MODE|SECURITY_ENFORCED)'; then
      # Also tolerate lines where the WITH clause is on the NEXT line.
      # Read 3 lines starting at line_no and check.
      window=$(sed -n "${line_no},$((line_no + 3))p" "$f" 2>/dev/null | tr -d '\n')
      if ! echo "$window" | grep -qiE 'WITH[[:space:]]+(USER_MODE|SECURITY_ENFORCED)'; then
        ISSUES+=("$(jq -n \
          --arg file "$f" \
          --arg line "$line_no" \
          --arg content "$(echo "$line_content" | sed 's/^[[:space:]]*//')" \
          '{
            type: "soql_without_user_mode",
            file: $file,
            line: ($line | tonumber),
            content: $content,
            severity: "warning",
            note: "SOQL detected without WITH USER_MODE or WITH SECURITY_ENFORCED. Override if this query runs in a system context or targets a non-user object."
          }')")
      fi
    fi
  done < <(grep -niE '\[[[:space:]]*SELECT[[:space:]].+FROM[[:space:]]+[A-Za-z_]' "$f" 2>/dev/null || true)

  # ─── Rule B: DML lacking Security.stripInaccessible ────────────────

  # DML keywords: insert, update, delete, upsert, merge, or Database.<op>
  # We flag any unguarded DML — i.e., a DML statement where no
  # `Security.stripInaccessible(...)` call appears in the 10 lines above.

  while IFS=: read -r line_no line_content; do
    [ -z "$line_no" ] && continue

    # Look at the 10 lines before this DML
    start=$((line_no > 10 ? line_no - 10 : 1))
    window=$(sed -n "${start},${line_no}p" "$f" 2>/dev/null)
    if ! echo "$window" | grep -qE 'Security\.stripInaccessible'; then
      # Also accept `WITH USER_MODE` on the DML itself (Apex 60+ supports DML in user mode)
      if ! echo "$line_content" | grep -qiE 'AS[[:space:]]+USER'; then
        ISSUES+=("$(jq -n \
          --arg file "$f" \
          --arg line "$line_no" \
          --arg content "$(echo "$line_content" | sed 's/^[[:space:]]*//')" \
          '{
            type: "dml_without_strip_inaccessible",
            file: $file,
            line: ($line | tonumber),
            content: $content,
            severity: "warning",
            note: "DML detected without Security.stripInaccessible above OR AS USER on the DML statement. Override if this DML runs in a system context."
          }')")
      fi
    fi
  done < <(grep -niE '^[[:space:]]*(insert|update|delete|upsert|merge|Database\.(insert|update|delete|upsert|merge))[[:space:]]' "$f" 2>/dev/null || true)

done

# ─── structured result ────────────────────────────────────────────────

ISSUE_COUNT=${#ISSUES[@]}

if [ "$ISSUE_COUNT" -gt 0 ]; then
  ISSUES_JSON=$(printf '%s\n' "${ISSUES[@]}" | jq -s '.')
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
    issue_count: $count,
    issues: $issues
  }' > "$RESULT_FILE"

echo "→ FLS/CRUD check: $STATUS ($ISSUE_COUNT issue(s) across ${#FILES[@]} file(s))"
[ "$ISSUE_COUNT" -gt 0 ] && echo "  Detail: $RESULT_FILE"

exit $EXIT
