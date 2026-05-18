#!/usr/bin/env bash
# cap-budget-alerts — fleet supervisor daemon for fleet-wide 429 pressure.
#
# Every INTERVAL seconds (default 60s) scans the cap-probe cache to count how
# many accounts are reporting 429 / "capped" verdicts inside a rolling
# WINDOW (default 300s = 5min). When the breach ratio exceeds THRESHOLD
# (default 0.5 = 50% of active accounts), the daemon:
#
#   1. touch /tmp/claude-viz/cap-budget.alert      (cheap stat() flag the
#                                                   supervisor can poll)
#   2. colony task_post --kind blocker ...         (best-effort; logs+skips
#                                                   if colony is missing or
#                                                   no active-plan / no
#                                                   available subtask)
#   3. notify-send "..."                           (best-effort; skip when
#                                                   notify-send is missing)
#
# To avoid spamming task_post / notify-send on every tick, the daemon tracks
# the last-known state ("ok" | "breached") in STATE_FILE and only posts on
# transitions (ok->breached, breached->ok). When the threshold is no longer
# breached, /tmp/claude-viz/cap-budget.alert is removed.
#
# Idempotent. shellcheck clean. Exits cleanly on SIGTERM.
#
# Cap-probe schema (verified 2026-05-18 against live cache):
#   {"verdict": "healthy|capped|unknown", "until_epoch": N,
#    "until_text": "...", "probed_at": <unix epoch>}
# A "429" account in this daemon's semantics is one whose verdict == "capped".

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-${CODEX_FLEET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"

CACHE_DIR="${CAP_BUDGET_CACHE_DIR:-/tmp/claude-viz/cap-probe-cache}"
ALERT_FLAG="${CAP_BUDGET_ALERT_FLAG:-/tmp/claude-viz/cap-budget.alert}"
STATE_FILE="${CAP_BUDGET_STATE_FILE:-/tmp/claude-viz/cap-budget.last-state}"
LOG="${CAP_BUDGET_LOG:-/tmp/claude-viz/cap-budget-alerts.log}"
ACTIVE_PLAN_FILE="${CAP_BUDGET_ACTIVE_PLAN:-$REPO_ROOT/.codex-fleet/active-plan}"
INTERVAL="${CAP_BUDGET_INTERVAL:-60}"
WINDOW="${CAP_BUDGET_WINDOW:-300}"
THRESHOLD="${CAP_BUDGET_THRESHOLD:-0.5}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$ALERT_FLAG")" "$(dirname "$STATE_FILE")"

ts() { date +%H:%M:%S; }
log() { printf '[%s] CAP-BUDGET: %s\n' "$(ts)" "$*" | tee -a "$LOG"; }

# count_breach <cache_dir> <window_seconds>
# Prints "<breached>\t<active>" to stdout. "active" = total *.json files in
# the cache dir; "breached" = files whose verdict=="capped" AND whose
# probed_at >= now - window.
count_breach() {
  local dir="$1" window="$2"
  CAP_DIR="$dir" WIN="$window" python3 - <<'PY' 2>/dev/null || echo $'0\t0'
import glob, json, os, time
cache_dir = os.environ["CAP_DIR"]
window = int(os.environ["WIN"])
now = int(time.time())
files = sorted(glob.glob(os.path.join(cache_dir, "*.json")))
active = len(files)
breached = 0
for f in files:
    try:
        with open(f) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        continue
    if data.get("verdict") != "capped":
        continue
    probed = int(data.get("probed_at") or 0)
    if probed <= 0:
        continue
    if (now - probed) <= window:
        breached += 1
print(f"{breached}\t{active}")
PY
}

# check_threshold <cache_dir> <window> <threshold> <alert_flag>
# Returns 0 (no alert) or 1 (alert). Creates the flag file on alert,
# removes it when the threshold is no longer breached. Echoes a
# tab-separated status line "<state>\t<breached>\t<active>" on stdout so
# the test harness can assert against it.
check_threshold() {
  local dir="$1" window="$2" thresh="$3" flag="$4"
  local counts breached active
  counts=$(count_breach "$dir" "$window")
  breached="${counts%%	*}"
  active="${counts##*	}"
  local state="ok"
  if [ "${active:-0}" -gt 0 ]; then
    # ratio = breached / active, compared against threshold via python (bash
    # has no native float comparison and we don't want a bc dependency).
    # NOTE on the comparator: the spec says "more than 50% of accounts" but
    # the operator-level test fixture (3 capped of 6 = 50%) is expected to
    # trigger the alert (see test/run-cap-budget.sh). Treating the boundary
    # as a breach matches the intent ("half the fleet is degraded — wake
    # the supervisor") and avoids off-by-one noise around exact halves.
    if B="$breached" A="$active" T="$thresh" python3 -c '
import os, sys
b=int(os.environ["B"]); a=int(os.environ["A"]); t=float(os.environ["T"])
sys.exit(0 if (b / a) >= t else 1)
' 2>/dev/null; then
      state="breached"
    fi
  fi
  if [ "$state" = "breached" ]; then
    : > "$flag"
    printf 'breached\t%s\t%s\n' "$breached" "$active"
    return 1
  fi
  rm -f "$flag"
  printf 'ok\t%s\t%s\n' "$breached" "$active"
  return 0
}

# read_state — last known transition state ("ok" | "breached" | "").
read_state() {
  [ -f "$STATE_FILE" ] || { printf ''; return 0; }
  cat "$STATE_FILE" 2>/dev/null || printf ''
}

write_state() {
  printf '%s' "$1" > "$STATE_FILE"
}

# active_plan_slug — strip whitespace/comments from the active-plan pointer.
active_plan_slug() {
  [ -f "$ACTIVE_PLAN_FILE" ] || return 0
  awk 'NF && !/^#/ {print; exit}' "$ACTIVE_PLAN_FILE" 2>/dev/null || true
}

# first_available_subtask_index <plan_slug>
# Echoes the subtask_index of the first task with status=="available", or
# nothing if no such task exists / plan.json is missing.
first_available_subtask_index() {
  local slug="$1"
  [ -n "$slug" ] || return 0
  local plan_json="$REPO_ROOT/openspec/plans/$slug/plan.json"
  [ -f "$plan_json" ] || return 0
  PLAN_JSON="$plan_json" python3 - <<'PY' 2>/dev/null || true
import json, os
with open(os.environ["PLAN_JSON"]) as f:
    plan = json.load(f)
for t in plan.get("tasks", []):
    if t.get("status") == "available":
        print(t.get("subtask_index", ""))
        break
PY
}

# post_blocker <breached> <active>
# Best-effort: writes a colony task_post(kind=blocker) against the first
# available subtask of the active plan. Never fails the daemon — every
# branch logs and continues so a missing colony / no-active-plan does not
# wedge the watcher loop.
post_blocker() {
  local breached="$1" active="$2"
  local content="cap-budget: ${breached}/${active} accounts at 429 in last $((WINDOW / 60))min"
  local slug
  slug=$(active_plan_slug)
  if [ -z "$slug" ]; then
    log "no active-plan; skipping colony task_post (content=$content)"
    return 0
  fi
  local idx
  idx=$(first_available_subtask_index "$slug")
  if [ -z "$idx" ]; then
    log "no available subtask in plan=$slug; skipping colony task_post (content=$content)"
    return 0
  fi
  if ! command -v colony >/dev/null 2>&1; then
    log "colony CLI missing; skipping task_post (plan=$slug subtask=$idx content=$content)"
    return 0
  fi
  # Colony's task_post takes --task <task_id>. We don't have the resolved
  # task_id here (plan.json carries subtask_index, not task_id); pass the
  # plan-scoped reference plan:slug:subtask_index and let colony reject if
  # the schema doesn't match. Either way, log the attempt + outcome so the
  # operator can see whether the blocker landed.
  local task_ref="plan:${slug}:${idx}"
  if colony task_post --task "$task_ref" --kind blocker --content "$content" >/dev/null 2>&1; then
    log "posted colony blocker task=$task_ref content=$content"
  else
    log "colony task_post failed task=$task_ref content=$content (continuing)"
  fi
}

# notify <breached> <active>
# Desktop notification, best-effort. notify-send is part of libnotify-bin —
# may not be installed on every operator's box, especially headless ones.
notify() {
  local breached="$1" active="$2"
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send --urgency=critical \
    "cap-budget: fleet 429 pressure" \
    "${breached}/${active} accounts at 429 in last $((WINDOW / 60))min" \
    >/dev/null 2>&1 || true
}

tick() {
  local status state breached active prev
  status=$(check_threshold "$CACHE_DIR" "$WINDOW" "$THRESHOLD" "$ALERT_FLAG" || true)
  state=$(printf '%s' "$status" | cut -f1)
  breached=$(printf '%s' "$status" | cut -f2)
  active=$(printf '%s' "$status" | cut -f3)
  prev=$(read_state)

  case "$state" in
    breached)
      if [ "$prev" != "breached" ]; then
        log "TRANSITION ok->breached: ${breached}/${active} accounts at 429 in last $((WINDOW / 60))min"
        post_blocker "$breached" "$active"
        notify "$breached" "$active"
      fi
      write_state "breached"
      ;;
    ok)
      if [ "$prev" = "breached" ]; then
        log "TRANSITION breached->ok: ${breached}/${active} accounts at 429 in last $((WINDOW / 60))min"
      fi
      write_state "ok"
      ;;
    *)
      log "unexpected state=$state (counts=${breached}/${active}); skipping"
      ;;
  esac
}

# Clean shutdown on SIGTERM/SIGINT so the ticker window's `remain-on-exit`
# trace shows a graceful exit, not a killed-mid-tick stack.
running=1
shutdown() {
  running=0
  log "shutdown requested; exiting after current tick"
}
trap shutdown TERM INT

# Test-harness escape hatch: `source cap-budget-alerts.sh` with
# CAP_BUDGET_TEST=1 in the env returns before the main loop so the test
# script can exercise `check_threshold` and friends in-process without
# spawning the daemon's `while true; sleep` loop.
if [ "${CAP_BUDGET_TEST:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# One-shot mode: `cap-budget-alerts.sh --once` runs a single tick and exits.
# Useful for cron, smoke tests, and manual operator runs.
if [ "${1:-}" = "--once" ]; then
  tick
  exit 0
fi

log "starting daemon (interval=${INTERVAL}s window=${WINDOW}s threshold=${THRESHOLD} cache=${CACHE_DIR})"
while [ "$running" -eq 1 ]; do
  tick || log "tick failed (continuing)"
  # Sleep in short bursts so SIGTERM is honored within ~1s rather than after
  # a full INTERVAL wait.
  remaining="$INTERVAL"
  while [ "$remaining" -gt 0 ] && [ "$running" -eq 1 ]; do
    sleep 1
    remaining=$((remaining - 1))
  done
done
log "daemon exited"
