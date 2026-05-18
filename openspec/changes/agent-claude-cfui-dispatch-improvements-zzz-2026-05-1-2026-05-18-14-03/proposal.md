## Why

Real-fleet telemetry from the 2026-05-18 `marketing-content-waves` bringup against the recodee repo surfaced six concrete dispatch-path defects that block workers from claiming Colony tasks even when the fleet is "physically up." Symptoms:

1. Stale dead panes from prior fleet runs linger in the overview chrome — workers terminated by `signal 15` show `Pane is dead` for hours and operators get no surfacing signal.
2. `cap-probe` cache TTL is stale across bringups: first run found 5/6 healthy accounts, fresh `--no-cap-cache` rerun ~5min later found 8/8 — the cache outlived the actual quota recovery.
3. The `wake-prompt` window stays blank on bringup completion — never auto-fires, so workers idle at default Codex placeholder prompts (`"Implement {feature}"`, `"Find and fix a bug in @filename"`).
4. `plan-watcher.sh` re-validates plan.json on each tick *without* passing `--allow-waves`, so any plan with `depends_on` fails hard, plan-watcher skips dispatch, and `force-claim` silently falls back to whatever plan is next in queue (we observed our priority plan being skipped while `trading-edge-foundations-pt2` got dispatched instead).
5. `force-claim` send-keys hits "not in a mode" on non-idle Codex panes and silently drops the dispatch — no retry, no backoff, no operator signal.
6. Even when send-keys reaches the input box, Codex's auto-submit doesn't fire — the prompt sits typed but never gets submitted. Context % drops (so the keys arrived) but no Colony claim is recorded.

These bugs compound: (4) blocks dispatch for plans with deps, (5) blocks dispatch for busy panes, (6) blocks dispatch *even when send-keys lands in the input box*. The net effect is that a freshly-bootstrapped fleet looks healthy in tmux but performs zero work.

## What Changes

- **F1 — surface dead panes**: `scripts/codex-fleet/show-fleet.sh` and the rust overview renderer add a `dead_panes` count; alert when any pane has `dead==1` for >60s.
- **F2 — cap-probe cache TTL**: drop cache file age threshold from current default to 60s; invalidate on any prior bringup failure marker.
- **F3 — auto-wake on bringup**: new `CODEX_FLEET_AUTO_WAKE` env (default `1`) that fires `wake-prompt.sh` once at the end of `full-bringup.sh`, before the `DONE.` banner. Existing wake-prompt window continues handling subsequent ticks.
- **F4 — plan-watcher inherits --allow-waves**: pass `--allow-waves` to `lib/plan-validator.sh` from `plan-watcher.sh:run_plan_validator()`. Optional env `CODEX_FLEET_PLAN_VALIDATOR_FLAGS` for operator override.
- **F5 — worker-ready signal + retry**: `force-claim.sh` checks each worker pane's mode (via `tmux display-message -p -t <pane> '#{pane_in_mode}'` plus a Codex-specific input-state heuristic) before send-keys; if not ready, backoff and retry on next tick rather than emit "not in a mode".
- **F6 — Codex auto-submit**: investigate whether send-keys requires a different terminator (e.g., `Enter Enter`, or sending text via `paste-buffer` + paste vs. raw send-keys). Add a smoke test in `scripts/codex-fleet/test/` that scripts a 1-pane fleet through claim → execute → status on a no-op plan, asserting the worker actually starts.

## Impact

- **Risk**: medium. Changes touch the dispatch hot path; a regression could prevent dispatch globally. Each subtask is bounded to a single script with disjoint file_scope, so they can roll back independently.
- **Surfaces affected**: `scripts/codex-fleet/show-fleet.sh`, `scripts/codex-fleet/cap-probe.sh`, `scripts/codex-fleet/full-bringup.sh`, `scripts/codex-fleet/plan-watcher.sh`, `scripts/codex-fleet/force-claim.sh`, `scripts/codex-fleet/test/` (new smoke test). No Colony / recodee changes.
- **Rollout**: features F1-F4 are observability/inheritance fixes — ship default-on. F5 (ready signal) and F6 (auto-submit) gate behind env `CODEX_FLEET_DISPATCH_V2=1` for one cycle of operator testing before flipping default.
- **Telemetry**: each subtask must also append one example JSONL entry to `docs/fleet-telemetry-cases.md` so future regressions are catchable.
