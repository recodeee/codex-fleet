#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-worker-standby.sh — SI-14 smoke test for the hard-standby short-circuit
# in scripts/codex-fleet/claude-worker.sh.
#
# Sources claude-worker.sh with CLAUDE_WORKER_LOOP_SOURCE_ONLY=1 so the
# helpers (worker_standby_active, worker_loop_iter, run_once) are defined
# without dropping into the live while(true). We then redefine run_once to
# a mock that records every invocation to a marker file — this stands in
# for the Colony poll that the wake-prompt would normally do via the
# claude CLI session.
#
# Scenarios:
#   1. CODEX_FLEET_WORKER_MODE=standby → worker_loop_iter returns 101 and
#      the mock run_once is NEVER called (no Colony poll happens in
#      standby). The 12s subshell timeout is a belt-and-braces guard
#      against an accidental infinite poll.
#   2. CODEX_FLEET_WORKER_MODE unset → worker_loop_iter calls run_once at
#      least once (the mock records a call) and returns 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKER_SH="$FLEET_DIR/claude-worker.sh"

[ -f "$WORKER_SH" ] || { echo "FAIL: $WORKER_SH not found" >&2; exit 1; }

TMP="$(mktemp -d -t si14-standby-XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT

CALLS_FILE="$TMP/test-colony-calls"
LOG_DIR_FIXTURE="$TMP/logs"
mkdir -p "$LOG_DIR_FIXTURE"
# claude-worker.sh constructs LOG_FILE as "$LOG_DIR/claude-worker-$AGENT.log"
# from CLAUDE_FLEET_LOG_DIR + CLAUDE_FLEET_AGENT_NAME, so we mirror that here.
LOG_FILE_FIXTURE="$LOG_DIR_FIXTURE/claude-worker-test-pane.log"
STOP_FILE_FIXTURE="$TMP/worker.stop"
: > "$CALLS_FILE"

PASS=0
FAIL=0

fail() {
  printf 'FAIL %s\n' "$1" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  printf 'PASS %s\n' "$1"
  PASS=$((PASS + 1))
}

# Drive a single worker_loop_iter call in a subshell with a hard wall-clock
# guard. The subshell sources claude-worker.sh in loop-source-only mode,
# redefines run_once as a mock that appends to $CALLS_FILE, then invokes
# worker_loop_iter once and prints its return code.
#
# Args:
#   $1  STANDBY env value to set ("standby", "active", or "" for unset)
#   $2  expected rc from worker_loop_iter
run_iter() {
  local mode="$1" expected_rc="$2" label="$3"
  local out rc
  out="$(
    CLAUDE_WORKER_LOOP_SOURCE_ONLY=1 \
    CLAUDE_FLEET_AGENT_NAME=test-pane \
    CLAUDE_FLEET_LOG_DIR="$LOG_DIR_FIXTURE" \
    CODEX_FLEET_WORKER_CWD="$TMP" \
    STOP_FILE="$STOP_FILE_FIXTURE" \
    CALLS_FILE="$CALLS_FILE" \
    LOG_FILE_FIXTURE="$LOG_FILE_FIXTURE" \
    CODEX_FLEET_WORKER_MODE="$mode" \
    timeout 12 bash -c "
      set -u
      # shellcheck disable=SC1090
      source '$WORKER_SH'
      # Mock the Colony-bound side of the iteration. The real run_once
      # spawns the claude CLI which then calls task_ready_for_agent. In
      # standby mode worker_loop_iter must return BEFORE this mock fires.
      run_once() {
        printf 'colony-call ts=%s mode=%s\\n' \"\$(date +%s)\" \"\${CODEX_FLEET_WORKER_MODE:-}\" \\
          >> \"\$CALLS_FILE\"
        return 0
      }
      worker_loop_iter
      echo \"rc=\$?\"
    " 2>&1
  )" || true
  rc="$(printf '%s\n' "$out" | sed -n 's/^rc=\([0-9][0-9]*\)$/\1/p' | tail -n1)"
  if [ "$rc" = "$expected_rc" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label (expected rc=$expected_rc, got rc='$rc', out=$out)"
  fi
}

# Scenario 1: standby short-circuits BEFORE run_once.
: > "$CALLS_FILE"
run_iter "standby" 101 "1 standby returns 101"
calls_after_standby="$(wc -l < "$CALLS_FILE" | tr -d ' ')"
if [ "$calls_after_standby" = "0" ]; then
  pass "1 standby made zero colony calls"
else
  fail "1 standby leaked $calls_after_standby colony call(s); CALLS_FILE=$(cat "$CALLS_FILE")"
fi

# Standby log line should be present in the worker log.
if grep -q 'standby mode active' "$LOG_FILE_FIXTURE"; then
  pass "1 standby log line emitted"
else
  fail "1 standby log line missing; log=$(cat "$LOG_FILE_FIXTURE")"
fi

# Scenario 2: MODE unset → run_once fires at least once.
: > "$CALLS_FILE"
: > "$LOG_FILE_FIXTURE"
run_iter "" 0 "2 unset MODE returns 0"
calls_after_active="$(wc -l < "$CALLS_FILE" | tr -d ' ')"
if [ "$calls_after_active" -ge 1 ]; then
  pass "2 unset MODE made $calls_after_active colony call(s)"
else
  fail "2 unset MODE made zero colony calls; expected >=1"
fi

# Scenario 3: MODE=active also runs normally (parity with unset).
: > "$CALLS_FILE"
: > "$LOG_FILE_FIXTURE"
run_iter "active" 0 "3 MODE=active returns 0"
calls_after_active_explicit="$(wc -l < "$CALLS_FILE" | tr -d ' ')"
if [ "$calls_after_active_explicit" -ge 1 ]; then
  pass "3 MODE=active made $calls_after_active_explicit colony call(s)"
else
  fail "3 MODE=active made zero colony calls; expected >=1"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
