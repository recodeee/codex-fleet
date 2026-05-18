#!/usr/bin/env bash
# show-fleet — one-command operator entrypoint for codex-fleet.
#
# Attaches a single kitty window to a fully-wired codex-fleet tmux session,
# ensuring all dashboard panes are running their canonical binaries (not bare
# bash) and that the per-pane health window exists. Idempotent.
#
# Flags:
#   --rebuild     force `cargo build --release --workspace` even if binaries exist
#   --no-kitty    skip launching the kitty viewer (operator already has it open)
#   -h, --help    print usage and exit 0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RBIN="$REPO_ROOT/rust/target/release"
SESSION="codex-fleet"
SOCKET="codex-fleet"

REBUILD=0
LAUNCH_KITTY=1

usage() {
  cat <<'USAGE'
Usage: show-fleet.sh [--rebuild] [--no-kitty] [-h|--help]

Attach a single kitty window to the running codex-fleet tmux session, ensuring
all dashboard windows have their canonical binaries running and the pane-health
window exists. Idempotent — safe to re-run.

Flags:
  --rebuild    force cargo build --release --workspace even if binaries exist
  --no-kitty   skip the kitty viewer launch
  -h, --help   print this usage and exit 0

Requires: a codex-fleet tmux session already up on socket "-L codex-fleet".
If not present, run scripts/codex-fleet/full-bringup.sh first.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild)  REBUILD=1; shift ;;
    --no-kitty) LAUNCH_KITTY=0; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "show-fleet: unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '[show-fleet] %s\n' "$*"; }

# 1. Detect tmux session.
if ! tmux -L "$SOCKET" has-session -t "$SESSION" 2>/dev/null; then
  echo "show-fleet: no codex-fleet tmux session on socket '$SOCKET'." >&2
  echo "  Bring the fleet up first: bash $SCRIPT_DIR/full-bringup.sh" >&2
  exit 1
fi

# 2. Build rust dashboard binaries if any are missing (or --rebuild).
REQUIRED_BINS=(fleet-state fleet-plan-tree fleet-waves fleet-watcher fleet-pane-health)
needs_build=0
if [[ "$REBUILD" -eq 1 ]]; then
  needs_build=1
else
  for b in "${REQUIRED_BINS[@]}"; do
    if [[ ! -x "$RBIN/$b" ]]; then
      needs_build=1
      break
    fi
  done
fi
if [[ "$needs_build" -eq 1 ]]; then
  log "building rust dashboards (cargo build --release --workspace)…"
  ( cd "$REPO_ROOT/rust" && cargo build --release --workspace 2>&1 | tail -5 ) || {
    echo "show-fleet: cargo build failed; see output above." >&2
    exit 1
  }
else
  log "rust dashboards already built; skipping cargo build"
fi

# 3. Walk windows 1..5 by name; respawn if still bare bash and marker not running.
respawn_if_bash() {
  local window="$1" cmd="$2" marker="$3" cur pane_pid
  cur="$(tmux -L "$SOCKET" display -t "$SESSION:$window" -p '#{pane_current_command}' 2>/dev/null || echo "")"
  if [[ "$cur" != "bash" ]]; then
    log "$window already running ($cur); skipping"
    return 0
  fi
  pane_pid="$(tmux -L "$SOCKET" display -t "$SESSION:$window" -p '#{pane_pid}' 2>/dev/null || echo "")"
  if [[ -n "$pane_pid" ]] && pgrep -f "$marker" -P "$pane_pid" >/dev/null 2>&1; then
    log "$window has $marker running under wrapper bash; skipping"
    return 0
  fi
  log "respawning $window → $cmd"
  tmux -L "$SOCKET" respawn-pane -k -t "$SESSION:$window" "$cmd"
}

respawn_if_bash fleet   "$RBIN/fleet-state"                                                 "fleet-state"
respawn_if_bash plan    "env CODEX_FLEET_PLAN_REPO_ROOT=$REPO_ROOT $RBIN/fleet-plan-tree"   "fleet-plan-tree"
respawn_if_bash waves   "$RBIN/fleet-waves"                                                 "fleet-waves"
respawn_if_bash review  "bash -c 'while true; do bash \"$SCRIPT_DIR/review-anim.sh\" || sleep 5; done'" "review-anim.sh"
respawn_if_bash watcher "$RBIN/fleet-watcher"                                               "fleet-watcher"

# 4. Ensure pane-health window exists.
if ! tmux -L "$SOCKET" list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -qx 'pane-health'; then
  log "creating pane-health window"
  tmux -L "$SOCKET" new-window -d -t "$SESSION:" -n pane-health \
    "env CODEX_FLEET_SESSION=$SESSION CODEX_FLEET_TMUX_SOCKET=$SOCKET $RBIN/fleet-pane-health"
else
  log "pane-health window already exists; skipping"
fi

# 5. Apply iOS nav strip if helper exists (parallel lane may not have landed yet).
NAV_STRIP="$SCRIPT_DIR/lib/ios-nav-strip.sh"
if [[ -f "$NAV_STRIP" ]]; then
  bash "$NAV_STRIP" "$SESSION" || true
else
  log "ios-nav-strip helper missing; skipping (lane will land separately)"
fi

# 6. Launch a single detached kitty (idempotent).
if [[ "$LAUNCH_KITTY" -eq 1 ]]; then
  if pgrep -f 'kitty.*codex-fleet · full view' >/dev/null 2>&1; then
    log "kitty window already open; skipping"
  else
    log "launching kitty viewer"
    kitty --title "codex-fleet · full view" --detach -- \
      tmux -L "$SOCKET" attach -t "$SESSION" || \
      log "kitty launch failed (non-fatal; attach manually with: tmux -L $SOCKET attach -t $SESSION)"
  fi
else
  log "--no-kitty set; skipping kitty launch"
fi

# 7. Window map.
cat <<'MAP'

codex-fleet · full view
  0 overview     17 panes (codex workers + idle-claude + spare)
  1 fleet        fleet-state    (account/quota dashboard)
  2 plan         fleet-plan-tree (active plan + sub-task progress)
  3 waves        fleet-waves    (animated wave viz)
  4 review       review-anim    (plan-review tail)
  5 watcher      fleet-watcher  (supervisor activity)
  6 pane-health  fleet-pane-health (per-pane health rows)

tmux: ctrl-b + <0..6> to jump · ctrl-b + n/p to cycle
MAP

# F1 — Dead-pane surfacing.
# tmux's `#{pane_dead}` format flag returns "1" on panes whose child process
# exited but tmux is keeping them open (remain-on-exit). They silently linger
# in the overview chrome with `Pane is dead (signal 15, …)` until the operator
# scrolls into them — observed live on the 2026-05-18 fleet runs.
#
# Emit a one-line JSON summary on stderr so it's grep-friendly. Markers under
# /tmp/claude-viz/dead-pane-firstseen/ track first-seen timestamps so we can
# alert on age >60s.
dead_panes_report() {
  local dead_total=0 dead_alert=0 now
  now=$(date +%s)
  local marker_dir="/tmp/claude-viz/dead-pane-firstseen"
  mkdir -p "$marker_dir"
  declare -a dead_panes_arr=()
  while IFS=$'\t' read -r pane_id pane_dead pane_title; do
    [ "$pane_dead" = "1" ] || continue
    dead_total=$(( dead_total + 1 ))
    dead_panes_arr+=("${pane_id}:${pane_title}")
    local marker="$marker_dir/${pane_id//[^a-zA-Z0-9_-]/_}"
    [ -f "$marker" ] || printf '%s' "$now" > "$marker"
    local first; first=$(cat "$marker" 2>/dev/null || echo "$now")
    if (( now - first > 60 )); then
      dead_alert=$(( dead_alert + 1 ))
    fi
  done < <(tmux -L "$SOCKET" list-panes -t "$SESSION" -a -F '#{pane_id}	#{pane_dead}	#{pane_title}' 2>/dev/null || true)

  local panes_csv=""
  if (( dead_total > 0 )); then
    panes_csv=$(printf '"%s",' "${dead_panes_arr[@]}")
    panes_csv="${panes_csv%,}"
  fi
  printf '{"kind":"dead-pane-report","session":"%s","dead_panes":%s,"dead_alert":%s,"panes":[%s]}\n' \
    "$SESSION" "$dead_total" "$dead_alert" "$panes_csv" >&2
  if (( dead_alert > 0 )); then
    log "ALERT: $dead_alert pane(s) dead for >60s — ${dead_panes_arr[*]}"
  fi
}
dead_panes_report
