---
title: Apex Trigger Handler
audience: public
last_updated: 2026-05-10
last_updated_by: harness-phase-1
related_tickets: []
related_docs: [bulkified-soql-update.md, testdatafactory-usage.md]
---

# Apex Trigger Handler

The trigger itself contains no logic. It dispatches to a handler class which exposes one method per trigger event. The handler is the only place where business logic touching this object's lifecycle lives.

## When to apply

- **Always**, when writing or modifying any Apex trigger on any object.
- When refactoring legacy triggers that have business logic inline.
- When multiple processes need to react to the same DML event on the same object — they belong in the same handler, ordered explicitly.

## When NOT to apply

- For pure read-only side effects achievable through Flows or declarative tools — prefer those.
- For cross-object aggregations that fit Roll-Up Summary fields — those are simpler.
- For one-shot data corrections — those are not triggers; use anonymous Apex.

## The pattern

### Step 1: the trigger is one line of dispatch per event

```apex
trigger RenewalTrigger on Renewal__c (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new RenewalTriggerHandler().run();
}
```

The trigger declares the events it cares about. It instantiates the handler and calls a single entry point. No logic, no `Trigger.new` access, no `if (Trigger.isInsert)` branching. Ever.

### Step 2: the handler extends a thin base

```apex
public abstract class TriggerHandler {
    public void run() {
        if (!isEnabled()) return;
        if (Trigger.isBefore && Trigger.isInsert)   { beforeInsert(); }
        if (Trigger.isBefore && Trigger.isUpdate)   { beforeUpdate(); }
        if (Trigger.isBefore && Trigger.isDelete)   { beforeDelete(); }
        if (Trigger.isAfter && Trigger.isInsert)    { afterInsert(); }
        if (Trigger.isAfter && Trigger.isUpdate)    { afterUpdate(); }
        if (Trigger.isAfter && Trigger.isDelete)    { afterDelete(); }
        if (Trigger.isAfter && Trigger.isUndelete)  { afterUndelete(); }
    }

    protected virtual Boolean isEnabled() { return true; }

    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}
    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}
}
```

The base only knows how to dispatch. It provides a kill switch (`isEnabled()`) for emergencies — see "Disable mechanism" below.

### Step 3: the concrete handler implements the events it needs

```apex
public with sharing class RenewalTriggerHandler extends TriggerHandler {

    private List<Renewal__c> newRenewals = (List<Renewal__c>) Trigger.new;
    private Map<Id, Renewal__c> oldMap   = (Map<Id, Renewal__c>) Trigger.oldMap;

    protected override void beforeInsert() {
        applyDefaults(newRenewals);
        validateAmount(newRenewals);
    }

    protected override void afterUpdate() {
        List<Renewal__c> statusChanged = filterByStatusChange(newRenewals, oldMap);
        if (statusChanged.isEmpty()) return;
        publishStatusChangeEvents(statusChanged);
        recalculateAccountRenewalRollup(statusChanged);
    }

    // ── domain logic ─────────────────────────────────────────────

    private void applyDefaults(List<Renewal__c> renewals) {
        for (Renewal__c r : renewals) {
            if (r.Status__c == null) {
                r.Status__c = 'Draft';
            }
        }
    }

    private void validateAmount(List<Renewal__c> renewals) {
        for (Renewal__c r : renewals) {
            if (r.Amount__c != null && r.Amount__c < 0) {
                r.Amount__c.addError('Amount must be non-negative.');
            }
        }
    }

    // ... more focused private methods ...
}
```

Each public override stays small and delegates to private methods named for what they do (`applyDefaults`, `validateAmount`, `filterByStatusChange`). Domain logic lives in the private methods.

### Step 4: the handler is bulk-safe by construction

The handler operates on `Trigger.new` and `Trigger.oldMap` as collections, never per-record. SOQL and DML are issued once per logical operation, outside any loop. See [`bulkified-soql-update.md`](./bulkified-soql-update.md) for the bulkification rules.

### Step 5: the handler is tested through the trigger

The trigger fires the handler; tests insert, update, and delete records to exercise each event:

```apex
@IsTest
private class RenewalTriggerHandlerTest {

    @IsTest
    static void beforeInsert_appliesDraftStatus_whenStatusNull() {
        // arrange
        Renewal__c r = TestDataFactory.buildRenewal();
        r.Status__c = null;

        // act
        Test.startTest();
        insert r;
        Test.stopTest();

        // assert
        Renewal__c reloaded = [SELECT Status__c FROM Renewal__c WHERE Id = :r.Id];
        System.assertEquals('Draft', reloaded.Status__c);
    }

    // ... tests for each branch ...
}
```

See [`testdatafactory-usage.md`](./testdatafactory-usage.md) for the test data factory contract.

## Anti-patterns

### ❌ Logic in the trigger

```apex
trigger RenewalTrigger on Renewal__c (before insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        for (Renewal__c r : Trigger.new) {
            if (r.Status__c == null) r.Status__c = 'Draft';   // <-- logic in trigger
        }
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        // ... 50 more lines ...
    }
}
```

**Why it's wrong:** triggers can't be inherited, mocked, or composed. Multiple processes touching the same object pile up in the same trigger and become unreadable. Testing branches requires forcing all conditions through a single entry point. The handler pattern exists to fix all of that.

### ❌ Multiple triggers on one object

```apex
trigger RenewalAuditTrigger on Renewal__c (after update) { ... }
trigger RenewalNotificationTrigger on Renewal__c (after update) { ... }
```

**Why it's wrong:** Salesforce does not guarantee execution order between triggers on the same object. If both triggers update related records, race conditions and duplicate work follow. **One trigger per object** — multiple processes coexist inside the handler, ordered explicitly.

### ❌ SOQL inside a loop

```apex
protected override void afterUpdate() {
    for (Renewal__c r : newRenewals) {
        Account a = [SELECT Renewal_Total__c FROM Account WHERE Id = :r.Account__c];   // <-- per-record SOQL
        a.Renewal_Total__c += r.Amount__c;
        update a;                                                                       // <-- per-record DML
    }
}
```

**Why it's wrong:** governor limits will fire in production on bulk updates. See [`bulkified-soql-update.md`](./bulkified-soql-update.md) for the correct shape.

## Variations

### Variant: framework-based handlers

Several open-source frameworks (e.g., `fflib-apex-common` Domain Layer, Kevin O'Hara's `sfab` triggers, Andrew Fawcett's domain pattern) provide richer handler bases with separation of unit-of-work, domain methods, and trigger orchestration. **Adopt one only if a single project's complexity warrants it** and document the choice in an ADR. The default handler base above is sufficient for most engagements.

### Variant: disable mechanism via Custom Metadata

The base handler's `isEnabled()` reads a Custom Metadata Type that lets ops disable a handler without code changes during incidents. Implement when the engagement has on-call rotation:

```apex
protected virtual Boolean isEnabled() {
    Trigger_Settings__mdt setting =
        Trigger_Settings__mdt.getInstance(this.getClass().getName());
    return setting == null || setting.IsEnabled__c;
}
```

## Tests

Each event override has at least one test. Tests use `TestDataFactory` (see [`testdatafactory-usage.md`](./testdatafactory-usage.md)) and bulk-test critical paths with at least 200 records to verify governor compliance.

```apex
@IsTest
static void afterUpdate_handles200RecordBulk_withinDmlLimits() {
    List<Renewal__c> renewals = TestDataFactory.createRenewals(200);
    Test.startTest();
    for (Renewal__c r : renewals) r.Status__c = 'Active';
    update renewals;
    Test.stopTest();
    // assertions
}
```

## Constraints and gotchas

- **Recursive trigger invocation.** If `afterUpdate` updates the same object, the trigger fires again. Track recursion via a static `Set<Id>` on the handler if your logic requires a record to pass through `afterUpdate` only once per transaction.
- **`Trigger.new` is null in test contexts** that don't perform DML. Tests must `insert` / `update` real records to exercise the handler.
- **`with sharing` on the handler** is not enough to enforce FLS — see [`fls-crud-enforcement.md`](./fls-crud-enforcement.md) for FLS handling in trigger logic.
- **Ordering between processes** in the same handler is the developer's responsibility. Order the calls inside each event override deliberately and comment on dependencies.

## References

- **Salesforce Apex Developer Guide:** [Triggers and Order of Execution](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_triggers_order_of_execution.htm).
- **Apex Recipes (Salesforce):** [TriggerHandler example](https://github.com/trailheadapps/apex-recipes).
- **Related patterns:** [`bulkified-soql-update.md`](./bulkified-soql-update.md), [`fls-crud-enforcement.md`](./fls-crud-enforcement.md), [`testdatafactory-usage.md`](./testdatafactory-usage.md).

## History

- **2026-05-10:** initial Phase 1 authoring.
