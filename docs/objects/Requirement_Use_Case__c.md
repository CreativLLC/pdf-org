---
title: "Requirement_Use_Case__c"
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs: []
---

# `Requirement_Use_Case__c`

## Purpose

Custom object representing a use case that estimates effort for a parent `Requirement__c`. The trigger on this object is currently **inert** — its body is entirely commented out — but the intended behavior, preserved as comments, is to roll up each requirement's child use cases' estimated time fields (configuration, design, development, documentation, project management, reporting, testing, training) onto the parent `Requirement__c` after every save.

## Type and origin

| | |
|---|---|
| **API name** | `Requirement_Use_Case__c` |
| **Type** | Custom (`__c`) |
| **Origin** | Not in this repo's `force-app/main/default/objects/`. Authored prior to this engagement. |

## Schema

Schema metadata not present in this repo's `force-app/main/default/objects/`. Behavior below is derived from trigger and handler Apex.

Fields referenced in the commented trigger body:

| Field reference | Inferred type | Purpose |
|---|---|---|
| `Requirement__c` | Lookup → `Requirement__c` | Parent requirement. |
| `Estimated_Configuration_Time__c` | Number | Configuration effort. |
| `Estimated_Design_Time__c` | Number | Design effort. |
| `Estimated_Development_Time__c` | Number | Development effort. |
| `Estimated_Documentation_Time__c` | Number | Documentation effort. |
| `Estimated_Project_Management_Time__c` | Number | PM effort. |
| `Estimated_Reporting_Time__c` | Number | Reporting effort. |
| `Estimated_Testing_Time__c` | Number | Testing effort. |
| `Estimated_Training_Time__c` | Number | Training effort. |

## Sharing model

Not in this repo.

## Validation rules

Not in this repo.

## Triggers and Apex touching this object

- **`RequirementUseCaseAfterSave.trigger`** — events: `after insert, after update`. **Body is entirely commented out.** No runtime behavior. The commented logic, if uncommented, would:
  1. Collect referenced `Requirement__c` ids from the trigger context.
  2. Query all `Requirement_Use_Case__c` records under those requirements.
  3. Sum the eight estimate fields per requirement.
  4. Update each parent `Requirement__c` with the sums.
- **`TestRequirementTriggers.cls`** — test class (not read here in detail) presumably covers the disabled behavior.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

Not in this repo.

## Constraints and gotchas

- **The trigger is inert.** Anyone expecting requirement-level rollups today is mistaken — the parent `Requirement__c` numeric fields will be stale unless populated by some other mechanism (a formula field, a separate flow, or manual entry).
- The commented logic uses `UtilNinja.smartValue(...)` to coerce nulls to zero before summing.
- If the trigger is re-enabled, note that it loads *every* Use Case under the affected requirements on every save — not just the ones in `Trigger.new` — to recompute totals. This is correct for a rollup but is O(n_per_requirement) per save event; bulk inserts could approach SOQL row limits.
- Bare `trigger` (no handler class delegation) — does not follow the `XxxTrigger` → `XxxUtils` pattern used by most other triggers in this org.

## Related ADRs

None.
