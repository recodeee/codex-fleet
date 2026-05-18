#!/usr/bin/env bash
#
# claude-worker.sh — persistent Claude Code worker wrapper for the fleet.
#
# Spawns `claude` (Claude Code CLI) with the fleet wake-prompt, in a loop
# with rate-limit-aware backoff. Mirrors codex/kiro worker behaviour:
# self-claims tasks from Colony's `task_ready_for_agent`, produces PRs
# via the Guardex `gx branch finish` flow.
#
# Quota model: ALL claude-fleet panes share the same Anthropic
# subscription on this host (`~/.claude/`). Spawn small (1–2 panes)
# unless multiple ANTHROPIC_API_KEY values are staged per pane via
# CLAUDE_FLEET_API_KEY.
#
# Required env:
#   CLAUDE_FLEET_AGENT_NAME   Colony agent id (e.g. claude-fleet-1)
#
# Optional env:
#   CLAUDE_FLEET_ACCOUNT_LABEL  Free-form tag surfaced in blocker posts
#                               (default: "shared")
#   CLAUDE_FLEET_TIER           high|medium|low (default: high)
#   CLAUDE_FLEET_SPECIALTY      comma/space-separated plan_slug prefixes
#                               (default: empty = generalist)
#   CLAUDE_FLEET_MODEL          model alias (default: sonnet)
#   CLAUDE_FLEET_CONFIG_DIR     exported as CLAUDE_CONFIG_DIR for this pane.
#                               Lets each pane use its own ~/.claude/ login
#                               (no API key needed). Default: host ~/.claude/
#                               (every pane shares one subscription).
#   CLAUDE_FLEET_API_KEY        if set, exported as ANTHROPIC_API_KEY for
#                               this pane only. Mutually exclusive with
#                               CLAUDE_FLEET_CONFIG_DIR — pick one.
#   CLAUDE_FLEET_ADD_DIRS       extra --add-dir roots (space-separated)
#   CLAUDE_FLEET_LOG_DIR        log dir (default /tmp/claude-viz)
#   RESTART_DELAY_SEC           normal exit backoff (default 30)
#   RATE_LIMIT_DELAY_SEC        429/quota backoff (default 300)
#   STOP_FILE                   touch this path to break the loop
#                               (default: $LOG_DIR/claude-worker-<id>.stop)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CODEX_FLEET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Resolve the worker's initial cwd by precedence:
#   1. CODEX_FLEET_WORKER_CWD from env (e.g. set in accounts.yml per-pane)
#   2. task.metadata.worker_cwd  (only after a task is claimed — the wake
#      prompt is responsible for cd'ing there; out of scope for this fn)
#   3. priority plan's metadata.writable_roots[0] read from
#      $REPO/.codex-fleet/active-plan-meta.json if present
#   4. fallback: $REPO (back-compat with pre-SI-9 behavior)
#
# TODO(SI-3/SI-5/SI-11): the bringup hardening PR is the right place to
# write $REPO/.codex-fleet/active-plan-meta.json from the priority plan's
# metadata. Until then case (3) is a no-op for live fleets and we fall
# through to (4) — which keeps things working exactly as before.
resolve_worker_cwd() {
  if [ -n "${CODEX_FLEET_WORKER_CWD:-}" ]; then
    if [ -d "$CODEX_FLEET_WORKER_CWD" ] && [ -w "$CODEX_FLEET_WORKER_CWD" ]; then
      echo "$CODEX_FLEET_WORKER_CWD"; return
    fi
  fi
  local meta_file="$REPO/.codex-fleet/active-plan-meta.json"
  if [ -f "$meta_file" ] && command -v jq >/dev/null 2>&1; then
    local wr
    wr=$(jq -r '.metadata.writable_roots[0] // empty' "$meta_file" 2>/dev/null)
    if [ -n "$wr" ] && [ -d "$wr" ] && [ -w "$wr" ]; then
      echo "$wr"; return
    fi
  fi
  echo "$REPO"
}

# When sourced by test/run-worker-cwd.sh we want resolve_worker_cwd
# defined but the rest of the script (env validation, banner, main loop)
# skipped. The test sets CLAUDE_WORKER_SOURCE_ONLY=1 before sourcing.
if [ "${CLAUDE_WORKER_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

AGENT="${CLAUDE_FLEET_AGENT_NAME:-}"
if [ -z "$AGENT" ]; then
  echo "[claude-worker] fatal: CLAUDE_FLEET_AGENT_NAME unset" >&2
  exit 2
fi

LABEL="${CLAUDE_FLEET_ACCOUNT_LABEL:-shared}"
TIER="${CLAUDE_FLEET_TIER:-high}"
SPECIALTY="${CLAUDE_FLEET_SPECIALTY:-}"
MODEL="${CLAUDE_FLEET_MODEL:-sonnet}"
LOG_DIR="${CLAUDE_FLEET_LOG_DIR:-/tmp/claude-viz}"
RESTART_DELAY_SEC="${RESTART_DELAY_SEC:-30}"
RATE_LIMIT_DELAY_SEC="${RATE_LIMIT_DELAY_SEC:-300}"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/claude-worker-$AGENT.log"
STOP_FILE="${STOP_FILE:-$LOG_DIR/claude-worker-$AGENT.stop}"

WAKE="$SCRIPT_DIR/claude-wake-prompt.md"
if [ ! -f "$WAKE" ]; then
  echo "[claude-worker] fatal: wake-prompt missing at $WAKE" >&2
  exit 2
fi

worker_cwd="$(resolve_worker_cwd)"
cd "$worker_cwd" || {
  echo "[claude-worker] fatal: cannot cd to resolved worker cwd: $worker_cwd" >&2
  exit 2
}

ADD_DIR_FLAGS=(
  --add-dir "/home/deadpool/Documents/recodee"
  --add-dir "/home/deadpool/Documents/codex-fleet"
  --add-dir "/tmp"
)
if [ -n "${CLAUDE_FLEET_ADD_DIRS:-}" ]; then
  for d in $CLAUDE_FLEET_ADD_DIRS; do
    ADD_DIR_FLAGS+=( --add-dir "$d" )
  done
fi

# Auth path selection. CLAUDE_FLEET_CONFIG_DIR (per-pane subscription) wins
# over CLAUDE_FLEET_API_KEY; default is host ~/.claude/.
if [ -n "${CLAUDE_FLEET_CONFIG_DIR:-}" ]; then
  mkdir -p "$CLAUDE_FLEET_CONFIG_DIR"
  export CLAUDE_CONFIG_DIR="$CLAUDE_FLEET_CONFIG_DIR"
  # Refuse to run if this config dir has no auth.json — the pane would
  # otherwise sit forever asking the user to log in.
  if [ ! -f "$CLAUDE_CONFIG_DIR/auth.json" ] && [ ! -f "$CLAUDE_CONFIG_DIR/credentials.json" ]; then
    printf '[claude-worker] fatal: CLAUDE_FLEET_CONFIG_DIR=%s has no auth — run:\n' "$CLAUDE_CONFIG_DIR" >&2
    printf '  CLAUDE_CONFIG_DIR=%s claude /login\n' "$CLAUDE_CONFIG_DIR" >&2
    exit 2
  fi
elif [ -n "${CLAUDE_FLEET_API_KEY:-}" ]; then
  export ANTHROPIC_API_KEY="$CLAUDE_FLEET_API_KEY"
fi

# Banner the operator can grep from a `tmux capture-pane`.
{
  printf '\n========== claude-worker boot ==========\n'
  printf 'agent=%s label=%s tier=%s spec=%s model=%s\n' \
    "$AGENT" "$LABEL" "$TIER" "$SPECIALTY" "$MODEL"
  printf 'wake=%s log=%s\n' "$WAKE" "$LOG_FILE"
  printf 'stop=%s (touch this to break the loop)\n' "$STOP_FILE"
  printf 'cwd=%s (resolved via CODEX_FLEET_WORKER_CWD precedence; fallback $REPO=%s)\n' \
    "$worker_cwd" "$REPO"
  printf 'add-dir: %s\n' "${ADD_DIR_FLAGS[*]}"
  printf '========================================\n\n'
} | tee -a "$LOG_FILE"

# Detect rate-limit-shaped exits in scrollback. The Claude CLI emits
# different banner shapes than codex (429 / usage limit / quota / overload).
rate_limited_in() {
  local f="$1"
  [ -f "$f" ] || return 1
  # Pull the last ~120 lines so we don't false-positive on ancient hits.
  tail -n 120 "$f" 2>/dev/null \
    | grep -qiE 'rate.?limit|usage.?limit|quota.?exceeded|429|overloaded|too many requests'
}

run_once() {
  local turn_log
  turn_log="$LOG_DIR/claude-worker-$AGENT.last-turn.log"
  : > "$turn_log"

  # The wake-prompt is fed via the positional `prompt` argument; the
  # worker then loops inside the Claude session by issuing tool calls
  # against Colony. We use the interactive mode (no --print) so the
  # agent can iterate. --dangerously-skip-permissions is required for
  # autonomous worktree edits and `gx branch finish` calls.
  env \
    CLAUDE_FLEET_AGENT_NAME="$AGENT" \
    CLAUDE_FLEET_ACCOUNT_LABEL="$LABEL" \
    CLAUDE_FLEET_TIER="$TIER" \
    CLAUDE_FLEET_SPECIALTY="$SPECIALTY" \
    claude \
      --model "$MODEL" \
      --permission-mode bypassPermissions \
      --dangerously-skip-permissions \
      "${ADD_DIR_FLAGS[@]}" \
      "$(cat "$WAKE")" \
    2>&1 | tee -a "$LOG_FILE" "$turn_log"

  rate_limited_in "$turn_log" && return 42
  return 0
}

while true; do
  if [ -f "$STOP_FILE" ]; then
    printf '[claude-worker] stop file present (%s); exiting\n' "$STOP_FILE" | tee -a "$LOG_FILE"
    exit 0
  fi

  run_once
  rc=$?

  if [ "$rc" -eq 42 ]; then
    printf '[claude-worker] rate-limit detected; sleeping %ss\n' "$RATE_LIMIT_DELAY_SEC" \
      | tee -a "$LOG_FILE"
    sleep "$RATE_LIMIT_DELAY_SEC"
  else
    printf '[claude-worker] exit rc=%s; relaunch in %ss\n' "$rc" "$RESTART_DELAY_SEC" \
      | tee -a "$LOG_FILE"
    sleep "$RESTART_DELAY_SEC"
  fi
done
