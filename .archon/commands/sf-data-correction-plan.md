# `sf-data-correction-plan`

You are producing the structured plan for a data correction. This family is the highest-blast-radius in the harness — your plan is what the engineer reviews at the pre-execute gate to decide whether to proceed. **Frame the correction as last-resort.** Data corrections fix data, not design. If the correction is recurring against the same root cause, surface that in `recurring_pattern_root_cause` so the document phase can propose an upstream fix.

**No code changes happen here** — this step is plan-only. No Apex is written; no SOQL runs against the org; no DML is staged.

## Inputs

- `$pull-jira-context.output` — the ticket
- `$classify-sub-type.output` — `sub_type`, `estimated_record_count`, `is_destructive`, `requires_system_mode`, `touches_restricted_object`, `recurring_pattern_flag`, scope
- `$smoke-validate-claims.output` — accuracy of ticket claims against engagement docs
- `$verify-org-context.output` — `target_org_alias`, `api_version`, whether the target is sandbox/prod
- `$load-engagement-context.output` — `salesforce.data_corrections.restricted_objects`, relevant `docs/objects/*` summaries, patterns in scope

## Tools

File reads, Glob, Grep against the engagement repo (`docs/`, `force-app/main/default/`). No file writes outside `$ARTIFACTS_DIR/`. No git operations. No `sf` CLI calls. No Jira writes.

## Task

1. **Re-read the ticket's acceptance criteria.** The plan must satisfy every AC, or explicitly flag which ones are out of scope. If the ticket is vague ("clean up the bad data"), refuse to produce a plan — output a structured error: `plan_failed: ticket lacks concrete criteria; cannot proceed without object, field, and WHERE-clause specifics`. The engineer re-tickets with specifics.

2. **Frame as last-resort.** In the plan's "Rationale" section, answer: *why is a data correction the right tool here vs fixing the upstream cause?* If the answer is "it isn't, but we need to clean up while we fix the upstream," say so. Examples:
   - Acceptable: "Trigger `RenewalTriggerHandler` was incorrectly setting `Status__c` to `Active` for closed renewals; trigger was fixed in `<PRIOR-TICKET>`. This correction backfills the records created during the broken window."
   - Acceptable: "Records loaded via a 2024 data migration were given the wrong `Owner__c`. No upstream fix needed; one-time correction."
   - Not acceptable: "Status field keeps ending up wrong; just fix the records." → check ticket history; if this is the third correction against the same root cause, set `recurring_pattern_flag: "true"` and surface the upstream concern in `recurring_pattern_root_cause`.

3. **Map sub_type to plan template:**

   | sub_type | Plan must specify |
   |---|---|
   | `data-update-anonymous-apex` | Target object, SOQL WHERE clause, fields being updated, source-of-truth for new values (literal? computed from another field?), expected reach, anonymous-block structure |
   | `data-update-batch` | Same as above + Batch class structure (start query, execute logic, finish summary), scope size justification, `Database.Stateful` usage |
   | `data-insert` | Target object, source of records (CSV path? Apex-generated from SOQL?), field-mapping spec, validation rules / triggers that will fire during insert |
   | `data-delete-anonymous` | Target object, SOQL WHERE clause selecting deletion targets, expected reach, recycle-bin recovery note (15-day retention) |
   | `data-delete-batch` | Same as anonymous-delete + Batch class structure, scope size, recovery note |
   | `data-undelete` | Target object, recycle-bin query criteria (`IsDeleted = true`), expected reach, post-undelete state confirmation |
   | `data-merge` | Survivor record ID, duplicate record IDs, child-record cascade enumeration (every relationship that will be re-parented), conflict resolution for non-null fields |

4. **Specify FLS posture explicitly.** For every sub-type, declare:
   - `fls_posture: "USER_MODE"` (default) — Apex uses `WITH USER_MODE` on SOQL and `Database.<op>(records, AccessLevel.USER_MODE)` on DML. Per [`fls-crud-enforcement.md`](../patterns/fls-crud-enforcement.md) and ADR-0009 §7.
   - `fls_posture: "SYSTEM_MODE"` (only when justified) — Apex uses unrestricted SOQL and DML. The plan MUST include `system_mode_justification` (one paragraph: why USER_MODE would fail and why system context is intentional). The pre-execute gate surfaces this for engineer review.

5. **Enumerate the SOQL WHERE clause.** Write the SOQL as it will appear in the dry-run / live Apex. Examples (use templates, not real org data):

   ```sql
   SELECT Id, <Field1>, <Field2>
   FROM <Object>
   WHERE <criterion-1>
     AND <criterion-2>
     AND CreatedDate < <ISO-DATE>
   WITH USER_MODE
   ```

   For `data-update-batch`, the same query goes in `Database.QueryLocator start()`. For deletes, the same query is used; DML target is the returned records.

6. **Estimate the affected-record count.** Two sources:
   - **Classifier estimate** (`$classify-sub-type.output.estimated_record_count`) — coarse guess from the ticket.
   - **Refinement from engagement docs** — if `docs/objects/<Object>.md` describes the field distributions (e.g., "10% of records have `Status__c = 'Stale'`"), use that to refine.

   Output `expected_reach` as an integer. The dry-run will be the authoritative count; this is your best a-priori estimate. If the dry-run exceeds this by >10%, the post-validate gate fires.

7. **Enumerate segmentation.** For the WHERE clause's predicted matching records, estimate:
   - `expected_distinct_accounts` — how many distinct Account values would be touched
   - `expected_distinct_owners` — how many distinct Owner values
   - `expected_distinct_record_types` — how many distinct Record Type values

   If the ticket says "fix the Status field on closed Acme accounts," the engineer expects `expected_distinct_accounts: 1` (Acme). If the dry-run finds 47 distinct Accounts, that's segmentation creep — the WHERE clause matched more than the engineer expected.

8. **Check restricted-object policy.** Read `$load-engagement-context.output.salesforce.data_corrections.restricted_objects`. If the target object is in that list, set `touches_restricted_object_per_engagement: "true"`. The post-validate gate will fire unconditionally.

9. **Identify patterns that apply.** For each pattern listed in `$load-engagement-context.output.patterns_in_scope`, state in one sentence how the Apex will adhere to it.
   - For `data-update-batch` and `data-delete-batch`: cite [`batch-apex-pattern.md`](../patterns/batch-apex-pattern.md). Specify `Database.Stateful` usage and scope size.
   - For any sub-type with SOQL/DML: cite [`fls-crud-enforcement.md`](../patterns/fls-crud-enforcement.md). Specify `WITH USER_MODE` + `AccessLevel.USER_MODE`.
   - For sub-types that do callouts after DML (rare; usually a Queueable inside a Batch's `finish()`): cite [`queueable-async-pattern.md`](../patterns/queueable-async-pattern.md).

10. **Identify documentation outputs.** Per ADR-0023 §5: the document phase is LIGHT. It does NOT touch state docs. List in the plan:
    - `docs_to_update: []` — always empty for this family (the Jira comment is the record).
    - `optional_adr: "docs/decisions/<NNNN>-prevent-<root-cause-slug>.md"` ONLY if `$classify-sub-type.output.recurring_pattern_flag == "true"` AND you have identified a clear root cause. The document phase writes a draft; the engineer reviews and refines.

11. **Identify risk surface.** Note any of:
    - **Reversibility:** for deletes, recycle-bin retention is 15 days; for merges, reversibility is none; for updates, the engineer must capture pre-state if rollback is conceivable.
    - **Concurrent-DML risk:** if the target records may be modified by triggers/Flows during the correction window, the dry-run count and live count may diverge. Note expected delta.
    - **Governor-limit exposure:** for anonymous Apex sub-types, total-records times average-DML-rows-per-record must stay under the synchronous limit (10K DML rows per transaction). If at risk, recommend the engineer escalate to a Batch sub-type.
    - **Validation-rule / required-field implications:** for `data-update`, if the new field value would violate an existing validation rule, the DML will fail per-record. The plan should pre-check the proposed values against `docs/objects/<Object>.md`'s "Validation rules" section.

12. **Write the full plan** to `$ARTIFACTS_DIR/plan.md` as readable markdown. Sections required: Rationale, Sub-type, Target object & SOQL, Expected reach & segmentation, FLS posture, Pattern adherence, Risk surface, Documentation outputs. Use template placeholders (`<Object>`, `<Field>`) — do NOT include real org data or real record IDs.

## Output

Emit a JSON summary on stdout. The gate display reads several of these fields directly.

```json
{
  "summary": "One-line description of the correction (template form: 'Update <Field> on <Object> records matching <criteria>; expected reach <N>').",
  "sub_type": "data-update-anonymous-apex",
  "target_object": "<Object>",
  "soql_where_clause": "<criterion-1> AND <criterion-2>",
  "fls_posture": "USER_MODE",
  "system_mode_justification": null,
  "expected_reach": 234,
  "expected_distinct_accounts": 1,
  "expected_distinct_owners": 3,
  "expected_distinct_record_types": 1,
  "touches_restricted_object_per_engagement": false,
  "recurring_pattern_flag": false,
  "recurring_pattern_root_cause": null,
  "patterns_followed": ["fls-crud-enforcement"],
  "docs_to_update": [],
  "optional_adr": null,
  "risks": [
    "Concurrent inserts to <Object> during correction window may cause dry-run vs actual delta > 2%."
  ],
  "out_of_scope_acceptance_criteria": []
}
```

If `recurring_pattern_flag == true`, `recurring_pattern_root_cause` must be a one-paragraph description naming the upstream artifact (trigger / Flow / validation rule) and the recommended fix. The document phase uses this to draft an engagement ADR.

If you cannot produce a viable plan (vague ticket, missing criteria), output:

```json
{
  "summary": null,
  "plan_failed": true,
  "plan_failure_reason": "<one-paragraph explanation of what's missing>"
}
```

The workflow's pre-execute gate displays the failure reason; the engineer re-tickets and re-runs.
