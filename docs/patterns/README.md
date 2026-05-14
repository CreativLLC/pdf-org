# Patterns (Engagement-Specific Overrides Only)

This directory holds pattern overrides for **this specific engagement** when it must deviate from the team-wide pattern library. **Most engagements will leave this directory empty** — the team's defaults apply unmodified.

## Where the patterns actually live

The team-wide pattern library is in the harness repo at [`harness/patterns/`](https://github.com/CreativLLC/archon-salesforce-jira/tree/main/patterns). That's where the canonical patterns are documented:

- [`apex-trigger-handler.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/patterns/apex-trigger-handler.md)
- [`fls-crud-enforcement.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/patterns/fls-crud-enforcement.md)
- [`bulkified-soql-update.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/patterns/bulkified-soql-update.md)
- [`testdatafactory-usage.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/patterns/testdatafactory-usage.md)

## When to add an override here

Add a pattern override only when this engagement *must* deviate from the team pattern. Examples that justify an override:

- The engagement has an org-specific constraint that conflicts with the pattern (e.g., a managed package's trigger framework that we can't bypass, requiring a different handler shape).
- The engagement uses a framework or library the team default doesn't account for.
- A team pattern was authored before a Salesforce platform change that this engagement now relies on.

If you find yourself needing to override the same team pattern on multiple engagements, that's signal — propose updating the team pattern via PR to the harness repo.

## Process for adding an override

1. Open a Jira ticket describing the deviation.
2. Author an ADR in [`../decisions/`](../decisions/) explaining why this engagement deviates.
3. Author the override here using the [`harness/docs-templates/standards-override.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/docs-templates/standards-override.md) template (the same template applies to pattern overrides).
4. Specify a sunset condition — when should this override be revisited or retired?

## Index

*(empty — this exemplar engagement uses team patterns unmodified.)*
