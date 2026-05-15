---
title: "Contact"
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets:
  - GRIM-50
related_docs:
  - Account.md
  - Contact_Role__c.md
---

# `Contact`

## Purpose

Standard Salesforce `Contact` object. Two pieces of engagement-specific automation run on save: a `Lead_Id_Passable__c → Lead__c` projection (mirroring the staging-field pattern used on Account and Opportunity), and a phone-number normalizer that reformats `Phone` to `(XXX) XXX-XXXX` for 10-digit and 11-digit-leading-1 inputs. Contacts are referenced extensively as participants/resources on [`Contact_Role__c`](Contact_Role__c.md), which is where the meaningful business logic lives.

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

Standard fields used: `Id`, `FirstName`, `LastName`, `AccountId`, `Name`, `Phone`.

## Sharing model

Not in this repo. Standard `Contact` OWD configured in setup.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **`ContactTrigger.trigger`** — declared on `before insert, before update`. Dispatches to two collaborators in order:
  1. **`ContactUtils`** — `handleBeforeInsert` / `handleBeforeUpdate` set `currentContact.Lead__c = currentContact.Lead_Id_Passable__c` on each row, the same staging-field projection used by Account and Opportunity. `handleBeforeDelete` and all `handleAfter*` methods are no-op stubs.
  2. **`ContactPhoneNormalizer`** — `normalize(List<Contact>)` reformats each `Phone` in-place. Strips non-digits; if the result is 10 digits, formats as `(XXX) XXX-XXXX`; if it is 11 digits with a leading `1`, drops the `1` and formats; otherwise leaves the field unchanged. Pure in-memory mutation — no SOQL, no DML, idempotent on already-formatted input.
- **`ResourcePlannerController.cls`** reads Contact via the `Contact_Role__c.Contact__r` traversal — never queries Contact directly, but treats it as the resource entity in the planner UI.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **Partially-reachable trigger body:** `ContactTrigger` is declared `on Contact (before insert, before update)`. Its body also contains `if/else if` branches for `before delete`, `after insert/update/delete/undelete` — those branches are unreachable because the header does not declare those events. The dead branches dispatch to `ContactUtils.handleAfter*` / `handleBeforeDelete`, which are themselves no-op stubs.
- **`Lead__c` projection runs on every update:** because `ContactTrigger` covers `before update`, the unconditional `Lead__c = Lead_Id_Passable__c` assignment in `ContactUtils.handleBeforeUpdate` fires on every Contact update. Routine updates that do not populate `Lead_Id_Passable__c` will set `Lead__c` to null. This mirrors Account's behavior via `AccountUtils.handleBeforeUpdate` + `AccountBeforeChange`.
- **Phone normalization is one-way:** the trigger reformats inputs but never restores them. International numbers (anything that isn't 10 digits, or 11 digits with leading `1`, after stripping) pass through verbatim. `MobilePhone`, `HomePhone`, and `OtherPhone` are not normalized.
- `ContactUtils.generateContact` is a test-data factory; it does not consume `Lead_Id_Passable__c`.

## Related ADRs

None.
