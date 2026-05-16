# Commands

Markdown prompt files invoked by workflow nodes. Each `command: <name>` reference in a workflow YAML resolves to a file in this directory. **All shipped** as of 2026-05-15 — backbone commands, the `sf-apex-change-*` per-step commands, the six `sf-discover-*` commands (including the three security commands per [ADR-0013](../decisions/0013-engagement-security-documentation.md)), and the four-per-family per-step commands for the Phase 7 task families (`sf-metadata-change-*`, `sf-flow-change-*`, `sf-permission-change-*`, `sf-lwc-change-*`, `sf-integration-change-*`, `sf-data-correction-*`) plus the orchestrator's `sf-orchestrator-multi-family-plan.md`. Per-family `*-classify.md` files are intentionally inline `prompt:` nodes inside their workflow YAMLs (their prompts are workflow-specific enough that the shared-prompt benefit doesn't apply).

> **What goes here?** One markdown file per named command. Workflows reference commands by basename (e.g., `command: pull-jira-context` → `commands/pull-jira-context.md`). The file's content is the prompt the workflow agent uses for that node.

## Why command files (instead of inline prompts)

Archon's separation of `commands/` from `workflows/` lets multiple workflows share the same prompt without duplication. The standard backbone steps (pull Jira, verify org context, load engagement context, update Jira, log run) are command files referenced by every harness workflow.

## Planned command set

These are the canonical commands that the structural backbone requires. Each will be authored in Phase 4 as part of authoring the first workflow.

### Backbone commands (shared across all workflows)

| Command | Purpose |
|---|---|
| `pull-jira-context.md` | Fetch Jira ticket via MCP, parse title/description/AC/comments/labels/status. Also fetches parent epic + sub-tasks + blocks/depends as read-only context. Also extracts URLs from the ticket's `## Context` section / opt-in custom field / `--context` flag and fetches their content via the right tool (Drive MCP, WebFetch, etc.) per [ADR-0015](../decisions/0015-external-context-from-tickets.md) |
| `verify-org-context.md` | Read `engagement.yaml`, check SF CLI alias is authorized, confirm API version |
| `load-engagement-context.md` | Load engagement docs relevant to the task (objects, features, flows, integrations, security) |
| `post-jira-comment.md` | Post a single structured comment to a Jira ticket at a defined workflow checkpoint. Comments follow per-checkpoint templates (workflow-started / plan-posted / validation-result / completion-success / completion-failure / multi-family-completion) so they're skimmable and consistent across all engagements |
| `transition-jira-status.md` | Transition a Jira ticket to a specific status using the engagement's `jira.statuses` mapping. Walks the transition graph up to 2 hops to reach the target |
| `update-jira-on-completion.md` | End-of-workflow Jira write-back: composes the structured completion comment + transitions to in_review. Handles both single-family runs (own results) and orchestrated runs (consolidated multi-family summary). Read-only invariant: only the typed-in ticket is touched, never related tickets |
| `update-jira-on-failure.md` | Post failure comment with diagnostics, leave ticket in current status |

### Per-workflow commands

Each workflow has its own per-step command files. All seven task families follow the same plan/execute/validate/document shape; the difference is in what they plan, execute, validate, and document.

**`sf-apex-change`** ([ADR-0009](../decisions/0009-sf-apex-change-scope-and-gates.md)):

| Command | Purpose |
|---|---|
| `sf-apex-change-plan.md` | Produce the structured plan: file changes, test strategy, doc outputs, risks |
| `sf-apex-change-execute.md` | Implement the change against the working tree (no deploy/test/Jira — those are downstream) |
| `sf-apex-change-validate.md` | Orchestrate the four validation scripts (deploy, tests+coverage, FLS/CRUD, destructive) and aggregate |
| `sf-apex-change-document.md` | Aggressively update every state-of-org doc the change touched (per ADR-0010); no per-ticket changelog |

**`sf-metadata-change`** ([ADR-0018](../decisions/0018-sf-metadata-change-scope-and-gates.md)):

| Command | Purpose |
|---|---|
| `sf-metadata-change-plan.md` | Plan custom-object / field / validation-rule / page-layout / record-type / picklist changes; identify which profiles/PSs need FLS updates |
| `sf-metadata-change-execute.md` | Write the metadata XML files (objects, fields, layouts, etc.); does not touch Apex or LWC |
| `sf-metadata-change-validate.md` | Deploy + run the FLS-coverage cross-check (flags newly-added fields invisible to every profile/PS) + destructive-change check |
| `sf-metadata-change-document.md` | Update `docs/objects/*.md` + any feature/security doc that references touched objects |

**`sf-flow-change`** ([ADR-0019](../decisions/0019-sf-flow-change-scope-and-gates.md)):

| Command | Purpose |
|---|---|
| `sf-flow-change-plan.md` | Plan record-triggered / scheduled / screen / autolaunched Flow changes; identify referenced Apex actions + subflows |
| `sf-flow-change-execute.md` | Write the Flow XML; respect Flow versioning conventions; activate as the final write step |
| `sf-flow-change-validate.md` | Deploy + verify activation via `FlowDefinitionView` + `scripts/check-flow-references.sh` (invocable Apex / subflows / objects / fields exist) |
| `sf-flow-change-document.md` | Update `docs/flows/*.md` with new step diagrams + decision logic + dependencies |

**`sf-permission-change`** ([ADR-0020](../decisions/0020-sf-permission-change-scope-and-gates.md)):

| Command | Purpose |
|---|---|
| `sf-permission-change-plan.md` | Plan profile / permission-set / PSG / custom-permission / sharing-rule / OWD / group / queue changes; classify blast radius into 3 tiers |
| `sf-permission-change-execute.md` | Write the permission XML / metadata; preserve hand-edits in unchanged sections |
| `sf-permission-change-validate.md` | Deploy + three-tier confirm (`CONFIRM-OWD` for org-wide-default changes / `CONFIRM` for sharing-rule + PSG / `y` for profile + PS edits) |
| `sf-permission-change-document.md` | Update `docs/security/profiles/*.md`, `docs/security/permission-sets/*.md`, and `sharing-model.md` to reflect the new posture |

**`sf-lwc-change`** ([ADR-0021](../decisions/0021-sf-lwc-change-scope-and-gates.md)):

| Command | Purpose |
|---|---|
| `sf-lwc-change-plan.md` | Plan LWC + backing `@AuraEnabled` Apex changes; identify Jest tests + a11y requirements |
| `sf-lwc-change-execute.md` | Write the LWC bundle (`.js` / `.html` / `.css` / `.js-meta.xml`) + the controller Apex; write/update Jest |
| `sf-lwc-change-validate.md` | 6-substep validate: deploy + Apex tests + Jest + a11y checks + FLS/CRUD + `scripts/check-lwc-controller-contract.sh` (every `@salesforce/apex/...` import resolves to a real `@AuraEnabled` method with matching signature) |
| `sf-lwc-change-document.md` | Update the relevant feature doc + add the LWC under "Components" in any object docs it consumes |

**`sf-integration-change`** ([ADR-0022](../decisions/0022-sf-integration-change-scope-and-gates.md)):

| Command | Purpose |
|---|---|
| `sf-integration-change-plan.md` | Plan callout / webhook / Named Credential / External Service / Platform Event / CDC / Connected App / OAuth-flow changes; identify the external system |
| `sf-integration-change-execute.md` | Write the integration metadata + supporting Apex; ALL secrets stay outside the workspace (per ADR-0008) |
| `sf-integration-change-validate.md` | Deploy + credentials-hygiene regex scan (no API keys / OAuth tokens / Basic-Auth literals in source); endpoint reachability check when feasible |
| `sf-integration-change-document.md` | Update `docs/integrations/<external-system>.md` with endpoints + auth model + retry posture + payload contracts |

**`sf-data-correction`** ([ADR-0023](../decisions/0023-sf-data-correction-scope-and-gates.md)):

| Command | Purpose |
|---|---|
| `sf-data-correction-plan.md` | Plan one-off DML / anonymous Apex; estimate affected-record count; check engagement's `salesforce.coverage.data_corrections.restricted_objects` allowlist |
| `sf-data-correction-execute.md` | Write BOTH the dry-run script (read-only count) AND the live script (actual writes); paired so the gate can compare them |
| `sf-data-correction-validate.md` | Two-phase: run dry-run, get actual count; gate-post-validate fires UNCONDITIONALLY with the count; only then run the live script. Compute dry-run-vs-actual delta — refuse to log success above the per-engagement delta tolerance |
| `sf-data-correction-document.md` | Light docs; the Jira comment + the cost-log entry are the durable record. Update object docs only when the correction reveals a data-integrity assumption worth documenting |

**`sf-orchestrator`** ([ADR-0017](../decisions/0017-multi-family-orchestrator.md)):

| Command | Purpose |
|---|---|
| `sf-orchestrator-multi-family-plan.md` | Take the dispatcher's classified `families: array`, order them by dependency (metadata → flow → apex → lwc → integration → permission → data-correction), refuse if more than 4 families, estimate cumulative cost, surface cross-family inconsistencies (e.g., apex references a field the metadata family isn't actually adding), produce the consolidated execution plan + the per-family ARGUMENTS payloads |

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

(Per-family sub-type classification is an inline `prompt:` node in each workflow YAML, not a separate command file — those prompts are workflow-specific.)

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
