# `sf-integration-change-validate`

You are orchestrating the validation gates for the integration change executed in the previous step. This command calls the two supporting scripts AND runs four integration-specific inline checks, then aggregates the results. The scripts are the source of truth for deploy and tests; the inline checks are the source of truth for pattern compliance, webhook auth, Platform Event subscriber consistency, and credentials hygiene.

## Inputs

- `$execute.output` — list of files actually changed (`files_changed_actual`, `named_credentials_referenced`)
- `$classify-sub-type.output` — `sub_type`, `external_system`, side flags (`endpoint_or_auth_changes`, `pe_field_removed_or_type_changed`, `touches_credentials`, etc.)
- `$load-engagement-context.output` — `coverage_threshold`, `regression_suite`, `engagement.yaml: integration.auth_helper_names` (optional allowlist)
- `$verify-org-context.output` — `target_org_alias`, `is_scratch_org`, `scratch_org_def_path`

## Tools

Bash, Read, Grep. The two supporting scripts live at `.archon/scripts/`:

- `deploy-to-scratch.sh` — creates a scratch org (or reuses existing) and deploys the changed files. Returns 0 on success. Same script the `sf-apex-change` and `sf-metadata-change` workflows use; the integration-change family deploys Apex classes + `*.namedCredential-meta.xml` + `*.connectedApp-meta.xml` + Platform Event `__e` objects + `*.externalServiceRegistration-meta.xml` in one call.
- `run-apex-tests.sh` — runs the test set (modified test classes + grep-referencing tests + engagement `regression_suite`) against the scratch org. HTTP-mocked tests use `Test.setMock(HttpCalloutMock.class, ...)` per [`patterns/apex-callout-pattern.md`](../patterns/apex-callout-pattern.md). Returns 0 only if every test passes AND every modified non-test class meets `coverage_threshold`.

The four integration-specific checks run inline (no script needed; lightweight regex/grep passes).

## Task

Run the steps in order. Capture each result and the structured output written to `$ARTIFACTS_DIR/<check-name>.json`. After all run, aggregate.

### 1. Deploy to scratch

Always run `deploy-to-scratch.sh` with the file list from `$execute.output.files_changed_actual`. If deploy fails, the workflow can't continue — emit `overall_result: fail` with `deploy_result: fail` and stop here.

### 2. Apex tests

Run `run-apex-tests.sh` with the org alias, the test class list (callout service classes' tests + webhook-handler tests + Queueable tests + engagement `regression_suite`), and `coverage_threshold`. Callout tests rely on `Test.setMock` providing `HttpCalloutMock` implementations — the test classes the execute step wrote include these mocks.

Capture pass/fail and per-class coverage. The script enforces the coverage gate internally and returns non-zero if any modified non-test class is below threshold.

### 3. Pattern compliance check (inline)

For each Apex callout class in `$execute.output.files_changed_actual` (file paths under `force-app/main/default/classes/` that contain `HttpRequest` or `Http().send`), grep the source for compliance with [`patterns/apex-callout-pattern.md`](../patterns/apex-callout-pattern.md):

1. **Named Credential reference (no hardcoded URLs).** Every `setEndpoint(...)` call must reference `callout:<NC_Name>/<path>`. Match: `setEndpoint\(\s*['"]callout:`. Fail signal: a `setEndpoint` call that does not reference `callout:` syntax (e.g., `setEndpoint('https://api.stripe.com/...')`).
2. **Explicit timeout.** Every callout class must call `setTimeout(<integer>)` on its `HttpRequest`. Match: `setTimeout\(\s*\d+`. Fail signal: a callout class with NO `setTimeout` call.
3. **Structured Result wrapper.** Every public callout method must return a class type (not raw `HttpResponse`). Match: method signatures that declare a return type ending in `Result` OR a class member named `Result` inside the callout class. Fail signal: a public callout method returning `HttpResponse`.
4. **Transient-vs-permanent error distinction.** The class must reference both `isTransient` (or `transient` boolean) AND inspect `getStatusCode()` against 5xx vs 4xx ranges. Match: presence of `isTransient` field assignment from `getStatusCode() >= 500`. Fail signal: error handling that catches `CalloutException` or inspects status code but does not set a transient flag.

Write results to `$ARTIFACTS_DIR/pattern-compliance.json`:

```json
{
  "result": "pass" | "fail",
  "callout_classes_checked": ["StripeBillingService.cls", "RetryStripeChargeJob.cls"],
  "failures": [
    {
      "class": "StripeBillingService.cls",
      "issue": "no-timeout",
      "file_line": "force-app/main/default/classes/StripeBillingService.cls:42",
      "snippet": "HttpRequest req = new HttpRequest(); req.setEndpoint(...);"
    }
  ]
}
```

### 4. Webhook handler authentication check (inline)

For each `@RestResource` class in `$execute.output.files_changed_actual` (grep `force-app/main/default/classes/*.cls` for `@RestResource`), check that the class body contains at least one of:

- **Connected App OAuth** — references `UserInfo.getSessionId()` or `Auth.SessionManagement` or checks `RestContext.request.headers.get('Authorization')` against a session token validator.
- **IP allowlist** — reads `RestContext.request.headers.get('X-Forwarded-For')` and checks the value against a `<Custom_Metadata>__mdt` entry.
- **Signature verification** — computes `Crypto.generateMac('HmacSHA256', ...)` against the request body and compares to a header value (e.g., `Stripe-Signature`).
- **Signed JWT** — calls `Auth.JWS.validate(...)` or `Auth.JWT.deserialize(...)`.
- **Engagement-allowlisted helper** — references any class name in `engagement.yaml: integration.auth_helper_names:` (this allowlist supports engagements that abstract auth into custom helpers the regex check can't detect by signature).

Fail signal: a `@RestResource` class with NO match against any of the five patterns above.

Write results to `$ARTIFACTS_DIR/webhook-auth.json`. Skip this check (result: `skipped`) if no `@RestResource` classes were modified.

### 5. Platform Event subscriber consistency check (inline)

Only runs when `sub_type ∈ {modify-platform-event, delete-platform-event}` AND `pe_field_removed_or_type_changed == 'true'` (or always for `delete-platform-event`).

For each modified Platform Event:

1. Parse the PE name from the file path (`force-app/main/default/objects/<PE>__e/`).
2. Grep `force-app/main/default/triggers/` for trigger files declared on the PE: pattern `on\s+<PE>__e`.
3. Grep `force-app/main/default/flows/` for Flows with `processType: AutoLaunchedFlow` or `RecordTriggered` whose start element references the PE.
4. For each subscriber found, parse the subscriber body for field references on the PE. Cross-reference against the new PE field schema (read from `force-app/main/default/objects/<PE>__e/fields/`).
5. Fail signal: a subscriber that references a field removed by this run, OR a subscriber that references a field whose type changed.

Write results to `$ARTIFACTS_DIR/pe-subscribers.json`:

```json
{
  "result": "pass" | "fail" | "skipped",
  "platform_event": "Charge_Failed__e",
  "subscribers_found": [
    "force-app/main/default/triggers/ChargeFailedTrigger.trigger",
    "force-app/main/default/flows/Notify_Ops_On_Charge_Failure.flow-meta.xml"
  ],
  "broken_references": [
    {
      "subscriber": "force-app/main/default/triggers/ChargeFailedTrigger.trigger",
      "line": 18,
      "field": "Failure_Reason__c",
      "issue": "field removed by this run"
    }
  ]
}
```

### 6. Credentials hygiene check (inline) — per [ADR-0008](../decisions/0008-credential-management.md)

**Always runs** within this family, regardless of `sub_type`. Scans every file in `$execute.output.files_changed_actual` for literal credentials.

Patterns checked (each is a regex; match emits a fail signal):

- `sk_live_[A-Za-z0-9]{20,}` — Stripe live secret key
- `sk_test_[A-Za-z0-9]{20,}` — Stripe test secret key (still flag — many test keys are deliberately public, but the workflow surfaces them so the engineer acknowledges via `CONFIRM`)
- `xoxb-[A-Za-z0-9-]{20,}` — Slack bot token
- `xoxp-[A-Za-z0-9-]{20,}` — Slack user token
- `ghp_[A-Za-z0-9]{36}` — GitHub personal access token (classic)
- `gho_[A-Za-z0-9]{36}` — GitHub OAuth token
- `AKIA[A-Z0-9]{16}` — AWS access key ID
- `ya29\.[A-Za-z0-9_-]{50,}` — Google OAuth access token
- `eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}` — JWT (base64-encoded header.payload.signature)
- Hex string ≥ 40 chars inside a string literal that is NOT prefixed by `callout:` — likely raw API token
- `Authorization\s*:\s*['"]?(Bearer|Basic)\s+[A-Za-z0-9+/=._-]{20,}` — literal Authorization header value (vs `callout:` syntax)
- Apex string literals containing the exact env-var names from [ADR-0008](../decisions/0008-credential-management.md): `JIRA_API_TOKEN`, `STRIPE_SECRET_KEY`, etc. (engineers sometimes copy a variable name's *value* and forget to replace with the reference)

For each match:

- Record file path, line number, and matched pattern name. **Do NOT echo the matched value** into the output. Per [ADR-0008](../decisions/0008-credential-management.md), the audit trail must not widen the leak — the artifact records `pattern_matched: "stripe_live_secret_key_prefix"` and `file: "force-app/main/default/classes/Foo.cls:42"`, not the secret itself.

Fail signal: any match in any changed file.

Write results to `$ARTIFACTS_DIR/credentials-hygiene.json`:

```json
{
  "result": "pass" | "fail",
  "files_scanned": ["force-app/main/default/classes/StripeBillingService.cls"],
  "matches": [
    {
      "file": "force-app/main/default/classes/StripeBillingService.cls",
      "line": 42,
      "pattern_matched": "stripe_live_secret_key_prefix",
      "context_hint": "Apex string literal in setHeader call"
    }
  ]
}
```

### 7. Aggregate

`overall_result` is `pass` only if:

- `deploy_result == "pass"`
- `tests_result == "pass"` (including coverage)
- `pattern_compliance_result ∈ {pass, skipped}`
- `webhook_auth_result ∈ {pass, skipped}` OR the post-validate gate approves with `CONFIRM`
- `pe_subscriber_result ∈ {pass, skipped}`
- `credentials_hygiene_result == "pass"` OR the post-validate gate approves with `CONFIRM`

A credentials hygiene match that was approved at the post-validate gate is still legitimately flagged; `credentials_hygiene_result` stays `fail` but `overall_result` can be `pass` because the human acknowledged it explicitly. Same logic for webhook auth.

## Output

```json
{
  "deploy_result": "pass",
  "deploy_artifact": "$ARTIFACTS_DIR/deploy-to-scratch.json",
  "tests_result": "pass",
  "tests_artifact": "$ARTIFACTS_DIR/run-apex-tests.json",
  "coverage_threshold": 75,
  "per_class_coverage": [
    {"class": "StripeBillingService", "coverage": 92},
    {"class": "RetryStripeChargeJob", "coverage": 88}
  ],
  "pattern_compliance_result": "pass",
  "pattern_compliance_artifact": "$ARTIFACTS_DIR/pattern-compliance.json",
  "webhook_auth_result": "skipped",
  "webhook_auth_artifact": "$ARTIFACTS_DIR/webhook-auth.json",
  "pe_subscriber_result": "skipped",
  "pe_subscriber_artifact": "$ARTIFACTS_DIR/pe-subscribers.json",
  "credentials_hygiene_result": "pass",
  "credentials_hygiene_artifact": "$ARTIFACTS_DIR/credentials-hygiene.json",
  "overall_result": "pass",
  "duration_seconds": 318
}
```

On any non-pass result, the JSON also includes a `failure_reasons` array of strings (one per failing check) so the post-validate gate can display them. The `failure_reasons` strings reference file paths and pattern names but **never echo matched credential values**.
