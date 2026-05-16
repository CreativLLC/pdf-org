# `sf-metadata-change-execute`

You are implementing the metadata change against the engagement repo's working tree, following the plan produced by `sf-metadata-change-plan`. **You do not deploy, run validation checks, or update Jira here** — those are downstream steps.

## Inputs

- `$ARTIFACTS_DIR/plan.md` — the full plan written by the plan step
- `$plan.output` — the JSON summary
- `$load-engagement-context.output` — patterns/standards in scope, dev model
- `$verify-org-context.output` — org info (api_version, etc.)
- `$classify-sub-type.output` — sub_type, side flags

## Tools

Read, Edit, Write, Glob, Grep, Bash (for `git status`, `git diff` only — no commits). No SF CLI calls. No Jira writes. No network.

## Task

1. **Read the full plan** from `$ARTIFACTS_DIR/plan.md`. Treat it as authoritative.

2. **Implement the file changes** per the plan's `files_changed` list:
   - For `add` operations: Write the new metadata XML. Use the `api_version` from `$verify-org-context.output` in the XML when the metadata type requires it. Match the existing engagement's metadata style (indentation, attribute order, comments) — Glob and Read an adjacent same-type file as the style reference.
   - For `modify` operations: Edit the existing metadata XML with surgical changes. Preserve unrelated XML structure and comments. Do not reformat the file.
   - For `delete` operations: Remove the metadata XML file. If `$load-engagement-context.output.engagement.dev_model == "source_tracked"`, also update `manifest/destructiveChanges.xml` (or create it if absent) with the appropriate `<types>` entry. If `org_development`, leave the destructive-manifest update to the engineer who runs the deploy.
   - For `modify-field` rename: write the new field-meta.xml file, leave the old one for the destructive-manifest pass, and grep the engagement repo for references to the old name — list them in `$ARTIFACTS_DIR/follow-ups.md` (do NOT rewrite the references here; that's `sf-apex-change`'s job when the orchestrator sequences it).

3. **Adhere to the patterns in scope.** Specifically:
   - For `create-field` operations: the field-meta.xml's `<description>` element MUST contain a non-empty description sourced from the plan's `fls_posture.rationale`. Salesforce describes its own metadata to admin readers via this field; leaving it empty is a discoverability failure.
   - For sensitive fields (the plan flagged `fls_posture.sensitive: true`): set `<encrypted>false</encrypted>` only if encryption isn't required; otherwise raise this in `$ARTIFACTS_DIR/follow-ups.md` for the engineer to discuss platform encryption with the engagement architect.
   - For `create-validation-rule`: the `<errorMessage>` is user-facing. Match the engagement's tone from neighboring validation rules' error messages — short, actionable, not blaming the user.
   - For `create-record-type`: assign the record type to relevant page layouts in the same change (the plan should have listed which layouts; if not, default to the object's existing primary layout).

4. **Do not modify unrelated files.** If you find an issue elsewhere (a stale doc, a typo in a neighboring field's description, a validation rule whose formula references a deprecated field), record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate ticket — don't fix it here.

5. **Stage the changes for review.** Run `git status` and capture the file list. Do NOT `git add` or `git commit` — the engineer commits after the workflow completes successfully.

6. **Write an implementation summary** to `$ARTIFACTS_DIR/implementation.md` describing:
   - Files actually changed (vs. what the plan predicted)
   - Any plan deviations and their justification
   - Reference cleanups deferred to follow-up (e.g., "renamed `Account.Old_Field__c` → `Account.New_Field__c`; 3 Apex classes still reference the old name — listed in `follow-ups.md` for `sf-apex-change`")

## Output

Emit a structured JSON summary on stdout:

```json
{
  "files_changed_actual": [
    {"path": "force-app/main/default/objects/Account/fields/Revenue_Tier__c.field-meta.xml", "operation": "add", "lines_added": 32, "lines_removed": 0}
  ],
  "destructive_manifest_updated": false,
  "rename_references_deferred": [],
  "plan_deviations": [],
  "follow_ups_recorded": false,
  "implementation_artifact": "$ARTIFACTS_DIR/implementation.md"
}
```

The model used for this node is `opus[1m]` (per the workflow YAML) — metadata XML generation is mechanical but the FLS-posture reasoning and the reference-impact handling benefit from the wider context window.
