#!/usr/bin/env bash
# codex-first-launch-supervisor — auto-drain Codex's first-launch interactive
# prompts so worker panes reach the input prompt without human clicks.
#
# Bringup creates per-account CODEX_HOMEs under /tmp/codex-fleet/<account>.
# On first Codex CLI launch in a fresh home, three prompts block the worker:
#
#   1. "Do you trust the contents of this directory?"  (Yes already highlighted → Enter)
#   2. "External agent config detected" / "Proceed with selected"  (key `1`)
#   3. "Press enter to continue"  (Enter)
#
# This script polls each worker pane, matches the prompt regex, and sends the
# right tmux key. Idempotent; safe to run multiple times. Designed to be
# invoked at the tail of full-bringup.sh (gated by CODEX_FLEET_AUTO_BYPASS=1
# default) before the DONE banner — see F7 in
# openspec/plans/fleet-dispatch-fixes-2026-05-18/plan.json.
#
# Usage:
#   bash scripts/codex-fleet/codex-first-launch-supervisor.sh <session> <pane-count>
#
# Env knobs:
#   TMUX_SOCKET                 — tmux -L socket name (default: codex-fleet)
#   CODEX_FLEET_BYPASS_ROUNDS   — max drain rounds per pane (default: 10)
#   CODEX_FLEET_BYPASS_INTERVAL — sleep between rounds in seconds (default: 1.5)

set -euo pipefail

SESSION="${1:-codex-fleet}"
PANES="${2:-8}"
SOCKET="${TMUX_SOCKET:-codex-fleet}"
ROUNDS="${CODEX_FLEET_BYPASS_ROUNDS:-10}"
INTERVAL="${CODEX_FLEET_BYPASS_INTERVAL:-1.5}"

tmx() { tmux -L "$SOCKET" "$@"; }
log() { printf '[first-launch-supervisor] %s\n' "$*" >&2; }

drain_pane() {
  local pane="$1"
  local rounds=0
  local advanced=0
  while (( rounds < ROUNDS )); do
    local snap; snap="$(tmx capture-pane -p -t "$pane" -S -25 2>/dev/null || true)"
    [ -z "$snap" ] && return 0
    if printf '%s' "$snap" | grep -qE 'Do you trust the contents'; then
      tmx send-keys -t "$pane" Enter 2>/dev/null || true
      advanced=1
      sleep "$INTERVAL"
    elif printf '%s' "$snap" | grep -qE 'External agent config detected|Proceed with selected'; then
      tmx send-keys -t "$pane" "1" 2>/dev/null || true
      advanced=1
      sleep "$INTERVAL"
    elif printf '%s' "$snap" | grep -qE 'Press enter to continue[[:space:]]*$'; then
      tmx send-keys -t "$pane" Enter 2>/dev/null || true
      advanced=1
      sleep "$INTERVAL"
    else
      # No matched prompt → worker is at idle prompt or already past first-launch
      if (( advanced )); then
        log "$pane drained after $rounds round(s)"
      fi
      return 0
    fi
    rounds=$(( rounds + 1 ))
  done
  log "WARN: $pane did not drain after $ROUNDS rounds"
}

if ! tmx has-session -t "$SESSION" 2>/dev/null; then
  log "session $SESSION not present on socket $SOCKET; nothing to drain"
  exit 0
fi

log "draining first-launch prompts on $SESSION (panes=$PANES)"
for p in $(seq 1 "$PANES"); do
  drain_pane "${SESSION}:overview.${p}" &
done
wait
log "done."
