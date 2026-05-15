# `pull-jira-context`

You are pulling the Jira ticket that drives this workflow run. The ticket is the **authoritative spec** for what work is being done. The free-form prompt the user typed when invoking the workflow is *additional context*, not the spec.

## Inputs

Resolved by Archon from the upstream `extract-jira-key` node (every workflow that uses this command declares one — see `workflows/sf-dispatcher.yaml` and `workflows/sf-apex-change.yaml`):

- `$extract-jira-key.output.ticket` — the Jira ticket key (e.g., `ACME-101`). Required. Format: `<PROJECT>-<NUMBER>`.
- `$extract-jira-key.output.description` — the engineer's free-form description, if provided. Optional.

## Tools

Use the `mcp-atlassian` MCP server's tools:

- `jira_get_issue` — fetch the ticket itself.
- `jira_search` (JQL) — fetch linked tickets *only if* the ticket has explicit `linkedIssues` we should also read.

Do **not** call `jira_create_issue`, `jira_update_issue`, `jira_add_comment`, or `jira_transition_issue` from this command. Those are owned by other commands run later.

## Task

1. **Validate the ticket key format.** Must match `^[A-Z][A-Z0-9]+-\d+$`. If not, fail with:
   ```
   error: invalid ticket key format. Expected like ACME-101.
   ```
2. **Fetch the ticket** with `jira_get_issue(issue_key=$extract-jira-key.output.ticket, fields="summary,description,status,labels,issuetype,assignee,reporter,priority,components,fixVersions,comment,issuelinks,customfield_10000_to_10100")`. The wildcard fields cover most engagement-relevant custom fields; if the engagement's `engagement.yaml` declares additional custom field IDs to read, include those.
3. **Check the status is workable.** The ticket's status must match one of the `engagement.yaml: jira.statuses` values that indicate work can start (`ready_for_dev` or `in_progress`). If it's `done`, `in_review`, or any other state, fail with:
   ```
   error: ticket <KEY> is in status "<STATUS>"; expected one of [<workable statuses>]. Refusing to start work.
   ```
4. **Extract structured fields**:
   - `title` — `fields.summary`
   - `description` — `fields.description` (Atlassian Document Format; render to plain text or markdown)
   - `acceptance_criteria` — if the description contains a section titled "Acceptance Criteria" or similar, extract its bullets. Some engagements use a custom field for AC; check `engagement.yaml: jira.acceptance_criteria_field` if defined.
   - `labels` — `fields.labels`
   - `task_type_label` — if any label is prefixed `task-type:` (e.g., `task-type:sf-apex-change`), extract the value. This is the **structured routing hint** from [ADR-0001](../decisions/0001-dispatcher-and-router-design.md).
   - `linked_tickets` — `fields.issuelinks` (just the keys + link types)
   - `recent_comments` — last 5 comments (author, created, body)
   - `current_status` — `fields.status.name`
5. **Fetch linked tickets' summaries** if `linked_tickets` is non-empty, using a single `jira_search` with JQL `key in (KEY1, KEY2, ...)`. Don't fetch the full body; just summary + status. This gives the workflow context without bloating the agent's context.

## Output

Emit a structured JSON object on stdout. Workflow downstream nodes consume this:

```json
{
  "ticket_key": "ACME-101",
  "title": "Add renewal_date field to Account",
  "description": "...",
  "acceptance_criteria": [
    "Field is required on the Account create page layout",
    "Field is editable by Sales Manager profile",
    "Tests cover both null and populated values"
  ],
  "labels": ["task-type:sf-metadata-change", "priority-high"],
  "task_type_label": "sf-metadata-change",
  "current_status": "Ready for Dev",
  "issue_type": "Story",
  "priority": "Medium",
  "linked_tickets": [
    { "key": "ACME-99", "type": "blocks", "summary": "Renewal__c object created", "status": "Done" }
  ],
  "recent_comments": [
    { "author": "alice@firm.com", "created": "2026-05-08T14:23:00Z", "body": "Confirmed with Acme PM — field is required, not optional." }
  ],
  "reporter": "pm@firm.com",
  "assignee": null
}
```

## Failure modes

| Failure | Action |
|---|---|
| MCP server unreachable | Fail with: `error: mcp-atlassian MCP server unreachable. Run 'uvx mcp-atlassian' to verify, check JIRA_URL / JIRA_API_TOKEN.` Halt the workflow. |
| 401 auth error | Fail with: `error: Jira auth failed. Regenerate API token at id.atlassian.com.` Halt. |
| 404 ticket not found | Fail with: `error: ticket <KEY> not found. Check spelling and that it belongs to project <expected from engagement.yaml>.` Halt. |
| Ticket too vague (no AC, description < 20 chars) | Fail with: `error: ticket <KEY> is too vague to action — no acceptance criteria and short description. Comment posted asking reporter to clarify.` *Also* invoke `post-jira-comment` with template `vague-ticket-clarification-request`. Halt. |
| Status not workable | Fail per step 3 above. Halt. |

## Guidance

- This command is **read-only**. It must not modify Jira state under any circumstance.
- Be conservative about AC extraction. If the description's structure is ambiguous, prefer to return `acceptance_criteria: []` and let downstream nodes' classifier decide whether the ticket has enough detail.
- Keep the output compact. The workflow's downstream classifier and planner read this; bloating it costs context budget on every later step.
