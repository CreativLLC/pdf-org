---
title: "Product2"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs: []
---

# `Product2`

## Purpose

Standard Salesforce `Product2` object. The engagement maintains a `PricebookEntry` on the Standard Pricebook for every Product, sourced from a custom `Base_Price__c` field. On insert, a new active `PricebookEntry` is created; on update, the existing entry's `UnitPrice` is synced to `Base_Price__c`. This avoids the manual two-step "create product, then create pricebook entry" workflow.

## Type and origin

| | |
|---|---|
| **API name** | `Product2` |
| **Type** | Standard |
| **Origin** | Out-of-box. Engagement adds one after-save trigger. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Custom fields referenced:

| Field reference | Inferred type | Source | Purpose |
|---|---|---|---|
| `Base_Price__c` | Currency / Number | `ProductAfterSave.trigger` | Used as the `UnitPrice` on the Standard Pricebook entry created/updated by the trigger. |

Standard fields used: `Id`.

The trigger also references the constant **[`CNST.Standard_Pricebook_Id`](../../force-app/main/default/classes/CNST.cls)** for the Pricebook2 Id.

## Sharing model

Not in this repo. Standard `Product2` OWD configured in setup.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **[`ProductAfterSave.trigger`](../../force-app/main/default/triggers/ProductAfterSave.trigger)** — events: `after insert, after update`. Inline logic (no handler class):
  1. Queries all existing `PricebookEntry` rows on the Pricebook named `'Standard Price Book'`, indexed by `Product2.Id`.
  2. For each `Product2` in `Trigger.new`, either creates a new active `PricebookEntry` (`Product2Id`, `UnitPrice = Base_Price__c`, `PriceBook2Id = CNST.Standard_Pricebook_Id`, `IsActive = true`) or updates the existing entry's `UnitPrice` to `Base_Price__c`.
  3. Bulk upserts the collected list.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **The trigger filters `PricebookEntry` by `PriceBook2.Name = 'Standard Price Book'`** but writes to `CNST.Standard_Pricebook_Id`. If the Standard Pricebook is renamed in setup, the query returns zero rows and the trigger always tries to insert — which then fails on the unique constraint. Keep the standard Pricebook's name aligned with the literal.
- **Inline logic, no handler class** — unusual for this codebase, which otherwise follows a `XxxTrigger` → `XxxUtils` pattern. Refactoring is a candidate task.
- `Base_Price__c` set to null produces a null `UnitPrice` on insert, which Salesforce will reject. Validation rule on `Product2` to require `Base_Price__c` would be defensive.
- No deactivation path — once a `PricebookEntry` is created, it stays `IsActive = true` even if the `Product2` is later deactivated.

## Related ADRs

None.
