---
title: "<System name> integration"
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <human-name | archon-run-id>
related_tickets: [<JIRA-KEYS>]
related_docs: [architecture/integration-topology.md, <related-objects>]
---

# `<System name>` integration

<!--
TEMPLATE: Integration documentation. One file per external system this engagement's
org talks to, located at `docs/integrations/<System-name>.md`.

Internal SF-to-SF data movement does NOT belong here — that's architecture. This
template is for talks to systems outside the Salesforce org.
-->

## Purpose

One paragraph: what this integration accomplishes for the business, and at what cost (latency, complexity, dependency). Be honest about both — integrations always carry weight.

## Direction(s) and pattern

| Direction | Pattern | Trigger |
|---|---|---|
| Outbound (SF → `<System>`) | REST callout / Platform Event / Outbound Message / Bulk API / etc. | <when> |
| Inbound (`<System>` → SF) | REST API / Platform Event subscriber / Streaming / Bulk API import / etc. | <when> |

If this integration is one-directional, say so explicitly and remove the unused row.

## Authentication

How SF authenticates with `<System>` (and vice versa, if inbound).

- **Auth method:** OAuth 2.0 (JWT bearer / Web Server / etc.) / Named Credential / API Key in protected Custom Metadata / Connected App.
- **Credential storage:** Named Credential `<Name>` / Custom Metadata Type `<Name>__mdt` / External Credential `<Name>`.
- **Rotation:** how credentials are rotated and on what cadence.
- **Scope/permissions:** what `<System>` is authorized to do; what SF is authorized to do.

> **Never document actual secrets.** Reference where they live; don't paste them.

## Endpoints / channels

For each endpoint or channel:

| Endpoint | Method | Purpose | Frequency |
|---|---|---|---|
| `<https://api.system.com/v1/path>` | POST | Create `<resource>` from SF | Per record event |
| `<https://api.system.com/v1/path/{id}>` | PATCH | Update `<resource>` from SF | Per record event |
| (inbound) `<SF Apex REST endpoint>` | POST | Receive `<event type>` from `<System>` | Async push |

## Payloads

For each notable endpoint, document the payload contract.

### Outbound: `POST /v1/<resource>`

**Request:**

```json
{
  "id": "...",
  "name": "...",
  "amount": 0,
  "currency": "USD"
}
```

**SF source:** which fields populate which payload keys, including any transformation.

| Payload key | SF source | Transformation |
|---|---|---|
| `id` | `<Object>.<ExternalId__c>` | none |
| `amount` | `<Object>.<Amount__c>` | multiplied by 100 (cents) |

**Successful response shape:** `200 OK` with `{ "id": "...", "status": "..." }`. SF stores the response `id` in `<Object>.<External_ID__c>`.

**Error response shapes:** `4xx` / `5xx` — what SF does with each.

## Error handling and retries

- **Transient errors** (network, 5xx): retried via `<mechanism>` with exponential backoff up to `<N>` attempts.
- **Permanent errors** (4xx with valid auth): logged to `<log object or platform event>`; not retried; surfaced to ops via `<channel>`.
- **Auth errors** (401/403): trigger `<refresh mechanism>` once; if refresh fails, alert via `<channel>`.
- **Idempotency:** how SF avoids duplicate side effects on retry (idempotency key in payload, deduplication in `<System>`, etc.).

## Bulk and rate limits

- **`<System>` rate limit:** <N> requests per <window>.
- **SF callout limits:** <N> callouts per transaction; the integration stays under by <strategy>.
- **Bulk operations:** how SF handles bulk record changes that produce many outbound calls (Queueable batching, Platform Event coalescing, etc.).

## Monitoring

How we know this integration is healthy.

- **Logs:** `<log object>` — fields, retention, search patterns.
- **Dashboards:** `<dashboard name or URL>`.
- **Alerts:** `<who gets paged on what condition>`.

## SF-side surface area

Code and metadata in this org that's part of the integration:

- **Apex:** `<ClassName>` — <role>; `<ClassName>` — <role>.
- **Named Credentials:** `<Name>`.
- **Custom Metadata Types:** `<Name>__mdt`.
- **Custom Settings:** `<Name>`.
- **Platform Events:** `<Event>__e`.
- **Apex REST endpoints:** `<URL pattern>`.

## `<System>`-side surface area

What lives in `<System>` for this integration:

- **Webhooks:** `<URL>` posting to `<SF endpoint>`.
- **API client / app:** `<name>`.
- **Mappings or configurations:** anything maintained on the `<System>` side that affects this integration.

## Failure modes and runbook

How to diagnose when this integration is broken.

| Symptom | Likely cause | First check | Runbook |
|---|---|---|---|
| Records not flowing into `<System>` | Auth expired / endpoint changed | `<log query>` | <link to runbook> |
| Inbound webhooks failing | SF endpoint down / payload schema drift | `<log query>` | <link to runbook> |

## Related decisions

ADRs in `docs/decisions/` that govern how this integration is shaped. Per-ticket change history lives in Jira + `git log <this file>`; this section captures the architectural choices.

- [`<NNNN-slug>`](../decisions/<NNNN-slug>.md) — <one-line summary of what the ADR locked about this integration>

If no engagement ADRs touch this integration, write `_None._` — do not omit the section.
