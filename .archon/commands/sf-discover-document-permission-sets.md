# `sf-discover-document-permission-sets`

You are documenting every permission set in this engagement. For each PS XML in `force-app/main/default/permissionsets/`, write or update `docs/security/permission-sets/<PS_API_Name>.md` per the canonical-reference template. Per [ADR-0013](../decisions/0013-engagement-security-documentation.md).

Permission sets are **additive** — they grant permissions ON TOP OF a user's base profile. This doc focuses on what each PS adds, not on what the base profile already gives.

Uses **opus[1m]**. Runs in parallel with `document-security-overview` and `document-security-profiles`.

## Inputs

- `force-app/main/default/permissionsets/*.permissionset-meta.xml`
- `force-app/main/default/permissionsetgroups/*.permissionsetgroup-meta.xml` (to identify PSG membership)
- `force-app/main/default/objects/*/<Object>.object-meta.xml` (cross-reference)
- `force-app/main/default/customPermissions/*.customPermission-meta.xml`
- The template: `docs/.harness-templates/permission-set-doc.md`

## Tools

Read, Edit, Write, Glob, Grep. Read-only on `force-app/`; writes to `docs/security/permission-sets/`.

## Idempotency rule

Standard — preserve docs whose `last_updated_by` is non-`archon-*`.

## Task — per permission set

For each `<PS_API_Name>.permissionset-meta.xml`:

### Step 1: Read the XML

Permission set XML has similar structure to profiles but the semantics are additive. Sections:

- `<license>` if any
- `<hasActivationRequired>` — is this PS gated by a permission set license?
- `<description>`
- `<objectPermissions>` — additive object access
- `<fieldPermissions>` — additive field access
- `<applicationVisibilities>` — apps this PS makes visible
- `<tabSettings>` — tabs this PS adjusts visibility for
- `<userPermissions>` — system permissions this PS adds
- `<classAccesses>`, `<pageAccesses>`, `<connectedAppAccesses>` — same as profiles
- `<customPermissions>` — Custom Permissions this PS grants

### Step 2: Identify PSG membership

For each permission set group in `force-app/main/default/permissionsetgroups/`, check whether this PS is listed in `<permissionSets>`. If so, record the PSG names — they go in the doc's "Permission Set Group membership" field.

### Step 3: Write `docs/security/permission-sets/<PS_API_Name>.md`

Follow the canon template at `docs/.harness-templates/permission-set-doc.md`. Required sections in order:

- **Frontmatter** — required keys: `title`, `audience: public`, `last_updated`, `last_updated_by`, `related_tickets: []`, `related_docs: [README.md, ../sharing-model.md]` (plus links to PSGs and dependent profiles if known).

- **`## Identity`** — REQUIRED. Per template: API name, Label, License, PSG membership, Origin, Description.

- **`## Purpose`** — REQUIRED. 1-2 sentence inferred purpose. Mark with `_(inferred)_` so engineers know to verify on re-run.

- **`## Object permissions added`** — REQUIRED. Table per template. Each row is an object this PS grants access to. If the PS grants no object permissions: placeholder.

- **`## Field-level security added`** — REQUIRED. Each row is a field this PS makes accessible. If none: placeholder.

- **`## App access added`** — REQUIRED. List apps. If none: placeholder.

- **`## Tab settings overrides`** — REQUIRED. Non-default rows. If none: placeholder.

- **`## System permissions added`** — REQUIRED. List notable system permissions this PS enables. If none: placeholder.

- **`## Custom Permissions granted`** — REQUIRED. Iterate `<customPermissions>` entries with `<enabled>=true`. For each, link to the entry in `../custom-permissions.md` and describe what it gates if known (grep Apex for `FeatureManagement.checkPermission('<name>')`).

- **`## Apex class access added`** — REQUIRED. List.

- **`## Visualforce page access added`** — REQUIRED. List.

- **`## Connected App access added`** — REQUIRED. List.

- **`## Typical assignment pattern`** — REQUIRED. The agent infers from name + PSG membership. If unclear: `_Assignment pattern not documented; check Setup or the engagement's onboarding runbook._`

- **`## Related decisions`** — REQUIRED. ADRs that govern this PS. If none: `_None._`

### Step 4: Also write `docs/security/permission-sets/README.md`

The subdirectory index. Required sections:

- **Frontmatter**.
- **`# Permission Sets — <Client Name>`** — H1.
- **Brief intro** — what permission sets are (additive grants on top of profiles).
- **`## Permission set inventory`** — table with columns: Permission Set, Label, License, PSG membership, Doc.
- **`## Permission Set Groups`** — *if any exist*: short list of PSGs with their composed PSs. Link to `../permission-set-groups.md` for the full PSG section.
- If no permission sets exist in source: write `_This engagement has no engagement-specific permission sets. Stock Salesforce permission sets (Sales User, Service Cloud User, etc.) may still be in use; those are not documented here._`

## Cross-link discipline

- Link to profiles that typically include this PS: `[`<Profile_Name>`](../profiles/<Profile_Name>.md)`.
- Link to objects: `[`<Object>`](../../objects/<Object>.md)`.
- Link to ADRs: `[`<NNNN-slug>`](../../decisions/<NNNN-slug>.md)`.
- Link to PSGs: `[`<PSG_Name>`](../permission-set-groups.md#<psg-slug>)`.
- **DO NOT** write relative links to `force-app/` source files.

## Section-name + completeness enforcement

Before writing each PS file, verify your draft has every REQUIRED section header spelled exactly as listed above. Empty content via the documented placeholders is OK; omitting a section is NOT.

## Output

```json
{
  "permission_sets_written": [
    "docs/security/permission-sets/Renewal_Manager_Permissions.md",
    "docs/security/permission-sets/PDF_Template_Author.md"
  ],
  "permission_sets_preserved": [],
  "permission_sets_failed": [],
  "readme_written": "docs/security/permission-sets/README.md",
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links_count": 0
  }
}
```
