#!/usr/bin/env bash
# run-claim-race — smoke test for scripts/codex-fleet/lib/claim-fence.sh.
#
# What we verify:
#   1. Two parallel claim_fence_check invocations against the same sub-task.
#      One starts seeing status=available and KEEPS seeing it through the
#      fence (returns 0). The other sees status=available before the fence
#      but gets a "claimed_by=other" mid-window (returns 2 — raced).
#      Assertion: exactly one process exits 0.
#   2. Sub-task that is already claimed at the first read: claim_fence_check
#      returns 1 (no race window opened).
#   3. Sub-task that goes available→completed mid-window: returns 2 (race).
#
# Implementation notes:
#   We don't talk to Colony here. The CLAIM_FENCE_QUERY_OVERRIDE env var
#   lets us swap in a tiny mock script that prints "<status>\tclaimed_by"
#   for any (slug, idx). The mock reads from a tmp state file so the test
#   can flip the fixture's state between the "before" and "after" reads.
#
# Run:
#   bash scripts/codex-fleet/test/run-claim-race.sh
#
# Exits 0 on full pass; non-zero with a diagnostic on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/claim-fence.sh"
[[ -f "$LIB" ]] || { echo "FAIL: missing $LIB" >&2; exit 1; }

WORK="$(mktemp -d -t claim-race-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

STATE="$WORK/state.tsv"
MOCK="$WORK/mock-query.sh"

# Mock query script. Reads STATE_FILE (passed via env) and prints the
# stored TSV line for the requested (slug, idx). Atomic with `flock` so
# parallel readers can't see a half-written state.
cat >"$MOCK" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
slug="$1"; idx="$2"
exec 9<"$STATE_FILE"
flock -s 9
line="$(awk -F'\t' -v s="$slug" -v i="$idx" '$1==s && $2==i {print $3"\t"$4; exit}' "$STATE_FILE")"
[[ -z "$line" ]] && { echo "mock: no state for $slug/$idx" >&2; exit 3; }
printf '%s\n' "$line"
MOCK
chmod +x "$MOCK"

# Helper: write/overwrite a row "<slug>\t<idx>\t<status>\t<claimed_by>".
set_state() {
  local slug="$1" idx="$2" status="$3" claimed="$4"
  local tmp; tmp="$(mktemp -p "$WORK")"
  if [[ -f "$STATE" ]]; then
    awk -F'\t' -v s="$slug" -v i="$idx" '!($1==s && $2==i)' "$STATE" >"$tmp" || true
  fi
  printf '%s\t%s\t%s\t%s\n' "$slug" "$idx" "$status" "$claimed" >>"$tmp"
  mv "$tmp" "$STATE"
}

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Speed the fence up so the test runs in ~2s instead of ~10s. The default
# of 5 is exercised by production callers; this test only cares about
# correctness, not the absolute window size.
export CODEX_FLEET_CLAIM_FENCE_SECONDS=1
export CLAIM_FENCE_QUERY_OVERRIDE="$MOCK"
export STATE_FILE="$STATE"

# Source the fence library AFTER the env vars are set so any tooling that
# captures them at source-time picks up the right values.
# shellcheck source=../lib/claim-fence.sh
source "$LIB"

# ── case 1: simple happy-path — sub-task stays available across the fence ──
set_state plan-A 0 available ""
if ! claim_fence_check plan-A 0 2>/dev/null; then
  fail "case 1: stable available should exit 0"
fi
pass "case 1: stable available → exit 0"

# ── case 2: already claimed at first read ──
set_state plan-A 1 claimed worker-x
if claim_fence_check plan-A 1 2>/dev/null; then
  fail "case 2: already-claimed should exit non-zero"
fi
pass "case 2: already-claimed → exit non-zero (no fence window)"

# ── case 3: race — available before, claimed during fence ──
set_state plan-A 2 available ""
( sleep 0  # ensure the background race-flipper starts after the first read
  # Wait long enough for the fencer's first query to land, then flip state.
  # The fence is 1s; flipping at 0.3s reliably wins the race.
  sleep 0.3
  set_state plan-A 2 claimed worker-y
) &
FLIP_PID=$!
rc=0
claim_fence_check plan-A 2 2>/dev/null || rc=$?
wait "$FLIP_PID" 2>/dev/null || true
if [[ "$rc" == "0" ]]; then
  fail "case 3: race should produce non-zero exit (got 0)"
fi
pass "case 3: race detected → exit non-zero ($rc)"

# ── case 4: two parallel fencers, exactly one wins ──
# Both start seeing available. We arrange for the state to flip mid-window
# so one fencer's "after" read sees a claim by the other. In a real Colony
# the winning worker is the one that calls task_plan_claim_subtask first
# (the loser sees `claimed_by=winner` on its re-read). We model that by
# having the FIRST fencer to finish its sleep "win" the claim and flip
# state right before exiting — then the second fencer's re-read sees a
# stranger's claim.
set_state plan-A 3 available ""

# A "competing" fencer wrapper: on success, immediately mark the sub-task
# claimed by this agent so the other fencer detects the race on its
# second read.
race_fencer() {
  local agent="$1"
  local rc=0
  claim_fence_check plan-A 3 2>/dev/null || rc=$?
  if [[ "$rc" == "0" ]]; then
    set_state plan-A 3 claimed "$agent"
    echo "win:$agent"
  fi
  return "$rc"
}

# Run both in parallel. Stagger by a tiny amount so one fencer's
# post-sleep read happens just after the other's state-flip — that's
# the race-detection path we want to exercise.
rcA_file="$WORK/rcA"; rcB_file="$WORK/rcB"
outA_file="$WORK/outA"; outB_file="$WORK/outB"

# NOTE: race_fencer returns non-zero on the losing path; set -e is inherited
# into subshells, so we explicitly disable errexit inside each one so the
# final `echo $? >file` always runs.
( set +e; race_fencer worker-A >"$outA_file" 2>/dev/null; echo $? >"$rcA_file" ) &
PIDA=$!
sleep 0.3
( set +e; race_fencer worker-B >"$outB_file" 2>/dev/null; echo $? >"$rcB_file" ) &
PIDB=$!
wait "$PIDA" 2>/dev/null || true
wait "$PIDB" 2>/dev/null || true

rcA="$(cat "$rcA_file")"
rcB="$(cat "$rcB_file")"
outA="$(cat "$outA_file")"
outB="$(cat "$outB_file")"

winners=0
[[ "$rcA" == "0" ]] && winners=$((winners+1))
[[ "$rcB" == "0" ]] && winners=$((winners+1))

if (( winners != 1 )); then
  echo "DIAG: rcA=$rcA outA=$outA"
  echo "DIAG: rcB=$rcB outB=$outB"
  fail "case 4: exactly one fencer must win (got $winners)"
fi
pass "case 4: parallel race → exactly one winner (rcA=$rcA rcB=$rcB)"

# ── case 5: fence env override ──
# Setting CODEX_FLEET_CLAIM_FENCE_SECONDS=0 should still validate (no sleep,
# but both reads still happen). Useful for unit tests in callers.
set_state plan-A 4 available ""
CODEX_FLEET_CLAIM_FENCE_SECONDS=0
export CODEX_FLEET_CLAIM_FENCE_SECONDS
if ! claim_fence_check plan-A 4 2>/dev/null; then
  fail "case 5: fence=0 with stable state should exit 0"
fi
pass "case 5: CODEX_FLEET_CLAIM_FENCE_SECONDS=0 honored"

# ── case 6: claim_fence_check_held_by happy path ──
set_state plan-A 5 claimed agent-z
CODEX_FLEET_CLAIM_FENCE_SECONDS=1
export CODEX_FLEET_CLAIM_FENCE_SECONDS
if ! claim_fence_check_held_by plan-A 5 agent-z 2>/dev/null; then
  fail "case 6: stable claim by agent should exit 0"
fi
pass "case 6: stable claim by agent → exit 0"

# ── case 7: claim_fence_check_held_by race (claim flips to completed) ──
set_state plan-A 6 claimed agent-q
( sleep 0.3; set_state plan-A 6 completed agent-q ) &
FLIP2_PID=$!
rc=0
claim_fence_check_held_by plan-A 6 agent-q 2>/dev/null || rc=$?
wait "$FLIP2_PID" 2>/dev/null || true
if [[ "$rc" == "0" ]]; then
  fail "case 7: held-by → completed mid-window must NOT exit 0"
fi
pass "case 7: held-by race detected → exit non-zero ($rc)"

echo "all claim-fence cases passed"
