# `sf-discover-document-profiles`

You are documenting every profile in this engagement. For each profile XML in `force-app/main/default/profiles/`, write or update `docs/security/profiles/<Profile_API_Name>.md` per the canonical-reference template, reflecting the profile's *current state* in source. Per [ADR-0013](../decisions/0013-engagement-security-documentation.md).

Uses **opus[1m]** because profile XML files can be large (thousands of lines for stock profiles with full object/field permission listings) and need to be cross-referenced against object metadata to identify non-default settings.

Runs in parallel with `document-security-overview` and `document-security-permission-sets`.

## Inputs

- `force-app/main/default/profiles/*.profile-meta.xml` (every profile to document)
- `force-app/main/default/objects/*/<Object>.object-meta.xml` (to identify the engagement's custom objects + standard objects with customizations)
- `force-app/main/default/customPermissions/*.customPermission-meta.xml` (for the "Custom Permissions granted" cross-reference)
- The template: `docs/.harness-templates/profile-doc.md`

## Tools

Read, Edit, Write, Glob, Grep. Read-only on `force-app/`; writes to `docs/security/profiles/`.

## Idempotency rule

Same as the other discover nodes — preserve docs whose frontmatter `last_updated_by` is non-`archon-*`.

## What counts as a "profile to document"

Every `.profile-meta.xml` file in the engagement's `force-app/main/default/profiles/`. Includes:

- Custom profiles created in this engagement.
- Customized stock profiles (e.g., Standard User with overrides).
- Stock profiles that have been retrieved alongside customizations.

If a profile XML exists in source, it gets a doc. The doc explains what's customized; for stock profiles with minimal customization, the doc will be short — that's fine.

## Task — per profile

For each `<Profile_API_Name>.profile-meta.xml`:

### Step 1: Read the XML

Parse the profile metadata. Key sections:

- `<userLicense>` and inferred from naming + `<custom>` (true = engagement-authored, false = stock)
- `<objectPermissions>` blocks — each has `<object>`, `<allowRead>`, `<allowCreate>`, `<allowEdit>`, `<allowDelete>`, `<viewAllRecords>`, `<modifyAllRecords>`
- `<fieldPermissions>` blocks — each has `<field>` (in `Object.Field` form), `<readable>`, `<editable>`
- `<applicationVisibilities>` — each has `<application>`, `<default>`, `<visible>`
- `<tabVisibilities>` — each has `<tab>`, `<visibility>` (DefaultOn / DefaultOff / Hidden)
- `<userPermissions>` — system permissions; each has `<name>`, `<enabled>`
- `<classAccesses>` — Apex class access; each has `<apexClass>`, `<enabled>`
- `<pageAccesses>` — VF page access; each has `<apexPage>`, `<enabled>`
- `<connectedAppAccess>` — Connected Apps; each has `<connectedApp>`, `<enabled>`
- `<customPermissions>` — Custom Permissions granted; each has `<name>`, `<enabled>`

### Step 2: Identify what's non-default

The profile XML lists every setting, including stock defaults. The doc should highlight what's NON-DEFAULT — that's the actionable information.

Heuristics for "non-default":

- **Object permissions**: a profile that has zero access to an object (all `allow*` are `false`) is skipped from the table. A profile that has standard access for a stock object is included but unannotated. Non-standard access (e.g., a custom object access) is fully detailed.
- **Field permissions**: ONLY include rows where `<readable>` is `false` OR `<editable>` is `false` for a field whose default is otherwise editable. Standard FLS is not enumerated.
- **Tab visibilities**: only call out tabs set to `Hidden` or `DefaultOff` if they're stock-`DefaultOn`. Skip rows where the visibility matches the tab's stock default.
- **System permissions**: only call out enabled permissions that are NOT stock for the profile's license tier (e.g., `ViewAllData`, `ModifyAllData`, `ManageUsers`, `Author Apex`, `Customize Application`). Stock-license permissions are not listed.
- **App / class / page / connected-app access**: list everything explicitly enabled.

### Step 3: Write `docs/security/profiles/<Profile_API_Name>.md`

Follow the canon template at `docs/.harness-templates/profile-doc.md` exactly. Required sections in order:

- **Frontmatter** (required keys, in this order): `title`, `audience: public`, `last_updated` (today), `last_updated_by` (`archon-discover-<run-id>` if `$ARCHON_RUN_ID` set; else `archon-discover`), `related_tickets: []`, `related_docs:` (relative paths — at minimum include `README.md` and `../sharing-model.md`).

- **`## Identity`** — REQUIRED. Two-column table per template: API name, Label, User license, License count (omit if unknown — write "_Not visible from source._"), Origin (Stock with customizations / Cloned from X / Custom — infer from `<custom>` + naming), Description (from XML `<description>` or "_Not set._").

- **`## Persona`** — REQUIRED. 1-2 sentence inferred persona per the template. The agent reads the profile name + object permissions and writes its best inference. Mark with `_(inferred)_` so engineers know to verify.

- **`## Object permissions`** — REQUIRED. Table per template. Standard objects with stock permissions: include row but no annotation. Custom objects + non-stock standard access: full detail in Notes column. If no custom-object access: write the placeholder.

- **`## Field-level security overrides`** — REQUIRED. Only non-default rows. If none: write `_No FLS overrides — uses default field visibility._`

- **`## App access`** — REQUIRED. List `<applicationVisibilities>` entries where `<visible>=true`. Mark the default app.

- **`## Tab settings`** — REQUIRED. Non-default rows only. If all defaults: placeholder.

- **`## System permissions of note`** — REQUIRED. Notable enabled system perms only.

- **`## Apex class access`** — REQUIRED. List `<classAccesses>` entries where `<enabled>=true`. If none: placeholder.

- **`## Visualforce page access`** — REQUIRED. Same as Apex classes.

- **`## Connected App access`** — REQUIRED. Same.

- **`## Typically assigned with`** — REQUIRED. The agent can't infer this from XML alone — write `_None known; permission sets are assigned ad-hoc._` unless the engagement's `engagement.yaml` or docs explicitly document profile-to-PS bundling.

- **`## Related decisions`** — REQUIRED. ADRs that govern this profile. If none: `_None._`

### Step 4: Also write `docs/security/profiles/README.md`

The subdirectory index. Required sections:

- **Frontmatter**.
- **`# Profiles — <Client Name>`** — H1.
- **Brief intro** — "one file per profile in `force-app/main/default/profiles/`."
- **`## Profile inventory`** — table with columns: Profile, Label, Origin (Custom / Stock-customized), User license, Doc.
- If no profiles exist in source: write `_This engagement has no profiles in source metadata. Either the org uses only stock Salesforce profiles (likely), or profiles haven't been retrieved into the SFDX project. To document stock profiles, retrieve them: \`sf project retrieve start -m Profile\`._`

## Cross-link discipline

- Link to permission sets that are typically bundled with this profile: `[`<PS_Name>`](../permission-sets/<PS_Name>.md)`.
- Link to objects this profile has access to where the doc adds engagement-specific context: `[`<Object>`](../../objects/<Object>.md)`.
- Link to ADRs: `[`<NNNN-slug>`](../../decisions/<NNNN-slug>.md)`.
- **DO NOT** write relative links to `force-app/` source files — they 404 on the rendered site. Use inline code or absolute GitHub URLs.

## Section-name + completeness enforcement

Before writing each profile file, verify your draft has every REQUIRED section header spelled exactly as listed above, in the listed order. Empty content within a section is OK with the documented `_None._` / `_No X._` placeholders; omitting the section is NOT.

## Output

```json
{
  "profiles_written": [
    "docs/security/profiles/System_Administrator.md",
    "docs/security/profiles/Standard_User.md",
    "docs/security/profiles/Sales_Manager_Custom.md"
  ],
  "profiles_preserved": [
    {
      "doc": "docs/security/profiles/Foo.md",
      "reason": "last_updated_by was 'engineer@firm.com' — preserved"
    }
  ],
  "profiles_failed": [],
  "readme_written": "docs/security/profiles/README.md",
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links_count": 0
  }
}
```
