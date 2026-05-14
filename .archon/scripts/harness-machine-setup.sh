#!/usr/bin/env bash
#
# harness-machine-setup.sh — Stage 1 of the bootstrap workflow
#
# Verifies that the engineer's machine has everything required to run harness
# workflows: tools, VSCode extensions, authentications, network reachability,
# dev hub configuration, and the direnv-based credential infrastructure.
#
# Idempotent: safe to re-run any time. Re-run after any tool upgrade or
# re-authentication.
#
# Usage:
#   ./harness-machine-setup.sh
#
# Exit codes:
#   0  — all checks passed; ~/.archon/machine-state.json written.
#   1  — invalid invocation or unexpected error.
#   2  — one or more required tools missing.
#   3  — one or more required VSCode extensions missing.
#   4  — authentication or network failure.
#   5  — dev hub or scratch-org configuration failure.
#   6  — direnv shell hook not installed.
#
# This script never modifies external state. It only inspects and reports.
# (The one exception: it creates ~/.archon/credentials/ with chmod 700 if missing.)
#
# References:
#   - decisions/0006-bootstrap-workflow-design.md  (the design contract)
#   - decisions/0008-credential-management.md      (the direnv requirement)

set -euo pipefail

# ─── output helpers ───────────────────────────────────────────────────

if [ -t 1 ]; then
  C_RESET=$'\e[0m'
  C_RED=$'\e[31m'
  C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'
  C_BLUE=$'\e[34m'
  C_BOLD=$'\e[1m'
  C_DIM=$'\e[2m'
else
  C_RESET= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_BOLD= C_DIM=
fi

section() {
  printf '\n%s── %s ──%s\n' "$C_BOLD" "$*" "$C_RESET"
}

ok() {
  printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

warn() {
  printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*"
  FAILURES=$((FAILURES + 1))
  if [ -n "${1+x}" ] && [ -n "${2:-}" ]; then
    printf '    %sFix:%s %s\n' "$C_DIM" "$C_RESET" "$2"
  fi
}

fail_with_fix() {
  printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1"
  printf '    %sFix:%s %s\n' "$C_DIM" "$C_RESET" "$2"
  FAILURES=$((FAILURES + 1))
}

info() {
  printf '  %sℹ%s %s\n' "$C_BLUE" "$C_RESET" "$*"
}

# ─── state ────────────────────────────────────────────────────────────

FAILURES=0
WARNINGS=0
CHECKS_RUN=()
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_VERSION="$(cd "$HARNESS_DIR" && git describe --tags --always 2>/dev/null || echo "unknown")"

# ─── banner ───────────────────────────────────────────────────────────

cat <<EOF
${C_BOLD}harness-machine-setup${C_RESET} — Stage 1 of the harness bootstrap

This script verifies your machine is ready to run harness workflows. It
inspects tools, auth, and network — it does NOT install anything.

If a check fails, the message tells you exactly what to install or fix.
Re-run this script after fixing.

Harness:        $HARNESS_DIR
Harness version: $HARNESS_VERSION
EOF

# ─── 1. tools ─────────────────────────────────────────────────────────

check_tool() {
  local name="$1"
  local test_cmd="$2"
  local install_hint="$3"

  if eval "$test_cmd" >/dev/null 2>&1; then
    local version
    version=$(eval "$test_cmd" 2>&1 | head -1)
    ok "$name — $version"
    CHECKS_RUN+=("tool:$name:pass")
  else
    fail_with_fix "$name not installed or not on PATH" "$install_hint"
    CHECKS_RUN+=("tool:$name:fail")
  fi
}

section "1. Tools"

check_tool "git"     "git --version"     "Install via Xcode CLT (\`xcode-select --install\`) or \`brew install git\`."
check_tool "gh"      "gh --version"      "Install GitHub CLI: \`brew install gh\` (macOS) or see https://cli.github.com."
check_tool "bun"     "bun --version"     "Install Bun: \`curl -fsSL https://bun.sh/install | bash\`. Required by Archon."
check_tool "sf"      "sf --version"      "Install Salesforce CLI v2+: \`npm install -g @salesforce/cli\` or \`brew install salesforce-cli\`."
check_tool "claude"  "claude --version"  "Install Claude Code: \`curl -fsSL https://claude.ai/install.sh | bash\` or download from https://claude.ai/code."
check_tool "code"    "code --version"    "Install VSCode CLI: in VSCode, run Command Palette → \"Shell Command: Install 'code' command in PATH\"."
check_tool "uv"      "uv --version"      "Install uv: \`curl -LsSf https://astral.sh/uv/install.sh | sh\`. Required to run the Jira MCP server (ADR-0007)."
check_tool "direnv"  "direnv version"    "Install direnv: \`brew install direnv\`. Required for credential management (ADR-0008)."

# Salesforce CLI must be v2+
if command -v sf >/dev/null 2>&1; then
  SF_MAJOR=$(sf --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
  if [ -n "$SF_MAJOR" ] && [ "$SF_MAJOR" -lt 2 ]; then
    fail_with_fix "Salesforce CLI is v$SF_MAJOR; v2+ required" "Upgrade: \`sf update\` or reinstall."
  fi
fi

# ─── 2. VSCode extensions ─────────────────────────────────────────────

check_extension() {
  local ext_id="$1"

  if [ -z "${VSCODE_EXTENSIONS_LIST+x}" ]; then
    VSCODE_EXTENSIONS_LIST=$(code --list-extensions 2>/dev/null || echo "")
  fi

  if printf '%s\n' "$VSCODE_EXTENSIONS_LIST" | grep -qix "$ext_id"; then
    ok "$ext_id"
    CHECKS_RUN+=("ext:$ext_id:pass")
  else
    fail_with_fix "VSCode extension '$ext_id' not installed" "Install: \`code --install-extension $ext_id\`"
    CHECKS_RUN+=("ext:$ext_id:fail")
  fi
}

section "2. VSCode extensions"

if ! command -v code >/dev/null 2>&1; then
  warn "Skipping extension checks — \`code\` CLI not on PATH."
else
  check_extension "salesforce.salesforcedx-vscode"
  check_extension "salesforce.salesforcedx-vscode-core"
  check_extension "salesforce.salesforcedx-vscode-apex"
  check_extension "salesforce.salesforcedx-vscode-lwc"
  check_extension "salesforce.salesforcedx-vscode-visualforce"
fi

# ─── 3. Authentication ────────────────────────────────────────────────

section "3. Authentication"

# GitHub
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    GH_USER=$(gh api user --jq .login 2>/dev/null || echo "?")
    ok "GitHub CLI authenticated as $GH_USER"
    CHECKS_RUN+=("auth:gh:pass")
  else
    fail_with_fix "GitHub CLI not authenticated" "Run: \`gh auth login\`"
    CHECKS_RUN+=("auth:gh:fail")
  fi
fi

# Salesforce — at least one org authorized
if command -v sf >/dev/null 2>&1; then
  SF_ORGS_JSON=$(sf org list --json 2>/dev/null || echo '{}')
  SF_ORG_COUNT=$(printf '%s' "$SF_ORGS_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    result = data.get("result", {})
    count = len(result.get("nonScratchOrgs", [])) + len(result.get("scratchOrgs", []))
    print(count)
except Exception:
    print(0)
' 2>/dev/null || echo 0)
  if [ "$SF_ORG_COUNT" -gt 0 ]; then
    ok "Salesforce CLI has $SF_ORG_COUNT authorized org(s)"
    CHECKS_RUN+=("auth:sf:pass")
  else
    fail_with_fix "Salesforce CLI has no authorized orgs" "Run: \`sf org login web --alias <some-alias>\`"
    CHECKS_RUN+=("auth:sf:fail")
  fi
fi

# Dev Hub (required for source_tracked dev model)
if command -v sf >/dev/null 2>&1 && [ "${SF_ORG_COUNT:-0}" -gt 0 ]; then
  DEV_HUB_COUNT=$(printf '%s' "$SF_ORGS_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    result = data.get("result", {})
    non = result.get("nonScratchOrgs", [])
    devhubs = [o for o in non if o.get("isDevHub")]
    print(len(devhubs))
except Exception:
    print(0)
' 2>/dev/null || echo 0)
  if [ "$DEV_HUB_COUNT" -gt 0 ]; then
    ok "Dev Hub authorized ($DEV_HUB_COUNT org(s))"
    CHECKS_RUN+=("auth:devhub:pass")
  else
    warn "No Dev Hub authorized — required if you use the source_tracked dev model (scratch orgs)."
    info "Authorize with: \`sf org login web --alias <devhub-alias> --set-default-dev-hub\`"
    CHECKS_RUN+=("auth:devhub:warn")
  fi
fi

# ─── 4. Network reachability ──────────────────────────────────────────

check_url() {
  local label="$1"
  local url="$2"

  if curl --silent --head --fail --max-time 10 "$url" >/dev/null 2>&1; then
    ok "$label reachable ($url)"
    CHECKS_RUN+=("net:$label:pass")
  else
    fail_with_fix "$label not reachable ($url)" "Check your network, VPN, or firewall."
    CHECKS_RUN+=("net:$label:fail")
  fi
}

section "4. Network reachability"

check_url "Salesforce login (prod)" "https://login.salesforce.com"
check_url "Salesforce login (test)" "https://test.salesforce.com"
check_url "Atlassian (id)"          "https://id.atlassian.com"
check_url "GitHub API"              "https://api.github.com"
check_url "Astral (uv installer)"   "https://astral.sh"

# ─── 5. direnv shell hook ─────────────────────────────────────────────

section "5. direnv shell hook"

if ! command -v direnv >/dev/null 2>&1; then
  warn "Skipping — direnv binary check already failed above."
else
  # Detect shell rc
  case "${SHELL##*/}" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
    *)    RC_FILE="" ;;
  esac

  if [ -z "$RC_FILE" ] || [ ! -f "$RC_FILE" ]; then
    warn "Could not detect a shell rc file for $SHELL — verify direnv hook manually."
  elif grep -q 'direnv hook' "$RC_FILE"; then
    ok "direnv hook present in $RC_FILE"
    CHECKS_RUN+=("direnv:hook:pass")
  else
    fail_with_fix "direnv hook not installed in $RC_FILE" "Run: \`echo 'eval \"\$(direnv hook ${SHELL##*/})\"' >> $RC_FILE && source $RC_FILE\`"
    CHECKS_RUN+=("direnv:hook:fail")
  fi
fi

# ─── 6. credentials directory ─────────────────────────────────────────

section "6. Credentials directory"

CRED_ROOT="$HOME/.archon/credentials"
if [ ! -d "$CRED_ROOT" ]; then
  mkdir -p "$CRED_ROOT"
  chmod 700 "$CRED_ROOT"
  ok "Created $CRED_ROOT (chmod 700)"
else
  PERMS=$(stat -f '%Lp' "$CRED_ROOT" 2>/dev/null || stat -c '%a' "$CRED_ROOT" 2>/dev/null || echo "?")
  if [ "$PERMS" = "700" ]; then
    ok "$CRED_ROOT exists (chmod 700)"
  else
    warn "$CRED_ROOT permissions are $PERMS; recommended 700. Fix: \`chmod 700 $CRED_ROOT\`"
  fi
fi

# A safety gitignore
if [ ! -f "$CRED_ROOT/.gitignore" ]; then
  printf '*\n' > "$CRED_ROOT/.gitignore"
  ok "Wrote $CRED_ROOT/.gitignore (* — defends against accidental commit if this dir ever lands in a repo)"
fi
CHECKS_RUN+=("creds_dir:pass")

# ─── final report ─────────────────────────────────────────────────────

printf '\n%s════════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_RESET"
if [ "$FAILURES" -eq 0 ]; then
  printf '%s  Machine ready ✓%s    %d checks passed' "$C_GREEN$C_BOLD" "$C_RESET" "${#CHECKS_RUN[@]}"
  [ "$WARNINGS" -gt 0 ] && printf ' (%d warning(s))' "$WARNINGS"
  printf '\n'
else
  printf '%s  Not ready ✗%s        %d failure(s), %d warning(s)\n' "$C_RED$C_BOLD" "$C_RESET" "$FAILURES" "$WARNINGS"
fi
printf '%s════════════════════════════════════════════════════════════════%s\n\n' "$C_BOLD" "$C_RESET"

# Write machine state file
mkdir -p "$HOME/.archon"
STATE_FILE="$HOME/.archon/machine-state.json"

cat > "$STATE_FILE" <<EOF
{
  "verified_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "harness_version": "$HARNESS_VERSION",
  "harness_dir": "$HARNESS_DIR",
  "shell": "${SHELL##*/}",
  "failures": $FAILURES,
  "warnings": $WARNINGS,
  "checks_run": ${#CHECKS_RUN[@]},
  "ready": $([ "$FAILURES" -eq 0 ] && echo true || echo false)
}
EOF
chmod 600 "$STATE_FILE"

if [ "$FAILURES" -eq 0 ]; then
  printf 'State recorded: %s\n\n' "$STATE_FILE"
  printf 'Next: when you have a new engagement to set up, run:\n'
  printf '  %s./harness-init.sh%s   (from the engagement repo root)\n\n' "$C_BOLD" "$C_RESET"
  exit 0
else
  printf '%sNo state recorded.%s Fix the failures above and re-run this script.\n\n' "$C_DIM" "$C_RESET"
  # Exit code by what failed
  for chk in "${CHECKS_RUN[@]}"; do
    case "$chk" in
      tool:*:fail) exit 2 ;;
    esac
  done
  for chk in "${CHECKS_RUN[@]}"; do
    case "$chk" in
      ext:*:fail) exit 3 ;;
    esac
  done
  for chk in "${CHECKS_RUN[@]}"; do
    case "$chk" in
      auth:*:fail|net:*:fail) exit 4 ;;
    esac
  done
  for chk in "${CHECKS_RUN[@]}"; do
    case "$chk" in
      direnv:hook:fail) exit 6 ;;
    esac
  done
  exit 1
fi
