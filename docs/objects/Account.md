---
title: "Account"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Contact.md
  - Opportunity.md
  - Project__c.md
---

# `Account`

## Purpose

Standard Salesforce `Account` object, used here as the customer entity that anchors `Opportunity`, `Project__c`, and `Invoice__c` records. The engagement carries two trigger files that maintain a `Last_Updated__c` audit timestamp on every save and re-project two custom fields — `Parent_Account__c` (custom Account lookup) onto the standard `ParentId`, and `Lead_Id_Passable__c` onto `Lead__c` — so that flows or imports that can only populate the custom-named fields end up with consistent standard relationships.

## Type and origin

| | |
|---|---|
| **API name** | `Account` |
| **Type** | Standard |
| **Origin** | Out-of-box. Engagement adds triggers and references custom fields. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced by the engagement's Apex against `Account` (custom fields exist on the org but are not source-tracked here):

| Field reference | Inferred type | Source | Purpose |
|---|---|---|---|
| `Last_Updated__c` | DateTime | `AccountBeforeChange.trigger`, `AccountUtils.handleBeforeInsert/Update` | Stamped to `System.now()` on every before-insert/update. |
| `Parent_Account__c` | Lookup → `Account` | `AccountUtils` | Copied onto standard `ParentId` on before-insert/update. |
| `Lead__c` | Lookup → `Lead` | `AccountUtils` | Populated from `Lead_Id_Passable__c`. |
| `Lead_Id_Passable__c` | Text / Id | `AccountUtils` | Inbound staging field — a writable proxy that the trigger lifts onto `Lead__c`. |

Standard fields used by other Apex on this engagement: `Id`, `Name`, `BillingStreet`, `BillingCity`, `BillingState`, `BillingPostalCode`, `BillingCountry`, `Account_Legal_Name__c` (custom), `Invoice_Attn_Line__c` (custom), `Billing_Type__c` (custom) — see [`InvoicePDFController`](../../force-app/main/default/classes/InvoicePDFController.cls) for the latter three.

## Sharing model

Not in this repo. The standard `Account` OWD is configured in setup.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **[`AccountTrigger.trigger`](../../force-app/main/default/triggers/AccountTrigger.trigger)** — events: `before insert/update/delete, after insert/update/delete, after undelete`. Delegates to static methods on **[`AccountUtils`](../../force-app/main/default/classes/AccountUtils.cls)** (`handleBeforeInsert`, `handleBeforeUpdate`, etc.). Most after-* handlers are no-op stubs; the active logic is in the before-handlers (audit stamp + field re-projection).
- **[`AccountBeforeChange.trigger`](../../force-app/main/default/triggers/AccountBeforeChange.trigger)** — events: `before insert, before update`. Stamps `Last_Updated__c = System.now()` on every row. This duplicates work already done by `AccountUtils.handleBeforeInsert/Update`; both triggers fire and the last one to write wins (they write the same value, so no practical conflict).
- **[`AccountForecastController.cls`](../../force-app/main/default/classes/AccountForecastController.cls)** — Visualforce controller that, despite the name, queries the custom `Acct__c` object (not `Account`). It does not touch `Account` directly; included here only because the engagement input list flagged it.
- **[`Standard_Logic_Acct.cls`](../../force-app/main/default/classes/Standard_Logic_Acct.cls)** — utility for creating `Acct__c` (the custom financial-account object), not `Account`. The class name is misleading. Listed in the discovery input but has no `Account` SOQL/DML.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **Two triggers on Account** (`AccountTrigger`, `AccountBeforeChange`) is generally an anti-pattern — order of execution between them is undefined. Here it works because both write the same `Last_Updated__c` value.
- `AccountUtils.generateAccount` calls `LeadUtils.uniqueNumber` (not `AccountUtils.uniqueNumber`) for the unique counter — a minor bug, but stable for test-data generation.
- `Standard_Logic_Acct` and `AccountForecastController` operate on the custom `Acct__c` object, not standard `Account`. The classify-significance step listed them under Account; treat that as informational, not authoritative.

## Related ADRs

None.
