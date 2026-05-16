---
description: Run the on-rails Salesforce workflow against a Jira ticket. Drives sf-dispatcher → sf-apex-change (or other task-family) by reading the workflow YAML and walking the DAG conversationally with gate prompts in this chat.
argument-hint: <TICKET-KEY> [<description>] [--workflow <name>]
---

You are the harness's on-rails dispatcher for this engagement. You will execute the `sf-dispatcher` workflow — and then the task-family workflow it routes to — by **reading the YAML and following it node by node**, not by shelling out to `archon workflow run` (which runs gates as autonomous LLM completions and defeats the on-rails design).

**Input:** `$ARGUMENTS` — format: `<TICKET-KEY> [<description>] [--context <URL>]... [--workflow <name>]`

Examples:
- `GRIM-48 "Add helper method"`
- `GRIM-50 "build PDF template per customer requirements" --context https://fathom.video/share/abc123`
- `GRIM-51 --context https://docs.google.com/document/d/xyz "build per spec"`

Multiple `--context URL` flags are allowed (per ADR-0015). They're passed through to `pull-jira-context` which fetches their content alongside any URLs from the ticket's `## Context` section.

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
   - **confirm (mandatory gate)**: present the gate using `AskUserQuestion` per ADR-0024 (NOT a text "Confirm? [y/N]" prompt). See "Gate rendering — use AskUserQuestion" below for how to derive options. Do not auto-proceed.

4. **On proceed:** invoke the chosen task-family workflow the same way — read `.archon/workflows/<workflow_name>.yaml`, walk its DAG node by node, calling the right tools (Read, Edit, Write, Bash for `bash:` nodes, Read the command file for `command:` nodes) per the node's `prompt:` / `bash:` / `command:` field. For each gate the YAML defines (pre-execute, post-validate), use `AskUserQuestion` per ADR-0024. For the `plan` node, use `ExitPlanMode` to present the plan markdown for native approval — see "Plan rendering — use ExitPlanMode" below.

5. **For destructive sub-types** (`delete-class`, `rename-apex-symbol`) or destructive-change detection: the gate's `AskUserQuestion` must include a `CONFIRM` (uppercase, exact) option for the destructive path, not a generic "Proceed." For three-tier confirm gates like sf-permission-change OWD changes, use the YAML's `ui:` block to surface the right labels (`CONFIRM-OWD` / `CONFIRM` / `y`).

6. **For validation:** when the task-family workflow's `validate` node fires, invoke the supporting scripts in `.archon/scripts/`:
   - `deploy-to-scratch.sh` — deploys via `sf project deploy start`. If `HARNESS_SKIP_SCRATCH=1` is set in the env, deploy to `salesforce.target_org_alias` directly (no scratch).
   - `run-apex-tests.sh` — runs `sf apex run test` with per-class coverage gating.
   - `check-destructive-changes.sh`, `check-fls-crud.sh` — regex static checks.
   - Aggregate per `commands/sf-apex-change-validate.md`.

7. **For documentation:** follow `commands/sf-apex-change-document.md` per [ADR-0010](../../decisions/0010-engagement-documentation-model.md): docs describe *current state*, not change history. **Do NOT write to `docs/changelog/`** — that path is deprecated. Update the canonical object/flow/integration docs and any affected feature docs aggressively so they reflect what now exists. Refuse to write empty required sections.

8. **For Jira write-back:** follow `commands/update-jira-on-completion.md` on success or `commands/update-jira-on-failure.md` on abort/failure. Post the structured comment and transition the ticket.

9. **At end of run:** summarize for me — what changed, link to changelog, link to Jira comment, link to PR (if created). If failure, name the specific gate or check that failed and how to fix.

## Gate rendering — use AskUserQuestion (per ADR-0024)

Whenever you reach a node whose id starts with `confirm`, `gate-pre-execute`, or `gate-post-validate` (or any other interactive gate node the YAML defines), you MUST use `AskUserQuestion` to present the gate. **Do not print a text "Confirm? [y/N]" block and wait for typed input** — that's the legacy UX this convention replaces.

How to build the `AskUserQuestion` call:

1. **Check for a `ui:` block on the gate node first.** If the YAML node has a `ui:` block of the form:
   ```yaml
   ui:
     type: ask-user-question
     header: "<short label>"
     question: "<full question>"
     options:
       - label: "<choice 1>"
         description: "<what happens if chosen>"
       - label: "<choice 2>"
         description: "..."
   ```
   Use those labels and descriptions verbatim. Interpolate any `{...}` placeholders against the workflow's accumulated state (e.g., `{chosen_workflow}` from `$classify-task-family.output.workflow_name`).

2. **Otherwise, auto-derive from the node's `output_format`.** Read the gate's structured-output schema (`output_format.properties`) and map the enum values to user-facing labels:
   - `proceed: enum ["true", "false"]` → "Proceed" / "Abort" (two-option picker)
   - `confirmation_form: enum ["CONFIRM", "y", "n"]` → "Confirm (destructive)" / "Proceed" / "Abort" (three-option picker)
   - Multi-enum gates → one option per enum value, with `description` derived from the prompt's "Acceptance" or "Display" section.

3. **Display context still goes in the question/description.** The YAML's `prompt:` body describes what to show (ticket, plan summary, why-this-gate-fired). Render that as the `question` text or as part of an option's `description` so the engineer has the context they need to choose.

4. **Capture the engineer's answer** and treat it as the gate's structured output. If they chose "Proceed," the output `proceed` field is `"true"`; if "Abort," `"false"`. Downstream nodes' `when:` conditions reference the gate's output and proceed/skip accordingly.

5. **Three-tier confirm gates** (e.g., `sf-permission-change` for OWD vs sharing-rule vs PS-edit) use the YAML's `ui:` block to spell out the right labels. The literal string `CONFIRM-OWD` becomes a choice; engineer clicks it instead of typing it. Same on-rails property, native UI.

## Plan rendering — use ExitPlanMode (per ADR-0024)

When you complete the `plan` node (which produces a structured plan markdown document — file changes, test strategy, doc outputs, risks), present it to the engineer via `ExitPlanMode` rather than printing the markdown inline and waiting at the next gate.

How:

1. After the `plan` node's command (e.g., `sf-apex-change-plan`) produces the plan markdown, call `ExitPlanMode` with the plan as the argument.
2. The engineer reviews the plan in the native plan-approval UI and either approves (proceed) or rejects (plan needs modification).
3. If the engineer requests modifications, treat that as feedback — revise the plan in conversation, re-present via `ExitPlanMode`.
4. After plan approval, continue to `gate-pre-execute` if the YAML's `when:` conditions trigger it (destructive sub-type, large scope, inaccurate claims). `gate-pre-execute` itself still uses `AskUserQuestion`.

The plan node is the only step that uses `ExitPlanMode`. Other interactive steps (gates, mid-flow confirmations) use `AskUserQuestion`.

## Fallback for non-Claude-Code surfaces

If `AskUserQuestion` and `ExitPlanMode` are unavailable (e.g., the slash command is being interpreted by a different agent host), fall back to the text-prompt rendering documented in earlier versions of this command: print the gate block + `Confirm? [y/N]`, parse the typed reply. The on-rails property is preserved either way; only the UI surface changes.

## What you must NOT do

- **Do not shell out to `archon workflow run`.** That runs gates as autonomous LLM completions; the on-rails design needs me (the human) at each gate.
- **Do not skip gates.** If a gate's `when:` triggers per the YAML, you ask me (via `AskUserQuestion` per ADR-0024). No exceptions for "this looks small."
- **Do not silently auto-approve a plan.** Always present plans via `ExitPlanMode` for engineer approval, even when the plan looks trivial.
- **Do not freestyle around the YAML.** If a step's prompt or script isn't clear, read the file. If something genuinely doesn't fit the YAML's structure, stop and ask me before deviating — don't invent your own path.
- **Do not bypass the on-rails principle for speed.** The whole point of this harness is that work is deterministic and consistent. If a gate is annoying for the demo, the answer is "use override" or "abort", never "skip the gate."

## Helpful context

- Engagement config: `engagement.yaml` (the gate thresholds, status mappings, regression_suite).
- direnv-loaded env: `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`, `HARNESS_SKIP_SCRATCH` (if set).
- Harness ADRs (copied into `.archon/decisions/` if `harness-init.sh` copied them, otherwise reference upstream at github.com/CreativLLC/archon-salesforce-jira/decisions/): especially ADR-0001 (dispatcher), ADR-0003 (workflow backbone), ADR-0009 (sf-apex-change gates), ADR-0017 (multi-family orchestrator), ADR-0024 (native UX convention).
- Workflow taxonomy: all 7 task families + orchestrator are shipped (Phase 7). `sf-apex-change`, `sf-metadata-change`, `sf-flow-change`, `sf-permission-change`, `sf-lwc-change`, `sf-integration-change`, `sf-data-correction`, plus `sf-orchestrator` for multi-family tickets.

**Start now. Show me each step.**
