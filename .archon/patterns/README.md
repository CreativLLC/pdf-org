# Team-wide Pattern Library

Canonical patterns the team uses across all Salesforce engagements. Workflows read this directory as context when generating Apex, LWC, Flow, or metadata changes; engineers reference it directly when authoring code.

> **Patterns vs standards:** A pattern says *"when X, do Y."* A standard says *"always Y, never not-Y."* Patterns are recommended; standards are enforced. If a pattern is non-negotiable, promote it to a standard (in [`../standards/`](../standards/)).

## How patterns are used

- **By workflows.** When a workflow generates Apex (or LWC, Flow, etc.), it loads the relevant pattern entries as context. The pattern's "when to apply" section drives selection; the pattern's code becomes the template the workflow follows.
- **By engineers.** When an engineer is implementing manually (in explore mode, or before a workflow exists for a task type), they read the pattern as a reference. The pattern's anti-patterns section is especially useful for catching common mistakes.

## How patterns are added

A new pattern is added by PR with at least one teammate reviewer. The PR description must answer:

1. What problem does this pattern solve?
2. Where in our existing engagements would we apply it?
3. What would happen if we didn't have it?

A pattern that can't answer those isn't ready to be canon.

## Current patterns

| Pattern | Scope | Summary |
|---|---|---|
| [`apex-trigger-handler.md`](./apex-trigger-handler.md) | Apex | One trigger per object delegating to a handler class with per-event methods |
| [`fls-crud-enforcement.md`](./fls-crud-enforcement.md) | Apex | Enforce field-level security and CRUD permissions on user-driven operations |
| [`bulkified-soql-update.md`](./bulkified-soql-update.md) | Apex | Never SOQL or DML inside loops; structure for bulk safety |
| [`testdatafactory-usage.md`](./testdatafactory-usage.md) | Apex tests | All test data goes through `TestDataFactory`; never inline `INSERT new Account(...)` |

## Per-engagement overrides

If an engagement needs to deviate from a team pattern (rare), the override lives in the engagement repo's `docs/patterns/<kebab-name>.md` and follows the [`standards-override.md`](../docs-templates/standards-override.md) template format. Overrides require a Jira ticket, an ADR, and a sunset condition.
