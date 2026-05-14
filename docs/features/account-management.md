---
title: Account Management
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - ../objects/Account.md
  - ../objects/Contact.md
---

# `Account Management`

> Customer Accounts carry an audit timestamp on every save and lift two custom-named staging fields onto the standard parent-account and lead relationships so inbound flows have consistent records to navigate.

## Overview

The standard [`Account`](../objects/Account.md) object is the customer entity for the engagement. Customizations are intentionally light: an audit timestamp `Last_Updated__c` is stamped on every save, and two staging fields — `Parent_Account__c` (custom Account lookup) and `Lead_Id_Passable__c` (text/Id) — are re-projected onto the standard `ParentId` and `Lead__c` lookups respectively. This pattern exists because inbound flows or imports can only populate custom-named fields; the triggers ensure the standard relationships are then consistent. Standard [`Contact`](../objects/Contact.md) participates in the same staging pattern via its own `Lead_Id_Passable__c → Lead__c` lift.

## How it works

1. **Audit stamp on every save.** Both `AccountTrigger` (via `AccountUtils.handleBeforeInsert/Update`) and the second `AccountBeforeChange` trigger set `Last_Updated__c = System.now()` on every row.
2. **Parent re-projection.** `AccountUtils` copies `Parent_Account__c` onto the standard `ParentId` on before-insert/update.
3. **Lead Id re-projection.** `AccountUtils` lifts the staging `Lead_Id_Passable__c` onto the custom `Lead__c` lookup on before-insert/update. The same pattern exists on `Contact` (see [`ContactTrigger`](../objects/Contact.md)) and on `Opportunity` (see [Opportunity Pipeline](opportunity-pipeline.md)).
4. **Downstream consumption.** Accounts are referenced by `Project__c.Account__c`, `Invoice__c.Invoiced_To__c`, and the invoice PDF render (`InvoicePDFController` reads the account's billing-address and `Account_Legal_Name__c` / `Invoice_Attn_Line__c` / `Billing_Type__c` custom fields).

## Acceptance signals

- Any new or updated `Account` shows `Last_Updated__c` reflecting the latest save time.
- An `Account` inserted with `Parent_Account__c` populated also shows `ParentId` set to the same value.
- An `Account` inserted with `Lead_Id_Passable__c` populated also shows `Lead__c` set to the same value.

## Known limitations

- **Two triggers on Account overlap.** `AccountTrigger` and `AccountBeforeChange` both fire before-insert/update; the order between them is undefined. They happen to write the same `Last_Updated__c` value today, so there's no functional conflict, but the duplication is an anti-pattern worth consolidating during any future refactor.
- **`AccountForecastController` and `Standard_Logic_Acct` are NOT part of standard-Account management.** Despite the class names, they operate on a separate custom `Acct__c` (a financial-account object distinct from standard `Account`). They are surfaced here only because earlier classification flagged them under `Account`. The actual money-movement features built on `Acct__c` are described in [Transactions and Forecast](transactions-and-forecast.md).
- **`AccountUtils.generateAccount` calls `LeadUtils.uniqueNumber`** (not `AccountUtils.uniqueNumber`) for its unique counter — a minor naming bug, stable for test data, but worth knowing.
- **No business rules on `Last_Updated__c`.** It is a timestamp only; nothing downstream gates on it.

## Related tickets

None recorded at the engagement level for this baseline behavior.
