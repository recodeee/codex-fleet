#!/usr/bin/env bash
#
# run-pr-babysitter-dry.sh — dry-run smoke test for pr-babysitter.sh.
#
# Replays each fixture under pr-babysitter-fixtures/ through the daemon's
# --dry-run path and asserts:
#   * checks-failed.json   → at least one `colony task_post --kind blocker`
#                            and one `colony task_hand_off` line emitted.
#   * checks-passing.json  → zero `DRYRUN: colony` lines emitted.
#
# Exit codes:
#   0  all assertions passed
#   1  at least one assertion failed
#   2  setup error (missing daemon / fixtures / jq)

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BABYSITTER="$FLEET_DIR/pr-babysitter.sh"
FIXTURE_DIR="$SCRIPT_DIR/pr-babysitter-fixtures"
PLAN_JSON="$FIXTURE_DIR/babysitter-test-plan/plan.json"

die() {
  printf 'run-pr-babysitter-dry: fatal: %s\n' "$*" >&2
  exit 2
}

[ -x "$BABYSITTER" ] || die "daemon not executable: $BABYSITTER"
[ -r "$FIXTURE_DIR/checks-failed.json" ] || die "missing fixture: checks-failed.json"
[ -r "$FIXTURE_DIR/checks-passing.json" ] || die "missing fixture: checks-passing.json"
[ -r "$PLAN_JSON" ] || die "missing fixture plan.json: $PLAN_JSON"
command -v jq >/dev/null 2>&1 || die "jq not on PATH"

# Use a temp state dir so the test is hermetic — counters from a previous
# run won't bleed into this one.
STATE_DIR="$(mktemp -d -t pr-babysitter-test.XXXXXX)"
trap 'rm -rf "$STATE_DIR"' EXIT
export PR_BABYSITTER_STATE_DIR="$STATE_DIR"
export FLEET_STATE_DIR="$STATE_DIR"

pass=0
fail=0

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    printf '  OK   %s contains: %s\n' "$label" "$needle"
    pass=$((pass + 1))
  else
    printf '  FAIL %s missing : %s\n' "$label" "$needle" >&2
    fail=$((fail + 1))
  fi
}

assert_absent() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    printf '  FAIL %s should not contain: %s\n' "$label" "$needle" >&2
    fail=$((fail + 1))
  else
    printf '  OK   %s absent: %s\n' "$label" "$needle"
    pass=$((pass + 1))
  fi
}

# ---------- checks-failed.json ----------
printf 'fixture: checks-failed.json\n'
failed_out="$(bash "$BABYSITTER" \
  --dry-run "$FIXTURE_DIR/checks-failed.json" \
  --dry-run-plan-json "$PLAN_JSON" 2>/dev/null || true)"

# stdout-only assertions (the DRYRUN lines are emitted on stdout).
assert_contains "checks-failed" "$failed_out" "DRYRUN: colony task_post"
assert_contains "checks-failed" "$failed_out" "--kind blocker"
assert_contains "checks-failed" "$failed_out" "DRYRUN: colony task_hand_off"
assert_contains "checks-failed" "$failed_out" "babysitter-test-plan#0"

# The passing PR in the failed-fixture (SP-1) should NOT trigger a hand-off.
# Verify by counting hand_off lines — exactly one expected (the TE-2 failure).
handoff_count="$(printf '%s' "$failed_out" | grep -c 'DRYRUN: colony task_hand_off' || true)"
if [ "$handoff_count" -eq 1 ]; then
  printf '  OK   checks-failed exactly 1 hand_off (got %d)\n' "$handoff_count"
  pass=$((pass + 1))
else
  printf '  FAIL checks-failed expected 1 hand_off, got %d\n' "$handoff_count" >&2
  fail=$((fail + 1))
fi

# ---------- checks-passing.json ----------
printf 'fixture: checks-passing.json\n'
passing_out="$(bash "$BABYSITTER" \
  --dry-run "$FIXTURE_DIR/checks-passing.json" \
  --dry-run-plan-json "$PLAN_JSON" 2>/dev/null || true)"

assert_absent  "checks-passing" "$passing_out" "DRYRUN: colony task_post"
assert_absent  "checks-passing" "$passing_out" "DRYRUN: colony task_hand_off"

# ---------- summary ----------
printf '\nsummary: %d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
