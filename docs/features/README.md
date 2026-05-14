---
title: Features
audience: public
last_updated: 2026-05-13
last_updated_by: harness-phase-5
related_tickets: []
related_docs: [../INDEX.md, ../objects/README.md]
---

# Features

The derived business-facing documentation layer per [ADR-0010](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/decisions/0010-engagement-documentation-model.md). One doc per significant user-facing feature.

**Distinction from `docs/objects/`:**

- `docs/objects/<Object>.md` — **canonical technical reference.** Dense, complete, mirrors SF metadata. Read by engineers and AI agents needing technical detail.
- `docs/features/<feature-slug>.md` — **business-facing summary.** PM/admin/stakeholder readable. Describes the feature's behavior in user terms. Links to canonical object docs for the deep technical detail; doesn't duplicate it.

A change to an object's behavior updates both the canonical object doc (deep) and the affected feature doc (summary), each in their own register.

## When to author a new feature doc

Create a new `features/<slug>.md` when:

- A `/sf` run introduces a recognizably-new user-facing capability (not just a refactor or utility add).
- The feature cuts across multiple objects/flows/integrations such that no single canonical doc tells the whole story.
- A stakeholder is likely to ask "how does X work?" and X is a user-flow, not a single object.

Don't create one for:

- Utility classes / helpers that aren't visible to end users.
- Pure refactors (preserve in `objects/*.md` updates only).
- Bug fixes that don't change behavior visibly.

## Style

Business-readable, not deep-technical. If a section feels like "this is the implementation detail," it belongs in `objects/*.md`, not here. Link instead.
