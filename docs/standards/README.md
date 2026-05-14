# Standards (Engagement-Specific Overrides Only)

This directory holds standard overrides for **this specific engagement** when it must deviate from the team-wide standards. **Most engagements will leave this directory empty** — the team's defaults apply unmodified.

## Where the standards actually live

The team-wide standards are in the harness repo at [`harness/standards/`](https://github.com/CreativLLC/archon-salesforce-jira/tree/main/standards). *(Phase 1 leaves the team standards directory as a placeholder; Phase 1.5 fleshes it out.)*

## Standards vs patterns

- A **pattern** says *"when X, do Y"* — recommended.
- A **standard** says *"always Y, never not-Y"* — enforced.

Standards are non-negotiable defaults. Workflows enforce them. An override here is a deliberate engagement-level deviation, not a casual choice.

## When to add an override here

The bar for overriding a standard is higher than for overriding a pattern. Add a standards override only when:

- The engagement has a constraint the team-wide standard literally cannot accommodate.
- The override has been reviewed and approved by the engagement architect plus at least one other senior team member.
- An ADR documents the rationale.
- A sunset condition specifies when the override should be revisited.

## Process for adding an override

1. Open a Jira ticket describing the deviation.
2. Author an ADR in [`../decisions/`](../decisions/).
3. Author the override here using the [`harness/docs-templates/standards-override.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/docs-templates/standards-override.md) template.
4. Get approval from the engagement architect and one other senior team member before merging.
5. Specify a sunset condition.

## Index

*(empty — this exemplar engagement follows team standards unmodified.)*
