# `sf-apex-change-document`

You are producing the engagement documentation updates for the change just made. **Per [ADR-0010](../decisions/0010-engagement-documentation-model.md), documentation describes *current state*, not change history.** Change history lives in Jira (the comment posted by `update-jira-on-completion`) and `git log`. Your job is to make the engagement's canonical and derived docs reflect what now exists in the org as a result of this change.

> **Important — supersedes ADR-0009 §8's per-ticket changelog rule.** Do NOT write to `docs/changelog/YYYY-MM/<TICKET>.md`. That model is deprecated. Update the canonical (object / flow / integration) docs and the derived (feature) docs instead.

## Inputs

- `$pull-jira-context.output` — title, description, acceptance criteria.
- `$classify-sub-type.output` — sub_type, scope, side flags (`touches_soql_dml`, `touches_callouts`).
- `$plan.output`, `$ARTIFACTS_DIR/plan.md` — the plan.
- `$execute.output`, `$ARTIFACTS_DIR/implementation.md` — what was actually done (files added / modified / deleted).
- `$validate.output` — test results, coverage, static-check outcomes.
- `$load-engagement-context.output` — patterns/standards/object docs in scope; helpful for identifying which docs to update.

## Tools

Read, Edit, Write, Glob, Grep. Templates live at `docs/.harness-templates/` in the engagement repo (copied from `harness/docs-templates/` at bootstrap).

## The aggressive-update model (ADR-0010 §3)

For every Apex class, trigger, or test class touched by this run, you walk the engagement's docs and update **every doc that references that artifact** — not just the most-affected one. Drift is the enemy.

Concretely:

1. **List every artifact this run touched** — combine `$execute.output.files_changed_actual` (file paths) with the class/trigger names extracted from those paths.
2. **For each artifact, identify candidate docs to update:**
   - `docs/objects/*.md` — for each, check whether it references the artifact (grep for the class/trigger name).
   - `docs/flows/*.md` — same.
   - `docs/integrations/*.md` — same.
   - `docs/features/*.md` — same (and additionally any feature explicitly named by `$plan.output` or in the ticket description).
3. **Update each matching doc** to reflect current state. Examples:
   - A new method added to `RenewalCalculator` referenced in `objects/Renewal__c.md` → update that doc's "Apex automation" section to describe the new method.
   - A new trigger created → update the object doc's "Apex automation" section AND add a row to its "Triggers" table.
   - A class deletion → update every doc that referenced the deleted class to remove references; add a note to a relevant ADR if the deletion changed an architectural pattern.
4. **For NEW artifacts that no existing doc references**:
   - New Apex class on an object that has a doc → add a section to that object's doc.
   - New Apex class on an object that DOES NOT yet have a doc → create the object doc from `docs/.harness-templates/object-doc.md`.
   - New feature (the ticket explicitly creates one or significantly extends one) → create or update the feature doc from `docs/.harness-templates/feature-doc.md`.

## Task

1. **Inventory the change.** From `$execute.output.files_changed_actual`, list:
   - Apex classes added / modified / deleted (names without extension).
   - Triggers added / modified / deleted (names).
   - Test classes added / modified (names).
   - The Salesforce objects they touch (parsed from trigger files' `on <Object>` declarations, and from class signatures or SOQL inside the class).

2. **Identify candidate docs.** For each touched artifact, grep the docs tree:
   ```bash
   grep -rln "<ArtifactName>" docs/objects docs/flows docs/integrations docs/features 2>/dev/null
   ```
   Build a list of `(artifact, candidate_doc_path)` pairs.

3. **Update each candidate doc.**
   - **For object docs** (`docs/objects/<Object>.md`): update the "Apex automation" section (and "Triggers" / "Handler classes" subsections per the template). Reflect what the class/trigger does NOW. If a method was added: describe it and its inputs/outputs. If a method was removed: remove its reference. If signature changed: update the description to match.
   - **For flow docs**: if a flow's referenced Apex changed, update the flow doc's "Invokes" section.
   - **For integration docs**: if a callout signature or a webhook handler changed, update the doc's "Apex layer" section.
   - **For feature docs**: if the change affects the feature's user-facing behavior, update the feature doc's "How it works" section. Cross-reference the canonical object docs (don't duplicate technical detail — link).

4. **Create missing canonical docs.**
   - If the change introduces work on an Object that has no `docs/objects/<Object>.md`: create it from the template. Fill every required section: Overview, Schema (fields touched), Sharing model, Apex automation, Flows, Integrations, Related ADRs.
   - If the change is the first significant touch of a new external integration: create `docs/integrations/<System>.md` from the template.

5. **Create or update the feature doc.** Identify the feature(s) the change relates to:
   - Heuristic: scan the ticket title and description for words/phrases matching existing `docs/features/*.md` slugs. Match on substring or close synonyms.
   - If no existing feature doc matches AND the ticket describes work that's plainly a new feature (e.g., the title is "Add SimpleGreeter utility class"), make a judgment call: is this a feature, or just a utility supporting an existing feature? Utility-supporting work → no new feature doc (just update the existing canonical docs); brand-new feature → create `docs/features/<slug>.md` from the template.
   - When updating a feature doc: keep it business-readable. Summarize, don't deep-dive. Link to `docs/objects/*.md` for the technical detail.

6. **Update `docs/index.md`.**
   - If a new object doc was created: add an entry under "Object index" with a one-line description.
   - If a new feature doc was created: add an entry under "Feature index" with a one-line description.
   - If a new integration doc was created: add an entry under "Integration index".
   - If no new files were created but existing entries' one-line descriptions are now stale (the change meaningfully changed what an object/feature does), update the descriptions.

7. **Do NOT write to `docs/changelog/`.** That directory may still exist in older engagements for historical entries — leave it untouched. The harness's structured Jira comment (written by `update-jira-on-completion.md`) is the per-ticket record.

8. **Do NOT modify team-canon patterns or standards.** `.archon/patterns/` and `.archon/standards/` are read-only in the engagement repo (copied content per ADR-0002). If the workflow exposed a gap in team canon, record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate PR against the harness repo.

9. **Frontmatter rules** for every doc you write or update:
   - `last_updated`: today's date (YYYY-MM-DD).
   - `last_updated_by`: `archon-run-<run-id>` if `$ARCHON_RUN_ID` is set; else the engineer's `git config user.email`.
   - `related_tickets`: append the current ticket key to the existing list (deduplicate).
   - `related_docs`: update to include any other doc this change made the current doc reference.

10. **Refuse to land empty required sections.** Object doc must have non-empty Overview, Schema, and Apex automation. Feature doc must have non-empty Overview, How it works, and Acceptance signals. Integration doc must have non-empty Purpose and API surface. If any required section comes out empty, fail this node and surface what's missing.

11. **Stage the doc changes.** Run `git status --porcelain` to confirm everything is in the working tree under `docs/`. Do NOT commit — the engineer commits the whole change (Apex + docs) as one commit after the Jira write-back step succeeds.

## Output

Emit a structured JSON summary on stdout:

```json
{
  "docs_created": [
    "docs/objects/Renewal__c.md",
    "docs/features/renewal-pipeline.md"
  ],
  "docs_updated": [
    "docs/objects/Account.md",
    "docs/integrations/Stripe.md",
    "docs/index.md"
  ],
  "docs_unchanged_but_inspected": [
    "docs/objects/Opportunity.md"
  ],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "follow_ups_recorded": false,
  "deprecated_changelog_writes_avoided": true
}
```

The last field is a deliberate marker for the workflow's run-log: it confirms this node followed ADR-0010 and didn't fall back to the old per-ticket changelog pattern.

If `frontmatter_validation.all_required_fields_present` is `false` or `broken_related_doc_links` is non-empty, the node fails. Engineer addresses the gap and re-runs.

## On state-vs-history (worth re-reading)

The most common pitfall here is writing change-history language into a state doc. Examples of what NOT to write:

- ❌ "As of GRIM-48, this method was added to support..."
- ❌ "Previously, this trigger fired on insert; now it fires on insert and update."
- ❌ "The team decided in 2026-05 to..."

Equivalents that ARE state-of-the-org:

- ✅ "This method [does X for Y purpose]."
- ✅ "This trigger fires on insert and update."
- ✅ "Per [ADR-0007 in this engagement], we use [pattern]."

The change history of "this used to be different" lives in `git log` for the doc, and in the Jira ticket that changed it. The doc itself is the present tense.
