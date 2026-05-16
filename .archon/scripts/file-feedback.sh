#!/usr/bin/env bash
#
# file-feedback.sh — open a GitHub Issue on the harness repo with auto-bundled
# engagement context. Invoked by the /sf-feedback slash command. Per ADR-0014.
#
# Usage:
#   bash ~/harness/scripts/file-feedback.sh --text "<free text>"
#   bash ~/harness/scripts/file-feedback.sh --text "<free text>" --ticket GRIM-49
#
# Auto-bundled context (read from the current engagement repo):
#   - engagement_alias       (engagement.yaml)
#   - harness_version        (engagement.yaml; short-SHA used in label)
#   - engagement_repo_url    (git remote get-url origin)
#   - engineer_email         (git config user.email)
#   - current_branch         (git rev-parse --abbrev-ref HEAD)
#   - current_ticket         (from --ticket flag, optional)
#   - timestamp              (UTC, ISO 8601)
#
# Exit codes:
#   0 — issue filed
#   1 — invocation error (missing args, not in an engagement)
#   2 — gh CLI missing or unauthenticated; feedback queued locally
#   3 — GitHub API error; feedback queued locally
#
# Output (stdout, JSON):
#   { "filed": true, "url": "...", "issue_number": N }
#   or
#   { "filed": false, "queued_at": "<path>", "reason": "..." }

set -euo pipefail

# ─── output helpers ────────────────────────────────────────────────────

if [ -t 1 ]; then
  C_RESET=$'\e[0m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_DIM=$'\e[2m'
else
  C_RESET= C_RED= C_GREEN= C_YELLOW= C_DIM=
fi

err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
warn() { printf '%s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
info() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

# ─── arg parsing ───────────────────────────────────────────────────────

FEEDBACK_TEXT=""
TICKET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --text)
      FEEDBACK_TEXT="$2"
      shift 2
      ;;
    --ticket)
      TICKET="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      err "unknown argument: $1"
      exit 1
      ;;
  esac
done

if [ -z "$FEEDBACK_TEXT" ]; then
  err "--text is required"
  exit 1
fi

if [ ${#FEEDBACK_TEXT} -lt 20 ]; then
  err "feedback text must be at least 20 characters (got ${#FEEDBACK_TEXT})"
  exit 1
fi

# Validate ticket format if provided
if [ -n "$TICKET" ] && ! [[ "$TICKET" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
  err "ticket key must match ^[A-Z][A-Z0-9]+-[0-9]+$ (got: $TICKET)"
  exit 1
fi

# ─── locate the engagement repo ────────────────────────────────────────

ENGAGEMENT_DIR="$(pwd)"

if [ ! -f "$ENGAGEMENT_DIR/engagement.yaml" ]; then
  # Walk up to find one
  CHECK_DIR="$ENGAGEMENT_DIR"
  while [ "$CHECK_DIR" != "/" ] && [ "$CHECK_DIR" != "$HOME" ]; do
    CHECK_DIR="$(dirname "$CHECK_DIR")"
    if [ -f "$CHECK_DIR/engagement.yaml" ]; then
      ENGAGEMENT_DIR="$CHECK_DIR"
      break
    fi
  done
fi

if [ ! -f "$ENGAGEMENT_DIR/engagement.yaml" ]; then
  err "not inside an engagement repo (no engagement.yaml found). Run from inside an engagement."
  exit 1
fi

# ─── gather engagement context ─────────────────────────────────────────

ENGAGEMENT_ALIAS=$(grep -E '^engagement_alias:' "$ENGAGEMENT_DIR/engagement.yaml" 2>/dev/null \
  | head -1 | sed -E 's/^engagement_alias:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' \
  || echo "unknown")

HARNESS_VERSION=$(grep -E '^harness_version:' "$ENGAGEMENT_DIR/engagement.yaml" 2>/dev/null \
  | head -1 | sed -E 's/^harness_version:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' \
  || echo "unknown")

# Short SHA for the label (first 7 chars if it looks like a hash; else as-is)
HARNESS_VERSION_SHORT="$HARNESS_VERSION"
if [[ "$HARNESS_VERSION" =~ ^[0-9a-f]{40}$ ]]; then
  HARNESS_VERSION_SHORT="${HARNESS_VERSION:0:7}"
fi

ENGAGEMENT_REPO_URL=$(git -C "$ENGAGEMENT_DIR" remote get-url origin 2>/dev/null || echo "unknown")
ENGINEER_EMAIL=$(git -C "$ENGAGEMENT_DIR" config user.email 2>/dev/null || echo "unknown")
CURRENT_BRANCH=$(git -C "$ENGAGEMENT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ─── build issue title + body ──────────────────────────────────────────

# Title: first sentence of feedback (up to 60 chars), prefixed [feedback]
FIRST_SENTENCE=$(printf '%s' "$FEEDBACK_TEXT" | head -c 200 | tr '\n' ' ' | sed -E 's/^[[:space:]]+//')
TITLE_BODY=$(printf '%s' "$FIRST_SENTENCE" | head -c 60 | sed -E 's/[[:space:]]+$//')
# Truncate at last whole word if we cut in the middle
if [ ${#FIRST_SENTENCE} -gt 60 ]; then
  TITLE_BODY="${TITLE_BODY% *}…"
fi
ISSUE_TITLE="[feedback] $TITLE_BODY"

# Body — multi-line structured markdown
ISSUE_BODY=$(cat <<EOF
**Free-text feedback:**

$FEEDBACK_TEXT

---

**Engagement context** *(auto-bundled by \`file-feedback.sh\`)*

| Field | Value |
|---|---|
| Engagement alias | \`$ENGAGEMENT_ALIAS\` |
| Harness version | \`$HARNESS_VERSION\` |
| Engagement repo | $ENGAGEMENT_REPO_URL |
| Current branch | \`$CURRENT_BRANCH\` |
| Active ticket | ${TICKET:-_None — feedback not tied to a specific run._} |
| Engineer | $ENGINEER_EMAIL |
| Filed at | $TIMESTAMP (UTC) |

---

🤖 Filed via \`/sf-feedback\` from the \`$ENGAGEMENT_ALIAS\` engagement.
EOF
)

# ─── pre-flight: gh CLI available + authenticated? ─────────────────────

GH_OK=0
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    GH_OK=1
  fi
fi

if [ "$GH_OK" -eq 0 ]; then
  # Queue locally and exit 2
  QUEUE_DIR="$HOME/.archon/pending-feedback"
  mkdir -p "$QUEUE_DIR"
  QUEUE_FILE="$QUEUE_DIR/$(date -u +%Y-%m-%dT%H-%M-%SZ).md"
  {
    echo "# Pending feedback — file when gh CLI is available"
    echo ""
    echo "**Title:** $ISSUE_TITLE"
    echo ""
    echo "$ISSUE_BODY"
    echo ""
    echo "---"
    echo ""
    echo "When ready, file with:"
    echo ""
    echo '```bash'
    echo "gh issue create --repo CreativLLC/archon-salesforce-jira \\"
    echo "  --label 'feedback,harness-version:$HARNESS_VERSION_SHORT' \\"
    echo "  --title '$ISSUE_TITLE' \\"
    echo "  --body-file '$QUEUE_FILE'"
    echo '```'
  } > "$QUEUE_FILE"

  warn "gh CLI not available or not authenticated."
  info "  Feedback queued at: $QUEUE_FILE"
  info "  Fix gh: run 'gh auth login' and refile from the queue file above."

  printf '{"filed": false, "queued_at": "%s", "reason": "gh CLI missing or unauthenticated"}\n' "$QUEUE_FILE"
  exit 2
fi

# ─── file the issue ────────────────────────────────────────────────────

LABEL_LIST="feedback"
if [ -n "$HARNESS_VERSION_SHORT" ] && [ "$HARNESS_VERSION_SHORT" != "unknown" ]; then
  LABEL_LIST="$LABEL_LIST,harness-version:$HARNESS_VERSION_SHORT"
fi

# Use a temp file for the body to avoid shell-escaping issues
BODY_TMPFILE=$(mktemp)
printf '%s\n' "$ISSUE_BODY" > "$BODY_TMPFILE"

if ! ISSUE_URL=$(gh issue create \
  --repo CreativLLC/archon-salesforce-jira \
  --label "$LABEL_LIST" \
  --title "$ISSUE_TITLE" \
  --body-file "$BODY_TMPFILE" 2>&1); then

  err "gh issue create failed:"
  err "  $ISSUE_URL"
  rm -f "$BODY_TMPFILE"

  # Queue for later
  QUEUE_DIR="$HOME/.archon/pending-feedback"
  mkdir -p "$QUEUE_DIR"
  QUEUE_FILE="$QUEUE_DIR/$(date -u +%Y-%m-%dT%H-%M-%SZ).md"
  printf '# Failed feedback filing\n\n**Title:** %s\n\n%s\n' "$ISSUE_TITLE" "$ISSUE_BODY" > "$QUEUE_FILE"

  printf '{"filed": false, "queued_at": "%s", "reason": "gh issue create failed"}\n' "$QUEUE_FILE"
  exit 3
fi

rm -f "$BODY_TMPFILE"

# Parse issue number from the URL (gh issue create prints the URL on success)
ISSUE_NUMBER=$(printf '%s' "$ISSUE_URL" | grep -oE '/issues/[0-9]+' | grep -oE '[0-9]+$' || echo "")

ok "Feedback filed: $ISSUE_URL"

printf '{"filed": true, "url": "%s", "issue_number": %s}\n' "$ISSUE_URL" "${ISSUE_NUMBER:-null}"
exit 0
