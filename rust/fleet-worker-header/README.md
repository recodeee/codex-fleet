# fleet-worker-header

Renders a single-line iOS-style status header for one codex-fleet worker pane.

The intent is to replace the noisy codex-CLI bottom bar ("Summarize recent
commits", "Explain this codebase", etc.) visually by writing a stable,
glanceable summary into the tmux pane title.

```
▲ codex-zazrifka │ high │ TE-2 src/edge module tree stubs │ 2m 14s │ cap: ok
```

## Usage

```sh
fleet-worker-header --pane "%337"
# → writes one UTF-8 line to stdout

# Pipe into the pane title:
tmux set-option -t "%337" pane-title "$(fleet-worker-header --pane %337)"
```

Optional flags:

- `--width <cols>` — width budget in columns. Default 80 (also via
  `CODEX_FLEET_HEADER_WIDTH`).
- `--json` — dump the gathered state instead of rendering. Useful when
  debugging the data pipeline.

## Data sources

All sources are best-effort; the binary always exits 0 even when none are
available. The renderer falls back to "— idle —", `cap: ?`, and `—` for
missing fields.

1. **fleet-status.sh** (preferred). Path resolved via
   `CODEX_FLEET_HEADER_FLEET_STATUS` (default
   `scripts/codex-fleet/fleet-status.sh`). Called as
   `fleet-status.sh --pane <id>` first; if that fails, the script is run
   without args and the binary plucks the matching worker out of `.workers[]`.
   The SI-4 schema's per-worker keys we read: `agent`, `tier`,
   `last_activity_age_seconds`, `claimed_task.title`.
2. **/tmp/claude-viz/cap-probe-cache/`<email>`.json** — keyed on
   `CODEX_FLEET_ACCOUNT_EMAIL`. We read the `verdict` field
   (`healthy` / `ok` / `rate_limited` / `throttled` / `429` / `cooldown`)
   and map it onto `cap: …`. Without an email we pick the freshest cache
   entry as a best-effort.
3. **tmux pane activity** — fallback when fleet-status.sh hasn't been
   shipped yet. Uses `tmux display-message -p -t <pane> "#{pane_activity}"`
   to derive a last-activity age in seconds.

Env-var-only fallbacks: `CODEX_FLEET_AGENT_NAME` and `CODEX_FLEET_TIER`
are read at startup so workers always have an identity even if
fleet-status.sh is offline.

## Integration with the fleet tick daemon

The wake-prompt exposes the rendered path as `$CODEX_FLEET_HEADER_RENDER_PATH`
(see `scripts/codex-fleet/worker-prompt.md`). The recommended cadence is:

```sh
# every 30s, for each worker pane:
tmux set-option -t <pane> pane-title "$(fleet-worker-header --pane <pane>)"
```

Wire that into `scripts/codex-fleet/fleet-tick-daemon.sh` (out of scope for
this crate — SI-7 only ships the renderer + binary).

## Width handling

The renderer is width-aware. When the line overflows, fields are shrunk in
this priority order:

1. Task title (most variable; truncated to `…`)
2. Agent name
3. Tier
4. Activity age

The `cap: …` field is never shrunk — it is load-bearing for supervisor
triage.

Snapshot tests pin the layout at widths **60**, **80**, and **120** for
three reference states (idle, working-on-task, capped-429); see
`tests/snapshot.rs`.

## Build + test

```sh
cargo check -p fleet-worker-header
cargo test  -p fleet-worker-header
```
