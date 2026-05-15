---
title: Architecture
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs: [../index.md]
---

# Architecture — Meditrina

The "why" of Meditrina's Salesforce org: system overview, subsystem boundaries, sharing model, integration topology, and any cross-cutting design notes. The org contains two weakly-coupled subsystems — a legacy PSA core (time-and-billing, project resourcing) and a newer PDF generator POC — documented at the object level under [`../objects/`](../objects/) and at the feature level under [`../features/`](../features/).

## Index

*Empty until populated. Suggested first additions:*

- `overview.md` — high-level system map (mermaid diagrams of object subsystems)
- `sharing-model.md` — OWD + sharing rules + Apex sharing posture
- `integration-topology.md` — system context diagram (currently no external integrations, so this is a placeholder)

Architecture docs are authored by engineers, not auto-generated.
