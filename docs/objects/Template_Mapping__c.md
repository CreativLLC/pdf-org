---
title: "Template_Mapping__c"
audience: public
last_updated: 2026-05-15
last_updated_by: drew.smith@openwacca.com
related_tickets: []
related_docs:
  - Document_Template__c.md
  - Template_Version__c.md
---

# `Template_Mapping__c`

## Purpose

A rule that picks which [`Template_Version__c`](Template_Version__c.md) renders for a given source record. Each mapping belongs to a [`Document_Template__c`](Document_Template__c.md) and tests the source record's record type and/or a configurable field. `PdfGeneratorController.resolveVersion` walks the mapping rules ordered by `Priority__c` (lowest wins) and falls back to the parent's `Default_Version__c` when none match. This is what lets a single Document Template handle multiple revisions or variants of a form without forcing the user to pick a version manually.

## Type and origin

| | |
|---|---|
| **API name** | `Template_Mapping__c` |
| **Type** | Custom (`__c`) |
| **Label (singular / plural)** | `Template Mapping` / `Template Mappings` |
| **Name field** | Auto Number `TM-{0000}`, "Mapping Number" |
| **Origin** | Created for the PDF generator POC. |

## Key fields

| Field API name | Label | Type | Required | Purpose |
|---|---|---|---|---|
| `Document_Template__c` | Document Template | Master-Detail → `Document_Template__c` | Yes | Parent template. Mappings are scoped to one template. |
| `Template_Version__c` | Template Version | Lookup → `Template_Version__c`, deleteConstraint=Restrict | Yes | The version selected when this rule matches. |
| `Priority__c` | Priority | Number(3,0), default `100` | Yes | Lowest priority wins among matching rules. Convention: `10` = specific recordType+field, `50` = recordType only, `100` = field only, `999` = catch-all default. |
| `Record_Type_Developer_Name__c` | Record Type Developer Name | Text(80) | No | Source record's `RecordType.DeveloperName` must equal this. Blank = any record type. |
| `Match_Field_Api_Name__c` | Match Field API Name | Text(80) | No | API name of a field on the source record (e.g., `Revision_Number__c`) to test against `Match_Value__c`. Blank with `Match_Operator__c = Default` makes this the catch-all. |
| `Match_Operator__c` | Match Operator | Picklist (restricted) | Yes | `Equals` (default), `In` (comma-separated `Match_Value__c`), `NotNull`, `Default` (always matches). |
| `Match_Value__c` | Match Value | Text(255) | No | Value to compare against. For `In`, comma-separated. Ignored for `NotNull` and `Default`. |

## Relationships

| Relationship | Field | Related object | Type | Cascade behavior |
|---|---|---|---|---|
| Parent | `Document_Template__c` | `Document_Template__c` | Master-Detail | Cascade delete |
| Lookup | `Template_Version__c` | `Template_Version__c` | Lookup, deleteConstraint=Restrict | Cannot delete the version while a mapping points at it |

## Sharing model

- **OWD:** Controlled by Parent (`Document_Template__c`).
- **History tracking:** Disabled.
- **Sharing rules:** None.

## Validation rules

None — operator/value coherence is enforced in Apex (`PdfGeneratorController.matches`) rather than declaratively.

## Triggers and Apex touching this object

No Apex triggers.

- **`PdfGeneratorController.resolveVersion`** is the only reader:
  1. SOQL: `SELECT Id, Template_Version__c, Record_Type_Developer_Name__c, Match_Field_Api_Name__c, Match_Operator__c, Match_Value__c, Priority__c FROM Template_Mapping__c WHERE Document_Template__c = :dt.Id ORDER BY Priority__c ASC NULLS LAST`.
  2. For each rule, evaluates record-type filter (when set), then operator:
     - `Default` → always match.
     - `Equals` → `String.valueOf(row.get(field)) == Match_Value__c`.
     - `In` → split `Match_Value__c` on `,` and test membership.
     - `NotNull` → `String.isNotBlank(value)`.
  3. Returns the first match's `Template_Version__c.Id`; on no match, returns `dt.Default_Version__c`.

## Flows touching this object

None.

## Integrations referencing this object

None.

## Record types

None.

## Constraints and gotchas

- **Priority semantics rely on convention**, not validation. Two rules can share a priority; SOQL `ORDER BY Priority__c ASC NULLS LAST` would then return them in undefined order. Keep priorities unique within a template.
- **`Match_Field_Api_Name__c` is a free-text field name**, not a metadata picklist. A typo silently never matches; there is no compile-time check.
- **`deleteConstraint=Restrict` to `Template_Version__c`**: archive an old version, don't delete it, if any mapping still references it.
- The `In` operator splits on a literal comma without escape handling — values containing `,` can't be used.

## Related ADRs

None.
