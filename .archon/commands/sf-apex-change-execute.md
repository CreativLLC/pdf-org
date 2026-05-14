# `sf-apex-change-execute`

You are implementing the change against the engagement repo's working tree, following the plan produced by `sf-apex-change-plan`. **You do not deploy, run tests, or update Jira here** — those are downstream steps.

## Inputs

- `$ARTIFACTS_DIR/plan.md` — the full plan written by the plan step
- `$plan.output` — the JSON summary
- `$load-engagement-context.output` — patterns/standards in scope
- `$verify-org-context.output` — org info (api_version, etc.)
- `$classify-sub-type.output` — sub_type, side flags

## Tools

Read, Edit, Write, Glob, Grep, Bash (for `git status`, `git diff` only — no commits). No SF CLI calls. No Jira writes. No network.

## Task

1. **Read the full plan** from `$ARTIFACTS_DIR/plan.md`. Treat it as authoritative.
2. **Implement the file changes** per the plan's `files_changed` list:
   - For `add` operations: Write the new file with content that satisfies the plan and adheres to every pattern in `patterns_followed`.
   - For `modify` operations: Edit the existing file with surgical changes. Preserve unrelated code formatting and structure.
   - For `delete` operations: Remove the file. If the engagement uses `source_tracked` dev model, also update `manifest/destructiveChanges.xml` (or create it if absent). If `org_development`, leave the destructive manifest update to the deploy step.
   - For `rename` operations: Move the file to the new path. Then grep all references in `force-app/main/default/` and update them.
3. **Adhere to the patterns in scope.** Specifically:
   - If a trigger is in scope, the trigger file is **one line of dispatch** — see `apex-trigger-handler.md`. No business logic in the trigger itself.
   - If the change does SOQL or DML on user data, use `WITH USER_MODE` on every SOQL and `Security.stripInaccessible` before every DML — see `fls-crud-enforcement.md`. (Static check runs in validate; following the pattern here avoids failing it.)
   - If a test class is touched, use `TestDataFactory` for fixture data — see `testdatafactory-usage.md`. No `SeeAllData=true`.
   - If you encounter a situation the plan didn't anticipate, **add the variation to the plan first** (write a new section to `$ARTIFACTS_DIR/plan.md` describing the deviation and why), THEN implement.
4. **Do not modify unrelated files.** If you find an issue elsewhere (a bug in a different class, a stale doc, a typo), record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate ticket — don't fix it here.
5. **Stage the changes for review.** Run `git status` and capture the file list. Do NOT `git add` or `git commit` — the engineer commits after the workflow completes successfully.
6. **Write an implementation summary** to `$ARTIFACTS_DIR/implementation.md` describing:
   - Files actually changed (vs. what the plan predicted)
   - Any plan deviations and their justification
   - Anti-pattern checks the engineer should run manually if any are out of scope for the FLS/CRUD static check

## Output

Emit a structured JSON summary on stdout:

```json
{
  "files_changed_actual": [
    {"path": "force-app/main/default/classes/RenewalCalculator.cls", "operation": "modify", "lines_added": 18, "lines_removed": 3},
    {"path": "force-app/main/default/classes/RenewalCalculator_Test.cls", "operation": "modify", "lines_added": 22, "lines_removed": 0}
  ],
  "plan_deviations": [],
  "follow_ups_recorded": false,
  "implementation_artifact": "$ARTIFACTS_DIR/implementation.md"
}
```

The model used for this node is `opus[1m]` (per the workflow YAML) — this is the heaviest reasoning step and gets the largest context window.
