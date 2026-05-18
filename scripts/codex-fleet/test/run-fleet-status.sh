#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-fleet-status.sh — smoke-test scripts/codex-fleet/fleet-status.sh.
#
# Starts an isolated tmux fixture session on a private socket so the test
# never disturbs a live codex-fleet, runs fleet-status.sh against that
# socket, validates the top-level JSON shape via jq, and asserts the
# ms_to_compose budget. Cleans up on exit.

set -u
set -o pipefail

PROG="run-fleet-status.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/scripts/codex-fleet/fleet-status.sh"

if [ ! -x "$TARGET" ]; then
    printf '%s: %s is not executable\n' "$PROG" "$TARGET" >&2
    exit 1
fi

# Use a fixture socket + session so we never collide with the live fleet.
FIXTURE_SOCKET="test-fleet-status-$$"
FIXTURE_SESSION="test-fleet-status"

cleanup() {
    local rc=$?
    tmux -L "$FIXTURE_SOCKET" kill-server >/dev/null 2>&1 || true
    exit "$rc"
}
trap cleanup EXIT INT TERM

if ! command -v tmux >/dev/null 2>&1; then
    printf '%s: tmux is required for this test\n' "$PROG" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    printf '%s: jq is required for this test\n' "$PROG" >&2
    exit 2
fi

# Start the fixture tmux session in detached mode.
tmux -L "$FIXTURE_SOCKET" new-session -d -s "$FIXTURE_SESSION" -x 200 -y 50 \
    "sleep 600"

# Wait briefly so the pane is fully attached before fleet-status.sh reads it.
# tmux 3.x publishes pane state synchronously after new-session returns; we
# poll once to be safe rather than sleeping unconditionally.
for _ in 1 2 3 4 5; do
    if tmux -L "$FIXTURE_SOCKET" list-panes -a >/dev/null 2>&1; then
        break
    fi
done

OUT_FILE="$(mktemp -t fleet-status-out.XXXXXX.json)"
ERR_FILE="$(mktemp -t fleet-status-err.XXXXXX.log)"
# shellcheck disable=SC2064
trap "rm -f '$OUT_FILE' '$ERR_FILE'; tmux -L '$FIXTURE_SOCKET' kill-server >/dev/null 2>&1 || true" EXIT

if ! CODEX_FLEET_SOCKET="$FIXTURE_SOCKET" "$TARGET" >"$OUT_FILE" 2>"$ERR_FILE"; then
    printf 'FAIL: fleet-status.sh exited non-zero\n' >&2
    cat "$ERR_FILE" >&2 || true
    exit 1
fi

# 1. Output must be valid JSON.
if ! jq empty <"$OUT_FILE" 2>/dev/null; then
    printf 'FAIL: output is not valid JSON\n' >&2
    head -c 500 "$OUT_FILE" >&2 || true
    exit 1
fi

# 2. schema_version must be 1.
schema_version="$(jq -r '.schema_version // empty' <"$OUT_FILE")"
if [ "$schema_version" != "1" ]; then
    printf 'FAIL: schema_version is %s, expected 1\n' "$schema_version" >&2
    exit 1
fi

# 3. Required top-level keys must all be present.
REQUIRED_KEYS=(
    schema_version
    generated_at_utc
    tmux_sessions
    workers
    plan
    plan_subtasks
    open_prs
    merged_prs_for_plan
    capacity
    blockers
    ms_to_compose
)
for key in "${REQUIRED_KEYS[@]}"; do
    if ! jq -e --arg k "$key" 'has($k)' <"$OUT_FILE" >/dev/null; then
        printf 'FAIL: missing required key: %s\n' "$key" >&2
        exit 1
    fi
done

# 4. tmux_sessions, workers, plan_subtasks, open_prs, merged_prs_for_plan,
#    capacity, blockers must all be arrays.
for key in tmux_sessions workers plan_subtasks open_prs merged_prs_for_plan capacity blockers; do
    if ! jq -e --arg k "$key" '.[$k] | type == "array"' <"$OUT_FILE" >/dev/null; then
        printf 'FAIL: key %s is not an array\n' "$key" >&2
        exit 1
    fi
done

# 5. The fixture session we just started should appear in tmux_sessions.
if ! jq -e --arg name "$FIXTURE_SESSION" \
        '.tmux_sessions | map(select(.name == $name)) | length >= 1' \
        <"$OUT_FILE" >/dev/null; then
    printf 'FAIL: fixture tmux session %s not present in tmux_sessions\n' \
        "$FIXTURE_SESSION" >&2
    jq '.tmux_sessions' <"$OUT_FILE" >&2 || true
    exit 1
fi

# 6. ms_to_compose must be < 5000 (the documented budget for MCP consumers).
ms_to_compose="$(jq -r '.ms_to_compose // -1' <"$OUT_FILE")"
case "$ms_to_compose" in
    ''|*[!0-9]*)
        printf 'FAIL: ms_to_compose is not an integer: %s\n' "$ms_to_compose" >&2
        exit 1
        ;;
esac
if [ "$ms_to_compose" -ge 5000 ]; then
    printf 'FAIL: ms_to_compose=%s ms exceeds 5000 ms budget\n' "$ms_to_compose" >&2
    exit 1
fi

# 7. workers list must include at least one entry whose pane belongs to the
#    fixture session (sanity-check the per-pane composer with a known input).
if ! jq -e --arg name "$FIXTURE_SESSION" \
        '.workers | map(select(.pane_id | startswith($name + ":"))) | length >= 1' \
        <"$OUT_FILE" >/dev/null; then
    printf 'FAIL: no worker entry references the fixture tmux session\n' >&2
    jq '.workers | map(.pane_id)' <"$OUT_FILE" >&2 || true
    exit 1
fi

printf 'PASS run-fleet-status.sh: schema_version=%s workers=%s ms_to_compose=%s\n' \
    "$schema_version" \
    "$(jq '.workers | length' <"$OUT_FILE")" \
    "$ms_to_compose"

exit 0
