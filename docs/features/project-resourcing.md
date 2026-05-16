---
title: Project Resourcing
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs:
  - ../objects/Project__c.md
  - ../objects/Contact_Role__c.md
  - ../objects/Project_Allocation__c.md
  - ../objects/Contact.md
---

# `Project Resourcing`

> Resources staffed onto a project automatically generate weekly hour allocations from start date through end date; a planner UI lets delivery managers see who is over- or under-allocated week by week.

## Overview

When a [`Contact_Role__c`](../objects/Contact_Role__c.md) of record type `Project_Assignment` is created on a [`Project__c`](../objects/Project__c.md), the system spawns one [`Project_Allocation__c`](../objects/Project_Allocation__c.md) row per Monday-starting week from the assignment's start date through its end date, defaulting the planned hours to the role's `Hours_Per_Week__c`. Updating the role's window, hours, or status reconciles the allocations (creating, deleting, or re-houring as needed). Delivery managers consume the resulting matrix through `ResourcePlannerController`, which renders a resource-vs-project heatmap of weekly planned hours bounded by each `Contact.Max_Hours_Per_Week__c`.

## How it works

1. **Project is born from an Opportunity.** When a `Project__c` is inserted with an `Opportunity__c` set, the system re-parents the opportunity's active `Contact_Role__c` records onto the new project in one bulk update — the sales-to-delivery handoff.
2. **Staff resources onto the project.** An admin creates a `Project_Assignment` Contact Role with a contact, start date, end date (null = open-ended → defaults to start + 365 days), and weekly hours.
3. **Allocations auto-generate.** On role insert, the system walks weekly from the previous Monday before `Start_Date__c` through `End_Date__c`, creating one `Project_Allocation__c` per week with `Hours__c` defaulted to the role's `Hours_Per_Week__c`.
4. **Edit a single week.** A user can override a specific week by editing the allocation's `Hours__c` directly. Before-update logic on the allocation compares the new value to the parent role's standard hours and sets `Overridden__c = true` (or clears it, if they realign).
5. **Edit the role.** Changing the role's date range causes allocations outside the new window to be deleted and missing weeks to be inserted. Changing `Hours_Per_Week__c` updates non-overridden allocations to the new hours; overridden ones are preserved. Flipping the role's `Status__c` from `Active` to `Completed`/`Cancelled` cascade-deletes all child allocations (including overridden ones).
6. **View the heatmap.** `ResourcePlannerController` builds a model joining active projects, their `Project_Assignment` Contact Roles, and the per-week allocations into a resource-vs-week matrix used by the planner UI. Each contact's `Max_Hours_Per_Week__c` caps the cell display so over-allocation is visible.

## Acceptance signals

- Creating a `Project_Assignment` Contact Role with start `2026-05-04` (Monday) and end `2026-06-01` produces five `Project_Allocation__c` rows dated 2026-05-04, 05-11, 05-18, 05-25, 06-01, each with `Hours__c` matching the role.
- Editing a single allocation's `Hours__c` sets `Overridden__c = true`; a subsequent role-level hours change leaves the overridden week alone.
- Closing the role (`Status__c → Completed`) removes all child allocations.
- The resource planner view shows that resource's weekly plan against the parent project's `Target_Weekly_Hours__c`.

## Known limitations

- **Monday-start weeks are hardcoded.** Both `ContactRoleUtils` allocation generation and `ResourcePlannerController.findPreviousMonday` assume Monday cadence. A different week-start would require coordinated changes in both.
- **Manually inserted allocations that don't align to a Monday are invisible** in the planner UI — the heatmap walks Monday-by-Monday and looks up cells by `Start_Date__c`.
- **365-day default end date for open-ended roles** silently generates up to 52 allocation rows on insert.
- **Reactivating a closed role does not regenerate allocations.** The `Closed → Active` branch is empty; the role becomes active without any weekly plan rows until someone manually edits dates or hours to force a re-run of the reconcile path.
- **Inactive projects are silently hidden** from the planner (`RecordTypeId == Active` filter).
- **Bulk DML risk** on large date-range changes — the after-update handler does `upsert` and `delete` without batching, so a wide change set could approach DML row limits.
- **Project re-parenting fires once on Project insert only.** Changing `Opportunity__c` later does not pull in roles from the new opportunity, and the re-parented roles keep their old `Opportunity__c` set alongside the new `Project__c`.

## Related tickets

None recorded at the engagement level for this baseline behavior.
