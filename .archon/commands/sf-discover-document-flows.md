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

3. **Write `docs/flows/<Flow>.md`** following the template:

   - **Frontmatter:** title, audience: public, last_updated, last_updated_by (`archon-discover-<run-id>`), related_tickets: [], related_docs: link to the primary object's doc + any integration docs the Flow's actions imply.

   - **Overview** — 2–3 sentences: what business outcome this Flow produces, when it fires, what entity it operates on.

   - **Trigger** — table:
     - Type (RecordTriggered / Scheduled / Screen / etc.)
     - Object (for record-triggered)
     - When (RecordAfterSave / RecordBeforeSave for record-triggered; cron for scheduled; user-click for screen)
     - Entry criteria — translate the `<filters>` into human-readable conditions

   - **Behavior** — step-by-step what the Flow does. Numbered list mirroring the Flow's element graph in execution order. For each step name the element type (Decision, Update Records, Invocable Apex, etc.) and what it accomplishes in plain language.

   - **Invokes** — Apex classes / sub-flows / email alerts / outbound messages this Flow calls. For each, brief description and link to the relevant doc (object doc for the class's host object; integration doc for callouts).

   - **DML performed** — which objects this Flow writes to (creates, updates, deletes). Reference the object doc for each.

   - **Decision points** — the major `<decisions>` and what each branch does. Critical for understanding the Flow's logic.

   - **Failure handling** — fault paths if defined (`<faultConnector>`). If none, note that explicitly (means errors propagate to the user / break the flow).

   - **Governing decisions** — `docs/decisions/*.md` ADRs that constrain this Flow. Skip if none.

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
