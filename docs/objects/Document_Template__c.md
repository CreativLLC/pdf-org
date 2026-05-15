---
title: "Document_Template__c"
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - Template_Version__c.md
  - Template_Mapping__c.md
  - ContentVersion.md
---

# `Document_Template__c`

## Purpose

Root template for a class of generated PDF documents (e.g., Pre-Op Form, Training Record). A `Document_Template__c` is bound to a single target SObject (any custom or standard object via API name) and acts as the parent for one-or-many [`Template_Version__c`](Template_Version__c.md) records and the [`Template_Mapping__c`](Template_Mapping__c.md) rules that pick which version renders for a given source record. It is the user-facing handle exposed to admins ("the Pre-Op form") even though the actual layout JSON lives on the child version.

## Type and origin

| | |
|---|---|
| **API name** | `Document_Template__c` |
| **Type** | Custom (`__c`) |
| **Label (singular / plural)** | `Document Template` / `Document Templates` |
| **Name field** | `Name` — Text, "Template Name" |
| **Origin** | Created for the PDF generator POC (see `PdfGeneratorController`). |

## Key fields

| Field API name | Label | Type | Required | Purpose |
|---|---|---|---|---|
| `Target_SObject__c` | Target SObject API Name | Text(80) | Yes | API name of the SObject this template generates against (e.g., `Form__c`, `Account`, `Opportunity`). Drives the dynamic SOQL in `PdfTemplateService`. |
| `Active__c` | Active | Checkbox (default true) | No | If unchecked, the Generate PDF button using this template is hidden/disabled. Enforced in `PdfGeneratorController.doGenerate`. |
| `Default_Version__c` | Default Version | Lookup → `Template_Version__c` | No | Fallback version used when no `Template_Mapping__c` rule matches the source record. Delete constraint: SetNull. |
| `File_Naming_Pattern__c` | File Naming Pattern | Text(255) | No | Tokenized file name. Tokens like `{{Name}}`, `{{CreatedDate}}`, `{{Field_Api_Name__c}}` are resolved at generate time. Defaults to `<Template Name> - <Record Name>` if blank. |
| `Overwrite_Existing_File__c` | Overwrite Existing File | Checkbox (default false) | No | If true, regenerating supersedes the prior PDF (matched via `ContentVersion.Source_Template_Version__c`). If false, each generation creates a new file. |
| `Description__c` | Description | Long Text Area(3000) | No | Free-form admin notes. |

## Relationships

| Relationship | Field | Related object | Type | Cascade behavior |
|---|---|---|---|---|
| Lookup | `Default_Version__c` | `Template_Version__c` | Lookup | SetNull |
| Child (reverse) | `Versions` (`Template_Version__c.Document_Template__c`) | `Template_Version__c` | Master-Detail | Cascade delete |
| Child (reverse) | `Mappings` (`Template_Mapping__c.Document_Template__c`) | `Template_Mapping__c` | Master-Detail | Cascade delete |

## Sharing model

- **OWD:** Public Read/Write (internal); external sharing model also Read/Write.
- **History tracking:** Disabled.
- **Sharing rules:** None.
- **Apex sharing:** None. `PdfGeneratorController` and `PdfTemplateService` both declare `with sharing`.

## Validation rules

None.

## Triggers and Apex touching this object

No Apex triggers. Read/write happens through controllers:

- **`PdfGeneratorController`** (`@AuraEnabled`, `with sharing`):
  - `generateAndSave(templateId, recordId)` / `generateAndSaveByName(templateName, recordId)` — resolves the template (by Id or Name), enforces `Active__c`, picks a `Template_Version__c` via `Template_Mapping__c` rules (or `Default_Version__c`), renders the VF page `DocumentRender` to PDF, saves as a `ContentVersion`/`ContentDocumentLink` on the source record, optionally supersedes prior generations.
  - `resolveVersion(dt, recordId)` — orders `Template_Mapping__c` by `Priority__c ASC NULLS LAST`, evaluates `Record_Type_Developer_Name__c` + `Match_Field_Api_Name__c`/`Match_Operator__c`/`Match_Value__c`, falls back to `Default_Version__c`.
  - `computeFileName(dt, recordId)` — expands `{{token}}` placeholders in `File_Naming_Pattern__c` against the source record.
- **`PdfTemplateService`** — `build(templateVersionId, recordId)` reads the parent `Document_Template__c.Target_SObject__c` to drive SOQL.
- **`TemplateBuilderController`** — `getContext(templateVersionId)` reads parent `Document_Template__c.Name` and `Target_SObject__c` for the builder UI.
- **`DocumentRenderController`** — the VF controller for `/apex/DocumentRender`; receives `templateVersionId` + `recordId` via URL and delegates to `PdfTemplateService.build`.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

None.

## Constraints and gotchas

- `Target_SObject__c` is a free-text API name; `PdfTemplateService.escapeIdentifier` regex-validates it but does not check that the SObject exists at create time. A typo surfaces only at generate time as a `TemplateException`.
- `Active__c` is enforced in Apex, not via validation rule. Inserting/updating an inactive template is allowed; only the Generate action throws.
- `Default_Version__c` uses `deleteConstraint=SetNull` — deleting the referenced version blanks the default rather than blocking. Combined with no mapping rules this means a generate call fails with "No matching Template Version" until an admin reassigns.
- Standard list view: `All`.

## Related ADRs

None.
