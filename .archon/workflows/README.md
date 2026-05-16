# Workflows

Archon DAG YAML files that define how each kind of Salesforce work is performed end-to-end. **Phase 4 shipped the first pair** — [`sf-dispatcher.yaml`](./sf-dispatcher.yaml) (the `/sf` entry point) and [`sf-apex-change.yaml`](./sf-apex-change.yaml) (the first task-family workflow). **Phase 5 added [`sf-discover-org.yaml`](./sf-discover-org.yaml)** — one-time-per-engagement baseline doc generation from existing SFDX metadata, per [ADR-0011](../decisions/0011-sf-discover-org-workflow.md). The remaining task-family workflows ship in Phase 7+.

> **What goes here?** YAML files matching the conventions in [`../decisions/0003-workflow-yaml-scope-and-naming.md`](../decisions/0003-workflow-yaml-scope-and-naming.md). Each YAML defines a coarse task family and uses internal classification branches for variation. The structural backbone (pull Jira → classify → smoke-validate → verify org → load context → plan → gate → execute → validate → document → update Jira → log) is required.

## Workflow set (per [ADR-0003](../decisions/0003-workflow-yaml-scope-and-naming.md))

| Workflow | Covers | Status |
|---|---|---|
| [`sf-dispatcher.yaml`](./sf-dispatcher.yaml) | The `/sf` entry point: pulls Jira context (incl. parent epic + sub-tasks per ADR-0011), external context per [ADR-0015](../decisions/0015-external-context-from-tickets.md), classifies, presents confirmation, invokes the matching task-family workflow | ✅ Shipped |
| [`sf-apex-change.yaml`](./sf-apex-change.yaml) | Create / modify / extend / delete / rename Apex classes, triggers, test classes — per [ADR-0009](../decisions/0009-sf-apex-change-scope-and-gates.md) | ✅ Shipped |
| [`sf-discover-org.yaml`](./sf-discover-org.yaml) | One-time-per-engagement baseline doc generation from existing SFDX metadata — six parallel `opus[1m]` nodes (objects / flows / integrations / security overview / profiles / permission sets) per [ADR-0011](../decisions/0011-sf-discover-org-workflow.md) + [ADR-0013](../decisions/0013-engagement-security-documentation.md) | ✅ Shipped |
| `sf-flow-change.yaml` | Record-triggered Flows, scheduled Flows, screen Flows, subflows | Phase 7+ |
| `sf-metadata-change.yaml` | Custom objects, fields, validation rules, page layouts, picklists | Phase 7+ |
| `sf-lwc-change.yaml` | Lightning Web Components and their backing Apex | Phase 7+ |
| `sf-integration-change.yaml` | External integrations: callouts, webhooks, named credentials, platform events | Phase 7+ |
| `sf-permission-change.yaml` | Permission sets, profiles, sharing rules, OWD changes | Phase 7+ |
| `sf-data-correction.yaml` | One-off DML or anonymous Apex against existing data (very tightly gated) | Phase 7+ |

## How a workflow YAML looks

The structure follows Archon's existing patterns — see [`Archon-dev/.archon/workflows/experimental/archon-fix-github-issue-experimental.yaml`](../../ArchonSFJira/Archon-dev/.archon/workflows/experimental/archon-fix-github-issue-experimental.yaml) for a fully-realized example. Our workflows adopt the same DAG node shape (`prompt:`, `bash:`, `command:`, `loop:`, `when:`, `depends_on:`) and add SF-specific gates.

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
