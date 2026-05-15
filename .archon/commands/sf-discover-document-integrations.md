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

2. **Write `docs/integrations/<SystemName>.md`** following the canonical template at `docs/.harness-templates/integration-doc.md`. The section names and order below match the canon exactly. **All sections are REQUIRED. Do not invent alternate names. Do not omit. Do not reorder.**

   - **Frontmatter** (required keys): `title`, `audience: public`, `last_updated` (today), `last_updated_by` (`archon-discover-<run-id>` if `$ARCHON_RUN_ID` set; else `archon-discover`), `related_tickets: []`, `related_docs:` (relative paths to object docs for objects this integration reads/writes; `architecture/integration-topology.md` if it exists).

   - **`## Purpose`** — REQUIRED. One paragraph: what this integration accomplishes for the business AND at what cost (latency, complexity, dependency). Be honest about both. (Not "Overview" — `## Purpose` matches canon.)

   - **`## Direction(s) and pattern`** — REQUIRED. Table per canon: `Direction` (Outbound SF → System / Inbound System → SF), `Pattern` (REST callout / Platform Event / Outbound Message / Bulk API), `Trigger` (when each direction fires). If one-directional, write the unused row as `| — | — | — |` and add a one-line note. (Was "API surface" — `## Direction(s) and pattern` matches canon.)

   - **`## Authentication`** — REQUIRED. Auth method, credential storage (Named Credential / Custom Metadata / External Credential — name the artifact, never the value), rotation cadence if known, scope/permissions. **Reference the credential storage convention (env vars per ADR-0008; never literal values in this doc.)** (Was "Auth" — `## Authentication` matches canon.)

   - **`## Endpoints / channels`** — REQUIRED. Table per canon: `Endpoint`, `Method`, `Purpose`, `Frequency`. If purely inbound and no outbound endpoints, write one row describing the inbound endpoint and note "no outbound calls."

   - **`## Payloads`** — REQUIRED. For each notable endpoint: request shape (JSON), SF-source mapping table (`Payload key | SF source | Transformation`), successful response shape, error response shapes. If you can't read payload contracts from metadata alone, write `_Payload contract not in source metadata; populate from API documentation or by reading the Apex callout class body._` — do NOT omit the section.

   - **`## Error handling and retries`** — REQUIRED. Transient errors, permanent errors, auth errors, idempotency. (Was "Failure modes" — `## Error handling and retries` matches canon.)

   - **`## Bulk and rate limits`** — REQUIRED. System rate limit (if known from docs), SF callout limits, bulk-operation strategy. If unknown, write `_Rate limits not documented in source; consult <System> API docs._`

   - **`## Monitoring`** — REQUIRED. Logs, dashboards, alerts. If not yet wired, write `_No monitoring configured; first failure will surface as a customer-facing error._`

   - **`## SF-side surface area`** — REQUIRED. Bullets: Apex classes (with one-line role each), Named Credentials, Custom Metadata Types, Custom Settings, Platform Events, Apex REST endpoints. (Was "Apex layer" — broader scope, `## SF-side surface area` matches canon.)

   - **`## <System>-side surface area`** — REQUIRED. What lives on the external side: webhooks, API client app, mappings or configurations maintained externally. If unknown from metadata, write `_External-side artifacts not visible from SF source; populate from <System> admin console review._`

   - **`## Failure modes and runbook`** — REQUIRED. Table per canon: `Symptom`, `Likely cause`, `First check`, `Runbook`. If no runbooks exist yet, write one row describing each known failure mode with an empty `Runbook` cell — do NOT omit.

   - **`## Related decisions`** — REQUIRED. `docs/decisions/*.md` ADRs that govern this integration. If none, write `_None._` — do NOT omit. (Replaces canon template's old `## History` section.)

### Section-name enforcement check

Before writing the file, verify your draft has each REQUIRED section header spelled exactly as listed above. If you find yourself wanting to use `## Overview`, `## Auth`, `## API surface`, `## Apex layer`, or `## Failure modes` (without "and runbook") — STOP. Those are not the canon section names. Rename before writing.

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
