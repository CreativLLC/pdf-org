---
description: File feedback about the harness as a GitHub Issue. Opens an issue at CreativLLC/archon-salesforce-jira with auto-bundled engagement context, the engineer's free text, and a `feedback` label. Per ADR-0014.
argument-hint: "<free-text feedback> [--ticket TICKET-KEY]"
---

You are filing feedback about the harness on behalf of the engineer. The feedback is about HOW THE HARNESS WORKED (or didn't), not about the engagement's Salesforce work. The destination is a GitHub Issue on the harness repo (`CreativLLC/archon-salesforce-jira`) per [ADR-0014](../../decisions/0014-feedback-mechanism.md).

**Input:** `$ARGUMENTS` — the engineer's free-text feedback, optionally followed by `--ticket TICKET-KEY` if they want to associate the feedback with a specific Jira ticket they were working on.

## What you must do, in order

1. **Validate the input.** `$ARGUMENTS` must contain at least 20 characters of meaningful free text (after stripping the optional `--ticket` flag). If shorter, refuse:
   ```
   /sf-feedback expects at least a sentence of free text.
   Example: /sf-feedback "the destructive gate fired on what should have been a small additive change — the classifier saw a method rename as a removal"
   ```

2. **Extract the optional `--ticket` flag.** If present, capture the value (must match `^[A-Z][A-Z0-9]+-\d+$`). If not present, leave ticket as empty string.

3. **Ask the engineer one clarifying question** (only if they didn't pass `--ticket` and you genuinely can't infer the ticket from recent conversation):

   > "Is this feedback about a specific Jira ticket you were working on? Type the key (e.g., `GRIM-49`) or `none`."

   Wait for response. If they answer `none` / empty / `n` / `no`, proceed with empty ticket. Otherwise capture the key.

4. **Invoke the helper script:**

   ```bash
   bash ~/harness/scripts/file-feedback.sh \
     --text "$FEEDBACK_TEXT" \
     ${TICKET:+--ticket "$TICKET"}
   ```

   (Path: the harness lives at `~/harness` per the standard install model. If the engineer has it elsewhere, the slash command can resolve via `.archon/scripts/file-feedback.sh` first, falling back to `~/harness/scripts/file-feedback.sh`. Prefer the `.archon/` path when present — it's already pinned to the engagement's harness version.)

5. **The script returns** a JSON object with the issue URL. Display the URL to the engineer:

   ```
   ✓ Feedback filed: <URL>

   Harness maintainers triage feedback weekly. If this is urgent or
   blocks your work, also ping #harness-questions in Slack.
   ```

6. **If the script fails** (gh not authenticated, GitHub unreachable, etc.), display the script's error message verbatim AND tell the engineer the fallback path:

   ```
   ✗ Could not file via GitHub: <reason>

   The feedback was queued locally at ~/.archon/pending-feedback/<timestamp>.md.
   When you've fixed the issue (gh auth login, etc.), re-run the script:
     bash ~/.archon/pending-feedback/file-pending.sh
   ```

## What you must NOT do

- **Do not modify the engineer's free text.** Pass it verbatim to the script. The script handles structured-body formatting; your job is to relay.
- **Do not file feedback about the engagement's Salesforce work itself.** That belongs in Jira against the engagement's project. `/sf-feedback` is exclusively for harness feedback (workflow behavior, gate ergonomics, prompt clarity, etc.).
- **Do not invoke `gh issue create` directly.** Always go through `file-feedback.sh` so the engagement context auto-bundle is consistent across feedback items.
- **Do not skip the clarifying question** unless the engineer explicitly passed `--ticket` or the answer is obvious from recent conversation (e.g., they just finished `/sf GRIM-49` two messages ago).

## Helpful context

- Engagement context the script auto-bundles:
  - `engagement_alias` from `engagement.yaml`
  - `harness_version` from `engagement.yaml`
  - `engagement_repo_url` from `git remote get-url origin`
  - `engineer_email` from `git config user.email`
  - `current_branch` from `git rev-parse --abbrev-ref HEAD`
  - `current_ticket` from the `--ticket` flag (if provided)
  - `timestamp` (UTC, ISO 8601)
- Labels applied: `feedback` (always) + `harness-version:<short-sha>` (derived from the engagement's harness_version).
- Issue title: auto-summarized to ~60 chars from the engineer's first sentence, prefixed `[feedback]`.

**File the feedback. Be brief; engineers want this to take under 10 seconds.**
