---
title: "Project_Allocation__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Contact_Role__c.md
  - Project__c.md
---

# `Project_Allocation__c`

## Purpose

A single week's planned hours for a [`Contact_Role__c`](Contact_Role__c.md) `Project_Assignment`. Allocations are auto-generated weekly (Monday-start) from the parent Contact Role's `Start_Date__c` through `End_Date__c` when the role is created or its window changes. Hours default to the role's `Hours_Per_Week__c`; an individual week's hours can be overridden by editing the allocation directly, in which case the `Overridden__c` flag is set so future role-level hour changes won't clobber the per-week value.

## Type and origin

| | |
|---|---|
| **API name** | `Project_Allocation__c` |
| **Type** | Custom (`__c`) |
| **Origin** | Not in this repo's `force-app/main/default/objects/`. Authored prior to this engagement. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced by Apex (`ProjectAllocationUtils`, `ContactRoleUtils`, `ResourcePlannerController`):

| Field reference | Inferred type | Purpose |
|---|---|---|
| `Contact_Role__c` | Lookup → `Contact_Role__c` | Parent assignment. |
| `Start_Date__c` | Date | First day of the week (Monday) for this allocation. |
| `End_Date__c` | Date | Last day of the allocation week (typically Start + 6). |
| `Hours__c` | Number | Planned hours for the week. Defaults to parent's `Hours_Per_Week__c`. |
| `Overridden__c` | Checkbox | Set automatically in `before update` when `Hours__c` differs from the parent Contact Role's `Hours_Per_Week__c`. Cleared when they re-align. |

## Sharing model

Not in this repo.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **[`ProjectAllocationTrigger.trigger`](../../force-app/main/default/triggers/ProjectAllocationTrigger.trigger)** — full event set, delegating to **[`ProjectAllocationUtils`](../../force-app/main/default/classes/ProjectAllocationUtils.cls)**:
  - `handleBeforeUpdate`: for any allocation whose `Hours__c` changed, queries the parent Contact Role's `Hours_Per_Week__c` and sets `Overridden__c = (Hours__c != Hours_Per_Week__c)`. This is the inverse signal used by `ContactRoleUtils.handleAfterUpdate` (it skips overridden allocations when bulk-updating hours).
  - All other handlers are no-op stubs.
  - `generateProjectAllocation` is a test-data factory.
- **[`ContactRoleUtils.handleAfterInsert`/`handleAfterUpdate`](../../force-app/main/default/classes/ContactRoleUtils.cls)** is the *only* source of allocation creates/deletes/upserts. Allocations are not typically created by hand.
- **[`ResourcePlannerController`](../../force-app/main/default/classes/ResourcePlannerController.cls)** queries allocations through the `Contact_Role__c.Project_Allocations__r` child relationship and sums per-week hours by resource and by project to render the heatmap.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **`Overridden__c` is computed only when `Hours__c` changes.** Initial inserts skip the comparison; the field stays at its declared default (presumably `false`) until the first edit.
- **Manually inserted allocations** that don't align to a Monday will not be visible in the `ResourcePlannerController` heatmap, which iterates from `findPreviousMonday(filterStart)` in 7-day steps and lookups by `Start_Date__c` as the map key.
- **Cascade-delete on Contact Role status close:** when `ContactRoleUtils` flips a role from `Active` → `Completed`/`Cancelled`, *all* child allocations are deleted, including overridden ones. Reopening the role does not regenerate them.
- The `ProjectAllocationUtils.generateProjectAllocation` factory does **not** set `End_Date__c`. The end date is presumably a formula field (e.g., `Start_Date__c + 6`) defined in metadata not in this repo.

## Related ADRs

None.
