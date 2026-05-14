# Commands

Markdown prompt files invoked by workflow nodes. Each `command: <name>` reference in a workflow YAML resolves to a file in this directory. **Phase 4 populated** — backbone commands and the `sf-apex-change-*` per-step commands are in place. `sf-apex-change-classify.md` is intentionally inline in `workflows/sf-apex-change.yaml` (a `prompt:` node, not a separate command file) because its prompt is workflow-specific enough that the shared-prompt benefit doesn't apply.

> **What goes here?** One markdown file per named command. Workflows reference commands by basename (e.g., `command: pull-jira-context` → `commands/pull-jira-context.md`). The file's content is the prompt the workflow agent uses for that node.

## Why command files (instead of inline prompts)

Archon's separation of `commands/` from `workflows/` lets multiple workflows share the same prompt without duplication. The standard backbone steps (pull Jira, verify org context, load engagement context, update Jira, log run) are command files referenced by every harness workflow.

## Planned command set

These are the canonical commands that the structural backbone requires. Each will be authored in Phase 4 as part of authoring the first workflow.

### Backbone commands (shared across all workflows)

| Command | Purpose |
|---|---|
| `pull-jira-context.md` | Fetch Jira ticket via MCP, parse title/description/AC/comments/labels/status |
| `verify-org-context.md` | Read `engagement.yaml`, check SF CLI alias is authorized, confirm API version |
| `load-engagement-context.md` | Load engagement docs relevant to the task (objects, flows, integrations, recent changelog) |
| `update-jira-on-completion.md` | Post structured progress comment, transition status |
| `update-jira-on-failure.md` | Post failure comment with diagnostics, leave ticket in current status |
| `log-run.md` | Append structured entry to harness run log |
| `verify-credentials.md` | Validate that all required env vars are set before any work begins |

### Per-workflow commands

Each workflow has its own per-step command files. For `sf-apex-change` (shipped in Phase 4):

| Command | Purpose |
|---|---|
| `sf-apex-change-plan.md` | Produce the structured plan: file changes, test strategy, doc outputs, risks |
| `sf-apex-change-execute.md` | Implement the change against the working tree (no deploy/test/Jira — those are downstream) |
| `sf-apex-change-validate.md` | Orchestrate the four validation scripts (deploy, tests+coverage, FLS/CRUD, destructive) and aggregate |
| `sf-apex-change-document.md` | Write changelog entry; update `docs/objects/<Object>.md` for trigger changes |

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
- Followed by the inputs available (`$workflow.input.ticket`, `$pull-jira-context.output`, etc.).
- Then explicit task instructions, often as a numbered list.
- Then the expected output format (often a structured object the workflow's downstream nodes can consume).

See [`Archon-dev/.archon/commands/defaults/archon-implement-tasks.md`](../../ArchonSFJira/Archon-dev/.archon/commands/defaults/archon-implement-tasks.md) and similar files for the form.

## Adding a new command

Adding a command is normally part of adding or modifying a workflow. The PR includes:

1. The command file.
2. The workflow YAML modification(s) that reference it.
3. Tests demonstrating the command works as expected (Phase 4+ when test infrastructure exists).
