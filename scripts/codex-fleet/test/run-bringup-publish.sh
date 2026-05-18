#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-bringup-publish.sh — smoke-test for the SI-3 publish-retry helper in
# scripts/codex-fleet/full-bringup.sh. Mocks `colony` on PATH so the first
# invocation prints the documented "auto_archive" undefined error and the
# second invocation (with --auto-archive) succeeds. Extracts the
# publish_plan_once function from full-bringup.sh and verifies the retry
# path actually fires.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BRINGUP="$FLEET_DIR/full-bringup.sh"

[ -f "$BRINGUP" ] || { echo "FAIL: $BRINGUP not found" >&2; exit 1; }

tmpdir="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$tmpdir'" EXIT

# ---- Mock colony --------------------------------------------------------
mkdir -p "$tmpdir/bin"
state_file="$tmpdir/colony-state"
echo 0 > "$state_file"
cat > "$tmpdir/bin/colony" <<'MOCK'
#!/usr/bin/env bash
# Mock of `colony` CLI for SI-3 retry test. First call exits 1 with the
# documented auto_archive error; subsequent calls succeed iff --auto-archive
# is in the argv.
state="${COLONY_MOCK_STATE:-/tmp/colony-mock-state}"
count=$(cat "$state" 2>/dev/null || echo 0)
new=$((count + 1))
echo "$new" > "$state"
if [ "$count" -eq 0 ]; then
  echo "Cannot read properties of undefined (reading auto_archive)" >&2
  exit 1
fi
# Retry path: succeed only if --auto-archive is present.
for arg in "$@"; do
  if [ "$arg" = "--auto-archive" ]; then
    echo "published ok (mock)"
    exit 0
  fi
done
echo "second call missing --auto-archive (mock)" >&2
exit 2
MOCK
chmod +x "$tmpdir/bin/colony"
export COLONY_MOCK_STATE="$state_file"
export PATH="$tmpdir/bin:$PATH"

# ---- Extract publish_plan_once from full-bringup.sh ---------------------
helper="$tmpdir/publish-helper.sh"
awk '
  /^publish_plan_once\(\) \{/ { capture=1 }
  capture { print }
  capture && /^\}$/ { capture=0; exit }
' "$BRINGUP" > "$helper"

if ! grep -q "publish_plan_once()" "$helper"; then
  echo "FAIL: could not extract publish_plan_once helper from $BRINGUP" >&2
  exit 1
fi

# ---- Stub the helper's collaborators ------------------------------------
runner="$tmpdir/run.sh"
cat > "$runner" <<EOF
#!/usr/bin/env bash
set -uo pipefail
warn() { printf '[warn] %s\n' "\$*" >&2; }
mkdir -p /tmp/codex-fleet
# Ensure a fresh cache mark for this slug.
rm -f /tmp/codex-fleet/.plan-publish.si3-smoke.mark
. "$helper"
publish_plan_once si3-smoke
rc=\$?
echo "FIRST_CALL_RC=\$rc"
ls -1 /tmp/codex-fleet/.plan-publish.si3-smoke.mark >/dev/null 2>&1 \
  && echo "MARK_TOUCHED=yes" || echo "MARK_TOUCHED=no"
# Cleanup
rm -f /tmp/codex-fleet/.plan-publish.si3-smoke.mark
EOF
chmod +x "$runner"

out="$("$runner" 2>"$tmpdir/run.err")" || true

# ---- Asserts ------------------------------------------------------------
call_count=$(cat "$state_file")
fail=0
if [ "$call_count" -ne 2 ]; then
  echo "FAIL: expected colony to be called twice, got $call_count" >&2
  fail=1
fi
if ! grep -q '^FIRST_CALL_RC=0$' <<<"$out"; then
  echo "FAIL: publish_plan_once should have returned 0 after retry" >&2
  echo "---- stdout ----" >&2
  echo "$out" >&2
  echo "---- stderr ----" >&2
  cat "$tmpdir/run.err" >&2 || true
  fail=1
fi
if ! grep -q '^MARK_TOUCHED=yes$' <<<"$out"; then
  echo "FAIL: per-slug cache mark was not touched on success" >&2
  fail=1
fi
if ! grep -q "retrying with --auto-archive" "$tmpdir/run.err"; then
  echo "FAIL: expected 'retrying with --auto-archive' message on stderr" >&2
  cat "$tmpdir/run.err" >&2 || true
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "OK: SI-3 publish-retry helper retried with --auto-archive and succeeded"
