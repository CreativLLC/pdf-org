---
title: Apex Callout Pattern
audience: public
last_updated: 2026-05-14
last_updated_by: harness-phase-7
related_tickets: []
related_docs: [fls-crud-enforcement.md, queueable-async-pattern.md]
---

# Apex Callout Pattern

HTTP callouts from Apex go through Named Credentials, run in a service class (never directly from triggers), set explicit timeouts, distinguish transient vs permanent failures, and return a structured result that callers can inspect.

## When to apply

- Calling any external HTTP service from Apex — REST, SOAP-over-HTTP, webhooks-out, third-party APIs (Stripe, DocuSign, Snowflake, internal microservices).
- Whenever you'd otherwise hardcode a URL, a header, or an auth secret in code.
- After a DML in a trigger — wrap the callout in a Queueable per [queueable-async-pattern.md](./queueable-async-pattern.md) since callouts can't run synchronously from a trigger context.

## When NOT to apply

- Inbound webhooks from external systems — those are Apex REST endpoints (`@RestResource`), a different pattern.
- Salesforce-to-Salesforce data movement — use Outbound Messages, Platform Events, or Replication API rather than HTTP callouts.
- High-volume bulk integration — use Bulk API (server-pulled) or Platform Events, not synchronous callouts which hit governor limits.

## The pattern

### Step 1: Named Credential

Configure auth + base URL declaratively in Setup → Named Credentials. **Never** hardcode the URL or any credential in code.

```xml
<!-- force-app/main/default/namedCredentials/Stripe_API.namedCredential-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Stripe API</label>
    <endpoint>https://api.stripe.com/v1</endpoint>
    <principalType>NamedUser</principalType>
    <protocol>Password</protocol>
    <authProvider>...</authProvider>
</NamedCredential>
```

The Apex callout references the named credential by name (`callout:Stripe_API/<path>`). Auth tokens and the base URL change in Setup without code changes.

### Step 2: The service class

```apex
public with sharing class StripeService {

    /**
     * Result wrapper — callers inspect this; never trust an exception
     * thrown from this class as the only signal.
     */
    public class Result {
        public Boolean success;
        public Integer statusCode;
        public String body;
        public String errorMessage;     // populated when success == false
        public Boolean isTransient;     // true for 5xx + network errors; safe to retry
    }

    private static final Integer DEFAULT_TIMEOUT_MS = 30000;

    public static Result createCharge(Decimal amountUsdCents, String customerId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Stripe_API/charges');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setTimeout(DEFAULT_TIMEOUT_MS);
        req.setBody('amount=' + amountUsdCents + '&customer=' + customerId);

        return executeWithStandardHandling(req);
    }

    private static Result executeWithStandardHandling(HttpRequest req) {
        Result r = new Result();
        try {
            HttpResponse res = new Http().send(req);
            r.statusCode = res.getStatusCode();
            r.body = res.getBody();
            r.success = res.getStatusCode() >= 200 && res.getStatusCode() < 300;
            r.isTransient = res.getStatusCode() >= 500;
            if (!r.success) {
                r.errorMessage = 'HTTP ' + r.statusCode + ': ' + res.getStatus();
            }
        } catch (CalloutException e) {
            r.success = false;
            r.isTransient = true;          // timeouts + DNS failures count as transient
            r.statusCode = 0;
            r.errorMessage = 'Callout failed: ' + e.getMessage();
        }
        return r;
    }
}
```

### Step 3: Caller handles the Result

```apex
StripeService.Result r = StripeService.createCharge(2500, 'cus_abc');
if (r.success) {
    // happy path: parse r.body, update SF state
} else if (r.isTransient) {
    // requeue via Queueable + chain — don't drop the work
    System.enqueueJob(new RetryStripeChargeJob(amount, customerId, attempt + 1));
} else {
    // permanent: log + alert; don't retry
    LogService.error('Stripe charge failed permanently: ' + r.errorMessage);
}
```

## Anti-patterns

❌ **Hardcoded URLs.** `req.setEndpoint('https://api.stripe.com/v1/charges')` — auth + URL changes require code deploys.

❌ **No timeout.** Default Apex callout timeout is 10s; explicit `setTimeout()` makes the SLA visible at the call site.

❌ **Treat all errors the same.** A 503 is transient (retry-worthy); a 422 is permanent (don't retry). Conflating them either retries forever on 4xx or drops work on 5xx.

❌ **Catching `Exception` instead of `CalloutException`.** Other exception types indicate bugs that should surface, not be silently retried.

❌ **Callout directly from a trigger.** Apex callouts from a trigger context fail with `CalloutException: Callout from triggers are currently not supported`. Use a Queueable.

❌ **Embedding the auth token in the request.** Tokens live in the Named Credential; the runtime injects them via `callout:` URL syntax.

## Testing

Use `Test.setMock(HttpCalloutMock.class, new MockProvider());` with one mock class per scenario (success, 4xx, 5xx, timeout). Don't share mocks across tests — each test sets its own mock to match what it's asserting.

```apex
@IsTest
private class StripeServiceTest {
    @IsTest
    static void createCharge_success_returnsSuccessResult() {
        Test.setMock(HttpCalloutMock.class, new StripeChargeSuccessMock());
        StripeService.Result r = StripeService.createCharge(2500, 'cus_abc');
        System.assert(r.success);
        System.assertEquals(200, r.statusCode);
    }

    @IsTest
    static void createCharge_serverError_marksTransient() {
        Test.setMock(HttpCalloutMock.class, new HttpStatusMock(503));
        StripeService.Result r = StripeService.createCharge(2500, 'cus_abc');
        System.assert(!r.success);
        System.assert(r.isTransient);
    }
}
```

## References

- [Salesforce: Named Credentials](https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm)
- [Salesforce: Apex Callouts](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_callouts.htm)
- [`queueable-async-pattern.md`](./queueable-async-pattern.md) — for callouts that need to run after a DML in a trigger context
- [`fls-crud-enforcement.md`](./fls-crud-enforcement.md) — when the callout result is then written back to a SObject
