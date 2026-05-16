# `sf-discover-document-security-overview`

You are producing the engagement's top-level security documentation: the consolidated sharing-model doc plus the small per-artifact-type files (custom permissions, public groups + queues, Apex sharing, optional permission set groups), and the section landing page (`docs/security/README.md`). Per [ADR-0013](../decisions/0013-engagement-security-documentation.md).

This runs in parallel with `document-security-profiles` and `document-security-permission-sets`. Together those three nodes produce the entire `docs/security/` category.

## Inputs

- The engagement's `force-app/main/default/` directory (read-only):
  - `objects/*/`-`.object-meta.xml` for OWD (`<sharingModel>`) and external sharing model (`<externalSharingModel>`)
  - `sharingRules/*.sharingRules-meta.xml` for criteria-based and ownership-based sharing rules
  - `customPermissions/*.customPermission-meta.xml`
  - `groups/*.group-meta.xml` (Public Groups)
  - `queues/*.queue-meta.xml` (or queues declared in `groups/` depending on metadata format)
  - `permissionsetgroups/*.permissionsetgroup-meta.xml` (if any)
  - `restrictionRules/*.restrictionRule-meta.xml` (if any)
  - `classes/*.cls` — grep for `__Share` token + `EventBus.publish` + `Database.setSavepoint` usage related to programmatic sharing
- `$classify-significance.output.objects` for the rolled-up OWD table
- The templates:
  - `docs/.harness-templates/sharing-model.md`

## Tools

Read, Edit, Write, Glob, Grep, Bash. Read-only on `force-app/`; writes to `docs/security/`.

## Idempotency rule

For each file you're about to write:

1. If `docs/security/<file>.md` exists, read its frontmatter `last_updated_by`.
2. If it does NOT start with `archon-`, the doc was hand-edited — skip; log as `preserved_human_edits`.
3. Otherwise, (re)generate.

## Files to produce

### 1. `docs/security/README.md` — the section landing page

A short index that orients readers. Required sections (REQUIRED, in order):

- **Frontmatter**: `title: Security`, `audience: public`, `last_updated`, `last_updated_by`, `related_tickets: []`, `related_docs: [../index.md, sharing-model.md]`.
- **`# Security — <Client Name>`** — H1 matches the engagement.
- **Brief intro** — one paragraph: "this directory contains the consolidated security and access-control posture of the org, auto-generated from metadata by `sf-discover-document-security-*` workflows per ADR-0013."
- **`## What's in this section`** — bulleted list of the files + subdirectories with one-line descriptions, in this order:
  - [`sharing-model.md`](./sharing-model.md) — Org-Wide Defaults, sharing rules, Apex sharing, implicit sharing, Restriction Rules summary.
  - [`custom-permissions.md`](./custom-permissions.md) — Custom Permissions + where they're checked in Apex / Flow.
  - [`public-groups-and-queues.md`](./public-groups-and-queues.md) — Public Groups + Queues + their purposes.
  - [`apex-sharing.md`](./apex-sharing.md) — Programmatic sharing in Apex (`__Share` records, `Database.runAs` boundaries).
  - [`permission-set-groups.md`](./permission-set-groups.md) — *only include this row if any PSGs exist.*
  - [`profiles/`](./profiles/) — One file per profile in this engagement.
  - [`permission-sets/`](./permission-sets/) — One file per permission set.

### 2. `docs/security/sharing-model.md` — consolidated sharing posture

Follow the canon template at `docs/.harness-templates/sharing-model.md`. Required sections per the template, in order:

- **Frontmatter**.
- **`## Org-wide defaults (OWD)`** — REQUIRED. Aggregate OWD by reading every `force-app/main/default/objects/<Object>/<Object>.object-meta.xml` and extracting `<sharingModel>` + `<externalSharingModel>`. Build the table per template shape. Note objects whose OWD is "Controlled by Parent" — point at the parent.
- **`## Sharing rules`** — REQUIRED. Iterate `force-app/main/default/sharingRules/*.sharingRules-meta.xml`. For each, list the rules. If empty: write `_None — this engagement relies on OWD + role hierarchy + Apex sharing only._`
- **`## Apex (programmatic) sharing`** — REQUIRED. Grep classes for `__Share` (e.g., `Renewal__Share`, `Account__Share`). For each match, identify the class + method + object being shared. If none: `_None — all sharing is declarative._`
- **`## Implicit sharing notes`** — REQUIRED. Document Standard SF implicit sharing relevant to this engagement (Account → Contact/Opportunity/Case). If only standard applies: write the placeholder string per template.
- **`## Restriction Rules`** — REQUIRED. Iterate `force-app/main/default/restrictionRules/*.restrictionRule-meta.xml`. If none: `_None._`
- **`## Role hierarchy notes`** — REQUIRED. High-level. You may not be able to read the role hierarchy in detail from metadata alone; if so, write `_Engagement-specific role hierarchy details not visible from source metadata; consult Setup → Roles for the full tree._`
- **`## Custom Permissions usage map`** — REQUIRED. For each Custom Permission, enumerate which profiles / PSs grant it. If none: write the placeholder.
- **`## Public Groups and Queues`** — REQUIRED. Pointer to `public-groups-and-queues.md` + a 2-3 line summary of any groups used in sharing rules.
- **`## Why this posture (engagement narrative)`** — REQUIRED. Stub with `_TODO: engineer to author. The auto-generator captured the facts above but cannot infer the WHY. Add a 2-4 paragraph explanation of the business reasoning behind the OWD choices, the existence of each sharing rule, and any deferred/rejected alternatives. Link to relevant ADRs in [../decisions/](../decisions/)._`
- **`## Related decisions`** — REQUIRED. List ADRs that touch sharing/security. If none: `_None._`

### 3. `docs/security/custom-permissions.md`

Single file enumerating every Custom Permission. Required sections:

- **Frontmatter**.
- **`# Custom Permissions`** — H1.
- **Brief intro** — what Custom Permissions are (feature-flag-style entitlements checked from Apex via `FeatureManagement.checkPermission(...)` or from Flow).
- **Per-permission entries** — for each `force-app/main/default/customPermissions/<Name>.customPermission-meta.xml`:

```markdown
## `<Permission_Name>`

| | |
|---|---|
| **Label** | <from XML> |
| **Description** | <from XML, or "_Not set._"> |
| **Required permissions** | <connected_app, if any> |

**Checked in:**
- `<ClassName>.<methodName>` — <one-line context>
- `<Flow_API_Name>` — <one-line context>

**Granted by:**
- Profile: `<Profile_Name>`
- Permission Set: `<PS_Name>`
```

  Use Grep to find `FeatureManagement.checkPermission` and `PermissionsCustomPermissionsAccess` references in Apex; cross-reference profile + PS XML to find which grant each permission.

- If no Custom Permissions exist: still produce the file with H1 + intro + one line: `_None — this engagement does not use Custom Permissions._`

### 4. `docs/security/public-groups-and-queues.md`

Required sections:

- **Frontmatter**.
- **`# Public Groups and Queues`** — H1.
- **`## Public Groups`** — table of every group in `force-app/main/default/groups/`. Columns: Group, Label, Includes (Users / Roles / Roles+Subordinates / Other Groups). If a group is used in a sharing rule, note it in a "Used in" column.
- **`## Queues`** — table of every queue. Columns: Queue, Label, SObject(s) it queues, Notes (e.g., "Tier-2 case routing").
- If neither exists: produce the file with H1 + a one-line "_No engagement-specific groups or queues._"

### 5. `docs/security/apex-sharing.md`

Required sections:

- **Frontmatter**.
- **`# Apex (programmatic) sharing`** — H1.
- **Brief intro** — what Apex programmatic sharing is.
- **`## Where it's used`** — table per row: `Apex class`, `Method`, `Object shared`, `Access level`, `Triggered by`.
- **`## Patterns + invariants`** — engineer-authored notes about the engagement's Apex sharing conventions. Stub with `_TODO: engineer to author. Likely conventions: are shares created in triggers? In scheduled jobs? Are they ever deleted (e.g., on owner-change)? Reference patterns from harness/patterns/ if applicable._`
- If no Apex sharing exists: H1 + intro + `_None — all sharing is declarative._`

### 6. `docs/security/permission-set-groups.md` — *only if any PSGs exist*

Required sections:

- **Frontmatter**.
- **`# Permission Set Groups`** — H1.
- **Per-group entries** — for each `force-app/main/default/permissionsetgroups/<Name>.permissionsetgroup-meta.xml`:

```markdown
## `<PSG_Name>`

**Description**: <from XML or "_Not set._">

**Composed permission sets:**
- [`<PS1>`](./permission-sets/<PS1>.md) — <PS1's purpose, one line>
- [`<PS2>`](./permission-sets/<PS2>.md) — <PS2's purpose, one line>

**Typical assignment**: <who gets this group in this engagement, if inferrable; else "_Not documented._">
```

If no PSGs exist: do NOT create this file. Update README.md to omit the row.

## Cross-link discipline

- All inter-doc links inside `docs/security/` use relative paths.
- Links from `docs/security/*` to `docs/objects/*` use `../objects/<Object>.md`.
- Links to ADRs use `../decisions/<NNNN-slug>.md`.
- **DO NOT** write relative links to files in `force-app/` from these docs — those 404 on the rendered site. If you must reference an Apex class file, use inline code (`` `Foo.cls` ``) or an absolute GitHub URL built from `mkdocs.yml: repo_url:`.

## State, not history (per ADR-0010)

Describe what each artifact GRANTS today. Don't write "as of GRIM-N, the Sales rule was tightened." Tightening is in `git log`; the current rule is what the table shows.

## Output

```json
{
  "files_written": [
    "docs/security/README.md",
    "docs/security/sharing-model.md",
    "docs/security/custom-permissions.md",
    "docs/security/public-groups-and-queues.md",
    "docs/security/apex-sharing.md",
    "docs/security/permission-set-groups.md"
  ],
  "files_preserved": [],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links_count": 0
  },
  "counts": {
    "objects_with_owd_documented": 0,
    "sharing_rules": 0,
    "apex_sharing_classes": 0,
    "custom_permissions": 0,
    "public_groups": 0,
    "queues": 0,
    "permission_set_groups": 0,
    "restriction_rules": 0
  }
}
```

Broken cross-link counts to the `permission-sets/` and `profiles/` subdirectories are expected during this run (the parallel sibling nodes will populate those); the `update-index` node verifies resolution after all security nodes finish.
