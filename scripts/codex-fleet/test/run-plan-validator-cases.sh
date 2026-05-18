#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-plan-validator-cases.sh — runs scripts/codex-fleet/lib/plan-validator.sh
# against every .json fixture in plan-validator-cases/ and asserts the
# observed exit code matches the matching .expected file (one integer per
# file). Used by SI-5 to lock in the new validation rules.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$FLEET_DIR/lib/plan-validator.sh"
CASES_DIR="$SCRIPT_DIR/plan-validator-cases"

[ -f "$VALIDATOR" ] || { echo "FAIL: $VALIDATOR not found" >&2; exit 1; }
[ -d "$CASES_DIR" ] || { echo "FAIL: $CASES_DIR not found" >&2; exit 1; }

pass=0
fail=0
for fixture in "$CASES_DIR"/*.json; do
  [ -f "$fixture" ] || continue
  base="${fixture%.json}"
  expected_file="${base}.expected"
  if [ ! -f "$expected_file" ]; then
    echo "FAIL: missing expected file: $expected_file" >&2
    fail=$((fail + 1))
    continue
  fi
  expected="$(head -n1 "$expected_file" | tr -d '[:space:]')"
  set +e
  bash "$VALIDATOR" "$fixture" --allow-waves >/dev/null 2>/dev/null
  actual=$?
  set -e
  if [ "$actual" = "$expected" ]; then
    echo "OK:   $(basename "$fixture") exit=$actual"
    pass=$((pass + 1))
  else
    echo "FAIL: $(basename "$fixture") exit=$actual (expected $expected)" >&2
    fail=$((fail + 1))
  fi
done

echo "summary: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
