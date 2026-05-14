# `sf-discover-document-integrations`

You are inventorying and documenting every external integration this engagement uses. For each integration in `$classify-significance.output.integrations`, write or update `docs/integrations/<SystemName>.md` per the canonical-reference template, reflecting the *current state* of how the org connects to the external system.

Runs in parallel with `document-objects` and `document-flows`. Uses **opus[1m]** because integration discovery may need to read multiple Apex classes, Connected App configs, Named Credential definitions, and Platform Event schemas in one pass.

## Inputs

- `$classify-significance.output.integrations` — array of integration descriptors: system_name, kind (callout / webhook / connected-app / named-credential / platform-event), endpoint (if applicable), apex_classes.
- The engagement's `force-app/main/default/` directory (read-only).
- The template: `docs/.harness-templates/integration-doc.md`.

## Tools

Read, Edit, Write, Glob, Grep. Read-only on `force-app/`; writes to `docs/integrations/`.

## Idempotency rule (per ADR-0011)

Per other discover-* nodes — check existing `docs/integrations/<System>.md` frontmatter `last_updated_by`. If non-`archon-*`, skip; log as preserved.

## What to inventory beyond the classifier's input

The classifier passed forward a list of probable integrations. Verify and extend:

- **Connected Apps:** read every `force-app/main/default/connectedApps/*.connectedApp-meta.xml`. For each: name, OAuth scopes, consumer key (no secrets — those aren't in source), callback URL, whether it's used for inbound or outbound OAuth.
- **Named Credentials:** `force-app/main/default/namedCredentials/*.namedCredential-meta.xml`. Each names an outbound endpoint + auth scheme. Match to Apex callouts by URL.
- **External Services:** `force-app/main/default/externalServiceRegistrations/`. Schema-driven integrations.
- **Platform Events (custom):** `force-app/main/default/objects/*__e/`. Read field schemas; identify publishers (Apex with `EventBus.publish`) and subscribers (Flows with `RecordTriggered` on the platform event, or Apex trigger files on the platform event).
- **Apex callouts:** every class in `force-app/main/default/classes/` that contains `HttpRequest` or `Http().send`. Group by endpoint domain.
- **Apex inbound (REST):** every class annotated `@RestResource`. Group as inbound integrations.
- **Webhook handlers:** Apex REST resources whose URL path suggests webhook intent (e.g., `/stripe/webhook/*`).

For each external system, identify both outbound (Salesforce calls them) AND inbound (they call Salesforce) directions where applicable.

## Task — per significant integration

For each external system in the inventory:

1. **Group all Salesforce-side artifacts** that touch this system: Connected App, Named Credential, Apex callout classes, REST endpoints, Platform Event definitions, related Flows.

2. **Write `docs/integrations/<SystemName>.md`** following the template:

   - **Frontmatter:** title, audience: public, last_updated, last_updated_by (`archon-discover-<run-id>`), related_tickets: [], related_docs: link to object docs for objects this integration reads/writes.

   - **Overview** — 2–4 sentences: what external system this connects to, what business purpose (billing, e-signature, identity, etc.), direction(s) (outbound / inbound / bidirectional).

   - **Auth** — Named Credential name + auth scheme (OAuth 2.0, JWT, Basic, API Key), or Connected App configuration. Reference the credential storage convention (env vars per ADR-0008; never literal values in this doc).

   - **API surface** — table of operations the org performs against this system:
     | Direction | Endpoint / event | Apex class | Triggered by | Notes |

   - **Apex layer** — the classes that implement the integration. Brief description of each, including what business logic it adds on top of the raw API call.

   - **Salesforce objects affected** — table:
     | Object | Direction | Notes |
     For each row, link to the object's doc.

   - **Failure modes** — known classes of failure (rate limits, schema mismatches, auth expiry) and how the integration handles them (retries, dead-letter, surfacing-to-user).

   - **Governing decisions** — `docs/decisions/*.md` ADRs that govern this integration. Skip if none.

3. **Cross-link aggressively.** Object docs (relative paths). Other integration docs if relevant (cross-vendor flows). Note the cross-links even if target docs don't exist yet.

## State, not history

Describe what the integration does NOW. Don't write "we used to use webhooks v1, now we use v2." Just describe v2 as the integration.

## Output

```json
{
  "integrations_written": [
    "docs/integrations/Stripe.md"
  ],
  "integrations_preserved": [],
  "integrations_failed": [],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links_count": 0
  }
}
```
