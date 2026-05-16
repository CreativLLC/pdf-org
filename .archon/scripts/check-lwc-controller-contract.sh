#!/usr/bin/env bash
#
# check-lwc-controller-contract.sh — Phase 7 / sf-lwc-change validate step
#
# Verifies that every @salesforce/apex/ import in an LWC's JavaScript
# resolves to an @AuraEnabled method on the named Apex controller. Catches
# the "deploys clean but the wire fails at runtime" failure mode that
# pure-deploy validation misses — the platform doesn't verify the LWC↔
# controller contract at deploy time.
#
# Per ADR-0021 §4.
#
# Detection patterns:
#   import getRenewals from '@salesforce/apex/RenewalController.getRenewals';
#   import updateStatus from '@salesforce/apex/RenewalController.updateStatus';
#
# For each match, verify:
#   force-app/main/default/classes/RenewalController.cls contains a method
#   annotated @AuraEnabled (with optional cacheable=true / continuation=true)
#   AND named matching the imported identifier.
#
# Also surfaces orphan @AuraEnabled methods (controller has methods no LWC
# imports — informational only, not a failure).
#
# Usage:
#   ./check-lwc-controller-contract.sh \
#       --lwcs "lwc1,lwc2,..." \
#       --controllers "Controller1,Controller2,..."
#
#   Both flags required. Comma-separated names (no spaces).
#
# Outputs:
#   $ARTIFACTS_DIR/check-lwc-controller-contract.json — structured result
#
# Exit codes:
#   0 — all imports resolve, contract intact
#   1 — invalid invocation
#   2 — at least one import doesn't resolve to an @AuraEnabled method

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not on PATH" >&2; exit 1; }

ARTIFACTS_DIR="${ARTIFACTS_DIR:-.archon/run-artifacts}"
mkdir -p "$ARTIFACTS_DIR"
RESULT_FILE="$ARTIFACTS_DIR/check-lwc-controller-contract.json"

# ─── arg parsing ──────────────────────────────────────────────────────

LWCS_CSV=""
CONTROLLERS_CSV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --lwcs)
      LWCS_CSV="$2"
      shift 2
      ;;
    --controllers)
      CONTROLLERS_CSV="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '3,32p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$LWCS_CSV" ]; then
  echo "error: --lwcs is required (comma-separated LWC component names)" >&2
  exit 1
fi

if [ -z "$CONTROLLERS_CSV" ]; then
  echo "error: --controllers is required (comma-separated Apex controller class names)" >&2
  exit 1
fi

# Convert CSVs to bash arrays
IFS=',' read -ra LWCS <<< "$LWCS_CSV"
IFS=',' read -ra CONTROLLERS <<< "$CONTROLLERS_CSV"

FORCE_APP="force-app/main/default"

# ─── collect imports from each LWC ────────────────────────────────────

BROKEN_IMPORTS=()       # "lwc:imported_name:controller.method:reason"
IMPORTED_METHODS=()     # "controller.method" — for orphan detection

for lwc in "${LWCS[@]}"; do
  lwc=$(echo "$lwc" | tr -d '[:space:]')
  [ -z "$lwc" ] && continue
  js_file="$FORCE_APP/lwc/${lwc}/${lwc}.js"
  if [ ! -f "$js_file" ]; then
    echo "  ⚠ $js_file not found — skipping $lwc" >&2
    continue
  fi

  # Extract: import <localName> from '@salesforce/apex/<Controller>.<method>';
  # Tolerant of single OR double quotes, optional whitespace.
  while IFS= read -r line; do
    # Match: from '@salesforce/apex/Controller.method' or from "@salesforce/apex/Controller.method"
    if [[ "$line" =~ from[[:space:]]*[\'\"]\@salesforce/apex/([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)[\'\"] ]]; then
      controller="${BASH_REMATCH[1]}"
      method="${BASH_REMATCH[2]}"
      cls_file="$FORCE_APP/classes/${controller}.cls"

      IMPORTED_METHODS+=("${controller}.${method}")

      if [ ! -f "$cls_file" ]; then
        BROKEN_IMPORTS+=("${lwc}|${controller}.${method}|controller class not found at ${cls_file}")
        continue
      fi

      # Search for @AuraEnabled + the method name. Regex: @AuraEnabled (possibly
      # with parameters) followed eventually by 'public' and the method name +
      # opening paren. Tolerant of newlines between the annotation and the
      # signature, and of return-type variations.
      #
      # Strategy: get the line range from @AuraEnabled to the next ';' or '{',
      # then check whether the method name appears inside.
      if ! awk -v method="$method" '
        /^[[:space:]]*@AuraEnabled/ { in_block=1; block=""; }
        in_block { block = block " " $0 }
        in_block && /[{;]/ {
          if (block ~ ("[[:space:]]" method "[[:space:]]*\\(")) {
            found=1; exit
          }
          in_block=0; block=""
        }
        END { exit (found ? 0 : 1) }
      ' "$cls_file"; then
        BROKEN_IMPORTS+=("${lwc}|${controller}.${method}|no @AuraEnabled method named ${method} in ${controller}")
      fi
    fi
  done < "$js_file"
done

# ─── orphan @AuraEnabled methods (informational) ──────────────────────

ORPHAN_METHODS=()
for controller in "${CONTROLLERS[@]}"; do
  controller=$(echo "$controller" | tr -d '[:space:]')
  [ -z "$controller" ] && continue
  cls_file="$FORCE_APP/classes/${controller}.cls"
  [ -f "$cls_file" ] || continue

  # Extract all @AuraEnabled method names
  while IFS= read -r method_name; do
    [ -z "$method_name" ] && continue
    # Is this method in IMPORTED_METHODS?
    qualified="${controller}.${method_name}"
    found_in_imports=0
    for imp in "${IMPORTED_METHODS[@]}"; do
      if [ "$imp" = "$qualified" ]; then
        found_in_imports=1
        break
      fi
    done
    [ "$found_in_imports" -eq 0 ] && ORPHAN_METHODS+=("$qualified")
  done < <(awk '
    /^[[:space:]]*@AuraEnabled/ { in_block=1; block=""; next }
    in_block { block = block " " $0 }
    in_block && /[{;]/ {
      # Match: public <returnType> <methodName>(
      if (match(block, /[[:space:]]public[[:space:]]+[A-Za-z<>,_[:space:]]+[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(/, m)) {
        print m[1]
      }
      in_block=0; block=""
    }
  ' "$cls_file")
done

# ─── emit JSON result ─────────────────────────────────────────────────

BROKEN_JSON=$(printf '%s\n' "${BROKEN_IMPORTS[@]}" | python3 -c '
import json, sys
out = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split("|", 2)
    if len(parts) == 3:
        out.append({"lwc": parts[0], "import": parts[1], "reason": parts[2]})
print(json.dumps(out))
')

ORPHAN_JSON=$(printf '%s\n' "${ORPHAN_METHODS[@]}" | python3 -c '
import json, sys
out = sorted({line.strip() for line in sys.stdin if line.strip()})
print(json.dumps(out))
')

IMPORTED_JSON=$(printf '%s\n' "${IMPORTED_METHODS[@]}" | python3 -c '
import json, sys
out = sorted({line.strip() for line in sys.stdin if line.strip()})
print(json.dumps(out))
')

RESULT="pass"
[ "${#BROKEN_IMPORTS[@]}" -gt 0 ] && RESULT="fail"

cat > "$RESULT_FILE" <<JSON
{
  "checked_lwcs": $(printf '%s\n' "${LWCS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'),
  "checked_controllers": $(printf '%s\n' "${CONTROLLERS[@]}" | python3 -c 'import json,sys; print(json.dumps([c.strip() for c in sys.stdin if c.strip()]))'),
  "imported_methods": $IMPORTED_JSON,
  "broken_imports": $BROKEN_JSON,
  "orphan_methods": $ORPHAN_JSON,
  "result": "$RESULT"
}
JSON

# ─── exit ─────────────────────────────────────────────────────────────

if [ "$RESULT" = "pass" ]; then
  if [ "${#ORPHAN_METHODS[@]}" -gt 0 ]; then
    echo "  ✓ Controller contract intact (${#IMPORTED_METHODS[@]} import(s) verified)"
    echo "    Informational: ${#ORPHAN_METHODS[@]} @AuraEnabled method(s) not imported by any in-scope LWC"
  else
    echo "  ✓ Controller contract intact (${#IMPORTED_METHODS[@]} import(s) verified)"
  fi
  exit 0
else
  echo "  ✗ Controller contract broken — see $RESULT_FILE" >&2
  for b in "${BROKEN_IMPORTS[@]}"; do
    IFS='|' read -r lwc imp reason <<< "$b"
    echo "    ${lwc}: ${imp} — ${reason}" >&2
  done
  exit 2
fi
