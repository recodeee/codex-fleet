#!/usr/bin/env bash
# F6 smoke test — proves the current Codex auto-submit bug and gates the fix.
#
# Strategy: spawn a single Codex worker pane, send-keys a wake prompt, then
# wait up to 90s for the worker to record any Colony claim or to mark a
# Colony task `claimed_by_session_id`. If nothing happens, the bug
# reproduces and the test exits 1. Once F6 ships the working submit key,
# the test should pass.
#
# This is an INTEGRATION test. Skips when CODEX bin is missing or when
# CODEX_FLEET_NO_INTEGRATION_TESTS=1.
set -euo pipefail

if [ "${CODEX_FLEET_NO_INTEGRATION_TESTS:-0}" = "1" ]; then
  echo "SKIP: CODEX_FLEET_NO_INTEGRATION_TESTS=1"
  exit 0
fi
if ! command -v codex >/dev/null 2>&1; then
  echo "SKIP: codex CLI not on PATH"
  exit 0
fi
if ! command -v colony >/dev/null 2>&1; then
  echo "SKIP: colony CLI not on PATH"
  exit 0
fi

SOCKET="codex-fleet-f6-test-$$"
SESSION="test-auto-submit"
cleanup() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
}
trap cleanup EXIT

# Create a 1-pane tmux session running codex against a temporary CODEX_HOME.
CODEX_HOME=$(mktemp -d -t codex-f6-XXXX)
export CODEX_HOME
tmux -L "$SOCKET" new-session -d -s "$SESSION" -n overview \
  "CODEX_HOME='$CODEX_HOME' codex" 2>/dev/null

# Drain first-launch prompts via the F7 supervisor (independent of F6).
SUPERVISOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/codex-first-launch-supervisor.sh"
TMUX_SOCKET="$SOCKET" CODEX_FLEET_BYPASS_INTERVAL=2.5 \
  bash "$SUPERVISOR" "$SESSION" 1 >/dev/null 2>&1 || true

# Send-keys a wake prompt with the candidate submit key. Today's force-claim
# uses bare Enter; F6's job is to identify the working sequence.
PROMPT="Claim the next ready Colony task via task_ready_for_agent and execute. Test ID: F6-$$"
tmux -L "$SOCKET" send-keys -t "$SESSION:overview.0" -l "$PROMPT"
tmux -L "$SOCKET" send-keys -t "$SESSION:overview.0" Enter

# Wait up to 90s for a Colony claim or worker output indicating execution.
deadline=$(( $(date +%s) + 90 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  visible=$(tmux -L "$SOCKET" capture-pane -p -t "$SESSION:overview.0" 2>/dev/null)
  # Detect either an active worker turn OR a Colony claim record.
  if printf '%s' "$visible" | grep -qE 'task_plan_claim_subtask|task_claim_file|Working \([0-9]+'; then
    echo "PASS: worker started executing (claim or work turn detected)"
    exit 0
  fi
  sleep 3
done

echo "FAIL: worker never started within 90s — F6 auto-submit bug reproduces"
echo "--- final pane visible content ---"
tmux -L "$SOCKET" capture-pane -p -t "$SESSION:overview.0" 2>/dev/null | tail -15
exit 1
