# `update-jira-on-completion`

You are posting the success-path Jira update for a completed workflow run. The validation gates passed, the documentation was written, and the engineer is ready to commit and push. This step closes the loop with the ticket.

## Inputs

This command is invoked in two contexts:

### Single-family context (when called from a task-family workflow directly)

- `$extract-jira-key.output.ticket` — the Jira key
- `$classify-sub-type.output` — sub_type, scope
- `$plan.output` — plan summary
- `$execute.output` — files actually changed
- `$validate.output` — test results, coverage
- `$document.output` — doc paths written/updated
- `engagement.yaml: jira.statuses` — workflow status names

### Orchestrator context (when called from sf-orchestrator per ADR-0017)

- `$extract-jira-key.output.ticket` — the Jira key
- `$invoke-families-in-sequence.output.orchestrator_run_id` — the run-id directory containing each family's family_result.json
- `$invoke-families-in-sequence.output.overall_result` — `success` (all families completed) or `failure` (one family failed; partial completion)
- The family_result.json files in `_internal/orchestrator-runs/<run-id>/` — one per family that ran. Read each to render the multi-family comment.

You detect the orchestrator context by the presence of `$invoke-families-in-sequence.output.orchestrator_run_id`. If absent, you're in single-family context.

## Tools

The `mcp-atlassian` MCP server's tools:

- `jira_add_comment` — post the structured comment
- `jira_get_transitions` — list transitions available from the current state
- `jira_transition_issue` — perform one transition
- `jira_get_issue` — re-fetch to verify the new status after each hop

Do **not** call `jira_update_issue` here.

## Task

1. **Build the structured comment.** Format as Atlassian Document Format (ADF) or markdown — sooperset/mcp-atlassian accepts both; markdown is simpler and renders well in Jira Cloud. Choose the template based on context:

### Single-family template (most runs)

   ```markdown
   ## Harness workflow run — success

   **Workflow:** sf-apex-change
   **Sub-type:** <sub_type from classify>
   **Scope:** <scope from classify>
   **Run ID:** <ARCHON_RUN_ID if set; else timestamp>
   **Engineer:** <git user.email>

   ### Files changed

   <bulleted list from $execute.output.files_changed_actual: path (operation, +N/-N)>

   ### Validation results

   - Deploy to scratch org: ✅ pass
   - Apex tests: ✅ pass (<N> tests run, <M> assertions, total duration <S>s)
   - Coverage (threshold <T>%): <per-class list with percentages>
   - FLS/CRUD static check: <pass | skipped (no SOQL/DML)>
   - Destructive change check: <pass | approved at gate ([reason])>

   ### Documentation updates

   <bulleted list of files written/updated from $document.output, with links if applicable>

   ### Next step for the engineer

   Review the working tree, commit the change with a message referencing this ticket
   (e.g., `<TICKET>: <one-line summary>`), and push the feature branch. The PR
   description should link back to this ticket.
   ```

### Multi-family template (per ADR-0017, when invoked by sf-orchestrator)

When `$invoke-families-in-sequence.output.orchestrator_run_id` is present, you're rendering the consolidated comment for an orchestrator run. Read each `_internal/orchestrator-runs/<run-id>/<family>.json` to populate the per-family sections.

   ```markdown
   ## Harness orchestrator run — <success | partial-success | failure>

   **Workflow:** sf-orchestrator
   **Families (in execution order):** sf-metadata-change → sf-apex-change → sf-permission-change
   **Run ID:** <orchestrator_run_id>
   **Engineer:** <git user.email>

   ---

   ### Family 1 of 3 — sf-metadata-change ✅
   *(Sub-type: create-field · Scope: small)*

   **Files changed:**
   - `force-app/main/default/objects/Account/fields/Revenue_Tier__c.field-meta.xml` (added, +28 lines)

   **Validation:** Deploy ✅ · FLS/CRUD ✅

   **Doc updates:**
   - `docs/objects/Account.md` (Key fields table + Sharing section)

   ---

   ### Family 2 of 3 — sf-apex-change ✅
   *(Sub-type: modify-class · Scope: small)*

   **Files changed:**
   - `force-app/main/default/classes/AccountTriggerHandler.cls` (modified, +14/-2)
   - `force-app/main/default/classes/AccountTriggerHandler_Test.cls` (modified, +35/-0)

   **Validation:** Deploy ✅ · Tests ✅ (12/12, 92% coverage) · FLS/CRUD ✅ · Destructive ✅

   **Doc updates:**
   - `docs/objects/Account.md` (Apex automation section updated)
   - `docs/features/account-management.md` (How it works step 3 updated)

   ---

   ### Family 3 of 3 — sf-permission-change ✅
   *(Sub-type: modify-permission-set · Scope: small)*

   **Files changed:**
   - `force-app/main/default/permissionsets/Sales_Manager_PS.permissionset-meta.xml` (modified, +4/-0)

   **Validation:** Deploy ✅ · No-access-removed ✅

   **Doc updates:**
   - `docs/security/permission-sets/Sales_Manager_PS.md` (FLS section updated)
   - `docs/security/sharing-model.md` (Custom Permissions map updated)

   ---

   ### Next step for the engineer

   Review the working tree (`git diff`), commit all family changes as one
   atomic commit referencing this ticket (e.g., `<TICKET>: <one-line summary>`),
   and push the feature branch. The PR description should link back to this
   ticket. Each family's individual files were modified by its respective
   workflow; the orchestrator did not commit on your behalf.
   ```

   **Partial-success variant** (when `overall_result == 'failure'` mid-run): replace the "Next step" section with:

   ```markdown
   ### ⚠️ Run did not complete — Family <N> failed

   **Family that failed:** sf-<X>-change
   **Reason:** <failed_reason from invoke-families-in-sequence>

   **Completed families left their files in the working tree.** Review the
   diff: you can keep what completed, fix the issue that broke family <N>,
   and re-run `/sf <TICKET>` (which will re-orchestrate from family 1 — each
   family is idempotent), OR `git restore` the incomplete state and re-plan.

   **Skipped families:** <N+1..end>
   ```

When the engineer re-runs after a partial-success failure, the orchestrator runs the full family sequence again. Each family's workflow is idempotent (re-running on a successful change is a no-op), so this is safe.
   ```

2. **Post the comment.** `jira_add_comment(issue_key="<TICKET>", body="<the markdown above>")`. Capture the comment id for the output payload.

   **Read-only invariant for related tickets.** `<TICKET>` is `$extract-jira-key.output.ticket` ONLY — the typed-in ticket. Even though `pull-jira-context` fetches full bodies of the parent epic, sub-tasks, and blocks-related tickets into `related_tickets_full_context`, those tickets are **context-only**. Do NOT:
   - Post comments to any related ticket.
   - Transition any related ticket.
   - Modify any field on any related ticket.

   The agent uses related-ticket content to UNDERSTAND the broader context (business intent, sibling work, blockers); its WRITES go exclusively to the typed-in ticket. If a related-ticket update is genuinely needed (e.g., a blocker now resolved), the engineer opens that ticket and runs a separate `/sf` against it.

3. **Transition the ticket toward `in_review` — walk the transition graph if a direct hop isn't available.** Jira project workflows frequently require multi-hop traversals (e.g. `Ready for Dev → In Progress → In Review`). Resolve this by BFS, bounded:

   Let `TARGET = engagement.yaml: jira.statuses.in_review`, `MAX_HOPS = 2`, and `ALLOWED_HOPS = the four named values of engagement.yaml: jira.statuses` (i.e. only hop *through* a status that the engagement has declared meaningful — never traverse stray statuses like "Won't Do" or "Blocked").

   1. **Re-fetch** the ticket with `jira_get_issue` to read the *actual* current status (the workflow may have started in `ready_for_dev` but other hops earlier in this run could have moved it).
   2. If current status already == `TARGET`, skip to step 4 with `transition_attempted: "none"`, `transition_succeeded: true`, `path_taken: []`.
   3. Call `jira_get_transitions(issue_key="<TICKET>")` to list the transitions available from the current state. Each entry has at least `id`, `name`, and `to.name` (the destination status name).
   4. **Direct hop available?** If any transition's `to.name` == `TARGET`, execute it with `jira_transition_issue(issue_key="<TICKET>", transition_id_or_name=<transition.id>)` and proceed to step 4.
   5. **One indirect hop needed.** Pick a transition whose `to.name` ∈ `ALLOWED_HOPS` (preferring `in_progress` when present — that's the canonical intermediate). Execute it. Re-fetch transitions from the new state. If `TARGET` is now directly reachable, execute that hop. Continue until reached or `MAX_HOPS` exhausted.
   6. **No path found within `MAX_HOPS` and `ALLOWED_HOPS`.** Do NOT keep traversing. Output `transition_succeeded: false`, populate `failure_reason` with the explored states + which transitions were available at each, and stop. The comment is already on the ticket — the audit trail is intact; the engineer can move the status manually.

   Record `path_taken: [<status1>, <status2>, ...]` — the sequence of `to.name` values the ticket actually moved through, ending at the final status. An empty list means no transition was attempted (already at target).

4. **Verify the final state.** Re-fetch the ticket with `jira_get_issue` and check `fields.status.name`. If it matches `TARGET`, set `current_status_after` accordingly. If it doesn't (transition reported success but the status didn't actually change — rare, but Jira automation rules can intercept), post a brief follow-up comment noting the discrepancy and emit `transition_succeeded: false` with a `failure_reason` describing the mismatch.

## Output

```json
{
  "comment_posted": true,
  "comment_id": "12345",
  "transition_attempted": "In Review",
  "transition_succeeded": true,
  "path_taken": ["In Progress", "In Review"],
  "current_status_after": "In Review",
  "failure_reason": null
}
```

`path_taken` records each intermediate status the ticket moved through (empty list if the ticket was already at target, single entry for a direct hop, multiple entries for a multi-hop traversal).

If the comment posted but the transition failed (no path within `MAX_HOPS`, or post-hop verification mismatched), return `transition_succeeded: false` and a `failure_reason` string describing the explored states and what's available. The workflow's overall result is still `success` (the user's change is good); the failure is just the Jira status not being movable, and the engineer can do it manually.
