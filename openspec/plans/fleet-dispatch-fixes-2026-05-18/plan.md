# Plan: fleet-dispatch-fixes-2026-05-18

Fix the codex-fleetui dispatch path so a bootstrapped fleet actually performs work. Six findings, six parallel-ready subtasks, one integration PR.

## Problem

The 2026-05-18 marketing-content-waves fleet run surfaced six dispatch-path defects: dead-pane silence, stale cap cache, blank wake-prompt, plan-watcher missing --allow-waves, send-keys "not in a mode" no-retry, Codex auto-submit failure. Symptoms compound — net effect is a healthy-looking tmux fleet that performs zero work.

## Scope

| # | Subtask | Files | Cap. hint |
|---|---------|-------|-----------|
| 0 | F1 — surface dead panes | `show-fleet.sh`, `docs/fleet-telemetry-cases.md` | `doc_work` |
| 1 | F2 — cap-probe TTL | `cap-probe.sh`, `cap-probe-cache.sh` | `test_work` |
| 2 | F3 — auto-wake on bringup | `full-bringup.sh` | `api_work` |
| 3 | F4 — plan-watcher --allow-waves | `plan-watcher.sh` | `frontend_work` |
| 4 | F5 — worker-ready signal + retry | `force-claim.sh` | `frontend_work` |
| 5 | F6 — Codex auto-submit smoke test | `test/codex-auto-submit-test.sh` | `test_work` |

All file_scopes are disjoint. All depends_on are empty (workers can claim any subtask in any order — plan-watcher will accept this plan without --allow-waves until F4 lands and lifts the constraint).

## Out of scope

- Colony coordination protocol changes.
- Recodee repo edits.
- Rust dashboard renderer overhaul (separate plan).
- Account auth-rotation rework.

## Telemetry side-task

Integration test (acceptance criterion 7) runs `full-bringup.sh --plan-slug fleet-dispatch-fixes-2026-05-18 --n 4 --auto-fleet-id --no-cap-cache` against THIS plan after all subtasks land, asserting >=4 Colony claims within 90s of DONE. That's the regression gate.
