---
title: "<Flow_Label>"
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <human-name | archon-run-id>
related_tickets: [<JIRA-KEYS>]
related_docs: [<paths-of-related-objects-and-architecture-docs>]
---

# `<Flow_Label>`

<!--
TEMPLATE: Flow documentation. One file per significant Flow, located at
`docs/flows/<Flow_API_Name>.md`. Use the Flow API name (with underscores) as the
filename for predictable lookup.

Trivial validation rules and small no-side-effect Flows do NOT need their own doc.
Document Flows that have side effects, span multiple objects, or implement business
logic worth understanding.
-->

## Purpose

One paragraph: what this Flow does and why it exists. Frame in terms of the business outcome, then the system effect.

## Type and trigger

| | |
|---|---|
| **API name** | `<Flow_API_Name>` |
| **Type** | Record-Triggered / Schedule-Triggered / Platform-Event-Triggered / Auto-Launched / Screen |
| **Triggering object** | `<ObjectAPIName>` *(if applicable)* |
| **Trigger condition** | `<when>` (e.g., "Created", "Updated and `Status__c` changes from `Draft` to `Submitted`") |
| **Trigger order** | Before-save / After-save *(for record-triggered)* |
| **Run-as user** | Triggering user / System Context Without Sharing / etc. |
| **Active version** | `<N>` *(updated whenever the Flow is republished)* |

## What it does

Step-by-step description of the Flow's logic in prose. Don't recreate the Flow XML — describe the *intent* of each major decision and action element. A reader should be able to verify whether the Flow's implementation matches this description.

1. **Get records** of `<Object>` where `<criterion>`.
2. **Decision:** if `<condition>`, then <branch A>; else <branch B>.
3. **Branch A:** create `<Object>` with `<key fields>`.
4. **Branch A:** update `<RelatedObject>.Status__c` to `<value>`.
5. **Branch B:** post platform event `<Event__e>` with `<payload>`.

## Side effects

What this Flow changes outside its triggering record:

- **Records created:** `<Object>` (under `<conditions>`).
- **Records updated:** `<Object>.<Field>` (under `<conditions>`).
- **Platform events published:** `<Event__e>`.
- **Outbound calls:** `<HTTP callout / queueable enqueue / etc.>`.
- **Email/notifications sent:** `<details>`.

If this Flow has no side effects beyond the triggering record, say so explicitly.

## Error handling

How failures are surfaced and managed.

- **Fault paths:** which elements have explicit fault connectors and what they do.
- **Errors users see:** if this Flow can show an error, what does it look like.
- **Errors that go silent:** what we accept as silent (e.g., logged via `<framework>` and reviewed by ops, not surfaced to users) and why.
- **Retries:** any retry mechanism if this Flow makes external calls.

## Dependencies

What this Flow depends on:

- **Custom Metadata:** `<Custom_Metadata__mdt>` records used as configuration — see [`../objects/<Custom_Metadata__mdt>.md`](../objects/<Custom_Metadata__mdt>.md).
- **Apex actions:** `<ApexClass>.<methodName>` invoked from the Flow.
- **Other Flows:** subflows or cross-Flow dependencies.
- **Permissions:** profiles or permission sets that must grant Flow access.

## Performance and limits

- **Bulkification:** how this Flow handles bulk record operations. Reference [`harness/patterns/bulkified-soql-update.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/patterns/bulkified-soql-update.md) if relevant.
- **DML count:** estimated DML operations per record processed.
- **SOQL count:** estimated SOQL queries per execution.
- **Known governor risks:** any limit this Flow approaches under load.

## Testing

How this Flow is verified.

- **Apex test class:** `<TestClassName>` — exercises this Flow by setting up triggering data and asserting side effects.
- **Manual test scenarios:** the canonical scenarios a human runs in a scratch org to verify this Flow end-to-end.

## Ownership and on-call

Who is responsible for this Flow when it breaks.

- **Subject-matter owner:** `<role-or-team>`.
- **Operational owner:** `<role-or-team>` *(may be the same)*.

## Related decisions

ADRs in `docs/decisions/` that govern how this Flow is shaped. Per-ticket change history lives in Jira + `git log <this file>`; this section captures the architectural choices that explain the current state.

- [`<NNNN-slug>`](../decisions/<NNNN-slug>.md) — <one-line summary of what the ADR locked about this Flow>

If no engagement ADRs touch this Flow, write `_None._` — do not omit the section.
