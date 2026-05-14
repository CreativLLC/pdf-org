---
title: Timesheet Billing
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - ../objects/Time_Sheet__c.md
  - ../objects/Invoice__c.md
  - ../objects/Contact_Role__c.md
  - ../objects/Project__c.md
---

# `Timesheet Billing`

> Worked hours imported from Jira/Tempo are auto-matched to the resource and project they belong to, summed into a printable invoice, and rolled up to the related support contract's used-hours balance.

## Overview

This is the time-and-billing core of the engagement. External time entries (Jira/Tempo) load into [`Time_Sheet__c`](../objects/Time_Sheet__c.md) records carrying raw `Done_By_Name__c` + `Project_Name__c` strings. On save, the system resolves each entry to a [`Contact_Role__c`](../objects/Contact_Role__c.md) via a string-key match, sums the eight effort-category fields into `Total_Hours__c`, and (once attached to an invoice with a support contract) rolls hours into the related standard `Contract.Contract_Hours_Used__c`. [`Invoice__c`](../objects/Invoice__c.md) records aggregate the period's timesheets, compute totals, and render a Visualforce-based printable invoice grouped by epic and resource.

## How it works

1. **Timesheets arrive.** External tooling inserts `Time_Sheet__c` rows with `Done_By_Name__c`, `Project_Name__c`, `Work_Date__c` (raw Tempo string), and the per-category time fields. The integration end is external to this repo.
2. **Hours sum on every save.** `Total_Hours__c` is recomputed before every insert/update from the eight category fields (configuration, design, development, documentation, project management, reporting, testing, training).
3. **Match to a Contact Role.** On insert (and on update when key fields change), the system constructs the matching key `<Done_By_Name>-<Project_Name>` and looks for an active `Contact_Role__c` whose `Jira_Matching_Key__c` equals that string. When found, `Contact_Role__c`, `Done_By__c`, and `Project__c` are back-filled on the timesheet. `Date__c` is normalized from the raw Tempo string if it's still null.
4. **Invoice the period.** An admin creates an [`Invoice__c`](../objects/Invoice__c.md) for a project covering a date range. On insert, `Payment_Days__c` defaults from the parent project's `Net_Payment_Terms__c`, and one `Referral_Commission_Payment__c` is created per active Referral/Sales-Team Contact Role on the project. Standard invoices that draw from a deposit invoice cause the deposit's `Available_Credit__c` to be recomputed.
5. **Render the printable invoice.** The Visualforce controller reads the invoice's `Time_Sheet__c` rows within the period (matched by project + date), groups them by `Epic__c` and `Resource_Type__c` (or by `Done_By_Name__c` when the invoice is billed `Individual`), and computes per-resource, per-epic, and overall hours/rates/totals.
6. **Roll up to the support contract.** When timesheets are inserted, updated, or deleted, the system collects the affected `Invoice__r.Support_Contract__c` ids and re-aggregates the related standard `Contract.Contract_Hours_Used__c`. The rollup is an absolute overwrite from the currently-attached timesheets — there are no incremental deltas.

## Acceptance signals

- A newly-imported `Time_Sheet__c` shows a non-blank `Contact_Role__c`, `Done_By__c`, and `Project__c` (back-filled from the role match) and a `Total_Hours__c` equal to the sum of the eight effort categories.
- An `Invoice__c` for a project displays `Payment_Days__c` matching the project's `Net_Payment_Terms__c` and an `Invoice_Total__c` reflecting work done minus applied credit (or the deposit amount, for deposit invoices).
- The Visualforce invoice PDF renders epic-grouped, resource-grouped line items with the expected hours and rates.
- The related `Contract.Contract_Hours_Used__c` increases when timesheets are attached to invoices whose `Support_Contract__c` is set and decreases when those timesheets are deleted.
- Active Referral / Sales-Team Contact Roles on the project trigger one `Referral_Commission_Payment__c` per active role on invoice insert.

## Known limitations

- **String-key matching is brittle.** `Jira_Matching_Key__c` matching is exact string equality. Whitespace, capitalization, apostrophe, or any character drift between Jira and Salesforce produces silent mismatches: the timesheet saves with null `Contact_Role__c`/`Done_By__c`/`Project__c` and no validation rule prevents the orphan state.
- **Three triggers on `Time_Sheet__c`** (`TimeSheetBeforeSave`, `TimeSheetTrigger`, `TimeSheetAfterIUD`). The order between the two before-save triggers is undefined; they happen to write disjoint fields today, but consolidation is a known refactor target.
- **`Net 15` maps to 30 days.** In the `Invoice__c` trigger's payment-terms switch, `Net 15` falls into the 30-day branch alongside `Net 30`. Treat any change here as a behavior change — the original author may have intended this.
- **Commission rows are created once, on after-insert.** Changing the project's active Referral/Sales-Team roles after the invoice exists does not produce new `Referral_Commission_Payment__c` rows.
- **`Invoice_Total__c` is recomputed in Apex on every save**, so manual overrides via API/Data Loader are clobbered.
- **The `InvoicePDFController` divides epic amount by epic hours**, so any epic with zero hours produces an `ArithmeticException` on render. Defensive when authoring test data.
- **The rollup writes `Contract_Hours_Used__c` unconditionally**, even when the recomputed list is empty. That's a no-op DML but counts toward governor limits.
- **The Jira/Tempo loader itself is not in this repo.** Only the matching/aggregation Apex is.

## Related tickets

None recorded at the engagement level for this baseline behavior.
