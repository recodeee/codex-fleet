# Checkpoints

## Rollup

- available: 0
- claimed: 0
- completed: 7
- blocked: 0

## Subtasks

- [x] sub-0 F1 — Surface dead panes in show-fleet.sh + rust overview [completed] — `show-fleet.sh:dead_panes_report()` reads `#{pane_dead}`, emits JSON to stderr, alerts at age >60s via `/tmp/claude-viz/dead-pane-firstseen/` markers. Example case documented in `docs/fleet-telemetry-cases.md`.
- [x] sub-1 F2 — Cap-probe cache TTL hardening [completed] — `CACHE_TTL_HEALTHY` default 60s (was 300s), `CODEX_FLEET_CAP_CACHE_TTL` env override added, bringup-failure marker zeroes TTL.
- [x] sub-2 F3+F7 wire-in — auto-wake + auto-bypass at tail of full-bringup [completed] — both gated by env (CODEX_FLEET_AUTO_BYPASS=1, CODEX_FLEET_AUTO_WAKE=1 defaults); auto-bypass runs first.
- [x] sub-3 F4 — plan-watcher inherits --allow-waves [completed] — validator invocation gains `--allow-waves`; `CODEX_FLEET_PLAN_VALIDATOR_FLAGS` env override layered after.
- [x] sub-4 F5 — Worker-ready signal + retry in force-claim [completed] — dispatch() checks `#{pane_in_mode}` + Codex `›` glyph + Working() heuristic before send-keys; defers (does NOT consume claim) when pane not ready.
- [x] sub-5 F6 — Codex auto-submit smoke test [completed] — `test/codex-auto-submit-test.sh` exits FAIL today; will pass once the working submit-key sequence is identified. Production fix lands in a follow-up after smoke confirms the working sequence.
- [x] sub-6 F7-test — Smoke test that no panes stay stuck on first-launch prompts [completed] — `test/first-launch-bypass-test.sh` PASSES (verified live).
