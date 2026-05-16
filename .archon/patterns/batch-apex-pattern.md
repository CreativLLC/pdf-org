---
title: Batch Apex Pattern
audience: public
last_updated: 2026-05-14
last_updated_by: harness-phase-7
related_tickets: []
related_docs: [queueable-async-pattern.md, bulkified-soql-update.md]
---

# Batch Apex Pattern

Process **large** record sets (10K to many million) by chunking. Salesforce executes the batch class in serial chunks ("scope") with **fresh governor limits per chunk**, which is the only way to do mass operations without hitting per-transaction caps.

## When to apply

- **Mass updates over 10K records** — backfills, mass field re-calculations, lifecycle status sweeps.
- **Nightly / scheduled cleanups** — closing stale Cases, reassigning ownership for inactive Accounts.
- **Mass data corrections** that exceed Queueable's per-transaction limits.
- **Anything that needs `Database.QueryLocator`** — i.e., the source data is a SOQL result that exceeds the 50K-row synchronous SOQL cap.

## When NOT to apply

- For **<10K records** — use Queueable Apex per [queueable-async-pattern.md](./queueable-async-pattern.md). Batch's overhead (scheduling, per-chunk governor reset cost) isn't worth it below that volume.
- For **fire-and-forget single-record async** — Queueable.
- For **real-time data movement** — use Platform Events or Streaming API.
- When **the data source isn't a SOQL query** — Batch Apex's `Iterable` form exists but is mostly hostile to debug; use Queueable chaining instead.

## The pattern

### Step 1: implements `Database.Batchable<SObject>`

```apex
public class CloseStaleCasesBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final Integer staleThresholdDays;
    private Integer recordsClosed = 0;                  // tracked across chunks via Database.Stateful
    private final List<String> errors = new List<String>();

    public CloseStaleCasesBatch(Integer staleThresholdDays) {
        this.staleThresholdDays = staleThresholdDays;
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        Datetime cutoff = Datetime.now().addDays(-staleThresholdDays);
        return Database.getQueryLocator([
            SELECT Id, Status
            FROM Case
            WHERE Status = 'Waiting on Customer'
            AND LastModifiedDate < :cutoff
            WITH USER_MODE                              // FLS-aware per ADR-0009 §7
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<SObject> scope) {
        List<Case> cases = (List<Case>) scope;
        for (Case c : cases) {
            c.Status = 'Closed';
            c.Description = (c.Description == null ? '' : c.Description + '\n') +
                            '[Auto-closed by CloseStaleCasesBatch on ' + Date.today() + ']';
        }

        Database.SaveResult[] results = Database.update(cases, false);  // partial-success allowed
        for (Database.SaveResult r : results) {
            if (r.isSuccess()) {
                recordsClosed++;
            } else {
                errors.add(r.getErrors()[0].getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext ctx) {
        // Notify, log, chain next job — finish() is one final transaction
        String summary = 'CloseStaleCasesBatch complete: '
            + recordsClosed + ' Cases closed, '
            + errors.size() + ' errors.';
        LogService.info(summary);
        if (!errors.isEmpty()) {
            LogService.error('CloseStaleCasesBatch errors: ' + String.join(errors, '; '));
        }
        // Optional: chain another batch or queueable here
    }
}
```

### Step 2: invoke with a chosen scope size

```apex
// One-shot manual invocation
Database.executeBatch(new CloseStaleCasesBatch(30), 200);
//                                                  ^^^ scope = 200 records per chunk
```

**Scope size guidance:**
- Default 200 is fine for most cases.
- If `execute()` does a lot of SOQL/DML per record, drop scope to 50-100 to stay under per-chunk governor limits.
- If `execute()` does callouts (`Database.AllowsCallouts`), max scope is 10.
- If the records are small and `execute()` is light, you can go to 2000.

### Step 3: scheduled invocation (typical for cleanup jobs)

```apex
public class CloseStaleCasesScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new CloseStaleCasesBatch(30), 200);
    }
}

// One-time setup (anonymous Apex):
// System.schedule('Daily stale Case cleanup', '0 0 2 * * ?', new CloseStaleCasesScheduler());
```

`Database.Stateful` makes the batch's instance fields persist across chunks — needed to aggregate counts/errors across the run.

## Anti-patterns

❌ **Scope size = 2000 with heavy logic.** A scope that does 5 SOQL queries per record at scope 2000 = 10K queries; over governor cap. Tune scope DOWN.

❌ **Without `Database.Stateful`, expecting fields to persist.** Instance fields reset between chunks unless you implement `Database.Stateful`. If you need to count across chunks or accumulate errors, implement it.

❌ **`Database.update(cases, true)` instead of `Database.update(cases, false)`.** All-or-nothing fails the whole chunk on the first bad record. Partial-success (`false`) is almost always what you want for batch jobs.

❌ **No FLS posture.** Batch jobs run as `System Mode` by default. Add `WITH USER_MODE` to the start query AND use `Security.stripInaccessible(...)` on the DML to honor profile-level FLS per ADR-0009 §7 — or explicitly justify why `System Mode` is intentional in the class header.

❌ **Forgetting `finish()`.** It's required by the interface; even if you don't need it, implement an empty one — but losing the chance to log a summary is a missed opportunity for observability.

❌ **Queueable when Batch is right.** If you're processing 100K records by chaining a Queueable 500 times, you've reinvented Batch Apex without the governor isolation. Use the right tool.

❌ **Querying inside `execute()` that doesn't scale with scope.** Each chunk gets its own SOQL budget (100 queries), but if `execute()` does N queries per record (N>1), drop scope size to compensate.

## Testing

`Test.startTest()` / `Test.stopTest()` forces the batch to run synchronously in one chunk. For multi-chunk behavior, you can manually call `execute()` with different scopes.

```apex
@IsTest
private class CloseStaleCasesBatchTest {
    @TestSetup
    static void setup() {
        // Create test cases with LastModifiedDate beyond the threshold
        // (use Test.setCreatedDate / setLastModifiedDate equivalent if needed)
    }

    @IsTest
    static void execute_closesStaleCasesOnly() {
        Test.startTest();
        Database.executeBatch(new CloseStaleCasesBatch(30), 200);
        Test.stopTest();

        Integer closed = [SELECT COUNT() FROM Case WHERE Status = 'Closed' AND Description LIKE '%Auto-closed%'];
        System.assertEquals(expectedStaleCount, closed);
    }
}
```

## References

- [Salesforce: Batch Apex](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_batch_interface.htm)
- [`queueable-async-pattern.md`](./queueable-async-pattern.md) — for sub-10K-record async work
- [`bulkified-soql-update.md`](./bulkified-soql-update.md) — bulkification principles apply inside each batch chunk
