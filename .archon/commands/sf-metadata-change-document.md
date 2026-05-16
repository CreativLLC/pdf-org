# `sf-metadata-change-document`

You are producing the engagement documentation updates for the metadata change just made. **Per [ADR-0010](../decisions/0010-engagement-documentation-model.md), documentation describes *current state*, not change history.** Change history lives in Jira (the comment posted by `update-jira-on-completion`, or the orchestrator's consolidated comment) and `git log`. Your job is to make the engagement's canonical and derived docs reflect what now exists in the org's schema as a result of this change.

## Inputs

- `$pull-jira-context.output` — title, description, acceptance criteria.
- `$classify-sub-type.output` — sub_type, scope, side flags (`touches_fls`, `is_destructive_modify_field`, `affects_picklist_data`).
- `$plan.output`, `$ARTIFACTS_DIR/plan.md` — the plan, including proposed FLS posture.
- `$execute.output`, `$ARTIFACTS_DIR/implementation.md` — what was actually done (files added / modified / deleted).
- `$validate.output` — deploy results, reference-impact results, FLS-coverage gaps.
- `$load-engagement-context.output` — patterns/standards/object docs in scope; helpful for identifying which docs to update.

## Tools

Read, Edit, Write, Glob, Grep. Templates live at `docs/.harness-templates/` in the engagement repo (copied from `harness/docs-templates/` at bootstrap).

## The aggressive-update model (ADR-0010 §3)

For every object, field, validation rule, record type, page layout, or picklist value touched by this run, walk the engagement's docs and update **every doc that references that artifact** — not just the most-affected one. Drift is the enemy.

Concretely:

1. **List every artifact this run touched** — combine `$execute.output.files_changed_actual` (file paths) with the object/field/rule/type names parsed from those paths.
2. **For each artifact, identify candidate docs to update:**
   - `docs/objects/<ObjectAPIName>.md` — always; this is the canonical doc for the touched object.
   - `docs/features/*.md` — grep each for references to the touched object/field by name.
   - `docs/flows/*.md` — grep each for references (a Flow might use the touched field).
   - `docs/integrations/*.md` — grep each (an integration might map the touched field to an external system).
   - `docs/security/*` — when `$classify-sub-type.output.touches_fls == "true"`, see step 5 below.
3. **Update each matching doc** to reflect current state. Examples:
   - New field added → update `docs/objects/<Object>.md`'s "Key fields" table with the new field row. Update its "Sharing model" section if FLS posture is documented.
   - Validation rule modified → update `docs/objects/<Object>.md`'s "Validation rules" table to reflect the current formula and active state.
   - Field deleted → remove the field row from "Key fields"; remove any references in feature docs.
   - Record type created → update "Record types" section of the object doc.
   - Picklist value added → update the field's row in "Key fields" with the current value list.

## Task

1. **Inventory the change.** From `$execute.output.files_changed_actual`, list:
   - Objects added / modified / deleted.
   - Fields added / modified / deleted (per object).
   - Validation rules added / modified / deleted (per object).
   - Record types added / modified.
   - Page layouts added / modified.
   - Picklist values added / deleted (per field).

2. **Identify candidate docs.** For each touched artifact, grep the docs tree:
   ```
   grep -rln "<ArtifactName>" docs/objects docs/flows docs/integrations docs/features docs/security 2>/dev/null
   ```
   Build a list of `(artifact, candidate_doc_path)` pairs. The object's own `docs/objects/<Object>.md` is always a candidate even if grep doesn't match (the doc may not yet mention the touched field/rule).

3. **Update the canonical object doc.** For each touched object, open or create `docs/objects/<ObjectAPIName>.md` from `docs/.harness-templates/object-doc.md` if it doesn't exist. Update sections per the canon (these section names match `sf-discover-document-objects.md` and the canon template — DO NOT invent alternate names):
   - **`## Key fields`** — for `create-field` / `modify-field` / `delete-field`: refresh the table row for the affected field. Use the field's current metadata XML as the source of truth.
   - **`## Validation rules`** — for `create-validation-rule` / `modify-validation-rule` / `delete-validation-rule`: refresh the table.
   - **`## Sharing model`** — for `modify-custom-object` where the sharing model changed: update the OWD line.
   - **`## Record types`** (optional section, include when relevant) — for `create-record-type` / `modify-record-type`: refresh the table.
   - **`## Triggers and Apex touching this object`** — if the metadata change affects what existing triggers/Apex do (e.g., a new field that an existing trigger should populate; or a field whose deletion will break an existing trigger), update the description. The fix itself happens in `sf-apex-change`; this doc note is the breadcrumb for the next reader.

4. **Update derived feature docs.** If `$plan.output` or the ticket description identifies a feature affected by the change, open `docs/features/<slug>.md` and refresh the "How it works" or "Inputs / Outputs" section to reflect the schema change. Keep it business-readable; link to the object doc for the technical detail.

5. **Security docs — touches_fls handling (per ADR-0013).**
   - When `sub_type == "create-field"` AND `touches_fls == "true"`: append a note to `docs/objects/<Object>.md`'s "Sharing model" section describing the proposed FLS posture from `$plan.output.fls_posture` (which profiles read / edit, and why). Use bullet points, not a separate table — the canonical profile/PS posture lives in `docs/security/profiles/*.md` and `docs/security/permission-sets/*.md`.
   - For each profile in `$plan.output.fls_posture.read` and `$plan.output.fls_posture.edit`: if `docs/security/profiles/<Profile>.md` exists, append a row or note to its "Object permissions matrix" section indicating this new field's posture. **Mark the row as `Pending sf-permission-change`** — the actual XML change hasn't happened yet; this workflow only declares intent.
   - Same for permission sets: if `docs/security/permission-sets/<PS>.md` exists, append a "Pending sf-permission-change" note for the new field.
   - When `sub_type == "modify-custom-object"` AND the sharing model changed: update `docs/security/sharing-model.md`'s table for that object.
   - When `validate.output.missing_security_docs` is non-empty: record the gap in `$ARTIFACTS_DIR/follow-ups.md` — the FLS posture references profiles/PSs that don't have security docs yet. A future `sf-permission-change` or manual security-doc backfill resolves this.

6. **Create missing canonical docs.**
   - If `sub_type == "create-custom-object"` and `docs/objects/<NewObject>.md` doesn't exist: create it from the template. Fill every required section: Purpose, Type and origin, Key fields (with the fields created in this run), Relationships, Sharing model, Validation rules (if any created), Triggers and Apex touching this object (empty initially), Flows touching this object (empty), Integrations referencing this object (empty), Test coverage (empty), Constraints and gotchas, Related decisions.
   - If the change introduces work on an Object that has no `docs/objects/<Object>.md`: same as above. Standard objects with no engagement-specific customizations typically don't have docs, but a new custom field on Account triggers creating `docs/objects/Account.md` if it doesn't yet exist.

7. **Update `docs/index.md`.**
   - If a new object doc was created: add an entry under "Object index" with a one-line description.
   - If an existing object's one-line description is now stale (the change meaningfully changed what the object represents — e.g., adding a Tier field changes the "what" of an Account): update.

8. **Do NOT modify team-canon patterns or standards.** `.archon/patterns/` and `.archon/standards/` are read-only in the engagement repo. If the workflow exposed a gap in team canon, record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate PR against the harness repo.

9. **Source-file reference formatting (avoid 404s on the rendered site).** When you reference any file *outside* `docs/` from inside an engagement doc — metadata XML in `force-app/`, scripts — **do NOT write a relative markdown link to it**. The MkDocs Material site publishes only the `docs/` tree; a link like `[Account.object-meta.xml](../../force-app/main/default/objects/Account/Account.object-meta.xml)` resolves to a file that exists on disk but 404s on the rendered site. Two acceptable forms:

   1. **Inline code, no link** (preferred for prose): `` `Account.object-meta.xml` ``, `` `Revenue_Tier__c.field-meta.xml` ``.
   2. **Absolute GitHub URL** (when the link adds real reader value): read `mkdocs.yml` once to get `repo_url:`, then write `[Revenue_Tier__c.field-meta.xml](<repo_url>/blob/main/force-app/main/default/objects/Account/fields/Revenue_Tier__c.field-meta.xml)`.

   Relative links between docs *inside* `docs/` (object → flow, feature → object, etc.) work normally — the rule above is only for paths leaving the docs tree.

10. **Frontmatter rules** for every doc you write or update:
    - `last_updated`: today's date (YYYY-MM-DD).
    - `last_updated_by`: `archon-run-<run-id>` if `$ARCHON_RUN_ID` is set; else the engineer's `git config user.email`.
    - `related_tickets`: append the current ticket key to the existing list (deduplicate).
    - `related_docs`: update to include any other doc this change made the current doc reference.

11. **Refuse to land empty required sections.** Object doc must have non-empty Purpose, Type and origin, Key fields, Relationships (or the "no relationships" sentinel), Sharing model, Validation rules (or "_None active_" sentinel), Triggers and Apex touching this object. Feature doc must have non-empty Overview, How it works, and Acceptance signals. If any required section comes out empty, fail this node and surface what's missing.

12. **State-vs-history scan (refuse-on-detection).** Before staging, scan every doc you wrote or edited for change-history language that violates ADR-0010. Grep each updated `.md` file for these forbidden patterns (case-insensitive):

    - `introduced with this` / `introduced in this`
    - `recently added` / `newly added`
    - `as of <any ticket key>` / `as of 20[0-9][0-9]-`
    - `previously` / `formerly` / `used to be` / `used to fire`
    - `now does` / `now uses` (when contrasting with a prior state)
    - `was added` / `was changed` / `was removed`
    - References to `../changelog/` or `docs/changelog/` in body OR frontmatter `related_docs:`
    - Body sentences naming the current Jira ticket (ticket attribution belongs in frontmatter `related_tickets:`, not in prose)

    If any pattern matches: **fail this node with a structured error** listing the file, line number, matched phrase, and a suggested rewrite to bare state. Example: matched `"recently added field"` at `docs/objects/Account.md:42` → rewrite to drop the qualifying clause; describe the field as a normal entry in the table.

    **Also enforce the external-context privacy invariant (per ADR-0015):** if `$pull-jira-context.output.external_context` is non-empty, for each entry scan every doc body for substrings of 50+ tokens that appear in the entry's `content` field. If found, fail the node with a structured error: external context (Fathom transcripts, Drive docs, etc.) is working memory only — it must not be echoed into engagement docs verbatim.

13. **Link-resolution scan.** Run the link validator against the docs tree:

    ```
    bash .archon/scripts/validate-doc-links.sh docs/
    ```

    Exit code 0: continue to staging. Exit code 1: broken links found — fail this node, surface the validator's output (file:line: target), and let the engineer fix the references and re-run.

14. **Stage the doc changes.** Run `git status --porcelain` to confirm everything is in the working tree under `docs/`. Do NOT commit — the engineer commits the whole change (metadata + docs) as one commit after the Jira write-back step succeeds (or after the orchestrator's consolidated write-back, when this workflow ran with `orchestrated: true`).

## Output

Emit a structured JSON summary on stdout:

```json
{
  "docs_created": [
    "docs/objects/Account.md"
  ],
  "docs_updated": [
    "docs/objects/Renewal__c.md",
    "docs/security/profiles/Sales.md",
    "docs/security/permission-sets/Sales_Edit_Revenue.md",
    "docs/features/renewal-pipeline.md",
    "docs/index.md"
  ],
  "docs_updated_count": 5,
  "docs_unchanged_but_inspected": [
    "docs/objects/Opportunity.md"
  ],
  "fls_posture_recorded": true,
  "fls_posture_pending_sf_permission_change": true,
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "follow_ups_recorded": false
}
```

The `fls_posture_pending_sf_permission_change` flag is a deliberate marker: when `true`, the engineer (or the orchestrator) needs to run `sf-permission-change` next to actually grant the FLS in profile/PS XML. The docs declare the posture; the permission-change workflow implements it.

If `frontmatter_validation.all_required_fields_present` is `false` or `broken_related_doc_links` is non-empty, the node fails. Engineer addresses the gap and re-runs.

## On state-vs-history (worth re-reading)

The most common pitfall here is writing change-history language into a state doc. For schema docs specifically:

- ❌ "The `Revenue_Tier__c` field was added in GRIM-201 to support tier-based renewal pricing."
- ❌ "Previously, the `Status__c` field had three values; the engagement added Cancelled and Renewing."
- ❌ "The team decided in 2026-05 to use Master-Detail instead of Lookup."

State-of-the-schema equivalents:

- "The `Revenue_Tier__c` field categorizes accounts by annual revenue for tier-based renewal pricing."
- "The `Status__c` picklist has five values: Active, Prospecting, Renewing, Cancelled, Lapsed."
- "Per [ADR-0007 in this engagement], the relationship to Account is Master-Detail to enforce cascading deletes on Account cleanup."

The change history of "this used to be different" lives in `git log` for the doc and in the Jira ticket that changed it. The doc itself is the present tense.
