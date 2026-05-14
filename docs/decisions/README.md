# Architectural Decision Records

ADRs in MADR format ([Markdown ADR](https://adr.github.io/madr/)). One file per significant architectural choice. Numbers are zero-padded 4-digit sequence numbers; the slug describes the decision.

## When to write an ADR

Write an ADR when:
- A non-trivial architectural option has multiple plausible alternatives.
- The decision will be questioned later (or already has been).
- The decision constrains other decisions.
- The decision involves tradeoffs that aren't obvious from the code.

Don't write an ADR for:
- Obvious choices (no real alternative).
- Decisions already documented in code or metadata.
- Implementation details that don't shape the system architecturally.

## Template

The MADR template lives at [`harness/docs-templates/adr.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/docs-templates/adr.md). Required sections: Status, Context, Decision drivers, Considered options (with at least one rejected alternative), Decision, Consequences, Validation.

## Index

| # | Title | Status |
|---|---|---|
| [0001](./0001-platform-events-for-billing-sync.md) | Use platform events for renewal-to-Stripe billing sync | Accepted |

*(Phase 1.5 will add: 0002 — renewal creation lead time; 0003 — picklist-vs-CMDT for renewal status; 0004 — sharing model for `Renewal__c`.)*

## Status taxonomy

- **Proposed** — under discussion; not yet accepted.
- **Accepted** — in effect.
- **Deprecated** — no longer in effect, but the consequences linger; reference for context.
- **Superseded by [NNNN](./NNNN-...md)** — replaced by a later ADR; keep the original for the historical record.
