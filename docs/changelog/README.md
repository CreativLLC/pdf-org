# Changelog

One file per Jira ticket that produced a change. Files are organized in monthly subdirectories (`YYYY-MM/<JIRA-KEY>.md`) to keep directory listings manageable as the engagement grows. **There is no aggregated `CHANGELOG.md`** — granularity is the point.

## Why per-ticket files

- **Granularity for AI navigation.** An agent looking for "what changed when we touched `Renewal__c`" can grep `related_docs: [objects/Renewal__c.md]` across changelog entries.
- **Git blame clarity.** Each change is its own file with its own commit history.
- **No merge conflicts** on a shared `CHANGELOG.md` when multiple workflows run in parallel.
- **Direct ticket-to-changelog correspondence.** `ACME-101.md` is unambiguously the changelog for ACME-101.

## Template

The changelog entry template lives at [`harness/docs-templates/changelog-entry.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/docs-templates/changelog-entry.md). Required sections: Summary, Why, What changed, Validation outcome, Files touched, Doc updates, PR, Notes.

## Authoring

In an active engagement, every harness workflow run that mutates the engagement repo produces a changelog entry as part of the change. Out-of-band edits (a teammate authoring directly without a workflow run) must still produce a changelog entry, named for the ticket key.

## Index by month

| Month | Entries |
|---|---|
| [`2026-05/`](./2026-05/) | [ACME-101](./2026-05/ACME-101.md) |

*(In a real engagement, this index could be auto-generated from the directory structure. For Phase 1, it's hand-maintained.)*
