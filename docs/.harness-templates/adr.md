---
title: "<NNNN>: <Decision title>"
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <human-name | archon-run-id>
related_tickets: [<JIRA-KEYS>]
related_docs: [<related-architecture-or-object-docs>]
---

# `<NNNN>`: `<Decision title>`

<!--
TEMPLATE: Architectural Decision Record (MADR format). One file per significant
decision, located at `docs/decisions/NNNN-kebab-slug.md` where NNNN is a
zero-padded 4-digit sequence number.

ADRs document significant choices: a non-trivial architectural option that has
multiple plausible alternatives. Don't write ADRs for obvious choices or for
decisions already documented in code/metadata.

The MADR format: status, context, decision, consequences. Optionally:
considered options, decision drivers, validation.
-->

## Status

`<status>` — one of: **Proposed** / **Accepted** / **Deprecated** / **Superseded by [NNNN](./NNNN-...md)**.

If this ADR is superseded, link to the ADR that replaced it.

## Context and problem statement

What situation prompted this decision? Describe the constraints, the existing system, and the question being answered. Two to four paragraphs.

Frame as a question: *"How should we ...?"* or *"What is the right way to ...?"* This is the question this ADR answers.

## Decision drivers

The forces that shape the decision. Three to seven, prioritized.

- **<Driver 1>** — <one-line explanation>.
- **<Driver 2>** — <one-line explanation>.
- **<Driver 3>** — <one-line explanation>.

## Considered options

The realistic options that were on the table. Each one gets enough detail that a reader can evaluate the tradeoff. **Always include at least one rejected option** — an ADR with no rejected alternative isn't really a decision.

### Option 1: `<short name>`

<Brief description of what this option means in practice — implementation sketch, not just a label.>

**Pros:**
- <pro>
- <pro>

**Cons:**
- <con>
- <con>

### Option 2: `<short name>`

<Description.>

**Pros:**
- <pro>

**Cons:**
- <con>

### Option 3: `<short name>` *(if applicable)*

<Description.>

**Pros:**
- <pro>

**Cons:**
- <con>

## Decision

We chose **Option <N>: `<short name>`**.

The decision and the *why*. Be explicit about which decision drivers this option satisfies and which it sacrifices. Don't pretend the chosen option is perfect — name what we accepted as the cost.

## Consequences

What follows from this decision, both intended and as side effects.

### Positive

- <consequence>
- <consequence>

### Negative

- <consequence>
- <consequence>

### Neutral / known tradeoffs

- <consequence>
- <consequence>

## Validation

How will we know this decision was right (or wrong)? Specify a validation signal — a metric, a behavior, a test, or a future review date.

- **Signal:** <what we'll watch>.
- **Threshold or condition:** <what triggers a revisit>.
- **Review date:** <YYYY-MM-DD> *(optional)*.

## References

- Jira tickets: `<JIRA-KEY>`, `<JIRA-KEY>`.
- Related ADRs: [`NNNN`](./NNNN-...md).
- External references: <Salesforce docs, blog posts, papers, RFCs>.
