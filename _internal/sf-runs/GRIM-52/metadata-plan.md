# Plan — sf-metadata-change (GRIM-52, family 1/3)

**Sub-type:** `create-picklist-value` (precedence; secondary: `create-field`)
**Scope:** small
**Touches FLS:** true (new field on `Template_Mapping__c`)

## Schema discovery

| Question | Finding |
|---|---|
| Where is the "PDF template's status"? | `Template_Version__c.Status__c` (Picklist: Draft / Published / Archived; required). `Document_Template__c` has no Status field in source. |
| Does "Approved" already exist? | **No.** Status__c values are Draft, Published, Archived. AC #2 implies adding it. |
| Where does the approval timestamp live? | **No existing field.** Best fit: `Template_Mapping__c.Approved_At__c` (DateTime). Reasoning: AC says "stamp on related records that haven't been stamped yet" — mappings reference a specific `Template_Version__c` via the `Template_Version__c` lookup, so mapping records ARE the natural "related records" when a version becomes Approved. (Alternative reading at the gate.) |

## Proposed file changes

| Path | Op | Notes |
|---|---|---|
| `force-app/main/default/objects/Template_Version__c/fields/Status__c.field-meta.xml` | modify | Append `Approved` value to the existing picklist (after `Archived`). Additive. |
| `force-app/main/default/objects/Template_Mapping__c/fields/Approved_At__c.field-meta.xml` | add | New DateTime field. `description`: "Timestamp when the parent Template_Version__c first transitioned to Status=Approved. Stamped by TemplateVersionApprovalHandler (invocable from the Approval Flow). Never overwritten once set." Not required. No formula. |

## Cross-family handoff

- The next family (sf-apex-change) will write `TemplateVersionApprovalHandler.cls` whose @InvocableMethod accepts a list of `Template_Version__c` IDs and stamps `Approved_At__c` on every related `Template_Mapping__c` where `Template_Version__c = :id AND Approved_At__c = NULL`.
- The third family (sf-flow-change) will create the record-triggered Flow on `Template_Version__c` that calls the invocable when `Status__c` transitions to `Approved`.
- FLS posture for the new field: deferred to a follow-up (no sf-permission-change in this run). `PdfGeneratorAdmin` PS will need editing in a separate ticket — same scope-discovery insight as GRIM-51: it's the only PS with object access to `Template_Mapping__c`.

## Alternative readings (surface at the gate)

1. **Timestamp on `Template_Version__c` itself** (the version that got approved, not its mappings). Simpler, no invocable needed (a record-action in Flow could do it). But AC #1 explicitly demands "Invocable @InvocableMethod" — meaning bulk-update across multiple records — so option A (on Template_Mapping__c) better matches the AC.
2. **Timestamp on `Document_Template__c`** (the grandparent). Doesn't fit "related records that haven't been stamped yet" because there's only one parent per version — no bulk.
3. **Both Template_Version__c and Template_Mapping__c.** Belt-and-suspenders. Adds a field unrelated to the invocable's purpose.

## Risk

- Adding `Approved` to a `required restricted` picklist is additive: no existing data breaks; no existing automation breaks.
- New `Approved_At__c` field is invisible to all profiles/PSes until granted (default-hidden FLS). PdfGeneratorAdmin currently has read+edit on all other Template_Mapping__c fields; for parity, the Apex's stamping action will work because Apex runs in system context. End users won't see the field until a follow-up sf-permission-change grants it.
