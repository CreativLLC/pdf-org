---
title: Security
audience: public
last_updated: 2026-05-15
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - ../index.md
  - sharing-model.md
---

# Security — Meditrina

The consolidated security and access-control posture of the org, auto-generated from `force-app/main/default/` metadata by `sf-discover-document-security-*` workflows per ADR-0013. The detail lives in the per-artifact files below; the [`sharing-model.md`](./sharing-model.md) is the rolled-up view that compliance/audit readers should start with.

## What's in this section

- [`sharing-model.md`](./sharing-model.md) — Org-Wide Defaults, sharing rules, Apex sharing, implicit sharing, Restriction Rules summary.
- [`custom-permissions.md`](./custom-permissions.md) — Custom Permissions + where they're checked in Apex / Flow.
- [`public-groups-and-queues.md`](./public-groups-and-queues.md) — Public Groups + Queues + their purposes.
- [`apex-sharing.md`](./apex-sharing.md) — Programmatic sharing in Apex (`__Share` records, `Database.runAs` boundaries).
- [`permission-set-groups.md`](./permission-set-groups.md) — Permission Set Groups (PSGs) in use.
- [`profiles/`](./profiles/) — One file per profile in this engagement.
- [`permission-sets/`](./permission-sets/) — One file per permission set.
