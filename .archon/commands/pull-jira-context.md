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
   - `linked_tickets` — `fields.issuelinks` (just the keys + link types — summary only)
   - `parent_ticket_key` — `fields.parent.key` if set, or extract from Epic Link customfield (`customfield_10014` in classic projects, `fields.parent` in team-managed). Null if no parent.
   - `subtask_keys` — `fields.subtasks[].key` (array of keys, possibly empty)
   - `recent_comments` — last 5 comments (author, created, body)
   - `current_status` — `fields.status.name`

5. **Fetch related-ticket FULL CONTEXT** — per the read-only context model. The goal: the agent should reason like a real engineer, "let me check the parent epic and sister sub-tasks before I start." Fetch full body (description + AC + recent comments) for these relationships:

   | Relationship | Fetch full body? | Source |
   |---|---|---|
   | Parent epic / parent story | **Yes** | `parent_ticket_key` |
   | Sub-tasks | **Yes** (each) | `subtask_keys` |
   | `blocks` / `is blocked by` / `depends on` issue links | **Yes** | `linked_tickets` filtered by link type name |
   | `relates to` / `duplicates` | Summary only (already in `linked_tickets`) | — |
   | `clones` | Skip — redundant content | — |

   Cap: max 7 related tickets fetched full-body. If the cap would be exceeded, prioritize parent → sub-tasks → blocks/depends and skip the rest with a `related_tickets_skipped` note in output.

   Use a single `jira_search` with JQL `key in (KEY1, KEY2, ...)` per the bulk-fetch pattern to keep this efficient. Request fields: `summary,description,status,issuetype,acceptance_criteria_field` (only what you need).

   Build a `related_tickets_full_context` array. Each entry has:
   ```json
   {
     "key": "ASC-100",
     "relationship": "parent-epic" | "subtask" | "blocks" | "depends-on" | "blocked-by",
     "title": "<summary>",
     "status": "<status>",
     "issue_type": "Epic" | "Story" | "Task" | "Sub-task" | "Bug",
     "description": "<rendered body>",
     "acceptance_criteria": [...] | null
   }
   ```

   **Read-only invariant.** Downstream nodes (classify, plan, execute, document, update-jira) treat `related_tickets_full_context` as CONTEXT ONLY. The agent never modifies, comments on, or transitions any ticket in this array. Only `$extract-jira-key.output.ticket` (the typed-in ticket) is mutated. This is enforced in `update-jira-on-completion.md` step 2 — the comment goes only to the typed-in ticket, never to parents or sub-tasks.

5b. **External context extraction (per ADR-0015).** The "real spec" for a ticket often lives outside Jira — a Fathom recording, a Google Drive doc, a Loom walkthrough. Pull those in as additional context. Sources, in priority order:

   1. **`## Context` (or `## References`) section** in the ticket description. Extract every markdown link target.
   2. **Optional custom field** if `engagement.yaml: jira.context_field:` is set. Read that field's value; extract markdown links from it.
   3. **Inline `--context URL` flag** in `$ARGUMENTS` (passed by the dispatcher when present at slash-command invocation).

   Dedupe by host+path. For each URL, classify by host and fetch:

   | Host pattern | Fetcher |
   |---|---|
   | `docs.google.com/document`, `drive.google.com` | Google Drive MCP if present in `.mcp.json`; else skip with reason |
   | `fathom.video/share` | WebFetch (public share URL) |
   | `loom.com/share` | WebFetch |
   | `*.atlassian.net/wiki` | sooperset/mcp-atlassian MCP |
   | `notion.so` | WebFetch (public) |
   | Any other public URL | WebFetch with a 30s timeout |
   | Auth-gated / unreachable | Skip with reason in `external_context_skipped` |

   For each successful fetch, emit:

   ```json
   {
     "url": "https://...",
     "host_category": "fathom" | "google-drive" | "loom" | "confluence" | "notion" | "web",
     "title": "<extracted page/doc title or filename>",
     "fetched_at": "<ISO 8601 UTC>",
     "content_excerpt": "<first 200 chars of rendered text>",
     "content": "<full rendered text>",
     "estimated_tokens": <int>
   }
   ```

   For each skipped URL:

   ```json
   {
     "url": "https://...",
     "reason": "<short message, e.g. 'auth required', 'fetch timeout', 'mcp not installed'>"
   }
   ```

   Output the arrays as `external_context` and `external_context_skipped` in the structured response.

   **Privacy invariants:** external_context content is **working memory only**. Downstream nodes use it to reason; they MUST NOT echo it verbatim into:
   - Jira comments (`update-jira-on-completion` references source URLs, never content)
   - Commit messages
   - Engagement docs (`docs/objects/*.md`, etc.)
   - ADRs (cite the URL as the source; don't paste content)

   The state-vs-history scan in `sf-apex-change-document.md` is the enforcement point — it flags substrings from `external_context` that appear in doc bodies.

   **Cap and budget:** if `external_context` total exceeds 100K tokens, stop fetching and record the rest as skipped with reason "context-budget-exceeded". The `confirm-external-context` gate node (per ADR-0015) shows the engineer what was fetched and the estimated cost; they can drop items before the workflow proceeds.

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
  "parent_ticket_key": "ACME-50",
  "subtask_keys": ["ACME-102", "ACME-103"],
  "linked_tickets": [
    { "key": "ACME-99", "type": "blocks", "summary": "Renewal__c object created", "status": "Done" },
    { "key": "ACME-200", "type": "relates to", "summary": "Q3 renewal pipeline cleanup", "status": "In Progress" }
  ],
  "related_tickets_full_context": [
    {
      "key": "ACME-50",
      "relationship": "parent-epic",
      "title": "Renewal pipeline foundation",
      "status": "In Progress",
      "issue_type": "Epic",
      "description": "<rendered epic body>",
      "acceptance_criteria": null
    },
    {
      "key": "ACME-102",
      "relationship": "subtask",
      "title": "Add Page Layout assignment for renewal_date",
      "status": "Done",
      "issue_type": "Sub-task",
      "description": "<rendered subtask body>",
      "acceptance_criteria": ["Renewal Manager layout shows the field"]
    },
    {
      "key": "ACME-99",
      "relationship": "blocks",
      "title": "Renewal__c object created",
      "status": "Done",
      "issue_type": "Story",
      "description": "<rendered prereq body>",
      "acceptance_criteria": [...]
    }
  ],
  "related_tickets_skipped": [],
  "external_context": [
    {
      "url": "https://fathom.video/share/abc123",
      "host_category": "fathom",
      "title": "Sales call with Meditrina — PDF builder requirements",
      "fetched_at": "2026-05-14T15:00:00Z",
      "content_excerpt": "Customer described the exact discount band rules; supports up to 6 discount tiers...",
      "content": "<full rendered transcript>",
      "estimated_tokens": 12400
    }
  ],
  "external_context_skipped": [
    {
      "url": "https://example.internal.acme.com/spec",
      "reason": "auth required"
    }
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
