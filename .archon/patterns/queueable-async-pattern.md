---
title: Queueable Async Pattern
audience: public
last_updated: 2026-05-14
last_updated_by: harness-phase-7
related_tickets: []
related_docs: [apex-callout-pattern.md, batch-apex-pattern.md, apex-trigger-handler.md]
---

# Queueable Async Pattern

Asynchronous Apex via `Queueable` — the modern preferred async mechanism. Used to defer work past a transaction boundary (so it can do things the calling transaction can't, like callouts after DML), to chain work across transactions, and to handle non-batch work that's too slow for synchronous execution.

## When to apply

- **Callouts after a DML.** A trigger inserts a record, then needs to notify an external system. The notification has to run in a Queueable.
- **Work that exceeds synchronous CPU or DML limits** but doesn't need batching (e.g., processing 50-500 records that touch many objects each).
- **Chaining sequential work** that must run after a prior step's transaction commits.
- **Deferring expensive computation** out of a user-facing flow (e.g., re-rolling-up calculated fields after a parent record changes).

## When NOT to apply

- For **mass operations on 10K+ records** — use Batch Apex (`batch-apex-pattern.md`) for built-in chunking + governor isolation per chunk.
- For **scheduled work** running at a fixed cadence — use Scheduled Apex (`@scheduled` class) or a Scheduled Flow.
- For **synchronous work that fits in one transaction** — async adds complexity; don't add it unless you need to cross a transaction boundary.
- For **fire-and-forget event broadcasts** — use Platform Events.

## The pattern

### Step 1: Implements `Queueable` (and `Database.AllowsCallouts` if needed)

```apex
public class StripeChargeJob implements Queueable, Database.AllowsCallouts {

    private final Decimal amountUsdCents;
    private final String customerId;
    private final Id sourceRecordId;
    private final Integer attempt;

    private static final Integer MAX_ATTEMPTS = 3;

    public StripeChargeJob(Decimal amount, String customer, Id source, Integer attempt) {
        this.amountUsdCents = amount;
        this.customerId = customer;
        this.sourceRecordId = source;
        this.attempt = attempt;
    }

    public void execute(QueueableContext ctx) {
        StripeService.Result r = StripeService.createCharge(amountUsdCents, customerId);

        if (r.success) {
            updateSourceRecordSucceeded();
            return;
        }

        if (r.isTransient && attempt < MAX_ATTEMPTS) {
            // Chain: requeue with attempt+1
            System.enqueueJob(new StripeChargeJob(amountUsdCents, customerId, sourceRecordId, attempt + 1));
            return;
        }

        // Permanent failure OR exhausted retries
        recordPermanentFailure(r.errorMessage);
    }

    private void updateSourceRecordSucceeded() { /* ... */ }
    private void recordPermanentFailure(String reason) { /* ... */ }
}
```

Constructor captures all inputs as `final` fields. `execute()` reads them; the job is self-contained.

### Step 2: Enqueue from the trigger / caller

```apex
public class RenewalTriggerHandler extends TriggerHandler {
    public override void afterUpdate() {
        List<Renewal__c> closedWon = filterForClosedWon((List<Renewal__c>) Trigger.new, (Map<Id, Renewal__c>) Trigger.oldMap);
        for (Renewal__c r : closedWon) {
            // One Queueable per record OR one Queueable processing all records — choose based on
            // expected DML/callout volume per record. For most cases, one-job-per-batch is fine
            // because Queueable has its own DML+callout budget.
            System.enqueueJob(new StripeChargeJob(r.Amount__c * 100, r.Stripe_Customer_Id__c, r.Id, 1));
        }
    }
}
```

### Step 3: Bulk-safe job that processes many records

For volumes where N-Queueable-jobs would explode the count, build one job that processes the whole list:

```apex
public class BulkRenewalNotifyJob implements Queueable, Database.AllowsCallouts {
    private final List<Id> renewalIds;

    public BulkRenewalNotifyJob(List<Id> ids) { this.renewalIds = ids; }

    public void execute(QueueableContext ctx) {
        for (Renewal__c r : [SELECT Id, Amount__c, Stripe_Customer_Id__c FROM Renewal__c WHERE Id IN :renewalIds]) {
            // process — but watch the Queueable's callout limit (100 callouts per transaction)
        }
    }
}
```

If `renewalIds.size()` could exceed callout governor limits, switch to Batch Apex.

## Anti-patterns

❌ **Storing SObjects in instance fields.** `private Renewal__c rec;` — at enqueue time the record state freezes, but by execution time it may have changed. Store IDs and re-query.

❌ **Infinite chains.** A Queueable that always enqueues another Queueable without a termination condition. Always track `attempt` (or similar) and stop at a max.

❌ **Implementing `Queueable` AND `Schedulable` AND `Batchable` on one class.** Each has different semantics; combining them obscures intent. Pick one per class.

❌ **Forgetting `Database.AllowsCallouts`.** Without it, the job can't do HTTP work. Add it whenever the job's `execute()` might call out, even indirectly.

❌ **Using `@future` for new code.** Queueable supersedes `@future`. It supports chaining, accepts SObject parameters via IDs, and runs more reliably. Migrate `@future` to Queueable when touching legacy code.

❌ **Putting all the work in `execute()` without splitting.** If `execute()` is 200 lines, the job is doing too much. Factor pieces into helper methods or service classes; keep `execute()` orchestration-only.

## Testing

```apex
@IsTest
private class StripeChargeJobTest {
    @IsTest
    static void execute_success_updatesSourceRecord() {
        Test.setMock(HttpCalloutMock.class, new StripeChargeSuccessMock());
        // ... set up source record ...

        Test.startTest();
        System.enqueueJob(new StripeChargeJob(2500, 'cus_abc', sourceId, 1));
        Test.stopTest();        // forces the job to run synchronously

        Renewal__c after = [SELECT Stripe_Charge_Id__c FROM Renewal__c WHERE Id = :sourceId];
        System.assertNotEquals(null, after.Stripe_Charge_Id__c);
    }
}
```

`Test.startTest()` / `Test.stopTest()` forces async jobs enqueued inside that block to run synchronously before the assertion — that's the standard way to test Queueables.

## References

- [Salesforce: Queueable Apex](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_queueing_jobs.htm)
- [`apex-callout-pattern.md`](./apex-callout-pattern.md) — for the inner `StripeService` (the callout this job wraps)
- [`batch-apex-pattern.md`](./batch-apex-pattern.md) — for volumes too large for Queueable
- [`apex-trigger-handler.md`](./apex-trigger-handler.md) — where Queueables are typically enqueued from
