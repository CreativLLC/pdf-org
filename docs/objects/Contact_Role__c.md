---
title: "Contact_Role__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Contact.md
  - Opportunity.md
  - Project__c.md
  - Project_Allocation__c.md
  - Invoice__c.md
  - Time_Sheet__c.md
---

# `Contact_Role__c`

## Purpose

Custom junction-style object linking a [`Contact`](Contact.md) to an [`Opportunity`](Opportunity.md), [`Project__c`](Project__c.md), or Lead in one of several roles distinguished by record type: `Project_Assignment` (a resource staffed to a project for N hours/week), `Sales_Team` (commission-bearing sales role), `Referral` (referral source), or `Other_Participants`. Project Assignment records drive the [`Project_Allocation__c`](Project_Allocation__c.md) generator — when one is created, the trigger spawns weekly allocation rows from the assignment's start date forward; when it's updated, allocations are reconciled (created, deleted, or re-hour'd) to match the new window.

## Type and origin

| | |
|---|---|
| **API name** | `Contact_Role__c` |
| **Type** | Custom (`__c`) |
| **Origin** | Not in this repo's `force-app/main/default/objects/`. Authored prior to this engagement. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced by Apex (`ContactRoleUtils`, `OpportunityUtils`, `ProjectUtils`, `InvoiceUtils`, `TimeSheetUtils`, `ResourcePlannerController`, `ProjectAllocationUtils`):

| Field reference | Inferred type | Purpose |
|---|---|---|
| `Contact__c` | Lookup → `Contact` | The resource / participant. |
| `Lead__c` | Lookup → `Lead` | Source lead for sales/referral roles. |
| `Opportunity__c` | Lookup → `Opportunity` | Sales context. |
| `Project__c` | Lookup → `Project__c` | Delivery context (back-filled by `ProjectUtils.handleAfterInsert` from the Opportunity's roles). |
| `RecordTypeId` | RecordType reference | Discriminates `Project_Assignment` / `Sales_Team` / `Referral` / `Other_Participants`. |
| `Status__c` | Picklist | Open: `Active`. Closed: `Completed`, `Cancelled`. See `ContactRoleUtils.openStatuses` / `closedStatuses`. |
| `Start_Date__c` | Date | Start of an assignment. |
| `End_Date__c` | Date | End of an assignment. Null = open-ended; handler defaults to start + 365 days. |
| `Hours_Per_Week__c` | Number | Standard weekly hours for the assignment. Drives `Project_Allocation__c.Hours__c` when not overridden. |
| `Title__c` | Text | Role title (e.g., `Referral Source`, `Sales Executive`). |
| `Fee_Commission_Type__c` | Picklist | `Percentage` or otherwise (used as amount). |
| `Fee_Commission_Rate__c` | Number | Rate for commission. Default `3.00` for auto-created referrals. |
| `Fee_Commission_Amount__c` | Currency | Flat-amount alternative. |
| `Jira_Matching_Key__c` | Text | Formula or stored key joining `Contact.Name` + Project name; used by `TimeSheetUtils` to link imported timesheets to Contact Roles. |

Record types referenced by Apex (developer names): `Project_Assignment`, `Sales_Team`, `Referral`, `Other_Participants`.

## Sharing model

Not in this repo.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **`ContactRoleTrigger.trigger`** — events: `before insert/update/delete, after insert/update/delete, after undelete`. Delegates to **`ContactRoleUtils`**:
  - `handleAfterInsert`: for `Project_Assignment` roles, generates `Project_Allocation__c` rows weekly from `Start_Date__c` (snapped back to the previous Monday via `UtilNinja.findPreviousMonday`) through `End_Date__c` (or `Start_Date__c + 365` days when null).
  - `handleAfterUpdate`: when a `Project_Assignment`'s `Hours_Per_Week__c`, `Start_Date__c`, `End_Date__c`, or `Status__c` changes, re-queries the role with its child `Project_Allocations__r` and reconciles:
    - Date-range changes: delete allocations now outside the window; insert missing weekly allocations.
    - Hours changes: update non-`Overridden__c` allocations to the new `Hours_Per_Week__c`.
    - Open-to-closed status transition (`Active` → `Completed`/`Cancelled`): delete all child allocations.
  - All other handlers are no-op stubs.
  - `getRecordTypeId(developerName)` is a cached lookup used across the codebase.
- **`OpportunityUtils.handleAfterInsert`** auto-inserts a `Referral` role when a new Opportunity carries a Lead with `Referral_Contact__c`.
- **`ProjectUtils.handleAfterInsert`** re-parents active `Contact_Role__r` records from the Opportunity onto the new Project.
- **`InvoiceUtils.handleAfterInsert`** queries the invoice's Project for `Project_Assignments__r` with record type `Referral` or `Sales_Team` and status `Active`, then creates `Referral_Commission_Payment__c` rows linking each role to the invoice.
- **`TimeSheetUtils.beforeInsert` / `beforeUpdate`** match incoming timesheet rows to Contact Roles via `Jira_Matching_Key__c` (constructed as `<Done_By_Name>-<Project_Name>`).
- **`ProjectAllocationUtils.handleBeforeUpdate`** compares an allocation's hours back to its parent Contact Role's `Hours_Per_Week__c` to decide the `Overridden__c` flag.
- **`ResourcePlannerController`** queries Project_Assignment Contact Roles to build the resource-vs-project allocation heatmap.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo. Developer names used in Apex: `Project_Assignment`, `Sales_Team`, `Referral`, `Other_Participants`.

## Constraints and gotchas

- **Weekly cadence is hardcoded to Monday-start weeks** via `UtilNinja.findPreviousMonday`. Changing to a different week-start would require revisiting both `ContactRoleUtils` and `ResourcePlannerController`.
- **365-day default end date** is silent. Open-ended Project Assignments generate up to 52 allocation rows on insert.
- **`Jira_Matching_Key__c`** must collide with the imported timesheet's `<Done_By_Name>-<Project_Name>` exactly; whitespace and capitalization mismatches result in unmatched timesheets that save without `Contact_Role__c`, `Done_By__c`, or `Project__c` populated.
- **Status: `Active` → closed transitions cascade-delete allocations.** Reactivating a closed role does *not* automatically regenerate allocations (`closed → open` branch is empty).
- **Bulk upsert risk:** the after-update handler does `upsert PAsToUpsert; delete PAsToDelete;` without batching considerations — large date-range changes on many roles at once could exceed DML row limits.

## Related ADRs

None.
