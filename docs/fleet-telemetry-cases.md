# Fleet Telemetry Cases

Live cases surfaced by `/tmp/codex-fleet-telemetry-*.jsonl` and the in-process
supervisors during real bringups. Each entry documents the symptom, the
detection signal, and the fix that addresses it.

## F1 — Dead panes silent in overview

**Symptom (live 2026-05-18):** `Pane is dead (signal 15, Mon May 18 11:43:27 2026)`
on 5+ panes of `codex-fleet` session. Operator only noticed by scrolling into
each pane manually; the overview chrome rendered them as if alive.

**Detection signal:**
```jsonl
{"kind":"pane","pane_id":"%16","last_line":"Pane is dead (signal 15, Mon May 18 11:43:27 2026)","blocked":0,"stall_secs":0}
```

**Fix:** `scripts/codex-fleet/show-fleet.sh:dead_panes_report()` reads
`tmux list-panes -F '#{pane_dead}'` and emits a JSON summary on stderr.
Markers under `/tmp/claude-viz/dead-pane-firstseen/` track first-seen
timestamps so we can alert at age >60s.

---

## F2 — Cap-probe cache outlived quota recovery

**Symptom (live 2026-05-18):** First `full-bringup.sh` found 5/6 healthy
accounts; a fresh `--no-cap-cache` re-run ~5min later found 8/8 healthy.
The 300s default `CACHE_TTL_HEALTHY` outlived the actual quota window
during a normal fleet bringup.

**Fix:** `scripts/codex-fleet/cap-probe.sh` lowers `CACHE_TTL_HEALTHY` default
to 60s, adds `CODEX_FLEET_CAP_CACHE_TTL` env override, and zeroes the TTL
when `/tmp/claude-viz/bringup-failure.marker` exists.

---

## F3 + F7 — wake-prompt and trust-prompt never fire on bringup

**Symptom (live 2026-05-18):** `fleet-ticker-2:wake-prompt` window blank
after bringup; 8 workers in `codex-fleet-2` stuck at default Codex
placeholders (`"Implement {feature}"`). Separately, FLEET_ID=3's 8 workers
each blocked on `Do you trust the contents of this directory?` →
`External agent config detected` → `Press enter to continue`.

**Fix:**
- `scripts/codex-fleet/codex-first-launch-supervisor.sh` (new) drains all
  three first-launch prompts in parallel. Verified live: 8/8 panes drained.
- `scripts/codex-fleet/full-bringup.sh` calls it just before the `DONE.`
  banner, gated by `CODEX_FLEET_AUTO_BYPASS=1` default. Auto-wake follows
  immediately after, gated by `CODEX_FLEET_AUTO_WAKE=1` default.

---

## F4 — plan-watcher rejects depends_on plans

**Symptom (live 2026-05-18):**
```
[plan-watcher] PLAN-VALIDATE: ERROR 5
[plan-watcher] {"ok":false,"errors":["tasks[1] '…' has depends_on=[0] but --allow-waves was not passed", …]}
[plan-watcher] plan-validator reported hard errors; skipping dispatch this tick
```
Force-claim silently fell back to `trading-edge-foundations-pt2-2026-05-18`
while our priority plan `marketing-content-waves-2026-05-18` (which used
`depends_on`) was rejected on every tick.

**Fix:** `scripts/codex-fleet/plan-watcher.sh:run_plan_validator()` passes
`--allow-waves` (matching what `full-bringup.sh` does at publish time).
`CODEX_FLEET_PLAN_VALIDATOR_FLAGS` env layers extra operator flags without
losing the baseline.

---

## F5 — force-claim silently drops dispatch on non-idle panes

**Symptom (live 2026-05-18):** force-claim log showed `not in a mode` 9× per
tick on panes that were busy with prior work. The Colony claim had already
been consumed; the dispatch silently failed; the subtask sat orphaned.

**Fix:** `scripts/codex-fleet/force-claim.sh:dispatch()` runs a pane-ready
check via `tmux display-message -p '#{pane_in_mode}'` plus a visible-screen
heuristic (last 10 lines must contain `›` input glyph and not contain
`Working (...esc to interrupt)`) before `send-keys`. Non-ready panes
return early with `[defer]` so the Colony claim is not consumed and the
subtask returns to `available` for the next tick.

---

## F6 — Codex auto-submit not firing on send-keys

**Symptom (live 2026-05-18):** Worker context drops from 92% to 83% (keys
arrived in the input box) but Colony shows 0 claims and the worker stays
at the input prompt. The typed prompt sits there unsubmitted.

**Fix (still investigating):** `scripts/codex-fleet/test/codex-auto-submit-test.sh`
spawns a 1-pane fleet against a no-op plan, sends the wake prompt via the
candidate submit-key sequence, and asserts >=1 Colony claim within 90s.
Candidate sequences tested: `Enter`, `Enter Enter`, `tmux paste-buffer`,
`Tab Enter`. The smoke test is the gate; the working sequence lands in
`force-claim.sh:dispatch()` once identified.
