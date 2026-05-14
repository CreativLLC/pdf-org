---
title: "Override: <standard name>"
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <human-name>
related_tickets: [<JIRA-KEY-or-empty>]
related_docs: [<links-to-team-standard-being-overridden>]
---

# Override: `<standard name>`

<!--
TEMPLATE: Standards override. One file per engagement-specific deviation from a
team-wide standard, located at `engagement-repo/docs/standards/<kebab-name>.md`.

Standards overrides should be RARE. If you find yourself overriding multiple team
standards on the same engagement, that's signal that either the team standards
need revisiting or the engagement has a structural mismatch worth surfacing.

Every override requires a Jira ticket linked, an ADR explaining the rationale,
and a sunset condition (when this override should be revisited).
-->

## What this overrides

The team-wide standard being overridden. Link to the canonical version.

- **Team standard:** [`harness/standards/<standard>.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/standards/<standard>.md).
- **Section overridden:** `<specific section or rule>`.

## What the override is

The engagement-specific rule, in concrete terms.

- **Team default:** "<the team standard's rule, quoted>"
- **This engagement:** "<the override's rule>"

## Why

The reason this engagement needs to deviate. Two paragraphs at most.

What the team standard assumes that doesn't hold here. What constraint or requirement makes the deviation necessary. What we tried first that didn't work.

This rationale must be specific enough that a reader can evaluate whether the override is still warranted later.

## Scope

What this override applies to and what it doesn't.

- **Applies to:** <code, metadata, or process scope>.
- **Does NOT apply to:** <areas where the team default still holds>.

## Tradeoffs we're accepting

What we lose by overriding. Be explicit — every override has a cost.

- <tradeoff>
- <tradeoff>

## Sunset condition

When should this override be revisited or retired?

- **Trigger:** <event or date>.
- **Decision authority:** <role or team>.
- **Revisit ticket:** *(optional placeholder for the ticket that will reconsider this)*.

## References

- **Jira ticket(s):** `<JIRA-KEY>`.
- **ADR:** [`../decisions/NNNN-...md`](../decisions/NNNN-...md).
- **Team standard:** [`harness/standards/<standard>.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/standards/<standard>.md).
