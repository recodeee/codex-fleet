#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-wake-templater.sh — SI-19 smoke test for wake-prompt-templater.sh.
#
# Sets up a fixture repo with .codex-fleet/active-plan + a fake plan, then
# injects a mock `colony` CLI via WAKE_COLONY_BIN that returns canned JSON
# for `task ready --json`. Runs the templater with WAKE_ONCE=1 and asserts
# the rendered file contains the substituted slug + title.
#
# Also verifies the exhausted-variant render when the mock returns empty.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATER="$FLEET_DIR/wake-prompt-templater.sh"
TEMPLATE="$FLEET_DIR/wake-prompt.template.md"

[ -x "$TEMPLATER" ] || { echo "FAIL: $TEMPLATER not executable" >&2; exit 1; }
[ -r "$TEMPLATE" ]  || { echo "FAIL: $TEMPLATE missing" >&2; exit 1; }

tmpdir="$(mktemp -d -t wake-templater-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '$tmpdir'" EXIT

# Fixture: fake repo with active-plan + a plan workspace.
fake_repo="$tmpdir/repo"
mkdir -p "$fake_repo/.codex-fleet" "$fake_repo/openspec/plans/fixture-plan-2026-05-18"
printf '%s' 'fixture-plan-2026-05-18' > "$fake_repo/.codex-fleet/active-plan"

# Mock colony — emits a single ready item matching the fixture plan slug.
mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/colony" <<'MOCK'
#!/usr/bin/env bash
# Mock colony CLI: when asked for `task ready --json`, emit a canned payload.
# Honor WAKE_TEST_MODE=exhausted to emit an empty payload (no ready items).
if [ "${1:-}" = "task" ] && [ "${2:-}" = "ready" ]; then
  shift 2
  for arg in "$@"; do
    case "$arg" in
      --json) ;;
    esac
  done
  if [ "${WAKE_TEST_MODE:-live}" = "exhausted" ]; then
    cat <<'JSON'
{"ready":[]}
JSON
  else
    cat <<'JSON'
{"ready":[{"plan_slug":"fixture-plan-2026-05-18","subtask_index":7,"title":"[FIX-7] live templater smoke test subject","description":"Make sure the wake-prompt-templater renders the live next-subtask into /tmp/codex-fleet-wake-prompt.md."}]}
JSON
  fi
  exit 0
fi
exit 0
MOCK
chmod +x "$tmpdir/bin/colony"

fail=0

# ---- Live variant: live next subtask is rendered ----
output_path="$tmpdir/wake-live.md"
WAKE_ONCE=1 \
  WAKE_TEMPLATE_PATH="$TEMPLATE" \
  WAKE_OUTPUT_PATH="$output_path" \
  WAKE_COLONY_BIN="$tmpdir/bin/colony" \
  CODEX_FLEET_REPO_ROOT="$fake_repo" \
  WAKE_TEST_MODE=live \
  bash "$TEMPLATER" >/dev/null 2>&1

if [ ! -f "$output_path" ]; then
  echo "FAIL: live variant — output file not written: $output_path" >&2
  fail=$((fail + 1))
else
  if grep -q 'fixture-plan-2026-05-18' "$output_path" \
     && grep -q '\[FIX-7\] live templater smoke test subject' "$output_path" \
     && grep -q '7' "$output_path"; then
    echo "OK:   live variant — slug + title + index substituted"
  else
    echo "FAIL: live variant — output missing slug/title/index" >&2
    sed 's/^/  /' "$output_path" >&2
    fail=$((fail + 1))
  fi
  # The live variant must NOT render the plan-exhausted notice.
  if grep -q 'plan-exhausted' "$output_path"; then
    echo "FAIL: live variant — exhausted notice should be empty" >&2
    fail=$((fail + 1))
  else
    echo "OK:   live variant — no exhausted notice"
  fi
fi

# ---- Exhausted variant: no ready items → exhausted notice rendered ----
output_path2="$tmpdir/wake-exhausted.md"
WAKE_ONCE=1 \
  WAKE_TEMPLATE_PATH="$TEMPLATE" \
  WAKE_OUTPUT_PATH="$output_path2" \
  WAKE_COLONY_BIN="$tmpdir/bin/colony" \
  CODEX_FLEET_REPO_ROOT="$fake_repo" \
  WAKE_TEST_MODE=exhausted \
  bash "$TEMPLATER" >/dev/null 2>&1

if [ ! -f "$output_path2" ]; then
  echo "FAIL: exhausted variant — output file not written" >&2
  fail=$((fail + 1))
else
  if grep -q 'plan-exhausted' "$output_path2" \
     && grep -q 'fixture-plan-2026-05-18' "$output_path2"; then
    echo "OK:   exhausted variant — plan-exhausted notice + slug rendered"
  else
    echo "FAIL: exhausted variant — missing exhausted notice or slug" >&2
    sed 's/^/  /' "$output_path2" >&2
    fail=$((fail + 1))
  fi
fi

[ "$fail" -eq 0 ] || exit 1
echo "summary: wake-templater ok"
