---
title: "Contact"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Account.md
  - Contact_Role__c.md
---

# `Contact`

## Purpose

Standard Salesforce `Contact` object. The engagement-specific customization is minimal: a single trigger that re-projects a custom `Lead_Id_Passable__c` staging field onto the standard-named custom `Lead__c` lookup. Contacts are referenced extensively as participants/resources on [`Contact_Role__c`](Contact_Role__c.md), which is where the meaningful business logic lives.

## Type and origin

| | |
|---|---|
| **API name** | `Contact` |
| **Type** | Standard |
| **Origin** | Out-of-box. Engagement adds one trigger. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Custom fields referenced by Apex:

| Field reference | Inferred type | Source | Purpose |
|---|---|---|---|
| `Lead__c` | Lookup → `Lead` | `ContactUtils` | Populated on before-insert/update from `Lead_Id_Passable__c`. |
| `Lead_Id_Passable__c` | Text / Id | `ContactUtils` | Staging field — writable proxy lifted onto `Lead__c`. |
| `Max_Hours_Per_Week__c` | Number | `ResourcePlannerController` reads this when treating a Contact as a project resource | Cap on resource availability used in the planner heatmap. |

Standard fields used: `Id`, `FirstName`, `LastName`, `AccountId`, `Name`.

## Sharing model

Not in this repo. Standard `Contact` OWD configured in setup.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **[`ContactTrigger.trigger`](../../force-app/main/default/triggers/ContactTrigger.trigger)** — declared on `before insert` only (despite the body checking other events; the trigger header limits which actually fire). Delegates to **[`ContactUtils`](../../force-app/main/default/classes/ContactUtils.cls)**:
  - `handleBeforeInsert` / `handleBeforeUpdate`: sets `currentContact.Lead__c = currentContact.Lead_Id_Passable__c` on each row.
  - All `handleAfter*` / `handleBeforeDelete` / `handleAfterUndelete` are no-op stubs.
- **[`ResourcePlannerController.cls`](../../force-app/main/default/classes/ResourcePlannerController.cls)** reads Contact via the `Contact_Role__c.Contact__r` traversal — never queries Contact directly, but treats it as the resource entity in the planner UI.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **Trigger header mismatch:** `ContactTrigger` is declared `on Contact (before insert)` but the body contains `if/else if` branches for update, delete, after-insert, etc. Only the `before insert` branch is ever reachable. If/when more events need wiring, expand the trigger declaration.
- `ContactUtils.generateContact` is a test-data factory; it does not consume `Lead_Id_Passable__c`.

## Related ADRs

None.
