# Scripts

Shell utilities. Three categories:

1. **Bootstrap scripts** — set up an engineer's machine and bootstrap a new engagement.
2. **Workflow utilities** — invoked from `bash:` nodes inside Archon workflows for deterministic operations.
3. **Engineer / operator tools** — invoked directly by engineers for reporting, validation, and feedback.

## Bootstrap scripts

| Script | Stage | When to run | What it does |
|---|---|---|---|
| [`harness-machine-setup.sh`](./harness-machine-setup.sh) | Stage 1 | Once per engineer (re-run after tool upgrades) | Verifies tools (`git`, `gh`, `bun`, `uv`, `direnv`, `jq`, `sf`, Node, Archon), VSCode extensions, GitHub + SF + Dev Hub auth, network reachability, the direnv shell hook. Writes `~/.archon/machine-state.json` on success. Never installs anything — only checks. |
| [`harness-init.sh`](./harness-init.sh) | Stage 2 | Once per new engagement | Prompts for engagement values, copies harness content into the engagement repo's `.archon/`, generates `engagement.yaml` + `.envrc` + `.mcp.json` + `CLAUDE.md` + `docs/` skeleton (including `docs/security/` per ADR-0013), writes credentials to `~/.archon/credentials/<alias>/.envrc` (off-workspace per ADR-0008), validates by hitting the Jira API. |
| [`harness-update.sh`](./harness-update.sh) | Update | Per engagement, when bumping to a newer harness version | Two-tier refresh per [ADR-0012](../decisions/0012-harness-update-refresh-policy.md): refreshes harness-canon files (`.archon/`, `.claude/commands/`, `.claude/skills/`, `docs/.harness-templates/`) and preserves engagement-shaped files (`engagement.yaml`, `mkdocs.yml`, `CLAUDE.md`, authored docs). Rewrites just the `harness_version` line in `engagement.yaml`. Audit-logged to `_internal/bootstrap-runs/`. |

### Running them

```bash
# Stage 1 — once per engineer
~/harness/scripts/harness-machine-setup.sh

# Stage 2 — once per new engagement
cd <engagement-repo>
~/harness/scripts/harness-init.sh

# Update — when ready to pull in new harness improvements
cd <engagement-repo>
~/harness/scripts/harness-update.sh
```

For Stage 2, run from an external terminal (not VSCode integrated) so the API-token prompt is off the IDE-watched surface. The script writes the token to `~/.archon/credentials/<alias>/.envrc` — outside any IDE workspace.

## Workflow utilities

Invoked from `bash:` nodes inside workflow YAMLs. Engineers typically don't run these directly — the workflows do — but they CAN be run for debugging.

| Script | Purpose | Invoked by |
|---|---|---|
| [`verify-jira-integration.sh`](./verify-jira-integration.sh) | Round-trip verification: Jira read + comment + transition + cleanup. Used for ADR-0007 layer-1 integration validation. | Engineer manually, after bootstrap, to confirm Jira creds work end-to-end |
| [`deploy-to-scratch.sh`](./deploy-to-scratch.sh) | Create / reuse the engagement's scratch org and deploy changed files. Outputs structured JSON to `$ARTIFACTS_DIR/deploy-to-scratch.json`. Set `HARNESS_SKIP_SCRATCH=1` to deploy to `target_org_alias` directly (no scratch). | `sf-apex-change-validate` |
| [`run-apex-tests.sh`](./run-apex-tests.sh) | Runs Apex tests against the scratch (or target) org. Enforces per-class coverage gate from `engagement.yaml.salesforce.coverage.per_class_target`. Outputs structured JSON. | `sf-apex-change-validate` |
| [`check-destructive-changes.sh`](./check-destructive-changes.sh) | Static, regex-based diff check for destructive Apex changes per [ADR-0009](../decisions/0009-sf-apex-change-scope-and-gates.md) §3 — file deletions, public-method removal, signature changes, visibility downgrades, removed `@AuraEnabled` / `@InvocableMethod`. | `sf-apex-change-validate` |
| [`check-fls-crud.sh`](./check-fls-crud.sh) | Static, regex-based check for `WITH USER_MODE` on SOQL and `Security.stripInaccessible` on DML per ADR-0009 §7. False positives surface at the post-validate gate. | `sf-apex-change-validate` |

## Engineer / operator tools

Run directly by engineers from inside an engagement repo for reporting, validation, or feedback.

| Script | Purpose | When you'd run it |
|---|---|---|
| [`validate-doc-links.sh`](./validate-doc-links.sh) | Walk every `.md` in `docs/`, extract `related_docs:` frontmatter entries + body markdown links, verify each relative target exists. Flags links pointing outside `docs/` as "out-of-site" (would 404 on the rendered MkDocs site). Skips absolute URLs, anchor-only links, fenced code blocks, `docs/_internal/`, `docs/.harness-templates/`. Per [ADR-0010](../decisions/0010-engagement-documentation-model.md). | Auto-runs inside `sf-apex-change-document` (step 12) and `sf-discover-update-index` (step 3). Can be run manually before commit: `bash .archon/scripts/validate-doc-links.sh docs/` |
| [`cost-summary.sh`](./cost-summary.sh) | Read `_internal/cost-log.jsonl` and aggregate by workflow / ticket / model / day. Estimates only (~20% accuracy) — see Anthropic Console for billing-grade numbers. Flags: `--by`, `--since`, `--until`, `--top`, `--json`, `--all-engagements`. Per [ADR-0016](../decisions/0016-cost-observability.md). | Engineer or engagement lead, anytime, to answer "what did this ticket / workflow / month cost?" |
| [`file-feedback.sh`](./file-feedback.sh) | Open a GitHub Issue on the harness repo (`CreativLLC/archon-salesforce-jira`) with auto-bundled engagement context (alias, harness version, current branch, active ticket, engineer email, timestamp). Labels: `feedback` + `harness-version:<sha>`. Falls back to `~/.archon/pending-feedback/` if `gh` isn't available. Per [ADR-0014](../decisions/0014-feedback-mechanism.md). | Engineer, via the `/sf-feedback "<text>"` slash command (which invokes this) |

## Conventions

Per [ADR-0003](../decisions/0003-workflow-yaml-scope-and-naming.md), every script in this directory:

1. Begins with `#!/usr/bin/env bash` shebang + `set -euo pipefail`.
2. Has a header comment explaining purpose, inputs, outputs, exit codes.
3. Reads configuration from environment variables (or, for workflow scripts, sources `.envrc` first via direnv per ADR-0008).
4. Emits **structured output** (JSON preferred) to stdout for programmatic consumption.
5. Emits **human-readable diagnostics** to stderr.
6. Is executable (`chmod +x`).
7. Documents specific exit codes in the header.

### Naming

| Element | Convention | Example |
|---|---|---|
| Filename | `<verb>-<noun>.sh` (kebab-case) | `validate-doc-links.sh`, `deploy-to-scratch.sh` |
| Workflow invocation | `bash: bash .archon/scripts/<name>.sh <args>` | (in workflow YAML) |
| Engineer invocation | `~/harness/scripts/<name>.sh` OR `.archon/scripts/<name>.sh` (the in-engagement copy is the same script) | |

### Why scripts, not inline bash

Archon's `bash:` workflow nodes can hold inline shell, but for anything beyond a few lines, scripts win:

- Readability — escaped multi-line YAML strings get unwieldy fast.
- Testable in isolation (`bats` or similar).
- Reusable across workflows.
- Invokable locally by engineers for debugging.

## Adding a new script

Adding a script is part of the workflow PR that uses it (or, for engineer-tools, the ADR that introduces them). The PR includes:

1. The script itself, with header documentation matching the conventions above.
2. The workflow YAML modification(s) that invoke it (if applicable).
3. An entry in this README under the appropriate category.
4. Tests demonstrating the script's behavior in isolation (Phase 4+ when test infrastructure exists).

## Planned future scripts

| Script | Purpose | Phase |
|---|---|---|
| `pull-org-metadata.sh` | Wrap `sf project retrieve start` with `engagement.yaml`-driven scope + target alias | When a workflow needs scoped retrieve |
| `validate-engagement-yaml.sh` | Schema validation against ADR-0004 | Phase 7+ |
| `scratch-org-clean.sh` | Reap stale scratch orgs from `deploy-to-scratch.sh`'s "leave running" policy | Phase 7+ |
| `sf-org-drift-check.sh` | Detect when an engagement's `force-app/` diverges from the org's actual state (e.g., admin made declarative changes in Setup without committing) | Future |
