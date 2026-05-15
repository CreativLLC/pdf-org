---
title: "Transaction__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs: []
---

# `Transaction__c`

## Purpose

Custom object representing a money movement — either a single instance, a recurring schedule that spawns instances, or a budget template. Three record types discriminate the modes: `Recurring`, `Budget`, and `Instance`. On insert of a `Budget` transaction, the trigger generates a stream of `Instance` rows from the start date through the end date according to `Recurrence_Period__c` (`Day`/`Week`/anything-else=Month) and `Recurrence_Number__c`. On update of a `Budget`, unpaid instance rows are re-synced. On creation of a `Recurring` transaction (or when an `Instance` flips to `Cleared`/`Cancelled`), the recurring source is re-projected forward via `TransactionLogic.upsertInstances`.

## Type and origin

| | |
|---|---|
| **API name** | `Transaction__c` |
| **Type** | Custom (`__c`) |
| **Origin** | Not in this repo's `force-app/main/default/objects/`. Authored prior to this engagement. Operates against the custom `Acct__c` financial-account object (not standard `Account`). |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced by Apex (`TransactionAfterSave`, `TransactionLogic`, `AccountForecastController`):

| Field reference | Inferred type | Purpose |
|---|---|---|
| `RecordTypeId` | RecordType | Record type names used in Apex: `Recurring`, `Budget`, `Instance`. |
| `Source__c` | Lookup → `Acct__c` | Where money comes from (recurring/budget). Copied onto child instances' `From__c`. |
| `Destination__c` | Lookup → `Acct__c` | Where money goes (recurring/budget). Copied onto child instances' `To__c`. |
| `From__c` | Lookup → `Acct__c` | Instance source. |
| `To__c` | Lookup → `Acct__c` | Instance destination. |
| `Instance_Of__c` | Lookup → `Transaction__c` (self) | An Instance's pointer to the Recurring/Budget parent. |
| `Date__c` | Date | Instance date, or start date of recurring/budget. |
| `End_Date__c` | Date | End of the recurring window. Null = open-ended; treated as today+1y in `upsertInstances`, today+2y in `generateNewInstances`. |
| `Amount__c` | Currency | Amount per instance. |
| `Recurrence_Period__c` | Picklist | `Day`, `Week`, otherwise treated as Month. |
| `Recurrence_Number__c` | Number | Step size (e.g., every 2 weeks). |
| `Status__c` | Picklist | `Planned`, `Cleared`, `Cancelled`, `Paid`. Unpaid = `Planned`. |
| `Auto_pay__c` | Checkbox | Propagated parent → child. |
| `Budget__c` | Text / Lookup | Optional categorization, propagated parent → child. |

## Sharing model

Not in this repo.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **`TransactionAfterSave.trigger`** — events: `after insert, after update`. Inline dispatch (no handler class delegation, though it calls `TransactionLogic`):
  - **Budget on insert** → `TransactionLogic.generateNewInstances(trans)` → returns a list of `Instance` rows from `Date__c` to `End_Date__c` (or `Date.today() + 2 years`), added to a bulk upsert list.
  - **Budget on update** → `TransactionLogic.updateUnpaidInstances(trans)` → returns the existing `Status__c = 'Planned'` instances re-positioned forward from the most recent paid date (or the budget start), with refreshed Amount/Source/Destination/Status.
  - **Recurring on any save** → adds `trans.Id` to a set passed to `TransactionLogic.upsertInstances(recurringTransIds)` at the end. This method walks from `Date__c` forward, generating placeholder Instances, then reconciles them against existing `Instance` rows whose `Status__c` is `Planned` or `Cancelled` — preserving paid/cleared instances and pruning surplus.
  - **Instance on update**, where `Status__c` changed to `Cleared` or `Cancelled` → adds `trans.Instance_Of__c` to the recurring-id set, triggering the same forward-projection. This is how clearing an instance causes the recurring schedule to refresh.
- **`TransactionLogic.cls`** — three public statics: `generateNewInstances`, `updateUnpaidInstances`, `upsertInstances`. Also contains a legacy `testTransactionAfterSave` test method inline (anti-pattern — tests belong in `*Test` classes).
- **`RollupTransaction.cls`** — a small wrapper DTO (`Transaction__c trans`, `rowLabel`, `rowId`, `rollupValue`). Not used in any other class read here; likely consumed by Visualforce pages outside this repo.
- **`AccountForecastController.cls`** — Visualforce controller for `/apex/AccountForecast`. Queries Transactions where `From__c = :accountId OR To__c = :accountId` with `Status__c IN ('Planned', 'Paid')`, ordered by `Date__c`, and produces a running-balance table for the bound `Acct__c` record.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo. Names used in Apex: `Recurring`, `Budget`, `Instance` (looked up by `getRecordTypeInfosByName`, *not* developer name — see Constraints).

## Constraints and gotchas

- **Record types are looked up by Name, not DeveloperName.** `Schema.SObjectType.Transaction__c.getRecordTypeInfosByName().get('Recurring')` will break if anyone renames the record type label. Most other objects in this codebase use developer-name lookups; this one is an outlier.
- **`upsertInstances` and `generateNewInstances` have different default end-of-window behavior:** `upsertInstances` uses `today + 1 year` for open-ended recurrings; `generateNewInstances` uses `start + 2 years`. Inserting and then immediately updating a Budget can therefore produce different numbers of Instance rows than just inserting it.
- **Test method `testTransactionAfterSave` lives inline in `TransactionLogic.cls`.** This is an old pattern that doesn't follow current Apex test-class conventions. It also creates `AccountForecastController` against pages that aren't deployed in source-tracked metadata here.
- **`Recurrence_Period__c` else-branch is Month.** If a new period (e.g., `Year`) is added to the picklist, it silently falls through to month-stepping.
- **`updateUnpaidInstances` advances `startDate` past the last paid date** before reassigning forward dates to unpaid instances. If `End_Date__c` is shortened post-payment, surplus unpaid instances are *not* deleted by this method — only `upsertInstances` (the Recurring path) handles deletes.
- This object's stack is the **only place** that references `Acct__c` (custom financial-account object, distinct from standard `Account`). Don't confuse the two.

## Related ADRs

None.
