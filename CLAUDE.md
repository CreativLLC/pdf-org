# CLAUDE.md — Meditrina engagement

You're working in the **Meditrina** engagement repo (alias `meditrina-pdf`). This repo is a Salesforce SFDX project + harness content.

## Two modes

- **Work mode** (changes to the org or repo): requires a Jira ticket from project `GRIM`. Triggered via `/sf <TICKET>` slash command.
- **Explore mode** (reading, learning, asking questions): direct Claude Code use. Read-only. No commits, no deploys, no Jira posts.

If you're asked to make a change without a Jira ticket, **refuse and ask for the ticket key**. Suggest `/sf <TICKET>`. The harness's on-rails principle is non-negotiable.

## Where things live

- **Harness content** (read-only, copied from harness repo at bootstrap): `.archon/{workflows,commands,scripts,patterns,standards}`, `docs/.harness-templates/`
- **Engagement docs** (we author and update these): `docs/{architecture,decisions,objects,flows,integrations,changelog,patterns,standards}`
- **Internal-only notes** (gitignored): `docs/_internal/`
- **Engagement config**: `engagement.yaml` at the repo root.

## SF org

This engagement targets SF org alias `meditrinaPOCsb` (API 66, source_tracked model). The harness shells out to `sf` commands using that alias.

## Credentials

Managed by direnv per [harness/decisions/0008-credential-management.md](.). Tokens live at `~/.archon/credentials/meditrina-pdf/.envrc` — outside this workspace. Never paste credentials into any file in this repo.

## When you start work

1. `cd` here. direnv auto-loads credentials.
2. Run `/sf <TICKET>` with a real Jira ticket key from project `GRIM`.
3. The dispatcher classifies, shows a confirmation, then runs the matching workflow.
