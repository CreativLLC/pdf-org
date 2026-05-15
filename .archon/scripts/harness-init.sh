#!/usr/bin/env bash
#
# harness-init.sh — Stage 2 of the bootstrap workflow
#
# Initializes a per-engagement repo with harness content, engagement.yaml,
# off-workspace credentials, and the docs/ skeleton. Run ONCE per new
# engagement, from inside the (empty or SFDX-only) engagement repo directory.
#
# Implements:
#   - decisions/0002-harness-install-model.md  (copy-at-bootstrap)
#   - decisions/0006-bootstrap-workflow-design.md  (the design)
#   - decisions/0008-credential-management.md  (direnv-based credentials)
#
# Usage:
#   cd <engagement-repo>
#   <path-to-harness>/scripts/harness-init.sh
#
# Where to run from:
#   You MAY run this from VSCode's integrated terminal, but for maximum safety
#   we recommend running it from an external terminal (Terminal.app, iTerm)
#   so the API token you paste is never near VSCode's IDE-extension hooks.
#
# Exit codes:
#   0 — bootstrap complete
#   1 — invalid invocation, missing inputs, or pre-flight failure
#   2 — Stage 1 not run (or stale); re-run harness-machine-setup.sh first
#   3 — refusing to overwrite an existing engagement (engagement.yaml exists)
#   4 — credential validation failed (Jira API rejected)
#   5 — Salesforce org alias not authorized
#
# Files this creates (in the engagement repo):
#   engagement.yaml
#   .envrc                                    (committable, points to home-dir credentials)
#   .gitignore                                (if missing)
#   CLAUDE.md                                 (engagement-level orchestration for AI)
#   .mcp.json                                 (committable, env-interpolation per ADR-0008)
#   .archon/{workflows,commands,scripts,patterns,standards}/  (copied from harness)
#   .claude/commands/<name>.md                (Claude Code slash commands — /sf etc., from claude-templates/)
#   .claude/skills/<name>/                    (Claude Code agentic skills, from claude-templates/skills/, when present)
#   .github/workflows/docs-deploy.yml         (GitHub Actions: build MkDocs Material site, deploy to GH Pages)
#   docs/{README.md, index.md, architecture, decisions, objects, flows, integrations, features, patterns, standards, _internal}/
#   docs/.harness-templates/                  (copied from harness/docs-templates/)
#   mkdocs.yml                                (MkDocs Material config — per ADR-0010)
#   requirements-docs.txt                     (Python deps for the GH Actions docs build)
#   _internal/bootstrap-runs/<run-id>.md      (audit log)
#
# Files this creates (outside the engagement repo, on engineer's machine):
#   ~/.archon/credentials/<engagement_alias>/.envrc    (chmod 600 — the secrets file)
#
# This script does NOT git commit. The engineer reviews the result and commits.

set -euo pipefail

# ─── output helpers (mirror of Stage 1) ───────────────────────────────

if [ -t 1 ]; then
  C_RESET=$'\e[0m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
  C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
else
  C_RESET= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_BOLD= C_DIM=
fi

section() { printf '\n%s── %s ──%s\n' "$C_BOLD" "$*" "$C_RESET"; }
ok()      { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
info()    { printf '  %sℹ%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
fail()    { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()     { fail "$1"; exit "${2:-1}"; }

# ─── locate the harness ──────────────────────────────────────────────

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_VERSION="$(cd "$HARNESS_DIR" && git describe --tags --always 2>/dev/null || echo "0.0.0-dev")"

ENGAGEMENT_DIR="$(pwd)"

# ─── banner ──────────────────────────────────────────────────────────

cat <<EOF
${C_BOLD}harness-init${C_RESET} — Stage 2 of the bootstrap workflow

This will set up the current directory as a harness-enabled engagement repo
by copying harness content here, prompting you for engagement-specific
values, and writing credentials to your home dir (OUTSIDE this repo) so
they never leak via IDE extensions.

Harness:        $HARNESS_DIR  ($HARNESS_VERSION)
Engagement dir: $ENGAGEMENT_DIR
EOF

# ─── pre-flight ──────────────────────────────────────────────────────

section "Pre-flight"

# 1. Stage 1 was run recently
STATE_FILE="$HOME/.archon/machine-state.json"
if [ ! -f "$STATE_FILE" ]; then
  die "Stage 1 not run. Run: $HARNESS_DIR/scripts/harness-machine-setup.sh first." 2
fi

VERIFIED_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['verified_at'])" 2>/dev/null || echo "")
READY=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['ready'])" 2>/dev/null || echo "false")

if [ "$READY" != "True" ] && [ "$READY" != "true" ]; then
  die "Stage 1 reported NOT READY. Re-run harness-machine-setup.sh, fix the failures, then try again." 2
fi
ok "Machine state verified ($VERIFIED_AT)"

# 2. Engineer is NOT inside the harness repo itself
if [ "$ENGAGEMENT_DIR" = "$HARNESS_DIR" ] || [[ "$ENGAGEMENT_DIR" == "$HARNESS_DIR"/* ]]; then
  die "Refusing to bootstrap inside the harness repo itself. cd into your engagement repo first." 1
fi
ok "Not running inside the harness repo"

# 3. engagement.yaml doesn't already exist (no overwrite)
if [ -f "$ENGAGEMENT_DIR/engagement.yaml" ]; then
  die "engagement.yaml already exists in $ENGAGEMENT_DIR. This engagement is already bootstrapped. Refusing to overwrite — see decisions/0006-bootstrap-workflow-design.md for update semantics." 3
fi
ok "engagement.yaml does not yet exist (clean slate)"

# 4. Warn (don't fail) if there's no .git here — most engagement repos are git-initialized but some aren't yet
if [ ! -d "$ENGAGEMENT_DIR/.git" ]; then
  warn "No .git directory in $ENGAGEMENT_DIR. You'll need to \`git init\` afterward."
fi

# ─── prompts: engagement identity ────────────────────────────────────

# Helper: prompt with optional default
prompt() {
  local label="$1" default="${2:-}" help="${3:-}"
  local value=""
  if [ -n "$help" ]; then
    printf '\n%s%s%s\n' "$C_DIM" "$help" "$C_RESET"
  fi
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default"
  else
    printf '%s: ' "$label"
  fi
  read -r value
  if [ -z "$value" ] && [ -n "$default" ]; then
    value="$default"
  fi
  REPLY="$value"
}

# Helper: prompt with hidden input (no echo) — for secrets
prompt_secret() {
  local label="$1" help="${2:-}"
  if [ -n "$help" ]; then
    printf '\n%s%s%s\n' "$C_DIM" "$help" "$C_RESET"
  fi
  printf '%s: ' "$label"
  stty -echo
  read -r REPLY
  stty echo
  printf '\n'
}

section "Engagement identity"

# Suggest engagement_alias from current dir name, sanitized
DEFAULT_ALIAS="$(basename "$ENGAGEMENT_DIR" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"

prompt "Engagement alias (kebab-case slug, used for credentials dir)" "$DEFAULT_ALIAS" "Short identifier; will be used as ~/.archon/credentials/<alias>/.envrc and in run logs."
ENGAGEMENT_ALIAS="$REPLY"
if ! [[ "$ENGAGEMENT_ALIAS" =~ ^[a-z][a-z0-9-]*$ ]]; then
  die "Alias must be kebab-case (lowercase, digits, hyphens; starts with a letter). Got: $ENGAGEMENT_ALIAS" 1
fi

prompt "Client display name (e.g. 'Acme Co.')" "" "How the client appears in client-readable docs."
CLIENT_NAME="$REPLY"
[ -n "$CLIENT_NAME" ] || die "Client name is required" 1

prompt "One-line engagement description" "" "What this engagement is. E.g. 'Renewal management on Sales Cloud'."
DESCRIPTION="$REPLY"
[ -n "$DESCRIPTION" ] || die "Description is required" 1

# ─── prompts: Salesforce ─────────────────────────────────────────────

section "Salesforce"

# List authorized orgs
printf '\nAuthorized SF orgs:\n'
sf org list --json 2>/dev/null | python3 -c '
import sys, json
data = json.load(sys.stdin).get("result", {})
non = data.get("nonScratchOrgs", [])
scr = data.get("scratchOrgs", [])
for o in non + scr:
    alias = o.get("alias") or "(no alias)"
    user = o.get("username", "?")
    devhub = " [DEV HUB]" if o.get("isDevHub") else ""
    inst = o.get("instanceUrl", "?")
    print(f"  - {alias}: {user} @ {inst}{devhub}")
' || warn "Could not list SF orgs."

prompt "Target SF org alias" "" "From the list above. The harness will deploy/test against this org."
SF_ORG_ALIAS="$REPLY"
[ -n "$SF_ORG_ALIAS" ] || die "Target SF org alias is required" 1

# Verify alias exists
if ! sf org display --target-org "$SF_ORG_ALIAS" >/dev/null 2>&1; then
  die "SF org alias '$SF_ORG_ALIAS' is not authorized. Run \`sf org login web --alias $SF_ORG_ALIAS\` first." 5
fi
ok "SF org '$SF_ORG_ALIAS' is authorized"

# Detect current API version from sf
DEFAULT_API_VERSION=$(sf --version 2>&1 | grep -oE 'api-version [0-9]+\.[0-9]+' | awk '{print $2}' || true)
if [ -z "$DEFAULT_API_VERSION" ]; then
  DEFAULT_API_VERSION="67.0"
fi
prompt "API version" "$DEFAULT_API_VERSION" "Pinned per engagement. Auto-detected from \`sf --version\`."
API_VERSION="$REPLY"

prompt "Dev model" "source_tracked" "source_tracked (scratch + unlocked pkgs) or org_development (sandboxes + change sets)."
DEV_MODEL="$REPLY"
if [ "$DEV_MODEL" != "source_tracked" ] && [ "$DEV_MODEL" != "org_development" ]; then
  die "Invalid dev model: $DEV_MODEL. Must be 'source_tracked' or 'org_development'." 1
fi

# ─── prompts: Jira ───────────────────────────────────────────────────

section "Jira"

DEFAULT_JIRA_URL=""
prompt "Jira Cloud URL (e.g. https://your-firm.atlassian.net)" "$DEFAULT_JIRA_URL" ""
JIRA_URL_VAL="$REPLY"
[ -n "$JIRA_URL_VAL" ] || die "Jira URL is required" 1

DEFAULT_JIRA_USERNAME=$(git config --get user.email 2>/dev/null || echo "")
prompt "Jira username (your Atlassian login email)" "$DEFAULT_JIRA_USERNAME" "The email you log in to Atlassian with."
JIRA_USERNAME_VAL="$REPLY"
[ -n "$JIRA_USERNAME_VAL" ] || die "Jira username is required" 1

prompt "Jira project key (e.g. ACME)" "" "All engagement tickets must be in this project."
JIRA_PROJECT_KEY="$REPLY"
[ -n "$JIRA_PROJECT_KEY" ] || die "Jira project key is required" 1
if ! [[ "$JIRA_PROJECT_KEY" =~ ^[A-Z][A-Z0-9]+$ ]]; then
  die "Project key must be uppercase letters/digits (e.g. ACME, PROJ123)." 1
fi

prompt_secret "Jira API token (paste here; will not be echoed)" "Generate at https://id.atlassian.com/manage-profile/security/api-tokens. Per-user, never shared. Will be written to ~/.archon/credentials/$ENGAGEMENT_ALIAS/.envrc (chmod 600, outside this workspace)."
JIRA_API_TOKEN_VAL="$REPLY"
[ -n "$JIRA_API_TOKEN_VAL" ] || die "Jira API token is required" 1

# Jira workflow statuses (with sane defaults)
prompt "Jira status: 'Ready for Dev' name in your project" "Ready for Dev" ""
JIRA_STATUS_READY="$REPLY"

prompt "Jira status: 'In Progress' name in your project" "In Progress" ""
JIRA_STATUS_IN_PROGRESS="$REPLY"

prompt "Jira status: 'In Review' name in your project" "In Review" ""
JIRA_STATUS_IN_REVIEW="$REPLY"

prompt "Jira status: 'Done' name in your project" "Done" ""
JIRA_STATUS_DONE="$REPLY"

# ─── prompts: docs audiences ─────────────────────────────────────────

section "Documentation audiences"

prompt "Will the client have read-access to this engagement repo?" "no" "If yes, the docs are held to client-safe standards and an internal-only carve-out (docs/_internal/) is enforced."
CLIENT_READ_INPUT="$REPLY"
case "$(printf '%s' "$CLIENT_READ_INPUT" | tr '[:upper:]' '[:lower:]')" in
  y|yes|true) DOCS_CLIENT_READ=true ;;
  *)          DOCS_CLIENT_READ=false ;;
esac

# ─── prompts: integrations (optional, can be added later) ────────────

section "Integrations (optional)"
info "Skip for now; add to engagement.yaml later or rerun init in update mode (future)."
info "Common integrations: stripe, docusign, snowflake, marketo."

# ─── actions: write credentials file (off-workspace) ─────────────────

section "Writing off-workspace credentials"

CRED_DIR="$HOME/.archon/credentials/$ENGAGEMENT_ALIAS"
CRED_FILE="$CRED_DIR/.envrc"

mkdir -p "$CRED_DIR"
chmod 700 "$CRED_DIR"

cat > "$CRED_FILE" <<EOF
# $ENGAGEMENT_ALIAS — local credentials for $JIRA_USERNAME_VAL
# Generated by harness-init.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# This file is OUTSIDE any IDE-watched workspace. Permissions: chmod 600.
# NEVER commit, share, or paste contents anywhere.

export JIRA_URL="$JIRA_URL_VAL"
export JIRA_USERNAME="$JIRA_USERNAME_VAL"
export JIRA_API_TOKEN="$JIRA_API_TOKEN_VAL"
EOF
chmod 600 "$CRED_FILE"
ok "Wrote $CRED_FILE (chmod 600)"

# Free the secret from this shell variable
unset JIRA_API_TOKEN_VAL

# ─── actions: write engagement repo files ────────────────────────────

section "Writing engagement repo files"

# .envrc — committable pointer
cat > "$ENGAGEMENT_DIR/.envrc" <<EOF
# Engagement repo .envrc — committable. Points at the engineer's off-workspace
# credentials. Each engineer maintains their own ~/.archon/credentials/<alias>/.envrc.
# See harness/decisions/0008-credential-management.md.

set -e
ENGAGEMENT_ALIAS="$ENGAGEMENT_ALIAS"
CRED_DIR="\$HOME/.archon/credentials/\$ENGAGEMENT_ALIAS"

if [ ! -f "\$CRED_DIR/.envrc" ]; then
  echo "harness: no credentials found at \$CRED_DIR/.envrc"
  echo "        run 'harness-init.sh' to set up, or see decisions/0008-credential-management.md"
  return 1
fi

source_env "\$CRED_DIR/.envrc"
echo "harness: credentials loaded for \$ENGAGEMENT_ALIAS"
EOF
ok "Wrote .envrc"

# engagement.yaml
cat > "$ENGAGEMENT_DIR/engagement.yaml" <<EOF
# engagement.yaml — generated by harness-init.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Per-engagement harness configuration. Committable; contains no secrets.

engagement_alias: $ENGAGEMENT_ALIAS
client_name: "$CLIENT_NAME"
description: "$DESCRIPTION"

harness_version: "$HARNESS_VERSION"

credentials:
  source: direnv

salesforce:
  target_org_alias: "$SF_ORG_ALIAS"
  api_version: "$API_VERSION"
  dev_model: "$DEV_MODEL"
  scratch_org_def_path: "config/project-scratch-def.json"
  coverage:
    org_wide_minimum: 75
    per_class_target: 75

jira:
  url_env: "JIRA_URL"
  username_env: "JIRA_USERNAME"
  api_token_env: "JIRA_API_TOKEN"
  project_key: "$JIRA_PROJECT_KEY"
  statuses:
    ready_for_dev: "$JIRA_STATUS_READY"
    in_progress: "$JIRA_STATUS_IN_PROGRESS"
    in_review: "$JIRA_STATUS_IN_REVIEW"
    done: "$JIRA_STATUS_DONE"

docs:
  root: "docs"
  audiences:
    - internal_engineers
    - onboarding
    - ai_sessions$([ "$DOCS_CLIENT_READ" = "true" ] && printf '\n    - client_read' || true)

integrations: {}

gates:
  destructive_changes_require_approval: true
  destructive_change_overrides:
    additions: []
    removals: []
EOF
ok "Wrote engagement.yaml"

# .mcp.json — env-interpolation per ADR-0008; committable
cat > "$ENGAGEMENT_DIR/.mcp.json" <<EOF
{
  "_comment": "Generated by harness-init.sh. Committable: no literal credentials. Values come from direnv-loaded environment (see ADR-0008).",
  "mcpServers": {
    "mcp-atlassian": {
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {
        "JIRA_URL": "\${JIRA_URL}",
        "JIRA_USERNAME": "\${JIRA_USERNAME}",
        "JIRA_API_TOKEN": "\${JIRA_API_TOKEN}",
        "READ_ONLY_MODE": "false",
        "ENABLED_TOOLS": "jira_get_issue,jira_search,jira_transition_issue,jira_add_comment,jira_update_issue"
      }
    }
  }
}
EOF
ok "Wrote .mcp.json"

# .gitignore (only if missing)
if [ ! -f "$ENGAGEMENT_DIR/.gitignore" ]; then
  cp "$HARNESS_DIR/examples/engagement/.gitignore" "$ENGAGEMENT_DIR/.gitignore"
  ok "Wrote .gitignore (from harness template)"
else
  warn ".gitignore already exists — leaving untouched. Verify it includes .env, .env.*, .mcp.json (with !.mcp.json.example exception), and docs/_internal/"
fi

# CLAUDE.md for the engagement repo
cat > "$ENGAGEMENT_DIR/CLAUDE.md" <<EOF
# CLAUDE.md — $CLIENT_NAME engagement

You're working in the **$CLIENT_NAME** engagement repo (alias \`$ENGAGEMENT_ALIAS\`). This repo is a Salesforce SFDX project + harness content.

## Two modes

- **Work mode** (changes to the org or repo): requires a Jira ticket from project \`$JIRA_PROJECT_KEY\`. Triggered via \`/sf <TICKET>\` slash command.
- **Explore mode** (reading, learning, asking questions): direct Claude Code use. Read-only. No commits, no deploys, no Jira posts.

If you're asked to make a change without a Jira ticket, **refuse and ask for the ticket key**. Suggest \`/sf <TICKET>\`. The harness's on-rails principle is non-negotiable.

## Where things live

- **Harness content** (read-only, copied from harness repo at bootstrap): \`.archon/{workflows,commands,scripts,patterns,standards}\`, \`docs/.harness-templates/\`
- **Engagement docs** (we author and update these): \`docs/{architecture,decisions,objects,flows,integrations,changelog,patterns,standards}\`
- **Internal-only notes** (gitignored): \`docs/_internal/\`
- **Engagement config**: \`engagement.yaml\` at the repo root.

## SF org

This engagement targets SF org alias \`$SF_ORG_ALIAS\` (API $API_VERSION, $DEV_MODEL model). The harness shells out to \`sf\` commands using that alias.

## Credentials

Managed by direnv per [harness/decisions/0008-credential-management.md](.). Tokens live at \`~/.archon/credentials/$ENGAGEMENT_ALIAS/.envrc\` — outside this workspace. Never paste credentials into any file in this repo.

## When you start work

1. \`cd\` here. direnv auto-loads credentials.
2. Run \`/sf <TICKET>\` with a real Jira ticket key from project \`$JIRA_PROJECT_KEY\`.
3. The dispatcher classifies, shows a confirmation, then runs the matching workflow.
EOF
ok "Wrote CLAUDE.md"

# ─── actions: copy harness content into .archon/ ─────────────────────

section "Copying harness content"

mkdir -p "$ENGAGEMENT_DIR/.archon"
for subdir in workflows commands scripts patterns standards; do
  if [ -d "$HARNESS_DIR/$subdir" ]; then
    cp -R "$HARNESS_DIR/$subdir" "$ENGAGEMENT_DIR/.archon/$subdir"
    ok "Copied harness/$subdir/ → .archon/$subdir/"
  fi
done

# docs templates as engagement-side ref
mkdir -p "$ENGAGEMENT_DIR/docs"
if [ -d "$HARNESS_DIR/docs-templates" ]; then
  cp -R "$HARNESS_DIR/docs-templates" "$ENGAGEMENT_DIR/docs/.harness-templates"
  ok "Copied harness/docs-templates/ → docs/.harness-templates/"
fi

# Claude Code slash commands / skills (Phase 4+). Only ADDS — never overwrites
# existing files in the engagement's .claude/, since engagements may have their
# own command files. Per ADR-0001 we ship /sf at minimum.
if [ -d "$HARNESS_DIR/claude-templates" ]; then
  mkdir -p "$ENGAGEMENT_DIR/.claude/commands"
  for src in "$HARNESS_DIR/claude-templates/commands/"*.md; do
    [ -f "$src" ] || continue
    base=$(basename "$src")
    [ "$base" = "README.md" ] && continue
    dest="$ENGAGEMENT_DIR/.claude/commands/$base"
    if [ -f "$dest" ]; then
      warn "Skipped .claude/commands/$base — file already exists in engagement (manual merge if needed)"
    else
      cp "$src" "$dest"
      ok "Copied claude-templates/commands/$base → .claude/commands/$base"
    fi
  done
  # Claude Code skills are folders, not files — copied as a tree
  if [ -d "$HARNESS_DIR/claude-templates/skills" ]; then
    mkdir -p "$ENGAGEMENT_DIR/.claude/skills"
    for skill_dir in "$HARNESS_DIR/claude-templates/skills/"*/; do
      [ -d "$skill_dir" ] || continue
      skill_name=$(basename "$skill_dir")
      if [ -d "$ENGAGEMENT_DIR/.claude/skills/$skill_name" ]; then
        warn "Skipped .claude/skills/$skill_name — skill already exists in engagement"
      else
        cp -R "$skill_dir" "$ENGAGEMENT_DIR/.claude/skills/$skill_name"
        ok "Copied claude-templates/skills/$skill_name → .claude/skills/$skill_name"
      fi
    done
  fi
fi

# ─── actions: docs/ skeleton ─────────────────────────────────────────

section "Scaffolding docs/"

# Generate minimal engagement-shaped category READMEs. Per ADR-0010 + ADR-0012:
# do NOT copy the Acme exemplar READMEs — they contain references to
# Renewal__c / Stripe / fictional ADRs that survive into real engagements
# and mislead clients reading the rendered docs site. The exemplar
# directory remains as a reference for harness authors (under
# examples/engagement/docs/), but is not the source of engagement docs.

TODAY=$(date -u +%Y-%m-%d)
HARNESS_CANON_URL="https://github.com/CreativLLC/archon-salesforce-jira/tree/main/docs-templates"

write_category_readme() {
  local subdir="$1" title="$2" blurb="$3" template_file="$4"
  mkdir -p "$ENGAGEMENT_DIR/docs/$subdir"
  cat > "$ENGAGEMENT_DIR/docs/$subdir/README.md" <<README_EOF
---
title: $title
audience: public
last_updated: $TODAY
last_updated_by: harness-init
related_tickets: []
related_docs: [../index.md]
---

# $title — $CLIENT_NAME

$blurb

## Index

*Empty until \`/sf-discover\` or \`/sf\` runs populate this section.*

---

Doc template: [\`$template_file\`](../.harness-templates/$template_file). Authoring guidance: [harness docs-templates]($HARNESS_CANON_URL).
README_EOF
}

write_category_readme "objects" "Objects" \
  "The canonical reference layer for Salesforce objects in this engagement. One file per significant standard-with-customizations or custom object. Standard objects with no engagement-specific customizations are not documented here — Salesforce documents those." \
  "object-doc.md"

write_category_readme "features" "Features" \
  "The derived business-facing layer per [ADR-0010](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/decisions/0010-engagement-documentation-model.md). One file per coherent end-to-end business capability that spans multiple objects, flows, or integrations. Reads like product documentation; links to canonical object/flow/integration docs for technical detail." \
  "feature-doc.md"

write_category_readme "flows" "Flows" \
  "Salesforce Flows (record-triggered, scheduled, screen, autolaunched) configured in this engagement. One file per significant Flow." \
  "flow-doc.md"

write_category_readme "integrations" "Integrations" \
  "External systems this engagement's Salesforce org reads from, writes to, or both. One file per integration boundary, regardless of transport (REST, platform events, SOAP, callouts, webhooks, named credentials)." \
  "integration-doc.md"

write_category_readme "decisions" "Architectural decisions" \
  "Engagement-specific ADRs in [MADR](https://adr.github.io/madr/) format. Records the architectural choices made for this client's Salesforce work. Distinct from the harness's own ADRs (which govern the harness platform, not this engagement)." \
  "adr.md"

# architecture/ — no category-doc template; carves out for engagement-specific
# system overview files. Bootstrap writes only the README.
mkdir -p "$ENGAGEMENT_DIR/docs/architecture"
cat > "$ENGAGEMENT_DIR/docs/architecture/README.md" <<README_EOF
---
title: Architecture
audience: public
last_updated: $TODAY
last_updated_by: harness-init
related_tickets: []
related_docs: [../index.md]
---

# Architecture — $CLIENT_NAME

The 'why' of $CLIENT_NAME's Salesforce org: system overview, subsystem boundaries, sharing model, integration topology, and any cross-cutting design notes.

## Index

*Empty until populated. Suggested first additions:*

- \`overview.md\` — high-level system map (mermaid diagrams of object subsystems)
- \`sharing-model.md\` — OWD + sharing rules + Apex sharing posture
- \`integration-topology.md\` — system context diagram if integrations are non-trivial

Architecture docs are authored by engineers, not auto-generated. There's no template; pattern after [ADR-0010](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/decisions/0010-engagement-documentation-model.md) and other docs in the harness exemplar.
README_EOF

# patterns/ and standards/ — engagement-specific overrides only (rare). Per
# the harness install model, team canon lives in the harness; per-engagement
# overrides go here.
for cat in patterns standards; do
  mkdir -p "$ENGAGEMENT_DIR/docs/$cat"
  cat > "$ENGAGEMENT_DIR/docs/$cat/README.md" <<README_EOF
---
title: $(echo "$cat" | sed 's/.*/\u&/')
audience: public
last_updated: $TODAY
last_updated_by: harness-init
related_tickets: []
related_docs: [../index.md]
---

# Engagement-specific $cat — $CLIENT_NAME

Engagement-specific $cat that diverge from or extend the team canon at [harness/$cat/](https://github.com/CreativLLC/archon-salesforce-jira/tree/main/$cat). Most engagements have zero or near-zero entries here — defaulting to harness canon is the norm.

## Index

*Empty.*
README_EOF
done

# _internal/ — gitignored from client distribution; for engineer notes
mkdir -p "$ENGAGEMENT_DIR/docs/_internal"
cat > "$ENGAGEMENT_DIR/docs/_internal/README.md" <<README_EOF
# Internal-only notes

Gitignored from client distribution per [ADR-0010](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/decisions/0010-engagement-documentation-model.md). Engineer war stories, half-finished hypotheses, risk logs, candid post-mortems live here. Never in the main \`docs/\` tree where the client may read them.
README_EOF

# CONVENTIONS.md — minimal engagement-side pointer. The full canon lives in
# the harness; this file is for engagement-specific overrides only.
cat > "$ENGAGEMENT_DIR/docs/CONVENTIONS.md" <<CONV_EOF
---
title: Engagement Documentation Conventions
audience: public
last_updated: $TODAY
last_updated_by: harness-init
related_tickets: []
related_docs: [README.md, index.md]
---

# Documentation conventions — $CLIENT_NAME

Authoritative doc conventions for this engagement live in the harness:
[harness/examples/engagement/docs/CONVENTIONS.md](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/examples/engagement/docs/CONVENTIONS.md).

This file is reserved for **engagement-specific overrides** — rare. Examples of what would land here: a different naming convention required by $CLIENT_NAME's existing repo, a client-mandated audience filter, a stricter PII redaction rule.

## Overrides

*None.*
CONV_EOF

if [ -d "$HARNESS_DIR/examples/engagement/docs" ]; then

  # docs/README.md — human entry point (engagement summary)
  cat > "$ENGAGEMENT_DIR/docs/README.md" <<EOF
# $CLIENT_NAME — Engagement Documentation

Generated at bootstrap; populate as work progresses. See [CONVENTIONS.md](./CONVENTIONS.md) for doc style and [.harness-templates/](./.harness-templates/) for the templates each doc type must conform to.

For AI-friendly navigation, see [index.md](./index.md).
EOF

  # docs/index.md — AI navigation entry point per ADR-0010
  cat > "$ENGAGEMENT_DIR/docs/index.md" <<EOF
---
title: $CLIENT_NAME — Engagement Documentation Index
audience: public
last_updated: $(date -u +%Y-%m-%d)
last_updated_by: harness-init
related_tickets: []
related_docs: [README.md, architecture/overview.md]
---

# $CLIENT_NAME — Engagement Documentation Index

> **For AI agents:** load this file first, then load ONLY the docs in the
> "Quick paths" section relevant to your current task. Do not load the
> entire \`docs/\` tree by default.

## Quick paths

### Working on Apex on a specific object
Load: \`docs/objects/<ObjectAPIName>.md\` + the Apex classes referenced therein.

### Working on a Flow
Load: \`docs/flows/<FlowName>.md\` + \`docs/objects/<primary-object>.md\`.

### Adding or modifying a feature
Load: \`docs/features/<closest-feature>.md\` + the object docs that feature references.

### Touching an external integration
Load: \`docs/integrations/<system>.md\` + any object docs the integration syncs with.

### Designing a new architectural pattern
Load: \`docs/architecture/overview.md\` + relevant \`docs/decisions/*.md\` ADRs.

## Object index

The canonical reference layer (one doc per significant object).

*(Empty — \`/sf\` runs will populate this section as they create object docs.)*

## Feature index

The derived business-facing layer (one doc per significant feature).

*(Empty — \`/sf\` runs will populate this section.)*

## Flow index

*(Empty.)*

## Integration index

*(Empty.)*

## Architectural decisions

See [\`decisions/\`](./decisions/).

---

Maintained by \`/sf\` workflows per [ADR-0010](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/decisions/0010-engagement-documentation-model.md).
EOF

  ok "Scaffolded docs/ with subdirectory READMEs + index.md (AI nav entry)"
fi

# ─── actions: MkDocs Material site config ────────────────────────────
#
# Per ADR-0010 §5: copy mkdocs.yml + requirements-docs.txt + the GitHub
# Actions workflow that auto-deploys to GitHub Pages. Substitute the
# placeholders for client name and (where possible) GitHub org/repo
# from the existing `origin` remote.

section "Scaffolding MkDocs site config"

EXAMPLE_ROOT="$HARNESS_DIR/examples/engagement"

# Determine GitHub org and repo from `origin` remote, if set. Falls back
# to placeholders if no remote is configured.
GH_ORG="<github-org>"
GH_REPO="<engagement-repo>"
if git -C "$ENGAGEMENT_DIR" remote get-url origin >/dev/null 2>&1; then
  ORIGIN_URL=$(git -C "$ENGAGEMENT_DIR" remote get-url origin)
  # Match git@github.com:org/repo.git or https://github.com/org/repo.git
  if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    GH_ORG="${BASH_REMATCH[1]}"
    GH_REPO="${BASH_REMATCH[2]}"
  fi
fi

# mkdocs.yml with substitutions
if [ -f "$EXAMPLE_ROOT/mkdocs.yml" ]; then
  sed \
    -e "s|<Client Name>|$CLIENT_NAME|g" \
    -e "s|<github-org>|$GH_ORG|g" \
    -e "s|<engagement-repo>|$GH_REPO|g" \
    "$EXAMPLE_ROOT/mkdocs.yml" > "$ENGAGEMENT_DIR/mkdocs.yml"
  ok "Wrote mkdocs.yml (client: $CLIENT_NAME, repo: $GH_ORG/$GH_REPO)"
fi

# requirements-docs.txt (no substitution needed)
if [ -f "$EXAMPLE_ROOT/requirements-docs.txt" ]; then
  cp "$EXAMPLE_ROOT/requirements-docs.txt" "$ENGAGEMENT_DIR/requirements-docs.txt"
  ok "Wrote requirements-docs.txt"
fi

# GitHub Actions workflow for Pages deploy
if [ -f "$EXAMPLE_ROOT/.github/workflows/docs-deploy.yml" ]; then
  mkdir -p "$ENGAGEMENT_DIR/.github/workflows"
  cp "$EXAMPLE_ROOT/.github/workflows/docs-deploy.yml" "$ENGAGEMENT_DIR/.github/workflows/docs-deploy.yml"
  ok "Wrote .github/workflows/docs-deploy.yml"
  info "  → after the first commit + push to main, enable GitHub Pages in the repo's"
  info "    Settings → Pages → 'Source: GitHub Actions'. Site will deploy automatically."
fi

# ─── validation ──────────────────────────────────────────────────────

section "Validation"

# direnv: allow the new .envrc
if command -v direnv >/dev/null 2>&1; then
  direnv allow "$ENGAGEMENT_DIR" >/dev/null 2>&1 || warn "direnv allow failed; try manually: cd here, then 'direnv allow'"
  ok "direnv allowed for this directory"
fi

# Test that credentials load via direnv
ENV_TEST=$(direnv exec "$ENGAGEMENT_DIR" bash -c 'echo "$JIRA_URL"' 2>/dev/null || echo "")
if [ -n "$ENV_TEST" ]; then
  ok "Credentials load via direnv (JIRA_URL resolves)"
else
  warn "Credentials didn't load via direnv exec — re-cd into the directory after this script."
fi

# Test Jira auth using the loaded credentials
JIRA_MYSELF=$(direnv exec "$ENGAGEMENT_DIR" bash -c '
curl --silent --fail --max-time 10 \
  -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
  -H "Accept: application/json" \
  "$JIRA_URL/rest/api/3/myself"
' 2>&1 || echo "AUTH_FAIL")

if printf '%s' "$JIRA_MYSELF" | grep -q '"accountId"'; then
  DISPLAY_NAME=$(printf '%s' "$JIRA_MYSELF" | python3 -c 'import sys, json; print(json.load(sys.stdin)["displayName"])' 2>/dev/null || echo "?")
  ok "Jira auth works ($DISPLAY_NAME)"
else
  fail "Jira auth failed. Token may be wrong or revoked. Re-run after regenerating at id.atlassian.com."
  exit 4
fi

# Test Jira project key exists
PROJECT_CHECK=$(direnv exec "$ENGAGEMENT_DIR" bash -c '
curl --silent --fail --max-time 10 \
  -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
  -H "Accept: application/json" \
  "$JIRA_URL/rest/api/3/project/'"$JIRA_PROJECT_KEY"'"
' 2>&1 || echo "PROJECT_FAIL")

if printf '%s' "$PROJECT_CHECK" | grep -q "\"key\":\"$JIRA_PROJECT_KEY\""; then
  ok "Jira project '$JIRA_PROJECT_KEY' exists and is accessible"
else
  warn "Jira project '$JIRA_PROJECT_KEY' could not be verified. Auth worked but project query failed. Check the project key."
fi

# ─── log the run ─────────────────────────────────────────────────────

mkdir -p "$ENGAGEMENT_DIR/docs/_internal/bootstrap-runs"
RUN_ID="$(date -u +%Y-%m-%d-%H%M%S)"
RUN_LOG="$ENGAGEMENT_DIR/docs/_internal/bootstrap-runs/$RUN_ID.md"
cat > "$RUN_LOG" <<EOF
# Bootstrap run $RUN_ID

| | |
|---|---|
| Date | $(date -u +%Y-%m-%dT%H:%M:%SZ) |
| Engineer | $(whoami) ($(git config --get user.email 2>/dev/null || echo "?")) |
| Harness version | $HARNESS_VERSION |
| Engagement alias | $ENGAGEMENT_ALIAS |
| Client | $CLIENT_NAME |
| Jira URL | $JIRA_URL_VAL |
| Jira project | $JIRA_PROJECT_KEY |
| SF org alias | $SF_ORG_ALIAS |
| API version | $API_VERSION |
| Dev model | $DEV_MODEL |

Generated by \`harness-init.sh\`.
EOF
ok "Wrote run log: $RUN_LOG"

# ─── done ────────────────────────────────────────────────────────────

printf '\n%s════════════════════════════════════════════════════════════════%s\n' "$C_BOLD" "$C_RESET"
printf '%s  Engagement bootstrapped ✓%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
printf '%s════════════════════════════════════════════════════════════════%s\n\n' "$C_BOLD" "$C_RESET"

cat <<EOF
  Engagement:     $CLIENT_NAME ($ENGAGEMENT_ALIAS)
  Repo:           $ENGAGEMENT_DIR
  Credentials:    $CRED_FILE   ${C_DIM}(outside this workspace — safe from IDE leaks)${C_RESET}
  Run log:        $RUN_LOG

  ${C_BOLD}Next steps:${C_RESET}
  1. Review the generated files (git status / diff).
  2. Commit:    ${C_DIM}git add . && git commit -m "Initial: harness bootstrap"${C_RESET}
  3. When you have your first Jira ticket from $JIRA_PROJECT_KEY:
       ${C_BOLD}/sf $JIRA_PROJECT_KEY-N${C_RESET}     ${C_DIM}(in Claude Code — Phase 4+)${C_RESET}

  ${C_DIM}direnv will auto-load credentials whenever you cd into this directory.${C_RESET}
EOF
