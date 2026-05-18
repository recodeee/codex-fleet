#!/usr/bin/env bash
# shellcheck shell=bash
#
# wake-prompt-templater — SI-19 daemon
#
# Every 30 seconds:
#   1. Read .codex-fleet/active-plan to resolve the priority plan slug.
#   2. Call `colony task ready --json` with --null-agent / no-agent to
#      preview the next claimable subtask without claiming it.
#   3. Substitute {{PLAN_SLUG}}, {{SUBTASK_INDEX}}, {{NEXT_TITLE}},
#      {{NEXT_DESCRIPTION}}, {{EXHAUSTED_NOTICE}} into
#      scripts/codex-fleet/wake-prompt.template.md.
#   4. Atomically rename the rendered file to /tmp/codex-fleet-wake-prompt.md.
#
# Why: bringup captures a single snapshot of the wake prompt at fleet
# start and panes re-read that snapshot every loop iteration. When the
# referenced subtask has already merged, the prompt keeps pointing
# workers at a long-gone task (observed 2026-05-18: all 8 panes still
# named TE-2 hours after TE-2 landed). This daemon makes the wake
# prompt live.
#
# Env knobs:
#   WAKE_TEMPLATE_PATH  override template path (default: sibling .template.md)
#   WAKE_OUTPUT_PATH    override output path (default: /tmp/codex-fleet-wake-prompt.md)
#   WAKE_INTERVAL_SEC   loop interval seconds (default: 30)
#   WAKE_ONCE           if set to 1, run a single iteration and exit
#   WAKE_COLONY_BIN     override colony CLI path (test-mode mock injection)
#   CODEX_FLEET_REPO_ROOT
#                       repo to read .codex-fleet/active-plan from
#
# Exits cleanly on SIGTERM / SIGINT.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CODEX_FLEET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

TEMPLATE_PATH="${WAKE_TEMPLATE_PATH:-$SCRIPT_DIR/wake-prompt.template.md}"
OUTPUT_PATH="${WAKE_OUTPUT_PATH:-/tmp/codex-fleet-wake-prompt.md}"
INTERVAL_SEC="${WAKE_INTERVAL_SEC:-30}"
COLONY_BIN="${WAKE_COLONY_BIN:-colony}"

log() { printf '[wake-prompt-templater] %s\n' "$*"; }
warn() { printf '[wake-prompt-templater] WARN: %s\n' "$*" >&2; }

stop_requested=0
on_signal() {
  stop_requested=1
}
trap on_signal TERM INT

# active_plan_slug — strip whitespace from .codex-fleet/active-plan.
# Echoes empty when the pointer is missing/blank.
active_plan_slug() {
  local f="$REPO_ROOT/.codex-fleet/active-plan"
  [ -f "$f" ] || { printf ''; return 0; }
  tr -d '[:space:]' < "$f" 2>/dev/null || true
}

# fetch_next_subtask <plan_slug>
#
# Calls `colony task ready --json --limit 1` and emits a TSV row of
# `idx<TAB>title<TAB>description` for the first ready subtask whose
# plan_slug matches the argument. Echoes empty on any error / no match
# / no colony binary so the caller renders the EXHAUSTED variant.
fetch_next_subtask() {
  local slug="$1"
  command -v "$COLONY_BIN" >/dev/null 2>&1 || { printf ''; return 0; }

  local raw
  raw="$("$COLONY_BIN" task ready --json --limit 5 --agent claude 2>/dev/null || true)"
  [ -n "$raw" ] || { printf ''; return 0; }

  # Pass the JSON payload via env var, not stdin: the heredoc to python's
  # `python3 -` already occupies stdin and would clobber a piped payload.
  RAW="$raw" SLUG="$slug" python3 - <<'PY' 2>/dev/null || true
import json, os
slug = os.environ.get("SLUG", "")
raw  = os.environ.get("RAW",  "")
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(0)
ready = data.get("ready") or []
if isinstance(data.get("task_ready"), list) and not ready:
    ready = data["task_ready"]
for item in ready:
    if not isinstance(item, dict):
        continue
    item_slug = item.get("plan_slug") or (item.get("plan") or {}).get("slug") or ""
    if slug and item_slug and item_slug != slug:
        continue
    idx = item.get("subtask_index")
    if idx is None:
        idx = item.get("sub_idx")
    if idx is None:
        continue
    title = (item.get("title") or "").replace("\t", " ").replace("\n", " ").strip()
    desc = (item.get("description") or "").replace("\t", " ").replace("\n", " ").strip()
    # cap description to keep the wake prompt readable
    if len(desc) > 600:
        desc = desc[:600].rstrip() + "..."
    print(f"{idx}\t{title}\t{desc}")
    break
PY
}

# render_template <slug> <idx> <title> <desc> <exhausted_notice>
#
# Atomically writes the substituted template to OUTPUT_PATH. Uses
# `mv` from a tmp file in the same directory so a concurrent reader
# never observes a partial write.
render_template() {
  local slug="$1" idx="$2" title="$3" desc="$4" notice="$5"

  [ -r "$TEMPLATE_PATH" ] || { warn "template not readable: $TEMPLATE_PATH"; return 1; }

  local out_dir
  out_dir="$(dirname "$OUTPUT_PATH")"
  mkdir -p "$out_dir" 2>/dev/null || true
  local tmp_path
  tmp_path="$(mktemp "${OUTPUT_PATH}.tmp.XXXXXX")" || return 1

  # Substitute via python so multi-line {{NEXT_DESCRIPTION}} values and
  # any sed-special chars (& / [ ]) survive intact. Values are passed
  # via env vars to avoid argv-length or quoting hazards.
  if ! TEMPLATE="$TEMPLATE_PATH" \
       OUT="$tmp_path" \
       SLUG="$slug" \
       IDX="$idx" \
       TITLE="$title" \
       DESC="$desc" \
       NOTICE="$notice" \
       python3 - <<'PY'
import os
with open(os.environ["TEMPLATE"]) as f:
    body = f.read()
body = body.replace("{{PLAN_SLUG}}",       os.environ.get("SLUG", ""))
body = body.replace("{{SUBTASK_INDEX}}",   os.environ.get("IDX", ""))
body = body.replace("{{NEXT_TITLE}}",      os.environ.get("TITLE", ""))
body = body.replace("{{NEXT_DESCRIPTION}}",os.environ.get("DESC", ""))
body = body.replace("{{EXHAUSTED_NOTICE}}",os.environ.get("NOTICE", ""))
with open(os.environ["OUT"], "w") as f:
    f.write(body)
PY
  then
    rm -f "$tmp_path"
    return 1
  fi

  mv "$tmp_path" "$OUTPUT_PATH" || { rm -f "$tmp_path"; return 1; }
  return 0
}

# render_once — one templater tick. Returns 0 always so the daemon loop
# survives transient failures (missing colony, missing active-plan).
render_once() {
  local slug idx title desc notice row
  slug="$(active_plan_slug)"

  if [ -z "$slug" ]; then
    notice="> NOTE: no active plan (.codex-fleet/active-plan missing or"
    notice="$notice empty). Waiting for the operator to pin a priority plan."
    render_template "" "" "(no active plan)" "(no description available)" "$notice" \
      || warn "render failed (no active plan)"
    return 0
  fi

  row="$(fetch_next_subtask "$slug")"
  if [ -z "$row" ]; then
    notice="> NOTE: plan-exhausted — Colony reports no claimable subtasks"
    notice="$notice for \`$slug\`. Workers should standby; await operator."
    render_template "$slug" "" "(no available subtask)" "(no description available)" "$notice" \
      || warn "render failed (exhausted variant)"
    return 0
  fi

  IFS=$'\t' read -r idx title desc <<< "$row"
  [ -n "$title" ] || title="(untitled)"
  [ -n "$desc" ]  || desc="(no description)"
  render_template "$slug" "$idx" "$title" "$desc" "" \
    || warn "render failed (live variant)"
  return 0
}

main() {
  if [ "${WAKE_ONCE:-0}" = "1" ]; then
    render_once
    return 0
  fi

  log "starting (interval=${INTERVAL_SEC}s template=$TEMPLATE_PATH output=$OUTPUT_PATH)"
  while [ "$stop_requested" -eq 0 ]; do
    render_once
    # Sleep in 1s slices so SIGTERM is observed within ~1s instead of waiting
    # for the full 30s interval.
    local waited=0
    while [ "$waited" -lt "$INTERVAL_SEC" ] && [ "$stop_requested" -eq 0 ]; do
      sleep 1
      waited=$((waited + 1))
    done
  done
  log "stop requested; exiting"
  return 0
}

main "$@"
