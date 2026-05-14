# Plan — GRIM-49: Opportunity stage-change automation

## Sub-type
`modify-trigger` (medium scope) — existing `OpportunityTrigger.trigger` is modified additively.

## Acceptance criteria (from ticket)
1. After-update trigger branches on `StageName` change to `Negotiation/Review` or `Closed Won`.
2. Negotiation/Review → 1 Task on Opp owner ("Draft proposal for …", today+3 business days).
3. Closed Won → 1 Task on Opp owner ("Send thank-you + invoice …", today+1 business day) **+** if zero OTHER Closed-Won Opps on the parent Account, a 2nd Task on Account owner ("Welcome new customer: …", today+2 business days).
4. Bulk-safe: 1 Account SOQL, 1 Opportunity SOQL, 1 DML insert per transaction (200-row stress test).
5. No-ops: stage didn't change, IsDeleted, null OwnerId, null AccountId on welcome path.
6. FLS/CRUD: explicit `Schema.sObjectType.Task.isCreateable()` + per-field; Account.OwnerId `isAccessible()`; throw custom exception on failure.
7. Test class with 8 specific methods; coverage threshold from ticket = 85% (see Risks below).
8. Use harness `apex-trigger-handler` pattern (don't invent framework); existing trigger preserved.

## Files changed
| Path | Op |
|---|---|
| `force-app/main/default/triggers/OpportunityTrigger.trigger` | modify |
| `force-app/main/default/triggers/OpportunityTrigger.trigger-meta.xml` | unchanged (exists) |
| `force-app/main/default/classes/TriggerHandler.cls` | add (framework base) |
| `force-app/main/default/classes/TriggerHandler.cls-meta.xml` | add |
| `force-app/main/default/classes/OpportunityTriggerHandler.cls` | add |
| `force-app/main/default/classes/OpportunityTriggerHandler.cls-meta.xml` | add |
| `force-app/main/default/classes/OpportunityTriggerHandler_Test.cls` | add |
| `force-app/main/default/classes/OpportunityTriggerHandler_Test.cls-meta.xml` | add |

## Design

### Trigger (additive modification)
Existing trigger calls `OpportunityUtils.handle*()` static methods (Utils pattern). Per ticket, follow harness `apex-trigger-handler.md` pattern. The cleanest additive merge:

```apex
trigger OpportunityTrigger on Opportunity (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    // Existing Utils-style dispatch (preserved; empty handleAfterUpdate is a no-op today).
    if (Trigger.isBefore) {
        if (Trigger.isInsert) OpportunityUtils.handleBeforeInsert();
        else if (Trigger.isUpdate) OpportunityUtils.handleBeforeUpdate();
        else if (Trigger.isDelete) OpportunityUtils.handleBeforeDelete();
    } else if (Trigger.isAfter) {
        if (Trigger.isInsert) OpportunityUtils.handleAfterInsert();
        else if (Trigger.isUpdate) OpportunityUtils.handleAfterUpdate();
        else if (Trigger.isDelete) OpportunityUtils.handleAfterDelete();
        else if (Trigger.isUndelete) OpportunityUtils.handleAfterUndelete();
    }
    // New: harness-pattern dispatch for stage-change Task automation (GRIM-49).
    new OpportunityTriggerHandler().run();
}
```

The trigger keeps the legacy Utils dispatch and adds one line for the handler. The handler's base `TriggerHandler.run()` only routes the `after update` event, so other event types are no-ops within the handler — no double-dispatch hazard.

### `TriggerHandler.cls` (new framework base)
Verbatim per the pattern's Step 2 (abstract dispatcher with `isEnabled()` kill switch + virtual hooks). Allows future triggers to migrate to the pattern incrementally.

### `OpportunityTriggerHandler.cls`
Extends `TriggerHandler`. Overrides `afterUpdate()`. Logic:

1. Walk `Trigger.new` casting to `List<Opportunity>`; for each new record, compare `StageName` to `Trigger.oldMap.get(id).StageName`. Skip if equal, `IsDeleted`, or `OwnerId == null`.
2. Partition changed Opps into two lists: `negotiationOpps` (stage now = `Negotiation/Review`) and `closedWonOpps` (stage now = `Closed Won`). Drop everything else.
3. **One SOQL on Opportunity** (only if `closedWonOpps` non-empty): count prior Closed-Won Opps grouped by AccountId. SOQL form:
   ```apex
   List<AggregateResult> ars = [
       SELECT AccountId, COUNT(Id) cnt
       FROM Opportunity
       WHERE AccountId IN :accountIds
         AND StageName = 'Closed Won'
         AND Id NOT IN :currentOppIds
       GROUP BY AccountId
       WITH USER_MODE
   ];
   ```
   Build `Map<Id, Integer> priorCwCountByAccount` from results (missing keys → 0).
4. **One SOQL on Account** (only if `closedWonOpps` non-empty and we need Account.OwnerId):
   ```apex
   Map<Id, Account> accountById = new Map<Id, Account>([
       SELECT Id, Name, OwnerId
       FROM Account
       WHERE Id IN :accountIds
       WITH USER_MODE
   ]);
   ```
   Plus explicit `Schema.sObjectType.Account.fields.OwnerId.isAccessible()` precheck (ticket-required); throw `OpportunityTriggerHandler.FlsException` if false.
5. **Build `List<Task> tasksToInsert`** — proposal Tasks for `negotiationOpps`, thank-you Tasks for `closedWonOpps`, welcome Tasks where `priorCwCountByAccount` is missing/zero AND `AccountId != null`.
6. **CRUD precheck** on `Task` + each field used (Subject, WhatId, OwnerId, ActivityDate, Status) via `Schema.sObjectType.Task.isCreateable()` and per-field `.fields.<X>.isCreateable()`. Throw `FlsException` with a descriptive message if any fail.
7. **One DML insert** with `AccessLevel.USER_MODE` (also satisfies the static FLS/CRUD check):
   ```apex
   if (!tasksToInsert.isEmpty()) {
       Database.insert(tasksToInsert, AccessLevel.USER_MODE);
   }
   ```

### Business-day helper
`today + 3 business days` is Salesforce's `BusinessDays.add()` ideally, but `BusinessDays` is a SOAP-API construct. The simplest Apex implementation: loop forward N times, skipping Saturday/Sunday. Document holidays as out-of-scope (per ticket, no custom config).

```apex
private static Date addBusinessDays(Date startDate, Integer days) {
    Date d = startDate;
    Integer added = 0;
    while (added < days) {
        d = d.addDays(1);
        Datetime dt = Datetime.newInstance(d, Time.newInstance(0,0,0,0));
        String dow = dt.format('EEE');
        if (dow != 'Sat' && dow != 'Sun') added++;
    }
    return d;
}
```

### Custom exception
```apex
public class FlsException extends Exception {}
```
Inner class on the handler; thrown when any CRUD/FLS precheck fails. Ticket says "do not silently swallow" → no try/catch.

## Test strategy
`OpportunityTriggerHandler_Test.cls` with the 8 required methods. Each method:
- `@IsTest static void <name>()` with inline fixture setup (no TestDataFactory exists in this repo — see Risks).
- Uses `System.runAs(testUser)` to exercise FLS where appropriate; otherwise uses System Admin.
- Asserts on `[SELECT WhatId, Subject, OwnerId, ActivityDate FROM Task]` after the DML.
- Bulk test (`testBulk_200Opps_MixedStages`) wraps the update in `Test.startTest()` / `Test.stopTest()` and asserts `Limits.getQueries() <= 2` (Account+Opportunity SOQLs) and `Limits.getDmlStatements() <= 1` (one Task insert).

Coverage: per-class threshold per `engagement.yaml: salesforce.coverage.per_class_target` = **75%**. Ticket asks for ≥85%; we target 100% on the handler (8 tests across all branches) which exceeds both. The workflow's gate enforces 75; if the engineer wants the stricter 85, they can manually verify after.

## Patterns / standards
- `apex-trigger-handler.md` → followed: zero logic in `.trigger`, base abstract dispatcher, concrete handler overrides exactly the events it needs. **Adherence note:** existing Utils dispatch preserved alongside; not a pure migration of the legacy code.
- `fls-crud-enforcement.md` → followed: `with sharing` on all classes; `WITH USER_MODE` on both SOQL queries; `AccessLevel.USER_MODE` on the DML; explicit isCreateable/isAccessible prechecks layered on top (ticket-required).
- `bulkified-soql-update.md` → followed: SOQL in IN-list form, no per-record queries inside the loop; aggregate count by AccountId; one DML for all Tasks.
- `testdatafactory-usage.md` → **NOT followed.** No TestDataFactory class exists in this repo. Test fixtures will be inline. Adding TestDataFactory is out of scope for this ticket; flagged in follow-ups.

## Documentation outputs
- `docs/changelog/2026-05/GRIM-49.md` (always)
- Update `docs/objects/Opportunity.md` "Apex automation" section to describe the new handler and trigger event (per ADR-0009 §8: trigger changes must update the object doc).

## Risk surface
1. **Adding a new framework class (`TriggerHandler.cls`).** Currently the engagement uses the Utils pattern across 11+ triggers. We're introducing the harness `TriggerHandler` base alongside it. This is what the ticket asks for, but it means two patterns coexist. **Follow-up ticket recommended** to migrate legacy triggers to the new pattern incrementally.
2. **Coverage threshold mismatch.** Ticket asks for ≥85%, engagement.yaml has 75%. The workflow enforces 75. Plan targets 100% on the handler so both thresholds are exceeded.
3. **No TestDataFactory.** Ticket says use it; doesn't exist. Tests will inline-create fixtures. Recommend a follow-up ticket to add a TestDataFactory.
4. **Coexistence with existing OpportunityUtils.handleAfterUpdate().** Currently an empty stub. If a future ticket adds logic to either side, the order of execution between `OpportunityUtils.handleAfterUpdate()` and the new handler's `afterUpdate()` is: Utils first, then handler (in trigger source order). Document this in the changelog.
5. **Business-day calculation uses local Apex date.** No org-timezone or holiday awareness. Ticket explicitly puts this out of scope ("no custom fields, no Flows"); proceeding with simple Sat/Sun-skip is correct per the ticket.

## Out-of-scope ACs
None; all 8 ACs and all 8 test methods will be implemented.

## Follow-ups recorded
- TestDataFactory class missing — recommend dedicated ticket.
- Migrate other engagement triggers to harness `TriggerHandler` pattern — recommend dedicated ticket.
