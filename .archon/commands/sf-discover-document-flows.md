# `sf-discover-document-flows`

You are documenting every significant active Flow in this engagement. For each Flow in `$classify-significance.output.flows`, write or update `docs/flows/<FlowAPIName>.md` per the canonical-reference template, reflecting the Flow's *current state* in `force-app/main/default/flows/`.

Runs in parallel with `document-objects` and `document-integrations`. Uses **opus[1m]** for the larger context windows Flow XML can require.

## Inputs

- `$classify-significance.output.flows` — array of significant active Flows: API name, type, target object, file path.
- The engagement's `force-app/main/default/flows/<Flow>.flow-meta.xml` files (read-only).
- Where applicable: `force-app/main/default/classes/` for invocable Apex referenced by the Flow.
- The template: `docs/.harness-templates/flow-doc.md`.

## Tools

Read, Edit, Write, Glob, Grep. Read-only on `force-app/`; writes to `docs/flows/`.

## Idempotency rule (per ADR-0011)

Per object-doc node — check existing `docs/flows/<Flow>.md` frontmatter `last_updated_by`. If non-`archon-*`, skip; log as preserved.

## Task — per significant Flow

For each Flow in the input list:

1. **Read the `.flow-meta.xml`.** Extract:
   - `<processType>` — Flow / AutoLaunchedFlow / RecordTriggeredFlow / ScreenFlow / etc.
   - `<status>` — Active / Draft / Obsolete. Should be Active per classify; double-check.
   - `<start>` element — for RecordTriggered flows: `<object>`, `<triggerType>` (RecordAfterSave, RecordBeforeSave), `<recordTriggerType>` (Create, Update, etc.), `<filters>` for entry criteria, `<scheduledPaths>` for scheduled-path branches.
   - `<actionCalls>` — invocable Apex, Email Alerts, etc. that this Flow triggers.
   - `<subflows>` — other Flows this one invokes.
   - `<decisions>` — major branch points and their conditions.
   - `<recordUpdates>`, `<recordCreates>`, `<recordDeletes>` — DML this Flow performs on which objects.
   - `<screens>` (for Screen Flows) — UI sections and what fields they expose.

2. **Read any invocable Apex.** For each `<actionCalls>` of type Apex, open the `force-app/main/default/classes/<Class>.cls` and identify the `@InvocableMethod` method's signature, what it does in 1–2 sentences.

3. **Write `docs/flows/<Flow>.md`** following the canonical template at `docs/.harness-templates/flow-doc.md`. The section names and order below match the canon exactly. **All sections are REQUIRED. Do not invent alternate names. Do not omit. Do not reorder.**

   - **Frontmatter** (required keys): `title`, `audience: public`, `last_updated` (today), `last_updated_by` (`archon-discover-<run-id>` if `$ARCHON_RUN_ID` set; else `archon-discover`), `related_tickets: []`, `related_docs:` (relative paths to the primary object's doc + any integration docs).

   - **`## Purpose`** — REQUIRED. One paragraph framing the business outcome first, then the system effect. (Not "Overview" — `## Purpose` matches canon.)

   - **`## Type and trigger`** — REQUIRED. Two-column key-value table per canon: API name, Type (RecordTriggered / Scheduled / Screen / etc.), Triggering object (if applicable), Trigger condition (translated `<filters>` in human-readable form), Trigger order (Before-save / After-save for record-triggered), Run-as user, Active version. (Not "Trigger" — `## Type and trigger` matches canon.)

   - **`## What it does`** — REQUIRED. Numbered list mirroring the Flow's element graph in execution order. Plain language, naming each element type (Decision, Update Records, Invocable Apex, etc.). A reader should be able to verify whether the Flow's implementation matches this description. (Not "Behavior" — `## What it does` matches canon.)

   - **`## Side effects`** — REQUIRED. Bullets: records created, records updated, platform events published, outbound calls, emails/notifications sent. If no side effects beyond the triggering record, write `_No side effects beyond the triggering record._` — do NOT omit. (Was "DML performed" + part of "Invokes" — `## Side effects` matches canon.)

   - **`## Error handling`** — REQUIRED. Fault paths, errors users see, errors that go silent (and why), retries. If no fault paths defined, write `_No fault paths defined; errors propagate to the user._` — do NOT omit. (Was "Failure handling" — `## Error handling` matches canon.)

   - **`## Dependencies`** — REQUIRED. Custom Metadata records, Apex actions (`<ApexClass>.<methodName>`), other Flows (subflows), permissions. Link to relevant docs. If none, write `_No external dependencies._` (Was "Invokes" — `## Dependencies` matches canon.)

   - **`## Performance and limits`** — REQUIRED. Bulkification posture, DML count per record, SOQL count per execution, known governor risks. If trivial, write `_Single-record processing; no bulk or governor risk._`

   - **`## Testing`** — REQUIRED. Apex test class (if any), manual test scenarios. If no automated coverage, write `_No automated test coverage._` — do NOT omit.

   - **`## Ownership and on-call`** — REQUIRED. Subject-matter owner, operational owner. From metadata you can only infer authorship; fill with `_Unknown — populate at first incident or via engagement.yaml: owners._`

   - **`## Related decisions`** — REQUIRED. `docs/decisions/*.md` ADRs that constrain this Flow. If none, write `_None._` — do NOT omit. (Replaces canon template's old `## History` section.)

### Section-name enforcement check

Before writing the file, verify your draft has each REQUIRED section header spelled exactly as listed above. If you find yourself wanting to use `## Overview`, `## Trigger`, `## Behavior`, `## DML performed`, `## Decision points`, `## Failure handling`, or `## Invokes` — STOP. Those are not the canon section names. Rename before writing.

### Source-file reference formatting (avoid 404s on the rendered site)

For any reference to files outside `docs/` (Apex classes, `.flow-meta.xml` source, metadata files): do NOT write relative markdown links — they 404 on the rendered MkDocs site, which only publishes `docs/`. Either format the filename as inline code (`` `Foo.cls` ``) with no link, or construct an absolute GitHub URL using `mkdocs.yml: repo_url:` + `/blob/main/<path>`. Same rule as `sf-discover-document-objects.md`; same reasoning. Relative links between docs *inside* `docs/` work normally.

4. **Cross-link aggressively.** Object docs, integration docs, sub-flow docs. Use relative paths even if the target doesn't exist yet — the other category nodes will create them.

## State, not history

Describe what the Flow does NOW. Don't write "Flow was updated in GRIM-N to handle Y" — just describe Y as part of the behavior.

## Output

```json
{
  "flows_written": [
    "docs/flows/Renewal_Auto_Create.md"
  ],
  "flows_preserved": [],
  "flows_failed": [],
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links_count": 0
  }
}
```
