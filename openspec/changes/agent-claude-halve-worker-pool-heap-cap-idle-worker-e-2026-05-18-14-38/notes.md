# agent-claude-halve-worker-pool-heap-cap-idle-worker-e-2026-05-18-14-38 (minimal / T1)

Branch: `agent/claude/halve-worker-pool-heap-cap-idle-worker-e-2026-05-18-14-38`

## Why

The codex-fleet currently holds ~10 GB of resident memory (16 codex CLIs
+ 258 node helper procs, observed via `ps -C codex -o rss`). Each codex
CLI is a native binary with ~200-400 MB of heap that does NOT shrink
while idle. Even when the plan is `plan-exhausted` and every worker is
in `sleep 60`, the native heap stays resident.

## What

Three changes, all in `scripts/codex-fleet/`:

1. `codex-fleet-2.sh` — worker count is now `WORKER_COUNT` env (default
   **4**, was **8**). Spawn loop driven by the env. The full
   `RESERVE_ACCOUNTS` array stays as the upper bound; bump by setting
   `WORKER_COUNT=8` for heavy plans.
2. `codex-fleet-2.sh` — `worker_cmd_for()` now exports
   `NODE_OPTIONS=--max-old-space-size=400` so any Node MCP-server child
   codex spawns is capped. (codex itself is native; the flag does not
   apply to its own heap.)
3. `worker-prompt.md` — added `empty_streak` counter to the worker
   loop. After 5 consecutive `plan-exhausted` polls (~5 min idle), the
   worker posts a Colony note and exits with status 0. Supervisor
   respawns it when Colony reports new claimable work for the account.
   Override per-pane via `IDLE_EXIT_THRESHOLD=0`.

## Expected impact

| Metric | Before | After |
| --- | --- | --- |
| Workers spawned at bringup | 8 | 4 |
| Idle floor when plan exhausted | ~2 GB | near 0 |
| Active-work peak | ~10 GB | ~5 GB |
| Node MCP child heap cap | unbounded | 400 MB |

## Handoff

- Handoff: change=`agent-claude-halve-worker-pool-heap-cap-idle-worker-e-2026-05-18-14-38`; branch=`agent/claude/halve-worker-pool-heap-cap-idle-worker-e-2026-05-18-14-38`; scope=`codex-fleet-2.sh + worker-prompt.md`; action=`finish via PR`.

## Cleanup

- [ ] Run: `gx branch finish --branch agent/claude/halve-worker-pool-heap-cap-idle-worker-e-2026-05-18-14-38 --base main --via-pr --wait-for-merge --cleanup`
- [ ] Tear down + bring up the fleet to pick up the new defaults:
      `bash scripts/codex-fleet/down.sh && bash scripts/codex-fleet/full-bringup.sh ...`
- [ ] Record PR URL + `MERGED` state in the completion handoff.
- [ ] Confirm sandbox worktree is gone (`git worktree list`, `git branch -a`).
