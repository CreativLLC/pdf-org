# Plan — GRIM-48: Add SimpleGreeter utility class

## Sub-type
`create-class` (small scope)

## Acceptance criteria (from ticket)
1. `SimpleGreeter.cls` + `SimpleGreeter.cls-meta.xml` added
2. `SimpleGreeter_Test.cls` + `SimpleGreeter_Test.cls-meta.xml` added
3. Test coverage ≥ 75%
4. No changes to existing classes

## Behavior spec
`public static String greet(String name)`
- `name` null or blank → return `"Hello, friend!"`
- Otherwise → return `"Hello, " + name + "!"`

## Files changed
| Path | Op |
|---|---|
| `force-app/main/default/classes/SimpleGreeter.cls` | add |
| `force-app/main/default/classes/SimpleGreeter.cls-meta.xml` | add |
| `force-app/main/default/classes/SimpleGreeter_Test.cls` | add |
| `force-app/main/default/classes/SimpleGreeter_Test.cls-meta.xml` | add |

## Test strategy
- New `SimpleGreeter_Test` with two `@IsTest` methods:
  - `testGreetWithName` — asserts `greet('World')` returns `'Hello, World!'`
  - `testGreetWithNullOrBlank` — asserts both `greet(null)` and `greet('   ')` return `'Hello, friend!'`
- Coverage: SimpleGreeter has 2 branches; both will be exercised → expected 100% on the class.
- Per-class target from `engagement.yaml`: 75% ✓
- Regression suite: empty in `engagement.yaml`; no callers to existing classes affected.

## Patterns / standards
- No mandatory patterns for this sub-type (no triggers, no SOQL/DML, no callouts).
- Uses `String.isBlank()` for null-or-blank check (standard Apex idiom; covers both null and whitespace).

## Documentation outputs
- `docs/changelog/2026-05/GRIM-48.md`

## Risk surface
- **None.** New file, no callers, no public-API change to existing code, no governor-limit exposure, no async/platform-events.

## Out-of-scope ACs
(none)
