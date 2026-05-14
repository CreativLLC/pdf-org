---
title: FLS and CRUD Enforcement in Apex
audience: public
last_updated: 2026-05-10
last_updated_by: harness-phase-1
related_tickets: []
related_docs: [apex-trigger-handler.md, bulkified-soql-update.md]
---

# FLS and CRUD Enforcement in Apex

User-driven Apex operations must respect the running user's field-level security and CRUD permissions. The platform does not enforce FLS automatically inside Apex; the code is responsible for checking. This pattern defines how.

## When to apply

- **Always**, when reading, creating, updating, or deleting records on behalf of a user (e.g., `@AuraEnabled` methods, REST resources, controller methods, Visualforce/Aura/LWC backends).
- When constructing records from user-supplied input (e.g., serialized payloads from LWC).
- When returning records to a UI — strip fields the user can't read before sending.

## When NOT to apply

- For **system context** operations explicitly scoped to run as system (e.g., scheduled batch jobs, integration callbacks, platform-event subscribers performing internal data movement). Document the choice in the class header and use `without sharing` deliberately, with an ADR explaining why.
- For trigger logic that operates on records the user has already been authorized to insert/update via the platform DML — the trigger doesn't add user permissions, it executes inside an already-authorized context. *(Triggers still enforce sharing if declared `with sharing`.)*

## The pattern

### Sharing first

Every Apex class declares its sharing posture explicitly. There is no implicit default.

```apex
public with sharing class RenewalController { ... }       // user-context
public without sharing class RenewalIntegrationJob { ... } // system-context (justified)
public inherited sharing class RenewalUtility { ... }      // inherits caller's sharing
```

Default to `with sharing`. `without sharing` requires a comment explaining the justification and an ADR if it's a non-trivial scope.

### Reading: `WITH SECURITY_ENFORCED` and `WITH USER_MODE`

For Apex API 60.0+ prefer `WITH USER_MODE`, which enforces both FLS and CRUD at the database layer. For older orgs, `WITH SECURITY_ENFORCED` enforces FLS for SELECT.

```apex
// API 60.0+ — preferred
List<Renewal__c> renewals = [
    SELECT Id, Name, Amount__c, Status__c, Account__c
    FROM Renewal__c
    WHERE Status__c = :status
    WITH USER_MODE
];
```

```apex
// Older orgs
List<Renewal__c> renewals = [
    SELECT Id, Name, Amount__c, Status__c, Account__c
    FROM Renewal__c
    WHERE Status__c = :status
    WITH SECURITY_ENFORCED
];
```

If the user lacks read access to any field in the SELECT list, the query throws `QueryException` (a clear, fail-loud error). Catch it at the controller boundary if the user-facing experience needs a specific message; otherwise let it propagate.

### Writing: `Database.insert/update/delete` with `AccessLevel.USER_MODE`

For Apex API 60.0+ use the `Database` methods with `AccessLevel.USER_MODE` to enforce FLS and CRUD on writes:

```apex
List<Database.SaveResult> results = Database.insert(
    renewals,
    AccessLevel.USER_MODE
);
```

For older orgs, use `Schema.sObjectType.<Object>.fields.<Field>.isCreateable() / isUpdateable() / isAccessible()` checks before stripping or refusing the write.

### Stripping inaccessible fields before write

When data comes from a serialized LWC payload and you want to silently drop fields the user can't write rather than fail the whole operation, use `Security.stripInaccessible`:

```apex
SObjectAccessDecision decision = Security.stripInaccessible(
    AccessType.UPDATABLE,
    renewals
);
update decision.getRecords();
// Optionally inspect decision.getRemovedFields() for telemetry.
```

This is the right choice when the operation should proceed with whatever the user *can* update, and the inaccessible fields aren't critical to the operation's correctness.

### Returning records to a UI

When returning records to LWC/Aura/REST consumers, strip fields the user can't read so the response doesn't leak metadata:

```apex
@AuraEnabled(cacheable=true)
public static List<Renewal__c> getActiveRenewals() {
    List<Renewal__c> renewals = [
        SELECT Id, Name, Amount__c, Status__c, Account__c
        FROM Renewal__c
        WHERE Status__c = 'Active'
        WITH USER_MODE
    ];
    return renewals;
}
```

`WITH USER_MODE` already restricts the SELECT to fields the user can read, so the returned objects are safe.

## Anti-patterns

### ❌ `without sharing` by default

```apex
public without sharing class RenewalController {
    @AuraEnabled
    public static void closeRenewal(Id renewalId) {
        Renewal__c r = [SELECT Id, Status__c FROM Renewal__c WHERE Id = :renewalId];   // <-- bypasses sharing
        r.Status__c = 'Closed';
        update r;                                                                       // <-- bypasses CRUD/FLS
    }
}
```

**Why it's wrong:** the user could close a renewal they're not allowed to see, edit, or own. `without sharing` here breaks tenancy and security boundaries. Default `with sharing` and add `WITH USER_MODE` for FLS.

### ❌ Bypassing FLS by querying everything

```apex
public with sharing class RenewalController {
    @AuraEnabled
    public static List<Renewal__c> all() {
        return [SELECT FIELDS(ALL) FROM Renewal__c LIMIT 200];   // <-- no security clause
    }
}
```

**Why it's wrong:** `FIELDS(ALL)` and an absence of `WITH USER_MODE` returns whatever the SOQL engine retrieves — including fields the user shouldn't see. Use `WITH USER_MODE` (or `WITH SECURITY_ENFORCED`) and an explicit field list.

### ❌ Trusting user input for DML targets

```apex
@AuraEnabled
public static void updateRenewal(Renewal__c payload) {
    update payload;   // <-- payload may contain fields the user can't write
}
```

**Why it's wrong:** the payload could contain `OwnerId` or any other field the user is not permitted to set. Use `Database.update(payload, AccessLevel.USER_MODE)` or `Security.stripInaccessible` before the DML.

## Variations

### Variant: SOQL injection-safe dynamic queries

When dynamic SOQL is unavoidable, use `String.escapeSingleQuotes()` for any user-supplied string interpolated into a query, and prefer bind variables for everything else:

```apex
String safeStatus = String.escapeSingleQuotes(rawStatus);
String soql =
    'SELECT Id, Name FROM Renewal__c WHERE Status__c = \'' + safeStatus + '\' WITH USER_MODE';
List<Renewal__c> renewals = Database.query(soql);
```

Better: avoid dynamic SOQL entirely. Most cases that "need" dynamic SOQL can be expressed with bind variables.

### Variant: Custom permissions for capability gates

For features gated on a permission beyond CRUD/FLS (e.g., "can override pricing"), define a Custom Permission and check it explicitly:

```apex
if (!FeatureManagement.checkPermission('Override_Renewal_Amount')) {
    throw new AuraHandledException('You do not have permission to override the renewal amount.');
}
```

Custom Permissions are assigned via Permission Sets — separating "what's the data?" (FLS/CRUD) from "what can this user do?" (capability).

## Tests

FLS tests run as a low-privilege user and verify the operation behaves correctly:

```apex
@IsTest
static void closeRenewal_throws_whenUserLacksFLS() {
    User restricted = TestDataFactory.createUserWithoutFLS('Status__c');
    Renewal__c r = TestDataFactory.createRenewal();

    System.runAs(restricted) {
        Test.startTest();
        try {
            RenewalController.closeRenewal(r.Id);
            System.assert(false, 'expected QueryException due to FLS');
        } catch (QueryException e) {
            System.assert(e.getMessage().contains('FLS'));
        }
        Test.stopTest();
    }
}
```

`TestDataFactory.createUserWithoutFLS` is the engagement's helper for spinning up a user with a configured permission shape — see [`testdatafactory-usage.md`](./testdatafactory-usage.md).

## Constraints and gotchas

- **`with sharing` is about record visibility (rows), not field visibility (columns).** It does not enforce FLS or CRUD. Use `WITH USER_MODE` / `Database.X(records, AccessLevel.USER_MODE)` for those.
- **`@AuraEnabled` methods do not run with sharing by default** — the class declaration controls it. Always declare `with sharing` (or justify otherwise).
- **System-context Apex (batch, schedulable, queueable, future)** runs without user permissions. Document explicitly when this is intentional.
- **`Schema.sObjectType.X.fields.Y.isAccessible()` checks only FLS for that field** — they don't check sharing or row visibility. Combine multiple checks deliberately.
- **PMD / Apex Code Analyzer rules** can catch many violations of this pattern. Wire them into the validation step where possible.

## References

- **Salesforce Developer Guide:** [Enforce User Mode for Database Operations](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_perms_enforcing.htm).
- **Salesforce Developer Guide:** [Filter SOQL Queries Using WITH SECURITY_ENFORCED](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_with_security_enforced.htm).
- **Salesforce Developer Guide:** [Strip Inaccessible Fields](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_perms_enforcing_stripinaccessible.htm).
- **Trailhead:** [Apex Security and Sharing](https://trailhead.salesforce.com/content/learn/modules/apex_basics_dotnet).
- **Related patterns:** [`apex-trigger-handler.md`](./apex-trigger-handler.md), [`testdatafactory-usage.md`](./testdatafactory-usage.md).

## History

- **2026-05-10:** initial Phase 1 authoring.
