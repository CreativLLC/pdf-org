# Workflows

Archon DAG YAML files that define how each kind of Salesforce work is performed end-to-end. **Phase 4 shipped the first pair** — [`sf-dispatcher.yaml`](./sf-dispatcher.yaml) (the `/sf` entry point) and [`sf-apex-change.yaml`](./sf-apex-change.yaml) (the first task-family workflow). **Phase 5 added [`sf-discover-org.yaml`](./sf-discover-org.yaml)** — one-time-per-engagement baseline doc generation from existing SFDX metadata, per [ADR-0011](../decisions/0011-sf-discover-org-workflow.md). **Phase 7 completed the task-family set** — six new family workflows (`sf-metadata-change`, `sf-flow-change`, `sf-permission-change`, `sf-lwc-change`, `sf-integration-change`, `sf-data-correction`) plus [`sf-orchestrator.yaml`](./sf-orchestrator.yaml) for tickets that legitimately span families (per [ADR-0017](../decisions/0017-multi-family-orchestrator.md)).

> **What goes here?** YAML files matching the conventions in [`../decisions/0003-workflow-yaml-scope-and-naming.md`](../decisions/0003-workflow-yaml-scope-and-naming.md). Each YAML defines a coarse task family and uses internal classification branches for variation. The structural backbone (pull Jira → classify → smoke-validate → verify org → load context → plan → gate → execute → validate → document → update Jira → log) is required.

## Workflow set (per [ADR-0003](../decisions/0003-workflow-yaml-scope-and-naming.md))

| Workflow | Covers | Status |
|---|---|---|
| [`sf-dispatcher.yaml`](./sf-dispatcher.yaml) | The `/sf` entry point: pulls Jira context (incl. parent epic + sub-tasks per ADR-0011), external context per [ADR-0015](../decisions/0015-external-context-from-tickets.md), classifies (single family or multi-family), presents confirmation, invokes the matching task-family workflow OR the orchestrator | ✅ Shipped |
| [`sf-orchestrator.yaml`](./sf-orchestrator.yaml) | Cross-family coordination for tickets that legitimately span multiple families (e.g., new custom field + Apex trigger that reads it + permission set that grants access). Orders families by dependency, invokes them sequentially with `--orchestrated true`, posts one consolidated Jira comment per [ADR-0017](../decisions/0017-multi-family-orchestrator.md) | ✅ Shipped |
| [`sf-apex-change.yaml`](./sf-apex-change.yaml) | Create / modify / extend / delete / rename Apex classes, triggers, test classes — per [ADR-0009](../decisions/0009-sf-apex-change-scope-and-gates.md) | ✅ Shipped |
| [`sf-metadata-change.yaml`](./sf-metadata-change.yaml) | Custom objects, custom fields, validation rules, page layouts, record types, picklists, formula fields — 14 sub-types per [ADR-0018](../decisions/0018-sf-metadata-change-scope-and-gates.md). Includes FLS-coverage cross-check that flags newly-added fields invisible to every profile/PS | ✅ Shipped |
| [`sf-flow-change.yaml`](./sf-flow-change.yaml) | Record-triggered Flows, scheduled Flows, screen Flows, subflows, autolaunched, platform-event-triggered Flows — 9 sub-types per [ADR-0019](../decisions/0019-sf-flow-change-scope-and-gates.md). Activation verification via `FlowDefinitionView` | ✅ Shipped |
| [`sf-permission-change.yaml`](./sf-permission-change.yaml) | Permission sets, profiles, permission set groups, custom permissions, sharing rules, OWD, public groups, queues — 14 sub-types per [ADR-0020](../decisions/0020-sf-permission-change-scope-and-gates.md). Three-tier confirm (CONFIRM-OWD / CONFIRM / y) escalating with org-wide blast radius | ✅ Shipped |
| [`sf-lwc-change.yaml`](./sf-lwc-change.yaml) | Lightning Web Components + their backing Apex controllers + Jest tests + a11y checks — 10 sub-types per [ADR-0021](../decisions/0021-sf-lwc-change-scope-and-gates.md). 6-substep validate (deploy + Apex tests + Jest + a11y + FLS/CRUD + controller contract) | ✅ Shipped |
| [`sf-integration-change.yaml`](./sf-integration-change.yaml) | Named credentials, external services, callouts, webhooks, platform events, change data capture, OAuth flows — 15 sub-types per [ADR-0022](../decisions/0022-sf-integration-change-scope-and-gates.md). Credentials hygiene check (regex scan for API keys/tokens in source) | ✅ Shipped |
| [`sf-data-correction.yaml`](./sf-data-correction.yaml) | One-off DML / anonymous Apex against existing data — 7 sub-types per [ADR-0023](../decisions/0023-sf-data-correction-scope-and-gates.md). Two-phase dry-run-then-live; unconditional pre-execute gate; restricted-objects engagement.yaml allowlist | ✅ Shipped |
| [`sf-discover-org.yaml`](./sf-discover-org.yaml) | One-time-per-engagement baseline doc generation from existing SFDX metadata — six parallel `opus[1m]` nodes (objects / flows / integrations / security overview / profiles / permission sets) per [ADR-0011](../decisions/0011-sf-discover-org-workflow.md) + [ADR-0013](../decisions/0013-engagement-security-documentation.md) | ✅ Shipped |

## How a workflow YAML looks

The structure follows Archon's existing patterns — see Archon's own [experimental workflow](https://github.com/coleam00/Archon/tree/main/.archon/workflows/experimental) for a fully-realized example. Our workflows adopt the same DAG node shape (`prompt:`, `bash:`, `command:`, `loop:`, `when:`, `depends_on:`) and add SF-specific gates.

## The orchestrator pattern (ADR-0017)

When a single ticket legitimately spans multiple families (e.g., GRIM-50 adds a custom field AND the Apex trigger that reads it AND the permission set that grants access), `sf-dispatcher` routes to `sf-orchestrator` instead of a single family. The orchestrator:

1. Orders families by dependency: metadata → flow → apex → lwc → integration → permission → data-correction.
2. Caps a single ticket at 4 families. Beyond that, the planner refuses and asks the engineer to split the ticket.
3. Invokes each family workflow sequentially with `--orchestrated true` in `$ARGUMENTS`, and a shared `$ORCHESTRATOR_RUN_ID` so families can drop their results in a known location.
4. Families detect orchestrated mode by grepping `$ARGUMENTS` for `--orchestrated true`. When set: they skip their own Jira comment / status transition, and write a JSON `family_result` to `_internal/orchestrator-runs/$ORCHESTRATOR_RUN_ID/sf-<family>.json` instead of emitting it to stdout (so the orchestrator can survive workflow stdout buffering).
5. After all families complete (or one fails), the orchestrator posts **one consolidated comment** to the Jira ticket and walks the transition graph. Single Jira comment per ticket — no matter how many families ran.

Every family workflow must satisfy this contract — see ADR-0017's "Family workflow contract" section for the full requirement list.

## Adding a new workflow

Adding a workflow is its own ADR. The PR includes:

1. The new ADR in [`../decisions/`](../decisions/) describing scope, gates, rationale.
2. The workflow YAML.
3. Any new command files in [`../commands/`](../commands/) the workflow references.
4. Any new patterns in [`../patterns/`](../patterns/) the workflow's classifier should match against.
5. Any new standards or doc-template additions if the workflow produces a new doc type.
6. Updates to this README's "Planned workflow set" table.
7. Test runs in the workbench (`ArchonSFJira/`) demonstrating the workflow on at least 2 representative tickets.

PRs that add a workflow without all of the above will be rejected in review.
