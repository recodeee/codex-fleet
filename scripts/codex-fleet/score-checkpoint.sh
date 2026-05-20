#!/usr/bin/env bash
# score-checkpoint.sh — improvement #3's checkpoint half: scan active
# Guardex agent worktrees, score each one's *uncommitted* diff against
# its plan's acceptance criteria, write per-agent results to
# /tmp/claude-viz/fleet-checkpoint-warnings.json.
#
# Runs against the SAME lib/score-diff.py primitive as the merged-PR
# scorer (improvement #1) — only the inputs and sink differ. That keeps
# the LLM-call surface single-sourced and means a prompt tweak for one
# improves both.
#
# The output is intended for a checkpoint dashboard (or, eventually, a
# colony task_post blocker when score < threshold). This script is the
# data-layer half; the consumer side lives in a follow-up PR.
#
# Usage:
#   ./scripts/codex-fleet/score-checkpoint.sh         # scan all active worktrees
#   ./scripts/codex-fleet/score-checkpoint.sh <path>  # score a single worktree
#
# Env:
#   ANTHROPIC_API_KEY  required (consumed by lib/score-diff.py)
#   CODEX_FLEET_CHECKPOINT_PATH  override sink (default: /tmp/claude-viz/fleet-checkpoint-warnings.json)
#   CODEX_FLEET_REPO_ROOT  override repo root (default: git toplevel)
#
# Cron / loop pattern (typical):
#   */15 * * * * cd $REPO_ROOT && ./scripts/codex-fleet/score-checkpoint.sh

set -euo pipefail

# --help / --version plumbing (see lib/version.sh).
FLEET_USAGE="score-checkpoint.sh — score uncommitted diffs in active Guardex
agent worktrees against their plan's acceptance criteria.

Usage:
  ./scripts/codex-fleet/score-checkpoint.sh                 # scan all active worktrees
  ./scripts/codex-fleet/score-checkpoint.sh <worktree>      # score a single worktree
  ./scripts/codex-fleet/score-checkpoint.sh --help | --version

Env:
  ANTHROPIC_API_KEY               required (consumed by lib/score-diff.py)
  CODEX_FLEET_CHECKPOINT_PATH     sink path (default /tmp/claude-viz/fleet-checkpoint-warnings.json)
  CODEX_FLEET_REPO_ROOT           repo root (default: git toplevel)

Flags:
  -h, --help                      print this help and exit 0
  --version                       print '<basename> <FLEET_VERSION>' and exit 0"
source "$(dirname "${BASH_SOURCE[0]}")/lib/version.sh"
handle_help_version_flags "$@"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCORER="$SCRIPT_DIR/lib/score-diff.py"
REPO_ROOT="${CODEX_FLEET_REPO_ROOT:-$(git rev-parse --show-toplevel)}"
SINK_PATH="${CODEX_FLEET_CHECKPOINT_PATH:-/tmp/claude-viz/fleet-checkpoint-warnings.json}"

mkdir -p "$(dirname "$SINK_PATH")"

score_worktree() {
  local wt="$1"
  local branch agent_id head_diff

  if [[ ! -d "$wt/.git" && ! -f "$wt/.git" ]]; then
    return 0  # not a git worktree, skip silently
  fi

  branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -z "$branch" || "$branch" == HEAD ]]; then
    return 0  # detached or broken; skip
  fi

  agent_id=$(echo "$branch" | awk -F/ '/^agent\// {print $2; exit} {print $0}')

  # Live diff: everything since the worktree's branch point on main. This
  # mirrors what a "show me what this agent has changed so far" check
  # would compute. If main isn't fetched, fall back to the index diff.
  head_diff=$(git -C "$wt" diff origin/main..HEAD -- 2>/dev/null || true)
  if [[ -z "$head_diff" ]]; then
    head_diff=$(git -C "$wt" diff HEAD -- 2>/dev/null || true)
  fi
  if [[ -z "$head_diff" ]]; then
    return 0  # nothing to score yet
  fi

  # Locate plan.md by branch-slug match (same lookup as score-merged-pr.sh).
  local criteria="" plan_slug="null"
  while IFS= read -r plan_md; do
    local slug
    slug=$(basename "$(dirname "$plan_md")")
    if echo "$branch" | grep -qF "$slug"; then
      criteria=$(awk '
        /^## Acceptance Criteria/ { capture=1; next }
        capture && /^## / { exit }
        capture { print }
      ' "$plan_md")
      plan_slug="\"$slug\""
      break
    fi
  done < <(find "$REPO_ROOT/openspec/plans" -maxdepth 2 -name plan.md 2>/dev/null)

  local verdict
  verdict=$(
    jq -n \
      --arg diff "$head_diff" \
      --arg criteria "$criteria" \
      --arg title "$branch" \
      --arg mode "checkpoint" \
      '{diff: $diff, criteria: $criteria, pr_title: $title, mode: $mode}' \
    | python3 "$SCORER"
  ) || {
    echo "score-checkpoint.sh: scorer failed for $wt; skipping." >&2
    return 0
  }

  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Print one JSON object per worktree, one line. The caller `jq -s` folds
  # them into the final sink.
  jq -n \
    --arg agent_id "$agent_id" \
    --arg branch "$branch" \
    --arg worktree "$wt" \
    --arg now "$now" \
    --argjson plan_slug "$plan_slug" \
    --argjson verdict "$verdict" \
    '{
      agent_id: $agent_id,
      branch: $branch,
      worktree: $worktree,
      plan_slug: $plan_slug,
      scored_at: $now,
      verdict: $verdict
    }'
}

# Choose which worktrees to score.
results=()
if [[ $# -ge 1 ]]; then
  results+=("$(score_worktree "$1" || true)")
else
  shopt -s nullglob
  for wt in "$REPO_ROOT"/.omc/agent-worktrees/*; do
    [[ -d "$wt" ]] || continue
    result=$(score_worktree "$wt" || true)
    [[ -n "$result" ]] && results+=("$result")
  done
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
COMBINED=$(
  printf '%s\n' "${results[@]}" \
  | jq -s --arg now "$NOW" '{
      generated_at: $now,
      warnings: map({key: .agent_id, value: .}) | from_entries
    }'
)

TMP=$(mktemp)
echo "$COMBINED" > "$TMP"
mv "$TMP" "$SINK_PATH"
echo "score-checkpoint.sh: wrote ${#results[@]} verdicts to $SINK_PATH"
