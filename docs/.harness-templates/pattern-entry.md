---
title: "<Pattern name>"
audience: public
last_updated: <YYYY-MM-DD>
last_updated_by: <human-name>
related_tickets: []
related_docs: [<related-patterns-or-standards>]
---

# `<Pattern name>`

<!--
TEMPLATE: Pattern entry. One file per pattern in the team-wide pattern library
at `harness/patterns/<kebab-name>.md`, OR (rare) in a per-engagement override
at `engagement-repo/docs/patterns/<kebab-name>.md`.

A pattern documents a recurring solution to a recurring problem. It's read by
both humans (looking for the right way to solve a problem) and by harness
workflows (loading relevant patterns as context for code generation).

Patterns are NOT the same as standards. A pattern says "when X, do Y" — a
standard says "always Y, never not-Y." Standards are enforced; patterns are
recommended. If a pattern is non-negotiable, promote it to a standard.
-->

## When to apply

Concrete signals that this pattern fits. Be specific — vague triggers like "when writing Apex" mean the pattern is too general.

- **Trigger:** <specific scenario>.
- **Trigger:** <specific scenario>.

## When NOT to apply

The cases where this pattern is the wrong choice. Equally important.

- <anti-trigger>
- <anti-trigger>

## The pattern

The pattern itself, with concrete code. Show, don't just describe.

```apex
// Apex example demonstrating the pattern
public with sharing class <ClassName> {
    // ...
}
```

For multi-step patterns, narrate the steps inline:

1. <step> — *why this step.*
2. <step> — *why this step.*
3. <step> — *why this step.*

## Anti-patterns

What this pattern is *not*. Show the common mistake and explain why it's wrong.

```apex
// ❌ Anti-pattern: <name>
public class <BadExample> {
    // shows the mistake
}
```

**Why it's wrong:** <explanation>. <Failure mode this introduces>.

```apex
// ✅ Correct: <pattern name>
public class <GoodExample> {
    // shows the pattern
}
```

## Variations

If the pattern has well-known variants, document them with their tradeoffs.

### Variant 1: `<name>`

<Description.> Use when <condition>. Tradeoff: <what you give up>.

### Variant 2: `<name>` *(if applicable)*

<Description.>

## Tests

How code following this pattern is tested. Reference the test data approach (see [`testdatafactory-usage.md`](./testdatafactory-usage.md)) and any pattern-specific test setup.

```apex
@IsTest
private class <TestClassName> {
    @IsTest
    static void <descriptive_test_name>() {
        // arrange
        // act
        // assert
    }
}
```

## Constraints and gotchas

Things that catch people out when applying this pattern:

- <gotcha>
- <gotcha>

## References

- **Salesforce documentation:** <link to relevant Apex Dev Guide / LWC Dev Guide section>.
- **Trailhead:** <link if applicable>.
- **Related patterns:** [`<other-pattern>.md`](./<other-pattern>.md).
- **Related standards:** [`harness/standards/<standard>.md`](../standards/<standard>.md).
- **Related ADRs:** in the engagement repo's `docs/decisions/`, if applicable.

## History

Changes to this pattern over time. Pattern changes are uncommon and consequential — the team should know when a pattern they've internalized has been updated.

- **<YYYY-MM-DD>:** <change>.
