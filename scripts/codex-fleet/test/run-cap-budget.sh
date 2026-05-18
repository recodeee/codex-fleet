#!/usr/bin/env bash
# run-cap-budget.sh — smoke test for cap-budget-alerts.sh's check_threshold.
#
# Walks each fixture under cap-probe-fixtures/, materializes it into a
# fresh test cache under /tmp/claude-viz/cap-probe-cache-test/<fixture>/
# (rewriting the __PROBED_AT__ placeholder to `date +%s` so every entry
# lands inside the 5-minute rolling window), then sources cap-budget-alerts.sh
# and calls `check_threshold` against the cache. Asserts the return code
# and the presence/absence of the alert flag file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON="$SCRIPT_DIR/../cap-budget-alerts.sh"
FIXTURES="$SCRIPT_DIR/cap-probe-fixtures"
WORK="${TMPDIR:-/tmp}/cap-budget-test-$$"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK"

# Silence the production logger and steer all daemon-side state into the
# scratch workdir so a parallel real fleet's /tmp/claude-viz files are not
# clobbered.
export CAP_BUDGET_LOG="$WORK/test.log"
export CAP_BUDGET_STATE_FILE="$WORK/last-state"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  if [ -f "$CAP_BUDGET_LOG" ]; then
    printf '----- daemon log -----\n' >&2
    cat "$CAP_BUDGET_LOG" >&2
  fi
  exit 1
}

# Source the daemon under the test guard. cap-budget-alerts.sh honors
# CAP_BUDGET_TEST=1 and returns before entering its main `while; sleep`
# loop, exposing helper functions (check_threshold, count_breach, ...)
# to the test process.
export CAP_BUDGET_TEST=1
# shellcheck source=/dev/null
source "$DAEMON"

materialize_fixture() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  rm -f "$dst"/*.json 2>/dev/null || true
  local now
  now=$(date +%s)
  local f
  for f in "$src"/*.json; do
    [ -f "$f" ] || continue
    sed "s/__PROBED_AT__/$now/g" "$f" > "$dst/$(basename "$f")"
  done
}

assert_flag_absent() {
  local flag="$1" label="$2"
  if [ -f "$flag" ]; then
    fail "$label: expected flag $flag to be absent, but it exists"
  fi
}

assert_flag_present() {
  local flag="$1" label="$2"
  if [ ! -f "$flag" ]; then
    fail "$label: expected flag $flag to be present, but it is missing"
  fi
}

run_case() {
  local fixture_name="$1" expected_rc="$2" expected_flag_state="$3" label="$4"
  local fixture_src="$FIXTURES/$fixture_name"
  local cache_dir="$WORK/cap-probe-cache-test/$fixture_name"
  local flag_file="$WORK/alert.${fixture_name}.flag"
  materialize_fixture "$fixture_src" "$cache_dir"

  set +e
  check_threshold "$cache_dir" 300 0.5 "$flag_file" >/dev/null
  local rc=$?
  set -e

  if [ "$rc" -ne "$expected_rc" ]; then
    fail "$label: expected rc=$expected_rc, got rc=$rc"
  fi

  case "$expected_flag_state" in
    absent) assert_flag_absent "$flag_file" "$label" ;;
    present) assert_flag_present "$flag_file" "$label" ;;
    *) fail "unknown expected_flag_state=$expected_flag_state" ;;
  esac

  printf 'PASS %s (rc=%s flag=%s)\n' "$label" "$rc" "$expected_flag_state"
}

# Case 1: all-ok → no alert, no flag.
run_case all-ok 0 absent "all-ok returns 0 (no alert)"

# Case 2: three-out-of-six-429 → alert (3/6 >= 50% threshold), flag created.
run_case three-out-of-six-429 1 present "three-out-of-six-429 returns 1 (alert) and creates flag file"

# Case 3: transition — re-running on all-ok should clear the alert flag.
run_case all-ok 0 absent "all-ok after breach clears alert flag (transition breached->ok)"

printf '\ncap-budget tests passed\n'
