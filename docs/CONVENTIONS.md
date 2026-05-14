---
title: Engagement Documentation Conventions
audience: public
last_updated: 2026-05-10
last_updated_by: harness-phase-1
related_tickets: []
related_docs: [README.md]
---

# Engagement Documentation Conventions

This document is the rulebook for documentation produced by harness workflows into a per-engagement repo's `docs/` directory. It applies to humans authoring docs and to AI agents producing docs through workflows. Both are held to the same bar.

> **For harness contributors:** the rules for the harness repo itself are in `harness/CONVENTIONS.md`. The two are different.

---

## Audience

Every doc in this `docs/` directory is read by four audiences at once:

1. **Internal engineers** working on the engagement.
2. **New engineers** onboarding mid-engagement, sometimes months in.
3. **Future AI sessions** loading docs as context to make good decisions.
4. **Clients** with read-access to this repo.

The strictest audience is the client. That rules out:

- Internal candor about teammates, the client, or the relationship.
- Half-finished hypotheses presented as facts.
- War stories, frustration, blame.
- Risk logs that name individuals.
- Hyperbolic language ("disaster," "nightmare," "garbage code").

If you need to write any of the above, it goes in `_internal/`, not in the main `docs/`.

---

## Voice and tone

- **Plain, professional, declarative.** "The Renewal__c object stores per-customer renewal records" — not "Basically the Renewal__c object kinda holds renewal info."
- **Explicit about "why."** Every architectural choice, every field, every Flow trigger should explain what problem it solves and what alternatives were rejected. "What" is for audit; "why" is what makes the doc useful to onboarders and AI.
- **Concrete over abstract.** Show the Apex method, not just describe it. Show the field schema, not just name it.
- **Linked, not orphaned.** Reference related docs and Jira tickets. A doc that doesn't connect to the rest of the system is hard for both humans and AI to use.
- **Honest about constraints and tradeoffs.** "We chose async because synchronous calls would exceed 100-callout governor limits" is a real piece of information; "the system uses async" is not.

---

## Frontmatter (required on every doc)

Every doc in `docs/` carries this frontmatter at the top:

```yaml
---
title: <Human-readable title — matches the H1>
audience: public            # public | internal
last_updated: YYYY-MM-DD
last_updated_by: <human-name> | archon-run-<run-id>
related_tickets: [PROJ-123, PROJ-456]
related_docs: [objects/Renewal__c.md, decisions/0001-...md]
---
```

| Key | Purpose |
|---|---|
| `title` | Human-readable title. Matches the file's H1. |
| `audience` | `public` for client-readable docs (everything in `docs/` except `docs/_internal/`); `internal` only for `_internal/`. Workflows enforce this. |
| `last_updated` | Date in `YYYY-MM-DD`. Updated whenever the doc changes meaningfully. |
| `last_updated_by` | A human name or an Archon run ID like `archon-run-2026-05-10-acme-101`. Auditability. |
| `related_tickets` | Jira ticket keys this doc is bound to. Empty array `[]` if none. |
| `related_docs` | Other docs in this engagement that are relevant. Paths are relative to `docs/`. |

The frontmatter is checked mechanically by the `docs:validate` step at the end of every workflow. Missing or malformed frontmatter fails the run.

---

## File and folder naming

| Kind | Convention | Example |
|---|---|---|
| Standard objects (with customizations) | `<ObjectAPIName>.md` | `Account.md` |
| Custom objects | `<ObjectAPIName>.md` (with `__c` suffix) | `Renewal__c.md` |
| Flows | `<Flow_Label_With_Underscores>.md` | `Renewal_Auto_Create.md` |
| Integrations | `<System-Name>.md` (lowercase, hyphens) | `Stripe-billing.md` |
| ADRs | `NNNN-kebab-slug.md` (4-digit zero-padded) | `0001-platform-events-for-billing-sync.md` |
| Changelog entries | `<JIRA-KEY>.md` inside `changelog/YYYY-MM/` | `changelog/2026-05/ACME-101.md` |
| Patterns (engagement overrides) | `kebab-case.md` | `custom-renewal-stage-pattern.md` |
| Standards (engagement overrides) | `kebab-case.md` | `apex-test-isolation.md` |

---

## Subdirectory purposes

| Subdir | What goes there | What does NOT go there |
|---|---|---|
| `architecture/` | The "why" of this engagement's org: object model rationale, sharing model, integration topology, key design decisions that span multiple objects. Narrative-heavy. | Per-object detail (goes in `objects/`); per-Flow detail (goes in `flows/`). |
| `decisions/` | ADRs (MADR format) — significant architectural choices with explicit alternatives considered and consequences. | Trivial decisions; choices that are already documented in code or metadata. |
| `objects/` | One file per significant standard-with-customizations or custom object. Purpose, fields, relationships, dependencies, tests, constraints. | Out-of-the-box standard objects with no engagement-specific customizations. |
| `flows/` | One file per significant Flow. Trigger, purpose, decisions, side effects, error handling, ownership. | Trivial validation rules (those go in the relevant object doc as a row in the Validation Rules table). |
| `integrations/` | One file per external system. Direction(s), auth, payloads, error/retry behavior, monitoring. | Internal SF-to-SF data movement (that's architecture); transient one-shot scripts. |
| `changelog/YYYY-MM/<TICKET>.md` | One entry per change tied to a Jira ticket. What changed, why, files touched, validation outcome, doc links. | Generic monthly summaries; aggregated changes. Granularity is the point. |
| `patterns/` | Engagement-specific pattern overrides only — when this engagement deviates from the team's `harness/patterns/` library. | Patterns that already exist in `harness/patterns/`. |
| `standards/` | Engagement-specific standard overrides only — when this engagement has a constraint the team-wide standards don't account for. | Restating team standards. |
| `_internal/` | Internal-only notes that must not reach the client: risk logs, in-flight hypotheses, candor. **Gitignored from the engagement repo** (see `.gitignore`). | Anything client-safe; anything that should be discoverable in the long term. |

---

## Cross-linking

Cross-links are how humans and AI agents traverse the docs. Strong cross-linking is the difference between a useful doc set and a pile of orphaned files.

Every doc should:

- Reference at least one **upstream** doc (more general — usually an `architecture/` doc).
- Reference at least one **downstream** doc when applicable (more specific — usually an `object/`, `flow/`, or `integration/` doc).
- Reference any **decision** that constrains it (an ADR in `decisions/`).
- List the **related tickets** in frontmatter that drove or modified the doc.

Use markdown link syntax with relative paths:

```markdown
The renewal lifecycle is described in [architecture/overview.md](../architecture/overview.md).
This object is touched by [Renewal_Auto_Create](../flows/Renewal_Auto_Create.md).
```

Workflows verify that every link in `related_docs:` resolves to a file. Broken links fail the run.

---

## Changelog format

Changelog entries are **one file per ticket**, organized in `changelog/YYYY-MM/<TICKET-KEY>.md` subdirectories. There is no aggregated `CHANGELOG.md`.

Why per-ticket files?

- **Granularity for AI navigation.** An agent looking for "what changed when we touched `Renewal__c`" can grep `related_docs: [objects/Renewal__c.md]` across changelog entries.
- **Git blame clarity.** Each change is its own file with its own commit history.
- **No merge conflicts on a shared CHANGELOG.md** when multiple workflows run in parallel.
- **Direct ticket-to-changelog correspondence.** `ACME-101.md` is unambiguously the changelog for ACME-101.

The monthly subdir keeps directory listings manageable as the engagement grows.

---

## What "good" looks like

A doc is good if:

1. A new engineer can read it and form a correct mental model without asking anyone.
2. A future AI session can pattern-match its structure to produce consistent output for similar artifacts.
3. The "why" is explicit. The "what" can be inferred from the code or metadata; the "why" cannot.
4. Cross-links resolve. Frontmatter is complete and accurate.
5. It's safe to share with the client without redaction.

A doc is **not good** if:

- It only describes "what" without "why."
- It contains internal candor, blame, or war stories.
- Its frontmatter is missing or stale.
- It's an orphan — nothing references it, it references nothing.
- Its claims contradict the code or metadata it describes.

---

## Internal carve-out (`_internal/`)

`docs/_internal/` is for content that must not reach the client:

- Risk logs naming individuals or interpersonal dynamics.
- In-flight hypotheses that haven't been validated.
- "What we'd change if we could" notes.
- Candid retrospectives.
- Scratch architecture sketches before they're cleaned up.

`_internal/` is **gitignored from the engagement repo** (see `.gitignore`). It exists locally for the team but is never committed. Engineers who need persistence for internal notes use a private team Confluence space or a separate private repo — not `_internal/` in a client-shared repo.

If `_internal/` is committed by mistake, treat it as a security incident: rotate access, audit who saw the commit, and remove from history.

> **Phase 1 note:** in this exemplar engagement, `_internal/` is included in the git history *as an exemplar* showing the form. In a real engagement, it must be gitignored. The exemplar's `_internal/risk-log.md` is fictional.
