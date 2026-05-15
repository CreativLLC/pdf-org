---
title: "Time_Sheet__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Invoice__c.md
  - Contact_Role__c.md
  - Project__c.md
---

# `Time_Sheet__c`

## Purpose

Custom object representing a worked time entry, typically imported from Jira/Tempo and matched to a [`Contact_Role__c`](Contact_Role__c.md) at save time. Time Sheets carry a breakdown of hours across eight effort categories (configuration, design, development, documentation, PM, reporting, testing, training) that sum into `Total_Hours__c` on every save. Once attached to an [`Invoice__c`](Invoice__c.md) whose `Support_Contract__c` is set, Time Sheet hours roll up into the related standard `Contract.Contract_Hours_Used__c`.

## Type and origin

| | |
|---|---|
| **API name** | `Time_Sheet__c` |
| **Type** | Custom (`__c`) |
| **Origin** | Not in this repo's `force-app/main/default/objects/`. Authored prior to this engagement. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced by Apex (`TimeSheetUtils`, `TimeSheetBeforeSave`, `TimeSheetAfterIUD`, `Logic_Contract`, `InvoicePDFController`):

| Field reference | Inferred type | Purpose |
|---|---|---|
| `Done_By__c` | Lookup → `Contact` | Resolved from the matched Contact Role's `Contact__c`. |
| `Done_By_Name__c` | Text | Inbound from the import; one half of the matching key. |
| `Project__c` | Lookup → `Project__c` | Resolved from the matched Contact Role's `Project__c`. |
| `Project_Name__c` | Text | Inbound from the import; other half of the matching key. |
| `Contact_Role__c` | Lookup → `Contact_Role__c` | The matched role for this entry. |
| `Date__c` | Date | Normalized work date. Populated by `UtilNinja.convertTempoDateString(Work_Date__c)` when null. |
| `Work_Date__c` | Text | Raw inbound date string (Tempo format). |
| `Total_Hours__c` | Number | Sum of all eight category-time fields, recomputed before every save. |
| `Configuration_Time__c`, `Design_Time__c`, `Development_Time__c`, `Documentation_Time__c`, `Project_Management__c`, `Reporting_Time__c`, `Testing_Time__c`, `Training_Time__c` | Number | Effort breakdown. Note: `Project_Management__c`, not `Project_Management_Time__c`. |
| `Hours__c` | Number | Read by `InvoicePDFController` for invoice line items. |
| `Total_Billable_Amount__c` | Currency | Read by `InvoicePDFController`. |
| `Epic__c` | Text | Read by `InvoicePDFController`; defaults to `'General Support'` if null. |
| `Resource_Type__c` | Text | Read by `InvoicePDFController` when invoice's billing type is not `'Individual'`. |
| `Invoice__c` | Lookup → `Invoice__c` | The invoice this timesheet rolls into. Traversed as `Invoice__r.Support_Contract__c`. |

## Sharing model

Not in this repo.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

Three triggers fire on this object:

- **`TimeSheetBeforeSave.trigger`** — events: `before insert, before update`. Inline logic (no handler): zeroes `Total_Hours__c` and adds the eight category fields. Runs unconditionally.
- **`TimeSheetTrigger.trigger`** — declared on the full event set but only the before-insert and before-update branches actually delegate (the after-* branches are commented out). Calls **`TimeSheetUtils`**:
  - `beforeInsert`: builds matching keys `<Done_By_Name>-<Project_Name>`, queries active `Contact_Role__c` rows where `Jira_Matching_Key__c IN :keys`, populates `Contact_Role__c`, `Done_By__c`, `Project__c` from the matched role, normalizes `Date__c` via `UtilNinja.convertTempoDateString` if null.
  - `beforeUpdate`: same matching pass, but only when `Done_By_Name__c`, `Project_Name__c`, or `Contact_Role__c` changed; re-normalizes `Date__c` when `Work_Date__c` changes or `Date__c` is null.
- **`TimeSheetAfterIUD.trigger`** — events: `after insert, after update, after delete`. Inline logic: collects affected `Time_Sheet__c.Invoice__r.Support_Contract__c` ids (from `Trigger.oldMap` on delete; `Trigger.newMap` otherwise), then calls `Logic_Contract.rollupTimeSheets(contractIds)` and updates the resulting Contract list.
- **`InvoicePDFController`** reads Time Sheets matching the invoice's project and date range, then groups by Epic + Resource for rendering.

## Flows touching this object

None.

## Integrations referencing this object

None. (Import path is Apex-driven via the `Jira_Matching_Key__c` matching pattern, presumably populated by an external loader. The integration end is not in this repo.)

## Record types

Not in this repo.

## Constraints and gotchas

- **Three triggers on one object** (`TimeSheetBeforeSave`, `TimeSheetTrigger`, `TimeSheetAfterIUD`). Order of execution between the two before-save triggers is undefined; both write `Total_Hours__c` and `Contact_Role__c`/`Done_By__c`/`Project__c` respectively, so as long as they don't fight, it's fine. Consolidate when refactoring.
- **`Project_Management__c` is the field name** for PM time, not `Project_Management_Time__c` as the commented `Requirement_Use_Case__c` trigger might suggest.
- **`TimeSheetUtils.beforeInsert` populates lookups only when a Contact Role is found.** Unmatched timesheets save with null `Contact_Role__c`/`Done_By__c`/`Project__c`. There is no validation rule preventing the orphan state.
- **`Jira_Matching_Key__c` matching is exact string equality** — whitespace, capitalization, and apostrophe differences all cause silent mismatches.
- **`TimeSheetAfterIUD` does `Database.update(contractsToUpdate)` unconditionally**, even when `Logic_Contract.rollupTimeSheets` returns an empty list. That's a no-op DML but counts toward governor limits.
- **`Logic_Contract.rollupTimeSheets` overwrites `Contract_Hours_Used__c`** with the sum from currently-attached timesheets — there's no incremental delta; a deleted timesheet's hours are removed by the rollup pass naturally on the next save.

## Related ADRs

None.
