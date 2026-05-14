# `post-jira-comment`

You are posting a **structured comment** to a Jira ticket at a defined workflow checkpoint. Comments follow templates so they're skimmable and consistent across all engagements. They are NOT free-form chat.

## Inputs

- `$workflow.input.ticket` — the Jira ticket key. Required.
- `$workflow.input.comment_template` — which template to apply. Required. One of:
  - `workflow-started`
  - `plan-posted` (the plan itself goes in `plan_markdown`)
  - `gate-awaiting-approval`
  - `validation-passed`
  - `validation-failed`
  - `workflow-completed`
  - `workflow-failed`
  - `vague-ticket-clarification-request`
- Template-specific inputs (see each template below).

## Tool

Use `jira_add_comment` from the `mcp-atlassian` MCP server.

## Templates

Render the chosen template with the inputs, then post the rendered body. Use Atlassian's wiki-markup or Markdown — `mcp-atlassian` handles conversion to Atlassian Document Format. Keep markdown simple (headings, bullets, code blocks, links) — Jira's renderer is finicky with complex markdown.

### `workflow-started`

Inputs: `workflow_name`, `run_id`, `engineer`, `engagement_alias`.

```markdown
🟢 **Harness workflow started:** `{{workflow_name}}`

- **Run ID:** `{{run_id}}`
- **Engineer:** {{engineer}}
- **Engagement:** {{engagement_alias}}
- **Started at:** {{utc_timestamp}}

Will post updates here at each checkpoint. If this run is unexpected or you want to abort it, contact the engineer.
```

### `plan-posted`

Inputs: `workflow_name`, `run_id`, `plan_markdown`, `classification_summary`.

```markdown
📋 **Plan posted for review**

**Classification:** {{classification_summary}}

**Plan:**

{{plan_markdown}}

---
*Workflow `{{workflow_name}}` run `{{run_id}}`. The workflow is paused at the gate until approval is granted (see next comment).*
```

### `gate-awaiting-approval`

Inputs: `workflow_name`, `run_id`, `approval_command`, `risk_summary`.

```markdown
🟡 **Gate: awaiting approval**

**Risk summary:** {{risk_summary}}

To approve and continue this workflow, run on your machine:
```
{{approval_command}}
```

Or reply to this comment with `/approve` (if the engagement repo has the Jira webhook listener enabled — Phase 6+).

---
*Workflow `{{workflow_name}}` run `{{run_id}}`. The run remains paused until you do one of the above.*
```

### `validation-passed`

Inputs: `workflow_name`, `run_id`, `validation_summary` (markdown — coverage, tests passing, FLS check results, etc.).

```markdown
✅ **Validation passed**

{{validation_summary}}

---
*Workflow `{{workflow_name}}` run `{{run_id}}`. Proceeding to documentation step.*
```

### `validation-failed`

Inputs: `workflow_name`, `run_id`, `failure_summary` (markdown), `next_steps`.

```markdown
❌ **Validation failed**

{{failure_summary}}

**Next steps:**

{{next_steps}}

---
*Workflow `{{workflow_name}}` run `{{run_id}}`. The run has halted. The ticket status has been left unchanged.*
```

### `workflow-completed`

Inputs: `workflow_name`, `run_id`, `pr_url`, `files_changed_summary`, `doc_updates` (list of relative paths), `next_status`.

```markdown
✅ **Workflow completed**

**PR:** {{pr_url}}

**Changes:**

{{files_changed_summary}}

**Doc updates:**

{{#doc_updates}}
- `{{.}}`
{{/doc_updates}}

**Ticket transition:** moved to `{{next_status}}`.

---
*Workflow `{{workflow_name}}` run `{{run_id}}`. Awaiting code review on the PR.*
```

### `workflow-failed`

Inputs: `workflow_name`, `run_id`, `failure_step`, `failure_message`, `remediation`.

```markdown
🚨 **Workflow failed**

**Failed step:** `{{failure_step}}`

**Reason:**

{{failure_message}}

**Suggested remediation:**

{{remediation}}

---
*Workflow `{{workflow_name}}` run `{{run_id}}`. The ticket status has been left unchanged. Engineer attention required.*
```

### `vague-ticket-clarification-request`

Inputs: `workflow_name`, `run_id`, `specific_gaps` (list of strings describing what's missing).

```markdown
🤔 **Ticket needs clarification before work can begin**

The harness workflow `{{workflow_name}}` refused to start because the ticket lacks enough detail to act on safely. Specifically:

{{#specific_gaps}}
- {{.}}
{{/specific_gaps}}

Please update the ticket with this information and re-trigger the workflow.

---
*Workflow `{{workflow_name}}` run `{{run_id}}`. This is a structured refusal — the harness is designed to push back on vague tickets rather than guess.*
```

## Task

1. **Validate inputs.** The `comment_template` must be one of the known names above. The required inputs for that template must all be present.
2. **Render the template** with the supplied inputs. Use plain string substitution; the templates use `{{variable}}` syntax for substitution and `{{#list}}...{{/list}}` for iteration over lists.
3. **Call `jira_add_comment`** with the rendered body and the ticket key.
4. **Verify the response.** The MCP returns the created comment's ID. Capture it for the run log.

## Output

```json
{
  "ticket_key": "ACME-101",
  "comment_id": "10042",
  "template_used": "workflow-completed",
  "posted_at": "2026-05-10T14:32:11Z"
}
```

## Failure modes

| Failure | Action |
|---|---|
| Unknown template name | Fail with: `error: unknown comment_template "<name>"; valid options: [list].` Halt. |
| Missing required template input | Fail with: `error: template "<name>" requires input "<input>"; not provided.` Halt. |
| MCP `jira_add_comment` returns 4xx | Log the error; do NOT halt the workflow. Comment posting is auxiliary — if it fails (e.g., ticket was deleted mid-run), continue with downstream steps but record the failure in the run log. |
| MCP `jira_add_comment` returns 5xx | Retry once after 5 seconds; if still failing, log and continue (same as above). |

## Guidance

- **Never include credentials, internal candor, or anything client-unsafe.** Comments are visible to anyone with read access to the ticket (which usually includes the client). Treat them like public docs.
- **Render simply.** Jira's markdown is fussier than GitHub's. Stick to headings, bullets, code blocks, links, bold/italic. Avoid tables (Jira's table rendering is unreliable) and HTML.
- **Reference the run ID** in every comment so it's traceable.
