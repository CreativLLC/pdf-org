# Architecture

The "why" of Acme Co.'s renewal management system. Documents in this directory describe the org at the *system* level — how objects relate, how data flows, why the topology is what it is. Per-object detail belongs in [`../objects/`](../objects/); per-flow detail in [`../flows/`](../flows/); per-integration detail in [`../integrations/`](../integrations/).

## Documents in this directory

| Doc | Purpose |
|---|---|
| [`overview.md`](./overview.md) | The system's purpose, top-level object model, and primary processes |
| `sharing-model.md` *(Phase 1.5)* | Roles, profiles, OWD, sharing rules, and the rationale |
| `integration-topology.md` *(Phase 1.5)* | External systems, directions, sync vs async, failure isolation |

## When to add a doc here

Add an architecture doc when:

- A choice spans multiple objects or processes (e.g., "we use platform events as the spine for cross-system sync") and needs a single canonical explanation.
- A new system-level concept is introduced (e.g., "the renewal lifecycle has these five states; here's how they map to billing").
- An ADR's consequences need a longer narrative form than the ADR itself supports.

Do *not* add an architecture doc for a single-object or single-flow concern — those live in `objects/` or `flows/`.
