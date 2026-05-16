# `sf-discover-update-index`

You are rebuilding `docs/index.md` to reflect every doc that now exists in this engagement after discovery has populated `docs/objects/`, `docs/flows/`, `docs/integrations/`, and `docs/features/`. This is the final node of `sf-discover-org`.

Per [ADR-0010](../decisions/0010-engagement-documentation-model.md): `docs/index.md` is the **AI navigation entry point**. Future Claude agents picking up a task on this engagement load this file first and use it to decide which docs to read for their context.

## Inputs

- `$document-objects.output.objects_written` — paths to all object docs.
- `$document-flows.output.flows_written` — paths to all flow docs.
- `$document-integrations.output.integrations_written` — paths to all integration docs.
- `$document-security-overview.output.files_written` — paths to the consolidated security files (sharing-model.md, custom-permissions.md, etc.). Per ADR-0013.
- `$document-security-profiles.output.profiles_written` — paths to per-profile docs.
- `$document-security-permission-sets.output.permission_sets_written` — paths to per-PS docs.
- `$synthesize-features.output.features_written` — paths to all feature docs.
- Existing `docs/decisions/*.md` (read for the ADR list; you don't author ADRs here).
- Existing `docs/index.md` (read to preserve human edits in the Quick Paths section if any).
- The template: `docs/.harness-templates/index.md`.

## Tools

Read, Edit, Write, Glob, Grep. Writes only `docs/index.md`.

## Task

1. **Load existing `docs/index.md`** if present. Note the `last_updated_by` value.
   - If it's `archon-*`, you can safely overwrite the entire file.
   - If it's human (anything else), preserve the engineer's edits in the "Quick paths" section — those are the team's task-specific shortcuts; don't trample. The auto-managed sections (Object index, Feature index, Flow index, Integration index) can still be rebuilt.

2. **Build the index file** from the template structure:

   - **Frontmatter:** title `<Client Name> — Engagement Documentation Index`, audience: public, last_updated (today), last_updated_by (`archon-discover-<run-id>`), related_tickets: [], related_docs: [README.md].

   - **AI agents header callout** — verbatim from the template ("For AI agents: load this file first...").

   - **Quick paths** — keep the template's default quick-paths if no engineer override exists. If engineer-overridden (existing file's last_updated_by is human), preserve their version.

   - **Object index** — table rebuilt from `objects_written`. One row per object doc. Read each object doc to extract its Overview's first sentence as the one-line description.

   - **Feature index** — table rebuilt from `features_written`. One row per feature. Use the feature doc's "one-line summary" at top (italicized) as the description.

   - **Flow index** — table rebuilt from `flows_written`. One row per flow. Use the flow doc's Overview's first sentence.

   - **Integration index** — table rebuilt from `integrations_written`. One row per system.

   - **Security overview** — REQUIRED per ADR-0013. Single paragraph + 2-line cheat sheet linking to the section:

     ```
     ## Security

     Auto-generated consolidated view at [`security/`](./security/). Covers
     Org-Wide Defaults, sharing rules, Apex sharing, Custom Permissions,
     Public Groups + Queues, profiles, permission sets, and permission set
     groups. The [`security/sharing-model.md`](./security/sharing-model.md)
     page is the one-stop summary; per-profile / per-permission-set detail
     is in the [`profiles/`](./security/profiles/) and
     [`permission-sets/`](./security/permission-sets/) subdirectories.

     Profile count: N. Permission set count: N. Custom Permissions: N.
     ```

     Read the security node outputs (`$document-security-profiles.output.profiles_written`, `$document-security-permission-sets.output.permission_sets_written`, etc.) for the counts.

   - **Architectural decisions** — list the 3–5 most-impactful ADRs in `docs/decisions/`. If there are more than 5, link to the full directory. Heuristic for "most impactful": most recent active ADRs.

   - **How this index stays current** — verbatim from the template; explains that `/sf` runs maintain this index per ADR-0010.

3. **Verify cross-link integrity via the link validator.** After writing the index, run:

    ```bash
    bash .archon/scripts/validate-doc-links.sh docs/ --json
    ```

    The validator walks every `.md` under `docs/` (skipping `_internal/`, `.harness-templates/`, fenced code blocks, absolute URLs, and anchor-only links) and verifies every `related_docs:` frontmatter entry and `[text](target)` body link resolves to an existing file.

    - Exit code 0: all links resolve. Populate the output's `broken_links` array as `[]`.
    - Exit code 1: parse the validator's JSON output and copy its `broken` array into `broken_links`. Do NOT fail the node — the index is still useful; the engineer reviews and fixes the references manually before committing. The whole point of running this at end-of-discovery is to surface drift, not to abort.

4. **Verify no duplicate entries.** Each object / feature / flow / integration appears in exactly one table.

## Output

```json
{
  "index_written": "docs/index.md",
  "entries_by_section": {
    "objects": 5,
    "features": 2,
    "flows": 3,
    "integrations": 1,
    "decisions_linked": 4
  },
  "broken_links": [],
  "engineer_quick_paths_preserved": false,
  "reasoning": "Index regenerated with 5 objects, 2 features, 3 flows, 1 integration. Quick paths section is default; no prior engineer override detected."
}
```

If `broken_links` is non-empty or any section count is unexpectedly zero (e.g., `objects: 0` when `document-objects` wrote N files), this node should flag the discrepancy but not fail — log it for the engineer to investigate.

## Closing observation

After this node, the engagement's `docs/` is fully populated. The engineer should:

1. Review the generated content (`git diff` will show the additions).
2. Commit the changes with a clear message like `sf-discover-org baseline (run <id>)`.
3. Push to `origin main` to trigger the MkDocs Material site build.
4. Browse the rendered site to spot anything that needs human polish.

From this point forward, `/sf` runs against real Jira tickets maintain the docs incrementally per ADR-0010.
