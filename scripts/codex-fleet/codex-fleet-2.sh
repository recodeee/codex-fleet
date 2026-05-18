#!/usr/bin/env bash
#
# codex-fleet-2 — open a second fleet kitty window with its own overview +
# visualization tabs.
#
# Lets you compare a candidate plan/fleet/waves rendering against the live
# `codex-fleet` session without touching it. Spawns a sibling tmux session
# `codex-fleet-2` whose tab 0 is an 8-pane tiled overview — each pane is a
# bash shell pre-configured for a distinct reserve codex account (CODEX_HOME
# set, CODEX_GUARD_BYPASS=1 set so codex-guard.sh defers to the real codex).
# Just type `codex` in a pane to launch that agent. Remaining tabs run the
# visualization scripts (fleet/waves/review/watcher/plan). No force-claim,
# no cap-swap. Safe to start while the live fleet is running — reserve
# accounts are disjoint from codex-fleet:overview's active set.
#
# Usage:
#   bash scripts/codex-fleet/codex-fleet-2.sh                    # auto-pick newest plan
#   bash scripts/codex-fleet/codex-fleet-2.sh --plan-slug <slug> # pin a specific plan
#   bash scripts/codex-fleet/codex-fleet-2.sh --no-kitty         # tmux-only (current terminal)
#   bash scripts/codex-fleet/codex-fleet-2.sh --kill             # close the session + kitty window
#
# All windows here use the SAME on-disk scripts as the live fleet, so editing
# plan-tree-anim.sh / waves-anim-generic.sh hot-reloads on the next respawn.

set -euo pipefail

# Route every `tmux ...` call through scripts/codex-fleet/lib/_tmux.sh — when
# CODEX_FLEET_TMUX_SOCKET is set in the env (e.g. by full-bringup.sh), this
# transparently rewrites the call to `tmux -L $SOCKET ...`. Default behavior
# (env unset) is identical to the prior `tmux` binary call.
source "$(dirname "${BASH_SOURCE[0]}")/lib/_tmux.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SESSION="${CODEX_FLEET_2_SESSION:-codex-fleet-2}"
PLAN_SLUG=""
USE_KITTY=1
KILL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-slug) PLAN_SLUG="$2"; shift 2 ;;
    --session)   SESSION="$2";   shift 2 ;;
    --no-kitty)  USE_KITTY=0;    shift   ;;
    --kill)      KILL=1;         shift   ;;
    -h|--help)
      sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "fatal: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --kill: tear down the session and any kitty window that hosts it.
if (( KILL == 1 )); then
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  pkill -f "kitty --title $SESSION" 2>/dev/null || true
  echo "[codex-fleet-2] killed session=$SESSION + kitty window"
  exit 0
fi

# Newest non-empty plan if not pinned (same heuristic as full-bringup.sh).
if [[ -z "$PLAN_SLUG" ]]; then
  PLAN_SLUG="$(python3 - "$REPO" <<'PY'
import os, sys, re, glob, json
repo = sys.argv[1]
plans = glob.glob(f"{repo}/openspec/plans/*/plan.json")
def key(p):
    s = os.path.basename(os.path.dirname(p))
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})$', s)
    d = (int(m[1]), int(m[2]), int(m[3])) if m else (0, 0, 0)
    return (d, os.path.getmtime(p))
plans.sort(key=key, reverse=True)
for p in plans:
    try:
        with open(p) as fh:
            if json.load(fh).get("tasks"):
                print(os.path.basename(os.path.dirname(p))); sys.exit(0)
    except Exception:
        continue
print("")
PY
)"
fi
if [[ -z "$PLAN_SLUG" ]] || [[ ! -f "$REPO/openspec/plans/$PLAN_SLUG/plan.json" ]]; then
  echo "fatal: no plan found at $REPO/openspec/plans/$PLAN_SLUG/plan.json" >&2
  echo "       pass --plan-slug <slug> or populate openspec/plans/." >&2
  exit 2
fi

# Pin the plan for plan-tree-anim so a second running instance doesn't pick a
# different newest-plan during the window's lifetime.
PIN_DIR="${PLAN_TREE_ANIM_PIN_DIR:-/tmp/claude-viz}"
PIN_FILE="$PIN_DIR/plan-tree-pin-2.txt"
mkdir -p "$PIN_DIR"
printf '%s\n' "$REPO/openspec/plans/$PLAN_SLUG/plan.json" > "$PIN_FILE"

# Tear down any stale session first so we always start from a clean canvas.
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo "[codex-fleet-2] session=$SESSION plan=$PLAN_SLUG"

# Build the session detached so kitty can attach to a stable target.
#
# Script resolution prefers the launcher's own checkout ($REPO) so an
# in-worktree edit shows up immediately, then falls back to the primary
# checkout so dashboards that live only in user-untracked locations
# (waves-anim-generic.sh, review-board.sh, ...) still work.
FALLBACK_REPO="${CODEX_FLEET_2_FALLBACK_REPO:-${CODEX_FLEET_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
resolve_script() {
  local name="$1"
  if [[ -f "$SCRIPT_DIR/$name" ]]; then
    printf '%s\n' "$SCRIPT_DIR/$name"
  elif [[ -f "$FALLBACK_REPO/scripts/codex-fleet/$name" ]]; then
    printf '%s\n' "$FALLBACK_REPO/scripts/codex-fleet/$name"
  fi
}

add_window() {
  local win="$1" script="$2" env_prefix="${3:-}"
  local path
  path="$(resolve_script "$script")"
  if [[ -n "$path" ]]; then
    tmux new-window -d -t "$SESSION:" -n "$win" \
      "${env_prefix}bash $path"
  else
    tmux new-window -d -t "$SESSION:" -n "$win" \
      "printf '[codex-fleet-2] missing: scripts/codex-fleet/%s\n' '$script'"
    tmux set-option -w -t "$SESSION:$win" remain-on-exit on
  fi
}

# Plan-tree-anim script must exist (used by the plan window below).
PLAN_SCRIPT="$(resolve_script plan-tree-anim.sh)"
[[ -z "$PLAN_SCRIPT" ]] && { echo "fatal: plan-tree-anim.sh missing in $REPO and $FALLBACK_REPO" >&2; exit 2; }

# Tab 0: overview with 8 tiled worker panes, each pre-configured for a
# different reserve codex account (CODEX_HOME set, codex-guard.sh bypassed).
# Run `codex` in any pane to launch that agent without the
# "Recodee-instrumented … missing" warning and the stdout-not-a-terminal
# fallback. Account list is reserve-only — accounts already in use by
# codex-fleet:overview are intentionally NOT listed here to avoid CODEX_HOME
# auth conflicts.
RESERVE_ACCOUNTS=(
  admin-kollarrobert admin-mite bia-zazrifka fico-magnolia
  koncita-pipacs mesi-lebenyse recodee-mite ricsi-zazrifka
)
# Worker count is now parameterizable. Default halved from 8 → 4 to cut
# the codex-fleet-2 RSS floor by ~50% (each codex CLI holds ~200-400 MB
# of native heap that does not shrink while idle). Bump back via
# `WORKER_COUNT=8 bash codex-fleet-2.sh ...` when a heavy plan needs
# more parallel lanes; the array above caps the upper bound.
WORKER_COUNT="${WORKER_COUNT:-4}"
if (( WORKER_COUNT < 1 )); then WORKER_COUNT=1; fi
if (( WORKER_COUNT > ${#RESERVE_ACCOUNTS[@]} )); then
  WORKER_COUNT=${#RESERVE_ACCOUNTS[@]}
fi
worker_cmd_for() {
  local acct="$1"
  # Launch codex directly as the pane command (matches codex-fleet:overview's
  # pattern in scripts/codex-fleet/full-bringup.sh). codex inherits the pane's
  # TTY cleanly because we skip the bash-lc indirection. The guard wrapper
  # (codex-guard.sh) sees CODEX_GUARD_BYPASS=1 and execs the real codex.
  #
  # NODE_OPTIONS=--max-old-space-size=400 caps any Node MCP-server child the
  # codex binary spawns. codex itself is a native binary so the V8 flag
  # does not apply to its own heap, but it keeps helper Node processes
  # from growing unbounded.
  printf 'env CODEX_GUARD_BYPASS=1 NODE_OPTIONS=--max-old-space-size=400 CODEX_HOME=/tmp/codex-fleet/%s CODEX_FLEET_AGENT_NAME=codex-fleet-2-%s CODEX_FLEET_ACCOUNT=%s CODEX_FLEET_SESSION=%s codex --dangerously-bypass-approvals-and-sandbox --add-dir /home/deadpool/Documents/codex-fleet --add-dir /home/deadpool/Documents/codex-fleetui' \
    "$acct" "$acct" "$acct" "$SESSION"
}
# Force a generous virtual size so the worker splits have room before the
# kitty client attaches. tmux resizes to the client on attach anyway.
tmux new-session -d -s "$SESSION" -x 274 -y 78 -n overview \
  "$(worker_cmd_for "${RESERVE_ACCOUNTS[0]}")"
for (( i = 1; i < WORKER_COUNT; i++ )); do
  acct="${RESERVE_ACCOUNTS[$i]}"
  tmux split-window -t "$SESSION:overview" "$(worker_cmd_for "$acct")" >/dev/null 2>&1 || true
  tmux select-layout -t "$SESSION:overview" tiled >/dev/null
done

add_window fleet   fleet-state-anim.sh
# Prefer waves-anim-generic.sh (newer) when present; fall back to the
# committed waves-anim.sh otherwise.
if [[ -n "$(resolve_script waves-anim-generic.sh)" ]]; then
  add_window waves waves-anim-generic.sh "FLEET_WAVES_PLAN_SLUG=$PLAN_SLUG "
else
  add_window waves waves-anim.sh         "FLEET_WAVES_PLAN_SLUG=$PLAN_SLUG "
fi
# Prefer review-anim.sh (committed sibling of plan-anim / waves-anim) when
# present; fall back to the historical review-board.sh placeholder otherwise.
if [[ -n "$(resolve_script review-anim.sh)" ]]; then
  add_window review review-anim.sh
else
  add_window review review-board.sh
fi
add_window watcher watcher-board.sh
add_window plan    plan-tree-anim.sh "PLAN_TREE_ANIM_PIN_FILE=$PIN_FILE "

tmux set-option -w -t "$SESSION:plan"  remain-on-exit on
tmux set-option -w -t "$SESSION:waves" remain-on-exit on
tmux select-window -t "$SESSION:overview"

# Mirror the codex-fleet socket setup (scripts/codex-fleet/tmux/up.sh) so the
# secondary session has a working mouse layer. Without `mouse on` the wheel
# never enters scroll/copy-mode (no chat scroll inside codex panes) and the
# `MouseDown3Pane` binding installed by style-tabs.sh below never fires
# (no iOS right-click context menu). codex-fleet-2.sh runs on whatever socket
# the operator launches it from (default = the user's normal tmux server),
# so scope these to $SESSION instead of `-g` to avoid silently flipping
# mouse on for unrelated sessions on that server.
tmux set-option -t "$SESSION" mouse on >/dev/null 2>&1 || true
tmux set-option -t "$SESSION" history-limit 50000 >/dev/null 2>&1 || true
# The right-click popup + prefix-m / prefix-Tab / prefix-C-h bindings expand
# `${CODEX_FLEET_REPO_ROOT}` from the tmux server env at fire time. Push it
# in so display-popup's spawned bash can find pane-context-menu-chooser.sh /
# menu-action-sheet.sh / section-jump-chooser.sh / help-popup.sh.
tmux set-environment -g CODEX_FLEET_REPO_ROOT "$REPO" >/dev/null 2>&1 || true

# Apply the canonical iOS-palette tab chrome (style-tabs.sh) — the second
# session no longer ships a custom orange-tinted status. Per-session distinction
# now comes from the `#S` token rendered inside style-tabs.sh's session badge
# pill (e.g. `◖ ◆ codex-fleet-2 ◗`), so both sessions read as one fleet visual
# language and pre-iOS overrides don't shadow the global palette.
# style-tabs.sh installs the sticky MouseDown3Pane (right-click iOS menu),
# WheelUpPane / WheelDownPane (alt-screen aware scroll routing), and
# MouseDown1Status (tab click) bindings — those need `mouse on` (set above)
# to actually receive events.
if [[ -x "$SCRIPT_DIR/style-tabs.sh" ]]; then
  CODEX_FLEET_SESSION="$SESSION" bash "$SCRIPT_DIR/style-tabs.sh" >/dev/null 2>&1 || true
fi
# Source the prefix-m action sheet, prefix-Tab section jumper, and prefix-C-h
# help popup. Done after style-tabs.sh so its binding pass can't shadow these.
# Mirrors scripts/codex-fleet/tmux/up.sh step 5.
if [[ -f "$SCRIPT_DIR/tmux-bindings.conf" ]]; then
  tmux source-file "$SCRIPT_DIR/tmux-bindings.conf" >/dev/null 2>&1 || true
fi
# style-tabs.sh sets status=off in favor of the in-binary fleet-tab-strip
# header pane. codex-fleet-2 deliberately does NOT install that header pane
# (it complicated the 3×3 worker layout), so re-enable the tmux-native top
# status bar — that becomes the menubar showing the window tab labels.
tmux set-option -t "$SESSION" status on >/dev/null 2>&1 || true
tmux set-option -t "$SESSION" status-position top >/dev/null 2>&1 || true

if (( USE_KITTY == 1 )) && command -v kitty >/dev/null 2>&1; then
  # Detached kitty window so this script returns immediately.
  setsid kitty --title "$SESSION" \
    bash -lc "tmux attach -t '$SESSION'" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
  echo "[codex-fleet-2] opened kitty window (--title $SESSION)"
  echo "[codex-fleet-2] tear down: bash scripts/codex-fleet/codex-fleet-2.sh --kill"
else
  echo "[codex-fleet-2] tmux-only mode — attach manually:"
  echo "    tmux attach -t $SESSION"
fi
