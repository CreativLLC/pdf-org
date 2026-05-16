# `sf-integration-change-plan`

You are producing the structured plan for an integration change. The plan is what the in-workflow gate (when triggered) displays to the engineer, and what the execute step implements against. **No code changes happen here** — this step is plan-only.

## Inputs

- `$pull-jira-context.output` — the ticket
- `$classify-sub-type.output` — `sub_type`, `scope`, `external_system`, and the side flags (`endpoint_or_auth_changes`, `scopes_reduced_or_callback_changed`, `pe_field_removed_or_type_changed`, `callout_endpoint_changes`, `webhook_url_pattern_changes`, `touches_credentials`)
- `$smoke-validate-claims.output` — accuracy of ticket claims
- `$verify-org-context.output` — org context
- `$load-engagement-context.output` — patterns/standards/object docs in scope

## Tools

File reads, Glob, Grep against the engagement repo. Specifically `force-app/main/default/classes/`, `force-app/main/default/namedCredentials/`, `force-app/main/default/connectedApps/`, `force-app/main/default/objects/*__e/`, `force-app/main/default/externalServiceRegistrations/`, and the loaded `docs/`. No file writes. No git operations. No SF CLI. No Jira writes. No network — including no fetch of the external system's documentation; that's planning context the engineer brings or that lives in the ticket's `## Context` per [ADR-0015](../decisions/0015-external-context-from-tickets.md).

## Task

1. **Re-read the ticket's acceptance criteria.** The plan must satisfy every AC, or explicitly flag which ones are out of scope.
2. **Map `sub_type` to plan template:**

   | sub_type | Plan must specify |
   |---|---|
   | `create-callout` | New Apex service class path, Named Credential referenced, methods (with timeouts), Result wrapper shape, transient/permanent error policy, mock classes to create, where the callout is invoked from (trigger via Queueable per `queueable-async-pattern.md` if after DML) |
   | `modify-callout` | Class path, methods touched, what changed (endpoint / payload / error-handling), regression risk to existing callers, whether tests' mocks need updating |
   | `create-named-credential` | NC name + label, endpoint (host only — never paste a token), auth scheme (Named User / Per User / OAuth Web Server), how secrets reach the NC (manual Setup step + which env var documents the token's home per `[ADR-0008](../decisions/0008-credential-management.md)`) |
   | `modify-named-credential` | NC name, what's changing (endpoint / auth / label), downstream caller list (grep `force-app/main/default/classes/` for `callout:<NC_Name>/...`), rotation plan if auth changing |
   | `delete-named-credential` | NC name, full caller list (grep), the manifest delta, what happens to in-flight Queueable jobs that reference the NC |
   | `create-connected-app` | Connected App name, OAuth scopes requested, callback URL, intended external-client identity, whether IP restriction is set |
   | `modify-connected-app` | Connected App name, scope diff (added/removed), callback URL diff, external clients affected |
   | `delete-connected-app` | Connected App name, external clients to notify, OAuth token revocation expectation |
   | `create-platform-event` | PE API name (must end `__e`), field definitions (API name, type, required, history tracking), publish channel (Apex `EventBus.publish` or change-data-capture), expected subscriber pattern (Apex trigger / Flow / external CometD client) |
   | `modify-platform-event` | PE name, field diff, subscriber list (grep `force-app/main/default/triggers/` and `flows/` for `<PE>__e`), whether the change is additive or breaks subscribers |
   | `delete-platform-event` | PE name, full subscriber list, what subscribers should do post-deletion |
   | `create-webhook-handler` | `@RestResource` class path, URL mapping, HTTP methods accepted, auth mechanism (Connected App OAuth / signature verification / IP allowlist), payload-parsing approach, response shapes |
   | `modify-webhook-handler` | Class path, what's changing (URL mapping / payload parsing / response shape), external systems with webhooks configured against the old shape |
   | `create-external-service` | ESR name, schema source (OpenAPI / WSDL), Named Credential referenced, generated invocable actions, intended Flow consumers |
   | `modify-external-service` | ESR name, schema diff, regenerated invocable actions, Flow consumers that may need updating |

3. **Identify the file changes.** List every file the change will touch with full path and an annotation:
   - `add` — new file
   - `modify` — existing file changed
   - `delete` — file removed
4. **Identify the test strategy.** Callout tests MUST mock HTTP via `Test.setMock(HttpCalloutMock.class, ...)` per [`patterns/apex-callout-pattern.md`](../patterns/apex-callout-pattern.md). Webhook-handler tests construct `RestRequest` / `RestResponse` and invoke the handler directly. Platform Event tests use `Test.startTest()` / `Test.stopTest()` with `EventBus.publish` to force subscribers to fire synchronously.
5. **Identify the downstream-consumer summary** (this is what the pre-execute gate displays):
   - For NC / Connected App / Platform Event / webhook-handler changes: enumerate every Apex class, Flow, and external-system consumer that depends on the changed artifact. Use grep against the engagement repo. For external systems, read the existing `docs/integrations/<System>.md` if present to surface the documented webhook configurations.
   - Output the full list to `$ARTIFACTS_DIR/downstream-consumers.txt` so the gate can reference it.
6. **Identify patterns and standards that apply.** Specifically [`patterns/apex-callout-pattern.md`](../patterns/apex-callout-pattern.md) (every callout), [`patterns/queueable-async-pattern.md`](../patterns/queueable-async-pattern.md) (callouts after DML), [`patterns/fls-crud-enforcement.md`](../patterns/fls-crud-enforcement.md) (when integration code reads/writes SObjects). For each pattern in scope, state in one sentence how the change will adhere to it.
7. **Identify documentation outputs** per [ADR-0010](../decisions/0010-engagement-documentation-model.md) and [ADR-0022](../decisions/0022-sf-integration-change-scope-and-gates.md) §7: always the integration doc (`docs/integrations/<System>.md`); object docs for any SObject the integration reads/writes; the security doc when sharing is affected; the index when a new external system is introduced. List the exact file paths the document step will produce.
8. **Identify risk surface.** Note any of:
   - Hardcoded URL or credential in the diff (CRITICAL — the credentials hygiene check WILL fire; plan must already use `callout:<NC_Name>/...`)
   - Callout without explicit `setTimeout()` (the pattern compliance check WILL fire)
   - Callout returning raw `HttpResponse` without a Result wrapper
   - Webhook handler with no authentication check (the post-validate gate WILL fire with `CONFIRM`)
   - Platform Event change that removes a field referenced by an existing subscriber
   - Connected App callback URL change that conflicts with documented external-client expectations
9. **Source-file reference formatting.** When the plan markdown references Apex class names, Named Credential names, Platform Event names, Connected App names, or External Service names, write them as inline code (`` `StripeBillingService.cls` ``, `` `Stripe_API` ``, `` `Charge_Failed__e` ``). Do not paste literal credential values; reference credentials only by Named Credential name.

## Output

Write the structured plan to `$ARTIFACTS_DIR/plan.md` as readable markdown. Also emit a JSON summary on stdout for the gate node to display:

```json
{
  "summary": "Add StripeBillingService.createCharge callout using existing Stripe_API named credential; new RetryStripeChargeJob Queueable for transient retries; covered by StripeBillingService_Test with HttpCalloutMock fixtures.",
  "sub_type": "create-callout",
  "scope": "small",
  "external_system": "Stripe",
  "files_changed": [
    {"path": "force-app/main/default/classes/StripeBillingService.cls", "operation": "add"},
    {"path": "force-app/main/default/classes/StripeBillingService.cls-meta.xml", "operation": "add"},
    {"path": "force-app/main/default/classes/RetryStripeChargeJob.cls", "operation": "add"},
    {"path": "force-app/main/default/classes/RetryStripeChargeJob.cls-meta.xml", "operation": "add"},
    {"path": "force-app/main/default/classes/StripeBillingService_Test.cls", "operation": "add"},
    {"path": "force-app/main/default/classes/StripeChargeSuccessMock.cls", "operation": "add"},
    {"path": "force-app/main/default/classes/StripeChargeTransientFailureMock.cls", "operation": "add"}
  ],
  "named_credential_used": "Stripe_API",
  "patterns_followed": ["apex-callout-pattern", "queueable-async-pattern"],
  "downstream_consumers": {
    "apex_classes": [],
    "flows": [],
    "external_systems_notified": []
  },
  "doc_outputs": [
    "docs/integrations/Stripe.md",
    "docs/objects/Renewal__c.md"
  ],
  "risks": [
    "Callout to api.stripe.com — pre-execute gate does NOT fire for create-callout; pattern compliance + credentials hygiene checks run in validate."
  ],
  "out_of_scope_acceptance_criteria": []
}
```

The full plan goes to the artifact file; the JSON is the structured summary that the gate node and the execute node read. **Never include actual credential values in either the JSON or the artifact file** — reference credentials only by Named Credential name.
