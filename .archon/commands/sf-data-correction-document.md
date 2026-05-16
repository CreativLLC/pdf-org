# `sf-data-correction-document`

You are NOT producing engagement documentation updates for the data correction itself. **Per [ADR-0023](../decisions/0023-sf-data-correction-scope-and-gates.md) §5 and [ADR-0010](../decisions/0010-engagement-documentation-model.md)'s state-not-history rule, data corrections are *events*, not state.** State docs (`docs/objects/*`, `docs/features/*`, `docs/flows/*`, `docs/integrations/*`) are NOT touched by this phase.

The correction's event record lives in:

- **The Jira comment** posted by `update-jira-on-completion.md` — structured detail (sub-type, dry-run vs actual count, sample IDs, artifact paths, dollar cost).
- **`_internal/harness-runs.log`** — durable in-repo run trace.
- **`_internal/cost-log.jsonl`** — cost record per [ADR-0016](../decisions/0016-cost-observability.md).
- **`$ARTIFACTS_DIR/`** — `correction.apex`, `correction-dry-run.apex`, `data-correction-dry-run.json`, `data-correction-deleted-ids.json` (for deletes). Run-scoped; not committed.

**The ONLY doc this phase may write** is an optional engagement ADR proposing an *upstream fix* for a recurring data-quality issue. That decision belongs to the planner (`$plan.output.recurring_pattern_flag`), not this phase — your job is to draft the ADR when the planner flagged the pattern.

## Inputs

- `$plan.output` — especially `recurring_pattern_flag` and `recurring_pattern_root_cause`
- `$classify-sub-type.output` — `sub_type`, `recurring_pattern_flag`
- `$validate.output` — dry-run and actual counts, sample IDs, deleted-IDs artifact path (for deletes)
- `$execute.output` — Apex artifact paths (for the Jira comment's links; the artifacts themselves stay in `$ARTIFACTS_DIR/`)
- `$pull-jira-context.output` — ticket title, description; ticket-history context informing whether this is recurring
- `$load-engagement-context.output` — to identify the next available engagement-ADR number

## Tools

Read, Write, Glob, Grep. The ADR template lives at `docs/.harness-templates/adr.md` (copied from the harness's `docs-templates/adr.md` at bootstrap). No git operations. No Jira writes.

## Task

### Step 1 — Decide whether to write the optional ADR

Read `$plan.output.recurring_pattern_flag`. If `"false"` (or absent), skip the rest of this command. Emit the no-op output (see below).

If `"true"`, also require `$plan.output.recurring_pattern_root_cause` to be a non-null paragraph. If it's null, fail this node with: `recurring_pattern_flag was true but recurring_pattern_root_cause is missing; planner must provide both`. The engineer re-runs after the planner is fixed.

### Step 2 — Identify the next engagement-ADR number

List `docs/decisions/*.md` in the engagement repo. Find the highest 4-digit NNNN prefix. The new ADR is `NNNN+1`. If no existing ADRs, start at `0001`.

The ADR path is `docs/decisions/<NNNN>-prevent-<root-cause-slug>.md` where `<root-cause-slug>` is a kebab-case slug derived from `$plan.output.recurring_pattern_root_cause` (max 5 words; e.g., "stale-renewal-status-on-close", "owner-not-set-on-import").

### Step 3 — Draft the ADR

Read the template `docs/.harness-templates/adr.md`. Fill it in:

#### Frontmatter

```yaml
---
title: "<NNNN>: Prevent recurring <root-cause-summary>"
audience: public
last_updated: <today YYYY-MM-DD>
last_updated_by: <archon-run-<id> if $ARCHON_RUN_ID set; else git config user.email>
related_tickets: [<TICKET-KEY>]
related_docs: []
---
```

#### Sections

**Status:** `Proposed — <today>. (Draft authored by sf-data-correction-document after a recurring-pattern flag was set by the planner. Engineer to refine and accept.)`

**Context and problem statement:**

A short paragraph derived from `$plan.output.recurring_pattern_root_cause`:

- What is the recurring data-quality issue? (Template form: "Records on `<Object>` are repeatedly ending up with `<Field> = <wrong-value>` despite multiple manual corrections.")
- What corrections have been run? (Cite this ticket key and any prior tickets the planner referenced.)
- What is the cost? (Approximate: "Each correction is a `sf-data-correction` run averaging $X and affecting ~N records.")

**Decision drivers:**

Three to five bullets. Examples:

- Corrections fix data, not design. Recurring corrections indicate the upstream is broken.
- The harness has run this correction <N> times in the past <window>; the trend is not improving.
- The proposed upstream fix is mechanically describable (a trigger condition to add, a validation rule to enforce, a Flow path to correct).
- Implementing the upstream fix is bounded work that can be scoped as a `sf-apex-change` or `sf-flow-change` ticket.

**Considered options:**

At minimum two:

1. **Continue running data corrections as needed.** Pros: zero engineering effort. Cons: ongoing cost, ongoing risk, doesn't address root cause.
2. **Fix the upstream cause.** Pros: stops the bleeding permanently. Cons: requires engineering work; risk of new bugs.

If the planner identified a specific upstream artifact (a named trigger / Flow / validation rule), add option 3:

3. **Specific fix:** (per the planner) — e.g., "Add `Status__c = 'Closed'` skip-condition to `RenewalTriggerHandler.beforeUpdate()`." Pros: directly addresses the root cause. Cons: requires testing the regression case.

**Decision:**

`Proposed — Option 2 (fix the upstream cause)` if the planner identified a specific artifact. Otherwise `Proposed — Option 2 (fix the upstream cause); specific implementation TBD by engineer.`

Mark the ADR as `Proposed` (not `Accepted`) — the engineer reviews this draft and accepts or refines it via a follow-up ticket.

**Consequences:** brief; "Accepting this decision means filing a `sf-apex-change` or `sf-flow-change` ticket to implement the fix. Pending acceptance, this draft remains as a reminder of the recurring pattern."

**References:** include a link to this ADR's source ticket (`related_tickets: [<TICKET-KEY>]` in frontmatter is the canonical reference).

**History:**

`- <today>: drafted by sf-data-correction-document workflow on <TICKET-KEY> run. Status Proposed pending engineer acceptance.`

### Step 4 — State-vs-history scan

Per [ADR-0010](../decisions/0010-engagement-documentation-model.md) §3 and `sf-apex-change-document.md` §11: scan the drafted ADR for change-history language. The ADR's `History` section is the ONE place change-history language is acceptable (it's the standard MADR pattern). Elsewhere in the ADR, forbid:

- "introduced with this", "newly added", "recently added"
- "as of <date>"
- "previously", "formerly", "used to be", "now does X" (when contrasting with prior state)
- "was added", "was changed", "was removed"
- References to `../changelog/` or `docs/changelog/`
- Body sentences naming the current Jira ticket outside the `related_tickets:` frontmatter and the `History:` section

If matches found in the body sections (not History): fail this node with a structured error listing each match (`file:line: matched-phrase → suggested rewrite`). Engineer addresses and re-runs.

### Step 5 — Link-resolution scan

The drafted ADR's `related_docs:` frontmatter starts empty. The engineer may add links during refinement. For now, the link validator runs and confirms no broken links. The empty list is fine.

```bash
bash .archon/scripts/validate-doc-links.sh docs/
```

Exit code 0: continue. Exit code 1: fail this node, surface the validator output.

### Step 6 — DO NOT touch state docs

Confirm via `git status --porcelain` that the ONLY change in `docs/` is the new ADR file. If anything else changed (especially `docs/objects/*`, `docs/features/*`, `docs/flows/*`, `docs/integrations/*`, `docs/index.md`), fail with:

```
state docs were modified by sf-data-correction-document — ADR-0023 §5 forbids
this. Data corrections are events, not state. Reset the engagement source tree
and re-run, or refine the planner's recurring_pattern_root_cause output.
```

The engagement source tree should also be untouched (no `force-app/` changes). The Apex artifacts live in `$ARTIFACTS_DIR/`, not in the engagement source tree.

### Step 7 — Frontmatter validation

Per `sf-apex-change-document.md` §10: refuse to land empty required sections. The drafted ADR must have non-empty Context, Decision drivers, Considered options, Decision, Consequences sections. If any are empty (the planner's `recurring_pattern_root_cause` was too thin to derive content from), fail this node with the missing-sections list.

## Output

Emit a structured JSON summary on stdout:

```json
{
  "recurring_pattern_acted_on": true,
  "docs_created": ["docs/decisions/<NNNN>-prevent-<root-cause-slug>.md"],
  "docs_updated": [],
  "docs_unchanged_but_inspected": [],
  "state_docs_untouched": true,
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "follow_ups_recorded": false,
  "docs_updated_count": 1
}
```

If `$plan.output.recurring_pattern_flag == "false"`, the no-op output:

```json
{
  "recurring_pattern_acted_on": false,
  "docs_created": [],
  "docs_updated": [],
  "docs_unchanged_but_inspected": [],
  "state_docs_untouched": true,
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "follow_ups_recorded": false,
  "docs_updated_count": 0,
  "note": "No documentation written. Data corrections are events; the Jira comment + run-log + cost-log are the records."
}
```

The Jira write-back step (`update-jira-on-completion`) handles the rest — posting the structured comment with sub-type, dry-run vs actual count, sample IDs, artifact paths. That is the canonical record of the correction event. State docs do not change.

## On state-vs-history (worth re-reading)

This command is the most aggressively-light document phase in the harness. The temptation is to write something — *anything* — to the state docs, on the theory that "a record of what happened" belongs there. **That theory is wrong** for data corrections specifically.

A correction doesn't change what the object IS. The object's *state* after the correction (field X has value Y for records matching Z) is the same shape it had before; only the values changed. Documenting "on 2026-05-15 we set 234 Account.Status fields to 'Active'" in `docs/objects/Account.md` would:

1. Violate the state-not-history rule explicitly.
2. Accumulate forever (every correction adds a new history line).
3. Compete with `git log` and the Jira ticket trail for authority.

The Jira comment is the rich detail. The harness's run-log is the durable in-repo trace. The cost-log captures the dollar cost. The artifact directory holds the Apex source. None of these are state docs. That's the correct shape.

The optional engagement ADR is the one exception, and it's not documenting the correction — it's documenting the *decision to fix the upstream cause*. That's an architectural decision, which is exactly what `docs/decisions/` is for. The ADR's body talks about the upstream artifact (the trigger, the Flow), not the correction's record IDs or field values.
