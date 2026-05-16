# `sf-data-correction-execute`

You are writing the Apex artifacts the validate step will run against the target org. Per [ADR-0023](../decisions/0023-sf-data-correction-scope-and-gates.md) §3, you produce **two** Apex artifacts: a dry-run (read-only) version and a live version. The dry-run is the source of truth; the live version is a mechanical transform of the dry-run with DML restored.

**You do not run the Apex, deploy anything, or update Jira here** — validate runs the artifacts; document writes the (optional) ADR.

**Critical invariant:** never write real record IDs, real usernames, or real org data into the artifacts. Use template placeholders (`<RECORD-ID>`, `<USERNAME>`) where the plan referenced them. Real data binds at runtime via SOQL.

## Inputs

- `$ARTIFACTS_DIR/plan.md` — the full plan written by `sf-data-correction-plan`
- `$plan.output` — the JSON summary (target_object, soql_where_clause, fls_posture, expected_reach, etc.)
- `$classify-sub-type.output` — sub_type, estimated_record_count, is_destructive, requires_system_mode
- `$verify-org-context.output` — api_version (drives `WITH USER_MODE` availability — requires API 60.0+)
- `$load-engagement-context.output` — patterns in scope

## Tools

Read, Write, Glob, Grep. Bash for staging directory checks only. No `sf` CLI calls. No git operations. No Jira writes. No network.

## Task

### Step 1 — Read the plan

Read `$ARTIFACTS_DIR/plan.md` in full. If `$plan.output.plan_failed == true`, output `execute_status: skipped_plan_failed` and stop. The workflow's pre-execute gate already aborted; the execute node shouldn't run, but defense-in-depth.

### Step 2 — Author the DRY-RUN artifact FIRST

This is the critical ordering. **Always write the dry-run first.** The live version is derived from it by a mechanical transform. Authoring the live version first creates the asymmetric "what if I missed a DML call when stripping" failure mode that ADR-0023 §3 specifically calls out.

Write to `$ARTIFACTS_DIR/correction-dry-run.apex` an Apex artifact that:

1. **Uses the same SOQL as the plan's `soql_where_clause`**, with `WITH USER_MODE` (or unrestricted only if `$plan.output.fls_posture == "SYSTEM_MODE"` AND the plan's `system_mode_justification` is non-null — see Step 5).

2. **Replaces every DML call with a Map-based accumulator and a count.** The accumulator captures what *would* have been affected:

   ```apex
   // DRY-RUN — no DML executed. Accumulate records that would be affected.
   Map<Id, SObject> dmlCandidates = new Map<Id, SObject>();
   Set<Id> distinctAccountIds = new Set<Id>();
   Set<Id> distinctOwnerIds = new Set<Id>();
   Set<Id> distinctRecordTypeIds = new Set<Id>();
   ```

3. **Prints the count + sample IDs + segmentation to the debug log** at the end. The validate step parses this output.

#### Sub-type templates

For each sub-type, here is the dry-run shape. Use the templates literally; substitute `<Object>`, `<Field>`, `<value>` per the plan. Do NOT add freeform logic beyond what the plan specified.

##### `data-update-anonymous-apex` (dry-run)

```apex
// SF-DATA-CORRECTION DRY-RUN — <TICKET-KEY>
// Sub-type: data-update-anonymous-apex
// Plan: $ARTIFACTS_DIR/plan.md
// THIS BLOCK PERFORMS NO DML. It reports what WOULD be affected.

Map<Id, SObject> dmlCandidates = new Map<Id, SObject>();
Set<Id> distinctAccountIds = new Set<Id>();
Set<Id> distinctOwnerIds = new Set<Id>();
Set<Id> distinctRecordTypeIds = new Set<Id>();

for (<Object> rec : [
    SELECT Id, OwnerId, <Field-1>, <Field-2>, <Account-lookup-if-present>, RecordTypeId
    FROM <Object>
    WHERE <plan.soql_where_clause>
    WITH USER_MODE
    LIMIT 50000
]) {
    // Same field assignment the LIVE version will do — captured, not executed.
    rec.<Field-1> = <new-value-1>;
    // ... additional field assignments from the plan ...

    dmlCandidates.put(rec.Id, rec);
    if (rec.<Account-lookup> != null) distinctAccountIds.add(rec.<Account-lookup>);
    distinctOwnerIds.add(rec.OwnerId);
    if (rec.RecordTypeId != null) distinctRecordTypeIds.add(rec.RecordTypeId);
}

// Sample (first 10) for engineer review at post-validate gate.
List<Id> sampleIds = new List<Id>();
Integer i = 0;
for (Id k : dmlCandidates.keySet()) {
    if (i >= 10) break;
    sampleIds.add(k);
    i++;
}

System.debug('DRY_RUN_COUNT=' + dmlCandidates.size());
System.debug('DRY_RUN_SAMPLE_IDS=' + JSON.serialize(sampleIds));
System.debug('DRY_RUN_DISTINCT_ACCOUNTS=' + distinctAccountIds.size());
System.debug('DRY_RUN_DISTINCT_OWNERS=' + distinctOwnerIds.size());
System.debug('DRY_RUN_DISTINCT_RECORD_TYPES=' + distinctRecordTypeIds.size());
```

##### `data-update-batch` (dry-run)

The dry-run for batch is a CLASS, not an anonymous block. It's invoked via `Database.executeBatch(new <ClassName>(), <scope>);` in a separate trigger anonymous block:

```apex
// SF-DATA-CORRECTION DRY-RUN — <TICKET-KEY>
// Sub-type: data-update-batch
// THIS CLASS PERFORMS NO DML. It reports what WOULD be affected.

public class <CorrectionName>DryRun implements Database.Batchable<SObject>, Database.Stateful {

    public Integer affectedCount = 0;
    public Set<Id> distinctAccountIds = new Set<Id>();
    public Set<Id> distinctOwnerIds = new Set<Id>();
    public Set<Id> distinctRecordTypeIds = new Set<Id>();
    public List<Id> sampleIds = new List<Id>();

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, OwnerId, <Field-1>, <Account-lookup>, RecordTypeId
            FROM <Object>
            WHERE <plan.soql_where_clause>
            WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<SObject> scope) {
        for (<Object> rec : (List<<Object>>) scope) {
            // Same logic the LIVE version will do — captured, not executed.
            rec.<Field-1> = <new-value-1>;
            affectedCount++;
            if (rec.<Account-lookup> != null) distinctAccountIds.add(rec.<Account-lookup>);
            distinctOwnerIds.add(rec.OwnerId);
            if (rec.RecordTypeId != null) distinctRecordTypeIds.add(rec.RecordTypeId);
            if (sampleIds.size() < 10) sampleIds.add(rec.Id);
        }
        // NO DML.
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('DRY_RUN_COUNT=' + affectedCount);
        System.debug('DRY_RUN_SAMPLE_IDS=' + JSON.serialize(sampleIds));
        System.debug('DRY_RUN_DISTINCT_ACCOUNTS=' + distinctAccountIds.size());
        System.debug('DRY_RUN_DISTINCT_OWNERS=' + distinctOwnerIds.size());
        System.debug('DRY_RUN_DISTINCT_RECORD_TYPES=' + distinctRecordTypeIds.size());
    }
}
```

Then a trigger anonymous block:

```apex
Database.executeBatch(new <CorrectionName>DryRun(), 200);
```

##### `data-delete-anonymous` (dry-run)

Identical SOQL to a delete operation, but the dry-run version accumulates IDs without calling `delete`:

```apex
// SF-DATA-CORRECTION DRY-RUN — <TICKET-KEY>
// Sub-type: data-delete-anonymous
// THIS BLOCK PERFORMS NO DML. It reports what WOULD be deleted.

Map<Id, SObject> deletionCandidates = new Map<Id, SObject>();
Set<Id> distinctAccountIds = new Set<Id>();
Set<Id> distinctOwnerIds = new Set<Id>();

for (<Object> rec : [
    SELECT Id, OwnerId, <Account-lookup>
    FROM <Object>
    WHERE <plan.soql_where_clause>
    WITH USER_MODE
    LIMIT 50000
]) {
    deletionCandidates.put(rec.Id, rec);
    if (rec.<Account-lookup> != null) distinctAccountIds.add(rec.<Account-lookup>);
    distinctOwnerIds.add(rec.OwnerId);
}

List<Id> sampleIds = new List<Id>();
Integer i = 0;
for (Id k : deletionCandidates.keySet()) {
    if (i >= 10) break;
    sampleIds.add(k);
    i++;
}

System.debug('DRY_RUN_COUNT=' + deletionCandidates.size());
System.debug('DRY_RUN_SAMPLE_IDS=' + JSON.serialize(sampleIds));
System.debug('DRY_RUN_DISTINCT_ACCOUNTS=' + distinctAccountIds.size());
System.debug('DRY_RUN_DISTINCT_OWNERS=' + distinctOwnerIds.size());
```

##### `data-delete-batch`, `data-insert`, `data-undelete`, `data-merge`

Same shape — SOQL + accumulator + debug-log emission of `DRY_RUN_COUNT`, `DRY_RUN_SAMPLE_IDS`, segmentation counts. For `data-insert`, the dry-run iterates the source records (CSV-read or Apex-generated) and counts them; for `data-merge`, the dry-run queries the survivor + duplicates and enumerates the cascade without calling `merge`.

For `data-merge` specifically, the dry-run is partial: merge has no clean accumulator form for the cascade (the cascade is a platform-side action of `Database.merge`). The dry-run reports only the survivor and duplicate IDs + the count of child records that would re-parent, queried explicitly. The merge gate's `CONFIRM` requirement is the primary safety mechanism for this sub-type.

### Step 3 — Author the LIVE artifact via mechanical transform

Once `correction-dry-run.apex` is complete, derive `$ARTIFACTS_DIR/correction.apex` by mechanical substitution. Do NOT freeform-author the live version.

Substitution rules:

| Dry-run line | Live line |
|---|---|
| `Map<Id, SObject> dmlCandidates = new Map<Id, SObject>();` | `List<<Object>> recordsToUpdate = new List<<Object>>();` (or `recordsToDelete`, `recordsToInsert` per sub-type) |
| `dmlCandidates.put(rec.Id, rec);` | `recordsToUpdate.add(rec);` |
| `deletionCandidates.put(rec.Id, rec);` | `recordsToDelete.add(rec);` |
| `System.debug('DRY_RUN_COUNT=...');` | `System.debug('ACTUAL_COUNT=' + recordsToUpdate.size());` (after DML) |
| `System.debug('DRY_RUN_SAMPLE_IDS=...');` | `System.debug('ACTUAL_SAMPLE_IDS=' + JSON.serialize(sampleIds));` |
| `// NO DML.` | the actual DML call (per sub-type below) |

DML calls by sub-type (`AccessLevel.USER_MODE` is REQUIRED when `fls_posture == "USER_MODE"`):

- `data-update-anonymous-apex` / `data-update-batch`:
  `Database.SaveResult[] results = Database.update(recordsToUpdate, false, AccessLevel.USER_MODE);`
- `data-insert`:
  `Database.SaveResult[] results = Database.insert(recordsToInsert, false, AccessLevel.USER_MODE);`
- `data-delete-anonymous` / `data-delete-batch`:
  `Database.DeleteResult[] results = Database.delete(recordsToDelete, false, AccessLevel.USER_MODE);`
  AND capture deleted IDs to a list for the artifact:
  `List<Id> actuallyDeletedIds = new List<Id>(); for (Database.DeleteResult r : results) { if (r.isSuccess()) actuallyDeletedIds.add(r.getId()); }`
  `System.debug('ACTUAL_DELETED_IDS=' + JSON.serialize(actuallyDeletedIds));`
- `data-undelete`:
  `Database.UndeleteResult[] results = Database.undelete(recordsToUndelete, false, AccessLevel.USER_MODE);`
- `data-merge`:
  `Database.MergeResult result = Database.merge(survivor, duplicateIds, false);` — note: merge does NOT accept `AccessLevel`; FLS is enforced via the SOQL that loaded the records. The plan's `system_mode_justification` should explicitly cover this if applicable.

For `data-update-batch` / `data-delete-batch`, the substitution happens inside the batch class's `execute()` method; the `start()` and `finish()` methods are otherwise identical to the dry-run version (different class name: `<CorrectionName>` vs `<CorrectionName>DryRun`).

### Step 4 — Capture the deleted-IDs artifact (delete sub-types only)

For `data-delete-anonymous` and `data-delete-batch`, the LIVE Apex's debug-log emission of `ACTUAL_DELETED_IDS` is what validate parses and writes to `$ARTIFACTS_DIR/data-correction-deleted-ids.json`. Your job here is only to ensure the live Apex emits the debug line correctly; validate handles the parsing.

### Step 5 — FLS posture enforcement

If `$plan.output.fls_posture == "USER_MODE"`:

- Every SOQL in both artifacts MUST include `WITH USER_MODE`. Verify by grep-checking your own output before emitting.
- Every DML in the live artifact MUST include `AccessLevel.USER_MODE`. Verify same.

If `$plan.output.fls_posture == "SYSTEM_MODE"`:

- The plan's `system_mode_justification` must be non-null. If it's null, fail with `execute_status: fls_posture_invalid` and emit an error explaining that SYSTEM_MODE without justification is rejected.
- Both artifacts run without USER_MODE qualifiers. Add a comment header to each artifact explaining the justification (so engineers reading the artifact later understand the context).

Validate has its own FLS posture check that re-greps the artifacts. Producing artifacts that fail validate's check means re-running execute — surface the error here to fail fast.

### Step 6 — Do not write to the engagement source tree

Apex artifacts live in `$ARTIFACTS_DIR/` (the run-specific artifact directory), NOT in `force-app/main/default/classes/` or anywhere else in the engagement source. Data corrections are one-shot; they don't persist as source. The document phase may write an engagement ADR (for recurring patterns) but that's a separate concern.

If the engineer wants to preserve the Apex for the audit trail, the Jira comment (posted by `update-jira-on-completion.md`) includes the artifact path — the engineer can copy it manually if needed.

### Step 7 — Stage the changes

The engagement source tree should be UNTOUCHED by this step. Run `git status --porcelain` and confirm no changes outside `$ARTIFACTS_DIR/`. If any changes appear in the engagement source tree, fail with `execute_status: unexpected_source_changes` and list the unexpected paths.

## Output

Emit a structured JSON summary on stdout:

```json
{
  "execute_status": "success",
  "dry_run_artifact": "$ARTIFACTS_DIR/correction-dry-run.apex",
  "live_artifact": "$ARTIFACTS_DIR/correction.apex",
  "sub_type": "data-update-anonymous-apex",
  "fls_posture_in_artifacts": "USER_MODE",
  "transform_method": "mechanical-substitution-from-dry-run",
  "files_changed_count": 0,
  "engagement_source_untouched": true
}
```

On failure, emit:

```json
{
  "execute_status": "failed",
  "execute_failure_reason": "<one-paragraph: what went wrong>",
  "dry_run_artifact": null,
  "live_artifact": null
}
```

Failures should be rare — they indicate either a malformed plan, a missing pattern, or an FLS posture inconsistency. The validate step's FLS re-check is a second line of defense; producing a failed execute here aborts the workflow before any Apex runs.

The model used for this node is `opus[1m]` (per the workflow YAML). The dry-run / live transform is the heaviest reasoning step in this family.
