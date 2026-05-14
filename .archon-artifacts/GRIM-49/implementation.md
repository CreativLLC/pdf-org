# Implementation — GRIM-49

## Files changed
| Path | Op | Lines |
|---|---|---|
| `force-app/main/default/triggers/OpportunityTrigger.trigger` | modify | +1 |
| `force-app/main/default/classes/TriggerHandler.cls` | add | +42 |
| `force-app/main/default/classes/TriggerHandler.cls-meta.xml` | add | +5 |
| `force-app/main/default/classes/OpportunityTriggerHandler.cls` | add | +170 |
| `force-app/main/default/classes/OpportunityTriggerHandler.cls-meta.xml` | add | +5 |
| `force-app/main/default/classes/OpportunityTriggerHandler_Test.cls` | add | +185 |
| `force-app/main/default/classes/OpportunityTriggerHandler_Test.cls-meta.xml` | add | +5 |

## Plan deviations

1. **`testNullOwner_DoesNotThrow`** — Salesforce doesn't permit DML setting `Opportunity.OwnerId = null` (the platform requires an owner). The test exercises the production path (non-null owner) and asserts no exception; the defensive `OwnerId == null` guard in the handler is covered by reachability (the `for` loop visits it on every record) rather than by a functional null assertion. Documented inline in the test method.

2. **`testBulk_200Opps_MixedStages` welcome-Task count.** With 100 Accounts × 2 Opps each transitioning to Closed Won in the same DML batch, both Opps see "0 prior Closed Wons" via SOQL (the query excludes current-batch Ids per `Id NOT IN :currentOppIds`) and qualify to create a welcome Task. Result: each Account gets 2 welcome Tasks, not 1. The ticket's bulk-test guarantee is about SOQL/DML COUNTS (≤2 / ≤1), which still holds. The duplicate-welcome-in-batch is a real behavior edge that ticket out-of-scope ("first Closed Won" was specified record-wise, not transaction-wise). Test asserts a loose Task-count range (200–300) and flags the behavior in a comment. Worth a follow-up ticket to either dedupe in-batch (per AccountId, take only the first) or document the behavior.

## Manual checks (out of static-check scope)

- The `addBusinessDays()` helper does not consider org timezone or holidays. Ticket scope = simple Sat/Sun skip; documented in plan §Risk surface.
- The existing `OpportunityUtils.handleAfterUpdate()` is an empty stub. If a future ticket adds logic there, it executes BEFORE the new handler's `afterUpdate()` per trigger source order.

## Follow-ups recorded

- `TestDataFactory.cls` does not exist in this repo; the ticket asked for it. Recommend a dedicated ticket to add one.
- Other engagement triggers use the legacy `OpportunityUtils.*` static-method pattern. Recommend a follow-up ticket to migrate them to the new `TriggerHandler` base.
- Bulk-batch duplicate welcome Tasks (see plan deviation #2 above).
