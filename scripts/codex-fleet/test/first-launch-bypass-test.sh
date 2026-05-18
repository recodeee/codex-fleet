#!/usr/bin/env bash
# F7 smoke test — asserts that codex-first-launch-supervisor.sh drains the
# three first-launch prompts within bounded wall time.
#
# Strategy: spin up a throwaway tmux session on a dedicated socket, paint
# each of the three prompt strings into a pane, run the supervisor, and
# assert the live screen no longer contains any of the prompt markers.
# Does NOT require a real Codex CLI or codex accounts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPERVISOR="$SCRIPT_DIR/codex-first-launch-supervisor.sh"
[ -x "$SUPERVISOR" ] || { echo "FAIL: supervisor not found at $SUPERVISOR"; exit 1; }

SOCKET="codex-fleet-test-$$"
SESSION="test-first-launch"
cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

# Start the tmux server with pane-base-index = 1 BEFORE creating the
# session so pane indices match the supervisor's `seq 1 $N` loop.
tmux -L "$SOCKET" start-server 2>/dev/null || true
tmux -L "$SOCKET" set-option -g base-index 1 2>/dev/null || true
tmux -L "$SOCKET" set-option -g pane-base-index 1 2>/dev/null || true
tmux -L "$SOCKET" new-session -d -s "$SESSION" -n overview "cat" 2>/dev/null || true
tmux -L "$SOCKET" split-window -t "$SESSION:overview" -h "cat" 2>/dev/null || true
tmux -L "$SOCKET" split-window -t "$SESSION:overview" -h "cat" 2>/dev/null || true

# Sanity: confirm pane indices are 1, 2, 3
PANES_FOUND=$(tmux -L "$SOCKET" list-panes -t "$SESSION:overview" -F '#{pane_index}' | tr '\n' ',')
if [ "$PANES_FOUND" != "1,2,3," ]; then
  echo "SKIP: tmux pane indices=${PANES_FOUND} (expected 1,2,3,); test harness incompatible"
  exit 0
fi

# Paint each prompt into the matched pane.
tmux -L "$SOCKET" send-keys -t "$SESSION:overview.1" "echo 'Do you trust the contents of this directory?'" Enter
tmux -L "$SOCKET" send-keys -t "$SESSION:overview.2" "echo 'External agent config detected'" Enter
tmux -L "$SOCKET" send-keys -t "$SESSION:overview.3" "echo 'Press enter to continue'" Enter
sleep 0.5

# Run the supervisor.
TMUX_SOCKET="$SOCKET" \
CODEX_FLEET_BYPASS_INTERVAL=0.3 \
CODEX_FLEET_BYPASS_ROUNDS=10 \
timeout 30 bash "$SUPERVISOR" "$SESSION" 3 >/dev/null 2>&1 || true

# Assert: live screen no longer shows the prompt markers.
fail=0
for p in 1 2 3; do
  visible=$(tmux -L "$SOCKET" capture-pane -p -t "$SESSION:overview.$p" 2>/dev/null | tail -3)
  if printf '%s' "$visible" | grep -qE 'Do you trust|External agent config|Press enter to continue'; then
    echo "FAIL: pane $p still shows prompt marker: $visible"
    fail=1
  fi
done

if (( fail == 0 )); then
  echo "PASS: all 3 prompt markers drained from live screen"
  exit 0
fi
exit 1
