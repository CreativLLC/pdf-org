# Team-wide Coding Standards

> **Phase 1 status:** placeholder. The standards directory is intentionally empty in Phase 1. The four team patterns in [`../patterns/`](../patterns/) cover most of what would otherwise be standards, and the [`../examples/engagement/docs/CONVENTIONS.md`](../examples/engagement/docs/CONVENTIONS.md) covers documentation conventions. Phase 1.5 will author the standards content.

## Standards vs patterns

- A **pattern** says *"when X, do Y"* — recommended. Engineers and workflows reference patterns; deviation is allowed when justified.
- A **standard** says *"always Y, never not-Y"* — enforced. Workflows reject changes that violate a standard. Deviation requires an explicit per-engagement override (and an ADR).

If a guideline can't be enforced (mechanically or via review), it's a pattern, not a standard.

## What goes here in Phase 1.5+

Likely first standards to author:

| Standard | Scope | What it enforces |
|---|---|---|
| `apex-class-conventions.md` | Apex | `with sharing` posture explicit; one public class per file; method/parameter naming |
| `apex-test-coverage.md` | Apex tests | Per-class coverage threshold (likely 75%+); bulk-test discipline |
| `metadata-naming.md` | Metadata | Object/field/permission-set naming patterns |
| `flow-conventions.md` | Flows | Naming, fault paths required, run-as-user discipline |
| `lwc-conventions.md` | LWC | Component naming, accessibility minimums, error-boundary requirements |
| `commit-and-pr.md` | VCS | PR template, commit message form, branch naming |

Each standard ships with an ADR explaining the rationale, the enforcement mechanism, and what failure mode it prevents.

## Process for adding a standard

The bar for adding a standard is higher than for a pattern:

1. Open a Jira ticket (or GitHub issue against this repo) proposing the standard.
2. Author an ADR in this repo's `decisions/` directory (Phase 1.5+) capturing rationale, enforcement, and failure mode.
3. Author the standard document.
4. Update workflows that should enforce it.
5. Open a PR with team review (at least two senior reviewers).

Standards are not added casually.
