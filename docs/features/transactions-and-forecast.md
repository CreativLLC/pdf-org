---
title: Transactions and Forecast
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs:
  - ../objects/Transaction__c.md
---

# `Transactions and Forecast`

> A recurring or budgeted transaction projects forward into individual money-movement instances; an account-forecast Visualforce page shows the running balance across a custom financial account based on planned and paid instances.

## Overview

[`Transaction__c`](../objects/Transaction__c.md) models money movement between custom `Acct__c` financial accounts (distinct from standard Salesforce `Account` — see [Account Management](account-management.md) for that). Three record types discriminate behavior: `Budget` (a finite-horizon series that pre-generates all instances on insert and re-syncs unpaid instances on update), `Recurring` (a forward-projected series that reconciles instance rows on every save, preserving paid/cleared ones), and `Instance` (a single movement that, when transitioned to `Cleared` or `Cancelled`, triggers the parent recurring source to re-project forward). `AccountForecastController` powers a Visualforce forecast page that sums planned and paid instances against a chosen `Acct__c` to show a running balance.

## How it works

1. **Define a recurring or budget transaction.** An admin creates a `Transaction__c` with `RecordTypeId = Recurring` (open-ended series) or `Budget` (finite window), specifying source/destination `Acct__c`, amount, start date, end date (optional for recurring), and recurrence period (`Day`, `Week`, otherwise treated as `Month`) plus step number.
2. **Instances generate on insert.**
   - **Budget** → all `Instance` rows are created from `Date__c` through `End_Date__c` (or `today + 2 years` if open-ended).
   - **Recurring** → `upsertInstances` walks from `Date__c` forward through `today + 1 year` (or `End_Date__c`), generating placeholders and reconciling with any existing instances.
3. **Edit the parent.** Updating a `Budget` re-syncs only its unpaid (`Status__c = 'Planned'`) instances, repositioning them forward from the most recent paid date and refreshing amount/source/destination. Updating a `Recurring` re-runs the forward projection, preserving paid/cleared instances and pruning surplus.
4. **Clear or cancel an instance.** When an `Instance` row's `Status__c` flips to `Cleared` or `Cancelled`, the parent recurring source (`Instance_Of__c`) is re-projected forward to fill any gap created by the state change.
5. **View the forecast.** A user navigates to the Visualforce `AccountForecast` page for an `Acct__c`. `AccountForecastController` queries Transactions where `From__c` or `To__c` matches the account and `Status__c` is `Planned` or `Paid`, orders by `Date__c`, and renders a running-balance table.

## Acceptance signals

- Inserting a `Budget` transaction with a 12-week date range and weekly recurrence creates 12 `Instance` rows linked back via `Instance_Of__c`.
- Marking a single `Instance` `Cleared` causes the parent `Recurring` series to repopulate any forward gaps without touching the cleared row.
- The forecast page for an `Acct__c` shows planned and paid instances summed into a running balance ordered by date.

## Known limitations

- **Record types are looked up by Name, not DeveloperName.** `Schema.SObjectType.Transaction__c.getRecordTypeInfosByName().get('Recurring')` breaks if the record type label is renamed. Most other objects in the engagement use developer-name lookups; `Transaction__c` is the outlier.
- **Different default end-of-window between insert and update.** `upsertInstances` uses `today + 1 year` for open-ended recurrings; `generateNewInstances` uses `start + 2 years`. Inserting and then immediately updating a Budget can produce different numbers of instances than just inserting.
- **`updateUnpaidInstances` does not delete surplus instances.** Shortening a Budget's end date post-payment leaves orphaned unpaid instances; only the Recurring code path (`upsertInstances`) handles deletes.
- **Recurrence else-branch is Month.** Adding a new value like `Year` to the picklist silently falls through to monthly stepping.
- **Transaction test method lives inside `TransactionLogic.cls`.** `testTransactionAfterSave` is an inline test method rather than a separate `*Test` class — old pattern, due for a refactor.
- **`RollupTransaction.cls` is an unused DTO** in the visible Apex; it is presumably consumed by Visualforce pages not present in this repo.
- **This stack operates exclusively on `Acct__c` (custom financial account), not standard `Account`.** Don't conflate them — see [Account Management](account-management.md).

## Related tickets

None recorded at the engagement level for this baseline behavior.
