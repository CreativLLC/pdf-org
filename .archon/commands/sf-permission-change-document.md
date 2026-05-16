# `sf-permission-change-document`

You are producing the engagement documentation updates for the permission/security change just made. **Per [ADR-0010](../decisions/0010-engagement-documentation-model.md), documentation describes *current state*, not change history.** Per [ADR-0013](../decisions/0013-engagement-security-documentation.md), security docs live in `docs/security/` with the structure: profiles in `docs/security/profiles/`, permission sets in `docs/security/permission-sets/`, plus top-level files (`sharing-model.md`, `custom-permissions.md`, `permission-set-groups.md`, etc.).

## Inputs

- `$pull-jira-context.output` — title, description, acceptance criteria
- `$classify-sub-type.output` — sub_type, side flags
- `$plan.output`, `$ARTIFACTS_DIR/plan.md` — the plan (including `posture_shift_triggers_adr_draft`)
- `$execute.output`, `$ARTIFACTS_DIR/implementation.md` — what was done
- `$validate.output` — blast-radius summary, orphan results, OWD direction, recipient checks
- `$load-engagement-context.output` — patterns/standards, object docs

## Tools

Read, Edit, Write, Glob, Grep. Templates live at `docs/.harness-templates/` in the engagement repo (copied from `harness/docs-templates/` at bootstrap):
- `docs/.harness-templates/profile-doc.md`
- `docs/.harness-templates/permission-set-doc.md`
- `docs/.harness-templates/sharing-model.md`
- `docs/.harness-templates/object-doc.md`
- `docs/.harness-templates/adr.md`

## The aggressive-update model (per ADR-0010 §3 and ADR-0013)

For every profile / permission set / sharing rule / OWD / restriction rule touched by this run, update **every doc that references that artifact** — not just the most-affected one.

## Task

### Step 1: Inventory the change

From `$execute.output.files_changed_actual`, list:
- Profiles added/modified/deleted (names: `<Profile_Name>`)
- Permission sets added/modified/deleted (names)
- Permission set groups added/modified/deleted (names)
- Sharing rules added/modified/deleted (rule fullName, on which object)
- Objects whose OWD changed (object names)
- Restriction rules added/modified/deleted (rule fullName, on which object)
- Custom Permissions whose grants changed (names — derived from `$validate.output.removed_breakdown` + `$plan.output.added_breakdown`)

### Step 2: Update per-artifact security docs

Per ADR-0013, every changed profile and PS gets a doc.

#### For each changed profile

Update or create `docs/security/profiles/<Profile_Name>.md` per the canon template at `docs/.harness-templates/profile-doc.md`. The doc reflects the profile's *current state* in source:

- **Identity** — refresh from XML.
- **Persona** — preserve existing engineer-authored text if present (idempotency rule from ADR-0013); only fill in if the section was a placeholder or empty.
- **Object permissions** table — regenerate from the current `<objectPermissions>` blocks. Skip stock objects with stock permissions; include custom objects and non-stock standard access.
- **FLS overrides** — regenerate from `<fieldPermissions>` entries that are non-default.
- **App access**, **Tab settings**, **System permissions of note**, **Apex class access**, **VF page access**, **Connected App access** — regenerate from XML.
- **Typically assigned with** — preserve existing engineer text.
- **Related decisions** — add the engagement-ADR draft (if one was triggered this run) to the list.

Use inline code for profile/PS/object references (e.g., `` `Custom_Sales_Manager_PS` ``). **Never** write a relative markdown link to `force-app/`.

#### For each changed permission set

Update or create `docs/security/permission-sets/<PS_Name>.md` per the canon template at `docs/.harness-templates/permission-set-doc.md`. Same idempotency rule: preserve engineer-authored prose sections (Purpose, Typical assignment pattern); regenerate XML-derived tables.

If the PS was deleted, also: mark the doc with `<!-- DELETED: this PS has been removed; doc kept for git history / Jira references but will be removed in a follow-up. -->` at top of body. Don't actually `git rm` the doc in this workflow — that's a follow-up housekeeping task.

### Step 3: Update consolidated security docs

#### If OWD, sharing rule, or restriction rule changed → `docs/security/sharing-model.md`

Update the relevant section(s) per `docs/.harness-templates/sharing-model.md`:

- **Org-wide defaults** table: refresh the row for the object whose OWD changed.
- **Sharing rules** section: refresh the per-object subsection.
- **Restriction Rules** table: refresh entries.
- **Why this posture** section: preserve existing engineer-authored content. If the engagement-ADR draft was triggered (step 6), append a line: `_See [ADR-NNNN](../decisions/NNNN-slug.md) for the rationale of the most recent change._`

Surface the scratch-org caveat from `$validate.output.caveats[]` at the top of the doc (idempotently — don't duplicate it if it's already there):

```markdown
> **Note**: This doc reflects the metadata in source. Sharing/OWD behavior is validated at deploy time against a scratch org, which has limited fidelity for sharing semantics (no role hierarchy, no record volume, single user). Production sharing should be re-verified in a sandbox before release.
```

#### If PSG composition changed → `docs/security/permission-set-groups.md`

Update the relevant PSG entry: refresh the composed-PSs list, the intended-assignees note (if engineer-authored, preserve), and the cross-link to the per-PS docs.

#### If custom permission grants changed → `docs/security/custom-permissions.md`

For each Custom Permission whose grant changed:
- Refresh the "Granted by" column (which profiles/PSs now grant it).
- Refresh the "Used by" column (Apex/Flow callers — same grep as the validate step's orphan check).
- If the custom permission is now orphaned AND has no Apex callers, add a note: `_Currently unused — eligible for deletion in a follow-up._`
- If it is orphaned AND has Apex callers (`$validate.output.orphan_result == "warn"` and the engineer chose to proceed at the post-validate gate), add a prominent warning: `_⚠️ Granted to no profile/PS but still checked by Apex code; this is a runtime-broken state pending a follow-up grant or code change._`

(The single `⚠️` here is intentional and matches the inline-warning convention in existing docs. Avoid adding other emojis.)

#### If admin profile was touched → no extra doc, but cross-link

The per-profile doc already covers the change. If `$validate.output.admin_lockout_result == "fail"` and the engineer proceeded at the post-validate gate, add a note to the profile's doc:

```markdown
> **Note**: This profile's `ViewAllData` / `ModifyAllData` system access has been narrowed. Per the engagement-ADR linked in Related decisions, this is intentional and the trade-off is accepted.
```

### Step 4: Update object docs for OWD changes

For each object whose OWD changed, update `docs/objects/<Object>.md`'s "Sharing model" subsection:

- The OWD value (internal + external).
- The list of sharing rules on the object (from `docs/security/sharing-model.md`).
- The list of restriction rules on the object.
- A cross-link to `docs/security/sharing-model.md` for the org-wide context.

State-not-history: describe what the sharing model IS now. Do not say "OWD was changed from Public Read to Private on this ticket."

### Step 5: Update `docs/index.md`

- If a new profile / PS doc was created, add an entry under the security index (`docs/security/README.md` if it serves as the security index, or `docs/index.md` per the engagement's structure).
- If the security index didn't exist, do NOT create the full security taxonomy here — that's `sf-discover-org`'s job. Note the gap in `$ARTIFACTS_DIR/follow-ups.md` instead.

### Step 6: Draft engagement-ADR for posture shifts

If `$plan.output.posture_shift_triggers_adr_draft == true`, write a draft ADR to `docs/decisions/<next-N>-<slug>.md`. Compute `<next-N>` by scanning existing `docs/decisions/NNNN-*.md` files and incrementing.

**The draft is a real ADR file written from `docs/.harness-templates/adr.md`** with these stubbed-but-distinct properties:

- Top of file: a prominent comment block:
  ```markdown
  <!--
  ╔══════════════════════════════════════════════════════════════════╗
  ║ TODO: ENGINEER REVIEW REQUIRED                                   ║
  ║                                                                  ║
  ║ This ADR was generated as a draft by sf-permission-change for    ║
  ║ ticket <TICKET-KEY> because the change represents a significant  ║
  ║ posture shift (modify-owd / view-all/modify-all records change / ║
  ║ delete-business-meaningful-sharing-rule / first-restriction).    ║
  ║                                                                  ║
  ║ DO NOT flip Status from `Proposed-Draft` to `Accepted` without   ║
  ║ human review. The Context, Decision drivers, and Consequences    ║
  ║ sections need to be authored.                                    ║
  ╚══════════════════════════════════════════════════════════════════╝
  -->
  ```

- Frontmatter `last_updated_by`: `archon-permission-draft-<run-id>` (so the idempotency rule preserves engineer edits on re-run).
- Status: `Proposed-Draft` (a non-standard status that will fail any ADR-status linter — deliberately, so the engineer can't ignore it).
- `related_tickets`: `[<TICKET-KEY>]`.
- Context, Decision drivers, Considered alternatives, Decision, Consequences sections: stubbed with `_TODO: engineer to author._` markers and a one-line summary of WHAT changed (drawn from `$plan.output.summary`), but no explanation of WHY (that's the engineer's job).

The workflow does NOT block on the engineer completing the ADR. The draft ships; the engineer commits and fills it in before merging the PR (this is mostly enforceable via PR review).

### Step 7: Frontmatter rules (every doc you write or update)

- `last_updated`: today's date (YYYY-MM-DD).
- `last_updated_by`: `archon-run-<run-id>` if `$ARCHON_RUN_ID` is set; else the engineer's `git config user.email`.
- `related_tickets`: append the current ticket key; deduplicate.
- `related_docs`: update to include any other doc this change made the current doc reference.

### Step 8: Refuse to land empty required sections

Per the same rule as `sf-apex-change-document`:

- Profile doc must have non-empty Identity, Persona, Object permissions (or its `_No custom-object access._` placeholder).
- PS doc must have non-empty Identity, Purpose.
- `sharing-model.md` must have non-empty OWD table.
- `custom-permissions.md` must have a non-empty list of permissions or the documented placeholder.

Empty docs are worse than missing docs — they appear to satisfy the gate without providing value.

### Step 9: State-vs-history scan (refuse-on-detection)

Before staging, grep every doc you wrote or edited for forbidden change-history language per ADR-0010 (case-insensitive):

- `introduced with this` / `introduced in this`
- `recently added` / `newly added`
- `as of <TICKET-KEY>` / `as of 20[0-9][0-9]-`
- `previously` / `formerly` / `used to be` / `used to have access` / `used to be visible to`
- `now grants` / `now denies` / `now hides` (when contrasting with prior state)
- `was added` / `was changed` / `was removed`
- References to `../changelog/` or `docs/changelog/`
- Body sentences naming the current Jira ticket

If any pattern matches: fail with structured error listing file, line number, matched phrase, and a suggested rewrite to bare state. The engineer addresses each match and re-runs.

**Permission-change-specific addition**: do NOT write "this profile now has access to X" — write "this profile has access to X." Do NOT write "the OWD was tightened on Renewal__c" — write "Renewal__c's OWD is Private." The "was tightened" framing is exactly the change-history-in-state-doc anti-pattern.

### Step 10: Link-resolution scan

```bash
bash .archon/scripts/validate-doc-links.sh docs/
```

Exit code 0: proceed. Exit code 1: surface broken links, fail the node.

### Step 11: Stage the doc changes

`git status --porcelain` to confirm everything is in the working tree under `docs/`. Do NOT commit — the engineer commits the whole change (metadata + docs) as one commit after the Jira write-back step.

## Source-file reference formatting

Same rule as `sf-apex-change-document`:

- **Profiles, permission sets, sharing rules, custom permissions, objects** referenced in prose → inline code: `` `Custom_Sales_Manager_PS` ``, `` `Renewal__c` ``.
- **Force-app paths** (`.permissionset-meta.xml`, `.profile-meta.xml`, `.object-meta.xml`) → NEVER write relative markdown links; they 404 on the rendered site. Use inline code, or an absolute GitHub URL constructed from `mkdocs.yml`'s `repo_url`.
- **Relative links between docs inside `docs/`** (profile doc → sharing-model, PS doc → custom-permissions, etc.) → work normally.

## Output

```json
{
  "docs_created": [
    "docs/security/profiles/Custom_Sales_Manager_Profile.md",
    "docs/decisions/0008-renewal-owd-tightening.md"
  ],
  "docs_updated": [
    "docs/security/permission-sets/Custom_Sales_Manager_PS.md",
    "docs/security/custom-permissions.md",
    "docs/security/sharing-model.md",
    "docs/objects/Renewal__c.md",
    "docs/index.md"
  ],
  "docs_unchanged_but_inspected": [
    "docs/security/profiles/System_Administrator.md"
  ],
  "draft_adr_created": "docs/decisions/0008-renewal-owd-tightening.md",
  "frontmatter_validation": {
    "all_required_fields_present": true,
    "broken_related_doc_links": []
  },
  "follow_ups_recorded": false,
  "state_vs_history_scan": "pass"
}
```

If `frontmatter_validation.all_required_fields_present` is `false`, `broken_related_doc_links` is non-empty, or `state_vs_history_scan` is `fail`, the node fails. Engineer addresses the gap and re-runs.

## On state-vs-history (worth re-reading for this family)

Permission docs are especially prone to the change-history failure mode because "we changed access" feels like the obvious thing to document. It isn't. The doc describes who has access now. The change history lives in git log + the Jira comment.

Examples of what NOT to write:

- "As of GRIM-103, this profile no longer has access to `Renewal__c.Internal_Margin__c`."
- "The OWD on `Renewal__c` was tightened from Public Read to Private."
- "We removed `ManageRenewals` from this PS because..."

Equivalents that ARE state-of-the-org:

- "This profile does not have access to `Renewal__c.Internal_Margin__c`."
- "`Renewal__c` is `Private` (internal) / `Private` (external)."
- "This PS does not grant `ManageRenewals`."

The "why we changed" lives in the engagement-ADR (if posture-shifting) and in the Jira ticket.
