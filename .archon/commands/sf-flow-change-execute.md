# `sf-flow-change-execute`

You are implementing the Flow change against the engagement repo's working tree, following the plan produced by `sf-flow-change-plan`. **You do not deploy, activate, or update Jira here** — those are downstream steps.

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
   - For `add` operations on `.flow-meta.xml`: Write the new Flow XML with content that satisfies the plan. The XML must be syntactically valid per the Salesforce Metadata API schema. Use the `$verify-org-context.output.api_version_engagement` for the `<apiVersion>` element (or honor an explicit override in the plan).
   - For `modify` operations on `.flow-meta.xml`: Edit the existing file with surgical changes. Preserve element ordering and indentation of unrelated elements. Flow XML is heavily ordered; reshuffling element order produces a diff that's hard to review even when the semantic change is small.
   - For `delete` operations: Remove the `.flow-meta.xml` file. If the engagement uses `source_tracked` dev model, also update `manifest/destructiveChanges.xml` (or create it if absent), adding `<types><members><FlowName></members><name>Flow</name></types>`. If `org_development`, leave the destructive manifest update to the deploy step.
   - For `modify (caller)` operations on Apex callers: Edit the Apex class to match the new Flow contract (e.g., updated input/output variable names if the subflow signature changed). Keep these edits minimal and scoped to the Flow's caller surface.
3. **Honor the `<status>` lifecycle per sub_type:**
   - `create-*` sub-types: set `<status>` per the plan's `ship_active` field. `ship_active == true` → write `<status>Active</status>`. `false` → write `<status>Draft</status>` (or omit; both are equivalent for new Flows).
   - `activate-flow`: change `<status>` from its current value to `<status>Active</status>`.
   - `deactivate-flow`: change `<status>` from `<status>Active</status>` to `<status>Obsolete</status>`.
   - `modify-flow`: do NOT change `<status>` unless the plan explicitly says to. Modifying an Active Flow keeps it Active.
   - `delete-flow`: not applicable — the file is removed.
4. **Adhere to the patterns in scope.** Specifically:
   - If the Flow's `<recordUpdates>` / `<recordCreates>` / `<recordDeletes>` operate on records that came from a loop element, ensure the DML is OUTSIDE the loop (collect into a variable inside the loop; do DML once after). See `bulkified-soql-update.md` — same anti-pattern as Apex DML-in-loop; Flow has the same governor limits.
   - For Flows that perform DML on user-data objects from a non-system-context Flow (`<runInMode>` is not `SystemModeWithSharing` / `SystemModeWithoutSharing`), the Flow honors FLS/CRUD automatically — no manual enforcement needed, but reference `fls-crud-enforcement.md` for the architectural reasoning. (Apex-from-Flow inherits the Flow's run-mode; if the Flow calls invocable Apex, that Apex should still use `WITH USER_MODE` to be safe across callers.)
   - If a screen flow exposes user-facing labels, follow the engagement's UX standards if any exist in `docs/standards/`.
   - If you encounter a situation the plan didn't anticipate, **add the variation to the plan first** (write a new section to `$ARTIFACTS_DIR/plan.md` describing the deviation and why), THEN implement.
5. **Always include fault paths on `<actionCalls>`.** Every `<actionCalls>` element (invocable Apex, Email Alert, etc.) should have a `<faultConnector>` defined OR an explicit comment in `$ARTIFACTS_DIR/implementation.md` justifying its absence. The validate step warns when fault paths are missing; surfacing the reasoning at execute time avoids the warning becoming a gate hit later.
6. **Do not modify unrelated files.** If you find an issue elsewhere (a stale doc, a typo in an unrelated Flow, a bug in a sibling Apex class), record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate ticket — don't fix it here.
7. **Stage the changes for review.** Run `git status` and capture the file list. Do NOT `git add` or `git commit` — the engineer commits after the workflow completes successfully.
8. **Write an implementation summary** to `$ARTIFACTS_DIR/implementation.md` describing:
   - Files actually changed (vs. what the plan predicted)
   - Any plan deviations and their justification
   - Fault-path coverage on `<actionCalls>` (per element: covered / uncovered + reason)
   - For `create-*` and `modify-flow`: a brief element graph (Decision → Update Records → Decision → etc.) to make the Flow's intent legible at review time without opening the XML

## Output

Emit a structured JSON summary on stdout:

```json
{
  "files_changed_actual": [
    {"path": "force-app/main/default/flows/Renewal_Auto_Create.flow-meta.xml", "operation": "add", "lines_added": 78, "lines_removed": 0},
    {"path": "force-app/main/default/classes/Renewal_Auto_Create_Test.cls", "operation": "add", "lines_added": 42, "lines_removed": 0}
  ],
  "status_changes": [
    {"flow": "Renewal_Auto_Create", "from": "(new)", "to": "Active"}
  ],
  "fault_paths": [
    {"flow": "Renewal_Auto_Create", "action_call": "InvokeRenewalCalculator", "fault_covered": true}
  ],
  "plan_deviations": [],
  "follow_ups_recorded": false,
  "implementation_artifact": "$ARTIFACTS_DIR/implementation.md"
}
```

The model used for this node is `opus[1m]` (per the workflow YAML) — Flow XML can be lengthy and the structural ordering requirements benefit from the largest context window.
