---
title: "Template_Version__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Document_Template__c.md
  - Template_Mapping__c.md
  - ContentVersion.md
---

# `Template_Version__c`

## Purpose

A revision of a [`Document_Template__c`](Document_Template__c.md). Holds the actual template body as JSON in `Definition_Json__c` (or, when it exceeds 128KB, in a `ContentVersion` titled `definition.json` linked to this record). Multiple versions per template are normal; which version renders for a given source record is decided by [`Template_Mapping__c`](Template_Mapping__c.md) rules at generate time. Lifecycle states are `Draft` → `Published` → `Archived`; only `Published` versions are selectable by mapping rules.

## Type and origin

| | |
|---|---|
| **API name** | `Template_Version__c` |
| **Type** | Custom (`__c`) |
| **Label (singular / plural)** | `Template Version` / `Template Versions` |
| **Name field** | Auto Number `TV-{0000}`, "Template Version Number" |
| **History tracking** | Enabled |
| **Origin** | Created for the PDF generator POC. |

## Key fields

| Field API name | Label | Type | Required | Purpose |
|---|---|---|---|---|
| `Document_Template__c` | Document Template | Master-Detail → `Document_Template__c` | Yes | Parent template. |
| `Definition_Json__c` | Definition JSON | Long Text Area(131072) | No | Template body — page properties, root row/col tree, text spans, merge tokens, conditional rules, tables. Read and rendered by [`PdfTemplateService.build`](../../force-app/main/default/classes/PdfTemplateService.cls). If blank, the service falls back to the spillover file (see Constraints). |
| `Status__c` | Status | Picklist (restricted) | Yes | `Draft` = editable in the builder, not pickable by mapping rules; `Published` = locked, pickable; `Archived` = hidden from selection but kept for historical PDFs. Default `Draft`. |
| `Revision_Number__c` | Revision Number | Number(4,0) | No | Numeric revision (1, 2, 3…). Used by `Template_Mapping__c` rules to map source records whose own `Revision_Number__c` (or equivalent) signals which version applies. |
| `Sample_Record_Id__c` | Sample Record Id | Text(18) | No | Last-used preview record ID for builder convenience. Stored as plain Text rather than a polymorphic reference because the target SObject varies per template. |

## Relationships

| Relationship | Field | Related object | Type | Cascade behavior |
|---|---|---|---|---|
| Parent | `Document_Template__c` | `Document_Template__c` | Master-Detail | Cascade delete |
| Reverse-lookup | (referenced from `Document_Template__c.Default_Version__c`) | `Document_Template__c` | Lookup | SetNull on this record's delete |
| Reverse-lookup | (referenced from `Template_Mapping__c.Template_Version__c`) | `Template_Mapping__c` | Lookup, deleteConstraint=Restrict | Cannot delete this version while any mapping rule points at it |
| Logical link | `ContentVersion.Source_Template_Version__c` (Text, external Id) | `ContentVersion` | Soft reference by Id string | Powers overwrite-on-regenerate |
| Files (`ContentDocumentLink`) | — | `ContentVersion` | Salesforce Files | Optional `definition.json` spillover when the JSON exceeds the field cap |

## Sharing model

- **OWD:** Controlled by Parent (`Document_Template__c`).
- **History tracking:** Enabled (changes to JSON, status, revision are tracked).
- **Sharing rules:** None.

## Validation rules

None.

## Triggers and Apex touching this object

No Apex triggers. Read/write through controllers:

- **[`PdfTemplateService`](../../force-app/main/default/classes/PdfTemplateService.cls)**:
  - `build(templateVersionId, recordId)` — queries `Id, Document_Template__c, Definition_Json__c, Status__c`, then queries the parent for `Target_SObject__c`, then loads the JSON (field or spillover file) and invokes the renderer.
  - `loadDefinitionJson(tv)` — returns `Definition_Json__c` if non-blank, else reads `ContentVersion` rows linked to this record whose `Title = 'definition.json'`.
- **[`PdfGeneratorController`](../../force-app/main/default/classes/PdfGeneratorController.cls)** — `resolveVersion(dt, recordId)` returns a `Template_Version__c.Id`; `removePriorVersions(versionId, recordId)` matches old PDFs by `ContentVersion.Source_Template_Version__c == versionId`.
- **[`TemplateBuilderController`](../../force-app/main/default/classes/TemplateBuilderController.cls)** — `getContext(templateVersionId)` returns version + parent metadata for the builder LWC; `previewTemplate(...)` renders unsaved JSON against a sample record via `PdfTemplateService.buildFromJson`; `saveTemplate(templateVersionId, defJson, sampleRecordId)` validates JSON parses, then updates `Definition_Json__c` and `Sample_Record_Id__c`.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

None.

## Constraints and gotchas

- **128KB spillover:** `Definition_Json__c` is capped at 131,072 chars. When a template exceeds that, the builder writes the JSON as a `ContentVersion` with `Title = 'definition.json'` attached to the version record; `PdfTemplateService.loadDefinitionJson` transparently picks file-over-field. Editing the spillover by hand requires uploading a new file version with the same title.
- **Status gating is policy, not enforced:** Nothing in Apex prevents a mapping rule from pointing at a `Draft` version — the picker UI is expected to surface only `Published` rows, but bulk DML or Data Loader could create rules that pick a Draft.
- **`deleteConstraint=Restrict` on incoming mapping references:** You cannot delete a version while any `Template_Mapping__c` still references it. Archive instead.
- **`Sample_Record_Id__c` is a text field**, not a lookup — there is no referential integrity. The builder simply blanks the preview if the record no longer exists.
- **History tracking is on** for this object specifically because version contents are auditable.

## Related ADRs

None.
