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

2. **For each feature**, write `docs/features/<slug>.md`. The slug is `kebab-case` and short (1–3 words). Per the template:

   - **Frontmatter:** title (display name), audience: public, last_updated, last_updated_by (`archon-discover-<run-id>`), related_tickets: [], related_docs: list of the canonical docs this feature draws from.

   - **One-line summary** at the very top, in italics: what the feature does for an end user.

   - **Overview** — 2–4 sentences. What is the feature, who uses it, when.

   - **How it works** — numbered list of steps in execution order, business-readable. Use phrases like "When a user closes-won an Opportunity, the system creates a Renewal record..." Not "RenewalTriggerHandler.afterInsert() fires and calls RenewalCalculator.create()..." That's in the object doc; link to it.

   - **Acceptance signals** — how a non-engineer knows the feature is working (visible record state, emails sent, downstream actions enabled).

   - **Known limitations** — honest list of edge cases not handled, or known imperfections.

   - **Governing decisions** — links to relevant ADRs.

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
