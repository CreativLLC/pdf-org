# Integrations

One file per external system the engagement's org talks to. Internal SF-to-SF data movement is not an integration — that's architecture, documented in [`../architecture/`](../architecture/).

## When to add an integration doc

Add a doc when:
- A new external system is connected.
- The auth model changes for an existing integration.
- A new endpoint, webhook, or channel is added.
- The error-handling or retry behavior changes materially.

Update the existing doc when:
- A new payload field is added.
- The rate limits or bulk strategy change.
- A new failure mode is observed and a runbook is updated.

## Template

The integration doc template lives at [`harness/docs-templates/integration-doc.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/docs-templates/integration-doc.md). Required sections: Purpose, Direction(s) and pattern, Authentication, Endpoints/channels, Payloads, Error handling and retries, Bulk and rate limits, Monitoring, SF-side surface area, External-side surface area, Failure modes and runbook, History.

## Index

| System | Direction | Doc |
|---|---|---|
| Stripe | Bidirectional | [`Stripe-billing.md`](./Stripe-billing.md) |

*(Phase 1.5 will add: DocuSign, Snowflake, Marketo.)*
