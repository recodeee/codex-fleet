#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-routing-filter.sh — SI-11 smoke test for compute_specialty in
# scripts/codex-fleet/lib/plan-routing-filter.sh. Asserts:
#   (a) foreign writable_roots → echoes the fixture's plan_slug
#   (b) fleet-family writable_roots → echoes empty
#   (c) pre-set CODEX_FLEET_SPECIALTY → respected verbatim

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$FLEET_DIR/lib/plan-routing-filter.sh"
FIX_DIR="$SCRIPT_DIR/routing-filter-fixtures"

[ -f "$FILTER" ] || { echo "FAIL: $FILTER not found" >&2; exit 1; }

# Source under a controlled env: unset any inherited CODEX_FLEET_SPECIALTY.
unset CODEX_FLEET_SPECIALTY
# shellcheck source=../lib/plan-routing-filter.sh
. "$FILTER"

fail=0

# Case (a): foreign writable_roots.
foreign_fix="$FIX_DIR/foreign-writable-roots.json"
foreign_slug="$(jq -r '.plan_slug' "$foreign_fix")"
got_foreign="$(compute_specialty "$foreign_slug" "$foreign_fix")"
if [ "$got_foreign" = "$foreign_slug" ]; then
  echo "OK:   foreign writable_roots → '$got_foreign'"
else
  echo "FAIL: foreign writable_roots → got '$got_foreign', expected '$foreign_slug'" >&2
  fail=$((fail + 1))
fi

# Case (b): fleet-family writable_roots → empty.
family_fix="$FIX_DIR/fleet-family-writable-roots.json"
family_slug="$(jq -r '.plan_slug' "$family_fix")"
got_family="$(compute_specialty "$family_slug" "$family_fix")"
if [ -z "$got_family" ]; then
  echo "OK:   fleet-family writable_roots → ''"
else
  echo "FAIL: fleet-family writable_roots → got '$got_family', expected ''" >&2
  fail=$((fail + 1))
fi

# Case (c): user override wins.
export CODEX_FLEET_SPECIALTY="manual-override"
got_override="$(compute_specialty "$foreign_slug" "$foreign_fix")"
unset CODEX_FLEET_SPECIALTY
if [ "$got_override" = "manual-override" ]; then
  echo "OK:   CODEX_FLEET_SPECIALTY pre-set → '$got_override' (respected)"
else
  echo "FAIL: pre-set CODEX_FLEET_SPECIALTY override lost → '$got_override'" >&2
  fail=$((fail + 1))
fi

[ "$fail" -eq 0 ] || exit 1
echo "summary: routing-filter ok"
