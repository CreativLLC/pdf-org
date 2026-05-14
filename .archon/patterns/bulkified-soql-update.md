---
title: Bulkified SOQL and DML
audience: public
last_updated: 2026-05-10
last_updated_by: harness-phase-1
related_tickets: []
related_docs: [apex-trigger-handler.md, fls-crud-enforcement.md]
---

# Bulkified SOQL and DML

All Apex code operates on collections, not individual records. SOQL and DML are issued **once per logical operation**, never inside a loop. This is the rule that keeps Apex within governor limits when bulk DML hits production.

## When to apply

- **Always**, in any Apex code that may be invoked with more than one record. That includes triggers, Queueable jobs, Batch Apex, REST endpoints, controllers, and helper methods.

## When NOT to apply

- Genuinely single-record contexts where the API contract guarantees `n=1` (e.g., a Custom Permission lookup that returns at most one record). Even then, structure the code so adding a second record doesn't require rewriting it.

## The pattern

### Step 1: collect the inputs first

Iterate the input collection to gather the IDs or keys you'll need to query, *without* doing any SOQL.

```apex
Set<Id> accountIds = new Set<Id>();
for (Renewal__c r : renewals) {
    if (r.Account__c != null) {
        accountIds.add(r.Account__c);
    }
}
```

### Step 2: query once, outside the loop

```apex
Map<Id, Account> accountById = new Map<Id, Account>([
    SELECT Id, Renewal_Total__c
    FROM Account
    WHERE Id IN :accountIds
    WITH USER_MODE
]);
```

One SOQL, regardless of how many renewals. The `Map<Id, ...>` shape gives O(1) lookups in step 3.

### Step 3: process the collection in memory

```apex
List<Account> toUpdate = new List<Account>();
for (Renewal__c r : renewals) {
    Account a = accountById.get(r.Account__c);
    if (a == null) continue;
    a.Renewal_Total__c = (a.Renewal_Total__c == null ? 0 : a.Renewal_Total__c) + r.Amount__c;
    toUpdate.add(a);
}
```

No SOQL, no DML in the loop. Just in-memory work.

### Step 4: DML once, outside the loop

```apex
if (!toUpdate.isEmpty()) {
    update Database.update(toUpdate, AccessLevel.USER_MODE);
}
```

One DML statement for the whole collection. The conditional avoids an empty DML which is wasteful.

## Anti-patterns

### ❌ SOQL in a loop

```apex
for (Renewal__c r : renewals) {
    Account a = [SELECT Id, Renewal_Total__c FROM Account WHERE Id = :r.Account__c];   // <-- per-record SOQL
    a.Renewal_Total__c += r.Amount__c;
    update a;                                                                            // <-- per-record DML
}
```

**Why it's wrong:** with 200 records, you've issued 200 SOQL queries (limit: 100) and 200 DML statements (limit: 150). The first batch update from a Data Loader run breaks the trigger. Inevitably.

### ❌ Hidden per-record DML via callouts

```apex
for (Renewal__c r : renewals) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Stripe/v1/invoices');
    req.setBody(JSON.serialize(buildPayload(r)));
    new Http().send(req);    // <-- per-record callout (limit: 100 per transaction)
}
```

**Why it's wrong:** even when you're not doing SOQL/DML, governor limits apply to callouts. Bulk operations exceed the 100-callout limit. Use Queueable or Platform Events to fan out work across transactions.

### ❌ Aggregating via List operations that hide loops

```apex
for (Renewal__c r : renewals) {
    List<Renewal_Line__c> lines = [SELECT Id FROM Renewal_Line__c WHERE Renewal__c = :r.Id];   // <-- hidden per-record SOQL
    // ...
}
```

**Why it's wrong:** even though the SOQL syntax looks "outside" the loop, the binding `:r.Id` makes it execute per record. Use `IN :collection` and a `Map<Id, List<Child>>` lookup.

```apex
// ✅ Correct
Set<Id> renewalIds = (new Map<Id, Renewal__c>(renewals)).keySet();
Map<Id, List<Renewal_Line__c>> linesByRenewal = new Map<Id, List<Renewal_Line__c>>();
for (Renewal_Line__c line : [
    SELECT Id, Renewal__c FROM Renewal_Line__c WHERE Renewal__c IN :renewalIds WITH USER_MODE
]) {
    if (!linesByRenewal.containsKey(line.Renewal__c)) {
        linesByRenewal.put(line.Renewal__c, new List<Renewal_Line__c>());
    }
    linesByRenewal.get(line.Renewal__c).add(line);
}
```

## Variations

### Variant: chunked DML for very large operations

When a single DML may exceed `DML rows per transaction` (10,000), split into chunks:

```apex
final Integer CHUNK = 5000;
for (Integer i = 0; i < toUpdate.size(); i += CHUNK) {
    Integer end = Math.min(i + CHUNK, toUpdate.size());
    Database.update(new List<Account>(toUpdate).subList(i, end), AccessLevel.USER_MODE);
}
```

This is rare and usually a sign that the work belongs in Batch Apex, not synchronous trigger logic.

### Variant: Queueable fan-out for callouts

When per-record callouts are required (rare — usually a single bulk-API call is preferable), enqueue Queueable jobs:

```apex
for (Renewal__c r : renewals) {
    System.enqueueJob(new RenewalCalloutJob(r.Id));
}
```

Each Queueable has its own governor limits. Note that `enqueueJob` itself has a per-transaction limit (50). For bulk fan-out, use Batch Apex or Platform Events.

### Variant: aggregate-functions instead of in-memory rollup

When the aggregation is simple (sum, count, max), prefer SOQL aggregate functions:

```apex
List<AggregateResult> totals = [
    SELECT Account__c accountId, SUM(Amount__c) total
    FROM Renewal__c
    WHERE Account__c IN :accountIds
    GROUP BY Account__c
    WITH USER_MODE
];
```

Cleaner than building a `Map<Id, Decimal>` in Apex, and avoids loading all child records into memory.

## Tests

Bulk-test critical Apex paths with at least 200 records:

```apex
@IsTest
static void afterUpdate_handles200RecordBulk_withinLimits() {
    List<Renewal__c> renewals = TestDataFactory.createRenewals(200);

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();

    for (Renewal__c r : renewals) r.Status__c = 'Active';
    update renewals;

    System.assert(Limits.getQueries() - queriesBefore < 5,
        'Expected handler to be bulkified; saw ' + (Limits.getQueries() - queriesBefore) + ' queries');
    System.assert(Limits.getDmlStatements() - dmlBefore < 5,
        'Expected handler to be bulkified; saw ' + (Limits.getDmlStatements() - dmlBefore) + ' DML statements');

    Test.stopTest();
}
```

Asserting on `Limits.getQueries()` and `Limits.getDmlStatements()` directly catches accidental loop-SOQL during refactors.

## Constraints and gotchas

- **`Database.query()` with dynamic SOQL** still counts against the SOQL limit, and the same bulkification rules apply.
- **`@future` methods** have separate limits per invocation but a per-transaction cap on how many you can spawn — don't fan out per-record.
- **Order of execution matters.** Triggers, Flows, Apex sharing rules, and validation rules all share the same governor limits inside one transaction. Bulkify defensively.
- **Mocked tests can mask bulk issues** — assert on actual `Limits` counters rather than mocking the database when bulk safety is what you're verifying.
- **`Map<Id, SObject>` constructed from a list iterates over the list under the hood.** That's fine — it's a single in-memory pass, not SOQL.

## References

- **Salesforce Apex Developer Guide:** [Apex Governor Limits](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm).
- **Trailhead:** [Apex Triggers — Bulk Apex Triggers](https://trailhead.salesforce.com/content/learn/modules/apex_triggers/apex_triggers_bulk).
- **Related patterns:** [`apex-trigger-handler.md`](./apex-trigger-handler.md), [`testdatafactory-usage.md`](./testdatafactory-usage.md).

## History

- **2026-05-10:** initial Phase 1 authoring.
