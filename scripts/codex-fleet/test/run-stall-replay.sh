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
if ! declare -F should_dispatch_dismissal >/dev/null 2>&1; then
  printf 'fatal: should_dispatch_dismissal not exported by stall-watcher.sh\n' >&2
  exit 2
fi
if ! declare -F record_dismissal >/dev/null 2>&1; then
  printf 'fatal: record_dismissal not exported by stall-watcher.sh\n' >&2
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

# ---------- SI-12: per-pane dismissed-recently cooldown ------------------
#
# Scenario: a worker pane (pane_id="codex-fleet:1.0") sees a trust-dir
# prompt. The first capture goes through prompt_tick, dispatches `1\r`,
# and stamps DISMISSED_AT[codex-fleet:1.0:trust-dir]=now. 5 seconds later
# the codex-CLI capture buffer still shows the (now-dismissed) prompt in
# its tail, so classify_prompt_kind returns "trust-dir" again. With the
# SI-12 cooldown active, should_dispatch_dismissal must return 1
# (suppress) until the cooldown window elapses. This proves the
# dispatcher fires once per prompt instance, not once per 5s tick.
cooldown_fixture="$FIXTURE_DIR/cooldown.txt"
cooldown_label="$FIXTURE_DIR/cooldown.label"

if [ -f "$cooldown_fixture" ] && [ -f "$cooldown_label" ]; then
  printf '\nSI-12 cooldown scenario:\n'
  cd_fails=()
  cd_pane="codex-fleet:1.0"
  cd_kind="$(tr -d '\n\r' < "$cooldown_label" | awk '{$1=$1; print}')"

  # Sanity: cooldown fixture must classify as the labelled kind. If this
  # ever drifts, all downstream assertions become meaningless.
  classified="$(classify_prompt_kind <"$cooldown_fixture")"
  if [ "$classified" = "$cd_kind" ]; then
    printf '  PASS  classify cooldown fixture -> %s\n' "$cd_kind"
  else
    printf '  FAIL  classify cooldown fixture -> %s (expected %s)\n' "$classified" "$cd_kind"
    cd_fails+=("classify: got=$classified expected=$cd_kind")
  fi

  # Reset cache for this (pane,kind) so the test is independent of any
  # earlier scenario state.
  unset "DISMISSED_AT[${cd_pane}:${cd_kind}]" 2>/dev/null || true

  # 1) First capture: cache empty, dispatch is permitted.
  CODEX_FLEET_DISMISS_COOLDOWN_SECONDS=30
  export CODEX_FLEET_DISMISS_COOLDOWN_SECONDS
  if should_dispatch_dismissal "$cd_pane" "$cd_kind"; then
    printf '  PASS  first dispatch permitted (cache empty)\n'
  else
    printf '  FAIL  first dispatch suppressed (cache should be empty)\n'
    cd_fails+=("first-dispatch: should have been permitted")
  fi

  # Stamp the cache (simulating a successful tmux send-keys).
  record_dismissal "$cd_pane" "$cd_kind"

  # 2) Second capture 5s later (simulated): cache has a fresh entry, the
  #    second dispatch MUST be suppressed.
  if should_dispatch_dismissal "$cd_pane" "$cd_kind"; then
    printf '  FAIL  second dispatch permitted (should be suppressed within cooldown)\n'
    cd_fails+=("second-dispatch: should have been suppressed")
  else
    printf '  PASS  second dispatch suppressed within %ss cooldown\n' "$CODEX_FLEET_DISMISS_COOLDOWN_SECONDS"
  fi

  # 3) Cooldown disabled: setting the env var to 0 must lift suppression.
  CODEX_FLEET_DISMISS_COOLDOWN_SECONDS=0
  export CODEX_FLEET_DISMISS_COOLDOWN_SECONDS
  if should_dispatch_dismissal "$cd_pane" "$cd_kind"; then
    printf '  PASS  cooldown=0 disables suppression\n'
  else
    printf '  FAIL  cooldown=0 did not disable suppression\n'
    cd_fails+=("cooldown-zero: should have permitted dispatch")
  fi

  # 4) Aged entry: backdate the stamp past the cooldown window and verify
  #    suppression lifts naturally.
  CODEX_FLEET_DISMISS_COOLDOWN_SECONDS=30
  export CODEX_FLEET_DISMISS_COOLDOWN_SECONDS
  aged_ts=$(( $(date -u +%s) - 31 ))
  record_dismissal "$cd_pane" "$cd_kind" "$aged_ts"
  if should_dispatch_dismissal "$cd_pane" "$cd_kind"; then
    printf '  PASS  aged entry (31s old) lifts suppression\n'
  else
    printf '  FAIL  aged entry (31s old) still suppressing dispatch\n'
    cd_fails+=("aged-entry: should have permitted dispatch")
  fi

  if [ "${#cd_fails[@]}" -gt 0 ]; then
    printf '\nSI-12 cooldown failures:\n'
    for f in "${cd_fails[@]}"; do
      printf '  - %s\n' "$f"
    done
    exit 1
  fi
else
  printf '\nskip: SI-12 cooldown scenario (missing %s or %s)\n' \
    "$(basename "$cooldown_fixture")" "$(basename "$cooldown_label")"
fi

exit 0
