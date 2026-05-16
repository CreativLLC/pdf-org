---
title: Apex (programmatic) sharing
audience: public
last_updated: 2026-05-15
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - README.md
  - sharing-model.md
---

# Apex (programmatic) sharing

Apex programmatic sharing is when code creates `<Object>__Share` records (e.g., `Account__Share`, `Renewal__Share`) directly via DML to grant a user, group, or role access to a record beyond what OWD + sharing rules + role hierarchy provide. It's typically used when access depends on runtime conditions that declarative sharing can't express.

_None — all sharing is declarative._

No `__Share` token usage was found in `force-app/main/default/classes/`. All record visibility in this engagement is governed by OWD, the single `Share_with_Internal_Users` Account ownership rule, the role hierarchy, and the implicit Account → child-record sharing.
