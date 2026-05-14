---
title: <Feature Display Name>
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <archon-run-id | human-name>
related_tickets: [<JIRA-KEY>, ...]
related_docs: [../objects/<ObjectAPIName>.md, ...]
---

# `<Feature Display Name>`

<!--
TEMPLATE: a feature doc lives at `docs/features/<feature-slug>.md`. Per
[ADR-0010](../decisions/0010-engagement-documentation-model.md), this is the
DERIVED business-facing layer — it summarizes a cross-cutting feature and
links to the canonical object/flow/integration docs for technical detail.

Audience: PMs, admins, occasional client stakeholders. Keep it readable,
not deep-technical. Heavy technical detail goes in the linked canonical
docs.

State, not history: describe what the feature does TODAY. Don't write
"as of <date>, this changed." Change history lives in Jira and git log.
-->

> **One-line summary** of what the feature does for an end user.

## Overview

What is this feature, in 2–4 sentences? Who uses it (admin, end user, integration)? When?

## How it works

A business-readable walkthrough of the feature's behavior. **Use a numbered list of "what happens" steps if the feature is a flow.**

Example structure:

1. **Trigger** — what initiates the feature (a record save, a scheduled job, a button click, an inbound webhook).
2. **Processing** — what happens. Keep it conceptual. Link to canonical docs for the Apex / Flow / integration that implements each step.
3. **Outcome** — what state the user / system is in afterward. What downstream behavior is enabled.

Cross-references to canonical docs:

- Object detail: [`<ObjectAPIName>`](../objects/<ObjectAPIName>.md)
- Underlying flow: [`<FlowName>`](../flows/<FlowName>.md)
- External integration: [`<SystemName>`](../integrations/<SystemName>.md)

## Acceptance signals

How does a user know the feature is working correctly? What's visible to them when it succeeds?

- Visible state on a record (e.g., `Status = 'Active'`).
- An email / notification sent.
- A downstream action enabled (e.g., a button becoming available).

## Known limitations

Honest list of edge cases the feature does NOT handle (or handles imperfectly). Avoids the trap of overstating capability.

- Limitation 1 — what doesn't work.
- Limitation 2 — known workaround if any.

## Governing decisions

ADRs that constrain how this feature works:

- [`<NNNN-slug>`](../decisions/<NNNN-slug>.md) — <one-line summary of what the ADR locked>

## Related tickets

(Frontmatter `related_tickets` is the authoritative list. This section is for human-readable summary if useful.)
