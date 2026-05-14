---
title: TestDataFactory Usage
audience: public
last_updated: 2026-05-10
last_updated_by: harness-phase-1
related_tickets: []
related_docs: [apex-trigger-handler.md, fls-crud-enforcement.md, bulkified-soql-update.md]
---

# TestDataFactory Usage

All Apex tests obtain their setup data from a single per-engagement `TestDataFactory` class. Tests do not call `INSERT new <Object>(...)` inline. The factory is the contract that keeps tests stable when objects, fields, or required relationships change.

## When to apply

- **Always**, when writing or modifying any Apex test class.
- When refactoring legacy tests with inline data construction.
- When test setup needs to vary by user permissions, by org context, or by data shape — the factory's overloads handle it.

## When NOT to apply

- For tests that don't need any data at all (e.g., pure utility-method tests with primitive inputs).
- For tests where the data is the test (e.g., a test of the factory itself).

## The pattern

### Step 1: every engagement has exactly one `TestDataFactory`

Located at `force-app/main/default/classes/TestDataFactory.cls`, declared `@IsTest public`, `with sharing`. It exposes:

- `build<Object>()` and `build<Object>(<key fields>)` — return an unsaved record with sensible defaults.
- `create<Object>()` and `create<Object>(<key fields>)` — return an inserted record.
- `create<Object>s(Integer count)` — return `count` inserted records (bulk-test ready).
- `createUserWith<Permission Shape>()` — return a user configured for a specific permission scenario.

```apex
@IsTest
public with sharing class TestDataFactory {

    public static Account buildAccount() {
        return new Account(
            Name = 'Test Account ' + uniqueSuffix()
        );
    }

    public static Account createAccount() {
        Account a = buildAccount();
        insert a;
        return a;
    }

    public static Renewal__c buildRenewal() {
        return new Renewal__c(
            Account__c = createAccount().Id,
            Amount__c = 1000,
            Status__c = 'Draft'
        );
    }

    public static Renewal__c buildRenewal(Id accountId) {
        return new Renewal__c(
            Account__c = accountId,
            Amount__c = 1000,
            Status__c = 'Draft'
        );
    }

    public static Renewal__c createRenewal() {
        Renewal__c r = buildRenewal();
        insert r;
        return r;
    }

    public static List<Renewal__c> createRenewals(Integer count) {
        Account a = createAccount();
        List<Renewal__c> renewals = new List<Renewal__c>();
        for (Integer i = 0; i < count; i++) {
            renewals.add(buildRenewal(a.Id));
        }
        insert renewals;
        return renewals;
    }

    // ── users ────────────────────────────────────────────────────

    public static User createStandardUser() { /* ... */ }
    public static User createUserWithoutFLS(String fieldApiName) { /* ... */ }

    // ── helpers ──────────────────────────────────────────────────

    private static String uniqueSuffix() {
        return String.valueOf(Math.mod(Crypto.getRandomLong(), 1000000));
    }
}
```

### Step 2: tests use the factory exclusively

```apex
@IsTest
private class RenewalTriggerHandlerTest {

    @IsTest
    static void afterUpdate_recalculatesAccountTotal_onStatusChange() {
        // arrange
        Renewal__c r = TestDataFactory.createRenewal();
        r.Amount__c = 2500;

        // act
        Test.startTest();
        r.Status__c = 'Active';
        update r;
        Test.stopTest();

        // assert
        Account a = [SELECT Renewal_Total__c FROM Account WHERE Id = :r.Account__c];
        System.assertEquals(2500, a.Renewal_Total__c);
    }
}
```

No `new Renewal__c(...)`, no `new Account(...)` — every record comes from the factory.

### Step 3: the factory enforces required relationships

When `Renewal__c` requires an `Account__c`, the factory ensures one exists. Tests don't have to know what fields are required — that's the factory's job. When a new required field is added to `Renewal__c`, the factory is updated once and all tests benefit.

### Step 4: bulk tests use the bulk methods

```apex
@IsTest
static void afterUpdate_handles200Renewals_withinLimits() {
    List<Renewal__c> renewals = TestDataFactory.createRenewals(200);
    // ... assertions on bulk behavior ...
}
```

## Anti-patterns

### ❌ Inline DML construction

```apex
@IsTest
static void closeRenewal_setsStatus() {
    Account a = new Account(Name = 'Test');                   // <-- inline
    insert a;
    Renewal__c r = new Renewal__c(Account__c = a.Id, ...);    // <-- inline
    insert r;
    // ...
}
```

**Why it's wrong:** every test repeats the construction. When `Renewal__c` adds a required field, every test breaks. The point of `TestDataFactory` is that *one place* knows how to build a valid record.

### ❌ `@TestSetup` with monolithic record creation

```apex
@TestSetup
static void setup() {
    insert new Account(Name = 'A');
    insert new Renewal__c(Account__c = [SELECT Id FROM Account].Id, ...);
    // 50 lines of inline construction
}
```

**Why it's wrong:** same problem as inline construction, just centralized within one test class. Use `@TestSetup` only for cross-test fixtures that genuinely should be shared, and have it call `TestDataFactory` methods.

```apex
// ✅ Correct
@TestSetup
static void setup() {
    TestDataFactory.createRenewals(5);
}
```

### ❌ Hard-coded field values that break uniqueness constraints

```apex
public static Account createAccount() {
    return new Account(Name = 'Test Account');   // <-- conflicts in tests that create more than one
}
```

**Why it's wrong:** tests that create multiple accounts hit duplicate-name validation rules or unique-key constraints. The factory uses a unique suffix.

## Variations

### Variant: scenario-named methods for complex setups

When a test scenario requires a specific multi-record shape (e.g., "an Account with three active renewals and one cancelled"), expose it as a named method:

```apex
public static Account createAccountWithThreeActiveRenewals() {
    Account a = createAccount();
    for (Integer i = 0; i < 3; i++) {
        Renewal__c r = buildRenewal(a.Id);
        r.Status__c = 'Active';
        insert r;
    }
    return a;
}
```

This keeps the *shape* knowledge in the factory and the test reads naturally:

```apex
Account a = TestDataFactory.createAccountWithThreeActiveRenewals();
```

### Variant: builder-style for complex variation

For records with many optional variations, prefer a builder over many overloads:

```apex
TestDataFactory.RenewalBuilder b =
    new TestDataFactory.RenewalBuilder()
        .withAccount(account)
        .withAmount(5000)
        .withStatus('Active');
Renewal__c r = b.create();
```

Use this pattern only when the number of variations exceeds 3–4; otherwise keep the simpler overload form.

### Variant: per-engagement extensions

The factory is per-engagement, not from the harness. Each engagement maintains its own factory tailored to its custom objects. The harness *recommends* the contract (method names, behaviors) but doesn't ship the implementation.

## Tests for the factory itself

Yes — the factory has its own tests:

```apex
@IsTest
private class TestDataFactoryTest {
    @IsTest static void createAccount_insertsRecord_withRequiredFields() {
        Account a = TestDataFactory.createAccount();
        System.assertNotEquals(null, a.Id);
        System.assertNotEquals(null, a.Name);
    }
    // ...
}
```

This catches regressions when the factory is updated to handle a new required field.

## Constraints and gotchas

- **`@IsTest` annotation on the factory class** is required so it doesn't count toward the org's Apex code limit.
- **Avoid `SeeAllData=true`.** The factory exists to make tests not depend on org data. Tests that set `SeeAllData=true` defeat the purpose.
- **Test users created by the factory must have unique usernames** — use the `uniqueSuffix()` helper to avoid `DUPLICATE_USERNAME` errors when multiple tests create users.
- **Factory methods that perform DML count against governor limits.** For bulk tests, use the bulk methods so the factory issues a single DML for all 200 records, not 200 individual ones.
- **Don't import the factory across packages.** If multiple unlocked packages need similar factory methods, each owns its own — packages don't share test code.

## References

- **Salesforce Apex Developer Guide:** [Test Data](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_testing_data.htm).
- **Salesforce Developer Guide:** [Test.startTest / Test.stopTest](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_annotation_IsTest.htm).
- **Related patterns:** [`apex-trigger-handler.md`](./apex-trigger-handler.md), [`fls-crud-enforcement.md`](./fls-crud-enforcement.md), [`bulkified-soql-update.md`](./bulkified-soql-update.md).

## History

- **2026-05-10:** initial Phase 1 authoring.
