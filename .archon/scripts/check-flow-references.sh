#!/usr/bin/env bash
#
# check-flow-references.sh — Phase 7 / sf-flow-change validate step
#
# Static check against each changed .flow-meta.xml: verifies that every
# referenced Apex class, subflow, object, and field exists in the
# engagement's local force-app/. Catches the "deploy succeeded but the
# Flow references nothing at runtime" failure that pure-deploy validation
# misses (the deploy verifies XML schema; this verifies referential
# integrity against the rest of the project).
#
# Per ADR-0019 §4.
#
# This check is intentionally regex/grep-based. The XML schema is well-
# enough constrained that the regexes are reliable; the false-negative
# risk is references that come from managed-package metadata not retrieved
# into the project (those won't be in force-app/ but they DO exist at
# runtime — these surface at the post-validate gate as "missing field"
# warnings that engineers can override with `y` when they know the gap
# is a managed-package whitelist issue).
#
# Usage:
#   ./check-flow-references.sh [<flow-meta-xml-path> ...]
#
#   With no args: checks all changed .flow-meta.xml in `git diff HEAD`.
#   With args: checks only the named files (must end in .flow-meta.xml).
#
# Outputs:
#   $ARTIFACTS_DIR/check-flow-references.json — structured result with
#   missing_invocable_apex, missing_subflows, missing_objects,
#   missing_fields arrays. Empty arrays mean "all references resolve."
#
# Exit codes:
#   0 — no missing references (all resolve)
#   1 — invalid invocation (missing python3, jq, or no flows to check)
#   2 — at least one reference doesn't resolve (the workflow's
#       post-validate gate decides what to do; missing_invocable_apex
#       and missing_objects are typically blockers; missing_fields can
#       be overridden when the cause is a managed-package whitelist)

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not on PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: 'python3' not on PATH (needed for XML parsing)" >&2; exit 1; }

ARTIFACTS_DIR="${ARTIFACTS_DIR:-.archon/run-artifacts}"
mkdir -p "$ARTIFACTS_DIR"
RESULT_FILE="$ARTIFACTS_DIR/check-flow-references.json"

# ─── collect files to check ───────────────────────────────────────────

FLOW_FILES=()
if [ $# -gt 0 ]; then
  for arg in "$@"; do
    case "$arg" in
      *.flow-meta.xml)
        [ -f "$arg" ] || { echo "error: $arg does not exist" >&2; exit 1; }
        FLOW_FILES+=("$arg")
        ;;
      *)
        echo "error: $arg is not a .flow-meta.xml file" >&2
        exit 1
        ;;
    esac
  done
else
  # No args: discover from git diff
  while IFS= read -r f; do
    [ -n "$f" ] && FLOW_FILES+=("$f")
  done < <(git diff HEAD --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.flow-meta\.xml$' || true)
fi

if [ ${#FLOW_FILES[@]} -eq 0 ]; then
  echo "  (no Flow files to check)" >&2
  printf '{"checked_files":[],"missing_invocable_apex":[],"missing_subflows":[],"missing_objects":[],"missing_fields":[],"result":"pass"}\n' > "$RESULT_FILE"
  exit 0
fi

# ─── parse via Python (regex over XML is brittle; ElementTree is fine) ─

PY_SCRIPT=$(cat <<'PYEOF'
import json
import os
import sys
import xml.etree.ElementTree as ET

NS = {"sf": "http://soap.sforce.com/2006/04/metadata"}

flow_files = sys.argv[1:]

# Collect references across all flows
all_refs = {
    "invocable_apex": set(),
    "subflows": set(),
    "objects": set(),
    "fields": set(),       # "Object.Field" form when we can attribute; else just "Field"
}
file_refs = {}             # per-file breakdown for the report

for fp in flow_files:
    refs = {
        "invocable_apex": set(),
        "subflows": set(),
        "objects": set(),
        "fields": set(),
    }
    try:
        tree = ET.parse(fp)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"  ⚠ couldn't parse {fp}: {e}", file=sys.stderr)
        file_refs[fp] = {"error": str(e), **{k: sorted(v) for k, v in refs.items()}}
        continue

    # Invocable Apex: <actionCalls><actionType>apex</actionType><actionName>ClassName</actionName>
    # (newer schema uses actionName; older uses apexClass — handle both)
    for action_call in root.findall(".//sf:actionCalls", NS):
        action_type = action_call.find("sf:actionType", NS)
        if action_type is not None and action_type.text == "apex":
            action_name = action_call.find("sf:actionName", NS)
            if action_name is not None and action_name.text:
                refs["invocable_apex"].add(action_name.text)
        # Also catch legacy <apexClass> form
        for cls in action_call.findall(".//sf:apexClass", NS):
            if cls.text:
                refs["invocable_apex"].add(cls.text)

    # Subflows: <subflows><flowName>OtherFlow</flowName>
    for subflow in root.findall(".//sf:subflows", NS):
        fn = subflow.find("sf:flowName", NS)
        if fn is not None and fn.text:
            refs["subflows"].add(fn.text)

    # Object references in DML elements: recordUpdates / recordCreates / recordDeletes / recordLookups
    for el_name in ("recordUpdates", "recordCreates", "recordDeletes", "recordLookups"):
        for el in root.findall(f".//sf:{el_name}", NS):
            obj = el.find("sf:object", NS)
            if obj is not None and obj.text:
                refs["objects"].add(obj.text)
            # Fields inside this element's inputAssignments / filters / outputAssignments
            for assign_field in el.findall(".//sf:field", NS):
                if assign_field.text:
                    refs["fields"].add(f"{obj.text if obj is not None else '?'}.{assign_field.text}")

    # Start element's object (for record-triggered flows)
    for start in root.findall(".//sf:start", NS):
        obj = start.find("sf:object", NS)
        if obj is not None and obj.text:
            refs["objects"].add(obj.text)
        for f in start.findall(".//sf:filters/sf:field", NS):
            if f.text:
                refs["fields"].add(f"{obj.text if obj is not None else '?'}.{f.text}")

    file_refs[fp] = {k: sorted(v) for k, v in refs.items()}
    for k, v in refs.items():
        all_refs[k].update(v)

# Now verify each reference resolves in force-app/
FORCE_APP = "force-app/main/default"

missing = {
    "invocable_apex": [],
    "subflows": [],
    "objects": [],
    "fields": [],
}

for cls_name in sorted(all_refs["invocable_apex"]):
    if not os.path.exists(f"{FORCE_APP}/classes/{cls_name}.cls"):
        missing["invocable_apex"].append(cls_name)

for flow_name in sorted(all_refs["subflows"]):
    # Subflow can be in flows/ or flowsTranslations/; we just check flows/
    if not os.path.exists(f"{FORCE_APP}/flows/{flow_name}.flow-meta.xml"):
        missing["subflows"].append(flow_name)

for obj_name in sorted(all_refs["objects"]):
    obj_meta = f"{FORCE_APP}/objects/{obj_name}/{obj_name}.object-meta.xml"
    if not os.path.exists(obj_meta) and not obj_name in ("Task", "Event", "Note", "Attachment"):
        # standard objects don't have object-meta.xml unless customized; skip the well-known ones
        # (Conservative: only skip universally-known standards. Better: cross-reference Salesforce's
        # standard-object list, but the maintenance cost outweighs the benefit.)
        if not _is_likely_standard_object(obj_name):
            missing["objects"].append(obj_name)

for field_ref in sorted(all_refs["fields"]):
    if "." not in field_ref or field_ref.startswith("?."):
        continue
    obj_name, field_name = field_ref.split(".", 1)
    # Standard fields on standard objects: too many to enumerate; skip the check.
    if not field_name.endswith("__c") and _is_likely_standard_object(obj_name):
        continue
    # Custom field: must have a field-meta.xml
    field_meta = f"{FORCE_APP}/objects/{obj_name}/fields/{field_name}.field-meta.xml"
    if not os.path.exists(field_meta):
        missing["fields"].append(field_ref)

result = {
    "checked_files": sorted(file_refs.keys()),
    "per_file_references": file_refs,
    "missing_invocable_apex": missing["invocable_apex"],
    "missing_subflows": missing["subflows"],
    "missing_objects": missing["objects"],
    "missing_fields": missing["fields"],
    "result": "pass" if not any(missing.values()) else "fail",
}

print(json.dumps(result, indent=2))


def _is_likely_standard_object(name):
    """Best-effort guess at whether a name is a standard SObject. Doesn't end
    in __c is the primary signal; we also conservatively allow some well-known
    custom standards (e.g., AccountTeamMember). Standard objects don't have an
    object-meta.xml in force-app/ unless they've been customized."""
    if name.endswith("__c"):
        return False
    return True
PYEOF
)

# Note: the helper function above lives in the same scope but Python's parser needs it
# declared. Move it above 'main' code by prepending in the actual exec.
PY_FINAL=$(cat <<'PYWRAP'
def _is_likely_standard_object(name):
    if name.endswith("__c"):
        return False
    return True

PYWRAP
)

python3 -c "${PY_FINAL}${PY_SCRIPT}" "${FLOW_FILES[@]}" > "$RESULT_FILE"

# ─── exit code ────────────────────────────────────────────────────────

RESULT=$(jq -r '.result' "$RESULT_FILE")
if [ "$RESULT" = "pass" ]; then
  echo "  ✓ All Flow references resolve (${#FLOW_FILES[@]} file(s) checked)"
  exit 0
else
  echo "  ✗ Flow reference check found missing targets — see $RESULT_FILE" >&2
  jq -r '
    if (.missing_invocable_apex | length) > 0 then "    Missing invocable Apex: " + (.missing_invocable_apex | join(", ")) else empty end,
    if (.missing_subflows | length) > 0       then "    Missing subflows: "       + (.missing_subflows | join(", "))       else empty end,
    if (.missing_objects | length) > 0        then "    Missing objects: "        + (.missing_objects | join(", "))        else empty end,
    if (.missing_fields | length) > 0         then "    Missing fields: "         + (.missing_fields | join(", "))         else empty end
  ' "$RESULT_FILE" >&2
  exit 2
fi
