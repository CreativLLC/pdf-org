# `sf-flow-change-document`

You are producing the engagement documentation updates for the Flow change just made. **Per [ADR-0010](../decisions/0010-engagement-documentation-model.md), documentation describes *current state*, not change history.** Per [ADR-0019](../decisions/0019-sf-flow-change-scope-and-gates.md) §9, this node updates the Flow's canonical doc, every object doc whose object the Flow touches, and parent/child Flow docs when subflow relationships changed.

## Inputs

- `$pull-jira-context.output` — title, description, acceptance criteria.
- `$classify-sub-type.output` — `sub_type`, `scope`, `affected_flow_names`, `touches_invocable_apex`, `touches_subflow_relationships`.
- `$plan.output`, `$ARTIFACTS_DIR/plan.md` — the plan, including `references` (objects touched, invocable Apex, subflows).
- `$execute.output`, `$ARTIFACTS_DIR/implementation.md` — what was actually done (files added / modified / deleted, status changes, fault-path coverage).
- `$validate.output` — deploy result, activation result, reference check result, test results, fault-paths result.
- `$load-engagement-context.output` — patterns/standards/object docs in scope; helpful for identifying which docs to update.

## Tools

Read, Edit, Write, Glob, Grep, Bash (for the link validator). Templates live at `docs/.harness-templates/` in the engagement repo (copied from `harness/docs-templates/` at bootstrap).

## The aggressive-update model (ADR-0010 §3, ADR-0019 §9)

For every Flow, invocable Apex class, or object touched by this run, you walk the engagement's docs and update every doc that references that artifact. Drift is the enemy.

Concretely:

1. **List every artifact this run touched** — combine `$execute.output.files_changed_actual` (file paths) with `$classify-sub-type.output.affected_flow_names` and `$plan.output.references` (invocable Apex names, objects touched, subflow names).
2. **For each artifact, identify candidate docs to update:**
   - `docs/flows/<FlowName>.md` — the canonical Flow doc (always for affected Flows).
   - `docs/objects/*.md` — for each object the Flow touches (per `$plan.output.references.objects_touched`), check whether the doc exists and update it.
   - `docs/flows/<OtherFlow>.md` — parent or child Flow docs when subflow relationships changed.
   - `docs/integrations/*.md` — when invocable Apex is part of an integration (e.g., the Flow calls a callout class).
   - `docs/features/*.md` — when the Flow change affects a feature's user-facing behavior.
3. **For deleted Flows:** `git rm docs/flows/<FlowName>.md`. Walk every other doc and remove references to the deleted Flow's name.

## Task

1. **Inventory the change.** From `$execute.output.files_changed_actual` + `$classify-sub-type.output.affected_flow_names` + `$plan.output.references`, list:
   - Flows added / modified / deleted (Flow API names).
   - Invocable Apex classes the Flow calls (names).
   - Objects the Flow touches (parsed from `<recordUpdates>` / `<recordCreates>` / `<recordDeletes>` `<object>` elements + `<start><object>` for record-triggered Flows).
   - Subflow relationships added / removed (parent → child Flow API names).
   - Status changes (`Active` → `Obsolete` for deactivations, etc.).

2. **Write or update `docs/flows/<Flow_API_Name>.md` per the canonical `flow-doc.md` template.** For each affected Flow:

   - **For `create-*` sub-types**: create the doc from `docs/.harness-templates/flow-doc.md`. Fill every required section per the canon shape (see `commands/sf-discover-document-flows.md` for the section-name discipline — `## Purpose`, `## Type and trigger`, `## What it does`, `## Side effects`, `## Error handling`, `## Dependencies`, `## Performance and limits`, `## Testing`, `## Ownership and on-call`, `## Related decisions`).
   - **For `modify-flow` / `activate-flow` / `deactivate-flow`**: update the existing doc to reflect current state. For `deactivate-flow`, the Flow's `## Type and trigger` table updates to show `Active version: (none — deactivated)` and `## What it does` may collapse to a one-line "Currently inactive. The behavior described below is the last-active version." If the engagement's convention is to delete inactive Flow docs entirely, follow that — but the default is to preserve the doc with the inactive marker so future readers can see what the Flow did when active.
   - **For `delete-flow`**: `git rm docs/flows/<FlowName>.md`.

3. **Update every `docs/objects/<Object>.md` whose object the Flow touches.** For each object in `$plan.output.references.objects_touched`:
   - Grep the object doc for the Flow's name. If referenced: update the section describing the Flow's automation on this object to reflect current state.
   - If NOT referenced AND the change adds DML on the object: add a row to the object doc's "Flow automation" section (or equivalent — section names per the engagement's object-doc template).
   - If the change is `deactivate-flow` or `delete-flow`: remove references to the Flow from the object doc. The doc should reflect what currently runs against the object, not what used to.

4. **Update parent/child Flow docs when subflow relationships changed.** If `$classify-sub-type.output.touches_subflow_relationships == 'true'`:
   - For every parent Flow that invokes the affected Flow via `<subflows>`: update the parent's `docs/flows/<Parent>.md` `## Dependencies` section to reflect the current subflow set.
   - For every child Flow (subflow): update the child's `docs/flows/<Child>.md` to reflect which parents invoke it. If the child's doc didn't yet reference the parent, add the reference under `## Dependencies` ("Invoked by: `<Parent>` Flow").

5. **Update `docs/objects/<Object>.md` for invocable-Apex changes.** If the Flow's invocable Apex calls changed (`touches_invocable_apex == 'true'`): for each Apex class added or removed as `<actionCalls type="apex">`, find the object docs that reference that class's primary object. Update the "Apex automation" section to reflect what the class now does (or that it's no longer called from the Flow).

6. **Update `docs/index.md`.**
   - For `create-*` sub-types: add an entry under "Flow index" with a one-line description of the new Flow.
   - For `delete-flow`: remove the entry from "Flow index".
   - For `modify-flow` that meaningfully changes what the Flow does: update the one-line description.
   - For `deactivate-flow`: leave the entry but annotate it `(deactivated)` per engagement convention, or remove if the engagement's convention is to hide inactive Flows from index.

7. **Do NOT modify team-canon patterns or standards.** `.archon/patterns/` and `.archon/standards/` are read-only in the engagement repo. If this run exposed a gap in the team-canon Flow pattern library, record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate PR against the harness repo.

8. **Source-file reference formatting (avoid 404s on the rendered site).** When referencing files OUTSIDE `docs/` from inside an engagement doc — `.flow-meta.xml` source, `.cls` files, `.object-meta.xml` files — do NOT write a relative markdown link. Two acceptable forms:

   1. **Inline code, no link** (preferred for prose): `` `Renewal_Auto_Create.flow-meta.xml` ``.
   2. **Absolute GitHub URL** (when the link adds real reader value): read `mkdocs.yml` once to get `repo_url:`, then write `[Renewal_Auto_Create.flow-meta.xml](<repo_url>/blob/main/force-app/main/default/flows/Renewal_Auto_Create.flow-meta.xml)`.

   Relative links between docs *inside* `docs/` (flow → object, object → flow, parent flow → subflow) work normally — the rule above is only for paths leaving the docs tree.

9. **Frontmatter rules** for every doc you write or update:
   - `last_updated`: today's date (YYYY-MM-DD).
   - `last_updated_by`: `archon-run-<run-id>` if `$ARCHON_RUN_ID` is set; else the engineer's `git config user.email`.
   - `related_tickets`: append the current ticket key to the existing list (deduplicate).
   - `related_docs`: update to include any other doc this change made the current doc reference.

10. **Refuse to land empty required sections.** Per the `flow-doc.md` canon, every section is REQUIRED. If `## Testing` would be empty for a screen Flow, write `_No automated test coverage._` — do NOT omit. If `## Side effects` would be empty for a Flow that only reads data, write `_No side effects beyond the triggering record._` — do NOT omit. Refuse to write a Flow doc whose required sections are blank.

11. **State-vs-history scan (refuse-on-detection).** Before staging, scan every doc you wrote or edited for change-history language that violates ADR-0010. The pattern is identical to `sf-apex-change-document.md` step 11. Forbidden patterns (case-insensitive):

    - `introduced with this` / `introduced in this`
    - `recently added` / `newly added`
    - `as of GRIM-` / `as of <any ticket key>` / `as of 20[0-9][0-9]-`
    - `previously` / `formerly` / `used to be` / `used to fire`
    - `now fires` / `now does` / `now uses` (when contrasting with a prior state)
    - `was added` / `was changed` / `was removed`
    - References to `../changelog/` or `docs/changelog/` in body OR frontmatter `related_docs:`
    - Body sentences naming the current Jira ticket (ticket attribution belongs in frontmatter `related_tickets:`, not in prose).

    If any pattern matches: **fail this node with a structured error** listing the file, line number, matched phrase, and a suggested rewrite. The engineer addresses each match and re-runs.

    **External-context privacy invariant per ADR-0015:** if `$pull-jira-context.output.external_context` is non-empty, scan every doc body for substrings of 50+ tokens that appear in the entries' `content` fields. If found, fail with a structured error: external context is working memory only — replace verbatim quotes with paraphrase + citation.

12. **Link-resolution scan.** Run the link validator against the docs tree:

    ```bash
    bash .archon/scripts/validate-doc-links.sh docs/
    ```

    Exit 0: continue. Exit 1: broken links — fail this node, surface the validator output, let the engineer fix and re-run.

13. **Stage the doc changes.** Run `git status --porcelain` to confirm everything is in the working tree under `docs/`. Do NOT commit — the engineer commits the whole change (Flow XML + docs) as one commit after the Jira write-back step succeeds.

## Output

Emit a structured JSON summary on stdout:

```json
{
  "docs_created": [
    "docs/flows/Renewal_Auto_Create.md"
  ],
  "docs_updated": [
    "docs/objects/Renewal__c.md",
    "docs/objects/Account.md",
    "docs/index.md"
  ],
  "docs_removed": [],
  "docs_unchanged_but_inspected": [
    "docs/flows/Renewal_Reminder.md"
  ],
  "subflow_relationships_documented": [],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "follow_ups_recorded": false
}
```

If `frontmatter_validation.all_required_fields_present` is `false` or `broken_related_doc_links` is non-empty, the node fails. Engineer addresses the gap and re-runs.

## On state-vs-history (worth re-reading)

The most common pitfall here is writing change-history language into a state doc. Examples of what NOT to write in a Flow doc:

- "As of GRIM-201, this Flow was deactivated."
- "Previously, this Flow fired on insert; now it fires on insert and update."
- "We added a record-update element to handle the new Stage__c field."

Equivalents that ARE state-of-the-org:

- "The Flow is currently inactive. The behavior below describes the last-active version."
- "This Flow fires on insert and update."
- "The Flow's record-update element sets `Stage__c` to `Submitted` when [condition]."

The change history of "this used to be different" lives in `git log` for the doc and in the Jira ticket that changed it. The doc itself is the present tense.
