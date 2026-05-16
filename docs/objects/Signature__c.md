---
title: "Signature__c"
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs:
  - Form__c.md
  - ContentVersion.md
---

# `Signature__c`

## Purpose

Demo/dummy child of [`Form__c`](Form__c.md) representing a single signature slot on a quality form (patient, physician, or witness). The actual signature image is **not** stored on this record — it is uploaded as a Salesforce File (`ContentVersion` linked via `ContentDocumentLink`) attached to the `Signature__c` record. The PDF renderer uses `Signature_Type__c` to discriminate which signature belongs in which slot of a multi-signature template; see `PdfTemplateService.resolveImageDataUri` which filters child rows by `Signature_Type__c == 'Physician'` (etc.) and inlines the first attached file as a data URI.

## Type and origin

| | |
|---|---|
| **API name** | `Signature__c` |
| **Type** | Custom (`__c`) |
| **Label (singular / plural)** | `Signature` / `Signatures` |
| **Name field** | Auto Number `SIG-{0000}`, "Signature Number" |
| **Origin** | Created for the PDF generator POC. |

## Key fields

| Field API name | Label | Type | Required | Purpose |
|---|---|---|---|---|
| `Form__c` | Form | Master-Detail → `Form__c` | Yes | Parent form record. |
| `Signature_Type__c` | Signature Type | Picklist (restricted): `Patient` (default), `Physician`, `Witness` | Yes | Distinguishes which slot in a multi-signature template a given signature feeds. Templates filter child rows by this value. |
| `Signed_By__c` | Signed By | Text(120) | No | Display name of the signer. |
| `Signed_At__c` | Signed At | DateTime | No | When the signature was captured. |

The signature **image bytes** are not a field on this object; they live on related `ContentVersion` records found via `ContentDocumentLink.LinkedEntityId = :Signature.Id`.

## Relationships

| Relationship | Field | Related object | Type | Cascade behavior |
|---|---|---|---|---|
| Parent | `Form__c` | `Form__c` | Master-Detail | Cascade delete |
| Files (`ContentDocumentLink`) | — | `ContentVersion` | Salesforce Files | Image file(s) for the signature |

## Sharing model

- **OWD:** Controlled by Parent (`Form__c`).
- **History tracking:** Disabled.
- **Sharing rules:** None.

## Validation rules

None.

## Triggers and Apex touching this object

No Apex triggers.

Read indirectly by the PDF stack:

- **`PdfTemplateService.queryRelated`** — when a template's JSON references the `Signatures` child relationship (e.g., for a Physician signature image), this method dynamically queries `Signature__c` rows under the source `Form__c` record.
- **`PdfTemplateService.resolveImageDataUri`** — evaluates a `filterExpr` such as `row.Signature_Type__c == 'Physician'` against the child rows, picks the first match, then loads its first attached `ContentVersion` as a base64 data URI for inline embedding in the rendered HTML/PDF.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

None.

## Constraints and gotchas

- The "signature" is conceptually two parts: the metadata record (`Signature__c`) and the image file (`ContentVersion`). Deleting the file while keeping the record results in an empty image slot in regenerated PDFs.
- `PdfTemplateService.loadFirstFileAsDataUri` picks the most-recently-created `ContentVersion.IsLatest = true` linked to the signature; if the user uploads multiple images, only the latest is rendered.
- Master-detail with `reparentableMasterDetail=false` — a signature cannot be moved between forms.
- Standard list view: `All`.

## Related ADRs

None.
