---
title: "ContentVersion"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Document_Template__c.md
  - Template_Version__c.md
  - Signature__c.md
---

# `ContentVersion`

## Purpose

Standard Salesforce Files object. This engagement customizes it with one custom field, `Source_Template_Version__c`, which records the [`Template_Version__c`](Template_Version__c.md) that produced a generated PDF. The field is what enables the "overwrite-on-regenerate" behavior in `PdfGeneratorController`: on regenerate, prior PDFs for the same template version on the same record are deleted before a fresh one is inserted. The field is also used (as a `Title` filter rather than a value) for definition JSON spillover when a `Template_Version__c.Definition_Json__c` exceeds 128KB.

## Type and origin

| | |
|---|---|
| **API name** | `ContentVersion` |
| **Type** | Standard, with engagement-specific custom field |
| **Origin** | Out-of-box Salesforce object. The custom field was added for the PDF generator POC. |

## Key fields (custom only)

| Field API name | Label | Type | Required | External Id | Purpose |
|---|---|---|---|---|---|
| `Source_Template_Version__c` | Source Template Version | Text(18) | No | Yes | Stores the `Template_Version__c.Id` (as a string) that produced this PDF. Used to find and supersede prior generated copies when the template's `Overwrite_Existing_File__c` flag is true. Marked external Id so SOQL filtering on this value is indexed. |

All standard `ContentVersion` fields apply normally (Title, PathOnClient, VersionData, ContentDocumentId, FileType, FileExtension, IsLatest, etc.).

## Relationships

Standard Files-object relationships. The engagement-specific link is logical, not declarative:

- `Source_Template_Version__c` is plain Text holding an Id string, not a Lookup. This is intentional — `Template_Version__c` is custom and can be deleted; the string survives orphaned without a cascade.
- Files attach to other records (e.g., `Form__c`, `Template_Version__c`, the source record receiving a generated PDF) via `ContentDocumentLink.LinkedEntityId`.

## Sharing model

Standard Files sharing (`ContentDocumentLink.ShareType` / `Visibility`). `PdfGeneratorController` creates links with `ShareType = 'V'` (Viewer) and `Visibility = 'AllUsers'`.

## Validation rules

None added by this engagement.

## Triggers and Apex touching this object

No Apex triggers.

Apex consumers:

- **`PdfGeneratorController.doGenerate`** inserts a new `ContentVersion` for each generated PDF, setting `Title`, `PathOnClient`, `VersionData`, and `Source_Template_Version__c = String.valueOf(versionId)`. It then inserts a `ContentDocumentLink` to attach the new file to the source record.
- **`PdfGeneratorController.removePriorVersions`** — when `Document_Template__c.Overwrite_Existing_File__c = true`, queries `ContentVersion` rows linked to the source record where `IsLatest = true AND Source_Template_Version__c = :versionStr`, collects their `ContentDocumentId`s, and deletes the underlying `ContentDocument`s.
- **`PdfTemplateService.loadDefinitionJson`** — when a `Template_Version__c.Definition_Json__c` is blank, looks for a `ContentVersion` titled exactly `definition.json` linked to that version record and reads its `VersionData` as the template body. This is the spillover path for templates larger than the 128KB long-text cap.
- **`PdfTemplateService.loadFirstFileAsDataUri`** — for any record (typically a [`Signature__c`](Signature__c.md)), reads the most recent `ContentVersion.IsLatest = true` and inlines it as a base64 data URI in the rendered HTML. MIME type is inferred from `FileExtension` (`jpg`/`jpeg` → `image/jpeg`, `gif` → `image/gif`, `svg` → `image/svg+xml`, else `image/png`).

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

None.

## Constraints and gotchas

- `Source_Template_Version__c` is **plain Text holding an Id string**, not a Lookup, by design — `Template_Version__c` can be deleted/archived without breaking the file. Code must use `String.valueOf(versionId)` when querying.
- The "overwrite" path matches **only files where `Source_Template_Version__c` equals the same version that just rendered**. Re-rendering with a different `Template_Version__c` (e.g., after a mapping rule change) will *not* supersede the older file — it lands as a sibling. This is documented behavior, but easy to overlook.
- The spillover JSON is keyed by the file's `Title = 'definition.json'` (case-sensitive exact match). Renaming the file silently breaks the template.
- `loadFirstFileAsDataUri` picks the latest `ContentVersion` for the linked record without filtering by file type — uploading a PDF as a signature image will produce broken `<img>` output.

## Related ADRs

None.
