#!/usr/bin/env bash
# test-fleet-mcp.sh -- smoke test for scripts/codex-fleet/mcp/fleet-mcp.py.
#
# For each of the 6 registered tools, pipes a single JSON-RPC 2.0 request
# over stdin, parses the reply with jq, and asserts:
#   * the response carries a `result.content[0].text` payload
#   * that payload parses as JSON
#   * either it is not an error, or the error matches a documented
#     "fleet-not-up" sentinel string
#
# Designed to be runnable both with a live fleet and without -- in the
# without case, several tools will return a documented error string
# (e.g. "fleet-status.sh not installed yet"); the test treats those as
# acceptable as long as the JSON shape is right.
#
# Exit 0 = pass, non-zero = fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$SCRIPT_DIR/fleet-mcp.py"

if [[ ! -x "$SERVER" ]]; then
  echo "FAIL: $SERVER missing or not executable" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq required" >&2
  exit 1
fi

# Documented sentinel errors that are acceptable when the fleet is not up.
# Anything else counts as a real failure.
ACCEPTABLE_ERRORS=(
  "fleet-status.sh not installed yet"
  "no server running"
  "error connecting"
  "plan .* not found"
  "tmux list-panes failed"
  "tmux send-keys exited"
  "can't find session"
  "gh CLI not installed"
  "gh pr list exited"
  "timeout after"
  "command not found"
)

pass=0
fail=0

call_tool() {
  local id="$1" name="$2" args_json="$3"
  # We send a minimal sequence: initialize, then the single tools/call.
  # The server replies with two JSON lines; we want the second.
  local reply
  reply="$(
    printf '%s\n%s\n' \
      "$(jq -cn --argjson id 1 '{jsonrpc:"2.0", id:$id, method:"initialize", params:{protocolVersion:"2024-11-05", capabilities:{}, clientInfo:{name:"smoke", version:"0"}}}')" \
      "$(jq -cn --argjson id "$id" --arg name "$name" --argjson args "$args_json" \
        '{jsonrpc:"2.0", id:$id, method:"tools/call", params:{name:$name, arguments:$args}}')" \
      | python3 "$SERVER" 2>/dev/null \
      | tail -n 1
  )"
  echo "$reply"
}

assert_tool() {
  local name="$1" args_json="$2"
  local id=$((RANDOM + 100))
  local reply
  reply="$(call_tool "$id" "$name" "$args_json" || true)"

  if [[ -z "$reply" ]]; then
    echo "FAIL [$name]: no reply from server" >&2
    fail=$((fail + 1))
    return
  fi

  # Must be valid JSON.
  if ! echo "$reply" | jq -e . >/dev/null 2>&1; then
    echo "FAIL [$name]: reply is not JSON: $reply" >&2
    fail=$((fail + 1))
    return
  fi

  # Must carry result.content[0].text (the tool payload).
  local text
  if ! text="$(echo "$reply" | jq -r '.result.content[0].text // empty')"; then
    echo "FAIL [$name]: jq error extracting content text" >&2
    fail=$((fail + 1))
    return
  fi
  if [[ -z "$text" ]]; then
    echo "FAIL [$name]: missing result.content[0].text. reply=$reply" >&2
    fail=$((fail + 1))
    return
  fi

  # The text payload itself must be JSON.
  if ! echo "$text" | jq -e . >/dev/null 2>&1; then
    echo "FAIL [$name]: tool payload is not JSON: $text" >&2
    fail=$((fail + 1))
    return
  fi

  # Determine error state.
  local err
  err="$(echo "$text" | jq -r '.error // empty')"
  if [[ -z "$err" ]]; then
    echo "PASS [$name]: non-error reply"
    pass=$((pass + 1))
    return
  fi

  local accepted=0
  for sentinel in "${ACCEPTABLE_ERRORS[@]}"; do
    if [[ "$err" =~ $sentinel ]]; then
      accepted=1
      break
    fi
  done
  if (( accepted == 1 )); then
    echo "PASS [$name]: acceptable fleet-not-up error: $err"
    pass=$((pass + 1))
  else
    echo "FAIL [$name]: unexpected error: $err" >&2
    fail=$((fail + 1))
  fi
}

echo "==> fleet-mcp smoke test"
echo "    server: $SERVER"
echo

# 1. fleet_status -- no args
assert_tool "fleet_status" '{}'

# 2. colony_plan_status -- pass the SI-1 plan slug (which exists)
assert_tool "colony_plan_status" '{"slug":"supervisor-improvements-2026-05-18"}'

# 3. tmux_pane_state -- no args (lists all panes, OK if tmux not up)
assert_tool "tmux_pane_state" '{}'

# 4. tmux_pane_send_keys -- target a likely-nonexistent pane on the
# codex-fleet socket. We expect EITHER ok (if a real pane matches) OR an
# acceptable tmux error (no server running, etc.). We send a harmless
# no-op key sequence so even a real pane won't be disturbed.
assert_tool "tmux_pane_send_keys" \
  '{"session":"nonexistent-smoke-test","pane":"0.0","keys":"","enter":false}'

# 5. worker_dismiss_prompts -- no args (scans all panes, OK if none)
assert_tool "worker_dismiss_prompts" '{}'

# 6. pr_list_for_plan -- use the SI-1 plan slug; if gh is unauthenticated
# we accept the documented gh error.
assert_tool "pr_list_for_plan" '{"slug":"supervisor-improvements-2026-05-18"}'

echo
echo "==> done: $pass passed, $fail failed"
exit "$fail"
