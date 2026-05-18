#!/usr/bin/env bash
# run-stall-replay.sh — replay harness for the SI-2 codex-CLI interactive
# prompt classifier in scripts/codex-fleet/stall-watcher.sh.
#
# Sources stall-watcher.sh (which short-circuits its daemon body when
# sourced) to get classify_prompt_kind + keys_for_kind, then iterates
# every .txt fixture under scripts/codex-fleet/test/stall-fixtures/,
# pipes the capture through classify_prompt_kind, and asserts the result
# matches the sibling .label file.
#
# Exit codes:
#   0 — every fixture classified correctly
#   1 — at least one mismatch (printed inline)
#   2 — usage / setup error (missing fixtures dir, missing classifier)

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="${1:-$SCRIPT_DIR/stall-fixtures}"
WATCHER_SH="$FLEET_DIR/stall-watcher.sh"

if [ ! -f "$WATCHER_SH" ]; then
  printf 'fatal: stall-watcher.sh not found at %s\n' "$WATCHER_SH" >&2
  exit 2
fi

# shellcheck source=../stall-watcher.sh
. "$WATCHER_SH"

if ! declare -F classify_prompt_kind >/dev/null 2>&1; then
  printf 'fatal: classify_prompt_kind not exported by stall-watcher.sh\n' >&2
  exit 2
fi
if ! declare -F keys_for_kind >/dev/null 2>&1; then
  printf 'fatal: keys_for_kind not exported by stall-watcher.sh\n' >&2
  exit 2
fi

if [ ! -d "$FIXTURE_DIR" ]; then
  printf 'fatal: fixture dir not found: %s\n' "$FIXTURE_DIR" >&2
  exit 2
fi

shopt -s nullglob

total=0
passes=0
fails=()

for fixture in "$FIXTURE_DIR"/*.txt; do
  base="$(basename "$fixture")"
  label_file="${fixture%.txt}.label"
  if [ ! -f "$label_file" ]; then
    printf 'skip: %s (missing sibling .label)\n' "$base"
    continue
  fi

  expected="$(tr -d '\n\r' < "$label_file" | awk '{$1=$1; print}')"
  actual="$(classify_prompt_kind <"$fixture")"
  total=$(( total + 1 ))

  if [ "$actual" = "$expected" ]; then
    keys="$(keys_for_kind "$actual" 2>/dev/null || printf '<no-keys>')"
    # Render \r as \\r for display.
    keys_disp="${keys//$'\r'/\\r}"
    keys_disp="${keys_disp//$'\n'/\\n}"
    printf '  PASS  %-16s -> %-16s  keys=%-6s  %s\n' "$expected" "$actual" "$keys_disp" "$base"
    passes=$(( passes + 1 ))
  else
    printf '  FAIL  %-16s -> %-16s                 %s\n' "$expected" "$actual" "$base"
    fails+=("$base: expected=$expected actual=$actual")
  fi
done

if [ "$total" -eq 0 ]; then
  printf 'fatal: no .txt fixtures found under %s\n' "$FIXTURE_DIR" >&2
  exit 2
fi

printf '\nfixtures total : %d\n' "$total"
printf 'fixtures pass  : %d\n' "$passes"
printf 'fixtures fail  : %d\n' "$(( total - passes ))"

if [ "${#fails[@]}" -gt 0 ]; then
  printf '\nfailing fixtures:\n'
  for f in "${fails[@]}"; do
    printf '  - %s\n' "$f"
  done
  exit 1
fi

exit 0
