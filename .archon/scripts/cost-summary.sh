#!/usr/bin/env bash
#
# cost-summary.sh — aggregate _internal/cost-log.jsonl into readable summaries.
# Per ADR-0016.
#
# Usage:
#   cd <engagement-repo>
#   ~/harness/scripts/cost-summary.sh                         # rolling 30 days, by workflow
#   ~/harness/scripts/cost-summary.sh --by ticket             # top tickets by cost
#   ~/harness/scripts/cost-summary.sh --by model              # by Claude model
#   ~/harness/scripts/cost-summary.sh --by day                # daily totals
#   ~/harness/scripts/cost-summary.sh --since 2026-05-01      # custom date range
#   ~/harness/scripts/cost-summary.sh --top 10                # top N
#   ~/harness/scripts/cost-summary.sh --json                  # raw aggregated data
#
# Estimation accuracy: ~20%. Per-node token counts are heuristics, not
# actuals from API responses. For billing-grade numbers, see the
# Anthropic Console (Teams / Enterprise tier).
#
# Exit codes:
#   0 — summary produced
#   1 — invocation error / not in an engagement / no log file

set -euo pipefail

# ─── output helpers ────────────────────────────────────────────────────

if [ -t 1 ]; then
  C_RESET=$'\e[0m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
else
  C_RESET= C_RED= C_GREEN= C_YELLOW= C_BOLD= C_DIM=
fi

err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
warn() { printf '%s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }

# ─── arg parsing ───────────────────────────────────────────────────────

BY="workflow"
SINCE=""
UNTIL=""
TOP=10
JSON_OUTPUT=0
ALL_ENGAGEMENTS_PATTERN=""

# Default: last 30 days
SINCE_DEFAULT=$(date -u -d "30 days ago" +"%Y-%m-%d" 2>/dev/null || date -u -v-30d +"%Y-%m-%d")
UNTIL_DEFAULT=$(date -u +"%Y-%m-%d")
SINCE="$SINCE_DEFAULT"
UNTIL="$UNTIL_DEFAULT"

while [ $# -gt 0 ]; do
  case "$1" in
    --by)
      BY="$2"
      shift 2
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --until)
      UNTIL="$2"
      shift 2
      ;;
    --top)
      TOP="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    --all-engagements)
      ALL_ENGAGEMENTS_PATTERN="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      err "unknown argument: $1"
      exit 1
      ;;
  esac
done

case "$BY" in
  workflow|ticket|model|day) ;;
  *)
    err "--by must be one of: workflow, ticket, model, day (got: $BY)"
    exit 1
    ;;
esac

# ─── locate log files ──────────────────────────────────────────────────

if [ -n "$ALL_ENGAGEMENTS_PATTERN" ]; then
  # Glob across multiple engagement repos
  LOG_FILES=()
  for path in $ALL_ENGAGEMENTS_PATTERN; do
    if [ -f "$path/_internal/cost-log.jsonl" ]; then
      LOG_FILES+=("$path/_internal/cost-log.jsonl")
    fi
    # Also pick up rotated monthly logs
    for rotated in "$path"/_internal/cost-log-*.jsonl; do
      [ -f "$rotated" ] && LOG_FILES+=("$rotated")
    done
  done
  if [ ${#LOG_FILES[@]} -eq 0 ]; then
    err "no cost-log.jsonl files found matching: $ALL_ENGAGEMENTS_PATTERN"
    exit 1
  fi
  ENGAGEMENT_LABEL="all engagements (${#LOG_FILES[@]} repos)"
else
  # Single engagement (current dir)
  ENGAGEMENT_DIR="$(pwd)"
  if [ ! -f "$ENGAGEMENT_DIR/engagement.yaml" ]; then
    err "not inside an engagement repo (no engagement.yaml)"
    exit 1
  fi

  LOG_FILES=()
  [ -f "$ENGAGEMENT_DIR/_internal/cost-log.jsonl" ] && LOG_FILES+=("$ENGAGEMENT_DIR/_internal/cost-log.jsonl")
  for rotated in "$ENGAGEMENT_DIR"/_internal/cost-log-*.jsonl; do
    [ -f "$rotated" ] && LOG_FILES+=("$rotated")
  done

  if [ ${#LOG_FILES[@]} -eq 0 ]; then
    warn "no cost-log.jsonl found at $ENGAGEMENT_DIR/_internal/"
    warn "  Either no /sf runs have completed yet, or the engagement is on an older harness version."
    warn "  Cost logging started with harness version supporting ADR-0016."
    exit 1
  fi

  ENGAGEMENT_ALIAS=$(grep -E '^engagement_alias:' "$ENGAGEMENT_DIR/engagement.yaml" 2>/dev/null \
    | head -1 | sed -E 's/^engagement_alias:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/' \
    || echo "unknown")
  ENGAGEMENT_LABEL="$ENGAGEMENT_ALIAS"
fi

# ─── verify python3 ────────────────────────────────────────────────────

if ! command -v python3 >/dev/null 2>&1; then
  err "python3 not found in PATH"
  exit 1
fi

# ─── aggregate via python ──────────────────────────────────────────────

PY_SCRIPT=$(cat <<'PYEOF'
import json
import sys
from collections import defaultdict
from datetime import datetime

by_axis = sys.argv[1]
since = sys.argv[2]
until = sys.argv[3]
top_n = int(sys.argv[4])
json_output = sys.argv[5] == "1"
log_files = sys.argv[6:]

# Per-token costs (USD per Mtok). Updated when Anthropic rates change.
# Keep in sync with ADR-0016.
RATES = {
    "haiku":   {"in": 1,  "out": 5},
    "sonnet":  {"in": 3,  "out": 15},
    "opus":    {"in": 15, "out": 75},
    "opus_1m": {"in": 20, "out": 100},
}

records = []
for log_file in log_files:
    try:
        with open(log_file, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                    records.append(rec)
                except json.JSONDecodeError:
                    continue
    except FileNotFoundError:
        continue

# Date-filter
since_dt = datetime.fromisoformat(since + "T00:00:00")
until_dt = datetime.fromisoformat(until + "T23:59:59")
filtered = []
for r in records:
    ts_str = r.get("ts", "")
    try:
        ts = datetime.fromisoformat(ts_str.replace("Z", ""))
        if since_dt <= ts <= until_dt:
            filtered.append(r)
    except (ValueError, AttributeError):
        continue

# Aggregate
totals = {
    "runs": len(filtered),
    "cost": sum(r.get("est_cost_usd", 0) for r in filtered),
    "duration_seconds": sum(r.get("duration_seconds", 0) for r in filtered),
    "input_tokens": sum(r.get("est_input_tokens", 0) for r in filtered),
    "output_tokens": sum(r.get("est_output_tokens", 0) for r in filtered),
}

# Group-by
groups = defaultdict(lambda: {"runs": 0, "cost": 0.0, "duration": 0})

for r in filtered:
    if by_axis == "workflow":
        key = r.get("workflow", "unknown")
    elif by_axis == "ticket":
        key = r.get("ticket", "—") or "—"
    elif by_axis == "model":
        # Sum the dominant model from the nodes map
        nodes = r.get("nodes", {})
        if nodes:
            # Heaviest model wins as the "primary"
            order = ["opus_1m", "opus", "sonnet", "haiku"]
            for m in order:
                if nodes.get(m, 0) > 0:
                    key = m
                    break
            else:
                key = "bash-only"
        else:
            key = "unknown"
    elif by_axis == "day":
        key = r.get("ts", "")[:10]  # YYYY-MM-DD
    else:
        key = "all"

    groups[key]["runs"] += 1
    groups[key]["cost"] += r.get("est_cost_usd", 0)
    groups[key]["duration"] += r.get("duration_seconds", 0)

# Sort by cost descending
sorted_groups = sorted(groups.items(), key=lambda kv: kv[1]["cost"], reverse=True)[:top_n]

if json_output:
    payload = {
        "since": since,
        "until": until,
        "totals": totals,
        "by": by_axis,
        "groups": [
            {"key": k, "runs": v["runs"], "cost": round(v["cost"], 2), "duration_seconds": v["duration"]}
            for k, v in sorted_groups
        ],
    }
    print(json.dumps(payload, indent=2))
else:
    # Pretty-print
    print(f"\nTotal runs:        {totals['runs']}")
    print(f"Total est. cost:   ${totals['cost']:.2f}")
    if totals['runs'] > 0:
        print(f"Avg per run:       ${totals['cost'] / totals['runs']:.2f}")
        print(f"Total wall-clock:  {totals['duration_seconds'] // 60} min")
    print(f"\nBy {by_axis}:")
    if not sorted_groups:
        print("  (no records in the date range)")
    else:
        for key, v in sorted_groups:
            avg = v["cost"] / v["runs"] if v["runs"] else 0
            print(f"  {key:<35} {v['runs']:>4} runs · ${v['cost']:>7.2f} · avg ${avg:.2f}")

    print(f"\n* Estimates only. See Anthropic Console for billing-grade numbers.")
PYEOF
)

# ─── render header ─────────────────────────────────────────────────────

if [ "$JSON_OUTPUT" -eq 0 ]; then
  printf '\n%sCost summary — %s, %s → %s%s\n' "$C_BOLD" "$ENGAGEMENT_LABEL" "$SINCE" "$UNTIL" "$C_RESET"
  printf '%s%s%s\n' "$C_DIM" "═══════════════════════════════════════════════════════════════" "$C_RESET"
fi

# ─── run aggregator ────────────────────────────────────────────────────

python3 -c "$PY_SCRIPT" "$BY" "$SINCE" "$UNTIL" "$TOP" "$JSON_OUTPUT" "${LOG_FILES[@]}"
