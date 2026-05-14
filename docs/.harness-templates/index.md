---
title: Engagement Documentation Index
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <archon-run-id | human-name>
related_tickets: []
related_docs: [README.md, architecture/overview.md]
---

# `<Client Name>` — Engagement Documentation Index

<!--
TEMPLATE: `docs/index.md` — the AI navigation entry point per
[ADR-0010](../decisions/0010-engagement-documentation-model.md).

An AI agent picking up a task on this engagement loads this file FIRST.
It maps task types and trigger phrases to the small relevant subset of
docs the agent should load — instead of pulling the whole `docs/` tree
into context.

Maintained by: every `/sf` run that creates a new object, feature, or
integration doc updates the relevant index list below. Manual edits
welcome for description fine-tuning.
-->

> **For AI agents:** load this file first, then load ONLY the docs in the
> "Quick paths" section relevant to your current task. Do not load the
> entire `docs/` tree by default.

## Quick paths

### Working on Apex on a specific object

Load: `docs/objects/<ObjectAPIName>.md` + the Apex classes referenced therein.

### Working on a Flow

Load: `docs/flows/<FlowName>.md` + `docs/objects/<primary-object>.md`.

### Adding or modifying a feature

Load: `docs/features/<closest-feature>.md` + the object docs that feature references.

### Touching an external integration

Load: `docs/integrations/<system>.md` + any object docs the integration syncs with.

### Designing a new architectural pattern

Load: `docs/architecture/overview.md` + relevant `docs/decisions/*.md` ADRs.

### Onboarding to the engagement (humans)

Read: `docs/README.md` → `docs/architecture/overview.md` → relevant feature docs from the index below.

---

## Object index

The canonical reference layer (one doc per significant object).

| Object | Description |
|---|---|
| [`<ObjectAPIName>`](./objects/<ObjectAPIName>.md) | <one-line description: what this object represents, its primary purpose in the engagement> |

<!-- Add new rows as `/sf` runs create new object docs. -->

## Feature index

The derived business-facing layer (one doc per significant feature). Each entry links to the canonical object/flow/integration docs for technical detail.

| Feature | Description |
|---|---|
| [`<feature-slug>`](./features/<feature-slug>.md) | <one-line business-facing description: what the feature does for end users> |

<!-- Add new rows as `/sf` runs create new feature docs. -->

## Flow index

Significant Flows (record-triggered, scheduled, screen, subflows).

| Flow | Purpose |
|---|---|
| [`<FlowName>`](./flows/<FlowName>.md) | <one-line description: what the Flow does and when it fires> |

## Integration index

External systems the org integrates with.

| Integration | Purpose |
|---|---|
| [`<SystemName>`](./integrations/<SystemName>.md) | <one-line description: what the integration does and which objects it syncs> |

## Architectural decisions

ADRs that record long-lived rationale for this engagement.

See [`decisions/`](./decisions/) for the full list. Recent / highest-impact:

- [`<NNNN-slug>`](./decisions/<NNNN-slug>.md) — <one-line summary>

---

## How this index stays current

- Every `/sf` run that creates a new object / feature / flow / integration doc adds an entry to the corresponding section above ([ADR-0010 §3](../../.archon/decisions/0010-engagement-documentation-model.md)).
- Descriptions on existing entries are updated when a `/sf` run materially changes what the underlying doc describes.
- If you see a stale or missing entry, edit this file directly — it's not generated.
