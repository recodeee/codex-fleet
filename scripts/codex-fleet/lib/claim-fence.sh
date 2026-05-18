#!/usr/bin/env bash
# claim-fence — 5-second pre-claim staleness fence for Colony sub-tasks.
#
# Why this exists:
#   On 2026-05-18 03:30 UTC+2 we observed three codex panes attempting to
#   claim the same TE-2 sub-task simultaneously. All three were stuck on
#   codex-CLI's "Create a plan?" prompt when force-claim.sh dispatched, and
#   Colony hadn't recorded the first pane's claim before the others issued
#   their own task_plan_claim_subtask calls. The fence prevents this: when
#   a worker (or dispatcher) sees a sub-task as `available`, it waits N
#   seconds (default 5) and re-checks before issuing the claim RPC.
#
# Read model:
#   plan.json on disk is the source of truth for fleet-side `status` /
#   `claimed_by_agent` reads — the same file every other fleet script reads
#   (see plan-watcher.sh:next_available_subtask, force-claim.sh:ready_tasks_all,
#   claim-release-supervisor.sh:claims_for_agent). The colony plan status
#   CLI does not expose per-sub-task claim state in its current form. We
#   honor that pattern here rather than introduce a new read path.
#
# Usage (sourced):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/claim-fence.sh"
#   if claim_fence_check "$plan_slug" "$sub_idx"; then
#     # safe to issue task_plan_claim_subtask
#   else
#     # someone else has it (or raced us during the fence window) — skip
#   fi
#
# Usage (CLI):
#   bash scripts/codex-fleet/lib/claim-fence.sh check <plan-slug> <sub-idx>
#   exit 0 = safe to claim, non-zero = unavailable / raced.
#
# Environment:
#   CODEX_FLEET_CLAIM_FENCE_SECONDS  fence sleep in seconds (default: 5)
#   CODEX_FLEET_REPO_ROOT            repo root (default: autodetect)
#   CODEX_FLEET_PLAN_JSON            override path to plan.json (test hook)
#   CLAIM_FENCE_QUERY_OVERRIDE       path to an executable that prints
#                                    "<status>\t<claimed_by_agent>" for
#                                    "<plan_slug> <sub_idx>" on stdin
#                                    (used by the race-test fixture; the
#                                    production path reads plan.json).
#
# Exit codes (CLI mode):
#   0  safe to claim — status was `available` both before and after fence.
#   1  not available — initial status is not `available`.
#   2  raced — status was `available` initially but became non-available
#      during the fence window.
#   3  read error — plan.json missing / unparseable / sub-task not found.
#   4  usage error.

# Guard against multi-source.
if [[ -n "${_CLAIM_FENCE_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_CLAIM_FENCE_SOURCED=1

# Locate this script's directory (resolving symlinks) so we can find a
# default plan.json relative to the repo root.
_CLAIM_FENCE_SRC="${BASH_SOURCE[0]}"
while [[ -L "$_CLAIM_FENCE_SRC" ]]; do
  _CLAIM_FENCE_DIR="$(cd -P -- "$(dirname -- "$_CLAIM_FENCE_SRC")" && pwd)"
  _CLAIM_FENCE_NEXT="$(readlink "$_CLAIM_FENCE_SRC")"
  case "$_CLAIM_FENCE_NEXT" in
    /*) _CLAIM_FENCE_SRC="$_CLAIM_FENCE_NEXT" ;;
     *) _CLAIM_FENCE_SRC="$_CLAIM_FENCE_DIR/$_CLAIM_FENCE_NEXT" ;;
  esac
done
_CLAIM_FENCE_DIR="$(cd -P -- "$(dirname -- "$_CLAIM_FENCE_SRC")" && pwd)"

# Resolve the repo root: env override > autodetect (lib/.. = scripts/codex-fleet,
# .. = scripts, .. = repo root).
: "${CODEX_FLEET_REPO_ROOT:=$(cd "$_CLAIM_FENCE_DIR/../../.." && pwd)}"

# claim_fence_query — emit "<status>\t<claimed_by_agent>" for the requested
# (plan_slug, sub_idx). Used by claim_fence_check. Honors:
#   - CLAIM_FENCE_QUERY_OVERRIDE (test hook; called as
#     "$override <plan_slug> <sub_idx>" — must print TSV on stdout, exit 0)
#   - CODEX_FLEET_PLAN_JSON (explicit plan.json path; takes precedence over
#     the per-slug lookup; useful when callers already know the path)
#   - default: $CODEX_FLEET_REPO_ROOT/openspec/plans/<slug>/plan.json
#
# Returns:
#   exit 0 + TSV stdout on success
#   exit 3 on read error (plan missing, sub-task not found, JSON malformed)
claim_fence_query() {
  local plan_slug="$1" sub_idx="$2"

  if [[ -n "${CLAIM_FENCE_QUERY_OVERRIDE:-}" ]]; then
    if [[ ! -x "$CLAIM_FENCE_QUERY_OVERRIDE" ]]; then
      printf 'claim-fence: CLAIM_FENCE_QUERY_OVERRIDE=%s not executable\n' \
        "$CLAIM_FENCE_QUERY_OVERRIDE" >&2
      return 3
    fi
    local out
    if ! out="$("$CLAIM_FENCE_QUERY_OVERRIDE" "$plan_slug" "$sub_idx" 2>/dev/null)"; then
      return 3
    fi
    [[ -z "$out" ]] && return 3
    printf '%s\n' "$out"
    return 0
  fi

  local plan_json="${CODEX_FLEET_PLAN_JSON:-$CODEX_FLEET_REPO_ROOT/openspec/plans/$plan_slug/plan.json}"
  if [[ ! -f "$plan_json" ]]; then
    printf 'claim-fence: plan.json not found at %s\n' "$plan_json" >&2
    return 3
  fi

  PLAN_JSON="$plan_json" SUB_IDX="$sub_idx" python3 - <<'PY' || return 3
import json, os, sys
plan_json = os.environ["PLAN_JSON"]
try:
    sub_idx = int(os.environ["SUB_IDX"])
except ValueError:
    sys.stderr.write(f"claim-fence: invalid sub_idx {os.environ['SUB_IDX']!r}\n")
    sys.exit(3)
try:
    with open(plan_json) as fh:
        plan = json.load(fh)
except Exception as exc:
    sys.stderr.write(f"claim-fence: failed to read {plan_json}: {exc}\n")
    sys.exit(3)
for task in plan.get("tasks", []) or []:
    if task.get("subtask_index") == sub_idx:
        status = (task.get("status") or "available")
        claimed = (task.get("claimed_by_agent") or "")
        # TSV: status \t claimed_by_agent
        print(f"{status}\t{claimed}")
        sys.exit(0)
sys.stderr.write(f"claim-fence: sub_idx {sub_idx} not found in {plan_json}\n")
sys.exit(3)
PY
}

# claim_fence_check <plan-slug> <sub-idx>
#   exit 0 — sub-task was `available` before AND after the fence window.
#            Caller may proceed with task_plan_claim_subtask.
#   exit 1 — sub-task is not `available` at first read. Someone has it.
#   exit 2 — race: was `available` initially but no longer `available` after
#            the fence. Another worker beat us. Caller must skip this iter.
#   exit 3 — read error (see claim_fence_query). Treat as not-safe (caller
#            should skip and retry on next pass).
#   exit 4 — usage error.
claim_fence_check() {
  local plan_slug="${1:-}" sub_idx="${2:-}"
  if [[ -z "$plan_slug" || -z "$sub_idx" ]]; then
    printf 'claim_fence_check: usage: claim_fence_check <plan-slug> <sub-idx>\n' >&2
    return 4
  fi

  local fence="${CODEX_FLEET_CLAIM_FENCE_SECONDS:-5}"
  # Validate fence is a non-negative integer; default to 5 on anything weird
  # (operators occasionally export the var as "" or "5s"; we don't want to
  # blow up the dispatcher on a typo).
  if ! [[ "$fence" =~ ^[0-9]+$ ]]; then
    printf 'claim-fence: invalid CODEX_FLEET_CLAIM_FENCE_SECONDS=%q; falling back to 5\n' \
      "$fence" >&2
    fence=5
  fi

  local before after status1 claimed1 status2 claimed2
  if ! before="$(claim_fence_query "$plan_slug" "$sub_idx")"; then
    return 3
  fi
  IFS=$'\t' read -r status1 claimed1 <<<"$before"
  if [[ "$status1" != "available" ]]; then
    printf 'claim-fence: %s/sub-%s not available (status=%s claimed_by=%s); skipping\n' \
      "$plan_slug" "$sub_idx" "${status1:-?}" "${claimed1:-?}" >&2
    return 1
  fi

  # Sleep the fence window. `sleep 0` is a valid no-op and lets tests
  # short-circuit the wait.
  sleep "$fence"

  if ! after="$(claim_fence_query "$plan_slug" "$sub_idx")"; then
    return 3
  fi
  IFS=$'\t' read -r status2 claimed2 <<<"$after"
  if [[ "$status2" != "available" ]]; then
    printf 'claim-fence: race on %s/sub-%s — status flipped to %s (claimed_by=%s) during %ss fence; skipping\n' \
      "$plan_slug" "$sub_idx" "${status2:-?}" "${claimed2:-?}" "$fence" >&2
    return 2
  fi

  return 0
}

# claim_fence_check_held_by <plan-slug> <sub-idx> <agent>
#   Variant for claim-release-supervisor.sh: returns 0 only when the
#   sub-task is `claimed` by <agent> BOTH before and after the fence window.
#   This guards against releasing a claim that the worker just transitioned
#   to `completed` mid-pass (cheap stat() race we observed on the same
#   2026-05-18 supervisor run that motivated the primary fence).
#
#   exit 0 — held by <agent> before AND after; safe to release.
#   exit 1 — not held by <agent> at first read (someone else / completed).
#   exit 2 — race: held by <agent> initially but flipped during the fence.
#   exit 3 — read error.
#   exit 4 — usage error.
claim_fence_check_held_by() {
  local plan_slug="${1:-}" sub_idx="${2:-}" agent="${3:-}"
  if [[ -z "$plan_slug" || -z "$sub_idx" || -z "$agent" ]]; then
    printf 'claim_fence_check_held_by: usage: <plan-slug> <sub-idx> <agent>\n' >&2
    return 4
  fi

  local fence="${CODEX_FLEET_CLAIM_FENCE_SECONDS:-5}"
  if ! [[ "$fence" =~ ^[0-9]+$ ]]; then
    fence=5
  fi

  local before after status1 claimed1 status2 claimed2
  if ! before="$(claim_fence_query "$plan_slug" "$sub_idx")"; then
    return 3
  fi
  IFS=$'\t' read -r status1 claimed1 <<<"$before"
  if [[ "$status1" != "claimed" || "$claimed1" != "$agent" ]]; then
    printf 'claim-fence: %s/sub-%s not held by %s (status=%s claimed_by=%s); skipping\n' \
      "$plan_slug" "$sub_idx" "$agent" "${status1:-?}" "${claimed1:-?}" >&2
    return 1
  fi

  sleep "$fence"

  if ! after="$(claim_fence_query "$plan_slug" "$sub_idx")"; then
    return 3
  fi
  IFS=$'\t' read -r status2 claimed2 <<<"$after"
  if [[ "$status2" != "claimed" || "$claimed2" != "$agent" ]]; then
    printf 'claim-fence: race on %s/sub-%s — flipped to status=%s claimed_by=%s during %ss fence; skipping\n' \
      "$plan_slug" "$sub_idx" "${status2:-?}" "${claimed2:-?}" "$fence" >&2
    return 2
  fi

  return 0
}

# CLI shim — `bash claim-fence.sh check <slug> <idx>` mirrors the function.
# Allows scripts to call the fence without sourcing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    check)
      shift
      claim_fence_check "$@"
      exit $?
      ;;
    check-held-by)
      shift
      claim_fence_check_held_by "$@"
      exit $?
      ;;
    query)
      shift
      claim_fence_query "$@"
      exit $?
      ;;
    "")
      printf 'claim-fence: usage: %s check <plan-slug> <sub-idx>\n' "$0" >&2
      exit 4
      ;;
    *)
      printf 'claim-fence: unknown subcommand %q (expected: check, check-held-by, query)\n' "$1" >&2
      exit 4
      ;;
  esac
fi
