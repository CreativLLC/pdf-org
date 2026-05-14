# Documentation Templates

These are the canonical templates harness workflows use to produce per-engagement documentation. Each template defines the **required structure** for one documentation type. Workflows fail validation if a produced doc is missing any required section.

## The doc types

Per [ADR-0010](../decisions/0010-engagement-documentation-model.md), engagement docs use a hybrid taxonomy: object-centric **canonical** docs (technical reference) + feature-centric **derived** docs (business-readable). Plus the AI navigation entry point.

### Canonical reference layer (per artifact)

| Template | Used in | Produced by |
|---|---|---|
| [`object-doc.md`](./object-doc.md) | `engagement/docs/objects/<ObjectAPIName>.md` | Workflows that create or modify custom objects, fields, triggers, or behavior on standard objects |
| [`flow-doc.md`](./flow-doc.md) | `engagement/docs/flows/<Flow_API_Name>.md` | Workflows that create or modify Flows |
| [`integration-doc.md`](./integration-doc.md) | `engagement/docs/integrations/<System-name>.md` | Workflows that create or modify external integrations |

### Derived business-facing layer (per feature)

| Template | Used in | Produced by |
|---|---|---|
| [`feature-doc.md`](./feature-doc.md) | `engagement/docs/features/<feature-slug>.md` | Workflows whose work has a feature-level business impact; humans authoring directly when defining a new feature |

### AI navigation entry point

| Template | Used in | Produced by |
|---|---|---|
| [`index.md`](./index.md) | `engagement/docs/index.md` (one per engagement, at docs root) | `harness-init.sh` at bootstrap; updated by workflows when new object/feature/integration docs are added |

### Long-lived rationale

| Template | Used in | Produced by |
|---|---|---|
| [`adr.md`](./adr.md) | `engagement/docs/decisions/NNNN-kebab-slug.md` | Workflows whose work involves a significant architectural decision (or a human authoring directly) |

### Team-canon overrides (rare, human-authored)

| Template | Used in | Produced by |
|---|---|---|
| [`pattern-entry.md`](./pattern-entry.md) | `harness/patterns/` (canonical) and `engagement/docs/patterns/` (rare overrides) | Humans authoring; workflows do not generate new patterns |
| [`standards-override.md`](./standards-override.md) | `engagement/docs/standards/<kebab-name>.md` | Humans authoring with team approval; workflows do not generate overrides |

### Deprecated

| Template | Status |
|---|---|
| [`changelog-entry.md`](./changelog-entry.md) | ⚠ **Deprecated** per ADR-0010. Per-ticket change history lives in Jira (the structured comment) and `git log`. New `/sf` runs do not produce changelog entries. Existing files in older engagements are preserved. |

## How to use these templates

### When the harness produces a doc

The workflow:
1. Reads the relevant template.
2. Populates each section based on the work performed.
3. Validates the populated doc against the template (required sections present, frontmatter complete, links resolve).
4. Writes the doc to the engagement repo.
5. Commits as part of the same change set.

### When a human authors a doc

For docs that workflows don't generate (currently: ADRs initiated by humans, new patterns, standards overrides):

1. Copy the template to the target location.
2. Replace the title and frontmatter placeholders.
3. Fill in every required section. Don't delete sections — if a section doesn't apply, write "*Not applicable to this <doc-type>.*" with a one-line reason.
4. Run the docs validation step locally (Phase 2+) before committing.

## Template conventions

- **Frontmatter is mandatory.** Every template's frontmatter shows the required keys; populate them all.
- **Comments in HTML `<!-- ... -->` are template guidance** for the author/agent, not for the rendered doc. They can be removed in the populated version, but their guidance must be followed.
- **Placeholders use angle-bracket form**: `<ObjectAPIName>`, `<JIRA-KEY>`, `<NNNN>`. Replace each with the concrete value.
- **Anchor cross-references to relative paths.** When a template shows a link like `../objects/<Object>__c.md`, the populated doc uses the same relative form.

## Modifying templates

Templates are versioned along with the harness. Modifying a template is a deliberate act:

1. The change requires an ADR in the harness repo (added in Phase 1.5+) describing what's being added/removed/changed and why.
2. The change ships in a minor or major version of the harness depending on backwards compatibility.
3. Existing engagement docs are NOT migrated automatically — they continue to satisfy the version of the template that produced them. New docs use the new version.

If a template has a missing section that you need, propose adding it via PR rather than working around it locally.
