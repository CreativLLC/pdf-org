---
description: One-time-per-engagement baseline documentation. Reads SFDX metadata and writes docs/objects, docs/flows, docs/integrations, docs/features. Per ADR-0011.
argument-hint: (no arguments — operates on current engagement)
---

You are running the harness's `sf-discover-org` workflow on this engagement. Per [ADR-0011](.archon/decisions/0011-sf-discover-org-workflow.md): inventory the SFDX metadata in `force-app/main/default/`, then write baseline documentation per ADR-0010's hybrid taxonomy.

**Read-only on `force-app/`.** Doesn't deploy, doesn't run tests, doesn't modify Salesforce metadata. Documentation-only.

## What to do

1. **Verify the engagement is ready.** Check that `force-app/main/default/` exists and has content. If not, stop — tell the user to run `sf project retrieve start` first.

2. **Drive the workflow conversationally**, same model as `/sf` per the post-Phase-4 design: read `.archon/workflows/sf-discover-org.yaml`, walk its DAG node by node, presenting the cost-confirmation gate to the user in chat.

3. **At the cost-confirmation gate**, show the user:
   - Count of significant objects / flows / integrations to document (from `classify-significance` output)
   - Estimated total token cost in USD
   - The list of doc paths that will be written
   - Idempotency guarantee: re-runs preserve hand-edits

   Wait for `y` / `yes` to proceed, or `n` / `no` / empty to abort.

4. **On `y`**, kick off the three parallel category nodes (document-objects, document-flows, document-integrations), then synthesize-features, then update-index. Each agent uses **opus[1m]** (1M context window).

5. **At each step**, stream progress to the user. Examples:
   - "Inventorying force-app/... found 5 significant objects, 3 flows, 1 integration."
   - "Writing docs/objects/Renewal__c.md..."
   - "Writing docs/features/renewal-pipeline.md..."

6. **When done**, summarize:
   - Files written (counts by category)
   - Files preserved due to existing human edits (per ADR-0011 §Idempotency)
   - Files failed (and why)
   - Total tokens / dollars actually spent (vs. estimate)
   - Next step: review `git diff`, commit, push to trigger the MkDocs site rebuild

## What you must NOT do

- **Do not write to `force-app/`** — discovery is documentation-only.
- **Do not skip the cost-confirmation gate** — agentic spending is bounded by explicit consent. Per ADR-0011 §Cost guardrails.
- **Do not regenerate docs that were hand-edited** — per the idempotency contract, docs whose frontmatter `last_updated_by` is non-`archon-*` are preserved as-is. Log them as `preserved`; don't touch them.
- **Do not invoke `archon workflow run sf-discover-org`** via your Bash tool — same reasoning as `/sf` (Archon CLI runs prompt: nodes as autonomous LLM completions, no human-in-the-loop at the gate). Drive the YAML directly here in chat.

## When to suggest running this

- Right after `harness-init.sh` finishes on a new engagement that has substantial existing metadata.
- After a sandbox refresh that brought in new metadata.
- After a vendor managed-package install that added new objects/classes the team should document.
- NOT before `/sf` work for the day — that's per-ticket, not per-engagement.

**Start now.** Begin with the smoke-validate-sfdx step.
