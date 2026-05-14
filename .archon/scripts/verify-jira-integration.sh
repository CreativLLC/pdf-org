#!/usr/bin/env bash
#
# verify-jira-integration.sh — Phase 3 Layer-1 verification
#
# Proves that the engineer's Jira credentials and target ticket are
# correctly configured by exercising the full read → comment → transition
# round-trip against the Jira REST API directly (no MCP server required).
#
# Usage:
#   ./verify-jira-integration.sh <TICKET-KEY>
#
# Reads from environment (or sourced from .env):
#   JIRA_URL          — required, e.g. https://your-firm.atlassian.net
#   JIRA_USERNAME     — required, your Atlassian email
#   JIRA_API_TOKEN    — required, generated at id.atlassian.com
#
# Exit codes:
#   0  — all checks passed
#   1  — invalid invocation (missing arg, missing env)
#   2  — auth failed
#   3  — ticket read failed
#   4  — comment post failed
#   5  — transition fetch failed
#   6  — transition apply failed
#   7  — post-transition verification failed
#
# What it does NOT do:
#   - Install or invoke the MCP server. That's Layer 2 (interactive).
#   - Modify the ticket beyond posting one verification comment and
#     applying one round-trip transition.

set -euo pipefail

# ─── arg parsing ──────────────────────────────────────────────────────

if [ $# -ne 1 ]; then
  echo "usage: $0 <TICKET-KEY>" >&2
  echo "example: $0 HARN-1" >&2
  exit 1
fi

TICKET="$1"

if ! [[ "$TICKET" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
  echo "error: '$TICKET' doesn't look like a Jira ticket key (expected PROJ-N format)" >&2
  exit 1
fi

# ─── env loading ──────────────────────────────────────────────────────

# Source .env if present in the current directory (engagement-repo convention)
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  set -a
  source .env
  set +a
fi

# Validate required vars
: "${JIRA_URL:?error: JIRA_URL not set (export it or put it in .env)}"
: "${JIRA_USERNAME:?error: JIRA_USERNAME not set (export it or put it in .env)}"
: "${JIRA_API_TOKEN:?error: JIRA_API_TOKEN not set (export it or put it in .env)}"

# Strip trailing slash from JIRA_URL for clean concatenation
JIRA_URL="${JIRA_URL%/}"

# ─── helpers ──────────────────────────────────────────────────────────

# curl wrapper with auth, JSON, and silent-but-show-errors
jcurl() {
  curl --silent --show-error --fail-with-body \
    -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
    -H "Accept: application/json" \
    "$@"
}

# Like jcurl but for POST/PUT with JSON body
jcurl_json() {
  jcurl -H "Content-Type: application/json" "$@"
}

# Pretty step header
step() {
  echo ""
  echo "── $* ──"
}

# Success message
ok() {
  echo "  ✓ $*"
}

# Failure message + exit
fail() {
  local code="$1"
  shift
  echo "  ✗ $*" >&2
  exit "$code"
}

# ─── 1. JIRA_URL reachable ────────────────────────────────────────────

step "1. JIRA_URL is reachable"

if ! curl --silent --fail --head --max-time 10 "$JIRA_URL" >/dev/null 2>&1; then
  fail 1 "cannot reach $JIRA_URL — check the URL and your network"
fi
ok "$JIRA_URL responds"

# ─── 2. auth works (/myself) ──────────────────────────────────────────

step "2. JIRA_USERNAME + JIRA_API_TOKEN authenticate"

MYSELF=$(jcurl "$JIRA_URL/rest/api/3/myself" 2>&1) || \
  fail 2 "auth failed against /rest/api/3/myself — regenerate your token at id.atlassian.com (HTTP body: $MYSELF)"

ACCOUNT_ID=$(printf '%s' "$MYSELF" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("accountId", ""))' 2>/dev/null || echo "")
DISPLAY_NAME=$(printf '%s' "$MYSELF" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("displayName", ""))' 2>/dev/null || echo "")

[ -n "$ACCOUNT_ID" ] || fail 2 "auth succeeded but response missing accountId — unexpected"
ok "authenticated as $DISPLAY_NAME (accountId=$ACCOUNT_ID)"

# ─── 3. read the test ticket ──────────────────────────────────────────

step "3. Read ticket $TICKET"

ISSUE=$(jcurl "$JIRA_URL/rest/api/3/issue/$TICKET?fields=summary,status" 2>&1) || \
  fail 3 "could not fetch ticket $TICKET — check it exists and you have read access (HTTP body: $ISSUE)"

SUMMARY=$(printf '%s' "$ISSUE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["fields"]["summary"])' 2>/dev/null || echo "<could not parse>")
ORIGINAL_STATUS=$(printf '%s' "$ISSUE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["fields"]["status"]["name"])' 2>/dev/null || echo "<could not parse>")

ok "ticket exists: $TICKET — \"$SUMMARY\""
ok "current status: \"$ORIGINAL_STATUS\""

# ─── 4. post a verification comment ───────────────────────────────────

step "4. Post a verification comment"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMENT_BODY=$(cat <<EOF
{
  "body": {
    "type": "doc",
    "version": 1,
    "content": [
      {
        "type": "paragraph",
        "content": [
          {
            "type": "text",
            "text": "🔧 Phase 3 verification — harness Jira integration round-trip test at $TIMESTAMP. This comment was created automatically by verify-jira-integration.sh; safe to delete."
          }
        ]
      }
    ]
  }
}
EOF
)

COMMENT_RESPONSE=$(jcurl_json -X POST -d "$COMMENT_BODY" "$JIRA_URL/rest/api/3/issue/$TICKET/comment" 2>&1) || \
  fail 4 "could not post comment to $TICKET — check write permissions (HTTP body: $COMMENT_RESPONSE)"

COMMENT_ID=$(printf '%s' "$COMMENT_RESPONSE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["id"])' 2>/dev/null || echo "<could not parse>")
ok "comment posted: id=$COMMENT_ID"

# ─── 5. fetch available transitions ───────────────────────────────────

step "5. Fetch available transitions"

TRANSITIONS=$(jcurl "$JIRA_URL/rest/api/3/issue/$TICKET/transitions" 2>&1) || \
  fail 5 "could not fetch transitions for $TICKET (HTTP body: $TRANSITIONS)"

TRANSITION_NAMES=$(printf '%s' "$TRANSITIONS" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for t in data.get("transitions", []):
    print(f"  {t['id']}: {t['name']} -> {t['to']['name']}")
' 2>/dev/null || echo "<could not parse>")

ok "available transitions from \"$ORIGINAL_STATUS\":"
printf '%s\n' "$TRANSITION_NAMES" | sed 's/^/    /'

# Pick the first transition that goes to a status DIFFERENT from current
FIRST_TRANSITION=$(printf '%s' "$TRANSITIONS" | python3 -c '
import sys, json
data = json.load(sys.stdin)
current = "'"$ORIGINAL_STATUS"'"
for t in data.get("transitions", []):
    if t["to"]["name"] != current:
        print(json.dumps({"id": t["id"], "name": t["name"], "to": t["to"]["name"]}))
        break
' 2>/dev/null || echo "")

if [ -z "$FIRST_TRANSITION" ]; then
  echo ""
  echo "  ⚠  No transitions available that would change the status."
  echo "     The round-trip transition test will be skipped."
  echo "     This usually means the ticket is in a terminal state or the workflow"
  echo "     requires a screen/field that this script doesn't fill in."
  TRANSITION_SKIPPED=1
else
  TRANSITION_SKIPPED=0
fi

# ─── 6. apply a transition (if available) ─────────────────────────────

if [ "$TRANSITION_SKIPPED" -eq 0 ]; then
  step "6. Apply a transition (round-trip test)"

  TRANSITION_ID=$(printf '%s' "$FIRST_TRANSITION" | python3 -c 'import sys, json; print(json.load(sys.stdin)["id"])')
  TRANSITION_NAME=$(printf '%s' "$FIRST_TRANSITION" | python3 -c 'import sys, json; print(json.load(sys.stdin)["name"])')
  TRANSITION_TO=$(printf '%s' "$FIRST_TRANSITION" | python3 -c 'import sys, json; print(json.load(sys.stdin)["to"])')

  TRANSITION_BODY="{\"transition\": {\"id\": \"$TRANSITION_ID\"}}"

  TRANSITION_RESPONSE=$(jcurl_json -X POST -d "$TRANSITION_BODY" "$JIRA_URL/rest/api/3/issue/$TICKET/transitions" 2>&1) || \
    fail 6 "transition '$TRANSITION_NAME' failed — Jira may require a screen/field for this transition (HTTP body: $TRANSITION_RESPONSE)"

  ok "applied transition: \"$TRANSITION_NAME\" → \"$TRANSITION_TO\""

  # ── 7. verify the new status sticks ─────────────────────────────────

  step "7. Verify post-transition state"

  ISSUE_AFTER=$(jcurl "$JIRA_URL/rest/api/3/issue/$TICKET?fields=status" 2>&1) || \
    fail 7 "could not re-fetch ticket after transition"

  NEW_STATUS=$(printf '%s' "$ISSUE_AFTER" | python3 -c 'import sys, json; print(json.load(sys.stdin)["fields"]["status"]["name"])' 2>/dev/null || echo "<could not parse>")

  if [ "$NEW_STATUS" != "$TRANSITION_TO" ]; then
    fail 7 "expected post-transition status '$TRANSITION_TO', got '$NEW_STATUS'"
  fi
  ok "post-transition status: \"$NEW_STATUS\""

  # ── 8. round-trip back to original status (if possible) ─────────────

  step "8. Round-trip back to original status (\"$ORIGINAL_STATUS\")"

  REVERSE_TRANSITIONS=$(jcurl "$JIRA_URL/rest/api/3/issue/$TICKET/transitions" 2>&1) || \
    fail 6 "could not fetch transitions for reverse-trip"

  REVERSE_TRANSITION_ID=$(printf '%s' "$REVERSE_TRANSITIONS" | python3 -c '
import sys, json
data = json.load(sys.stdin)
target = "'"$ORIGINAL_STATUS"'"
for t in data.get("transitions", []):
    if t["to"]["name"] == target:
        print(t["id"])
        break
' 2>/dev/null || echo "")

  if [ -z "$REVERSE_TRANSITION_ID" ]; then
    echo "  ⚠  No transition back to \"$ORIGINAL_STATUS\" is available from \"$NEW_STATUS\"."
    echo "     The ticket is left in \"$NEW_STATUS\". You may want to move it back manually."
  else
    REVERSE_BODY="{\"transition\": {\"id\": \"$REVERSE_TRANSITION_ID\"}}"
    # Jira's transition endpoint returns HTTP 204 No Content on success — empty body.
    # Branch on curl's exit code (jcurl_json uses --fail-with-body), not response body.
    if jcurl_json -X POST -d "$REVERSE_BODY" "$JIRA_URL/rest/api/3/issue/$TICKET/transitions" >/dev/null 2>&1; then
      ok "reversed: status back to \"$ORIGINAL_STATUS\""
    else
      echo "  ⚠  Could not reverse-transition (the ticket is left in \"$NEW_STATUS\")"
    fi
  fi
fi

# ─── done ─────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Layer-1 Jira verification: PASSED"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  Authenticated as:  $DISPLAY_NAME"
echo "  Ticket exercised:  $TICKET"
echo "  Verification comment posted (id $COMMENT_ID — safe to delete)"
if [ "$TRANSITION_SKIPPED" -eq 0 ]; then
  echo "  Round-trip transitioned through \"$NEW_STATUS\" and back"
fi
echo ""
echo "  Layer-2 verification (interactive, requires MCP):"
echo "  1. Install uv:   curl -LsSf https://astral.sh/uv/install.sh | sh"
echo "  2. Register the mcp-atlassian MCP in your Claude Code config"
echo "     (see decisions/0007-jira-mcp-integration.md)"
echo "  3. In Claude Code, ask: \"Using mcp-atlassian, get ticket $TICKET and summarize it.\""
echo "  4. A correct summary confirms the MCP integration end-to-end."
echo ""
