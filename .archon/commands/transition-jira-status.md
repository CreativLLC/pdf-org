# `transition-jira-status`

You are transitioning a Jira ticket to a new status as part of a workflow's completion or failure handling. Status transitions follow the engagement's defined statuses (per `engagement.yaml: jira.statuses`); the harness does not invent statuses.

## Inputs

- `$workflow.input.ticket` — the Jira ticket key. Required.
- `$workflow.input.target_status_key` — which `engagement.yaml: jira.statuses` key to transition to. Required. One of: `ready_for_dev`, `in_progress`, `in_review`, `done`.
- `$engagement.jira.statuses` — the engagement's mapping (read from `engagement.yaml`). Required.

The harness uses the *keys* (`ready_for_dev`, etc.) as a stable abstraction; the *values* (the actual Jira status names like `"Ready for Dev"`) vary per engagement.

## Tool

Use `jira_transition_issue` from the `mcp-atlassian` MCP server.

## Task

1. **Resolve the target status name.** Read `$engagement.jira.statuses[$workflow.input.target_status_key]`. If the key is not in the engagement's statuses, fail with:
   ```
   error: unknown target_status_key "<key>"; engagement.yaml jira.statuses defines: [<known keys>].
   ```
2. **Fetch the ticket's currently available transitions.** Use `jira_get_issue` (limited fields: `status,transitions`) or call `jira_transition_issue` with `dry_run=true` if supported, otherwise the MCP exposes a transitions list via the issue endpoint.
3. **Find the transition** whose target status matches the resolved status name. Match case-insensitively to tolerate Jira config quirks.
4. **Sanity-check the transition.** Some Jira workflows have a "no-op" transition that keeps the same status. If the ticket is already in the target status, log a notice and return success without calling the MCP again:
   ```
   info: ticket already in "<status>"; no transition needed.
   ```
5. **Apply the transition.** Call `jira_transition_issue(issue_key=$ticket, transition=<matched-transition-name-or-id>)`.
6. **Verify the post-transition state.** Re-fetch the ticket's `fields.status.name`; confirm it equals the target. If it doesn't, fail with:
   ```
   error: transition applied but ticket status did not change to "<expected>" (saw "<actual>"). Check Jira workflow conditions or screen requirements.
   ```

## Output

```json
{
  "ticket_key": "ACME-101",
  "from_status": "In Progress",
  "to_status": "In Review",
  "transitioned_at": "2026-05-10T14:32:18Z",
  "transition_name": "Submit for Review"
}
```

If no transition was needed (step 4):

```json
{
  "ticket_key": "ACME-101",
  "from_status": "In Review",
  "to_status": "In Review",
  "transitioned_at": null,
  "transition_name": null,
  "note": "ticket already in target status; no transition applied"
}
```

## Failure modes

| Failure | Action |
|---|---|
| Unknown `target_status_key` | Fail per step 1. Halt. |
| Target status name not found among Jira's available transitions | Fail with: `error: ticket <KEY> has no available transition leading to "<target>". The Jira workflow may not allow this transition from the current status "<current>".` Halt. |
| Transition requires a screen / field | Jira workflows can require fields to be set during transition (e.g., a "resolution" field). The MCP will return a 400 with details. Fail with: `error: transition to "<target>" requires fields: [<list>]. Set them manually on the ticket and re-run.` Halt. |
| Auth error | Fail per the `pull-jira-context` failure-mode pattern. Halt. |
| MCP unreachable | Fail per the `pull-jira-context` failure-mode pattern. Halt. |

## Guidance

- **The harness never invents statuses.** Only transition to a status that's declared in `engagement.yaml: jira.statuses`. If a workflow needs a new status concept (e.g., "Awaiting QA"), that's an `engagement.yaml` change with a Jira project change behind it, not a workaround in this command.
- **Status mismatches** between the engagement's expected statuses and the Jira project's actual workflow are a real failure mode at engagement-setup time. The bootstrap workflow (see [ADR-0006](../decisions/0006-bootstrap-workflow-design.md)) validates this; this command assumes it's correct.
- **Don't auto-add comments here.** Posting an explanation comment is a separate `post-jira-comment` call, with its own template. Single-responsibility per command.
- **Workflow steps that call this** typically pair it with a `post-jira-comment` call (e.g., post `workflow-completed` then transition to `in_review`). The order is: post the explaining comment first, then transition. That way readers of the ticket see the explanation alongside the status change.
