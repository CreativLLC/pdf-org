---
title: PDF Template Builder
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs:
  - ../objects/Document_Template__c.md
  - ../objects/Template_Version__c.md
  - ../objects/Template_Mapping__c.md
  - ../objects/Form__c.md
  - ../objects/Signature__c.md
  - ../objects/ContentVersion.md
---

# `PDF Template Builder`

> Admins design reusable PDF document templates against any Salesforce object, then end users generate a fully merged PDF from any matching record with one click.

## Overview

The PDF Template Builder is a proof-of-concept document generation stack: an admin authors a layout (text, images, conditional rules, tables, merge tokens) once and binds it to a target SObject; afterwards anyone with access to that SObject can produce a rendered PDF from a record and have it saved back to Salesforce Files on that record. The stack is object-agnostic — the target SObject is configured per template rather than hardcoded — and supports multiple template variants chosen automatically based on record type or field values. `Form__c` and `Signature__c` exist as a sample target object pair so the builder has realistic, shaped data (including image-bearing children) to exercise.

## How it works

1. **Author a template.** An admin creates a [`Document_Template__c`](../objects/Document_Template__c.md), naming the target SObject (e.g., `Form__c`, `Account`, `Opportunity`) and a file-naming pattern with merge tokens. They then create one or more [`Template_Version__c`](../objects/Template_Version__c.md) child records. The layout body (page properties, row/column tree, text spans, merge tokens, tables, conditional rules) is stored as JSON on the version. Versions move through `Draft` → `Published` → `Archived`.
2. **Configure version selection rules.** For templates with multiple variants, admins add [`Template_Mapping__c`](../objects/Template_Mapping__c.md) rules. Each rule tests the source record's record type and/or a field value with an operator (`Equals`, `In`, `NotNull`, `Default`) and is ordered by priority. The parent template's `Default_Version__c` is the fallback when no rule matches.
3. **Generate a PDF.** A user invokes generation from a record (Id + template). The system enforces `Active__c`, picks a version via the mapping rules (lowest priority wins), and renders the version's JSON against the source record through dynamic SOQL that pulls only the fields referenced by the layout's merge tokens. Child records (e.g., the `Signatures` collection on a `Form__c`) and inline image references resolve to attached Salesforce Files, base64-embedded into the rendered output.
4. **Save the result.** The PDF is inserted as a `ContentVersion` linked to the source record. A custom field — `Source_Template_Version__c` on [`ContentVersion`](../objects/ContentVersion.md) — stamps which version produced the file so that, if the template is flagged `Overwrite_Existing_File__c`, regenerating supersedes the prior copy on the same record.
5. **Iterate on templates.** Editing a draft version through the builder UI saves the JSON back to the same record (with a preview against a sample record). When the JSON exceeds the 128 KB long-text cap, it transparently spills into a Salesforce File titled `definition.json` attached to the version — the renderer reads file-over-field automatically.

Underlying technical detail lives in the canonical object docs linked above (and in the supporting Apex: `PdfGeneratorController`, `PdfTemplateService`, `TemplateBuilderController`, `DocumentRenderController`).

## Acceptance signals

- The admin sees their `Document_Template__c` with at least one `Published` `Template_Version__c` child and (optionally) mapping rules.
- An end user clicking Generate from a target record produces a new `ContentVersion` attached to that record; the file name matches the template's `File_Naming_Pattern__c` with tokens resolved.
- The `Files` related list on the source record shows the generated PDF; opening it shows merged field values, conditionally-shown sections, and any embedded signature images for child rows whose `Signature_Type__c` matches the template's filter.
- Re-generating on a template flagged `Overwrite_Existing_File__c = true` replaces the prior file rather than adding a sibling; with the flag off, both files coexist.

## Known limitations

- **Target SObject is free text.** `Document_Template__c.Target_SObject__c` is validated by a regex (no Apex check that the SObject actually exists), so typos surface only at generate time as a `TemplateException`.
- **Match-field names are free text.** `Template_Mapping__c.Match_Field_Api_Name__c` is a plain text field; a typo silently never matches. There is no metadata-level picker.
- **Overwrite is keyed by version Id, not template Id.** If a mapping rule change causes a different `Template_Version__c` to be selected on the next generate, the prior file (stamped with the old version) is not superseded — the new PDF lands as a sibling.
- **Active status is enforced in Apex only.** Inserting/updating an inactive template is allowed at the data layer; only the Generate action throws.
- **Spillover JSON is keyed by file Title.** The 128 KB-overflow path looks for a `ContentVersion` titled exactly `definition.json` (case-sensitive) on the version record. Renaming the file silently breaks the template.
- **Image rendering picks the latest file unconditionally.** A `Signature__c`'s image is the most recently uploaded `ContentVersion` linked to it, with MIME type inferred from extension — uploading a non-image file produces a broken `<img>` in the rendered PDF.
- **`Status__c` gating on versions is policy, not enforced.** Apex does not block a mapping rule from pointing at a `Draft` version; the picker UI is expected to surface only `Published` rows, but Data Loader could create rules that select Drafts.
- The `In` operator on mapping rules splits its value on a literal comma with no escape handling, so commas in match values are not supported.

## Related tickets

None recorded at the engagement level; this feature represents the original POC baseline plus the smart-DOCX-import enhancements visible in the git history.
