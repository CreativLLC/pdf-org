# `verify-org-context`

You are verifying that the engineer's Salesforce CLI is authorized and the engagement's target org alias is reachable. This is the equivalent of `pull-jira-context` for Salesforce: it loads ground-truth org context before the workflow plans or executes any change.

## Inputs

- `engagement.yaml` at the engagement repo root. Read it.
  - `salesforce.target_org_alias` — required.
  - `salesforce.api_version` — required.
  - `salesforce.scratch_org_def_path` — required for any workflow that creates scratch orgs.

## Tools

Shell out via `bash`:
- `sf org display --target-org <alias> --json` — verify the alias is authorized.
- `sf org list --json` — list authorized orgs (for error messages if the alias is missing).
- `sf project retrieve start --target-org <alias> --metadata <type:name> --json` — for targeted retrieval (used by downstream steps; **don't run here**).

No MCP tools.

## Task

1. **Read `engagement.yaml`.** Extract `salesforce.target_org_alias`, `salesforce.api_version`, `salesforce.scratch_org_def_path`. If any required field is missing, fail with:
   ```
   error: engagement.yaml missing required field salesforce.<field>; run harness-init.sh to regenerate
   ```
2. **Verify the org alias is authorized.** Run `sf org display --target-org "$TARGET_ORG_ALIAS" --json`. On non-zero exit, fail with:
   ```
   error: SF CLI alias "<alias>" is not authorized on this machine.
     Run: sf org login web --alias <alias>
     Or list available aliases: sf org list
   ```
3. **Capture key org context** from the `sf org display` output:
   - `org_id` — the 18-character org ID
   - `instance_url` — e.g. `https://acme.my.salesforce.com`
   - `username` — the authorized user
   - `connected_status` — should be `Connected`; if anything else, fail
   - `is_scratch_org` — boolean; the workflow's deployment strategy depends on this
   - `is_sandbox` — boolean
4. **Sanity-check API version alignment.** Compare `engagement.yaml: salesforce.api_version` against the org's `apiVersion` from `sf org display`. If they differ by more than one major version, emit a warning (not a failure):
   ```
   warning: engagement api_version=67.0 but org reports apiVersion=64.0; retrieved metadata may not match
   ```
5. **Verify the scratch org definition exists** (only if the workflow is one that creates scratch orgs — caller signals this via env var `WORKFLOW_NEEDS_SCRATCH=true`). Check `salesforce.scratch_org_def_path` resolves to a real file. If not, fail.
6. **Do NOT retrieve metadata here.** That's deferred to the workflow's execute / validate steps so they can target only the metadata the change actually touches.

## Output

Emit a structured JSON object on stdout. Downstream nodes consume this:

```json
{
  "target_org_alias": "acme-prod",
  "org_id": "00D1U000000DummyID",
  "instance_url": "https://acme.my.salesforce.com",
  "username": "developer@acme.com",
  "is_scratch_org": false,
  "is_sandbox": true,
  "api_version_engagement": "67.0",
  "api_version_org": "67.0",
  "version_warning": null,
  "scratch_org_def_path": "config/project-scratch-def.json",
  "scratch_org_def_exists": true
}
```

On failure, exit non-zero and emit a structured error to stderr.
