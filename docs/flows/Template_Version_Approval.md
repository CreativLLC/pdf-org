---
title: "Template Version Approval"
audience: public
last_updated: 2026-05-16
last_updated_by: drew.smith@openwacca.com
related_tickets:
  - GRIM-52
related_docs:
  - ../objects/Template_Version__c.md
  - ../objects/Template_Mapping__c.md
---

# `Template Version Approval`

## Purpose

Captures the approval milestone on a [`Template_Version__c`](../objects/Template_Version__c.md). When a template version transitions to `Status = Approved`, this Flow cascades a timestamp (`Approved_At__c`) onto every [`Template_Mapping__c`](../objects/Template_Mapping__c.md) record that points at the now-approved version and doesn't already carry a stamp. The audit trail answers "when did mapping rule X start pointing at an approved version?" without having to reconstruct it from `LastModifiedDate` or `setupAuditTrail` history.

## Type and trigger

| | |
|---|---|
| **API name** | `Template_Version_Approval` |
| **Type** | Record-Triggered (Auto-Launched) |
| **Triggering object** | `Template_Version__c` |
| **Trigger condition** | Created OR Updated AND record changed to meet criteria. Filter: `ISPICKVAL({!$Record.Status__c}, 'Approved')`. |
| **Trigger order** | After-save (`RecordAfterSave`) |
| **Run-as user** | Triggering user (`CurrentTransaction` model) |
| **Active version** | 1 |

## What it does

One step:

1. **Invoke Apex action** `TemplateVersionApprovalHandler` (the `@InvocableMethod` named `Stamp Approval On Related Mappings`) with `templateVersionId = {!$Record.Id}`. The handler queries `Template_Mapping__c` where `Template_Version__c = :id AND Approved_At__c = NULL`, stamps each with `Datetime.now()`, and bulk-updates them in a single DML.

No decisions, loops, or assignments in the Flow itself — all the work is in the Apex.

## Side effects

- **Records updated:** `Template_Mapping__c.Approved_At__c` on every mapping pointing at the just-approved version where the stamp is still `NULL`. Idempotent: subsequent runs against an already-stamped mapping skip it.
- **No platform events, no outbound callouts, no emails.**

## Error handling

- **Fault paths:** none configured. The Apex Action throws on DML failure (e.g., FLS denial, validation rule), which Salesforce surfaces to the user that saved the Template_Version__c. For background updates (e.g., from an integration), the failure shows up in the Flow Interview error email to the org admin and in Setup → Process Automations → Paused and Failed Interviews.
- **Errors users see:** if a user manually transitions `Status` to `Approved` and the cascade fails, they see a Salesforce error toast: "Flow Template Version Approval failed... <DML error>." The save of the Template_Version__c also rolls back.
- **Retries:** none. If the Flow fails, the user (or admin) reruns the same status transition after fixing the underlying issue.

## Dependencies

- **Apex actions:** `TemplateVersionApprovalHandler.stampApproval` (in `force-app/main/default/classes/TemplateVersionApprovalHandler.cls`).
- **Picklist value:** `Template_Version__c.Status__c` must include `Approved` (added alongside this Flow).
- **Field:** `Template_Mapping__c.Approved_At__c` must exist (added alongside this Flow).
- **Permissions:** users transitioning `Status__c` to `Approved` need edit on `Template_Version__c.Status__c` AND the Apex action must be executable in their context (i.e., they need access to the `TemplateVersionApprovalHandler` class — currently granted to nobody explicitly; rely on system-context Apex Action invocation from the Flow).

## Performance and limits

- **Bulkification:** record-triggered Flows fire per-record but Salesforce bulks them at the platform level when many records save in one transaction. The Apex receives a `List<Input>` and issues exactly one SOQL + one DML regardless of input size — verified by the bulk-200 test in `TemplateVersionApprovalHandler_Test`.
- **DML count:** 1 per Flow invocation (the Apex's update).
- **SOQL count:** 1 per Flow invocation (the Apex's query).
- **Known governor risks:** if a single Template Version has thousands of mappings, the SOQL row limit (50,000) could matter — but realistically each version has < 20 mappings.

## Testing

- **Apex test class:** `TemplateVersionApprovalHandler_Test` — exercises the invocable directly with 1-version, idempotent, bulk-200, and empty-input scenarios. The Flow itself has no test coverage requirement (Flows are exempt from the Apex coverage gate), but the same Apex test verifies the Flow's end-state semantics.
- **Manual test scenarios:**
  1. In Setup → Salesforce Files, open a `Template_Version__c` record in `Draft`. Change `Status` to `Approved`. Save. Refresh. Inspect a related `Template_Mapping__c`: `Approved_At__c` should be `~now`.
  2. Re-save the same record (no status change). The Flow's `doesRequireRecordChangedToMeetCriteria` filter prevents re-firing.
  3. Pre-stamp a `Template_Mapping__c` with an old `Approved_At__c`. Approve a sibling version that points at the same mapping. The pre-stamped mapping should retain its old timestamp (idempotency).

## Ownership and on-call

- **Subject-matter owner:** PDF generator product team.
- **Operational owner:** Meditrina admin (drew.smith@openwacca.com on this engagement).

## Related decisions

_None._
