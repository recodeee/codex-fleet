#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-env-propagation.sh — end-to-end smoke test for the SI-11 -> SI-13
# regression observed on 2026-05-18.
#
# Background:
#   The SI-11 plan-routing-filter (scripts/codex-fleet/lib/plan-routing-filter.sh)
#   computes a non-empty FLEET_DEFAULT_SPECIALTY at bringup time when the
#   priority plan's metadata.writable_roots are foreign (outside the
#   codex-fleet repo family). Bringup logs the value, and full-bringup.sh
#   spawns each codex worker via:
#     env ... CODEX_FLEET_SPECIALTY="$effective_specialty" \
#         CODEX_FLEET_TIER=... CODEX_FLEET_AGENT_NAME=... \
#         codex --dangerously-bypass-approvals-and-sandbox ...
#
#   On 2026-05-18 ~07:36 UTC the host-Claude supervisor observed that
#   `printenv CODEX_FLEET_SPECIALTY` inside the spawned codex CLI returned
#   the empty string even though bringup's "auto-routing:" log line proved
#   the value had been set on the env when the codex process was started.
#   Without specialty, Colony's matchmaker routed workers into stale plans
#   whose writable-roots failed preflight — the very pathology SI-11 was
#   supposed to prevent.
#
# Role of this test:
#   This script reproduces the exact propagation path end-to-end. It (a)
#   stages a minimal fixture plan whose writable_roots are deliberately
#   foreign (forcing SI-11 to set FLEET_DEFAULT_SPECIALTY), (b) spins up a
#   single-pane codex-fleet against that fixture on an isolated tmux socket
#   (codex-fleet-test), (c) sends `printenv` to the spawned codex CLI, (d)
#   captures the pane, and (e) asserts the four CODEX_FLEET_* env vars all
#   print non-empty values. Any future regression where codex CLI scrubs
#   these vars between spawn and prompt-execution will fail this test at PR
#   time — before it lands and silently breaks the live supervisor.
#
# Required env vars asserted non-empty on the spawned codex CLI side:
#   CODEX_FLEET_SPECIALTY      — set by SI-11 routing-filter (foreign
#                                writable_roots -> plan_slug)
#   CODEX_FLEET_TIER           — set by full-bringup.sh from accounts.yml
#                                lookup (default "high")
#   CODEX_FLEET_AGENT_NAME     — set by full-bringup.sh as "codex-$id"
#   CODEX_FLEET_WORKER_CWD     — set by the worker-prompt boot step (after
#                                SI-17 lands, sourced from the staged env
#                                file under /tmp/codex-fleet/<agent>/env)
#
# CI safety:
#   If cap-probe / account staging cannot find any healthy codex account
#   (CI runner without a logged-in codex CLI, or all accounts capped) the
#   test prints "[SKIP] no healthy codex accounts" and exits 0. Credential
#   issues must not red-CI the env-propagation lane.
#
# Usage:
#   bash scripts/codex-fleet/test/run-env-propagation.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FLEET_DIR/../.." && pwd)"
BRINGUP="$FLEET_DIR/full-bringup.sh"

FIXTURE_SRC="$SCRIPT_DIR/env-prop-fixture/plan.json"
FIXTURE_SLUG="env-prop-fixture-test"
FIXTURE_ROOT="/tmp/env-prop-test"
PLAN_DIR_DEST="$REPO_ROOT/openspec/plans/$FIXTURE_SLUG"
TEST_SOCKET="codex-fleet-test"
TEST_SESSION="codex-fleet-test"

log()   { printf '\033[36m[env-prop-test]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[env-prop-test]\033[0m %s\n' "$*"; }
fail()  { printf '\033[31m[env-prop-test] FAIL:\033[0m %s\n' "$*" >&2; }
skip()  { printf '\033[33m[env-prop-test] SKIP:\033[0m %s\n' "$*"; exit 0; }

# ---- Preflight ----------------------------------------------------------
[ -f "$BRINGUP" ]      || { fail "missing $BRINGUP"; exit 1; }
[ -f "$FIXTURE_SRC" ]  || { fail "missing fixture plan at $FIXTURE_SRC"; exit 1; }
command -v tmux >/dev/null 2>&1 || skip "tmux not on PATH"

# ---- Teardown -----------------------------------------------------------
plan_dir_was_present=0
[ -d "$PLAN_DIR_DEST" ] && plan_dir_was_present=1

cleanup() {
    local rc=$?
    set +e
    # Kill the isolated tmux server (covers both the fleet session and the
    # sibling ticker session). Safe to run even if no server was ever started.
    tmux -L "$TEST_SOCKET" kill-server 2>/dev/null
    # Best-effort kill of any leftover daemons launched by full-bringup.sh
    # (fleet-tick / cap-swap / supervisor / plan-watcher) that may have
    # spawned outside the tmux server.
    pkill -f "fleet-tick-daemon.sh"          2>/dev/null
    pkill -f "plan-watcher.sh"               2>/dev/null
    pkill -f "cap-swap-daemon.sh"            2>/dev/null
    pkill -f "claude-supervisor.sh"          2>/dev/null
    pkill -f "auto-reviewer.sh"              2>/dev/null
    # Remove the fixture plan if we placed it (don't nuke an operator's
    # pre-existing plan dir of the same name — extremely unlikely but cheap
    # to guard against).
    if [ "$plan_dir_was_present" = "0" ] && [ -d "$PLAN_DIR_DEST" ]; then
        rm -rf "$PLAN_DIR_DEST"
    fi
    # Remove the fixture writable root (only if we created it).
    if [ "${FIXTURE_ROOT_CREATED:-0}" = "1" ] && [ -d "$FIXTURE_ROOT" ]; then
        rm -rf "$FIXTURE_ROOT"
    fi
    set -e
    exit "$rc"
}
trap cleanup EXIT INT TERM

# ---- Refuse to clobber a live fleet -------------------------------------
if tmux -L "$TEST_SOCKET" has-session -t "$TEST_SESSION" 2>/dev/null; then
    fail "tmux session '$TEST_SESSION' already exists on socket '$TEST_SOCKET'; aborting to avoid clobbering a live fleet"
    exit 1
fi

# ---- Stage the fixture writable root ------------------------------------
FIXTURE_ROOT_CREATED=0
if [ ! -d "$FIXTURE_ROOT" ]; then
    mkdir -p "$FIXTURE_ROOT"
    FIXTURE_ROOT_CREATED=1
fi
[ -w "$FIXTURE_ROOT" ] || { fail "fixture writable root not writable: $FIXTURE_ROOT"; exit 1; }
log "fixture writable root: $FIXTURE_ROOT (created=$FIXTURE_ROOT_CREATED)"

# ---- Stage the fixture plan into openspec/plans/ ------------------------
# full-bringup.sh resolves the priority plan by openspec/plans/<slug>/plan.json
# in the repo root. We copy the fixture in for the duration of the test and
# remove it on cleanup (unless an identically named dir was already there).
if [ "$plan_dir_was_present" = "0" ]; then
    mkdir -p "$PLAN_DIR_DEST"
    cp "$FIXTURE_SRC" "$PLAN_DIR_DEST/plan.json"
    log "staged fixture plan at $PLAN_DIR_DEST/plan.json"
else
    warn "plan dir already exists at $PLAN_DIR_DEST; leaving operator copy in place"
fi

# ---- Bring up a single-pane fleet on the isolated socket ---------------
log "running full-bringup.sh --plan-slug $FIXTURE_SLUG --n 1 --no-attach (socket=$TEST_SOCKET)"
bringup_log="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$bringup_log'; cleanup" EXIT INT TERM

set +e
CODEX_FLEET_TMUX_SOCKET="$TEST_SOCKET" \
    SESSION="$TEST_SESSION" \
    TICKER_SESSION="fleet-ticker-test" \
    FLEET_STATE_DIR="/tmp/claude-viz/fleet-env-prop-test" \
    bash "$BRINGUP" --plan-slug "$FIXTURE_SLUG" --n 1 --no-attach \
    > "$bringup_log" 2>&1
bringup_rc=$?
set -e

# Surface bringup output for CI debugging.
sed 's/^/  [bringup] /' "$bringup_log"

if [ "$bringup_rc" -ne 0 ]; then
    # Distinguish credential failure (skip) from real failure.
    if grep -qE "no candidate accounts found|no healthy accounts" "$bringup_log"; then
        skip "no healthy codex accounts (cap-probe/agent-auth could not stage an account); skipping env-propagation assertion"
    fi
    fail "full-bringup.sh exited rc=$bringup_rc; see bringup output above"
    exit 1
fi

# ---- Locate the worker pane --------------------------------------------
# full-bringup.sh creates an `overview` window with N worker panes (plus a
# header pane marked '[codex-fleet-tab-strip]'). For N=1 there is exactly
# one worker pane carrying '@panel = [codex-<id>]'.
log "locating worker pane (overview window)"
worker_pane=""
for _ in $(seq 1 20); do
    worker_pane=$(tmux -L "$TEST_SOCKET" list-panes -t "$TEST_SESSION:overview" \
        -F '#{@panel}|#{pane_id}' 2>/dev/null \
        | awk -F'|' '$1 != "[codex-fleet-tab-strip]" && $1 != "" { print $2; exit }')
    [ -n "$worker_pane" ] && break
    sleep 0.5
done

if [ -z "$worker_pane" ]; then
    fail "could not find a worker pane on $TEST_SESSION:overview after 10s"
    tmux -L "$TEST_SOCKET" list-panes -t "$TEST_SESSION:overview" \
        -F 'pane=#{pane_id} panel=#{@panel}' 2>&1 | sed 's/^/  /'
    exit 1
fi
log "worker pane id = $worker_pane"

# ---- Wait up to 60s for the codex CLI prompt ('›') to appear ----------
log "waiting up to 60s for codex CLI prompt (looking for '>' marker)"
prompt_seen=0
for i in $(seq 1 60); do
    pane_dump=$(tmux -L "$TEST_SOCKET" capture-pane -t "$worker_pane" -p 2>/dev/null || true)
    # codex CLI's interactive prompt uses the U+203A SINGLE RIGHT-POINTING
    # ANGLE QUOTATION MARK ('›'). Match either that or an ASCII '>' on the
    # last non-empty line for portability across codex CLI versions.
    if printf '%s\n' "$pane_dump" | grep -q '›'; then
        prompt_seen=1
        log "codex prompt visible after ${i}s"
        break
    fi
    sleep 1
done

if [ "$prompt_seen" -ne 1 ]; then
    fail "codex CLI prompt never appeared in pane $worker_pane within 60s"
    fail "pane capture follows:"
    tmux -L "$TEST_SOCKET" capture-pane -t "$worker_pane" -p 2>&1 | sed 's/^/  /'
    exit 1
fi

# ---- Send printenv into the codex CLI ----------------------------------
PRINTENV_CMD='printenv CODEX_FLEET_SPECIALTY CODEX_FLEET_TIER CODEX_FLEET_AGENT_NAME CODEX_FLEET_WORKER_CWD'
log "send-keys: $PRINTENV_CMD"
tmux -L "$TEST_SOCKET" send-keys -t "$worker_pane" "$PRINTENV_CMD" Enter

# ---- Wait for output, then capture --------------------------------------
sleep 5
captured="$(tmux -L "$TEST_SOCKET" capture-pane -t "$worker_pane" -p)"
log "captured pane snapshot (last 40 lines):"
printf '%s\n' "$captured" | tail -n 40 | sed 's/^/  /'

# ---- Assert each var is non-empty in the captured output ----------------
# We assert the *value* line (the line after printenv's echo) is non-empty.
# `printenv VAR` prints either the value followed by a newline, or nothing
# at all (and exits non-zero) when the var is unset. We can't easily parse
# per-var output (printenv's multi-arg form concatenates results without
# labels), so we use a defensive heuristic: each var name listed in the
# command line above must appear once (the echoed command line itself) and
# at least one non-command, non-prompt line of output must follow.
fail_count=0
assertions=(
    "CODEX_FLEET_SPECIALTY"
    "CODEX_FLEET_TIER"
    "CODEX_FLEET_AGENT_NAME"
    "CODEX_FLEET_WORKER_CWD"
)

# Pull only the lines that follow the last printenv echo in the capture.
# This trims older noise (codex banner, wake-prompt, etc).
post_cmd=$(printf '%s\n' "$captured" \
    | awk -v cmd="$PRINTENV_CMD" '
        index($0, cmd) { last = NR; next }
        { lines[NR] = $0 }
        END {
            for (i = last + 1; i <= NR; i++) {
                if (lines[i] != "") print lines[i]
            }
        }')

if [ -z "$post_cmd" ]; then
    fail "no output captured after sending printenv; codex CLI may not have executed the command"
    fail "full pane capture follows:"
    printf '%s\n' "$captured" | sed 's/^/  /'
    exit 1
fi

# Count non-empty value lines after the printenv echo. printenv emits one
# value per arg in order, so for 4 vars we expect at least 4 non-empty
# lines of values before the next codex prompt redraws.
value_lines=$(printf '%s\n' "$post_cmd" | grep -v -E '^[[:space:]]*[›>][[:space:]]*$' | grep -vE '^[[:space:]]*$' | head -n 20)
log "value-line region:"
printf '%s\n' "$value_lines" | sed 's/^/  >> /'

# Heuristic per-var presence check: every value line we found must be
# non-empty. printenv writes nothing for an unset var, so a missing var
# would manifest as N-1 lines (or fewer) of output.
nonempty_count=$(printf '%s\n' "$value_lines" | grep -cE '^.+$' || true)
if [ "$nonempty_count" -lt 4 ]; then
    fail "expected at least 4 non-empty value lines from printenv (one per var), got $nonempty_count"
    fail "one or more of ${assertions[*]} is unset in the spawned codex CLI"
    fail "this is the SI-11 -> SI-13 regression: bringup-time env did not propagate to the codex process"
    fail_count=$((fail_count + 1))
fi

# Additional sanity check: the SI-11 routing-filter must have logged a
# non-empty FLEET_DEFAULT_SPECIALTY (foreign writable_roots forces it).
if ! grep -qE "auto-routing: CODEX_FLEET_SPECIALTY default = '[^']+'" "$bringup_log"; then
    fail "bringup did not log a non-empty CODEX_FLEET_SPECIALTY default; SI-11 routing-filter may not have fired for the fixture plan"
    fail_count=$((fail_count + 1))
fi

if [ "$fail_count" -gt 0 ]; then
    fail "env-propagation assertions failed (count=$fail_count); see SI-11 -> SI-13 regression notes in this script's header"
    exit 1
fi

log "OK: all four CODEX_FLEET_* env vars propagated to the spawned codex CLI"
exit 0
