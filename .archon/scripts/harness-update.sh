#!/usr/bin/env bash
#
# harness-update.sh — Phase 6.5 MVP
#
# Updates an existing engagement's harness content to a newer harness version.
# Implements the update half of the ADR-0002 install model. Run from inside an
# engagement repo that was previously bootstrapped via harness-init.sh.
#
# What it overwrites (harness-supplied content; safe to refresh):
#   .archon/workflows/         — workflow YAMLs
#   .archon/commands/          — command markdown prompts
#   .archon/scripts/           — validation/utility scripts
#   .archon/patterns/          — team-canon pattern library
#   .archon/standards/         — team-canon standards
#   docs/.harness-templates/   — doc-type templates
#
# What it adds (only if missing; never overwrites):
#   .claude/commands/<name>.md — Claude Code slash commands from harness templates
#   .claude/skills/<name>/     — Claude Code agentic skills from harness templates
#
# What it touches MINIMALLY:
#   engagement.yaml            — only the `harness_version:` line is rewritten;
#                                everything else (engagement-specific config) preserved
#
# What it leaves ALONE entirely:
#   .envrc, .mcp.json, CLAUDE.md, .gitignore     (engagement-specific or user-edited)
#   docs/<any-subdir>/<any-file>.md              (engagement-authored docs)
#   docs/_internal/                              (internal notes, gitignored)
#   force-app/, manifest/, config/, sfdx-project.json, package.json, etc.
#
# Usage:
#   cd <engagement-repo>
#   <path-to-harness>/scripts/harness-update.sh                # interactive
#   <path-to-harness>/scripts/harness-update.sh --force        # allow downgrade
#   <path-to-harness>/scripts/harness-update.sh --yes          # skip the confirm prompt
#
# Exit codes:
#   0 — update applied
#   1 — invalid invocation / not in an engagement repo
#   2 — refusing to downgrade (no --force)
#   3 — user declined at confirmation prompt
#   4 — re-copy failed

set -euo pipefail

# ─── output helpers (mirror of Stage 1/2) ─────────────────────────────

if [ -t 1 ]; then
  C_RESET=$'\e[0m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
  C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
else
  C_RESET= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_BOLD= C_DIM=
fi

section() { printf '\n%s── %s ──%s\n' "$C_BOLD" "$*" "$C_RESET"; }
ok()      { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()     { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
info()    { printf '  %s%s\n' "$C_DIM" "$*$C_RESET"; }

# ─── arg parsing ──────────────────────────────────────────────────────

FORCE=0
SKIP_CONFIRM=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --yes|-y) SKIP_CONFIRM=1 ;;
    --help|-h)
      sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      err "unknown argument: $arg"
      exit 1
      ;;
  esac
done

# ─── locate harness and engagement ────────────────────────────────────

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGAGEMENT_DIR="$(pwd)"

if [ ! -f "$ENGAGEMENT_DIR/engagement.yaml" ]; then
  err "no engagement.yaml at $ENGAGEMENT_DIR"
  info "run from inside an engagement repo that was bootstrapped via harness-init.sh."
  exit 1
fi

NEW_VERSION="$(cd "$HARNESS_DIR" && git describe --tags --always 2>/dev/null || echo "0.0.0-dev")"

# Pull current version out of engagement.yaml. Tolerant grep — accepts both
# `harness_version: "0.4.2"` and `harness_version: 0.4.2`.
CURRENT_VERSION="$(grep -E '^harness_version:' "$ENGAGEMENT_DIR/engagement.yaml" \
  | head -1 \
  | sed -E 's/^harness_version:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/')"

if [ -z "$CURRENT_VERSION" ]; then
  err "couldn't find a 'harness_version:' line in engagement.yaml"
  info "engagement.yaml may be from a pre-Phase-2 bootstrap. Inspect and add harness_version manually."
  exit 1
fi

# ─── version comparison ───────────────────────────────────────────────

section "Versions"
info "Harness:      $HARNESS_DIR"
info "Engagement:   $ENGAGEMENT_DIR"
echo ""
printf "  Current:  %s\n" "$CURRENT_VERSION"
printf "  New:      %s\n" "$NEW_VERSION"

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
  ok "engagement is already on $NEW_VERSION — re-copy will refresh files but contents are unchanged"
fi

# We can't reliably semver-compare without tags, so we ask the user to confirm
# unless --force was passed. With tags, future improvement: parse and compare.

# ─── what will change (dry-summary) ────────────────────────────────────

section "What this update will do"

cat <<EOF
  Overwrite (harness-supplied content):
    .archon/workflows/          .archon/scripts/
    .archon/commands/           .archon/patterns/
    .archon/standards/          docs/.harness-templates/

  Add (only files that don't already exist):
    .claude/commands/<name>.md
    .claude/skills/<name>/

  Rewrite ONE line of engagement.yaml:
    harness_version: "$CURRENT_VERSION" → harness_version: "$NEW_VERSION"

  Leave alone:
    .envrc, .mcp.json, CLAUDE.md, .gitignore
    docs/<subdir>/<any-engagement-authored-doc>.md
    docs/_internal/
    force-app/, manifest/, config/, etc. (SFDX content)
EOF

# ─── confirm ───────────────────────────────────────────────────────────

if [ "$SKIP_CONFIRM" -eq 0 ]; then
  echo ""
  printf "  %sProceed?%s [y/N] " "$C_BOLD" "$C_RESET"
  read -r REPLY
  case "$(printf '%s' "$REPLY" | tr '[:upper:]' '[:lower:]')" in
    y|yes) ;;
    *)
      info "Aborted."
      exit 3 ;;
  esac
fi

# ─── do the update ─────────────────────────────────────────────────────

section "Re-copying harness content"

CHANGED=0

# .archon/<subdir>/  — always overwrite
mkdir -p "$ENGAGEMENT_DIR/.archon"
for subdir in workflows commands scripts patterns standards; do
  if [ -d "$HARNESS_DIR/$subdir" ]; then
    rm -rf "$ENGAGEMENT_DIR/.archon/$subdir"
    cp -R "$HARNESS_DIR/$subdir" "$ENGAGEMENT_DIR/.archon/$subdir"
    ok "Refreshed .archon/$subdir/"
    CHANGED=1
  fi
done

# docs/.harness-templates/  — always overwrite
if [ -d "$HARNESS_DIR/docs-templates" ]; then
  rm -rf "$ENGAGEMENT_DIR/docs/.harness-templates"
  cp -R "$HARNESS_DIR/docs-templates" "$ENGAGEMENT_DIR/docs/.harness-templates"
  ok "Refreshed docs/.harness-templates/"
  CHANGED=1
fi

# .claude/commands/  — add new only
if [ -d "$HARNESS_DIR/claude-templates/commands" ]; then
  mkdir -p "$ENGAGEMENT_DIR/.claude/commands"
  for src in "$HARNESS_DIR/claude-templates/commands/"*.md; do
    [ -f "$src" ] || continue
    base=$(basename "$src")
    [ "$base" = "README.md" ] && continue
    dest="$ENGAGEMENT_DIR/.claude/commands/$base"
    if [ -f "$dest" ]; then
      info "(kept existing .claude/commands/$base)"
    else
      cp "$src" "$dest"
      ok "Added .claude/commands/$base"
      CHANGED=1
    fi
  done
fi

# .claude/skills/<dir>/  — add new only
if [ -d "$HARNESS_DIR/claude-templates/skills" ]; then
  mkdir -p "$ENGAGEMENT_DIR/.claude/skills"
  for skill_dir in "$HARNESS_DIR/claude-templates/skills/"*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    if [ -d "$ENGAGEMENT_DIR/.claude/skills/$skill_name" ]; then
      info "(kept existing .claude/skills/$skill_name/)"
    else
      cp -R "$skill_dir" "$ENGAGEMENT_DIR/.claude/skills/$skill_name"
      ok "Added .claude/skills/$skill_name/"
      CHANGED=1
    fi
  done
fi

# ─── docs site config — add new files only (ADR-0010) ────────────────
#
# MkDocs Material + GitHub Pages auto-deploy. Added in v0.5+ per
# ADR-0010 (decisions/0010-engagement-documentation-model.md). For
# engagements bootstrapped before this version, harness-update copies
# the files if they're missing — but never overwrites existing ones.

EXAMPLE_ROOT="$HARNESS_DIR/examples/engagement"

# mkdocs.yml
if [ -f "$EXAMPLE_ROOT/mkdocs.yml" ]; then
  if [ -f "$ENGAGEMENT_DIR/mkdocs.yml" ]; then
    info "(kept existing mkdocs.yml — review against $EXAMPLE_ROOT/mkdocs.yml manually if drift)"
  else
    # Derive GH org/repo from origin, else use placeholders
    GH_ORG="<github-org>"
    GH_REPO="<engagement-repo>"
    if git -C "$ENGAGEMENT_DIR" remote get-url origin >/dev/null 2>&1; then
      ORIGIN_URL=$(git -C "$ENGAGEMENT_DIR" remote get-url origin)
      if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        GH_ORG="${BASH_REMATCH[1]}"
        GH_REPO="${BASH_REMATCH[2]}"
      fi
    fi
    # Try to read client_name from engagement.yaml
    CLIENT_NAME=$(grep -E '^client_name:' "$ENGAGEMENT_DIR/engagement.yaml" 2>/dev/null \
      | head -1 | sed -E 's/^client_name:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' \
      || echo "<Client Name>")
    sed \
      -e "s|<Client Name>|$CLIENT_NAME|g" \
      -e "s|<github-org>|$GH_ORG|g" \
      -e "s|<engagement-repo>|$GH_REPO|g" \
      "$EXAMPLE_ROOT/mkdocs.yml" > "$ENGAGEMENT_DIR/mkdocs.yml"
    ok "Added mkdocs.yml (client: $CLIENT_NAME, repo: $GH_ORG/$GH_REPO)"
    CHANGED=1
  fi
fi

# requirements-docs.txt
if [ -f "$EXAMPLE_ROOT/requirements-docs.txt" ] && [ ! -f "$ENGAGEMENT_DIR/requirements-docs.txt" ]; then
  cp "$EXAMPLE_ROOT/requirements-docs.txt" "$ENGAGEMENT_DIR/requirements-docs.txt"
  ok "Added requirements-docs.txt"
  CHANGED=1
fi

# .github/workflows/docs-deploy.yml
if [ -f "$EXAMPLE_ROOT/.github/workflows/docs-deploy.yml" ] && [ ! -f "$ENGAGEMENT_DIR/.github/workflows/docs-deploy.yml" ]; then
  mkdir -p "$ENGAGEMENT_DIR/.github/workflows"
  cp "$EXAMPLE_ROOT/.github/workflows/docs-deploy.yml" "$ENGAGEMENT_DIR/.github/workflows/docs-deploy.yml"
  ok "Added .github/workflows/docs-deploy.yml"
  info "  → after the next push to main, enable GitHub Pages in repo Settings → Pages → 'Source: GitHub Actions'."
  CHANGED=1
fi

# docs/index.md — only add if missing (engagement may have written its own).
if [ ! -f "$ENGAGEMENT_DIR/docs/index.md" ] && [ -f "$EXAMPLE_ROOT/docs/index.md" ]; then
  # Use a minimal scaffold rather than copying Acme's filled-out exemplar
  CLIENT_NAME=$(grep -E '^client_name:' "$ENGAGEMENT_DIR/engagement.yaml" 2>/dev/null \
    | head -1 | sed -E 's/^client_name:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' \
    || echo "engagement")
  cat > "$ENGAGEMENT_DIR/docs/index.md" <<EOF
---
title: $CLIENT_NAME — Engagement Documentation Index
audience: public
last_updated: $(date -u +%Y-%m-%d)
last_updated_by: harness-update
related_tickets: []
related_docs: [README.md]
---

# $CLIENT_NAME — Engagement Documentation Index

> **For AI agents:** load this file first; load specific subset docs from the index below per ADR-0010.

## Object index
*(Empty — \`/sf\` runs will populate.)*

## Feature index
*(Empty.)*

## Flow index
*(Empty.)*

## Integration index
*(Empty.)*

## Architectural decisions
See [\`decisions/\`](./decisions/).
EOF
  ok "Added docs/index.md (AI navigation entry point per ADR-0010)"
  CHANGED=1
fi

# docs/features/ — create if missing
if [ ! -d "$ENGAGEMENT_DIR/docs/features" ]; then
  mkdir -p "$ENGAGEMENT_DIR/docs/features"
  if [ -f "$EXAMPLE_ROOT/docs/features/README.md" ]; then
    cp "$EXAMPLE_ROOT/docs/features/README.md" "$ENGAGEMENT_DIR/docs/features/README.md"
  fi
  ok "Added docs/features/ (per ADR-0010 derived layer)"
  CHANGED=1
fi

# ─── update engagement.yaml's harness_version line ────────────────────

section "Updating engagement.yaml"

# Cross-platform sed-in-place (GNU vs BSD): write via temp file
TMP_YAML="$(mktemp)"
sed -E "s|^harness_version:[[:space:]]*\"?[^\"]+\"?[[:space:]]*\$|harness_version: \"$NEW_VERSION\"|" \
  "$ENGAGEMENT_DIR/engagement.yaml" > "$TMP_YAML"
mv "$TMP_YAML" "$ENGAGEMENT_DIR/engagement.yaml"
ok "harness_version: \"$CURRENT_VERSION\" → \"$NEW_VERSION\""

# ─── audit log entry ──────────────────────────────────────────────────

section "Logging"

mkdir -p "$ENGAGEMENT_DIR/_internal/bootstrap-runs"
RUN_ID="update-$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_LOG="$ENGAGEMENT_DIR/_internal/bootstrap-runs/$RUN_ID.md"

cat > "$RUN_LOG" <<EOF
# Harness update — $RUN_ID

| | |
|---|---|
| Date | $(date -u +%Y-%m-%dT%H:%M:%SZ) |
| Engineer | $(whoami) ($(git config --get user.email 2>/dev/null || echo "?")) |
| From version | $CURRENT_VERSION |
| To version | $NEW_VERSION |
| Harness dir | $HARNESS_DIR |
| Engagement dir | $ENGAGEMENT_DIR |

Re-copied harness content (\`.archon/{workflows,commands,scripts,patterns,standards}/\`, \`docs/.harness-templates/\`).
Added any new \`.claude/commands/\` and \`.claude/skills/\` from the harness's \`claude-templates/\`.
Updated \`engagement.yaml\`'s \`harness_version:\` line.

Left untouched: \`.envrc\`, \`.mcp.json\`, \`CLAUDE.md\`, \`.gitignore\`, engagement-authored docs.
EOF

ok "Wrote audit log: $RUN_LOG"

# ─── summary ──────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════════════"
if [ "$CHANGED" -eq 1 ]; then
  printf '  %sHarness update applied%s — %s → %s\n' "$C_BOLD" "$C_RESET" "$CURRENT_VERSION" "$NEW_VERSION"
else
  printf '  %sNo files changed%s — already current at %s\n' "$C_BOLD" "$C_RESET" "$NEW_VERSION"
fi
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "    1. ${C_BOLD}git diff${C_RESET}                  # review what changed"
echo "    2. ${C_BOLD}archon validate workflows${C_RESET} # confirm refreshed workflows still parse"
echo "    3. ${C_BOLD}archon doctor${C_RESET}             # confirm the engagement is healthy"
echo "    4. Open a PR. Reference the harness changelog from $CURRENT_VERSION to $NEW_VERSION."
echo ""
echo "  If the update introduced new gates or sub-types that affect in-flight tickets,"
echo "  pause and check ticket status before re-running /sf against them."
echo ""
