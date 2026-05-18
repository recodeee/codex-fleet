# cap-probe-fixtures

Fixture directories consumed by `../run-cap-budget.sh` to exercise the
`check_threshold` function extracted from `../../cap-budget-alerts.sh`.

Each fixture is a *directory* of per-account JSON files matching the live
cap-probe-cache schema (verified 2026-05-18 against
`/tmp/claude-viz/cap-probe-cache/*.json`):

```json
{"verdict": "healthy|capped|unknown", "until_epoch": N,
 "until_text": "...", "probed_at": <unix epoch>}
```

Fixture files use the literal token `__PROBED_AT__` where the unix epoch
should live; `run-cap-budget.sh` rewrites that placeholder to `date +%s`
when materializing the cache under `/tmp/claude-viz/cap-probe-cache-test/`.
This keeps the fixtures stable on disk while still landing every
`probed_at` inside the rolling 5-minute window the daemon checks.

| Fixture | Active | Capped (in-window) | Expected |
| --- | --- | --- | --- |
| `all-ok/` | 6 | 0 | no alert (state=ok, flag absent) |
| `three-out-of-six-429/` | 6 | 3 | alert (3/6 == 50% breach threshold) |
