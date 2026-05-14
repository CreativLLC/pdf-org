# `load-engagement-context`

You are loading the engagement-specific context the workflow needs to plan and execute the change correctly: the engagement's `engagement.yaml`, the relevant patterns and standards (with engagement-specific overrides), and the relevant existing docs.

This is the step that makes the agent reason like "someone who knows *this* engagement" rather than generic Salesforce.

## Inputs

- `$classify-sub-type.output` — the sub-type and side flags from the previous node.
- `$pull-jira-context.output` — the Jira ticket. Used to find referenced objects.
- `$verify-org-context.output` — org context (org_id, api_version, etc.).

## Tools

File reads (`Read`, `Glob`, `Grep`):
- `engagement.yaml`
- `.archon/patterns/**/*.md` (team-wide canon)
- `docs/patterns/**/*.md` (engagement-specific overrides, if any)
- `.archon/standards/**/*.md`
- `docs/standards/**/*.md`
- `docs/objects/**/*.md` (engagement object docs)
- `docs/integrations/**/*.md`

No MCP tools, no SF CLI calls (those are in `verify-org-context`).

## Task

1. **Read `engagement.yaml`.** Extract:
   - `engagement_alias`, `client_name`
   - `salesforce.dev_model` (`source_tracked` or `org_development`)
   - `salesforce.coverage.per_class_target` (default 75 if absent)
   - `tests.regression_suite` (optional list; empty if absent)
   - `gates.destructive_changes_require_approval` (default `true`)
2. **Load relevant patterns based on `sub_type` and side flags.** The patterns the agent should always have in scope for this workflow:
   - Always: `apex-trigger-handler.md` (if `sub_type` is `*-trigger`), `testdatafactory-usage.md` (for any sub_type that touches tests)
   - When `touches_soql_dml == "true"`: `fls-crud-enforcement.md`, `bulkified-soql-update.md`
   - Engagement-specific override: if `docs/patterns/<same-name>.md` exists, read both and prefer the engagement override; if `docs/patterns/` adds patterns not in `.archon/patterns/`, those are engagement-specific additions — load them when their topic matches.
3. **Identify referenced objects from the ticket.** Grep the ticket title + description for likely Salesforce object names — both standard (`Account`, `Contact`, `Opportunity`, etc.) and custom (anything matching `[A-Z][A-Za-z0-9_]+__c`). For each match, attempt to read `docs/objects/<ObjectAPIName>.md`. If it doesn't exist, record the gap (the workflow may need to create the doc later).
4. **Identify referenced integrations.** Grep for likely integration names — `Stripe`, `DocuSign`, `Snowflake`, `Outreach`, anything matching named credentials patterns. Read `docs/integrations/<name>.md` for each match.
5. **Load the engagement's architecture overview.** Always read `docs/architecture/overview.md` if it exists.
6. **Identify recent change history.** List the 5 most recent `docs/changelog/YYYY-MM/<TICKET>.md` files. The summaries help the agent avoid contradicting recent decisions.

## Output

Emit a structured JSON object on stdout summarizing what was loaded:

```json
{
  "engagement": {
    "alias": "acme-renewals",
    "client_name": "Acme Co.",
    "dev_model": "source_tracked",
    "coverage_threshold": 75,
    "regression_suite": ["AccountTriggerHandler_Test", "RenewalCalculator_Test"],
    "destructive_changes_require_approval": true
  },
  "patterns_in_scope": [
    ".archon/patterns/apex-trigger-handler.md",
    ".archon/patterns/fls-crud-enforcement.md",
    ".archon/patterns/testdatafactory-usage.md"
  ],
  "standards_in_scope": [
    ".archon/standards/<name>.md"
  ],
  "referenced_objects": [
    {"name": "Renewal__c", "doc_path": "docs/objects/Renewal__c.md", "doc_exists": true},
    {"name": "Account", "doc_path": "docs/objects/Account.md", "doc_exists": false}
  ],
  "referenced_integrations": [
    {"name": "Stripe", "doc_path": "docs/integrations/Stripe-billing.md", "doc_exists": true}
  ],
  "architecture_overview_path": "docs/architecture/overview.md",
  "recent_changelog_entries": [
    "docs/changelog/2026-05/ACME-097.md",
    "docs/changelog/2026-05/ACME-094.md"
  ],
  "doc_gaps": [
    "docs/objects/Account.md is missing — workflow's document step should create or update"
  ]
}
```

If `engagement.yaml` is missing entirely, fail with:
```
error: engagement.yaml not found at repo root. Are you in an engagement repo? Run harness-init.sh to bootstrap.
```
