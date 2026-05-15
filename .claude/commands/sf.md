---
description: Run the on-rails Salesforce workflow against a Jira ticket. Drives sf-dispatcher → sf-apex-change (or other task-family) by reading the workflow YAML and walking the DAG conversationally with gate prompts in this chat.
argument-hint: <TICKET-KEY> [<description>] [--workflow <name>]
---

You are the harness's on-rails dispatcher for this engagement. You will execute the `sf-dispatcher` workflow — and then the task-family workflow it routes to — by **reading the YAML and following it node by node**, not by shelling out to `archon workflow run` (which runs gates as autonomous LLM completions and defeats the on-rails design).

**Input:** `$ARGUMENTS` (e.g., `GRIM-48 "Add helper method"`).

## What you must do, in order

1. **Validate the ticket key.** First whitespace-delimited token of `$ARGUMENTS` must match `^[A-Z][A-Z0-9]+-\d+$`. If not, refuse:
   ```
   /sf expects a Jira ticket key first.
   Example: /sf GRIM-48 "Add SimpleGreeter utility class"
   ```

2. **Read the dispatcher's YAML:** `.archon/workflows/sf-dispatcher.yaml`. Understand the DAG: parse-args → pull-jira-context → classify-task-family → confirm → invoke-workflow → log-dispatcher-run.

3. **Execute the dispatcher's nodes one at a time, in chat:**
   - **parse-args**: extract ticket + description + override_workflow from `$ARGUMENTS`. Show the result.
   - **pull-jira-context**: read the command file at `.archon/commands/pull-jira-context.md`; use the `mcp-atlassian` MCP if available, otherwise fetch via curl using `$JIRA_URL` / `$JIRA_USERNAME` / `$JIRA_API_TOKEN` from the engagement's direnv-loaded env. Show the ticket title and status.
   - **classify-task-family**: read the inline prompt in the dispatcher YAML; decide which `sf-*` task family fits. Show the choice + reasoning.
   - **confirm (mandatory gate)**: print the gate's display block per ADR-0001 with the resolved workflow, scope, reasoning, and what the workflow will do. **Then stop and ask me (the engineer) in chat: `Confirm? [y/N]` — wait for my reply.** Do not auto-proceed. Acceptable replies: `y`, `yes`, `n`, `no`, `override <workflow-name>`.

4. **On `y` / `yes`:** invoke the chosen task-family workflow the same way — read `.archon/workflows/<workflow_name>.yaml`, walk its DAG node by node, calling the right tools (Read, Edit, Write, Bash for `bash:` nodes, Read the command file for `command:` nodes) per the node's `prompt:` / `bash:` / `command:` field. For each gate the YAML defines (pre-execute, post-validate), pause and ask me in chat.

5. **For destructive sub-types** (`delete-class`, `rename-apex-symbol`) or destructive-change detection: require the literal string `CONFIRM` (uppercase, exact). Reject `y`/`yes` for those.

6. **For validation:** when the task-family workflow's `validate` node fires, invoke the supporting scripts in `.archon/scripts/`:
   - `deploy-to-scratch.sh` — deploys via `sf project deploy start`. If `HARNESS_SKIP_SCRATCH=1` is set in the env, deploy to `salesforce.target_org_alias` directly (no scratch).
   - `run-apex-tests.sh` — runs `sf apex run test` with per-class coverage gating.
   - `check-destructive-changes.sh`, `check-fls-crud.sh` — regex static checks.
   - Aggregate per `commands/sf-apex-change-validate.md`.

7. **For documentation:** follow `commands/sf-apex-change-document.md` per [ADR-0010](../../decisions/0010-engagement-documentation-model.md): docs describe *current state*, not change history. **Do NOT write to `docs/changelog/`** — that path is deprecated. Update the canonical object/flow/integration docs and any affected feature docs aggressively so they reflect what now exists. Refuse to write empty required sections.

8. **For Jira write-back:** follow `commands/update-jira-on-completion.md` on success or `commands/update-jira-on-failure.md` on abort/failure. Post the structured comment and transition the ticket.

9. **At end of run:** summarize for me — what changed, link to changelog, link to Jira comment, link to PR (if created). If failure, name the specific gate or check that failed and how to fix.

## What you must NOT do

- **Do not shell out to `archon workflow run`.** That runs gates as autonomous LLM completions; the on-rails design needs me (the human) at each gate.
- **Do not skip gates.** If a gate's `when:` triggers per the YAML, you ask me. No exceptions for "this looks small."
- **Do not freestyle around the YAML.** If a step's prompt or script isn't clear, read the file. If something genuinely doesn't fit the YAML's structure, stop and ask me before deviating — don't invent your own path.
- **Do not bypass the on-rails principle for speed.** The whole point of this harness is that work is deterministic and consistent. If a gate is annoying for the demo, the answer is "use override" or "abort", never "skip the gate."

## Helpful context

- Engagement config: `engagement.yaml` (the gate thresholds, status mappings, regression_suite).
- direnv-loaded env: `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`, `HARNESS_SKIP_SCRATCH` (if set).
- Harness ADRs (copied into `.archon/decisions/` if `harness-init.sh` copied them, otherwise reference upstream at github.com/CreativLLC/archon-salesforce-jira/decisions/): especially ADR-0001 (dispatcher), ADR-0003 (workflow backbone), ADR-0009 (sf-apex-change gates).
- Workflow taxonomy: only `sf-apex-change` is shipped as of Phase 4. If classify picks an unshipped workflow, surface the gap to me; don't try to implement it freestyle.

**Start now. Show me each step.**
