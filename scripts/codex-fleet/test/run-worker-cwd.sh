#!/usr/bin/env bash
#
# run-worker-cwd.sh — SI-9 unit tests for claude-worker.sh's
# resolve_worker_cwd precedence helper.
#
# Sources claude-worker.sh with CLAUDE_WORKER_SOURCE_ONLY=1 in a subshell
# so the function is defined without firing the main loop, then exercises
# four scenarios:
#
#   1. CODEX_FLEET_WORKER_CWD set + writable → echoes that path.
#   2. CODEX_FLEET_WORKER_CWD unset, active-plan-meta.json points at a
#      writable dir → echoes that dir.
#   3. Both unset → echoes $REPO.
#   4. CODEX_FLEET_WORKER_CWD points at non-existent path → falls
#      through to plan-meta (if usable) or $REPO.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORKER_SH="$ROOT/scripts/codex-fleet/claude-worker.sh"

[ -f "$WORKER_SH" ] || { echo "FAIL: missing $WORKER_SH" >&2; exit 1; }

TMP="$(mktemp -d -t si9-worker-cwd-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

fail() {
  printf 'FAIL %s\n' "$1" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  printf 'PASS %s\n' "$1"
  PASS=$((PASS + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$label"
  else
    fail "$label (expected='$expected' actual='$actual')"
  fi
}

# Helper: invoke resolve_worker_cwd in a clean subshell with a forced
# REPO and a chosen $HOME-like sandbox so each test is isolated.
#
# Args:
#   $1  fake REPO root (must exist; we control whether
#       .codex-fleet/active-plan-meta.json sits inside it)
#   env: CODEX_FLEET_WORKER_CWD optional pass-through
run_resolver() {
  local fake_repo="$1"
  CLAUDE_WORKER_SOURCE_ONLY=1 \
  CODEX_FLEET_REPO_ROOT="$fake_repo" \
  CODEX_FLEET_WORKER_CWD="${CODEX_FLEET_WORKER_CWD:-}" \
  bash -c "
    set -u
    # shellcheck disable=SC1090
    source '$WORKER_SH'
    resolve_worker_cwd
  "
}

# Scenario 1: CODEX_FLEET_WORKER_CWD set + writable → echoes it.
foo="$TMP/foo"
mkdir -p "$foo"
fake_repo_1="$TMP/repo1"
mkdir -p "$fake_repo_1"
got="$(CODEX_FLEET_WORKER_CWD="$foo" run_resolver "$fake_repo_1")"
assert_eq "1 env override returns explicit path" "$foo" "$got"

# Scenario 2: env unset, active-plan-meta points at /tmp/bar.
bar="$TMP/bar"
mkdir -p "$bar"
fake_repo_2="$TMP/repo2"
mkdir -p "$fake_repo_2/.codex-fleet"
cat >"$fake_repo_2/.codex-fleet/active-plan-meta.json" <<JSON
{ "metadata": { "writable_roots": ["$bar", "/should/not/use"] } }
JSON
unset CODEX_FLEET_WORKER_CWD
if command -v jq >/dev/null 2>&1; then
  got="$(run_resolver "$fake_repo_2")"
  assert_eq "2 plan-meta writable_roots[0] used" "$bar" "$got"
else
  printf 'SKIP 2 plan-meta test (jq not on PATH)\n'
fi

# Scenario 3: both unset → echoes $REPO.
fake_repo_3="$TMP/repo3"
mkdir -p "$fake_repo_3"
unset CODEX_FLEET_WORKER_CWD
got="$(run_resolver "$fake_repo_3")"
assert_eq "3 fallback to \$REPO" "$fake_repo_3" "$got"

# Scenario 4: CODEX_FLEET_WORKER_CWD points at non-existent path.
# With no plan-meta, must fall through to $REPO. Confirms the env path
# does NOT clobber the resolution when the target is unusable.
fake_repo_4="$TMP/repo4"
mkdir -p "$fake_repo_4"
got="$(CODEX_FLEET_WORKER_CWD="$TMP/does-not-exist" run_resolver "$fake_repo_4")"
assert_eq "4 non-existent env path falls through to \$REPO" "$fake_repo_4" "$got"

# Scenario 4b: non-existent env path WITH valid plan-meta → plan-meta wins.
baz="$TMP/baz"
mkdir -p "$baz"
fake_repo_4b="$TMP/repo4b"
mkdir -p "$fake_repo_4b/.codex-fleet"
cat >"$fake_repo_4b/.codex-fleet/active-plan-meta.json" <<JSON
{ "metadata": { "writable_roots": ["$baz"] } }
JSON
if command -v jq >/dev/null 2>&1; then
  got="$(CODEX_FLEET_WORKER_CWD="$TMP/still-missing" run_resolver "$fake_repo_4b")"
  assert_eq "4b non-existent env path falls through to plan-meta" "$baz" "$got"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
