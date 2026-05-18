#!/usr/bin/env bash
#
# stall-watcher — two-mode codex-fleet daemon:
#
#   (1) auto-dismiss interactive prompts (SI-2): every 5s, capture each
#       worker pane's tail and detect the three known codex-CLI blockers:
#         - "Do you trust the contents of this directory" → send `1\r`
#         - "External agent config detected"             → send `3\r`
#         - "Create a plan?" + plan-mode hint            → send `\r`
#       Each dismissal is recorded as a Colony task_post note against the
#       worker's current claimed task (best-effort) and always logged to
#       NDJSON at $FLEET_STATE_DIR/stall-watcher.log so we never deadlock
#       on Colony being unreachable.
#
#       Per-pane dismissed-recently cache (SI-12): after dispatching keys
#       for (pane, kind), the daemon records the unix timestamp into the
#       in-memory DISMISSED_AT associative array keyed by "<pane>:<kind>".
#       Subsequent ticks consult should_dispatch_dismissal() before any
#       send-keys: if (now - DISMISSED_AT[pane:kind]) is less than
#       CODEX_FLEET_DISMISS_COOLDOWN_SECONDS (default 30), the dispatch is
#       suppressed silently (no log line, no key injection). This closes
#       the regression where the same trust-dir prompt was still visible
#       in capture-pane buffer 5s after dismissal, causing a literal '1'
#       to be re-injected into the codex chat buffer as a user message.
#       The cache is in-memory only and clears on daemon restart.
#
#   ENV vars consumed:
#     CODEX_FLEET_DISMISS_COOLDOWN_SECONDS  (default 30)
#         Per-(pane,kind) suppression window in seconds. Set to 0 to
#         disable the cooldown (every detection dispatches).
#
#   (2) rescue stranded plan claims so the queue keeps moving, and hand
#       the released slot to the supervisor for takeover-worker spawning.
#       This is the original behaviour of stall-watcher.sh: one codex
#       worker claims a sub-task then dies (cap hit, user kill, idle wait
#       that never resumes); the stale claim blocks every downstream
#       sub-task and the whole fleet wedges. The loop calls
#       `colony rescue stranded --apply --json` on a slower cadence and
#       enqueues `takeover_recommended` events for supervisor.sh to act
#       on.
#
# Both modes are idempotent. The prompt classifier is exposed as a
# sourceable function (`classify_prompt_kind`) so it can be unit-tested
# from scripts/codex-fleet/test/run-stall-replay.sh without spawning a
# daemon.
#
# Usage:
#   bash scripts/codex-fleet/stall-watcher.sh
#   STALL_WATCHER_OLDER_THAN=20m bash scripts/codex-fleet/stall-watcher.sh
#   STALL_WATCHER_INTERVAL=30 bash scripts/codex-fleet/stall-watcher.sh
#   bash scripts/codex-fleet/stall-watcher.sh --once       # single tick + exit
#   bash scripts/codex-fleet/stall-watcher.sh --dry-run    # rescue scan only
#   bash scripts/codex-fleet/stall-watcher.sh --prompts-only   # skip rescue
#   bash scripts/codex-fleet/stall-watcher.sh --rescue-only    # skip prompts

# Allow `source` from the test harness without exec'ing the daemon.
# Detect that case by checking BASH_SOURCE[0] vs $0.
__stall_watcher_sourced=0
if [ "${BASH_SOURCE[0]:-}" != "${0:-}" ]; then
  __stall_watcher_sourced=1
fi

if [ "$__stall_watcher_sourced" = "0" ]; then
  set -eo pipefail
fi

# ---------- classifier (sourceable) ---------------------------------------
#
# classify_prompt_kind <captured-tail-as-stdin>
#   Reads up to 30 lines from stdin and prints one of:
#     trust-dir       — "Do you trust the contents of this directory" prompt
#     external-agent  — "External agent config detected" prompt
#     plan-prompt     — codex-CLI "Create a plan?" with plan-mode hint
#     none            — no actionable prompt detected
#
# Implementation note: we read into a variable first so multiple grep
# passes share the same input, and we prefer fgrep-style fixed-string
# matches to avoid regex surprises in the captured TUI output.
classify_prompt_kind() {
  local tail
  tail="$(cat)"

  # Limit to the last 30 lines — the prompts always sit at the bottom of
  # the rendered pane. Using tail keeps the match cheap.
  tail="$(printf '%s\n' "$tail" | tail -n 30)"

  if printf '%s' "$tail" | grep -qF 'Do you trust the contents of this directory'; then
    printf 'trust-dir\n'
    return 0
  fi

  if printf '%s' "$tail" | grep -qF 'External agent config detected'; then
    printf 'external-agent\n'
    return 0
  fi

  # Plan prompt: require BOTH the "Create a plan?" text AND a plan-mode
  # hint ("shift + tab use Plan mode" OR "esc dismiss"). The double match
  # avoids false positives from incidental "Create a plan?" mentions in
  # commit messages or chat history echoed to the pane.
  if printf '%s' "$tail" | grep -qF 'Create a plan?'; then
    if printf '%s' "$tail" | grep -qFe 'shift + tab use Plan mode' -e 'esc dismiss'; then
      printf 'plan-prompt\n'
      return 0
    fi
  fi

  printf 'none\n'
  return 0
}

# keys_for_kind <kind>
#   Prints the literal key sequence to send via tmux send-keys for the
#   given dismissal kind. The classifier returns symbolic kinds; the
#   caller routes through this helper so the mapping lives in one place
#   and can be unit-tested by sourcing this file.
keys_for_kind() {
  case "$1" in
    trust-dir)      printf '1\r' ;;
    external-agent) printf '3\r' ;;
    plan-prompt)    printf '\r' ;;
    *)              return 1 ;;
  esac
}

# ---------- dismissed-recently cache (SI-12, sourceable) -----------------
#
# DISMISSED_AT — associative array keyed by "<pane>:<kind>", values are
# unix epoch seconds of the last successful dispatch. In-memory only;
# cleared on daemon restart. Declared with `-gA` so it survives whether
# the file is sourced (test harness) or executed (daemon).
declare -gA DISMISSED_AT 2>/dev/null || declare -A DISMISSED_AT

# DISMISS_COOLDOWN_SECONDS — read from CODEX_FLEET_DISMISS_COOLDOWN_SECONDS
# (default 30). Reread on each `should_dispatch_dismissal` call so tests
# can mutate the env var between calls without re-sourcing.
_dismiss_cooldown_seconds() {
  local v="${CODEX_FLEET_DISMISS_COOLDOWN_SECONDS:-30}"
  # Validate: must be a non-negative integer. Anything else falls back to
  # the default to avoid arithmetic errors in `should_dispatch_dismissal`.
  case "$v" in
    ''|*[!0-9]*) printf '30\n' ;;
    *)           printf '%s\n' "$v" ;;
  esac
}

# should_dispatch_dismissal <pane> <kind>
#   Exit 0 if the caller is allowed to dispatch keys for (pane, kind);
#   exit 1 if the dispatch must be suppressed because a previous dispatch
#   for the same (pane, kind) is still within the cooldown window.
#   Stateless from the caller's view: pure read against DISMISSED_AT.
should_dispatch_dismissal() {
  local pane="$1" kind="$2"
  local key="${pane}:${kind}"
  local prev="${DISMISSED_AT[$key]:-}"
  if [ -z "$prev" ]; then
    return 0
  fi
  local cooldown now
  cooldown="$(_dismiss_cooldown_seconds)"
  if [ "$cooldown" -le 0 ]; then
    return 0
  fi
  now="$(date -u +%s)"
  if [ $(( now - prev )) -lt "$cooldown" ]; then
    return 1
  fi
  return 0
}

# record_dismissal <pane> <kind> [<ts>]
#   Stamp DISMISSED_AT[pane:kind] with `ts` (defaults to now). Tests pass
#   an explicit ts to simulate older entries deterministically.
record_dismissal() {
  local pane="$1" kind="$2" ts="${3:-}"
  if [ -z "$ts" ]; then
    ts="$(date -u +%s)"
  fi
  DISMISSED_AT["${pane}:${kind}"]="$ts"
}

# Stop here if we were sourced (test harness path).
if [ "$__stall_watcher_sourced" = "1" ]; then
  return 0 2>/dev/null || true
fi

# ---------- daemon ---------------------------------------------------------

OLDER_THAN="${STALL_WATCHER_OLDER_THAN:-30m}"
INTERVAL="${STALL_WATCHER_INTERVAL:-60}"
PROMPT_INTERVAL="${STALL_WATCHER_PROMPT_INTERVAL:-5}"
# Per-fleet state dir — full-bringup.sh exports FLEET_STATE_DIR scoped to
# /tmp/claude-viz/fleet-<id> when --fleet-id is set; defaults to
# /tmp/claude-viz for single-fleet back-compat.
FLEET_STATE_DIR="${FLEET_STATE_DIR:-/tmp/claude-viz}"
QUEUE_FILE="${STALL_WATCHER_QUEUE:-$FLEET_STATE_DIR/supervisor-queue.jsonl}"
LOG_FILE="${STALL_WATCHER_LOG:-$FLEET_STATE_DIR/stall-watcher.log}"
NOTIFY="${STALL_WATCHER_NOTIFY:-1}"
TMUX_SESSION="${STALL_WATCHER_SESSION:-codex-fleet}"
TMUX_WINDOW="${STALL_WATCHER_WINDOW:-1}"
ONCE=0
APPLY_FLAG="--apply"
MODE="both"  # both | prompts | rescue

while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --dry-run) APPLY_FLAG="--dry-run"; shift ;;
    --older-than) OLDER_THAN="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --prompt-interval) PROMPT_INTERVAL="$2"; shift 2 ;;
    --prompts-only) MODE="prompts"; shift ;;
    --rescue-only) MODE="rescue"; shift ;;
    -h|--help) sed -n '1,60p' "$0"; exit 0 ;;
    *) echo "fatal: unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$QUEUE_FILE")" "$(dirname "$LOG_FILE")"
touch "$QUEUE_FILE" "$LOG_FILE"

log() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s [stall-watcher] %s\n' "$ts" "$*" | tee -a "$LOG_FILE" >&2
}

# ndjson_log <kind> <pane> <keys>
#   Append a single NDJSON line capturing one dismissal event. We do this
#   on EVERY dismissal regardless of whether the Colony post succeeded,
#   so the audit trail survives Colony outages.
ndjson_log() {
  local kind="$1" pane="$2" keys="$3" ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Escape backslashes and quotes in keys/pane for safe JSON embedding.
  local esc_keys esc_pane
  esc_keys="${keys//\\/\\\\}"
  esc_keys="${esc_keys//\"/\\\"}"
  esc_keys="${esc_keys//$'\r'/\\r}"
  esc_keys="${esc_keys//$'\n'/\\n}"
  esc_pane="${pane//\\/\\\\}"
  esc_pane="${esc_pane//\"/\\\"}"
  printf 'STALL-DISMISS: {"ts":"%s","pane":"%s","prompt_kind":"%s","action":"sent %s"}\n' \
    "$ts" "$esc_pane" "$kind" "$esc_keys" >>"$LOG_FILE"
}

# colony_post_dismiss <kind> <pane>
#   Best-effort: tell Colony a dismissal happened. We post against the
#   worker's currently claimed subtask if we can find one; otherwise we
#   fall back to the active plan's first available subtask. If both
#   lookups fail or `colony` is missing, we return non-zero — the caller
#   only logs that and keeps going.
colony_post_dismiss() {
  local kind="$1" pane="$2"
  if ! command -v colony >/dev/null 2>&1; then
    return 1
  fi

  local content="auto-dismiss: kind=${kind} pane=${pane}"

  # Try worker's currently claimed task first (best identifier we have).
  # The Colony CLI surface for this is intentionally indirect: there is
  # no "task by pane" query, so we look up the active plan + walk for
  # the first claimed-but-not-completed subtask. If that fails we fall
  # back to the active plan's first available subtask. Both branches are
  # best-effort and gated behind `colony plan list --json` succeeding.
  local plans_json
  if ! plans_json="$(colony plan list --json 2>/dev/null)"; then
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  local plan_slug
  plan_slug="$(printf '%s' "$plans_json" \
    | jq -r '(.plans // []) | map(select(.status == "active"))[0].slug // empty' 2>/dev/null)"
  if [ -z "$plan_slug" ]; then
    return 1
  fi

  local tasks_json
  if ! tasks_json="$(colony task plan list "$plan_slug" --json 2>/dev/null)"; then
    return 1
  fi

  local subtask_index
  subtask_index="$(printf '%s' "$tasks_json" \
    | jq -r '
        (.subtasks // .tasks // []) as $rows
        | (
            ($rows | map(select(.status == "claimed"))[0].subtask_index) //
            ($rows | map(select(.status == "available"))[0].subtask_index) //
            empty
          )
      ' 2>/dev/null)"
  if [ -z "$subtask_index" ]; then
    return 1
  fi

  colony task post \
    --plan "$plan_slug" \
    --subtask "$subtask_index" \
    --kind note \
    --content "$content" >/dev/null 2>&1
}

# discover_panes
#   Prints one pane id per line for the worker tiles in
#   codex-fleet:1.* (the overview window). Honors STALL_WATCHER_SESSION
#   and STALL_WATCHER_WINDOW overrides for non-default deployments.
discover_panes() {
  local target="${TMUX_SESSION}:${TMUX_WINDOW}"
  command tmux -L codex-fleet list-panes -t "$target" \
    -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true
}

# prompt_tick
#   One iteration of the prompt-detection loop: enumerate panes, capture
#   each, classify, and dismiss + record on match.
prompt_tick() {
  local pane tail kind keys
  while IFS= read -r pane; do
    [ -z "$pane" ] && continue
    if ! tail="$(command tmux -L codex-fleet capture-pane -t "$pane" -p 2>/dev/null)"; then
      continue
    fi
    kind="$(printf '%s' "$tail" | tail -n 10 | classify_prompt_kind)"
    if [ "$kind" = "none" ]; then
      continue
    fi
    # SI-12: suppress re-dispatch within the per-(pane,kind) cooldown
    # window. The codex-CLI capture buffer keeps the dismissed prompt
    # visible for a few seconds after a successful dismissal, which used
    # to cause us to re-inject the same keys (e.g. literal '1') as a
    # follow-up user message. Skip silently — no log, no send-keys.
    if ! should_dispatch_dismissal "$pane" "$kind"; then
      continue
    fi
    if ! keys="$(keys_for_kind "$kind")"; then
      continue
    fi
    # send-keys with -l would send literally; we WANT the \r to be
    # interpreted as Enter so we use the default (non-literal) mode and
    # pass keys as a single argument.
    if command tmux -L codex-fleet send-keys -t "$pane" "$keys" 2>/dev/null; then
      record_dismissal "$pane" "$kind"
      ndjson_log "$kind" "$pane" "$keys"
      if ! colony_post_dismiss "$kind" "$pane"; then
        # Colony post failed — we already logged via ndjson_log.
        :
      fi
      log "auto-dismiss kind=$kind pane=$pane"
    fi
  done < <(discover_panes)
}

# rescue_tick — original stranded-claim rescue logic. Kept verbatim from
# the pre-SI-2 version of this file so existing deployments keep working.
rescue_tick() {
  local out
  if ! out="$(colony rescue stranded --older-than "$OLDER_THAN" $APPLY_FLAG --json 2>>"$LOG_FILE")"; then
    log "colony rescue failed (non-zero exit)"
    return 0
  fi

  local scanned stranded_count
  if ! command -v jq >/dev/null 2>&1; then
    log "jq not on PATH; cannot parse rescue output"
    return 0
  fi
  scanned="$(printf '%s' "$out" | jq -r '.scanned // 0' 2>/dev/null || echo 0)"
  stranded_count="$(printf '%s' "$out" | jq -r '(.stranded // []) | length' 2>/dev/null || echo 0)"

  if [ "$stranded_count" -eq 0 ]; then
    log "scanned=$scanned stranded=0"
    return 0
  fi

  log "scanned=$scanned stranded=$stranded_count → rescuing"

  printf '%s' "$out" \
    | jq -c '(.stranded // [])[] | {agent, session_id, task_ids, held_claim_count, last_activity}' \
    | while IFS= read -r row; do
        local agent ts ts_min reason
        agent="$(printf '%s' "$row" | jq -r '.agent // "unknown"')"
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        ts_min="$(date -u +%Y-%m-%dT%H:%M)"
        reason="stranded ($(printf '%s' "$row" | jq -r '.held_claim_count // 0') held claims)"
        printf '{"ts":"%s","ts_min":"%s","agent":"%s","email":"","reason":"%s","action":"takeover_recommended"}\n' \
          "$ts" "$ts_min" "$agent" "$reason" >>"$QUEUE_FILE"
        log "queued takeover for agent=$agent reason=\"$reason\""
        if [ "$NOTIFY" = "1" ] && command -v notify-send >/dev/null 2>&1; then
          notify-send -t 4000 "codex-fleet: stranded claim rescued" \
            "agent=$agent — takeover queued"
        fi
      done
}

log "starting (mode=$MODE older-than=$OLDER_THAN interval=${INTERVAL}s prompt-interval=${PROMPT_INTERVAL}s dismiss-cooldown=$(_dismiss_cooldown_seconds)s apply=$APPLY_FLAG queue=$QUEUE_FILE)"

if [ "$ONCE" = "1" ]; then
  case "$MODE" in
    prompts) prompt_tick ;;
    rescue)  rescue_tick ;;
    both)    prompt_tick; rescue_tick ;;
  esac
  exit 0
fi

# Main loop: prompt-tick runs on the fast cadence; rescue-tick runs on
# the slow cadence. We compute how many prompt-ticks fit per rescue tick
# and skip rescue on intermediate iterations.
rescue_every=1
if [ "$PROMPT_INTERVAL" -gt 0 ] && [ "$INTERVAL" -gt 0 ]; then
  rescue_every=$(( INTERVAL / PROMPT_INTERVAL ))
  [ "$rescue_every" -lt 1 ] && rescue_every=1
fi
i=0
while :; do
  if [ "$MODE" != "rescue" ]; then
    prompt_tick || true
  fi
  if [ "$MODE" != "prompts" ]; then
    if [ $(( i % rescue_every )) -eq 0 ]; then
      rescue_tick || true
    fi
  fi
  i=$(( i + 1 ))
  sleep "$PROMPT_INTERVAL"
done
