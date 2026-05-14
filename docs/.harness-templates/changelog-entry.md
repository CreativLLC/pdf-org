---
title: "<Jira ticket key>: <One-line summary of the change>"
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <human-name | archon-run-id>
related_tickets: [<JIRA-KEY>]
related_docs: [<paths-of-docs-this-change-touched>]
---

# <JIRA-KEY>: <One-line summary>

> ⚠ **DEPRECATED — do not use for new work** (per [ADR-0010](../decisions/0010-engagement-documentation-model.md)).
>
> The per-ticket changelog pattern this template represents is superseded by:
> 1. **Jira itself** — the per-ticket change history, with structured comments posted by the harness's `update-jira-on-completion.md` command.
> 2. **State-of-the-org docs** — `docs/objects/`, `docs/features/`, `docs/integrations/`, `docs/flows/`. These describe what *exists*, not what *changed*.
>
> Workflows no longer produce changelog entries. Existing entries from pre-ADR-0010 runs are preserved for historical engagements; new `/sf` runs do not touch this directory.
>
> If you're a human looking for change history, use:
> - **Per ticket** → Jira (the ticket and its structured comment).
> - **Per file** → `git log <path>` / `git blame <path>`.
> - **Per architectural decision** → `docs/decisions/`.

<!--
TEMPLATE: Changelog entry. One file per Jira ticket, located at
`docs/changelog/YYYY-MM/<JIRA-KEY>.md` where YYYY-MM is the month the change merged.

This template is the canonical form for changelog output produced by harness workflows.
Every section is required unless explicitly marked optional. Workflows that produce
changelog entries fail validation if a required section is missing.
-->

## Summary

One paragraph (3–5 sentences) describing what changed and why. Lead with the user-visible or system-visible effect; follow with the underlying rationale. Avoid implementation jargon — that's what the rest of the doc is for.

## Why

The motivation for this change. Reference the Jira ticket's stated goal and connect it to the broader architecture if relevant. If this change resolves a defect, name the failure mode it eliminates. If this change adds capability, describe the gap it closes.

## What changed

Itemized list of artifact-level changes. Be specific about API names, file paths, and the *kind* of change.

- **Apex:** `<ClassName>.cls` — added `<methodName>` for `<purpose>`.
- **Metadata:** `<Object>__c` — added field `<Field__c>` (`<Type>`, `<length-or-precision>`).
- **Flow:** `<Flow_Name>` — added decision branch for `<condition>`.
- **Integration:** `<System>` — updated outbound payload to include `<field>`.
- **Test:** `<TestClassName>.cls` — added `<testMethodName>` covering `<scenario>`.
- **Docs:** `<paths>` — updated.

## Validation outcome

Concrete evidence the change works:

- **Apex test results:** all tests passed; coverage <X>% (org-wide), <Y>% on <ClassName>.
- **Scratch deploy:** succeeded against scratch org `<alias>`.
- **Acceptance criteria check:** each AC from the ticket is mapped to evidence (tests, scratch behavior, manual verification).
- **Destructive changes:** none / list with explicit human approval reference.

## Files touched

A flat list of files modified, added, or deleted. Sorted by path.

```
force-app/main/default/classes/<ClassName>.cls
force-app/main/default/classes/<ClassName>.cls-meta.xml
force-app/main/default/classes/<TestClassName>.cls
force-app/main/default/classes/<TestClassName>.cls-meta.xml
force-app/main/default/objects/<Object>__c/fields/<Field>__c.field-meta.xml
docs/changelog/<YYYY-MM>/<JIRA-KEY>.md
docs/objects/<Object>__c.md
```

## Doc updates

Links to other docs updated as part of this change. Use relative paths from this file.

- [`../objects/<Object>__c.md`](../objects/<Object>__c.md) — added field `<Field>__c` row to the field table.
- [`../decisions/<NNNN>-<slug>.md`](../decisions/<NNNN>-<slug>.md) — *(if this change introduced a new decision)*.

## PR

Link to the GitHub (or other VCS) pull request: `<URL>`.

## Notes

*Optional.* Anything else worth recording: deferred follow-ups, items punted to a later ticket, observations that don't fit elsewhere. Keep client-safe — internal candor goes in `_internal/`.
