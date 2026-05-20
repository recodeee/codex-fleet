#!/usr/bin/env bash
# test-script-help.sh — smoke test for the --help / --version flags added to
# cap-probe.sh, score-checkpoint.sh, and force-claim.sh.
#
# Asserts, for each script:
#   * --help  exits 0 with non-empty stdout that mentions the script name
#   * --version  exits 0, mentions the script name, and emits something that
#                looks like a version token
#
# Run from the repo root: `bash tests/scripts/test-script-help.sh`
# Exits 0 on success, non-zero on the first failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts/codex-fleet"

SCRIPTS=(
  cap-probe.sh
  score-checkpoint.sh
  force-claim.sh
)

fail=0
pass=0

check() {
  local script="$1" flag="$2" want_token="$3"
  local out rc
  out=$(bash "$SCRIPTS_DIR/$script" "$flag" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'FAIL: %s %s exited %d\n' "$script" "$flag" "$rc" >&2
    printf '       stdout/stderr:\n%s\n' "$out" >&2
    fail=$((fail + 1))
    return 1
  fi
  if [ -z "$out" ]; then
    printf 'FAIL: %s %s produced empty stdout\n' "$script" "$flag" >&2
    fail=$((fail + 1))
    return 1
  fi
  if ! printf '%s' "$out" | grep -qF "$want_token"; then
    printf 'FAIL: %s %s output missing token %q\n' "$script" "$flag" "$want_token" >&2
    printf '       output:\n%s\n' "$out" >&2
    fail=$((fail + 1))
    return 1
  fi
  pass=$((pass + 1))
  return 0
}

for s in "${SCRIPTS[@]}"; do
  # --help: must mention the script name somewhere in usage.
  check "$s" "--help" "$s"
  # --version: must mention the script name. Additionally assert a digit
  # appears (covers both "0.0.0-dev" and any future "vX.Y.Z" tag).
  out=$(bash "$SCRIPTS_DIR/$s" --version 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'FAIL: %s --version exited %d\n' "$s" "$rc" >&2
    printf '       output:\n%s\n' "$out" >&2
    fail=$((fail + 1))
    continue
  fi
  if ! printf '%s' "$out" | grep -qF "$s"; then
    printf 'FAIL: %s --version missing script name; got: %s\n' "$s" "$out" >&2
    fail=$((fail + 1))
    continue
  fi
  if ! printf '%s' "$out" | grep -qE '[0-9]'; then
    printf 'FAIL: %s --version missing version token; got: %s\n' "$s" "$out" >&2
    fail=$((fail + 1))
    continue
  fi
  pass=$((pass + 1))
done

printf 'test-script-help: %d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
