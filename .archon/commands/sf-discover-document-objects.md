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

4. **Write `docs/objects/<Object>.md`** following the template's section structure:

   - **Frontmatter:** title, audience: public, last_updated (today), last_updated_by (`archon-discover-<run-id>` if `$ARCHON_RUN_ID` set; else `archon-discover`), related_tickets: [], related_docs: list the flow/integration docs you cross-reference.

   - **Overview** — 2–4 sentences explaining what the object represents in the business domain and its primary purpose. Pull from the object's label and field semantics. Do NOT just restate the API name.

   - **Schema** — table of significant fields. Columns: API name, label, type, required/optional, description (from field-meta.xml `<description>` or `<inlineHelpText>` if present; otherwise inferred from name + type). Group standard fields separately at the bottom if relevant; focus the top of the table on custom fields.

   - **Sharing model** — pulled from `<sharingModel>` in the object-meta. Note any sharing rules in `force-app/main/default/sharingRules/<Object>SharingRules.sharingRules-meta.xml` if present.

   - **Validation rules** — table of active validation rules. Columns: rule name, condition (errorConditionFormula), error message. Mark inactive ones briefly if relevant.

   - **Apex automation** — describe the triggers and handler classes that operate on this object. For each trigger: what events, what handler class, what the handler does. Reference the handler class file path for engineers to read.

   - **Flows** — bullet list of active Flows that reference this object, with one-line summary each. Link to the flow doc when written: `[Flow_API_Name](../flows/Flow_API_Name.md)`.

   - **Integrations** — bullet list of external integrations that read or write this object. Link to integration docs: `[System](../integrations/System.md)`.

   - **Record types** — if any, table with name + label + picklist filters.

   - **Related ADRs** — `docs/decisions/*.md` entries that govern this object. Skip if none.

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
