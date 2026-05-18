#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-spawn-enforcement.sh — smoke-test for SI-16's CODEX_FLEET_AGENT_NAME
# enforcement in scripts/codex-fleet/claude-spawn.sh.
#
# Covers two cases:
#
#   Case 1: CODEX_FLEET_AGENT_NAME unset → claude-spawn.sh exits 2 with the
#           documented FATAL message. Catches accidental regression of the
#           fail-fast guard (the gap observed 2026-05-18 where panes
#           spawned without an agent name and Colony's matchmaker treated
#           them as one generic 'codex' agent).
#
#   Case 2: CODEX_FLEET_AGENT_NAME set → spawn proceeds. We use --dry-run
#           plus build_pane_cmd extraction to assert the rendered env_str
#           propagates the CODEX_FLEET_* family (AGENT_NAME, TIER,
#           SPECIALTY, and WORKER_CWD when set). The rendered string is
#           the same one passed to `env <vars> bash claude-worker.sh`, so
#           if it contains the var, the spawned process's environ will
#           too (verified separately by case 2b which captures /proc env
#           for a backgrounded subprocess).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPAWN="$FLEET_DIR/claude-spawn.sh"

[ -f "$SPAWN" ] || { echo "FAIL: $SPAWN not found" >&2; exit 1; }

PASS=0
FAIL=0

pass() { printf '  PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL: %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Case 1: unset CODEX_FLEET_AGENT_NAME → exit 2 + FATAL message.
# ---------------------------------------------------------------------------
echo "case 1: CODEX_FLEET_AGENT_NAME unset → fail-fast"

# Run in a subshell so the unset does not leak. Capture stderr+stdout
# together so we can grep for the FATAL banner regardless of where it
# lands.
out=""
rc=0
out="$(
  env -u CODEX_FLEET_AGENT_NAME \
    bash "$SPAWN" --dry-run -n 1 2>&1
)" || rc=$?

if [ "$rc" -ne 2 ]; then
  fail "expected exit code 2, got $rc"
else
  pass "exit code is 2"
fi

if printf '%s\n' "$out" | grep -q 'FATAL: CODEX_FLEET_AGENT_NAME not set'; then
  pass "FATAL banner present"
else
  fail "FATAL banner missing; got: $out"
fi

# ---------------------------------------------------------------------------
# Case 2: set CODEX_FLEET_AGENT_NAME → spawn proceeds (dry-run, exit 0).
# ---------------------------------------------------------------------------
echo "case 2: CODEX_FLEET_AGENT_NAME=test-fixture → dry-run succeeds"

out2=""
rc2=0
out2="$(
  CODEX_FLEET_AGENT_NAME=test-fixture \
    bash "$SPAWN" --dry-run -n 1 2>&1
)" || rc2=$?

if [ "$rc2" -ne 0 ]; then
  fail "expected exit code 0, got $rc2 (output: $out2)"
else
  pass "exit code is 0"
fi

if printf '%s\n' "$out2" | grep -q '\[dry-run\] would spawn'; then
  pass "dry-run banner present"
else
  fail "dry-run banner missing; got: $out2"
fi

# ---------------------------------------------------------------------------
# Case 2b: with the var set, render build_pane_cmd by extracting it from
# claude-spawn.sh and assert CODEX_FLEET_* family is in the env_str. This
# is the env that env(1) hands to the spawned wrapper, so anything in it
# is in the wrapper's /proc/<pid>/environ.
# ---------------------------------------------------------------------------
echo "case 2b: build_pane_cmd renders CODEX_FLEET_* family in env_str"

tmpdir="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$tmpdir'" EXIT

helper="$tmpdir/build-helper.sh"
awk '
  /^build_pane_cmd\(\) \{/ { capture=1 }
  capture { print }
  capture && /^\}$/ { capture=0; exit }
' "$SPAWN" > "$helper"

if ! grep -q "build_pane_cmd()" "$helper"; then
  fail "could not extract build_pane_cmd helper from $SPAWN"
else
  pass "extracted build_pane_cmd helper"
fi

# Stage minimal globals build_pane_cmd reads.
runner="$tmpdir/run.sh"
cat > "$runner" <<EOF
#!/usr/bin/env bash
set -u
TIER="medium"
SPECIALTY="fixture-specialty"
MODEL="sonnet"
CODEX_HOME="/tmp/fake-codex-home"
ACCOUNT_EMAIL=""
CODEX_FLEET_TASK_ID=""
CODEX_FLEET_WORKER_CWD="/tmp/fake-worker-cwd"
WRAPPER="/tmp/fake-wrapper"
. "$helper"
build_pane_cmd "claude-fleet-7" "fixture-label" "" ""
EOF
chmod +x "$runner"

rendered="$(bash "$runner" 2>&1)"

# AGENT_NAME, TIER, SPECIALTY, WORKER_CWD must all appear under the
# CODEX_FLEET_* prefix in the rendered env_str so the spawned worker
# can see them via printenv.
for needle in \
  "CODEX_FLEET_AGENT_NAME='claude-fleet-7'" \
  "CODEX_FLEET_TIER='medium'" \
  "CODEX_FLEET_SPECIALTY='fixture-specialty'" \
  "CODEX_FLEET_WORKER_CWD='/tmp/fake-worker-cwd'"
do
  if printf '%s' "$rendered" | grep -qF "$needle"; then
    pass "env_str contains $needle"
  else
    fail "env_str missing $needle; got: $rendered"
  fi
done

# ---------------------------------------------------------------------------
# Case 2c: end-to-end environ check. Mock the wrapper as a script that
# dumps its environ to a file, then invoke claude-spawn.sh with a tmux
# session it cannot find (forcing the kitty fallback) AND with `kitty`
# also unavailable (so spawn_one returns non-zero) — instead we exercise
# the env_str path by extracting build_pane_cmd and running the rendered
# command directly with the mock wrapper. This proves the rendered
# command actually exports the vars into the child's environ.
# ---------------------------------------------------------------------------
echo "case 2c: rendered env_str produces CODEX_FLEET_* in child environ"

mock_wrapper="$tmpdir/mock-wrapper.sh"
environ_dump="$tmpdir/environ.txt"
cat > "$mock_wrapper" <<EOF
#!/usr/bin/env bash
# Dump current env to a known path so the test can assert on it.
env > "$environ_dump"
EOF
chmod +x "$mock_wrapper"

runner2="$tmpdir/run2.sh"
cat > "$runner2" <<EOF
#!/usr/bin/env bash
set -u
TIER="medium"
SPECIALTY="fixture-specialty"
MODEL="sonnet"
CODEX_HOME="/tmp/fake-codex-home"
ACCOUNT_EMAIL=""
CODEX_FLEET_TASK_ID=""
CODEX_FLEET_WORKER_CWD="/tmp/fake-worker-cwd"
WRAPPER="$mock_wrapper"
. "$helper"
cmd="\$(build_pane_cmd "claude-fleet-7" "fixture-label" "" "")"
# The rendered command is "env VAR=... bash 'WRAPPER'\\n". Execute it
# under bash -c so the env(1) prefix applies.
eval "\$cmd"
EOF
chmod +x "$runner2"

bash "$runner2" >/dev/null 2>&1 || true

if [ ! -f "$environ_dump" ]; then
  fail "mock wrapper did not write environ dump at $environ_dump"
else
  for var in \
    "CODEX_FLEET_AGENT_NAME=claude-fleet-7" \
    "CODEX_FLEET_TIER=medium" \
    "CODEX_FLEET_SPECIALTY=fixture-specialty" \
    "CODEX_FLEET_WORKER_CWD=/tmp/fake-worker-cwd"
  do
    if grep -qF "$var" "$environ_dump"; then
      pass "child environ contains $var"
    else
      fail "child environ missing $var; got: $(cat "$environ_dump")"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
printf 'summary: %d pass, %d fail\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
