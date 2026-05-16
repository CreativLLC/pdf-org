# Plan — sf-permission-change (GRIM-51, family 2/2)

**Sub-type as classified:** `modify-profile` (classifier saw "everyone else" sweep).
**Sub-type as planned:** `modify-permission-set` — see "Scope discovery" below.
**Scope:** small (1 file actually changed, not the 30+ the classifier feared).

## Scope discovery (from smoke-validate)

The ticket's AC #3 and #4 imply two operations:

| AC | Operation |
|---|---|
| #3 | Grant the "PDF Author PS" read+edit on `Document_Template__c.Reviewer__c`. |
| #4 | Read-only for everyone else. |

A read of `force-app/main/default/profiles/` and `force-app/main/default/permissionsets/` shows:

- **Zero profiles** in source grant any `<objectPermissions>` on `Document_Template__c`. Every user that can see Document Template records today does so via permission set assignment, not via their base profile.
- **One permission set** in source grants object access: **`PdfGeneratorAdmin`** (full CRUD via `<objectPermissions>`, plus `<readable>` and `<editable>` FLS on every other custom field on the object).
- The other 6 PSes (`Manage_Billing`, `View_Invoices`, `System_Admin_Extra_Perms`, `MFA_Required`, `TEST`, `sfdcInternalInt__sfdc_nc_constraints_engine_deploy`) grant zero on `Document_Template__c`.

**Implication:** AC #4 ("read-only for everyone else") is **vacuously satisfied** by the current access model. Without object-level read on Document Template, no user can navigate to a record at all — FLS on a field of that record is unreachable. Adding explicit `<readable>true/editable>false` on Reviewer__c to every profile and every non-PdfGeneratorAdmin PS would be **30+ files of noise** that grants nothing in practice.

The minimal correct change is to grant the one PS that has object access — `PdfGeneratorAdmin` — read+edit on `Reviewer__c`. Match the existing pattern (every other Document_Template__c field has the same shape there).

## "PDF Author PS" → `PdfGeneratorAdmin`

The ticket says "PDF Author PS"; no PS by that literal name exists. Best fit: `PdfGeneratorAdmin`. Surfaced at the gate for engineer confirmation. If the engineer wants a brand-new "PDF Author" PS created, that's a separate scope (and a different sub-type — `create-permission-set`).

## File changes (proposed)

| Path | Op | Notes |
|---|---|---|
| `force-app/main/default/permissionsets/PdfGeneratorAdmin.permissionset-meta.xml` | modify | Add one `<fieldPermissions>` block for `Document_Template__c.Reviewer__c` with `<readable>true</readable>` + `<editable>true</editable>`. Insert in API-name-alphabetical position (matching the rest of the file). |

## Blast radius

- `files_changed`: 1
- `added_count`: 1 field permission entry
- `removed_count`: 0
- `removes_access`: false (purely additive)
- `narrows_access`: n/a (not a sharing rule)
- `owd_direction`: n/a
- `affects_admin`: false (Admin profile is unchanged; admin gets access via `ViewAllData` system permission, not via Document_Template__c grants)
- `affects_critical_object`: false

## Documentation outputs

- `docs/security/permission-sets/PdfGeneratorAdmin.md` — add Reviewer__c row to the field-level security table; update last_updated.
- `docs/objects/Document_Template__c.md` was already updated by the metadata family with a forward-reference to the PS doc — confirm that reference still resolves after this family's edits.

## Risk surface

- Zero. Additive FLS on a field that already exists in the org. Aligns with the engagement's documented security posture (PDF authoring lives in `PdfGeneratorAdmin`).

## What this plan does NOT do

- Does NOT modify any of the 25 profiles. The literal AC #4 reading was "PDF authoring posture isn't governed by profiles in this engagement; profiles are minimum-access (per `Minimum Access - Salesforce` and similar)."
- Does NOT modify the other 6 PSes — they don't grant `Document_Template__c` object access, so FLS on its fields is unreachable for their users.
- Does NOT create a new "PDF Author" PS — if that's wanted, a separate ticket is the right venue.
