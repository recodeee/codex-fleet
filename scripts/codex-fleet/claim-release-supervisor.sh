#!/usr/bin/env bash
# claim-release-supervisor — when a codex pane goes idle without completing
# its claimed Colony sub-task, release that claim so force-claim can re-route
# the work to a different pane.
#
# Distinct from supervisor.sh (quota-exhaust replacement that spawns new
# kitty windows): this watcher operates entirely inside the existing tmux
# fleet, never spawns kitty windows, only mutates Colony state and lets the
# existing force-claim daemon do the redispatch.
#
# Loop:
#   1. For each codex pane in $SESSION:$WINDOW:
#      a. Read @panel to get agent name (codex-<account-id>).
#      b. Check pane idle state via the same heuristic force-claim.sh uses
#         (default codex prompt placeholder in last 12 lines, no Working).
#   2. For each idle pane:
#      a. Walk every openspec/plans/*/plan.json and look for sub-tasks still
#         claimed_by_agent == that-agent and status != done.
#      b. If claim_age >= MIN_IDLE_SEC, call colony rescue stranded --apply
#         narrowed to that agent.
#   3. Sleep INTERVAL seconds, repeat.
#
# Environment:
#   CR_SUP_SESSION       tmux session name (default: codex-fleet)
#   CR_SUP_WINDOW        tmux window with codex panes (default: overview)
#   CR_SUP_INTERVAL      poll period in seconds (default: 60)
#   CR_SUP_MIN_IDLE_SEC  minimum claim age before releasing (default: 120)
#   CR_SUP_REPO_ROOT     repo root (default: autodetect from script location)
#   CR_SUP_DRY           1 = log only, do not call release (default: 0)
#
# Run standalone:
#   bash scripts/codex-fleet/claim-release-supervisor.sh --loop
# Or one-shot:
#   bash scripts/codex-fleet/claim-release-supervisor.sh --once

set -eo pipefail

# SI-6: pre-release staleness fence. Before we ask Colony to release a
# claim we think is stranded, sleep a few seconds and re-check that the
# claim is still held by that agent — guards against racing a worker that
# completed mid-pass.
# shellcheck source=lib/claim-fence.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/claim-fence.sh"

SESSION="${CR_SUP_SESSION:-codex-fleet}"
WINDOW="${CR_SUP_WINDOW:-overview}"
INTERVAL="${CR_SUP_INTERVAL:-60}"
MIN_IDLE_SEC="${CR_SUP_MIN_IDLE_SEC:-120}"
REPO_ROOT="${CR_SUP_REPO_ROOT:-${CODEX_FLEET_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
DRY="${CR_SUP_DRY:-0}"
MODE="loop"

while [ $# -gt 0 ]; do
  case "$1" in
    --loop)  MODE=loop; shift ;;
    --once)  MODE=once; shift ;;
    --dry)   DRY=1; shift ;;
    --interval=*) INTERVAL="${1#--interval=}"; shift ;;
    --window=*)   WINDOW="${1#--window=}"; shift ;;
    --session=*)  SESSION="${1#--session=}"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# Mirror of force-claim.sh:idle_panes(). Emits "pane_idx<TAB>agent" per idle.
idle_panes() {
  tmux list-panes -t "$SESSION:$WINDOW" -F '#{pane_index} #{@panel}' 2>/dev/null \
    | while read -r pidx panel; do
        [ -z "$pidx" ] && continue
        local tail agent
        tail=$(tmux capture-pane -t "$SESSION:$WINDOW.$pidx" -p -S -12 2>/dev/null \
                 | sed 's/\x1B\[[0-9;]*m//g')
        echo "$tail" | grep -qE "Working \([0-9]+[ms]" && continue
        echo "$tail" | grep -qE "Reviewing approval request" && continue
        echo "$tail" | grep -qE "^› (Find and fix|Use /skills|Run /review|Improve documentation|Implement|Summarize|Explain|Write tests)" \
          || continue
        agent="${panel#[}"
        agent="${agent%]}"
        [ -z "$agent" ] && continue
        printf '%s\t%s\n' "$pidx" "$agent"
      done
}

# plan_slug<TAB>subtask_index<TAB>claimed_at_epoch<TAB>title (short) for each
# sub-task currently claimed by $1 that is not yet done.
claims_for_agent() {
  local agent="$1"
  ( cd "$REPO_ROOT" && python3 - "$agent" <<'PY'
import glob, json, os, sys
agent = sys.argv[1]
for p in glob.glob("openspec/plans/*/plan.json"):
    try:
        with open(p) as f: plan = json.load(f)
    except Exception:
        continue
    slug = os.path.basename(os.path.dirname(p))
    for t in plan.get("tasks", []):
        if t.get("claimed_by_agent") != agent: continue
        if t.get("status") in ("done", "completed"): continue
        ts = t.get("claimed_at_epoch") or t.get("claimed_at") or 0
        title = (t.get("title", "") or "")[:60]
        print(f"{slug}\t{t.get('subtask_index','')}\t{ts}\t{title}")
PY
  )
}

release_for_agent() {
  local agent="$1" slug="$2" sub="$3" title="$4"
  if [ "$DRY" = "1" ]; then
    log "[DRY] release ${agent} ${slug}/sub-${sub} (${title})"
    return 0
  fi
  ( cd "$REPO_ROOT" \
    && timeout 10 colony rescue stranded --apply --agent "$agent" \
         --session "claim-release-supervisor" --repo-root "$REPO_ROOT" 2>&1 \
       | sed "s/^/  [release ${agent} ${slug}\/sub-${sub}] /" \
       | head -5
  ) || true
}

one_pass() {
  local idle=0 released=0 now slug sub claimed_ts title age
  while IFS=$'\t' read -r pidx agent; do
    [ -z "$agent" ] && continue
    idle=$((idle+1))
    while IFS=$'\t' read -r slug sub claimed_ts title; do
      [ -z "$slug" ] && continue
      now=$(date +%s)
      # Normalize ms → s if value looks like millis
      [ "$claimed_ts" -gt 9999999999 ] 2>/dev/null && claimed_ts=$((claimed_ts/1000))
      age=$((now - claimed_ts))
      if [ "$claimed_ts" -gt 0 ] && [ "$age" -lt "$MIN_IDLE_SEC" ]; then
        log "skip ${agent} ${slug}/sub-${sub} — claim age ${age}s < ${MIN_IDLE_SEC}s"
        continue
      fi
      # SI-6: re-check after a short fence; skip release if the claim
      # flipped (e.g. worker completed it between idle-detection and now).
      if ! CODEX_FLEET_REPO_ROOT="$REPO_ROOT" \
           claim_fence_check_held_by "$slug" "$sub" "$agent"; then
        log "skip ${agent} ${slug}/sub-${sub} — claim state changed during fence"
        continue
      fi
      log "RELEASE ${agent} ${slug}/sub-${sub} age=${age}s title=${title}"
      release_for_agent "$agent" "$slug" "$sub" "$title"
      released=$((released+1))
    done < <(claims_for_agent "$agent")
  done < <(idle_panes)
  log "pass: idle_panes=${idle} released=${released}"
}

if [ "$MODE" = "once" ]; then
  one_pass
  exit 0
fi

log "claim-release-supervisor up (session=${SESSION} window=${WINDOW} interval=${INTERVAL}s min_idle=${MIN_IDLE_SEC}s dry=${DRY})"
while true; do
  one_pass || true
  sleep "$INTERVAL"
done
