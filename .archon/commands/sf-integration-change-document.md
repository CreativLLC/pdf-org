# `sf-integration-change-document`

You are producing the engagement documentation updates for the integration change just made. **Per [ADR-0010](../decisions/0010-engagement-documentation-model.md), documentation describes *current state*, not change history.** Change history lives in Jira (the comment posted by `update-jira-on-completion`) and `git log`. Your job is to make the engagement's canonical (integration / object) and derived (feature) docs reflect what now exists in the org as a result of this change.

This command writes primarily to `docs/integrations/<System>.md` per [`docs-templates/integration-doc.md`](../docs-templates/integration-doc.md). It is the "describe what just changed" sibling of [`commands/sf-discover-document-integrations.md`](./sf-discover-document-integrations.md) (which is "describe what exists across the whole org"). Both write to the same canonical template; both honor the same idempotency and state-not-history rules.

## Inputs

- `$pull-jira-context.output` — title, description, acceptance criteria, `external_context` (per [ADR-0015](../decisions/0015-external-context-from-tickets.md))
- `$classify-sub-type.output` — `sub_type`, `scope`, `external_system`, side flags
- `$plan.output`, `$ARTIFACTS_DIR/plan.md` — the plan
- `$execute.output`, `$ARTIFACTS_DIR/implementation.md` — what was actually done (files added / modified / deleted; `named_credentials_referenced`; manual setup steps)
- `$validate.output` — deploy / test / pattern-compliance / webhook-auth / PE-subscriber / credentials-hygiene results
- `$load-engagement-context.output` — patterns/standards/object docs in scope

## Tools

Read, Edit, Write, Glob, Grep. Templates live at `docs/.harness-templates/` in the engagement repo (copied from `harness/docs-templates/` at bootstrap).

## The aggressive-update model (ADR-0010 §3) applied to integrations

For every external system, Named Credential, Platform Event, Connected App, callout class, or webhook handler touched by this run, walk the engagement's docs and update **every doc that references those artifacts**.

Concretely:

1. **List every artifact this run touched** — from `$execute.output.files_changed_actual` extract:
   - External system identity (from `$classify-sub-type.output.external_system`).
   - Named Credential names (from `*.namedCredential-meta.xml` paths + `$execute.output.named_credentials_referenced`).
   - Connected App names (from `*.connectedApp-meta.xml` paths).
   - Platform Event names (from `force-app/main/default/objects/*__e/` paths).
   - Apex callout class names (from `force-app/main/default/classes/*.cls` paths containing HTTP work).
   - Webhook handler class names (from `@RestResource` classes in changed files).
   - External Service Registration names (from `*.externalServiceRegistration-meta.xml` paths).
2. **For each artifact, identify candidate docs to update:**
   - `docs/integrations/*.md` — for each, check whether it references the artifact (grep for the class / NC / Connected App / PE name).
   - `docs/objects/*.md` — for any SObject the integration reads or writes (parsed from SOQL inside the callout class, or from the Platform Event's relationship to other objects via Apex publishers).
   - `docs/security/sharing-model.md` — when the integration touches sharing (e.g., a callout class declared `with sharing` reading PII; an inbound webhook writing records the caller wouldn't normally see).
   - `docs/features/*.md` — when the integration supports a documented business-facing feature.
3. **Update each matching doc** to reflect current state. Examples:
   - A new callout method added to `StripeBillingService` → update `docs/integrations/Stripe.md` "SF-side surface area" section's Apex bullet for `StripeBillingService` to describe the new method's role.
   - A new Named Credential → update the "Authentication" section to name the NC and its endpoint (NEVER the token).
   - A modified Connected App scope → update the "Authentication" section's scope/permissions line.
   - A Platform Event added → update or create `docs/integrations/<System>.md`'s "Direction(s) and pattern" table to list the PE-based channel.
   - A webhook handler created → update "Endpoints / channels" table with the inbound endpoint and "Authentication" section with the auth mechanism.

## Task

1. **Inventory the change.** From `$execute.output.files_changed_actual`, list each integration-relevant artifact (per the artifact list in §"The aggressive-update model" above).

2. **Identify candidate docs.** For each touched artifact, grep the docs tree:
   ```bash
   grep -rln "<ArtifactName>" docs/integrations docs/objects docs/security docs/features 2>/dev/null
   ```
   Build a list of `(artifact, candidate_doc_path)` pairs.

3. **Update or create `docs/integrations/<System>.md`** per [`docs-templates/integration-doc.md`](../docs-templates/integration-doc.md). All sections are REQUIRED. Section names match canon exactly — do NOT rename, omit, or reorder:

   - **Frontmatter** (required keys): `title`, `audience: public`, `last_updated` (today), `last_updated_by` (`archon-run-<run-id>` if `$ARCHON_RUN_ID` set; else the engineer's `git config user.email`), `related_tickets:` (append the current ticket key to the existing list; dedupe), `related_docs:` (relative paths to object docs for objects this integration reads/writes; `architecture/integration-topology.md` if it exists).
   - **`## Purpose`** — what this integration accomplishes for the business and at what cost.
   - **`## Direction(s) and pattern`** — outbound / inbound table.
   - **`## Authentication`** — auth method, credential storage. **Reference the Named Credential by name only.** Per [ADR-0008](../decisions/0008-credential-management.md), actual API keys, OAuth secrets, and tokens NEVER appear in this section. Acceptable: "Auth via `Stripe_API` Named Credential (Per User OAuth)." NOT acceptable: pasting a token, consumer secret, or signing key.
   - **`## Endpoints / channels`** — outbound endpoints, inbound endpoints (webhook handlers), Platform Event channels.
   - **`## Payloads`** — for each notable endpoint: request shape, SF source mapping, response shapes.
   - **`## Error handling and retries`** — transient vs permanent policy, idempotency.
   - **`## Bulk and rate limits`** — system rate limit (from external docs), SF callout limits, bulk strategy.
   - **`## Monitoring`** — logs, dashboards, alerts. If not yet wired: `_No monitoring configured; first failure will surface as a customer-facing error._`
   - **`## SF-side surface area`** — Apex callout classes, Named Credentials, Connected Apps, Platform Events, External Service Registrations, Apex REST endpoints. Each artifact named with one-line role.
   - **`## <System>-side surface area`** — webhooks configured externally, API client app, mappings maintained externally.
   - **`## Failure modes and runbook`** — table: Symptom, Likely cause, First check, Runbook.
   - **`## Related decisions`** — engagement ADRs governing this integration. If none: `_None._` — do NOT omit.

4. **Update `docs/objects/<Object>.md`** for every SObject the integration reads/writes (per the aggressive-update model). Update the "Apex automation" section to mention the callout / handler / Queueable that touches the object. Update the "Integrations" section (if the template includes one) to list the integration.

5. **Update `docs/security/sharing-model.md`** when the integration touches sharing. Specifically:
   - When a new callout class is declared `with sharing` AND reads sensitive data (PII fields, financial data) — note the integration in the sharing-model doc's "Apex sharing surface" section.
   - When an inbound webhook handler writes records — note the running user (Guest User, Integration User, etc.) and what records it can create.
   - When a Connected App grants OAuth scopes that include `api` or `refresh_token` on objects with restrictive OWD — note the Connected App in the security-model doc.

6. **Update `docs/index.md`** if a new external system was introduced (new entry under "Integration index" with one-line description). If existing entries' descriptions are now stale (the change meaningfully extended what the integration does), update them.

7. **Update or create `docs/features/<slug>.md`** if the integration supports a documented business-facing feature. Heuristic: scan the ticket title and description for words/phrases matching existing `docs/features/*.md` slugs. If matched: update the feature doc's "How it works" section to mention the new integration component. If no match and the ticket describes a new feature: create the feature doc from the template.

8. **Do NOT modify team-canon patterns or standards.** `.archon/patterns/` and `.archon/standards/` are read-only in the engagement repo (per [ADR-0002](../decisions/0002-harness-install-model.md)). If the workflow exposed a gap in canon (e.g., a new auth pattern not yet documented in [`patterns/apex-callout-pattern.md`](../patterns/apex-callout-pattern.md)), record it in `$ARTIFACTS_DIR/follow-ups.md` for a separate PR against the harness repo.

9. **Source-file reference formatting** per [ADR-0010](../decisions/0010-engagement-documentation-model.md). When you reference any file *outside* `docs/` — Apex `.cls` files, `*.namedCredential-meta.xml`, `*.connectedApp-meta.xml`, Platform Event `*.object-meta.xml`, scripts — do NOT write a relative markdown link to it. The MkDocs Material site publishes only the `docs/` tree; relative links into `force-app/` 404 on the rendered site. Two acceptable forms:
   1. **Inline code, no link** (preferred for prose): `` `StripeBillingService.cls` ``, `` `Stripe_API` ``, `` `Charge_Failed__e` ``.
   2. **Absolute GitHub URL** (when the link adds real reader value): read `mkdocs.yml` once to get `repo_url:`, then write `[StripeBillingService.cls](<repo_url>/blob/main/force-app/main/default/classes/StripeBillingService.cls)`.

   Relative links between docs *inside* `docs/` (integration → object, integration → security) work normally — the rule above is only for paths leaving the docs tree.

10. **Refuse to land empty required sections.** Integration doc must have non-empty Purpose, Direction(s) and pattern, Authentication, Endpoints / channels, SF-side surface area, and Failure modes and runbook. Object doc must have non-empty Overview, Schema, and Apex automation. If any required section comes out empty, fail this node and surface what's missing.

11. **State-vs-history scan (refuse-on-detection)** per [ADR-0010](../decisions/0010-engagement-documentation-model.md) §"State-not-history." Before staging, scan every doc you wrote or edited for change-history language. The same forbidden patterns from `sf-apex-change-document.md` apply: `introduced with this`, `recently added`, `as of <TICKET>`, `previously`, `now uses`, `was added`, references to `../changelog/`, ticket attribution in prose body.

   If any pattern matches: **fail this node with a structured error** listing file, line number, matched phrase, and suggested rewrite to bare state.

   **Also enforce the external-context privacy invariant** (per [ADR-0015](../decisions/0015-external-context-from-tickets.md)): if `$pull-jira-context.output.external_context` is non-empty, scan every doc body for substrings of 50+ tokens from any `content` field. If found, fail with a structured error — external context (Fathom transcripts, Drive docs) is working memory only.

12. **Credentials hygiene scan on doc bodies.** Before staging, run the same regex set from `sf-integration-change-validate.md` §6 against every doc you wrote or edited. If any literal credential pattern matches: **fail this node**. Per [ADR-0008](../decisions/0008-credential-management.md), credentials never appear in engagement docs — only Named Credential names. The integration doc's "Authentication" section names the NC; it does not paste the token. If the scan flags a match, the engineer either (a) rewrote the doc to reference the NC by name instead of pasting the value, or (b) confirms the match is a false positive (e.g., an example payload value from the external system's documentation that happens to match the heuristic) and re-runs with the false positive removed or the section rewritten.

13. **Link-resolution scan.** Run the link validator against the docs tree:

    ```bash
    bash .archon/scripts/validate-doc-links.sh docs/
    ```

    Exit code 0: continue to staging. Exit code 1: broken links found. Fail this node, surface the validator's output (file:line: target), let the engineer fix and re-run.

14. **Frontmatter rules** for every doc you write or update:
    - `last_updated`: today's date (YYYY-MM-DD).
    - `last_updated_by`: `archon-run-<run-id>` if `$ARCHON_RUN_ID` is set; else the engineer's `git config user.email`.
    - `related_tickets`: append the current ticket key to the existing list (deduplicate).
    - `related_docs`: update to include any other doc this change made the current doc reference.

15. **Stage the doc changes.** Run `git status --porcelain` to confirm everything is in the working tree under `docs/`. Do NOT commit — the engineer commits the whole change (integration code + docs) as one commit after the Jira write-back step succeeds.

## Output

Emit a structured JSON summary on stdout:

```json
{
  "docs_created": [
    "docs/integrations/Stripe.md"
  ],
  "docs_updated": [
    "docs/objects/Renewal__c.md",
    "docs/security/sharing-model.md",
    "docs/index.md"
  ],
  "docs_unchanged_but_inspected": [
    "docs/features/renewal-pipeline.md"
  ],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "credentials_hygiene_scan_on_docs": "pass",
  "follow_ups_recorded": false
}
```

If `frontmatter_validation.all_required_fields_present` is `false`, `broken_related_doc_links` is non-empty, or `credentials_hygiene_scan_on_docs == "fail"`, the node fails. Engineer addresses the gap and re-runs.

## On state-vs-history (worth re-reading for integrations)

The most common pitfall is writing change-history language into a state doc. Examples of what NOT to write in an integration doc:

- "As of GRIM-120, we added retry logic to `StripeBillingService.createCharge`."
- "Previously we hit Stripe's v1 API; now we use v2."
- "The team decided in 2026-05 to use Named Credentials for all OAuth."

Equivalents that ARE state-of-the-integration:

- "`StripeBillingService.createCharge` retries transient failures up to 3 times via `RetryStripeChargeJob`."
- "Calls Stripe's v2 API at `callout:Stripe_API/v2/charges`."
- "Per [`ADR-0004`](../decisions/0004-named-credentials-for-all-oauth.md) in this engagement, every OAuth integration uses a Named Credential."

The change history of "this used to be different" lives in `git log` for the doc and in the Jira ticket. The integration doc is the present tense.
