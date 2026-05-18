#!/usr/bin/env bash
#
# claude-spawn — inject N Claude Code worker panes into an existing fleet.
#
# ──────────────────────────────────────────────────────────────────────────────
# CONTRACT — cap-swap inheritance (mirrors cap-swap-daemon.sh's CONTRACT)
# ──────────────────────────────────────────────────────────────────────────────
# When cap-swap-daemon.sh hands a 429'd codex pane off to this script, every
# field below MUST round-trip via the caller's env and end up exported in the
# new worker's environment so the fallback agent resumes the SAME Colony
# claim, in the SAME worktree, against the SAME account file.
#
#   CODEX_FLEET_TASK_ID    Colony task id the swapped-out worker was holding.
#                          When set, the wake prompt injects a directive that
#                          tells the spawned Claude worker to immediately
#                          re-claim the task and resume in-place. The id is
#                          also exported into the pane env so claude-worker.sh
#                          (or any nested helper) can read it.
#
#   CODEX_HOME             Codex auth root (default ~/.codex). Inherited so a
#                          swapped pane keeps using the account file the
#                          previous worker was using until cap-swap explicitly
#                          rotates it.
#
#   ACCOUNT_EMAIL          Email of the account the previous worker held. Used
#                          as the default Colony agent label when --labels is
#                          not passed.
#
#   FLEET_ID               Optional fleet id; selects the codex-fleet-$FLEET_ID
#                          tmux session (default "codex-fleet").
#
#   CODEX_FLEET_PANE_ID    Specific tmux pane id (%N) to respawn into when
#                          cap-swap targets one pane. Refused unless the
#                          target pane's @panel matches the worker pattern
#                          below.
#
# Idempotency: re-running this script against a pane that already has a live
# claude worker is a 0-exit no-op. Detection is two-pronged:
#   1. The candidate pane's @panel label looks like [claude-*].
#   2. tmux capture-pane on the candidate shows the claude REPL banner / the
#      wrapper's "claude-worker boot" line / a known live prompt.
# If either signal is present we log "idempotent: …" and return 0 without
# respawning.
#
# @panel guard: when CODEX_FLEET_PANE_ID is passed (cap-swap targets a
# specific pane), refuse to spawn unless that pane's @panel option matches
# the expected worker-slot pattern:
#   ^\[(codex|kiro|claude|idle-claude)-
# Anything else is operator-parked or a non-worker pane; we log and exit 1.
#
# Models after `add-workers.sh` but for the Claude runtime:
#   - prefers respawning dead panes in `codex-fleet:overview`
#   - falls back to splitting the window when no dead panes are free
#   - falls back to detached `kitty` windows when no tmux session
#
# All Claude panes share the host's single `~/.claude/` auth, so this is
# the cap-fallback path (codex runs out → fill remaining slots with
# claude). Counts against the same Anthropic subscription.
#
# Usage:
#   bash scripts/codex-fleet/claude-spawn.sh                # spawn 1 (host ~/.claude)
#   bash scripts/codex-fleet/claude-spawn.sh -n 2           # spawn 2 (same subscription)
#   bash scripts/codex-fleet/claude-spawn.sh -n 4 --model opus
#   bash scripts/codex-fleet/claude-spawn.sh --labels free,team,api1
#   bash scripts/codex-fleet/claude-spawn.sh --tier medium
#   bash scripts/codex-fleet/claude-spawn.sh --dry-run -n 3
#   CODEX_FLEET_TASK_ID=tsk_abc123 CODEX_FLEET_PANE_ID=%17 \
#     bash scripts/codex-fleet/claude-spawn.sh -n 1   # cap-swap inheritance
#
# Per-pane subscription isolation (no API keys needed):
#   1. Stage one ~/.codex-fleet/claude/<name>/ per Anthropic account you
#      own, each logged in once:
#         mkdir -p ~/.codex-fleet/claude/work
#         CLAUDE_CONFIG_DIR=~/.codex-fleet/claude/work claude /login
#   2. Spawn one pane per account:
#         bash scripts/codex-fleet/claude-spawn.sh --accounts work,personal
#
# Auth precedence: --accounts (per-pane CLAUDE_CONFIG_DIR) > CLAUDE_FLEET_API_KEYS
# > host ~/.claude (every pane shares one subscription, fast cap-hit).
#
# Optional env:
#   CLAUDE_FLEET_API_KEYS    : space/comma ANTHROPIC_API_KEY values per pane.
#   CLAUDE_FLEET_PROFILE_ROOT: dir holding per-account profiles
#                              (default ~/.codex-fleet/claude).
#   CODEX_FLEET_PANE_ID      : specific tmux pane id to respawn into (cap-swap).
#   CODEX_FLEET_TASK_ID      : Colony task id to inherit (cap-swap inheritance).
#   CODEX_HOME               : Codex auth root inherited from caller.
#   ACCOUNT_EMAIL            : Caller account email; default label fallback.

set -eo pipefail

# SI-16: enforce CODEX_FLEET_AGENT_NAME at script entry, BEFORE any tmux
# operations, env staging, or pane creation. Spawning a pane that would
# self-identify as the generic 'codex' agent causes Colony's matchmaker
# to see multiple panes as one logical agent, which in turn causes
# overlapping task_ready_for_agent claims and confused handoffs (observed
# 2026-05-18 during the pt2 trading-edge run). Fail fast here so the
# operator can fix accounts.yml / the spawning daemon before any pane
# state is mutated.
if [ -z "${CODEX_FLEET_AGENT_NAME:-}" ]; then
  echo "[claude-spawn] FATAL: CODEX_FLEET_AGENT_NAME not set; refusing to spawn a pane that would identify as the generic 'codex' agent. Set it via accounts.yml or the parent process env." >&2
  exit 2
fi

# shellcheck source=lib/_tmux.sh
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/_tmux.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$SCRIPT_DIR/claude-worker.sh"
WAKE="$SCRIPT_DIR/claude-wake-prompt.md"

# REPO_ROOT is consumed by callers / future expansions; reference it once so
# static analysis does not flag the assignment as unused.
: "${REPO_ROOT:?}"

N=""
MODEL="${CLAUDE_FLEET_MODEL:-sonnet}"
TIER="${CLAUDE_FLEET_TIER:-high}"
SPECIALTY="${CLAUDE_FLEET_SPECIALTY:-}"
LABELS=""
ACCOUNTS=""
PROFILE_ROOT="${CLAUDE_FLEET_PROFILE_ROOT:-$HOME/.codex-fleet/claude}"
FLEET_ID="${FLEET_ID:-}"
TARGET="tmux"
DRY_RUN=0

# Cap-swap inheritance inputs. Defaults preserve prior behavior when unset.
CODEX_FLEET_TASK_ID="${CODEX_FLEET_TASK_ID:-}"
CODEX_FLEET_PANE_ID="${CODEX_FLEET_PANE_ID:-}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
ACCOUNT_EMAIL="${ACCOUNT_EMAIL:-}"

# @panel patterns that mark a pane as a legitimate worker slot. Anything else
# (operator-parked tabs, dashboard panes, tab-strips) is refused.
EXPECTED_PANEL_RE='^\[(codex|kiro|claude|idle-claude)-'

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--n) N="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --tier) TIER="$2"; shift 2 ;;
    --specialty) SPECIALTY="$2"; shift 2 ;;
    --labels) LABELS="$2"; shift 2 ;;
    --accounts) ACCOUNTS="$2"; shift 2 ;;
    --profile-root) PROFILE_ROOT="$2"; shift 2 ;;
    --fleet-id) FLEET_ID="$2"; shift 2 ;;
    --pane-id) CODEX_FLEET_PANE_ID="$2"; shift 2 ;;
    --task-id) CODEX_FLEET_TASK_ID="$2"; shift 2 ;;
    --kitty) TARGET="kitty"; shift ;;
    --tmux) TARGET="tmux"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '1,95p' "$0"; exit 0 ;;
    *) echo "fatal: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --accounts implies the pane count if -n wasn't given.
IFS=', ' read -r -a ACCOUNT_ARR <<<"${ACCOUNTS}"
if [ -z "$N" ]; then
  if [ "${#ACCOUNT_ARR[@]}" -gt 0 ] && [ -n "${ACCOUNT_ARR[0]}" ]; then
    N="${#ACCOUNT_ARR[@]}"
  else
    N=1
  fi
fi

# Dry-run never invokes the wrapper, so existence checks are gated on the
# real spawn path. This also lets the script self-test in CI/worktrees that
# do not yet have claude-worker.sh + claude-wake-prompt.md staged.
if [ "$DRY_RUN" = "0" ]; then
  [ -x "$WRAPPER" ] || { echo "fatal: missing $WRAPPER" >&2; exit 2; }
  [ -f "$WAKE" ]    || { echo "fatal: missing $WAKE" >&2; exit 2; }
fi

log()  { printf '\033[36m[claude-spawn]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[claude-spawn]\033[0m %s\n' "$*" >&2; }

if [ -n "$FLEET_ID" ]; then
  TMUX_SESSION="codex-fleet-$FLEET_ID"
else
  TMUX_SESSION="codex-fleet"
fi
TMUX_WINDOW="overview"

# Inheritance log (visible during cap-swap so the operator can see what was
# carried forward into the fallback worker).
if [ -n "$CODEX_FLEET_TASK_ID" ] || [ -n "$ACCOUNT_EMAIL" ] || [ -n "$CODEX_FLEET_PANE_ID" ]; then
  log "inheritance: task_id=${CODEX_FLEET_TASK_ID:-<none>} pane=${CODEX_FLEET_PANE_ID:-<auto>} email=${ACCOUNT_EMAIL:-<none>} codex_home=${CODEX_HOME}"
fi

# Build pane label and per-pane API key lists.
IFS=', ' read -r -a LABEL_ARR <<<"${LABELS}"
IFS=', ' read -r -a KEY_ARR   <<<"${CLAUDE_FLEET_API_KEYS:-}"

ALLOCATED_IDS=""
NEXT_ID_OUT=""

next_free_id() {
  # Pick the lowest unused integer suffix for claude-fleet-<id>. Combines
  # tmux-pane @panel hits with in-run allocations so consecutive calls
  # inside the same invocation hand out distinct ids. We return via the
  # NEXT_ID_OUT global (not stdout) because `$()` capture would fork a
  # subshell and lose ALLOCATED_IDS updates between iterations.
  local used
  used=$(tmux list-panes -s -t "$TMUX_SESSION" -F '#{@panel}' 2>/dev/null \
    | grep -oE 'claude-fleet-[0-9]+' \
    | grep -oE '[0-9]+$' \
    | sort -n -u || true)
  local i=1
  while :; do
    if printf '%s\n' "$used" | grep -qx "$i"; then i=$((i + 1)); continue; fi
    case " $ALLOCATED_IDS " in
      *" $i "*) i=$((i + 1)); continue ;;
    esac
    break
  done
  ALLOCATED_IDS="$ALLOCATED_IDS $i"
  NEXT_ID_OUT="$i"
}

find_dead_pane() {
  tmux list-panes -s -t "$TMUX_SESSION" -F '#{pane_id}\t#{pane_dead}\t#{@panel}' 2>/dev/null \
    | awk -F'\t' '$2 == 1 || $3 == "" || $3 ~ /^\[dead/ {print $1}'
}

# pane_panel_label — read the @panel option for a specific pane id, or empty.
pane_panel_label() {
  local pid="$1"
  tmux display-message -p -t "$pid" '#{@panel}' 2>/dev/null || true
}

# pane_is_live_claude — heuristic: pane already runs a claude worker. Used
# for idempotency. Looks at both the @panel label and a tail of capture-pane
# for the wrapper's boot banner or the claude REPL prompt.
pane_is_live_claude() {
  local pid="$1"
  local label
  label="$(pane_panel_label "$pid")"
  case "$label" in
    \[claude-*\]) ;;
    *) return 1 ;;
  esac
  local snap
  snap="$(tmux capture-pane -p -t "$pid" -S -200 2>/dev/null || true)"
  if [ -z "$snap" ]; then
    # Pane is labeled claude-* and we cannot peek; assume live (safer than
    # a double-spawn).
    return 0
  fi
  if printf '%s\n' "$snap" \
    | grep -qE 'claude-worker boot|Welcome to Claude Code|\? for shortcuts|\[claude-fleet-[0-9]+\]'
  then
    return 0
  fi
  return 1
}

# panel_matches_worker_pattern — guardrail for explicit --pane-id /
# CODEX_FLEET_PANE_ID targets. Refuses to spawn into operator-parked or
# non-worker panes.
panel_matches_worker_pattern() {
  local label="$1"
  [ -n "$label" ] || return 1
  printf '%s' "$label" | grep -qE "$EXPECTED_PANEL_RE"
}

build_pane_cmd() {
  local agent="$1" label="$2" api_key="$3" config_dir="$4"
  # The wrapper handles the loop / rate-limit backoff. We just hand it env.
  # Cap-swap inheritance: CODEX_FLEET_TASK_ID is forwarded so claude-worker.sh
  # (and the wake prompt it injects) can resume the prior Colony claim.
  # CODEX_HOME + ACCOUNT_EMAIL are forwarded so the new worker keeps the same
  # codex auth + Colony agent identity until cap-swap explicitly rotates.
  local env_str
  env_str="CLAUDE_FLEET_AGENT_NAME='$agent' CLAUDE_FLEET_ACCOUNT_LABEL='$label' CLAUDE_FLEET_TIER='$TIER' CLAUDE_FLEET_SPECIALTY='$SPECIALTY' CLAUDE_FLEET_MODEL='$MODEL'"
  env_str="$env_str CODEX_HOME='$CODEX_HOME'"
  # SI-16: also propagate the CODEX_FLEET_* family explicitly. The
  # CLAUDE_FLEET_* names above are what claude-worker.sh reads internally,
  # but downstream tooling (Colony's matchmaker, the codex CLI when it
  # gets spawned later in the loop for nested ops, the worker-prompt
  # boot step that calls `printenv CODEX_FLEET_*`) keys off the
  # CODEX_FLEET_* names. Without these explicit prefixes the codex CLI's
  # env scrubbing can wipe them between spawn and prompt execution,
  # which surfaces as workers self-identifying as the generic 'codex'
  # agent (2026-05-18 pt2 run, SI-16). The pane @panel label is the
  # canonical agent name, so we set CODEX_FLEET_AGENT_NAME to the same
  # value claude-worker.sh receives via CLAUDE_FLEET_AGENT_NAME.
  env_str="$env_str CODEX_FLEET_AGENT_NAME='$agent' CODEX_FLEET_TIER='$TIER' CODEX_FLEET_SPECIALTY='$SPECIALTY'"
  # SI-9: forward per-pane worker cwd override into the wrapper env so
  # claude-worker.sh's resolve_worker_cwd picks it up before the main loop.
  if [ -n "${CODEX_FLEET_WORKER_CWD:-}" ]; then
    env_str="$env_str CODEX_FLEET_WORKER_CWD='$CODEX_FLEET_WORKER_CWD'"
  fi
  if [ -n "$ACCOUNT_EMAIL" ]; then
    env_str="$env_str ACCOUNT_EMAIL='$ACCOUNT_EMAIL'"
  fi
  if [ -n "$CODEX_FLEET_TASK_ID" ]; then
    # Wake-prompt mechanism: claude-worker.sh reads CODEX_FLEET_TASK_ID. When
    # set, it appends a directive to the rendered wake prompt instructing the
    # spawned Claude to immediately re-claim that Colony task (via
    # mcp__colony__task_accept_handoff or task_ready_for_agent) and resume
    # in-place. The env var is preserved across restarts of the wrapper loop.
    env_str="$env_str CODEX_FLEET_TASK_ID='$CODEX_FLEET_TASK_ID'"
  fi
  if [ -n "$config_dir" ]; then
    env_str="$env_str CLAUDE_FLEET_CONFIG_DIR='$config_dir'"
  elif [ -n "$api_key" ]; then
    env_str="$env_str CLAUDE_FLEET_API_KEY='$api_key'"
  fi
  printf "env %s bash '%s'\n" "$env_str" "$WRAPPER"
}

spawn_one() {
  local idx="$1"
  local id label key acct config_dir=""
  next_free_id
  id="$NEXT_ID_OUT"
  acct="${ACCOUNT_ARR[$idx]:-}"
  # Account name wins over default label so blockers surface which login hit
  # the cap.
  if [ -n "$acct" ]; then
    label="$acct"
    config_dir="$PROFILE_ROOT/$acct"
    if [ ! -d "$config_dir" ] || { [ ! -f "$config_dir/auth.json" ] && [ ! -f "$config_dir/credentials.json" ]; }; then
      warn "account '$acct' has no login at $config_dir"
      warn "   one-time setup: CLAUDE_CONFIG_DIR=$config_dir claude /login"
      if [ "$DRY_RUN" = "0" ]; then
        return 1
      fi
    fi
  elif [ -n "${LABEL_ARR[$idx]:-}" ]; then
    label="${LABEL_ARR[$idx]}"
  elif [ -n "$ACCOUNT_EMAIL" ]; then
    # Cap-swap inheritance: fall back to the caller's account email when
    # neither --accounts nor --labels was passed.
    label="$ACCOUNT_EMAIL"
  else
    label="shared"
  fi
  key="${KEY_ARR[$idx]:-}"
  local agent="claude-fleet-$id"
  local pane_cmd
  pane_cmd="$(build_pane_cmd "$agent" "$label" "$key" "$config_dir")"

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] would spawn: agent=$agent label=$label model=$MODEL target=$TARGET task_id=${CODEX_FLEET_TASK_ID:-<none>} codex_home=$CODEX_HOME"
    return 0
  fi

  # Explicit --pane-id / CODEX_FLEET_PANE_ID path: cap-swap targets one
  # specific pane. Enforce the @panel worker pattern and idempotency before
  # respawning.
  if [ -n "$CODEX_FLEET_PANE_ID" ] && [ "$idx" = "0" ]; then
    if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
      warn "no tmux session '$TMUX_SESSION'; cannot honor --pane-id $CODEX_FLEET_PANE_ID"
      return 1
    fi
    local target_label
    target_label="$(pane_panel_label "$CODEX_FLEET_PANE_ID")"
    if ! panel_matches_worker_pattern "$target_label"; then
      warn "refusing to spawn into pane $CODEX_FLEET_PANE_ID — @panel='${target_label:-<empty>}' does not match $EXPECTED_PANEL_RE"
      return 1
    fi
    if pane_is_live_claude "$CODEX_FLEET_PANE_ID"; then
      log "idempotent: pane $CODEX_FLEET_PANE_ID already runs a live claude worker (@panel=$target_label) — skipping"
      return 0
    fi
    tmux set-option -p -t "$CODEX_FLEET_PANE_ID" '@panel' "[$agent]" >/dev/null 2>&1 || true
    tmux respawn-pane -k -t "$CODEX_FLEET_PANE_ID" "$pane_cmd" >/dev/null
    log "respawned pane $CODEX_FLEET_PANE_ID → $agent (label=$label model=$MODEL${config_dir:+ profile=$config_dir} task_id=${CODEX_FLEET_TASK_ID:-<none>})"
    return 0
  fi

  if [ "$TARGET" = "tmux" ] && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    local dead_pid
    dead_pid="$(find_dead_pane | head -1 || true)"
    if [ -n "$dead_pid" ]; then
      # Idempotency belt-and-braces: a pane returned by find_dead_pane should
      # not already host a live worker, but check anyway.
      if pane_is_live_claude "$dead_pid"; then
        log "idempotent: candidate pane $dead_pid already runs a live claude worker — skipping"
        return 0
      fi
      tmux set-option -p -t "$dead_pid" '@panel' "[$agent]" >/dev/null 2>&1 || true
      tmux respawn-pane -k -t "$dead_pid" "$pane_cmd" >/dev/null
      log "respawned dead pane $dead_pid → $agent (label=$label model=$MODEL${config_dir:+ profile=$config_dir} task_id=${CODEX_FLEET_TASK_ID:-<none>})"
      return 0
    fi
    local new_pid
    new_pid="$(tmux split-window -t "$TMUX_SESSION:$TMUX_WINDOW" -P -F '#{pane_id}' "$pane_cmd" 2>/dev/null || true)"
    if [ -n "$new_pid" ]; then
      tmux set-option -p -t "$new_pid" '@panel' "[$agent]" >/dev/null 2>&1 || true
      tmux select-layout -t "$TMUX_SESSION:$TMUX_WINDOW" tiled >/dev/null 2>&1 || true
      log "split-window $new_pid → $agent (label=$label model=$MODEL${config_dir:+ profile=$config_dir} task_id=${CODEX_FLEET_TASK_ID:-<none>})"
      return 0
    fi
    warn "tmux split failed for $agent; falling through to kitty"
  fi

  if ! command -v kitty >/dev/null 2>&1; then
    warn "no tmux session '$TMUX_SESSION' and kitty not on PATH — cannot spawn $agent"
    return 1
  fi
  kitty --title "$agent" --detach bash -lc "$pane_cmd"
  log "kitty window → $agent (label=$label model=$MODEL${config_dir:+ profile=$config_dir} task_id=${CODEX_FLEET_TASK_ID:-<none>})"
}

log "spawning $N Claude Code pane(s) (target=$TARGET model=$MODEL tier=$TIER specialty='${SPECIALTY:-<generalist>}')"
for ((i=0; i<N; i++)); do
  spawn_one "$i" || warn "spawn_one $i returned non-zero (continuing)"
done
log "done. tail logs with: tail -f /tmp/claude-viz/claude-worker-claude-fleet-*.log"
