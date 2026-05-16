# Commands

Markdown prompt files invoked by workflow nodes. Each `command: <name>` reference in a workflow YAML resolves to a file in this directory. **All shipped** as of 2026-05-14 — backbone commands, the `sf-apex-change-*` per-step commands, the six `sf-discover-*` commands (including the three new security commands per [ADR-0013](../decisions/0013-engagement-security-documentation.md)). `sf-apex-change-classify.md` is intentionally inline in `workflows/sf-apex-change.yaml` (a `prompt:` node, not a separate command file) because its prompt is workflow-specific enough that the shared-prompt benefit doesn't apply.

> **What goes here?** One markdown file per named command. Workflows reference commands by basename (e.g., `command: pull-jira-context` → `commands/pull-jira-context.md`). The file's content is the prompt the workflow agent uses for that node.

## Why command files (instead of inline prompts)

Archon's separation of `commands/` from `workflows/` lets multiple workflows share the same prompt without duplication. The standard backbone steps (pull Jira, verify org context, load engagement context, update Jira, log run) are command files referenced by every harness workflow.

## Planned command set

These are the canonical commands that the structural backbone requires. Each will be authored in Phase 4 as part of authoring the first workflow.

### Backbone commands (shared across all workflows)

| Command | Purpose |
|---|---|
| `pull-jira-context.md` | Fetch Jira ticket via MCP, parse title/description/AC/comments/labels/status. Also fetches parent epic + sub-tasks + blocks/depends as read-only context (Q3). Also extracts URLs from the ticket's `## Context` section / opt-in custom field / `--context` flag and fetches their content via the right tool (Drive MCP, WebFetch, etc.) per [ADR-0015](../decisions/0015-external-context-from-tickets.md) |
| `verify-org-context.md` | Read `engagement.yaml`, check SF CLI alias is authorized, confirm API version |
| `load-engagement-context.md` | Load engagement docs relevant to the task (objects, features, flows, integrations, security) |
| `update-jira-on-completion.md` | Post structured progress comment + walk Jira transition graph (up to 2 hops) to reach in_review. Read-only invariant: only the typed-in ticket is touched, never related tickets |
| `update-jira-on-failure.md` | Post failure comment with diagnostics, leave ticket in current status |
| `log-run.md` | Append structured entry to harness run log + cost log per [ADR-0016](../decisions/0016-cost-observability.md) |
| `verify-credentials.md` | Validate that all required env vars are set before any work begins |

### Per-workflow commands

Each workflow has its own per-step command files.

**`sf-apex-change`** (Phase 4):

| Command | Purpose |
|---|---|
| `sf-apex-change-plan.md` | Produce the structured plan: file changes, test strategy, doc outputs, risks |
| `sf-apex-change-execute.md` | Implement the change against the working tree (no deploy/test/Jira — those are downstream) |
| `sf-apex-change-validate.md` | Orchestrate the four validation scripts (deploy, tests+coverage, FLS/CRUD, destructive) and aggregate |
| `sf-apex-change-document.md` | Aggressively update every state-of-org doc the change touched (per ADR-0010); no per-ticket changelog |

**`sf-discover-org`** (per [ADR-0011](../decisions/0011-sf-discover-org-workflow.md) + [ADR-0013](../decisions/0013-engagement-security-documentation.md)):

| Command | Purpose |
|---|---|
| `sf-discover-classify.md` | Inventory `force-app/main/default/`, decide which objects / flows / integrations are significant enough to document |
| `sf-discover-document-objects.md` | Iterate over significant objects, write/update `docs/objects/*.md` (opus[1m]) |
| `sf-discover-document-flows.md` | Iterate over significant Flows, write/update `docs/flows/*.md` (opus[1m]) |
| `sf-discover-document-integrations.md` | Inventory + document external integrations → `docs/integrations/*.md` (opus[1m]) |
| `sf-discover-document-security-overview.md` | Produce the consolidated security docs: sharing-model, custom-permissions, public-groups-and-queues, apex-sharing, permission-set-groups + section README |
| `sf-discover-document-profiles.md` | Iterate over `force-app/main/default/profiles/`, write one file per profile |
| `sf-discover-document-permission-sets.md` | Iterate over `force-app/main/default/permissionsets/`, write one file per PS |
| `sf-discover-synthesize-features.md` | Cluster the canonical docs into business-facing features → `docs/features/*.md` |
| `sf-discover-update-index.md` | Rebuild `docs/index.md` from everything that now exists; runs the link validator |

(Sub-type classification within `sf-apex-change` is an inline `prompt:` node in the workflow YAML, not a separate command file — its prompt is workflow-specific.)

## Naming

| Element | Convention | Example |
|---|---|---|
| Filename | `<scope>-<verb>.md` (kebab-case) | `pull-jira-context.md`, `sf-apex-change-classify.md` |
| Reference in workflow YAML | filename without `.md` | `command: pull-jira-context` |
| Shared backbone commands | no `sf-` prefix | `pull-jira-context.md` |
| Workflow-specific commands | `sf-<workflow>-<step>.md` | `sf-apex-change-execute.md` |

## What a command file looks like

Each command is a markdown prompt. By Archon convention:

- Front-loaded with the agent's role and goal in 2–3 sentences.
- Followed by the inputs available (`$extract-jira-key.output.ticket`, `$pull-jira-context.output`, etc. — see the upstream nodes the workflow's `depends_on` declares).
- Then explicit task instructions, often as a numbered list.
- Then the expected output format (often a structured object the workflow's downstream nodes can consume).

See [`Archon-dev/.archon/commands/defaults/archon-implement-tasks.md`](../../ArchonSFJira/Archon-dev/.archon/commands/defaults/archon-implement-tasks.md) and similar files for the form.

## Adding a new command

Adding a command is normally part of adding or modifying a workflow. The PR includes:

1. The command file.
2. The workflow YAML modification(s) that reference it.
3. Tests demonstrating the command works as expected (Phase 4+ when test infrastructure exists).
