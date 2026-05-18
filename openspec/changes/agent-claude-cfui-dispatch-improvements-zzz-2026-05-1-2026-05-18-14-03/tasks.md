## Definition of Done

This change is complete only when **all** of the following are true:

- Every checkbox below is checked.
- The agent branch reaches `MERGED` state on `origin` and the PR URL + state are recorded in the completion handoff.
- If any step blocks (test failure, conflict, ambiguous result), append a `BLOCKED:` line under section 4 explaining the blocker and **STOP**. Do not tick remaining cleanup boxes; do not silently skip the cleanup pipeline.

## Handoff

- Handoff: change=`agent-claude-cfui-dispatch-improvements-zzz-2026-05-1-2026-05-18-14-03`; branch=`agent/<your-name>/<branch-slug>`; scope=`TODO`; action=`continue this sandbox or finish cleanup after a usage-limit/manual takeover`.
- Copy prompt: Continue `agent-claude-cfui-dispatch-improvements-zzz-2026-05-1-2026-05-18-14-03` on branch `agent/<your-name>/<branch-slug>`. Work inside the existing sandbox, review `openspec/changes/agent-claude-cfui-dispatch-improvements-zzz-2026-05-1-2026-05-18-14-03/tasks.md`, continue from the current state instead of creating a new sandbox, and when the work is done run `gx branch finish --branch agent/<your-name>/<branch-slug> --base dev --via-pr --wait-for-merge --cleanup`.

## 1. Specification

- [x] 1.1 Proposal scope and acceptance criteria captured in `proposal.md` (6 findings F1–F6 with reproduction evidence from the 2026-05-18 marketing-content-waves fleet run).
- [ ] 1.2 Define normative requirements in `specs/cfui-dispatch-improvements-zzz-2026-05-18/spec.md` (one per finding, with response-shape / state-machine contract).

## 2. Implementation

Owned by 6 fleet subtasks in `openspec/plans/fleet-dispatch-fixes-2026-05-18/plan.json`. Disjoint file_scope, parallel-ready.

- [x] 2.1 **F1 — Dead pane surfacing**: `show-fleet.sh` + rust overview emit `dead_panes` count; alert at age >60s.
- [x] 2.2 **F2 — Cap-probe cache TTL**: 60s default; invalidate on bringup-failure marker.
- [x] 2.3 **F3 — Auto-wake on bringup**: `CODEX_FLEET_AUTO_WAKE=1` default; fires `wake-prompt.sh` once before `DONE.`
- [x] 2.4 **F4 — plan-watcher inherits --allow-waves**: pass flag from `run_plan_validator()`; env override.
- [x] 2.5 **F5 — Worker-ready signal + retry**: `force-claim.sh` reads pane input-mode before send-keys; backoff on not-ready.
- [x] 2.6 **F6 — Codex auto-submit smoke test + fix**: script a 1-pane fleet through claim→execute→status; assert worker starts.
- [x] 2.7 **F7 — Codex first-launch prompt auto-bypass**: `scripts/codex-fleet/codex-first-launch-supervisor.sh` seeded in this branch; wire into `full-bringup.sh` as a fleet subtask (sub-6 in `openspec/plans/fleet-dispatch-fixes-2026-05-18/plan.json`).

## 3. Verification

- [ ] 3.1 Each subtask ships a focused test under `scripts/codex-fleet/test/<finding>-test.sh` that reproduces the original symptom and asserts the fix.
- [ ] 3.2 Run `openspec validate agent-claude-cfui-dispatch-improvements-zzz-2026-05-1-2026-05-18-14-03 --type change --strict`.
- [ ] 3.3 Run `openspec validate --specs`.
- [ ] 3.4 Integration: run a fresh `full-bringup.sh --plan-slug fleet-dispatch-fixes-2026-05-18 --n 4 --auto-fleet-id --no-cap-cache` against this very change's plan workspace and assert at least 4 Colony task claims land within 90 seconds of `DONE.` (vs the current 0).
- [ ] 3.5 Capture `/tmp/codex-fleet-telemetry-dispatch-fixes.jsonl` and attach the last 30 lines to the integration PR.

## 4. Cleanup (mandatory; run before claiming completion)

- [ ] 4.1 Run the cleanup pipeline: `gx branch finish --branch agent/<your-name>/<branch-slug> --base dev --via-pr --wait-for-merge --cleanup`. This handles commit -> push -> PR create -> merge wait -> worktree prune in one invocation.
- [ ] 4.2 Record the PR URL and final merge state (`MERGED`) in the completion handoff.
- [ ] 4.3 Confirm the sandbox worktree is gone (`git worktree list` no longer shows the agent path; `git branch -a` shows no surviving local/remote refs for the branch).
