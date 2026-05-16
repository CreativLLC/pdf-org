---
title: "Project__c"
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs:
  - Account.md
  - Opportunity.md
  - Contact_Role__c.md
  - Project_Allocation__c.md
  - Invoice__c.md
---

# `Project__c`

## Purpose

Custom delivery object representing a piece of work after the [`Opportunity`](Opportunity.md) closes. Projects own a customer ([`Account`](Account.md)), an originating opportunity, weekly hour targets, payment terms, and downstream [`Contact_Role__c`](Contact_Role__c.md) records (resources staffed to the project) plus [`Invoice__c`](Invoice__c.md) records. On insert, the trigger re-parents active `Contact_Role__c` rows from the source Opportunity onto the new Project — bridging the sales-to-delivery handoff in one DML pass.

## Type and origin

| | |
|---|---|
| **API name** | `Project__c` |
| **Type** | Custom (`__c`) |
| **Origin** | Not in this repo's `force-app/main/default/objects/`. Authored prior to this engagement. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced by Apex (`ProjectUtils`, `ResourcePlannerController`, `InvoiceUtils`, `InvoicePDFController`):

| Field reference | Inferred type | Purpose |
|---|---|---|
| `Account__c` | Lookup → `Account` | Customer. |
| `Opportunity__c` | Lookup → `Opportunity` | Source sales record. Used by `ProjectUtils.handleAfterInsert` to find Contact Roles to re-parent. |
| `Status__c` | Picklist | E.g., `New`. |
| `RecordTypeId` | RecordType | Active vs. inactive states. Developer name `Active` used in Apex. |
| `Target_Weekly_Hours__c` | Number | Used by `ResourcePlannerController` for the project allocation heatmap. |
| `Net_Payment_Terms__c` | Picklist | Drives `Invoice__c.Payment_Days__c` default. Values: `Net 7`, `Net 15`, `Net 30`, others fall through to `30`. |
| `PO_Number__c` | Text | Read by `InvoicePDFController`. |
| `Contact_Role__r` (child relationship via `Contact_Role__c.Project__c`) | Child | Project assignments / sales / referrals tied to this project. |
| `Project_Assignments__r` | Child (alias) | Same child rel, used by `InvoiceUtils.handleAfterInsert` when filtering by record type. |

## Sharing model

Not in this repo.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **`ProjectTrigger.trigger`** — full event set, delegating to **`ProjectUtils`**:
  - `handleAfterInsert`: for any new Project with `Opportunity__c` set, queries the Opportunity for active `Contact_Role__r` rows and updates each one's `Project__c = currentProject.Id`. Bulk update.
  - All other handlers are no-op stubs.
  - `getRecordTypeId(developerName)` cached lookup; `generateProject` is a test-data factory.
- **`ResourcePlannerController.getResourcePlannerModel`** primes its project map with `[SELECT Id, Name, Target_Weekly_Hours__c, Account__r.Name FROM Project__c WHERE RecordTypeId = :Active]`, then joins to `Contact_Role__c` Project Assignments to build the weekly allocation matrix.
- **`InvoiceUtils`** reads `Project__c.Net_Payment_Terms__c` to default `Invoice__c.Payment_Days__c`, and queries `Project_Assignments__r` to create commission payments.
- **`InvoicePDFController`** reads `Project__r.Name` and `Project__r.PO_Number__c`.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo. Developer name used in Apex: `Active`.

## Constraints and gotchas

- **Contact Role re-parenting fires once on Project insert.** Changing the Project's `Opportunity__c` later does *not* pull in Contact Roles from the new Opportunity. This is consistent with the sales-to-delivery handoff intent but worth knowing when migrating data.
- **The re-parented Contact Roles still keep `Opportunity__c` set** (the after-insert handler only sets `Project__c`, never blanks `Opportunity__c`).
- **`Project_Assignments__r` child relationship name** in `InvoiceUtils` differs from `Contact_Role__r` used in `ProjectUtils`. Both resolve to the same child object (`Contact_Role__c.Project__c`) — child relationship name appears to be aliased in the metadata. Be careful when reading SOQL across these two classes.
- `ResourcePlannerController` only surfaces projects whose `RecordTypeId == Active`; inactive projects are silently filtered.

## Related ADRs

None.
