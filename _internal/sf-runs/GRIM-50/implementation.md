# Implementation — GRIM-50

## Files actually changed

| Path | Op | +/− | Notes |
|---|---|---|---|
| `force-app/main/default/triggers/ContactTrigger.trigger` | modify | +10 / −4 | Header `(before insert)` → `(before insert, before update)`. Wired `ContactPhoneNormalizer.normalize(...)` into the before-insert and before-update branches; left the dead `isAfter`/`isDelete`/`isUndelete` body branches in place since the trigger header still does not declare those events. |
| `force-app/main/default/classes/ContactPhoneNormalizer.cls` | add | new | Helper class. Public static `normalize(List<Contact>)`. `@TestVisible` private `formatPhone(String)` and a compiled `Pattern` for non-digit stripping. |
| `force-app/main/default/classes/ContactPhoneNormalizer.cls-meta.xml` | add | new | apiVersion 66.0. |
| `force-app/main/default/classes/ContactPhoneNormalizer_Test.cls` | add | new | 6 `@IsTest` methods exactly matching the AC test cases. The "already-formatted" test exercises both insert and update paths to prove idempotency on the new before-update branch. |
| `force-app/main/default/classes/ContactPhoneNormalizer_Test.cls-meta.xml` | add | new | apiVersion 66.0. |

## Plan deviations

None. The implementation matches the plan as written.

Minor execution decision worth recording: the empty-string test asserts `phone == null || phone == ''` because Salesforce sometimes coerces empty-string Phone to null at persistence time depending on storage path. Either result signals "no normalization applied," which is what the AC requires; tightening to a single value would make the test brittle.

## Anti-pattern checks out of scope for the FLS/CRUD static check

- The trigger does **no DML and no SOQL** — FLS/CRUD enforcement is not applicable here. The static check will record `n/a` or `pass` for this change.
- The trigger does NOT migrate to the `TriggerHandler` base class from GRIM-49. This is a deliberate scope decision (ticket says "modify additively"); a separate ticket should migrate `ContactTrigger` (and the other legacy `*Utils`-style triggers) to the new base.

## Follow-ups (not implemented; record in a separate ticket)

- Migrate `ContactTrigger` to the `TriggerHandler` base class. Same migration likely needed for `AccountTrigger`, `OpportunityTrigger`, `InvoiceTrigger`, `ProjectTrigger`, `TimeSheetTrigger`, etc. — all of them currently use the older `<Object>Utils.handle*` pattern that pre-dates GRIM-49.
- `ContactTrigger.trigger-meta.xml` is still on `apiVersion 50.0`; class metas in the engagement are drifting (49 / 50 / 60 / 66). Worth a sweep ticket to standardize.
