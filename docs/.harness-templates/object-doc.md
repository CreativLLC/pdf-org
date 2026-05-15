---
title: "<ObjectAPIName>"
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <human-name | archon-run-id>
related_tickets: [<JIRA-KEYS>]
related_docs: [architecture/overview.md, <other-related-docs>]
---

# `<ObjectAPIName>`

<!--
TEMPLATE: Object documentation. One file per significant standard-with-customizations
or custom object, located at `docs/objects/<ObjectAPIName>.md`.

Standard objects with no engagement-specific customizations should NOT have a doc here.
Out-of-the-box behavior is documented by Salesforce.
-->

## Purpose

One-paragraph description of what this object represents in the business model. Lead with the real-world entity, then the role it plays in the engagement's processes. Explain *why this object exists* in this org — especially if it's a custom object.

## Type and origin

| | |
|---|---|
| **API name** | `<ObjectAPIName>` |
| **Type** | Standard / Custom (`__c`) / Custom Metadata (`__mdt`) / External / Big Object / Platform Event (`__e`) |
| **Label (singular / plural)** | `<Singular>` / `<Plural>` |
| **Origin** | Out-of-box / Created in `<JIRA-KEY>` / Inherited from `<package>` |

## Key fields

The fields material to understanding or working with this object. Not every field — only those that drive logic, integrations, or reporting. Workflows handling field changes update this table.

| Field API name | Type | Required | FLS posture | Purpose |
|---|---|---|---|---|
| `Name` | Auto Number / Text | Yes | Read for all profiles | <purpose> |
| `<Field>__c` | <Type> | <Yes/No> | <Read for X; Edit for Y> | <purpose> |
| `<Field>__c` | <Type> | <Yes/No> | <FLS> | <purpose> |

> **FLS posture** records the engagement's intent: which profiles or permission sets read or edit this field, and why. The implementation is in metadata; this column is the rationale.

## Relationships

| Relationship | Field | Related object | Type | Cascade behavior |
|---|---|---|---|---|
| Parent | `<Field>__c` | `<Object>` | Lookup / Master-Detail | Restrict / Cascade / Set Null |
| Child | (referenced from <Object>.<Field>) | `<Object>` | reverse of above | — |

## Sharing model

How records of this object are shared, and why.

- **OWD:** Public Read/Write / Public Read Only / Private / Controlled by Parent.
- **Sharing rules:** list each, with the criterion and the why.
- **Apex sharing:** any programmatic shares; reference the Apex class.
- **Implicit sharing:** account/contact/case parent rules if relevant.

For the broader sharing context across the org, see [`../architecture/sharing-model.md`](../architecture/sharing-model.md).

## Validation rules

| Rule | Formula summary | Error message | Why |
|---|---|---|---|
| `<Rule_Name>` | `<short formula description>` | `<the user-visible message>` | <why this rule exists> |

## Triggers and Apex touching this object

Code that mutates or reads this object beyond standard CRUD.

- **Trigger:** `<TriggerName>` — fires on <events>; delegates to handler `<HandlerClassName>` (see [`../flows/<related-flow>.md`](../flows/) or pattern [`harness/patterns/apex-trigger-handler.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/patterns/apex-trigger-handler.md)).
- **Apex consumers:** `<ClassName>.<methodName>` — <purpose>; `<ClassName>.<methodName>` — <purpose>.

## Flows touching this object

Flows that create, update, or query this object.

- [`../flows/<Flow_Name>.md`](../flows/<Flow_Name>.md) — <triggering condition and side effect>.

## Integrations referencing this object

External systems that read or write this object.

- [`../integrations/<System>.md`](../integrations/<System>.md) — <direction and frequency>.

## Test coverage

How this object is exercised in tests.

- **Test data factory method:** `TestDataFactory.create<ObjectName>(...)` — see [`harness/patterns/testdatafactory-usage.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/patterns/testdatafactory-usage.md).
- **Test classes:** `<TestClassName>` (covers `<aspect>`); `<TestClassName>` (covers `<aspect>`).

## Constraints and gotchas

Anything that's surprising, nontrivial, or easy to get wrong. Examples:

- "This object's `Status__c` picklist values are referenced by name in `<ClassName>.cls`. Renaming a value requires the Apex update."
- "The `OwnerId` is reassigned by `<Flow_Name>` on certain transitions; manual ownership changes will be overwritten."
- "Bulk DML must be batched at <N> records to stay within governor limits given the trigger's downstream lookups."

## Related decisions

ADRs in `docs/decisions/` that govern how this object is shaped or used. Frontmatter `related_tickets:` is the per-ticket attribution; `git log <this file>` is the granular change history. This section captures the *architectural choices* that explain the current state.

- [`<NNNN-slug>`](../decisions/<NNNN-slug>.md) — <one-line summary of what the ADR locked about this object>

If no engagement ADRs touch this object, write `_None._` — do not omit the section.

<!--
Replaces the older `## History` section. Per ADR-0010 state-not-history: the
doc body describes the current state. Per-ticket change history lives in Jira
and `git log`; engagement-wide architectural choices live in ADRs. This
section is the bridge from "what the object is today" to "why we made it
that way."
-->

