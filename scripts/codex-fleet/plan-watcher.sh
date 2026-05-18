#!/usr/bin/env bash
# plan-watcher.sh — auto-prompt codex-fleet workers when Colony plans have
# unclaimed work and one or more worker panes are idle. Closes the gap
# between `colony plan publish ...` and workers actually picking up
# sub-tasks (previously required a manual tmux send-keys per pane).
#
# Architecture:
#   1. Every INTERVAL seconds, list Colony plans via `colony plan status`
#      and keep the ones with available > 0.
#   2. For each idle worker pane (detected by recent stdout — "no claimable
#      work" / "polls returned" / "stale rescue" — or no edits in N minutes),
#      pair it with one of the available plans. The pairing prefers plans
#      that don't yet have a claimed sub-task so we spread workers across
#      plans rather than piling onto one.
#   3. Send an OVERRIDE prompt that pins the worker to the next available
#      sub-task of its assigned plan. Idempotent: per-(pane, plan) cooldown
#      stored in $STATE_DIR/plan-watcher-state.tsv prevents re-prompting
#      the same worker on the same plan within COOLDOWN_SECONDS.
#
# What "idle" means here:
#   - The pane's tail (last ~20 captured lines) matches one of the
#     IDLE_PATTERNS (worker reports it has no claimable work).
#   - OR the pane has not produced new output in IDLE_AFTER_SECONDS
#     (default 120s) — a worker silently polling counts as idle.
#
# What this script does NOT do:
#   - It does not handle codex CLI auth caps — that's cap-swap-daemon.sh.
#   - It does not respawn dead panes — that's add-workers.sh + supervisor.sh.
#   - It does not decompose sequential plans into parallel sub-tasks; it
#     only fans workers across the work already available.
#
# Usage:
#   bash plan-watcher.sh --loop --interval=30
#   bash plan-watcher.sh --once                                       # one tick + exit
#   bash plan-watcher.sh --once --dry-run                              # print decisions, no send
#   CODEX_FLEET_SESSION=codex-fleet-2 bash plan-watcher.sh --loop      # second fleet

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CODEX_FLEET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SESSION="${CODEX_FLEET_SESSION:-codex-fleet}"
WINDOW="${CODEX_FLEET_OVERVIEW_WINDOW:-overview}"
FLEET_STATE_DIR="${FLEET_STATE_DIR:-/tmp/claude-viz}"
STATE_DIR="${PLAN_WATCHER_STATE_DIR:-$FLEET_STATE_DIR/plan-watcher}"
STATE_FILE="$STATE_DIR/state.tsv"
INTERVAL="${PLAN_WATCHER_INTERVAL:-30}"
COOLDOWN_SECONDS="${PLAN_WATCHER_COOLDOWN:-600}"   # 10 min — long enough for a sub-task to start
IDLE_AFTER_SECONDS="${PLAN_WATCHER_IDLE_AFTER:-120}"
DRY_RUN=0
ONCE=0

mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

while [ $# -gt 0 ]; do
  case "$1" in
    --loop) ONCE=0; shift ;;
    --once) ONCE=1; shift ;;
    --interval=*) INTERVAL="${1#*=}"; shift ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --cooldown=*) COOLDOWN_SECONDS="${1#*=}"; shift ;;
    --idle-after=*) IDLE_AFTER_SECONDS="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '1,42p' "$0"; exit 0 ;;
    *) echo "fatal: unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { printf '\033[36m[plan-watcher]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[plan-watcher]\033[0m %s\n' "$*" >&2; }
dryrun() { (( DRY_RUN == 1 )) && printf '\033[35m[plan-watcher][dry-run]\033[0m %s\n' "$*" || true; }

# ── plan-validator log sink ─────────────────────────────────────────────────
# All PLAN-VALIDATE: lines append to /tmp/plan-watcher.log so operators can
# grep them out without scraping the supervisor pane buffer. We also stream
# the line to stdout (via log) so it remains visible in `--once` runs.
PLAN_WATCHER_LOG="${PLAN_WATCHER_LOG:-/tmp/plan-watcher.log}"
plan_validate_log() {
  local line="$*"
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$line" >> "$PLAN_WATCHER_LOG" 2>/dev/null || true
  log "$line"
}

# ── plan-validator hook ─────────────────────────────────────────────────────
# Called at the top of every tick. Reads .codex-fleet/active-plan to find
# the currently-pinned plan slug, resolves the on-disk plan.json, and
# invokes scripts/codex-fleet/lib/plan-validator.sh on it. The validator is
# owned by Lane 4 and may not exist yet — when it's missing we log a
# 'skipped' marker and return 0 so the watcher keeps dispatching.
#
# Exit-code contract (matches the Lane 4 spec):
#   0 → ok (log once)
#   2 → warnings (log WARN <count> + JSON summary, continue dispatching)
#   3 → hard errors (log ERROR <count> + JSON summary, SKIP dispatch)
#   * → other (treated like an internal error; skip dispatch defensively)
#
# Returns 0 to caller when dispatch should proceed, 1 when dispatch must
# be skipped for this tick.
run_plan_validator() {
  local active_plan_file="$REPO_ROOT/.codex-fleet/active-plan"
  if [ ! -f "$active_plan_file" ]; then
    plan_validate_log "PLAN-VALIDATE: skipped (no .codex-fleet/active-plan)"
    return 0
  fi

  local slug
  slug="$(tr -d '[:space:]' < "$active_plan_file" 2>/dev/null || true)"
  if [ -z "$slug" ]; then
    plan_validate_log "PLAN-VALIDATE: skipped (empty active-plan slug)"
    return 0
  fi

  local plan_json="$REPO_ROOT/openspec/plans/$slug/plan.json"
  if [ ! -f "$plan_json" ]; then
    plan_validate_log "PLAN-VALIDATE: skipped (plan.json missing for $slug)"
    return 0
  fi

  local validator="$SCRIPT_DIR/lib/plan-validator.sh"
  if [ ! -f "$validator" ]; then
    plan_validate_log "PLAN-VALIDATE: skipped (validator missing)"
    return 0
  fi

  # Capture stdout (JSON summary) separately from exit code so we can log
  # both without losing the rc. set -e is enabled at the top of the script,
  # so we must guard the validator call so a non-zero exit doesn't abort
  # the watcher.
  #
  # F4 — Inherit --allow-waves so plans with depends_on don't fail the
  # validator at runtime. full-bringup.sh already passes --allow-waves
  # at publish time; the watcher must match. Operators can layer extra
  # flags through CODEX_FLEET_PLAN_VALIDATOR_FLAGS without losing the
  # baseline.
  local extra_flags
  # shellcheck disable=SC2206  # intentional word-split of operator-supplied flags
  extra_flags=(${CODEX_FLEET_PLAN_VALIDATOR_FLAGS:-})
  local summary rc
  set +e
  if [ -x "$validator" ]; then
    summary="$("$validator" "$plan_json" --allow-waves "${extra_flags[@]}" 2>/dev/null)"
  else
    summary="$(bash "$validator" "$plan_json" --allow-waves "${extra_flags[@]}" 2>/dev/null)"
  fi
  rc=$?
  set -e

  # Best-effort count extraction from the JSON summary. The validator
  # emits a JSON object with either "warnings"/"errors" as arrays or
  # "warning_count"/"error_count" as ints. We accept both shapes; arrays
  # collapse to their len(). Falls back to "?" on parse failure.
  # The "next line" JSON summary is also compacted to one line so it
  # stays grep-friendly in /tmp/plan-watcher.log.
  local count summary_oneline
  summary_oneline="$(printf '%s' "$summary" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read() or "{}")
    print(json.dumps(d, separators=(",",":")))
except Exception:
    pass' 2>/dev/null || true)"
  [ -z "$summary_oneline" ] && summary_oneline="$summary"

  case "$rc" in
    0)
      plan_validate_log "PLAN-VALIDATE: ok"
      return 0
      ;;
    2)
      count="$(printf '%s' "$summary" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read() or "{}")
    v=d.get("warnings", d.get("warning_count", "?"))
    print(len(v) if isinstance(v,(list,tuple)) else v)
except Exception:
    print("?")' 2>/dev/null || printf '?')"
      plan_validate_log "PLAN-VALIDATE: WARN $count"
      [ -n "$summary_oneline" ] && plan_validate_log "$summary_oneline"
      return 0
      ;;
    3)
      count="$(printf '%s' "$summary" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read() or "{}")
    v=d.get("errors", d.get("error_count", "?"))
    print(len(v) if isinstance(v,(list,tuple)) else v)
except Exception:
    print("?")' 2>/dev/null || printf '?')"
      plan_validate_log "PLAN-VALIDATE: ERROR $count"
      [ -n "$summary_oneline" ] && plan_validate_log "$summary_oneline"
      return 1
      ;;
    *)
      plan_validate_log "PLAN-VALIDATE: ERROR (validator exited $rc)"
      [ -n "$summary_oneline" ] && plan_validate_log "$summary_oneline"
      return 1
      ;;
  esac
}

# Telltale phrases the worker prints when task_ready_for_agent has no work
# for its current pin. These are the lines we see in the overview screenshot
# when a plan is exhausted or stuck behind a stale blocker.
IDLE_PATTERNS=(
  "No claimable subtask"
  "no claimable work"
  "polls returned no claimable work"
  "task_ready_for_agent reports the queue is blocked"
  "task_ready_for_agent has no claimable work"
  "task_ready_for_agent keeps returning a stale blocker"
  "repeated 60s polls"
)

# ── colony plan status parser ───────────────────────────────────────────────
# `colony plan status` prints one plan per stanza:
#   <slug>  <title>
#     tasks: A completed, B claimed, C available, D blocked
#     path:  …
# We emit TSV: slug \t completed \t claimed \t available \t blocked.
# Parsed in bash + sed because mawk (the default on Debian/Ubuntu) doesn't
# support gawk's array-capturing `match()` form.
list_plans_with_available_work() {
  local slug=""
  colony plan status 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      "  tasks:"*)
        local completed claimed available blocked
        completed="$(printf '%s' "$line" | sed -nE 's/.*[[:space:]]([0-9]+) completed.*/\1/p')"
        claimed="$(printf '%s' "$line"   | sed -nE 's/.*[[:space:]]([0-9]+) claimed.*/\1/p')"
        available="$(printf '%s' "$line" | sed -nE 's/.*[[:space:]]([0-9]+) available.*/\1/p')"
        blocked="$(printf '%s' "$line"   | sed -nE 's/.*[[:space:]]([0-9]+) blocked.*/\1/p')"
        if [ -n "$slug" ] && [ -n "$available" ] && [ "$available" -gt 0 ] 2>/dev/null; then
          printf '%s\t%s\t%s\t%s\t%s\n' "$slug" "${completed:-0}" "${claimed:-0}" "$available" "${blocked:-0}"
        fi
        slug=""
        ;;
      "  path:"*) ;;   # noise
      "")        ;;   # noise
      *)
        # The slug stanza header starts in column 0 and the slug is the
        # first whitespace-separated token. Everything that doesn't match
        # the indented `  tasks:` / `  path:` rows is treated as a header.
        case "$line" in
          [a-z0-9-]*) slug="${line%% *}" ;;
          *) ;;
        esac
        ;;
    esac
  done
}

# ── idle-worker detection ───────────────────────────────────────────────────
# Returns one pane_id per line for panes that look idle. Skips panes without an
# @panel option (uninitialised / shell) and panes whose tail does not match any
# IDLE_PATTERN. The fleet-tab-strip header pane was removed in
# codex-fleet-glass-menu-drop-tabstrip-2026-05-15, so every labelled pane is now
# eligible for idle-worker detection.
list_idle_workers() {
  tmux list-panes -t "$SESSION:$WINDOW" -F '#{pane_id}|#{@panel}' 2>/dev/null \
    | while IFS='|' read -r pid panel; do
        [ -z "$panel" ] && continue
        # Capture the last ~25 lines of the pane and grep for idle markers.
        # `tail -25` keeps the check cheap — workers print the same idle
        # status repeatedly so the signal stays in the recent window.
        tail="$(tmux capture-pane -p -t "$pid" -S -25 2>/dev/null || true)"
        for pat in "${IDLE_PATTERNS[@]}"; do
          if printf '%s\n' "$tail" | grep -qF "$pat"; then
            printf '%s|%s\n' "$pid" "$panel"
            break
          fi
        done
      done
}

# ── per-(pane, plan) cooldown ───────────────────────────────────────────────
# State file is plain TSV: pane_id \t plan_slug \t unix_ts_last_prompted.
# Avoids re-prompting the same pane on the same plan within
# COOLDOWN_SECONDS — when a sub-task starts, the worker takes a few
# minutes to spawn a worktree + build + edit + PR, and we don't want to
# stomp on that with a fresh OVERRIDE every 30s.
last_prompted() {
  local pid="$1" slug="$2"
  awk -F'\t' -v p="$pid" -v s="$slug" '$1==p && $2==s {print $3; exit}' "$STATE_FILE"
}

record_prompt() {
  local pid="$1" slug="$2" ts
  ts="$(date +%s)"
  # Strip any prior row for this (pane, plan) pair, then append the new one.
  local tmp; tmp="$(mktemp)"
  awk -F'\t' -v p="$pid" -v s="$slug" '!($1==p && $2==s)' "$STATE_FILE" > "$tmp"
  printf '%s\t%s\t%s\n' "$pid" "$slug" "$ts" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

within_cooldown() {
  local pid="$1" slug="$2" last_ts now
  last_ts="$(last_prompted "$pid" "$slug")"
  [ -z "$last_ts" ] && return 1     # never prompted → not cooling down
  now="$(date +%s)"
  (( now - last_ts < COOLDOWN_SECONDS ))
}

# ── plan-aware sub-task resolver ────────────────────────────────────────────
# `colony plan status <slug>` (singular) does NOT emit per-task rows in the
# current CLI build — it just gives a rollup. We read the on-disk plan.json
# directly to find the first available sub-task's index and its full
# context block (title / description / file_scope) for the rich prompt.
#
# Output (one line, tab-separated): index \t title.
# Empty output means "no available sub-tasks found" — caller handles fallback.
next_available_subtask() {
  local slug="$1"
  local plan_json="$REPO_ROOT/openspec/plans/$slug/plan.json"
  [ -f "$plan_json" ] || return 0
  PLAN_JSON="$plan_json" python3 - <<'PY' 2>/dev/null || true
import json, os, sys
with open(os.environ["PLAN_JSON"]) as f:
    plan = json.load(f)
for t in plan.get("tasks", []):
    if t.get("status") == "available":
        print(f"{t['subtask_index']}\t{t.get('title', '')}")
        break
PY
}

# ── build a rich OVERRIDE prompt ────────────────────────────────────────────
# Reads the plan.json on disk and includes:
#   - the plan's problem statement (truncated to 600 chars) so the worker
#     understands the WHY before reading the description
#   - the specific sub-task's title + description (truncated to 900 chars)
#   - the file_scope list so the worker knows which files to claim
#   - explicit numbered action steps (claim → worktree → edit → verify →
#     PR → task_post → mark completed)
#   - fallback instruction when the claim races and loses
#
# This is the upgrade requested in tonight's GOAL: instead of "claim sub-task
# N of plan X" boilerplate, the worker gets enough context to start
# implementing immediately without reading the plan workspace files first.
build_prompt() {
  local slug="$1" sub_idx="$2" sub_title="$3"
  local plan_json="$REPO_ROOT/openspec/plans/$slug/plan.json"

  if [ -f "$plan_json" ]; then
    PLAN_JSON="$plan_json" SLUG="$slug" SUB_IDX="$sub_idx" python3 - <<'PY' 2>/dev/null
import json, os
with open(os.environ["PLAN_JSON"]) as f:
    plan = json.load(f)
slug = os.environ["SLUG"]
try:
    sub_idx = int(os.environ["SUB_IDX"])
except ValueError:
    sub_idx = 0

# Find the sub-task by index; fall back to the first task if the index
# doesn't resolve (defensive — plan.json schema occasionally drifts).
sub = next((t for t in plan.get("tasks", []) if t.get("subtask_index") == sub_idx), None)
if sub is None and plan.get("tasks"):
    sub = plan["tasks"][0]
    sub_idx = sub.get("subtask_index", 0)

def truncate(text, limit):
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "…"

problem = truncate(plan.get("problem", ""), 600)
sub_title = (sub or {}).get("title", os.environ.get("SUB_TITLE", "")) or "(see plan workspace)"
sub_desc = truncate((sub or {}).get("description", ""), 900)
file_scope = (sub or {}).get("file_scope", [])

print(f"OVERRIDE current plan pinning. A new Colony plan has been published and you are being assigned a specific sub-task.\n")
print(f"PLAN: {plan.get('plan_slug', slug)}")
print(f"TITLE: {plan.get('title', '(untitled)')}")
print()
print(f"WHY THIS PLAN EXISTS:\n{problem}")
print()
print(f"YOUR ASSIGNMENT — sub-task {sub_idx}:")
print(f"TITLE: {sub_title}")
if sub_desc:
    print(f"\nDESCRIPTION:\n{sub_desc}")
if file_scope:
    print(f"\nFILE SCOPE (claim each via task_claim_file before editing):")
    for f in file_scope:
        print(f"  - {f}")
print()
print("ACTION STEPS:")
print(f"  1. Claim the sub-task: task_plan_claim_subtask(plan_slug=\"{slug}\", subtask_index={sub_idx}, session_id=<your-session>, agent=$CODEX_FLEET_AGENT_NAME).")
print(f"     If the claim is rejected (someone else got it first), do NOT rescue stale claims. Instead call task_ready_for_agent against any plan with available work and take that.")
print(f"  2. Start a fresh agent worktree per AGENTS.md: gx branch start \"<short-task-slug>\" \"$CODEX_FLEET_AGENT_NAME\" --new")
print(f"  3. cd into the printed worktree path. Claim each file in FILE SCOPE via task_claim_file.")
print(f"  4. Implement per the DESCRIPTION above. Keep changes inside FILE SCOPE; don't touch files outside it.")
print(f"  5. Run the narrowest meaningful verification (e.g. `cargo test -p <crate>` for Rust, `bash -n <script>` for shell). Capture the green output as completion evidence.")
print(f"  6. Finish via PR: gx branch finish --branch <your-branch> --base main --via-pr --wait-for-merge --cleanup")
print(f"  7. Post a Colony task_post on this sub-task (task id from the claim response) with: branch, PR URL, MERGED state, files changed, verification command + result.")
print(f"  8. Mark the sub-task completed via task_plan_complete_subtask.")
print()
print("If your worker pane was previously pinned to a different plan that has no claimable work, this OVERRIDE replaces that pin. Do not return to the old plan until task_ready_for_agent suggests it.")
PY
  else
    # Fallback: minimal prompt when plan.json isn't reachable (e.g. plan
    # registered in Colony but disk workspace deleted). Worker still gets
    # the claim instructions and the title; they can fetch the rest via
    # task_plan_list themselves.
    cat <<EOF
OVERRIDE current plan pinning. Claim sub-task ${sub_idx} of plan ${slug} via task_plan_claim_subtask(plan_slug="${slug}", subtask_index=${sub_idx}, agent=\$CODEX_FLEET_AGENT_NAME). Title: ${sub_title}.

The plan's on-disk workspace is not reachable from the supervisor — call task_plan_list with detail=full filtered to this plan slug for the description + file scope before starting.

Action: claim → fresh agent worktree → implement → cargo test (or narrowest verification) → gx branch finish --via-pr --wait-for-merge --cleanup → task_post evidence → mark sub-task completed. If claim is rejected, fall back to task_ready_for_agent rather than rescuing stale claims.
EOF
  fi
}

# ── idempotency check: is the OVERRIDE for THIS plan already queued? ─────────
# Codex CLI's "tab to queue message" buffer stays visible at the bottom of a
# pane until the agent finishes its current work and pulls the next message.
# If we paste another OVERRIDE while one is already queued (same plan slug),
# the pane fills with duplicate prompts and codex churns through redundant
# resubmissions. This check inspects the pane's tail for an existing
# `OVERRIDE current plan pinning. Claim sub-task <N> of plan <slug>` line
# that matches the slug we're about to send — if found, we skip.
already_queued() {
  local pane="$1" slug="$2"
  local tail
  tail="$(tmux capture-pane -p -t "$pane" -S -40 2>/dev/null || true)"
  printf '%s\n' "$tail" \
    | grep -F "OVERRIDE current plan pinning" \
    | grep -Fq "plan ${slug}"
}

# ── send a prompt to a pane via the canonical fleet pattern ─────────────────
# Behaviour:
#   1. Dedup against the pane's recent tail — if an OVERRIDE for the same
#      plan slug is already visible (queued in codex's input buffer), skip.
#      Caller passes the slug as the third arg; legacy callers can omit and
#      lose dedup.
#   2. Send Esc once to dismiss any pending input from a prior dispatch
#      (codex CLI's queue input clears on Esc). Best-effort — Esc in a
#      working pane is a no-op.
#   3. load-buffer + paste-buffer for multi-line literal paste; Enter to
#      submit. Buffer is deleted after.
send_prompt() {
  local pane="$1" prompt="$2" slug="${3:-}"
  if [ -n "$slug" ] && already_queued "$pane" "$slug"; then
    log "skip $pane: OVERRIDE for $slug already queued in pane input"
    return 0
  fi
  if (( DRY_RUN == 1 )); then
    dryrun "send-keys → $pane: $(printf '%s' "$prompt" | head -c 120)…"
    return 0
  fi
  # Clean the codex input buffer first so we don't stack duplicate
  # OVERRIDE blocks on top of each other.
  tmux send-keys -t "$pane" Escape 2>/dev/null || true
  local buf="plan-watcher-$(date +%s)-$$"
  printf '%s' "$prompt" | tmux load-buffer -b "$buf" -
  tmux paste-buffer -b "$buf" -t "$pane" -p
  tmux send-keys -t "$pane" Enter
  tmux delete-buffer -b "$buf" 2>/dev/null || true
}

# ── one iteration ───────────────────────────────────────────────────────────
tick() {
  local now; now="$(date +%s)"
  log "tick @ $(date +%H:%M:%S) — session=$SESSION"

  # Plan-validator gate: runs before dispatch. On hard errors (rc=3) we
  # skip dispatch for this tick but keep the loop going so the next tick
  # picks up any operator fix. Warnings pass through.
  if ! run_plan_validator; then
    log "plan-validator reported hard errors; skipping dispatch this tick"
    return 0
  fi

  # Snapshot live state in two reads, then iterate in-memory.
  local plans idle_workers
  plans="$(list_plans_with_available_work)"
  idle_workers="$(list_idle_workers)"

  if [ -z "$plans" ]; then
    log "no plans with available work; sleeping"
    return 0
  fi
  if [ -z "$idle_workers" ]; then
    log "no idle workers; sleeping"
    return 0
  fi

  # Convert to arrays.
  local -a plan_lines worker_lines
  mapfile -t plan_lines <<<"$plans"
  mapfile -t worker_lines <<<"$idle_workers"

  log "candidates: ${#plan_lines[@]} plan(s) with available work, ${#worker_lines[@]} idle worker(s)"

  # Round-robin: walk workers, assign each to the plan with the most
  # available + the fewest already-claimed slots (best fanning candidate).
  # Cooldown skips already-prompted (pane, plan) pairs.
  local plan_idx=0
  for w in "${worker_lines[@]}"; do
    local pid panel
    pid="${w%%|*}"
    panel="${w#*|}"

    local assigned=""
    local tries=0
    while (( tries < ${#plan_lines[@]} )); do
      local plan_line="${plan_lines[$plan_idx]}"
      local slug="${plan_line%%	*}"
      if ! within_cooldown "$pid" "$slug"; then
        assigned="$plan_line"
        break
      fi
      plan_idx=$(( (plan_idx + 1) % ${#plan_lines[@]} ))
      tries=$((tries + 1))
    done

    if [ -z "$assigned" ]; then
      log "skip $panel ($pid): all available plans cooling down for this pane"
      continue
    fi

    local slug; slug="${assigned%%	*}"
    # next_available_subtask reads the on-disk plan.json (the singular
    # `colony plan status <slug>` CLI doesn't emit per-task rows). Output
    # is tab-separated: index \t title. Empty means no available sub-task
    # found — caller defaults to sub-0 + a placeholder title and lets the
    # rich prompt's plan.json read fill in the rest.
    local sub_row; sub_row="$(next_available_subtask "$slug")"
    local sub_idx sub_title
    if [ -n "$sub_row" ]; then
      sub_idx="${sub_row%%	*}"
      sub_title="${sub_row#*	}"
    else
      sub_idx="0"
      sub_title="(see plan ${slug})"
    fi
    [ -z "$sub_title" ] && sub_title="(see plan ${slug})"

    log "→ prompt $panel ($pid) with $slug / sub-${sub_idx}: ${sub_title:0:60}"
    send_prompt "$pid" "$(build_prompt "$slug" "$sub_idx" "$sub_title")" "$slug"
    record_prompt "$pid" "$slug"

    # Move to next plan so back-to-back workers spread across plans.
    plan_idx=$(( (plan_idx + 1) % ${#plan_lines[@]} ))
  done
}

# ── main ────────────────────────────────────────────────────────────────────
if (( ONCE == 1 )); then
  tick
  exit 0
fi

log "starting loop (interval=${INTERVAL}s, cooldown=${COOLDOWN_SECONDS}s, session=$SESSION)"
while :; do
  tick || warn "tick failed; continuing"
  sleep "$INTERVAL"
done
