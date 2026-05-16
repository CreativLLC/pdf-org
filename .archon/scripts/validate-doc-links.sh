#!/usr/bin/env bash
#
# validate-doc-links.sh — verify cross-references in docs/ are all valid
#
# Per ADR-0010 (engagement docs should be cross-linked + checkable) and the
# follow-up identified in the GRIM-49 audit (Opportunity.md's related_docs
# reference to a deleted changelog directory became a dangling pointer with
# no automated check to catch it).
#
# Walks docs/**/*.md in the engagement, extracts:
#   • frontmatter `related_docs:` list entries
#   • markdown `[text](relative-path.md)` body links
# Then verifies each relative target file exists. Reports broken links with
# source file + line number + target path.
#
# Skips:
#   • absolute URLs (http://, https://, mailto:)
#   • anchor-only links (#section)
#   • docs/_internal/ (gitignored; engineer notes that may not be merged yet)
#   • docs/.harness-templates/ (templates contain intentional <placeholder> targets)
#
# Usage:
#   cd <engagement-repo>
#   <path-to-harness>/scripts/validate-doc-links.sh                  # all docs
#   <path-to-harness>/scripts/validate-doc-links.sh docs/objects/    # subset
#   <path-to-harness>/scripts/validate-doc-links.sh --json           # machine-readable
#
# Exit codes:
#   0 — all links resolve
#   1 — broken links found (details printed to stderr / structured JSON to stdout)
#   2 — invocation error (not in an engagement repo, missing python3, etc.)

set -euo pipefail

# ─── arg parsing ──────────────────────────────────────────────────────

OUTPUT_MODE="text"
SCAN_PATHS=()

for arg in "$@"; do
  case "$arg" in
    --json) OUTPUT_MODE="json" ;;
    --help|-h)
      sed -n '3,32p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      printf 'unknown flag: %s\n' "$arg" >&2
      exit 2
      ;;
    *)
      SCAN_PATHS+=("$arg")
      ;;
  esac
done

# Default scan path: the engagement's docs/ if we're in one
if [ ${#SCAN_PATHS[@]} -eq 0 ]; then
  if [ -d "docs" ]; then
    SCAN_PATHS=("docs")
  else
    printf 'validate-doc-links: no docs/ directory in $(pwd); pass a path explicitly\n' >&2
    exit 2
  fi
fi

# ─── verify python3 ───────────────────────────────────────────────────

if ! command -v python3 >/dev/null 2>&1; then
  printf 'validate-doc-links: python3 not found in PATH\n' >&2
  exit 2
fi

# ─── do the scan in python (more reliable parsing than bash) ──────────

PY_SCRIPT=$(cat <<'PYEOF'
import json
import os
import re
import sys
from pathlib import Path

# Inputs from bash
output_mode = sys.argv[1]
scan_paths = sys.argv[2:]

# Patterns
FRONTMATTER_DELIM = re.compile(r"^---\s*$")
RELATED_DOCS_LINE = re.compile(r"^related_docs:\s*\[(.*)\]\s*$")
RELATED_DOCS_BLOCK_START = re.compile(r"^related_docs:\s*$")
RELATED_DOCS_BLOCK_ITEM = re.compile(r"^\s*-\s*(.+)$")
MARKDOWN_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

# Targets to skip
SKIP_SCHEMES = ("http://", "https://", "mailto:", "ftp://")
SKIP_DIRS = ("_internal", ".harness-templates", ".github")


def is_skippable_dir(path: Path) -> bool:
    parts = set(path.parts)
    return any(skip in parts for skip in SKIP_DIRS)


def split_target(raw: str) -> str:
    """Return only the path portion of a link target, stripping anchor / query / whitespace."""
    raw = raw.strip().strip("\"'`")
    # Drop anchor + query
    raw = raw.split("#", 1)[0]
    raw = raw.split("?", 1)[0]
    return raw.strip()


def collect_targets(md_path: Path) -> list:
    """Return list of (line_no, source_section, target_str) for every link in the file."""
    targets = []
    try:
        lines = md_path.read_text(encoding="utf-8").splitlines()
    except Exception as e:
        return [("file_read_error", str(e), None)]

    # Frontmatter pass: find related_docs (inline-list OR block-list)
    in_frontmatter = False
    in_related_docs_block = False
    for i, line in enumerate(lines, start=1):
        if i == 1 and FRONTMATTER_DELIM.match(line):
            in_frontmatter = True
            continue
        if in_frontmatter and FRONTMATTER_DELIM.match(line):
            in_frontmatter = False
            in_related_docs_block = False
            continue
        if not in_frontmatter:
            break  # frontmatter ended; skip rest in this pass

        m = RELATED_DOCS_LINE.match(line)
        if m:
            # Inline form: related_docs: [a.md, b.md, c.md]
            in_related_docs_block = False
            inside = m.group(1)
            for raw in inside.split(","):
                target = split_target(raw)
                if target:
                    targets.append((i, "frontmatter:related_docs", target))
            continue

        if RELATED_DOCS_BLOCK_START.match(line):
            in_related_docs_block = True
            continue

        if in_related_docs_block:
            m = RELATED_DOCS_BLOCK_ITEM.match(line)
            if m:
                target = split_target(m.group(1))
                if target:
                    targets.append((i, "frontmatter:related_docs", target))
            elif line.strip() and not line.startswith(" ") and not line.startswith("-"):
                # End of the block
                in_related_docs_block = False

    # Body pass: markdown [text](target) links — skipping fenced code blocks
    # (links inside ``` ... ``` are illustrative examples, not real cross-refs)
    in_frontmatter_body_pass = False
    in_fenced_code = False
    fence_marker = None
    for i, line in enumerate(lines, start=1):
        if i == 1 and FRONTMATTER_DELIM.match(line):
            in_frontmatter_body_pass = True
            continue
        if in_frontmatter_body_pass:
            if FRONTMATTER_DELIM.match(line):
                in_frontmatter_body_pass = False
            continue

        # Track fenced code blocks (``` or ~~~). A fence opens; the matching
        # fence (same character) closes. Indented code blocks (4+ spaces)
        # are not handled — rare in our doc style, and the false-positive
        # risk is low.
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            marker = stripped[:3]
            if not in_fenced_code:
                in_fenced_code = True
                fence_marker = marker
            elif marker == fence_marker:
                in_fenced_code = False
                fence_marker = None
            continue

        if in_fenced_code:
            continue

        # Body links. Note: backtick-decorated link text like
        # `[\`Foo.md\`](./Foo.md)` is common; we deliberately do NOT strip
        # inline code spans before matching, because that would empty the
        # bracket text and the link regex would drop the link. False
        # positives from "whole link inside inline code" (e.g.
        # `\`[text](target)\``) are rare in our doc style and tolerable.
        for m in MARKDOWN_LINK.finditer(line):
            target = split_target(m.group(2))
            if target:
                targets.append((i, "body:link", target))

    return targets


def is_skippable_target(target: str) -> bool:
    if not target:
        return True
    if target.startswith(SKIP_SCHEMES):
        return True
    # In-page anchor only (already stripped above, but defensive)
    if target.startswith("#"):
        return True
    return False


def resolve_and_check(md_path: Path, target: str, docs_root: Path) -> tuple:
    """Return (resolved_path, exists_bool, reason_str).

    Three outcomes for a relative link:
      - resolves to a file inside docs/ that exists      → valid
      - resolves to a file inside docs/ that's missing   → broken (missing target)
      - resolves to a path OUTSIDE docs/                 → broken (out-of-site)
        regardless of whether the file exists on disk: MkDocs only publishes
        docs/, so a link to force-app/ / scripts/ / etc. will 404 on the
        rendered site. Use inline code or an absolute GitHub URL instead.
    """
    # Absolute path inside the engagement (rare in docs)
    if target.startswith("/"):
        candidate = (docs_root.parent / target.lstrip("/")).resolve()
    else:
        candidate = (md_path.parent / target).resolve()

    # Is the resolved path inside docs/? If not, the link won't work on the
    # rendered site — flag it as out-of-site even if the file exists on disk.
    try:
        candidate.relative_to(docs_root)
        inside_docs = True
    except ValueError:
        inside_docs = False

    if not inside_docs:
        if candidate.exists():
            reason = (
                "out-of-site: target lives outside docs/, won't resolve on the "
                "rendered MkDocs site. Use inline code or an absolute GitHub URL."
            )
        else:
            reason = (
                "out-of-site + missing: target is outside docs/ AND doesn't exist."
            )
        return (candidate, False, reason)

    return (candidate, candidate.exists(), None if candidate.exists() else "missing")


# Walk
results = {
    "files_scanned": 0,
    "links_checked": 0,
    "links_skipped": 0,
    "broken": [],
    "file_errors": [],
}

# Resolve the docs root (parent of the first scan path that's named "docs" or under one)
docs_root = None
for sp in scan_paths:
    p = Path(sp).resolve()
    if p.name == "docs":
        docs_root = p
        break
    # Walk up to find a docs/ ancestor
    for parent in [p] + list(p.parents):
        if parent.name == "docs":
            docs_root = parent
            break
    if docs_root:
        break
if docs_root is None:
    # Best-effort fallback
    docs_root = Path("docs").resolve() if Path("docs").exists() else Path.cwd()

for sp in scan_paths:
    base = Path(sp).resolve()
    if base.is_file():
        md_files = [base] if base.suffix == ".md" else []
    elif base.is_dir():
        md_files = [p for p in base.rglob("*.md") if not is_skippable_dir(p.relative_to(base))]
    else:
        results["file_errors"].append({"path": str(base), "reason": "path does not exist"})
        continue

    for md_path in md_files:
        results["files_scanned"] += 1
        targets = collect_targets(md_path)
        for entry in targets:
            line_no, section, target = entry
            if section == "file_read_error":
                results["file_errors"].append({"path": str(md_path), "reason": target})
                continue
            if is_skippable_target(target):
                results["links_skipped"] += 1
                continue
            results["links_checked"] += 1
            resolved, exists, reason = resolve_and_check(md_path, target, docs_root)
            if not exists:
                results["broken"].append({
                    "source": str(md_path.relative_to(docs_root.parent) if docs_root else md_path),
                    "line": line_no,
                    "section": section,
                    "target": target,
                    "resolved_to": str(resolved),
                    "reason": reason,
                })

# Output
if output_mode == "json":
    print(json.dumps(results, indent=2))
else:
    print(f"validate-doc-links: scanned {results['files_scanned']} file(s), "
          f"checked {results['links_checked']} link(s), "
          f"skipped {results['links_skipped']} absolute/anchor link(s)")
    if results["file_errors"]:
        print(f"\nFile errors ({len(results['file_errors'])}):", file=sys.stderr)
        for err in results["file_errors"]:
            print(f"  {err['path']}: {err['reason']}", file=sys.stderr)
    if results["broken"]:
        print(f"\nBroken links ({len(results['broken'])}):", file=sys.stderr)
        for b in results["broken"]:
            print(f"  {b['source']}:{b['line']}  [{b['section']}]  {b['target']}", file=sys.stderr)
            print(f"    resolved to: {b['resolved_to']}", file=sys.stderr)
    else:
        print("\nAll links resolve.")

# Exit code
if results["broken"] or results["file_errors"]:
    sys.exit(1)
sys.exit(0)
PYEOF
)

python3 -c "$PY_SCRIPT" "$OUTPUT_MODE" "${SCAN_PATHS[@]}"
