#!/usr/bin/env bash
#
# pr-babysitter — watch CI on fleet PRs and hand failed claims back to the pool.
#
# Failure mode this fixes: when a fleet worker opens a PR and CI fails, today
# the worker has often already moved on to the next claim or exited the pane
# entirely. The original sub-task remains in `completed` (or claimed-but-stale)
# state with a red PR attached to it, and no one picks the failure back up
# until an operator notices manually. This daemon routes those CI failures
# back into the available pool so a fresh worker can pick them up.
#
# Loop (every $PR_BABYSITTER_INTERVAL seconds, default 60):
#   1. Read .codex-fleet/active-plan to resolve the current plan slug.
#      Skip the tick if the file is missing or empty.
#   2. `gh pr list --search '<PR_BABYSITTER_SEARCH>' --state open --json
#      number,headRefName,statusCheckRollup,url,title`
#      (search pattern is in the CONFIG block below — future plans can change
#      it without editing the rest of the script).
#   3. For each PR whose statusCheckRollup contains at least one FAILURE
#      (neutral / skipped / pending / in_progress are treated as non-failing):
#        a. Parse the branch via the BRANCH_REGEX in CONFIG → section + N.
#        b. Look up subtask_index in openspec/plans/<slug>/plan.json by matching
#           the title-tag (`[<SECTION>-<N>]`).
#        c. task_post(kind:'blocker', content:'PR <url> ci-failed: <summary>').
#        d. Increment metadata.retry_count via a counter file under
#           $PR_BABYSITTER_STATE_DIR (Colony does not expose a direct metadata
#           edit; the post above records the count for audit too).
#        e. If retry_count < 3: task_hand_off(to_agent:'any',
#           reason:'ci-failed retry <count>/3') so the claim returns to pool.
#        f. If retry_count >= 3: task_post(kind:'note', content:'pr-babysitter
#           giving up after 3 retries; needs operator') and skip the hand-off.
#   4. Sleep $PR_BABYSITTER_INTERVAL and repeat.
#
# Dry-run mode (`--dry-run <fixture.json>`):
#   - Reads $1 as a JSON file in the same shape gh would return (array of PRs).
#   - Prints the Colony calls that would have been made, one per line, with
#     the prefix `DRYRUN:` for the test harness to grep.
#   - Does not invoke colony or gh; exits 0.
#
# Usage:
#   bash scripts/codex-fleet/pr-babysitter.sh               # loop forever
#   bash scripts/codex-fleet/pr-babysitter.sh --once        # single tick + exit
#   bash scripts/codex-fleet/pr-babysitter.sh --dry-run fx.json
#
# shellcheck disable=SC2155

set -eo pipefail

# ---------------- CONFIG ----------------
# Keep these top-of-file so future plans (e.g. a follow-up "supervisor-extras"
# plan) can re-target the babysitter without touching the rest of the script.
PR_BABYSITTER_SEARCH="${PR_BABYSITTER_SEARCH:-edge- in:title OR si- in:title}"
# Branch regex extracts (section, N) — first capture is the family prefix
# (`edge` or `si`), second is the section tag, third is the numeric index.
# The script uses sections+N to compose the title-tag lookup `[<SECTION>-<N>]`.
PR_BABYSITTER_BRANCH_REGEX="${PR_BABYSITTER_BRANCH_REGEX:-agent/.*/(edge|si)-(te|sp|bk|rk|cm|ma|ni|ns|ra|cv|ex|si)([0-9]+)-}"
PR_BABYSITTER_INTERVAL="${PR_BABYSITTER_INTERVAL:-60}"
PR_BABYSITTER_MAX_RETRIES="${PR_BABYSITTER_MAX_RETRIES:-3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${CODEX_FLEET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
ACTIVE_PLAN_FILE="$REPO_ROOT/.codex-fleet/active-plan"

FLEET_STATE_DIR="${FLEET_STATE_DIR:-/tmp/claude-viz}"
PR_BABYSITTER_STATE_DIR="${PR_BABYSITTER_STATE_DIR:-$FLEET_STATE_DIR/pr-babysitter}"
LOG_FILE="${PR_BABYSITTER_LOG:-$FLEET_STATE_DIR/pr-babysitter.log}"

ONCE=0
DRY_RUN=0
DRY_RUN_FIXTURE=""
DRY_RUN_PLAN_JSON=""

usage() {
  sed -n '1,40p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --dry-run)
      DRY_RUN=1
      DRY_RUN_FIXTURE="${2:-}"
      shift 2 || shift
      ;;
    --dry-run-plan-json)
      # Test hook: override the plan.json path used for title-tag lookup.
      DRY_RUN_PLAN_JSON="${2:-}"
      shift 2
      ;;
    --interval) PR_BABYSITTER_INTERVAL="$2"; shift 2 ;;
    --search) PR_BABYSITTER_SEARCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'pr-babysitter: unknown arg: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$PR_BABYSITTER_STATE_DIR" "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s [pr-babysitter] %s\n' "$ts" "$*" | tee -a "$LOG_FILE" >&2
}

# Counter file per (plan_slug, subtask_index). Stored as a plain integer.
retry_counter_path() {
  local slug="$1" idx="$2"
  printf '%s/%s__%s.count' "$PR_BABYSITTER_STATE_DIR" "$slug" "$idx"
}

retry_count_read() {
  local path="$1"
  if [ -r "$path" ]; then
    local n; n="$(tr -dc '0-9' <"$path" 2>/dev/null || true)"
    printf '%s' "${n:-0}"
  else
    printf '0'
  fi
}

retry_count_increment() {
  local path="$1"
  local cur; cur="$(retry_count_read "$path")"
  local next=$((cur + 1))
  printf '%s\n' "$next" >"$path"
  printf '%s' "$next"
}

# ---------------- plan.json title-tag lookup ----------------
# Given a plan.json path and a tag like "TE-2", emit the matching
# subtask_index. Empty output if no match.
lookup_subtask_index_by_tag() {
  local plan_json="$1" tag="$2"
  [ -r "$plan_json" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  # Match tasks whose title starts with `[<TAG>]` (case-insensitive on the
  # tag prefix because some plans use mixed case).
  jq -r --arg tag "$tag" '
    .tasks // []
    | map(select(.title | test("^\\[" + $tag + "\\]"; "i")))
    | .[0].subtask_index // empty
  ' "$plan_json" 2>/dev/null || true
}

# ---------------- gh PR retrieval ----------------
fetch_open_prs_json() {
  if [ "$DRY_RUN" = "1" ]; then
    if [ -z "$DRY_RUN_FIXTURE" ] || [ ! -r "$DRY_RUN_FIXTURE" ]; then
      log "dry-run: fixture path missing or unreadable: $DRY_RUN_FIXTURE"
      return 1
    fi
    cat "$DRY_RUN_FIXTURE"
    return 0
  fi
  command -v gh >/dev/null 2>&1 || { log "gh CLI absent; cannot fetch PRs"; return 1; }
  gh pr list \
    --search "$PR_BABYSITTER_SEARCH" \
    --state open \
    --json number,headRefName,statusCheckRollup,url,title 2>>"$LOG_FILE"
}

# ---------------- failure detection ----------------
# Reads a single PR's JSON (object) on stdin, emits "FAIL" if any conclusion
# in statusCheckRollup is FAILURE, otherwise emits nothing. Pending / neutral
# / skipped / in_progress are treated as not-failing — only a definitive
# FAILURE conclusion routes a hand-off.
pr_has_failure() {
  jq -r '
    [
      (.statusCheckRollup // [])[]
      | (.conclusion // .state // "")
      | ascii_upcase
    ]
    | any(. == "FAILURE" or . == "FAILED" or . == "TIMED_OUT" or . == "ACTION_REQUIRED")
  '
}

pr_failure_summary() {
  jq -r '
    [
      (.statusCheckRollup // [])[]
      | select(((.conclusion // .state // "") | ascii_upcase) as $c
               | $c == "FAILURE" or $c == "FAILED" or $c == "TIMED_OUT" or $c == "ACTION_REQUIRED")
      | (.name // .context // "check")
    ]
    | join(",")
  '
}

# ---------------- Colony call emission ----------------
# In live mode, invokes the colony CLI. In dry-run, prints DRYRUN: lines.
emit_task_post() {
  local task_ref="$1" kind="$2" content="$3"
  if [ "$DRY_RUN" = "1" ]; then
    printf 'DRYRUN: colony task_post --task %s --kind %s --content %q\n' \
      "$task_ref" "$kind" "$content"
    return 0
  fi
  if command -v colony >/dev/null 2>&1; then
    colony task_post --task "$task_ref" --kind "$kind" --content "$content" \
      >/dev/null 2>>"$LOG_FILE" \
      || log "colony task_post failed for task=$task_ref kind=$kind (continuing)"
  else
    log "colony CLI absent; would task_post task=$task_ref kind=$kind"
  fi
}

emit_task_hand_off() {
  local task_ref="$1" reason="$2"
  if [ "$DRY_RUN" = "1" ]; then
    printf 'DRYRUN: colony task_hand_off --task %s --to-agent any --reason %q\n' \
      "$task_ref" "$reason"
    return 0
  fi
  if command -v colony >/dev/null 2>&1; then
    colony task_hand_off --task "$task_ref" --to-agent any --reason "$reason" \
      >/dev/null 2>>"$LOG_FILE" \
      || log "colony task_hand_off failed for task=$task_ref (continuing)"
  else
    log "colony CLI absent; would task_hand_off task=$task_ref reason=$reason"
  fi
}

# ---------------- per-PR processing ----------------
process_failed_pr() {
  local pr_json="$1" plan_slug="$2" plan_json="$3"
  local number url branch title
  number="$(printf '%s' "$pr_json" | jq -r '.number // empty')"
  url="$(printf '%s' "$pr_json" | jq -r '.url // empty')"
  branch="$(printf '%s' "$pr_json" | jq -r '.headRefName // empty')"
  title="$(printf '%s' "$pr_json" | jq -r '.title // empty')"

  local section_lower="" section_num=""
  if [[ "$branch" =~ $PR_BABYSITTER_BRANCH_REGEX ]]; then
    section_lower="${BASH_REMATCH[2]}"
    section_num="${BASH_REMATCH[3]}"
  fi
  if [ -z "$section_lower" ] || [ -z "$section_num" ]; then
    log "skip pr#$number: branch '$branch' does not match babysitter regex"
    return 0
  fi
  local tag_upper
  tag_upper="$(printf '%s-%s' "$section_lower" "$section_num" | tr '[:lower:]' '[:upper:]')"

  local subtask_idx
  subtask_idx="$(lookup_subtask_index_by_tag "$plan_json" "$tag_upper")"
  if [ -z "$subtask_idx" ]; then
    log "skip pr#$number: no subtask in $plan_slug matches tag [$tag_upper]"
    return 0
  fi

  local summary; summary="$(printf '%s' "$pr_json" | pr_failure_summary)"
  local task_ref="$plan_slug#$subtask_idx"
  local count_path; count_path="$(retry_counter_path "$plan_slug" "$subtask_idx")"
  local prior_count; prior_count="$(retry_count_read "$count_path")"
  local count
  if [ "$DRY_RUN" = "1" ]; then
    # In dry-run, do not mutate counter state — simulate prior+1.
    count=$((prior_count + 1))
  else
    count="$(retry_count_increment "$count_path")"
  fi

  log "fail pr#$number branch=$branch tag=[$tag_upper] subtask=$subtask_idx retry=$count/$PR_BABYSITTER_MAX_RETRIES checks=$summary"

  emit_task_post "$task_ref" "blocker" \
    "PR $url ci-failed (retry $count/$PR_BABYSITTER_MAX_RETRIES): $summary"

  if [ "$count" -lt "$PR_BABYSITTER_MAX_RETRIES" ]; then
    emit_task_hand_off "$task_ref" "ci-failed retry $count/$PR_BABYSITTER_MAX_RETRIES"
  else
    emit_task_post "$task_ref" "note" \
      "pr-babysitter giving up after $PR_BABYSITTER_MAX_RETRIES retries; needs operator"
    log "give-up pr#$number subtask=$subtask_idx (>= $PR_BABYSITTER_MAX_RETRIES retries)"
  fi
}

resolve_active_plan() {
  if [ "$DRY_RUN" = "1" ] && [ -n "$DRY_RUN_PLAN_JSON" ]; then
    # Caller supplied a plan.json directly; derive a synthetic slug from
    # its parent dir name.
    local pj="$DRY_RUN_PLAN_JSON"
    local slug; slug="$(basename "$(dirname "$pj")")"
    printf '%s\t%s\n' "$slug" "$pj"
    return 0
  fi
  if [ ! -r "$ACTIVE_PLAN_FILE" ]; then
    return 1
  fi
  local slug; slug="$(tr -d '[:space:]' <"$ACTIVE_PLAN_FILE")"
  [ -n "$slug" ] || return 1
  printf '%s\t%s\n' "$slug" "$REPO_ROOT/openspec/plans/$slug/plan.json"
}

tick() {
  local resolved
  if ! resolved="$(resolve_active_plan)"; then
    log "no active plan; skipping tick"
    return 0
  fi
  local plan_slug plan_json
  plan_slug="$(printf '%s' "$resolved" | cut -f1)"
  plan_json="$(printf '%s' "$resolved" | cut -f2)"

  if ! command -v jq >/dev/null 2>&1; then
    log "jq absent; cannot parse PR JSON"
    return 0
  fi

  local prs_json
  if ! prs_json="$(fetch_open_prs_json)"; then
    log "fetch_open_prs_json failed; skipping tick"
    return 0
  fi
  if [ -z "$prs_json" ]; then
    log "no open PRs returned"
    return 0
  fi

  # Iterate each PR as a compact JSON object. Use a process-substitution
  # while-read loop so the body runs in the current shell (not a subshell)
  # — important if we ever start tracking per-tick counters in shell vars.
  local processed=0 failed=0
  while IFS= read -r pr_obj; do
    [ -n "$pr_obj" ] || continue
    processed=$((processed + 1))
    local has_fail
    has_fail="$(printf '%s' "$pr_obj" | pr_has_failure)"
    if [ "$has_fail" = "true" ]; then
      failed=$((failed + 1))
      process_failed_pr "$pr_obj" "$plan_slug" "$plan_json"
    fi
  done < <(printf '%s' "$prs_json" | jq -c '.[]?')

  log "tick complete plan=$plan_slug processed=$processed failed=$failed"
}

log "starting (interval=${PR_BABYSITTER_INTERVAL}s search=\"$PR_BABYSITTER_SEARCH\" max_retries=$PR_BABYSITTER_MAX_RETRIES dry_run=$DRY_RUN)"

if [ "$DRY_RUN" = "1" ]; then
  tick
  exit 0
fi

if [ "$ONCE" = "1" ]; then
  tick
  exit 0
fi

while :; do
  tick || true
  sleep "$PR_BABYSITTER_INTERVAL"
done
