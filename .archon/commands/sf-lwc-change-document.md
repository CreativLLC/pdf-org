# `sf-lwc-change-document`

You are producing the engagement documentation updates for the LWC change just made. **Per [ADR-0010](../decisions/0010-engagement-documentation-model.md), documentation describes *current state*, not change history.** Change history lives in Jira (the comment posted by `update-jira-on-completion`) and `git log`.

Per [ADR-0021](../decisions/0021-sf-lwc-change-scope-and-gates.md) §9, an LWC change touches docs at multiple layers: the **canonical** object docs (for any SObject the controller reads/writes), the **derived** feature docs (for the LWC's feature[s]), and optionally a **component** doc when the LWC is significant enough to deserve one.

## Inputs

- `$pull-jira-context.output` — ticket title, description, acceptance criteria.
- `$classify-sub-type.output` — sub_type, scope, side flags.
- `$plan.output`, `$ARTIFACTS_DIR/plan.md` — the plan; `lwc_names`, `controller_names`, `doc_outputs`.
- `$execute.output`, `$ARTIFACTS_DIR/implementation.md` — what was actually done.
- `$validate.output` — test results, coverage, a11y findings, FLS/CRUD result.
- `$load-engagement-context.output` — object/feature/integration docs already in scope.

## Tools

Read, Edit, Write, Glob, Grep, Bash (for the link validator). Templates live at `docs/.harness-templates/` in the engagement repo.

## The aggressive-update model (ADR-0010 §3)

For every artifact this run touched — each LWC name, each controller name, each SObject the controller reads or writes — walk the engagement's docs and update **every doc that references that artifact**. Drift is the enemy.

## Task

1. **Inventory the change.** From `$execute.output.files_changed_actual` and `$plan.output`, list:
   - LWC component names added / modified / deleted.
   - Apex controller names added / modified / deleted.
   - Apex test classes added / modified.
   - Jest test paths added / modified.
   - SObjects referenced by the controller (parsed from SOQL `FROM` clauses, DML target types, and `@AuraEnabled` method parameter / return types in the controller `.cls`).
   - Features the LWC is part of (heuristic: match LWC name and ticket description against existing `docs/features/*.md` slugs; also consider the LWC's `<target>` in its meta-XML — `lightning__RecordPage` for `Renewal__c` strongly implies the renewal-pipeline feature).

2. **Identify candidate docs.** For each touched artifact (LWC name, controller name, SObject), grep the docs tree:

   ```bash
   grep -rln "<ArtifactName>" docs/objects docs/flows docs/integrations docs/features docs/components 2>/dev/null
   ```

   Build a list of `(artifact, candidate_doc_path)` pairs.

3. **Update each candidate doc.**

   - **For object docs** (`docs/objects/<Object>.md`): the LWC controller reads/writes this object. Update or add a section under the object doc's "Apex automation" (or analogous) area describing the controller and its `@AuraEnabled` methods, what they query / mutate, and the FLS posture (which fields are read, which are written). Also update the "User interfaces touching this object" section (or add one) listing the LWC that surfaces this object to users. If the LWC name or controller method names appear nowhere in the doc but the doc IS about a touched SObject, add the references.
   - **For feature docs** (`docs/features/<feature>.md`): update the "How it works" section to reflect the current end-to-end behavior including the LWC's role. **Keep it business-readable** — don't deep-dive technical detail; link to the canonical object doc and component doc (if any) for that.
   - **For integration docs** (`docs/integrations/<System>.md`): if the LWC controller calls out to an external system, the doc's "Apex layer" or "Consumers" section names the controller and the methods that issue callouts.
   - **For component docs** (`docs/components/<LWCName>.md`): see step 5 for when to create one; when updating an existing one, reflect current props, public methods, events emitted, and parent / sibling components that compose with this one.

4. **Reference formatting — inline code only for LWC and controller names.**

   Per ADR-0021 §9 and the precedent in `sf-apex-change-document.md` step 8a: when you reference an LWC component or an Apex controller from within an engagement doc, **do NOT write a relative markdown link to its `force-app/` source**. The MkDocs Material site publishes only the `docs/` tree; a link like `[renewalSummary](../../force-app/main/default/lwc/renewalSummary/renewalSummary.js)` resolves on disk but 404s on the rendered site.

   Two acceptable forms:

   1. **Inline code, no link** (preferred for prose): `` `renewalSummary` `` and `` `RenewalSummaryController` ``.
   2. **Absolute GitHub URL** (when the link adds real reader value): read `mkdocs.yml` once to get `repo_url:`, then write `[renewalSummary](<repo_url>/blob/main/force-app/main/default/lwc/renewalSummary/renewalSummary.js)`.

   Relative links between docs inside `docs/` work normally — this rule applies only to paths leaving the docs tree.

5. **Create missing canonical docs and optional component doc.**

   - **Object doc:** if the controller reads/writes an SObject that has no `docs/objects/<Object>.md`, create it from `docs/.harness-templates/object-doc.md`. Fill every required section.
   - **Feature doc:** if the change is the first significant touch of a new feature, create `docs/features/<slug>.md` from the template.
   - **Component doc** (`docs/components/<LWCName>.md`) — **conditional**. Create only when the LWC is significant enough to deserve its own doc. The planner phase made the initial judgment; respect it (`$plan.output.doc_outputs` includes the component doc path if the planner decided yes). Use judgment if the planner left it ambiguous: a major user-facing component on a high-traffic record page or a community landing page → yes; a small utility component used in two places → no (its context lives in the parent components' docs and the object doc).

     When you create a component doc, fill these sections at minimum:
     - **Overview** — what the component does for the user.
     - **Public API** — `@api` properties (props), public methods, events emitted.
     - **Wired data** — `@wire` adapters used, the underlying `@AuraEnabled` methods.
     - **Imperative Apex** — non-`@wire` controller methods imported, when they're invoked.
     - **Composes / composed by** — sibling components (children rendered by this one, parents that render this one).
     - **Visibility** — which `<target>` entries it supports, whether `<isExposed>` is true, App Builder design properties.

6. **Update `docs/index.md`.**

   - If a new object doc was created: add an entry under "Object index" with a one-line description.
   - If a new feature doc was created: add an entry under "Feature index".
   - If a new component doc was created: add an entry under "Component index" (create the section if it doesn't exist yet).
   - Update existing entries' one-line descriptions when the change meaningfully changed what the artifact does.

7. **Do NOT write to `docs/changelog/`.** The per-ticket changelog model was superseded by ADR-0010. The harness's structured Jira comment is the per-ticket record.

8. **Do NOT modify team-canon patterns or standards.** `.archon/patterns/` and `.archon/standards/` are read-only in the engagement repo (copied content per ADR-0002). If the workflow exposed a gap in team canon (e.g., the engagement needs a `lwc-jest-pattern.md`), record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate harness-repo PR.

9. **Frontmatter rules** for every doc you write or update:
   - `last_updated`: today's date (YYYY-MM-DD).
   - `last_updated_by`: `archon-run-<run-id>` if `$ARCHON_RUN_ID` is set; else the engineer's `git config user.email`.
   - `related_tickets`: append the current ticket key to the existing list (deduplicate).
   - `related_docs`: update to include any other doc this change made the current doc reference.

10. **Refuse to land empty required sections.** Object doc must have non-empty Overview, Schema, Apex automation. Feature doc must have non-empty Overview, How it works, Acceptance signals. Component doc must have non-empty Overview, Public API, Wired data (or "none" with brief explanation). If any required section comes out empty, fail this node and surface what's missing.

11. **State-vs-history scan (refuse-on-detection).** Before staging, scan every doc you wrote or edited for change-history language that violates ADR-0010. Same patterns as `sf-apex-change-document.md` step 11, plus LWC-specific:

    - `introduced with this` / `introduced in this`
    - `recently added` / `newly added`
    - `as of GRIM-` / `as of <any ticket key>` / `as of 20[0-9][0-9]-`
    - `previously` / `formerly` / `used to be` / `used to render`
    - `now renders` / `now uses` / `now exposes` (when contrasting with prior state)
    - `was added` / `was changed` / `was removed`
    - References to `../changelog/` or `docs/changelog/` in body OR frontmatter
    - Body sentences naming the current Jira ticket — ticket attribution belongs in frontmatter `related_tickets`, not in prose.

    If any pattern matches: fail this node with a structured error listing the file, line number, matched phrase, and a suggested rewrite to bare state.

    **Also enforce the external-context privacy invariant (per ADR-0015):** if `$pull-jira-context.output.external_context` is non-empty, scan every doc body for substrings of 50+ tokens that appear in the entry's `content` field. Fail if found — external context (Fathom transcripts, Drive docs) is working memory only.

12. **Link-resolution scan.** Run the link validator:

    ```bash
    bash .archon/scripts/validate-doc-links.sh docs/
    ```

    Exit code 0: continue to staging. Exit code 1: fail this node, surface the validator's output. Common LWC-specific cause: a component doc's `related_docs:` lists an object doc that wasn't created in this run because the planner judged the component didn't need its own doc.

13. **Stage the doc changes.** Run `git status --porcelain` to confirm everything is in the working tree under `docs/`. Do NOT commit.

## Output

Emit a structured JSON summary on stdout:

```json
{
  "docs_created": [
    "docs/components/renewalSummary.md"
  ],
  "docs_updated": [
    "docs/objects/Renewal__c.md",
    "docs/features/renewal-pipeline.md",
    "docs/integrations/Stripe-billing.md",
    "docs/index.md"
  ],
  "docs_unchanged_but_inspected": [
    "docs/objects/Account.md"
  ],
  "lwc_names_documented": ["renewalSummary"],
  "controller_names_documented": ["RenewalSummaryController"],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "follow_ups_recorded": false,
  "deprecated_changelog_writes_avoided": true
}
```

If `frontmatter_validation.all_required_fields_present` is `false` or `broken_related_doc_links` is non-empty, the node fails. Engineer addresses the gap and re-runs.

The `deprecated_changelog_writes_avoided` flag is a deliberate marker for the run-log: it confirms this node followed ADR-0010 and didn't fall back to the per-ticket changelog pattern.
