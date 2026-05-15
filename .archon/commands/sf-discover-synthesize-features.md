# `sf-discover-synthesize-features`

You are identifying the engagement's business-facing features and writing `docs/features/<slug>.md` for each, per [ADR-0010](../decisions/0010-engagement-documentation-model.md)'s derived-business-facing layer. This runs after `document-objects`, `document-flows`, and `document-integrations` have populated the canonical docs.

A *feature* is a coherent end-to-end business capability that spans multiple objects, flows, and/or integrations. Example: "Renewal Pipeline" = `Renewal__c` object + `Renewal_Auto_Create` flow + `RenewalCalculator` Apex + `Stripe` integration. The feature doc tells the business story; the canonical docs hold the technical detail.

## Inputs

- `$classify-significance.output.probable_features` — the classifier's first-pass feature sketches.
- `$document-objects.output.objects_written` — the objects/*.md files now in place.
- `$document-flows.output.flows_written` — the flows/*.md files now in place.
- `$document-integrations.output.integrations_written` — the integrations/*.md files now in place.
- The newly-written canonical docs themselves (read them to identify cross-references).
- The template: `docs/.harness-templates/feature-doc.md`.

## Tools

Read, Edit, Write, Glob, Grep. Reads `docs/` (the canonical docs just written + any existing); writes to `docs/features/`.

## Idempotency rule (per ADR-0011)

Per other discover-* nodes — check existing `docs/features/<slug>.md` frontmatter `last_updated_by`. If non-`archon-*`, skip; log as preserved.

## Task

1. **Refine the feature list.** The classifier produced `probable_features`; refine by reading the newly-written canonical docs:
   - Cluster objects whose canonical docs cross-reference each other (object → flow → object indicates a feature touching both objects).
   - Trace integrations to the objects they affect → those go in the same feature as the objects.
   - A feature should be **business-recognizable** — name it as a PM would name it ("Renewal pipeline", "Document generation", "Account onboarding"), not as a developer would ("Renewal__c CRUD", "Trigger handler refactor").

2. **For each feature**, write `docs/features/<slug>.md`. The slug is `kebab-case` and short (1–3 words). The section names and order below match `docs/.harness-templates/feature-doc.md` exactly. **All sections are REQUIRED. Do not omit any. Do not invent alternate names. Do not reorder.**

   - **Frontmatter** (required keys): `title` (display name), `audience: public`, `last_updated` (today), `last_updated_by` (`archon-discover-<run-id>` if `$ARCHON_RUN_ID` set), `related_tickets: []`, `related_docs:` (relative paths to the canonical docs this feature draws from).

   - **One-line summary** at the very top, in italics: `> **One-line summary** of what the feature does for an end user.`

   - **`## Overview`** — REQUIRED. 2–4 sentences. What is this feature, who uses it (admin, end user, integration), when.

   - **`## How it works`** — REQUIRED. Numbered list of steps in execution order, **business-readable**. Use phrases like "When a user closes-won an Opportunity, the system creates a Renewal record..." NOT "RenewalTriggerHandler.afterInsert() fires and calls RenewalCalculator.create()..." Apex class names, field API names, and method signatures belong in the linked object doc, not here. Cross-reference the canonical docs at the bottom of the section.

   - **`## Acceptance signals`** — REQUIRED. How does a user know the feature is working correctly? Visible record state, emails/notifications sent, downstream actions enabled. If the feature has no user-visible acceptance signal (rare — usually data-only features), write `_This feature has no end-user-visible acceptance signal; verification is via record-level inspection by an admin._` — do NOT omit.

   - **`## Known limitations`** — REQUIRED. Honest list of edge cases the feature does NOT handle (or handles imperfectly), framed from the user's perspective. If you find yourself writing engineering smells (duplicate trigger files, unused DTOs, Apex test placement) — those belong in the object doc's `Constraints and gotchas`, not here. If no user-facing limitations exist, write `_None known._` — do NOT omit.

   - **`## Governing decisions`** — REQUIRED. Links to ADRs in `docs/decisions/` that constrain how this feature works. Format per canon: `- [`<NNNN-slug>`](../decisions/<NNNN-slug>.md) — <one-line summary of what the ADR locked>`. **If no engagement ADRs govern this feature yet, write `_None yet._`** — do NOT omit. This section is the gateway from features to architectural decisions; future workflows verify it exists.

   - **`## Related tickets`** — REQUIRED (matches canon template). The authoritative list is in frontmatter `related_tickets`. This section is for human-readable summary if useful. If frontmatter `related_tickets` is empty, write `_None — see frontmatter._`

### Section-name + completeness enforcement

Before writing each feature file, verify your draft has every REQUIRED section header spelled exactly as listed above, in the listed order. If `## Governing decisions` is missing from your draft, STOP and add it before writing. The same applies to every section above marked REQUIRED. Empty content within a section is OK (use the documented `_None._` / `_None yet._` placeholders); omitting the section entirely is NOT.

3. **DO NOT duplicate technical detail.** If you find yourself describing Apex method signatures, SOQL queries, or trigger event-order specifics — STOP and link to the object/flow doc instead. The feature doc summarizes; the canonical doc has the depth.

4. **DO NOT invent features** that aren't supported by the canonical docs. Every claim in a feature doc should be traceable to facts in the underlying object/flow/integration docs.

5. **Skip clusters that don't form a coherent feature.** Some custom objects are pure data-storage with no automation, or pure-utility classes — no feature doc needed. List them in the output's `clusters_skipped` array with reasoning.

## Special case: no features identified

If after analysis there are zero coherent features (rare — typically means a very small engagement or pure-data-warehouse-style usage), output `features_written: []` and explain in `reasoning` so the engineer knows discovery didn't miss something.

## Output

```json
{
  "features_written": [
    "docs/features/renewal-pipeline.md",
    "docs/features/document-generation.md"
  ],
  "features_preserved": [
    {
      "doc": "docs/features/onboarding.md",
      "reason": "last_updated_by was 'drew.smith@openwacca.com' — human edit, preserved"
    }
  ],
  "clusters_skipped": [
    {
      "involves_objects": ["Audit_Log__c"],
      "reason": "Pure data-storage object; no automation, no integration. No feature emerges."
    }
  ],
  "reasoning": "Identified 2 features spanning 4 of the 5 documented objects. Audit_Log__c is data-only; no feature."
}
```
