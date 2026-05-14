# `update-jira-on-completion`

You are posting the success-path Jira update for a completed workflow run. The validation gates passed, the documentation was written, and the engineer is ready to commit and push. This step closes the loop with the ticket.

## Inputs

- `$extract-jira-key.output.ticket` — the Jira key
- `$classify-sub-type.output` — sub_type, scope
- `$plan.output` — plan summary
- `$execute.output` — files actually changed
- `$validate.output` — test results, coverage
- `$document.output` — doc paths written/updated
- `engagement.yaml: jira.statuses` — workflow status names for this engagement

## Tools

The `mcp-atlassian` MCP server's tools:

- `jira_add_comment` — post the structured comment
- `jira_transition_issue` — transition the ticket

Do **not** call `jira_update_issue` here.

## Task

1. **Build the structured comment.** Format as Atlassian Document Format (ADF) or markdown — sooperset/mcp-atlassian accepts both; markdown is simpler and renders well in Jira Cloud. Template:

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

2. **Post the comment.** `jira_add_comment(issue_key="<TICKET>", body="<the markdown above>")`.
3. **Transition the ticket.** From the current status to `engagement.yaml: jira.statuses.in_review`. Use `jira_transition_issue(issue_key="<TICKET>", transition_id_or_name="<status name>")`. If the transition isn't directly available from the current state (Jira workflows can require multi-hop), fail with a structured error explaining what manual step the engineer needs to take — but the comment is already posted, so the audit trail is intact.
4. **Verify the transition.** Re-fetch the ticket via `jira_get_issue` and check that `fields.status.name` matches the expected `in_review` value. If not, post a follow-up comment noting the discrepancy.

## Output

```json
{
  "comment_posted": true,
  "comment_id": "12345",
  "transition_attempted": "In Review",
  "transition_succeeded": true,
  "current_status_after": "In Review"
}
```

If the comment posted but the transition failed, return `transition_succeeded: false` and a `failure_reason` string. The workflow's overall result is still `success` (the user's change is good); the failure is just the Jira status not being movable, and the engineer can do it manually.
