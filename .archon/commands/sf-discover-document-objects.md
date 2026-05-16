# `sf-discover-document-objects`

You are documenting every significant Salesforce object in this engagement. For each object in `$classify-significance.output.objects`, write or update `docs/objects/<ObjectAPIName>.md` per the canonical-reference template, reflecting the object's *current state* in `force-app/main/default/objects/<Object>/`.

This node uses **opus[1m]** because the context demands matter: each object's doc references the object's fields (potentially dozens), validation rules, triggers, handler classes, and referenced Flows. You iterate the object list serially within one agent; parallelism happens across the three category nodes (objects / flows / integrations), not within them.

## Inputs

- `$classify-significance.output.objects` — array of significant-object descriptors, each with API name, file path, field count, trigger files, referencing Apex classes, referencing Flows.
- The engagement's `force-app/main/default/` directory (read-only).
- The template: `docs/.harness-templates/object-doc.md`.

## Tools

Read, Edit, Write, Glob, Grep. Read-only on `force-app/`; writes to `docs/objects/`.

## Idempotency rule (per ADR-0011)

For each object you're about to document:

1. Check whether `docs/objects/<Object>.md` already exists.
2. If it does, read its frontmatter `last_updated_by` value.
3. If the value does NOT start with `archon-` (e.g., it's a human email or `harness-init`), the doc was hand-edited — **skip this object**, log it as `preserved_human_edits`.
4. If the value starts with `archon-` OR the doc doesn't exist, proceed to (re)generate.

## Task — per significant object

For each object in the input list:

1. **Read the metadata.** Open the directory `force-app/main/default/objects/<Object>/`. Read:
   - `<Object>.object-meta.xml` (label, plural label, sharing model, history tracking, etc.)
   - `fields/*.field-meta.xml` for each field (type, length, required, description, formula)
   - `validationRules/*.validationRule-meta.xml` for each (errorConditionFormula, errorMessage, active)
   - `recordTypes/*.recordType-meta.xml` for each (label, picklist filters)
   - `listViews/*.listView-meta.xml` for major saved lists
   - `webLinks/*.webLink-meta.xml` for custom buttons

2. **Read the Apex.** For each `apex_classes_referencing` entry:
   - Read `force-app/main/default/classes/<Class>.cls`.
   - Identify what methods touch this object's SOQL/DML.
   - For trigger files: identify event handlers (before insert, after update, etc.) and the handler class they dispatch to.

3. **Read the Flows.** For each `flows_referencing` entry: open `force-app/main/default/flows/<Flow>.flow-meta.xml`. Identify the trigger type and what the Flow does to this object.

4. **Write `docs/objects/<Object>.md`** following the canonical template at `docs/.harness-templates/object-doc.md`. The section names and order below are **non-negotiable** — they match the canon template exactly and other workflows (link validation, future drift checks, AI-agent retrieval) depend on them. **Do not invent alternate section names. Do not omit required sections. Do not reorder.**

   - **Frontmatter** (required keys, in this order): `title`, `audience: public`, `last_updated` (today, YYYY-MM-DD), `last_updated_by` (`archon-discover-<run-id>` if `$ARCHON_RUN_ID` set; else `archon-discover`), `related_tickets: []`, `related_docs:` (list the flow/integration/feature/decision docs you cross-reference; relative paths from `docs/objects/`).

   - **`## Purpose`** — REQUIRED. 2–4 sentences explaining what the object represents in the business domain and its primary purpose. Pull from the object's label and field semantics. Do NOT just restate the API name. (Not "Overview" — `## Purpose` matches canon.)

   - **`## Type and origin`** — REQUIRED. Two-column key-value table per canon template: API name, Type (Standard / Custom (`__c`) / Custom Metadata (`__mdt`) / External / Big Object / Platform Event (`__e`)), Label (singular / plural), Origin (Out-of-box / Created in `<JIRA-KEY>` / Inherited from `<package>`).

   - **`## Key fields`** — REQUIRED. Table of significant fields. Columns per canon: `Field API name`, `Type`, `Required`, `FLS posture`, `Purpose`. Cover fields material to understanding or working with the object — not every field. (Not "Schema" — `## Key fields` matches canon.)

   - **`## Relationships`** — REQUIRED. Table per canon: `Relationship` (Parent/Child), `Field`, `Related object`, `Type` (Lookup/Master-Detail), `Cascade behavior` (Restrict/Cascade/Set Null). If the object has no relationships, write the table header followed by a single row `| — | — | — | — | — |` and a one-line note "_No parent or child relationships._" — do NOT omit the section.

   - **`## Sharing model`** — REQUIRED. Pulled from `<sharingModel>` in the object-meta. Cover OWD, sharing rules, Apex sharing, implicit sharing if relevant.

   - **`## Validation rules`** — REQUIRED. Table of active validation rules per canon. If none active, write a single row `| _None active_ | — | — | — |` — do NOT omit.

   - **`## Triggers and Apex touching this object`** — REQUIRED. Code that mutates or reads this object beyond standard CRUD. For each trigger: what events, what handler class, what the handler does. (Not "Apex automation" — `## Triggers and Apex touching this object` matches canon.)

   - **`## Flows touching this object`** — REQUIRED. Bullet list of active Flows that reference this object, with one-line summary each. Link: `[Flow_API_Name](../flows/Flow_API_Name.md)`. If none, write `_None._`.

   - **`## Integrations referencing this object`** — REQUIRED. Bullet list of external integrations that read or write this object. Link: `[System](../integrations/System.md)`. If none, write `_None._`.

   - **`## Test coverage`** — REQUIRED. Test data factory method, test classes covering this object's behavior. If no tests touch the object, write `_No test coverage._` — do NOT omit.

   - **`## Constraints and gotchas`** — REQUIRED. Anything surprising, nontrivial, or easy to get wrong. Examples in canon template. If none, write `_None._`.

   - **`## Related decisions`** — REQUIRED. `docs/decisions/*.md` entries that govern this object. If none, write `_None._` — do NOT omit. (Replaces canon template's `## History` section, which violated ADR-0010 state-not-history.)

   - **`## Record types`** — OPTIONAL. Include only if the object has custom record types. Table with name + label + picklist filters.

### Section-name enforcement check

Before writing the file, verify your draft has each REQUIRED section header spelled exactly as listed above (matching case, spacing, punctuation). If you find yourself wanting to use `## Schema`, `## Overview`, `## Apex automation`, or `## Related ADRs` — STOP. Those are not the canon section names. Rename before writing.

### Source-file reference formatting (avoid 404s on the rendered site)

When you reference any file *outside* `docs/` — Apex `.cls`/`.trigger` files in `force-app/`, metadata XML, scripts, anything in the engagement repo's source tree — **do NOT write a relative markdown link to it**. The MkDocs Material site publishes only the `docs/` tree; relative paths like `[Foo.cls](../../force-app/main/default/classes/Foo.cls)` resolve to a file that exists on disk but 404s on the rendered site.

Two acceptable forms:

1. **Inline code (preferred for prose).** Just style the filename as code: `` `ContactPhoneNormalizer.cls` `` — no link. Engineers wanting the source open it from VSCode or grep the repo. The doc isn't a navigation tool for source files.
2. **Absolute GitHub URL (use when the link adds real reader value).** Read `mkdocs.yml` once at the start of your pass; the `repo_url:` field holds `https://github.com/<org>/<repo>`. Construct: `[ContactPhoneNormalizer.cls](<repo_url>/blob/main/force-app/main/default/classes/ContactPhoneNormalizer.cls)`. The link goes to GitHub's file view, which renders Apex source cleanly.

Relative links between docs *inside* `docs/` (object → flow, feature → object, etc.) work normally — that's what MkDocs publishes. The rule above is only for the `force-app/` / `scripts/` / `manifest/` / etc. directories.

5. **Cross-link aggressively.** Use relative markdown links to other docs/objects/, docs/flows/, docs/integrations/ pages, even if those pages don't exist yet (the document-flows / document-integrations nodes will fill them in; cross-links resolve once their pass completes).

## State, not history (per ADR-0010)

Describe what exists NOW. Do not write "as of GRIM-N this changed." If a recent change introduced a field, the field is just *part of the schema*. Change attribution lives in `git blame` and Jira.

## Output

Structured JSON summary:

```json
{
  "objects_written": [
    "docs/objects/Renewal__c.md",
    "docs/objects/Account.md"
  ],
  "objects_preserved": [
    {
      "doc": "docs/objects/Opportunity.md",
      "reason": "last_updated_by was 'drew.smith@openwacca.com' (human edit, preserved)"
    }
  ],
  "objects_failed": [
    {
      "object": "Custom_Object__c",
      "reason": "object-meta.xml unreadable or missing"
    }
  ],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links_count": 0
  }
}
```

Broken cross-links are expected during this run (the flows/ and integrations/ docs don't exist yet); count them so the synthesize-features and update-index nodes can verify resolution after all three category nodes finish.
