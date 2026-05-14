---
title: "Form__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Signature__c.md
  - Document_Template__c.md
---

# `Form__c`

## Purpose

Demo/dummy object representing a quality form (e.g., Pre-Op, Post-Op) in the PDF generator POC. The generator itself is object-agnostic — it can render against any SObject whose API name is set on `Document_Template__c.Target_SObject__c` — but `Form__c` exists so the builder has realistic, shaped data (with record types and a signature relationship) to test merge tokens, conditional rules, and image embedding against. Outside the POC, `Form__c` carries no business meaning.

## Type and origin

| | |
|---|---|
| **API name** | `Form__c` |
| **Type** | Custom (`__c`) |
| **Label (singular / plural)** | `Form` / `Forms` |
| **Name field** | `Name` — Text, "Form Name" |
| **Origin** | Created for the PDF generator POC as a sample target object. |

## Key fields

| Field API name | Label | Type | Required | Purpose |
|---|---|---|---|---|
| `Patient_Name__c` | Patient Name | Text(120) | No | Sample subject of the form. Mergeable into PDFs as `{{Patient_Name__c}}`. |
| `Procedure_Date__c` | Procedure Date | Date | No | Sample date field for date-formatting tests in the PDF renderer. |
| `Revision_Number__c` | Revision Number | Number(4,0) | No | Revision of the underlying quality form template. Used by `Template_Mapping__c` rules to pick the correct `Template_Version__c` for a given form. |
| `Status__c` | Status | Picklist (restricted): `Draft` (default), `In Progress`, `Complete` | No | Lifecycle of a form instance. |
| `Comments__c` | Comments | Long Text Area(32000) | No | Free-form notes; useful for testing long-text rendering. |

Standard fields used: `Id`, `Name`, `CreatedDate`, `LastModifiedDate`, `OwnerId`, `RecordTypeId`.

## Relationships

| Relationship | Field | Related object | Type | Cascade behavior |
|---|---|---|---|---|
| Child (reverse) | `Signatures` ([`Signature__c.Form__c`](Signature__c.md)) | `Signature__c` | Master-Detail | Cascade delete |

## Sharing model

- **OWD:** Public Read/Write (internal and external).
- **History tracking:** Disabled.
- **Sharing rules:** None.

## Validation rules

None.

## Triggers and Apex touching this object

No Apex triggers.

`Form__c` is exercised as data by the PDF generator stack:

- **[`PdfTemplateService`](../../force-app/main/default/classes/PdfTemplateService.cls)** queries it dynamically when a `Document_Template__c.Target_SObject__c = 'Form__c'`. Field set discovered by walking the template JSON for `{{token}}` references; child rows fetched via the `Signatures` child-relationship.
- **[`PdfGeneratorController.computeFileName`](../../force-app/main/default/classes/PdfGeneratorController.cls)** expands `{{Patient_Name__c}}`, `{{Procedure_Date__c}}`, etc. into the saved PDF's file name.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

| Developer name | Label | Active | Picklist filters |
|---|---|---|---|
| `Pre_Op` | Pre-Op | Yes | `Status__c`: Draft / In Progress / Complete (default Draft) |
| `Post_Op` | Post-Op | Yes | `Status__c`: Draft / In Progress / Complete (default Draft) |

Record types exist to demonstrate the `Template_Mapping__c.Record_Type_Developer_Name__c` selection path: a single Pre-Op/Post-Op `Document_Template__c` can route to different `Template_Version__c` records based on the form's record type.

## Constraints and gotchas

- This object exists for the POC; do not build production processes against it.
- The `Status__c` picklist is restricted; values cannot be added without metadata changes.
- Standard list view: `All`.

## Related ADRs

None.
