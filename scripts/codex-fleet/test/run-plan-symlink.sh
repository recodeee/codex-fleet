#!/usr/bin/env bash
# shellcheck shell=bash
#
# run-plan-symlink.sh — SI-15 smoke test for the plan-into-writable_root
# symlink staging in scripts/codex-fleet/full-bringup.sh.
#
# Extracts the stage_plan_symlink() helper from full-bringup.sh and asserts:
#   (a) for a writable_root OUTSIDE the repo, the symlink is created and
#       resolves to the canonical plan workspace
#   (b) for a writable_root INSIDE the repo, the helper skips (no symlink
#       is created — the plan already lives there)
#   (c) re-running the helper is idempotent (ln -sfn replaces the link
#       without error)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BRINGUP="$FLEET_DIR/full-bringup.sh"

[ -f "$BRINGUP" ] || { echo "FAIL: $BRINGUP not found" >&2; exit 1; }

tmpdir="$(mktemp -d -t plan-symlink-test.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -rf '$tmpdir'" EXIT

# Fake repo with one plan workspace.
repo="$tmpdir/repo"
mkdir -p "$repo/openspec/plans/test-plan-slug"
echo '{"plan_slug":"test-plan-slug"}' > "$repo/openspec/plans/test-plan-slug/plan.json"

# Foreign writable_root (outside the repo).
foreign="$tmpdir/foreign"
mkdir -p "$foreign"

# Extract stage_plan_symlink + log/warn helpers from full-bringup.sh.
helper="$tmpdir/symlink-helper.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set -uo pipefail'
  echo 'log() { printf "[full-bringup] %s\n" "$*"; }'
  echo 'warn() { printf "[full-bringup] %s\n" "$*" >&2; }'
  awk '
    /^stage_plan_symlink\(\) \{/ { capture=1 }
    capture { print }
    capture && /^\}$/ { capture=0; exit }
  ' "$BRINGUP"
} > "$helper"

# shellcheck disable=SC1090
. "$helper"

fail=0

# Case (a): foreign writable_root → symlink created.
stage_plan_symlink "$foreign" "test-plan-slug" "$repo" >/dev/null
link="$foreign/openspec/plans/test-plan-slug"
if [ -L "$link" ] && [ -e "$link" ]; then
  resolved="$(readlink "$link")"
  if [ "$resolved" = "$repo/openspec/plans/test-plan-slug" ]; then
    echo "OK:   foreign writable_root → symlink resolves to canonical plan dir"
  else
    echo "FAIL: foreign writable_root → symlink points at '$resolved'" >&2
    fail=$((fail + 1))
  fi
else
  echo "FAIL: foreign writable_root → symlink not created at $link" >&2
  fail=$((fail + 1))
fi

# Case (b): writable_root inside the repo → skipped.
inside="$repo/inside-root"
mkdir -p "$inside"
stage_plan_symlink "$inside" "test-plan-slug" "$repo" >/dev/null
inside_link="$inside/openspec/plans/test-plan-slug"
if [ -L "$inside_link" ] || [ -e "$inside_link" ]; then
  echo "FAIL: in-repo writable_root → unexpected symlink/dir at $inside_link" >&2
  fail=$((fail + 1))
else
  echo "OK:   in-repo writable_root → skipped (no symlink staged)"
fi

# Case (c): re-running on the foreign root is idempotent.
if stage_plan_symlink "$foreign" "test-plan-slug" "$repo" >/dev/null; then
  if [ -L "$link" ]; then
    echo "OK:   re-running stage_plan_symlink is idempotent"
  else
    echo "FAIL: re-run lost the symlink" >&2
    fail=$((fail + 1))
  fi
else
  echo "FAIL: re-run returned non-zero" >&2
  fail=$((fail + 1))
fi

[ "$fail" -eq 0 ] || exit 1
echo "summary: plan-symlink ok"
