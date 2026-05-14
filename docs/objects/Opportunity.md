---
title: "Opportunity"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Account.md
  - Contact_Role__c.md
  - Project__c.md
  - Invoice__c.md
---

# `Opportunity`

## Purpose

Standard Salesforce `Opportunity` used as the sales/contracting record in this engagement. Two engagement-specific behaviors run on save: a quote-validity date is computed from `Quote_Valid_For__c` (a custom picklist) and stamped onto `Quote_Valid_Until__c`; on insert, if the originating Lead carries a `Referral_Contact__c`, a `Referral` [`Contact_Role__c`](Contact_Role__c.md) is auto-created with a default 3% commission rate. Opportunities are the parent of `Contact_Role__c` records that later carry forward onto [`Project__c`](Project__c.md) (see `ProjectUtils.handleAfterInsert`).

## Type and origin

| | |
|---|---|
| **API name** | `Opportunity` |
| **Type** | Standard |
| **Origin** | Out-of-box. Engagement adds two triggers and a handler class. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Custom fields referenced by Apex:

| Field reference | Inferred type | Source | Purpose |
|---|---|---|---|
| `Quote_Valid_For__c` | Picklist | Both triggers | Drives quote-validity calc. Values handled in Apex: `30 Days`, `60 Days`, `90 Days`, `6 Months`, `1 Year`. Anything else falls through to `30 Days`. |
| `Quote_Valid_Until__c` | Date | Both triggers | Computed = `Date.today()` + delta from `Quote_Valid_For__c`. |
| `Lead__c` | Lookup → `Lead` | `OpportunityUtils` | Populated from `Lead_Id_Passable__c` on before-insert. Used on after-insert to look up the originating Lead's `Referral_Contact__c`. |
| `Lead_Id_Passable__c` | Text / Id | `OpportunityUtils` | Staging proxy lifted onto `Lead__c`. |

Standard fields used: `Id`, `Name`, `AccountId`, `StageName`, `CloseDate`.

## Sharing model

Not in this repo. Standard `Opportunity` OWD configured in setup.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **[`OpportunityTrigger.trigger`](../../force-app/main/default/triggers/OpportunityTrigger.trigger)** — events: `before insert/update/delete, after insert/update/delete, after undelete`. Delegates to **[`OpportunityUtils`](../../force-app/main/default/classes/OpportunityUtils.cls)**:
  - `handleBeforeInsert`: computes `Quote_Valid_Until__c` from `Quote_Valid_For__c`, copies `Lead_Id_Passable__c → Lead__c`.
  - `handleAfterInsert`: for any new Opportunity with `Lead__c` set, queries the Lead for `Referral_Contact__c`; if non-null, inserts a `Contact_Role__c` with `RecordTypeId = Referral`, `Fee_Commission_Type__c = 'Percentage'`, `Fee_Commission_Rate__c = 3.00`, `Status__c = 'Active'`, `Title__c = 'Referral Source'`.
  - All other `handleBefore*` / `handleAfter*` are no-op stubs.
- **[`OpportunityBeforeUpsert.trigger`](../../force-app/main/default/triggers/OpportunityBeforeUpsert.trigger)** — events: `before insert, before update`. Duplicates the `Quote_Valid_Until__c` calc that `OpportunityUtils.handleBeforeInsert` already does. Both triggers fire on insert; on update only this one fires (`OpportunityUtils.handleBeforeUpdate` is a stub).
- **[`Logic_Contract.cls`](../../force-app/main/default/classes/Logic_Contract.cls)** — operates on standard `Contract` (not `Opportunity`); listed in classification because of business adjacency. Rolls up `Time_Sheet__c.Total_Hours__c` to `Contract.Contract_Hours_Used__c` via the `Invoice__c.Support_Contract__c` chain.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **Two triggers on Opportunity** (`OpportunityTrigger`, `OpportunityBeforeUpsert`) with overlapping `Quote_Valid_Until__c` logic. Both compute the same value, so no functional conflict — but consolidating into one is a typical refactor target.
- **`Quote_Valid_For__c = '6 Months'` and `'1 Year'`** branches are duplicated across the two triggers; if one is updated without the other, behavior diverges.
- **`Net 15` → 30 days mapping** in `InvoiceUtils` is unrelated but illustrates a similar copy-paste pattern across this codebase: review duplicate logic before editing.
- The Referral Contact Role auto-creation runs once per Opportunity insert; updating `Lead__c` post-insert does **not** create a new Referral role.
- `Logic_Contract` class name is misleading — it does not operate on `Opportunity`, only on standard `Contract`.

## Related ADRs

None.
