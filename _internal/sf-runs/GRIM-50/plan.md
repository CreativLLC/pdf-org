# Plan — GRIM-50

**Title:** Auto-format Contact Phone to (XXX) XXX-XXXX on save
**Sub-type:** `modify-trigger` (primary). Secondary: create-class + create-test for the helper and its tests. Per ADR-0009 precedence, `modify-trigger` wins as the routing sub-type.
**Scope:** small
**Status:** Backlog (`ready_for_dev`) — workable
**Touches SOQL/DML:** false (pure in-memory mutation of `Trigger.new`)
**Touches callouts:** false
**Needs external research:** false

## Acceptance criteria mapping

| AC | Plan element |
|---|---|
| Before-insert + before-update trigger on Contact | Extend `ContactTrigger.trigger` header from `(before insert)` to `(before insert, before update)` |
| Strip non-digits; 10-digit → `(XXX) XXX-XXXX`; 11-digit leading-1 → drop the 1, format; else unchanged | Implemented in `ContactPhoneNormalizer.normalize(List<Contact>)` |
| Bulk-safe, no SOQL/DML beyond the trigger | Pure in-place mutation of `Trigger.new`; single pass |
| Idempotent | `(XXX) XXX-XXXX` re-normalizes to identical 10-digit-stripped representation; no DML means no recursion |
| ≥85% per-class coverage (ticket-specific, overrides engagement default 75) | 6 test methods in `ContactPhoneNormalizer_Test` exercising each branch |

## File changes

| Path | Op | Notes |
|---|---|---|
| `force-app/main/default/triggers/ContactTrigger.trigger` | modify | Header `(before insert)` → `(before insert, before update)`. Add `ContactPhoneNormalizer.normalize((List<Contact>) Trigger.new);` in both before-insert and before-update branches. Keep existing `ContactUtils.handleBeforeInsert/Update` calls intact. |
| `force-app/main/default/classes/ContactPhoneNormalizer.cls` | add | New helper class. Public static `normalize(List<Contact>)`. |
| `force-app/main/default/classes/ContactPhoneNormalizer.cls-meta.xml` | add | apiVersion 66.0 (matches engagement). |
| `force-app/main/default/classes/ContactPhoneNormalizer_Test.cls` | add | 6 `@IsTest` methods covering each AC branch. |
| `force-app/main/default/classes/ContactPhoneNormalizer_Test.cls-meta.xml` | add | apiVersion 66.0. |

## Design — `ContactPhoneNormalizer`

```apex
public with sharing class ContactPhoneNormalizer {
    @TestVisible
    private static final Pattern NON_DIGIT = Pattern.compile('\\D');

    public static void normalize(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty()) return;
        for (Contact c : contacts) {
            String formatted = formatPhone(c.Phone);
            if (formatted != null) c.Phone = formatted;
        }
    }

    @TestVisible
    private static String formatPhone(String raw) {
        if (String.isBlank(raw)) return null;
        String digits = NON_DIGIT.matcher(raw).replaceAll('');
        if (digits.length() == 11 && digits.startsWith('1')) {
            digits = digits.substring(1);
        }
        if (digits.length() != 10) return null;
        return '(' + digits.substring(0, 3) + ') '
             + digits.substring(3, 6) + '-'
             + digits.substring(6, 10);
    }
}
```

Returning `null` from `formatPhone` signals "leave unchanged" so the caller skips the assignment (preserving the literal original string, including whitespace differences for international numbers).

## Trigger modification

```apex
trigger ContactTrigger on Contact (before insert, before update) {
    if (trigger.isBefore) {
        if (trigger.isInsert) {
            ContactUtils.handleBeforeInsert();
            ContactPhoneNormalizer.normalize((List<Contact>) trigger.new);
        } else if (trigger.isUpdate) {
            ContactUtils.handleBeforeUpdate();
            ContactPhoneNormalizer.normalize((List<Contact>) trigger.new);
        } else if (trigger.isDelete) {
            ContactUtils.handleBeforeDelete();
        }
    } else if (trigger.isAfter) {
        // existing dead branches retained — trigger header doesn't declare these events
        if (trigger.isInsert) ContactUtils.handleAfterInsert();
        else if (trigger.isUpdate) ContactUtils.handleAfterUpdate();
        else if (trigger.isDelete) ContactUtils.handleAfterDelete();
        else if (trigger.isUndelete) ContactUtils.handleAfterUndelete();
    }
}
```

## Test strategy

`ContactPhoneNormalizer_Test.cls` — 6 methods per AC:

1. `phone_normalize_10digit_formats` — `5551234567` → `(555) 123-4567`
2. `phone_normalize_11digit_leadingOne_dropsAndFormats` — `1-555-123-4567` → `(555) 123-4567`
3. `phone_normalize_alreadyFormatted_isIdempotent` — `(555) 123-4567` → `(555) 123-4567`
4. `phone_normalize_emptyOrNull_unchanged` — null and `''` both unchanged
5. `phone_normalize_international_unchanged` — `+44 20 7946 0958` unchanged
6. `phone_normalize_bulk200_mixedShapes_allCorrectlyNormalized` — 200 Contacts inserted in one DML, mix of raw / leading-1 / pre-formatted / international / empty

Existing classes that grep-reference Contact/ContactUtils that run during validate: `ContactUtilsTest`, `ContactRoleUtilsTest`, `InvoiceUtilsTest`, `TimeSheetUtilsTest`, `ProjectAllocationUtilsTest`, `OpportunityUtilsTest`, `ResourcePlannerControllerTest`, `ProjectUtilsTest` (and any others that DML-insert Contacts). Regression suite in `engagement.yaml` is empty.

## Patterns adherence

- **`apex-trigger-handler.md`** — **partial.** `ContactTrigger` does not currently use the `TriggerHandler` base class (a recent commit GRIM-49 introduced the base; migration is incremental). Per ticket instruction "modify additively" and CLAUDE.md "don't introduce abstractions beyond what the task requires," we are NOT refactoring ContactTrigger to the new pattern. Documenting the variance.
- **`testdatafactory-usage.md`** — `ContactPhoneNormalizer_Test` uses `ContactUtils.generateContact` for Contact construction where suitable.

## Documentation outputs (post-validate)

Per ADR-0010, docs describe *current state*, not change history. No `docs/changelog/` entries.

- `docs/objects/Contact.md` — UPDATE:
  - Add `Phone` to "Standard fields used."
  - Add `ContactPhoneNormalizer.cls` to "Triggers and Apex touching this object."
  - Rewrite "Constraints and gotchas → Trigger header mismatch" to reflect that `before update` is now wired; note that the `isAfter` / `isDelete` / `isUndelete` body branches remain unreachable (no header declaration for those events).
  - Mention that Contact's `Lead_Id_Passable__c → Lead__c` projection now fires on update too (brings Contact in line with Account/Opportunity).
- `docs/features/account-management.md` — possibly minor update: the cross-reference to `ContactTrigger` could note phone normalization. Only if the doc surveys Contact behavior.

## Risk surface

1. **Behavior change: `before update` newly active on Contact.** Activating the header exposes `ContactUtils.handleBeforeUpdate`, which projects `Lead_Id_Passable__c` onto `Lead__c` unconditionally. Today this only runs on insert; from this ticket forward it will also run on every Contact update. *Most updates carry `Lead_Id_Passable__c = null`, which means `Contact.Lead__c` will be set to null on routine updates.* This is the same behavior that already exists for `Account` (via `AccountUtils.handleBeforeUpdate` + `AccountBeforeChange` trigger) — bringing Contact into alignment. The `docs/objects/Contact.md` "Constraints and gotchas" section explicitly invites this fix.

   **Mitigation if the engineer does NOT want this side effect:** could be scoped out by adding before-update via a *separate handler entry point* that bypasses `ContactUtils.handleBeforeUpdate`. Not recommended — violates the one-trigger-per-object pattern from `apex-trigger-handler.md`.

2. **No public API change.** New class, no removals, no signature changes. Safe for LWC/Aura/external integrations.

3. **No governor exposure.** Pure in-memory string ops; one regex per row; no SOQL, no DML.

4. **Recursion safe.** Idempotent output + no DML means no infinite loop, even on update-after-trigger-update scenarios.

## Out-of-scope acceptance criteria

None — every AC is in scope and addressed above.
