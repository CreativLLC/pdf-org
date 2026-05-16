# Plan — sf-metadata-change (GRIM-51, family 1/2)

**Sub-type:** `create-field` (precedence wins over the `modify-page-layout` aspect)
**Scope:** small
**Object:** [`Document_Template__c`](../../../docs/objects/Document_Template__c.md)

## What this family does

Create a `Reviewer__c` Lookup(User) field on `Document_Template__c`. The associated page-layout edit (AC #2) is blocked unless we first retrieve the existing layout/flexipage — surfaced at the pre-execute gate.

## File changes

| Path | Op | Notes |
|---|---|---|
| `force-app/main/default/objects/Document_Template__c/fields/Reviewer__c.field-meta.xml` | add | Lookup → `User`. `relationshipLabel: Reviewer`, `relationshipName: Reviewed_Templates`. Not required. No delete-cascade (Lookup default `SetNull`). Description: "User who reviewed this template before promotion to production." |

## Layout placement (AC #2)

**Blocked by the smoke-validate mismatch:** there is no Document_Template__c layout file in `force-app/main/default/objects/Document_Template__c/layouts/` and no flexipage in `force-app/main/default/flexipages/`. We can't deploy a layout/flexipage edit without first retrieving the existing definition.

Options to resolve at the gate:

1. **Retrieve first, edit, deploy** — `sf project retrieve start --metadata Layout:Document_Template__c-Document Template Layout` then add `Reviewer__c` to the relevant section. Surface the retrieved file in this same commit.
2. **Defer the layout edit** — ship the field in this run; track AC #2 as a follow-up (or do it via Setup clicks, leaving the layout still un-tracked).
3. **Use Lightning App Builder via Setup** — if the org uses a Lightning Record Page for Document_Template__c, the field can be placed there too (and that flexipage similarly needs retrieving first).

Recommendation: **option (1)** — retrieve the layout, add the field, deploy. Keeps everything in source. If the engineer prefers option (2), the layout placement becomes a separate ticket.

## Field-meta.xml content (final)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Reviewer__c</fullName>
    <description>User who reviewed this template before promotion to production. Populated by PDF authors during the review handoff workflow.</description>
    <externalId>false</externalId>
    <label>Reviewer</label>
    <referenceTo>User</referenceTo>
    <relationshipLabel>Reviewed Templates</relationshipLabel>
    <relationshipName>Reviewed_Templates</relationshipName>
    <required>false</required>
    <trackTrending>false</trackTrending>
    <type>Lookup</type>
</CustomField>
```

## Documentation outputs (post-validate)

Per ADR-0010, current-state only:
- `docs/objects/Document_Template__c.md` — add `Reviewer__c` to the Key fields table; note the FLS posture decision (the permission family records the actual grants).

## Cross-family handoff

The permission family runs next per the orchestrator's sequence. The FLS grants depend on this field existing in the org (and in source), so the dependency ordering is right.

## Risk surface

1. **No layout in source** — see "Layout placement" above.
2. **No public API change** — additive Lookup field.
3. **No governor exposure** — declarative-only.
4. **`Reviewer__c` relationship name** — `Reviewed_Templates` chosen to avoid collision with any existing User-side relationship; verify in the org doesn't already have one.

## Out-of-scope AC

- AC #2 (page layout) — pending the layout-retrieval decision at the pre-execute gate.
- AC #3, #4 (FLS) — handled by the sibling sf-permission-change family.
