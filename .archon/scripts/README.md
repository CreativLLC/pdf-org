# Scripts

Shell utilities. Two categories:

1. **Bootstrap scripts** (`harness-machine-setup.sh`, `harness-init.sh`) — Phase 6. Run on the engineer's machine, not from within workflows. Set up everything needed to use the harness.
2. **Workflow utilities** (`verify-jira-integration.sh` and Phase 4+ additions) — Shell helpers invoked from `bash:` workflow nodes for deterministic operations.

## Bootstrap scripts

| Script | Stage | When to run | What it does |
|---|---|---|---|
| [`harness-machine-setup.sh`](./harness-machine-setup.sh) | Stage 1 | Once per engineer (re-run after tool upgrades) | Verifies tools (git, gh, bun, sf, claude, code, uv, direnv), VSCode extensions, auth (GitHub + SF + Dev Hub), network reachability, and the direnv shell hook. Writes `~/.archon/machine-state.json` on success. |
| [`harness-init.sh`](./harness-init.sh) | Stage 2 | Once per new engagement | Prompts for engagement values, copies harness content into the engagement repo's `.archon/`, generates `engagement.yaml` + `.envrc` + `.mcp.json` + `CLAUDE.md` + `docs/` skeleton, writes credentials to `~/.archon/credentials/<alias>/.envrc` (off-workspace), validates by hitting the Jira API. |
| [`harness-update.sh`](./harness-update.sh) | Update | Per engagement, whenever a newer harness version warrants pulling in | Refreshes `.archon/{workflows,commands,scripts,patterns,standards}/` and `docs/.harness-templates/`, adds any new `.claude/commands/` or `.claude/skills/`, rewrites just the `harness_version` line in `engagement.yaml`. Leaves engagement-specific files (`.envrc`, `.mcp.json`, `CLAUDE.md`, authored docs) alone. Audit-logged to `_internal/bootstrap-runs/`. |

### Stage 1 — engineer-machine setup

```bash
# From anywhere
<path-to-harness>/scripts/harness-machine-setup.sh
```

Idempotent. Re-run after any tool upgrade or re-authentication. The script never installs anything — it only checks and reports. If a check fails, the output tells you the exact command to fix it.

### Stage 2 — engagement bootstrap

```bash
# Create your new engagement repo, then:
cd <engagement-repo>
<path-to-harness>/scripts/harness-init.sh
```

The script prompts you through engagement identity, Salesforce config (from `sf org list`), Jira config (URL, project key, status names, API token), and documentation audiences. Then it writes all the engagement-repo files and validates by hitting Jira's API with your credentials.

**Where to run from**: VSCode's integrated terminal works, but for maximum safety (your API token is prompted live), an external terminal (Terminal.app, iTerm) is preferred. The script writes the token to `~/.archon/credentials/<alias>/.envrc` — outside any IDE workspace.

## Workflow utilities

| Script | Purpose |
|---|---|
| [`verify-jira-integration.sh`](./verify-jira-integration.sh) | Phase 3 layer-1 verification: round-trip Jira read + comment + transition. Uses env vars loaded by direnv per ADR-0008. |
| [`deploy-to-scratch.sh`](./deploy-to-scratch.sh) | Phase 4 — creates (or reuses) the engagement's scratch org and deploys changed files; structured JSON to `$ARTIFACTS_DIR/deploy-to-scratch.json`. |
| [`run-apex-tests.sh`](./run-apex-tests.sh) | Phase 4 — runs Apex tests against the scratch org; enforces per-class coverage gate from `engagement.yaml.salesforce.coverage.per_class_target`; structured JSON output. |
| [`check-destructive-changes.sh`](./check-destructive-changes.sh) | Phase 4 — static, regex-based diff check for destructive Apex changes per ADR-0009 §3 (file deletions, public-method removal, signature changes, visibility downgrades, removed `@AuraEnabled`/`@InvocableMethod`). |
| [`check-fls-crud.sh`](./check-fls-crud.sh) | Phase 4 — static, regex-based check for `WITH USER_MODE` on SOQL and `Security.stripInaccessible` on DML per ADR-0009 §7. Intentionally regex-based; false positives surface at the post-validate gate. |

## Conventions (per [ADR-0003](../decisions/0003-workflow-yaml-scope-and-naming.md))

Every script in this directory:

1. Begins with `#!/usr/bin/env bash` and `set -euo pipefail`.
2. Has a header comment explaining purpose, inputs, outputs, and exit codes.
3. Reads configuration from environment variables (or, for workflow scripts, sources `.env` first if present).
4. Emits structured output (JSON or env-var-style) to stdout for workflow consumption.
5. Is executable (`chmod +x`).

> **What goes here?** Bash scripts (`.sh`) invoked from workflow `bash:` nodes for deterministic operations: SF CLI wrappers, validation helpers, file inspection. Anything that should run *deterministically* (no LLM) and benefits from being shell rather than embedded in YAML.

## Why scripts (instead of inline bash)

Archon's `bash:` workflow nodes can contain inline shell, but for anything more than a few lines of logic, scripts win:

- Easier to read and maintain than escaped multi-line YAML strings.
- Testable in isolation (unit tests via `bats` or similar).
- Reusable across workflows.
- Can be invoked locally by engineers for debugging.

## Planned future scripts

These are noted for future phases but not yet authored.

| Script | Purpose | Phase |
|---|---|---|
| `pull-org-metadata.sh` | Wrap `sf project retrieve start` with engagement.yaml-driven scope and target alias | When a workflow needs scoped retrieve (Phase 4+ extension) |
| `validate-engagement-yaml.sh` | Schema validation against ADR-0004 (e.g., via Python `pydantic` or Node `zod`) | Phase 7+ |
| ~~`harness-update.sh`~~ | ✅ Shipped (Phase 6.5 MVP) — see above. Future: semver-aware version comparison once tags exist; CLAUDE.md / .mcp.json drift diffs. | — |
| `scratch-org-clean.sh` | Reap stale scratch orgs created by `deploy-to-scratch.sh`'s "leave running" policy | Phase 7+ |

## Naming

| Element | Convention | Example |
|---|---|---|
| Filename | `<verb>-<noun>.sh` (kebab-case) | `verify-credentials.sh`, `pull-org-metadata.sh` |
| Invocation in workflow | `bash: ./.archon/scripts/<name>.sh <args>` | (in workflow YAML) |
| Exit codes | 0 = success, non-zero = structured failure (specific codes per script, documented in the script's header) | |

## Conventions

Every script in this directory:

1. Begins with a `#!/usr/bin/env bash` shebang.
2. Uses `set -euo pipefail` to fail fast.
3. Has a header comment explaining purpose, inputs, outputs, and exit codes.
4. Reads configuration from environment variables, **not** from positional args (which are reserved for ticket-specific data).
5. Emits structured output (JSON or env-var-style) to stdout for the workflow to consume.
6. Emits human-readable diagnostics to stderr.
7. Is executable (`chmod +x`).
8. Is tested in isolation where feasible.

## Adding a new script

Adding a script is part of the workflow PR that uses it. The script and its tests ship in the same PR as the workflow and the command file(s) that invoke it.
