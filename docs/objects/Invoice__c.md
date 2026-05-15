---
title: "Invoice__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Project__c.md
  - Contact_Role__c.md
  - Time_Sheet__c.md
  - Account.md
---

# `Invoice__c`

## Purpose

Custom billing object that aggregates time and materials for a [`Project__c`](Project__c.md) into a customer-facing invoice. Two distinct invoice modes coexist: standard invoices (work done, applied credit, total) and deposit invoices that carry a `Credit_Debt__c` balance which standard invoices draw down via `Applied_Credit__c`. On insert, the trigger autopopulates `Payment_Days__c` from the parent Project's `Net_Payment_Terms__c` and creates one `Referral_Commission_Payment__c` per active `Referral`/`Sales_Team` [`Contact_Role__c`](Contact_Role__c.md) on the project. On update, deposit invoices' `Available_Credit__c` is recomputed from the sum of their child standard invoices' applied credits.

## Type and origin

| | |
|---|---|
| **API name** | `Invoice__c` |
| **Type** | Custom (`__c`) |
| **Origin** | Not in this repo's `force-app/main/default/objects/`. Authored prior to this engagement. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced by Apex (`InvoiceUtils`, `InvoicePDFController`, `Logic_Contract`, `TimeSheetAfterIUD`):

| Field reference | Inferred type | Purpose |
|---|---|---|
| `Project__c` | Lookup → `Project__c` | Parent project; drives payment terms, links to related Contact Roles. |
| `Invoiced_To__c` | Lookup → `Account` | Billed customer. |
| `Deposit_Invoice__c` | Lookup → `Invoice__c` (self) | When set, this is a standard invoice drawing from a deposit; the deposit invoice's `Available_Credit__c` will be recomputed. |
| `Support_Contract__c` | Lookup → `Contract` | Used by `TimeSheetAfterIUD.trigger` and `Logic_Contract` to roll Time Sheet hours up to the related standard `Contract.Contract_Hours_Used__c`. |
| `Applied_Credit__c` | Currency | Credit applied from a deposit invoice. |
| `Work_Done_Amount__c` | Currency | Labor/work charges. Defaulted to 0 if null. |
| `Pre_Paid_Amount__c` | Currency | Used for deposit invoices. Defaulted to 0 if null. |
| `Invoice_Total__c` | Currency | Computed: if `Pre_Paid_Amount__c > 0`, equals `Pre_Paid_Amount__c`; otherwise `Work_Done_Amount__c - Applied_Credit__c`. |
| `Credit_Debt__c` | Currency | Deposit invoices: original credit amount. |
| `Available_Credit__c` | Currency | Deposit invoices: `Credit_Debt__c - sum(child standard invoices' Applied_Credit__c)`. |
| `Payment_Days__c` | Number | Net payment window in days. Defaulted from `Project__c.Net_Payment_Terms__c` (`Net 7` → 7; `Net 15`, `Net 30`, else → 30). |
| `Invoice_Due_Date__c` | Date | Used by `InvoicePDFController`. |
| `Invoice_Start_Date__c` / `Invoice_End_Date__c` | Date | Period covered. Used to query Time Sheets for the period. |
| `Status__c` | Picklist | E.g., `Created`. |
| `AppliedToInvoices__r` | Child relationship | Standard invoices that drew from this (deposit) invoice. |

## Sharing model

Not in this repo.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **`InvoiceTrigger.trigger`** — full event set, delegating to **`InvoiceUtils`**:
  - `handleBeforeInsert` / `handleBeforeUpdate`: defaults `Payment_Days__c` from the parent Project's `Net_Payment_Terms__c`; nulls become zeros for `Work_Done_Amount__c` and `Pre_Paid_Amount__c`; recomputes `Invoice_Total__c`.
  - `handleAfterInsert`:
    1. For each invoice with `Project__c`, queries the project's `Project_Assignments__r` filtered to `Referral` or `Sales_Team` record types with `Status__c = 'Active'`, and inserts one `Referral_Commission_Payment__c` per role (`Contact_Role__c`, `Invoice__c` set).
    2. For each invoice with `Deposit_Invoice__c`, recomputes the deposit invoice's `Available_Credit__c`.
  - `handleAfterUpdate`: re-runs the deposit-invoice credit recomputation when `Deposit_Invoice__c` is non-null.
- **`InvoicePDFController.cls`** — Visualforce controller for the printable invoice. Reads the invoice + invoiced Account + the `Time_Sheet__c` rows whose `Project__c` and `Date__c` fall within the invoice period; groups them by `Epic__c` and `Resource_Type__c` (or `Done_By_Name__c` when `Billing_Type__c = 'Individual'`); computes per-resource, per-epic, and overall hours/rates/totals.
- **`TimeSheetAfterIUD.trigger`** reads `Invoice__r.Support_Contract__c` to roll up hours to the related `Contract`.
- **`Logic_Contract.rollupTimeSheets`** queries `Time_Sheet__c` traversing `Invoice__r.Support_Contract__r.Id` to sum hours per Contract.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **`Net 15` mapping is a bug-or-feature:** in the trigger's `switch on proj.Net_Payment_Terms__c`, `Net 15` maps to **30 days**, not 15. The original author may have intended this; treat any change as a behavior change.
- **`Invoice_Total__c` is set in Apex on every save**, including update. Manually setting `Invoice_Total__c` via API or Data Loader will be overwritten by the trigger. To support a manual override path, add a checkbox and gate the recomputation.
- **`Referral_Commission_Payment__c` rows are created on after-insert only.** If the project's active referral/sales-team Contact Roles change after the invoice is created, no new commission rows appear.
- **Deposit-invoice math** uses `AppliedToInvoices__r` and sums `Applied_Credit__c`; nulls are coerced to 0. The child relationship name comes from the `Invoice__c.Deposit_Invoice__c` lookup.
- **`Invoice_Due_Date__c` is not computed by the trigger** — it appears in `InvoicePDFController` reads but no Apex sets it. Likely a formula field (`Invoice_Start_Date__c + Payment_Days__c` or similar) defined in metadata not present here.
- `InvoicePDFController` will throw `ArithmeticException` if any `Epic__c` has zero hours total (divides `epicAmount/epicHours`). Defensive when authoring test data.

## Related ADRs

None.
