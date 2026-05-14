# `update-jira-on-failure`

You are posting the failure-path Jira update. This fires when validation failed, a gate aborted, or the workflow stopped before completion. The audit trail records what happened and transitions the ticket back to a workable state so the engineer can fix and retry.

## Inputs

- `$extract-jira-key.output.ticket` — the Jira key
- `$classify-sub-type.output` — sub_type (may be partial if the workflow stopped early)
- `$plan.output` *(may be empty if workflow stopped pre-plan)*
- `$execute.output` *(may be empty)*
- `$validate.output` *(may be partial — e.g., deploy failed before tests ran)*
- `$gate-pre-execute.output` *(present only if that gate ran)*
- `$gate-post-validate.output` *(present only if that gate ran)*
- `engagement.yaml: jira.statuses` — workflow status names

## Tools

`mcp-atlassian`: `jira_add_comment`, `jira_transition_issue`. Same as the success path; only the message body and target transition differ.

## Task

1. **Determine the failure reason.** Inspect inputs in order — the first present-and-failing one is the reason:

   | Source | Failure reason |
   |---|---|
   | `gate-pre-execute.proceed == 'false'` | Engineer aborted at the pre-execute gate (display the gate's trigger and the engineer's reasoning) |
   | `validate.deploy_result == 'fail'` | Deploy to scratch org failed (include first error from deploy artifact) |
   | `validate.tests_result == 'fail'` | Apex tests failed or coverage below threshold (include failing test names and per-class coverage) |
   | `validate.destructive_result == 'fail'` and the pre-gate didn't approve it | Destructive change detected and not approved |
   | `validate.fls_crud_result == 'fail'` and post-gate aborted | FLS/CRUD check failed and not overridden |
   | `gate-post-validate.proceed == 'false'` | Engineer aborted at the post-validate gate |

2. **Build the structured failure comment:**

   ```markdown
   ## Harness workflow run — failure

   **Workflow:** sf-apex-change
   **Sub-type:** <sub_type, or "(unclassified)" if workflow stopped pre-classify>
   **Run ID:** <ARCHON_RUN_ID if set; else timestamp>
   **Engineer:** <git user.email>
   **Stopped at:** <node id where the failure originated>

   ### What went wrong

   <one-paragraph failure summary>

   ### Details

   <reason-specific detail block — e.g., for tests:>

       Failing tests:
         - RenewalCalculator_Test.test_handlesNullDate (NullPointerException at line 47)
         - RenewalCalculator_Test.test_bulkInsert (Too many SOQL queries: 101)

       Coverage (threshold 75%):
         - RenewalCalculator: 62% ← below threshold

   ### What was preserved

   - Working tree: <"changes intact" | "rolled back" — depends on which stage failed>
   - Documentation: <"not written" | "partial">
   - Scratch org: <"left running for inspection" | "not created">

   ### Next step

   Fix the failures and re-run `/sf <TICKET> "<description>"`. The harness will
   create a fresh run; this failed run remains in the audit trail.
   ```

3. **Post the comment.** `jira_add_comment(issue_key="<TICKET>", body="<the markdown above>")`.

4. **Transition the ticket back to a workable state.** Target `engagement.yaml: jira.statuses.ready_for_dev`. If the ticket is currently in `in_progress`, this transition is usually available; if not, post a note explaining the engineer should reset the status manually.

5. **Do NOT close the ticket on failure.** Even if the workflow can't proceed, the ticket itself remains the engineer's anchor for the work — a failed harness run doesn't mean the work doesn't need doing.

## Output

```json
{
  "comment_posted": true,
  "comment_id": "12346",
  "failure_reason": "tests_failed_coverage_below_threshold",
  "transition_attempted": "Ready for Dev",
  "transition_succeeded": true,
  "current_status_after": "Ready for Dev"
}
```
