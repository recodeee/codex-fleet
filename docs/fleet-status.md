# fleet-status JSON snapshot

`scripts/codex-fleet/fleet-status.sh` emits a single JSON document on STDOUT
describing the live state of the entire codex-fleet — tmux panes, workers
with classification + claimed task, the active plan, open/merged PRs,
per-account capacity probes, recent blockers, and how long the snapshot took
to compose.

This is the JSON source of truth for:

- `scripts/codex-fleet/mcp/fleet-mcp.py` (SI-1) — exposes `fleet_status` over
  stdio MCP for the host supervisor.
- The future ratatui fleet dashboard.
- Any one-off supervisor query — replaces the 5-command stat composition
  (`tmux ls`, `tmux list-windows`, per-pane `capture-pane`, `pgrep`,
  `gh pr list`, `colony plan publish`) that supervisors had to do by hand.

## Usage

```bash
# Compact, single-line JSON (default — friendly for jq, MCP, pipelines).
scripts/codex-fleet/fleet-status.sh

# Pretty-printed for human reading.
scripts/codex-fleet/fleet-status.sh --pretty

# Override the active plan slug (default reads .codex-fleet/active-plan,
# falling back to the newest dir under openspec/plans/).
scripts/codex-fleet/fleet-status.sh --plan codex-fleet-tui-improvements-2026-05-15

# Use a different tmux socket (default: codex-fleet).
scripts/codex-fleet/fleet-status.sh --socket codex-fleet
```

Exits 0 even when there is no live fleet — in that case `tmux_sessions` is
`[]`, `workers` is `[]`, and best-effort data is still pulled from the active
plan, cap-probe cache, and recent gh PRs.

Dependencies: bash, python3, jq, plus optional `tmux`, `gh`, and
`colony`. No new Rust deps.

## Schema (`schema_version: 1`)

```json
{
  "schema_version": 1,
  "generated_at_utc": "2026-05-18T03:30:00Z",
  "tmux_sessions": [
    { "name": "codex-fleet", "windows": 6, "attached": true }
  ],
  "workers": [
    {
      "pane_id": "codex-fleet:1.1",
      "agent": "codex-bia-zazrifka",
      "account_email": "bia@zazrifka.sk",
      "tier": "high",
      "specialty": "trading-edge-foundations-2026-05-18",
      "cwd": "/home/deadpool/Documents/polymarket-cli",
      "last_activity_age_seconds": 12,
      "classification": "working",
      "current_codex_pid": 12345,
      "claimed_task": {
        "plan_slug": "trading-edge-foundations-2026-05-18",
        "subtask_index": 0,
        "title": "TE-1 edge module tree stubs"
      }
    }
  ],
  "plan": {
    "slug": "trading-edge-foundations-2026-05-18",
    "title": "trading edge foundations",
    "subtask_count": 6,
    "status_histogram": {
      "available": 2,
      "claimed": 1,
      "working": 2,
      "completed": 1,
      "blocked": 0
    }
  },
  "plan_subtasks": [
    {
      "index": 0,
      "title": "TE-1 edge module tree stubs",
      "status": "working",
      "claimed_by_agent": "codex-bia-zazrifka",
      "completed_summary": null
    }
  ],
  "open_prs": [
    {
      "number": 174,
      "title": "feat(edge): TE-2 …",
      "branch": "agent/codex-bia/edge-2-…",
      "mergeable": "MERGEABLE",
      "checks_state": "PENDING"
    }
  ],
  "merged_prs_for_plan": [
    { "number": 173, "title": "…", "merged_at": "2026-05-18T01:14:00Z" }
  ],
  "capacity": [
    {
      "account_email": "bia@zazrifka.sk",
      "last_probe_at": 1779067434,
      "last_status": "healthy",
      "cache_age_s": 30
    }
  ],
  "blockers": [
    "cap-budget alert flag present: /tmp/claude-viz/cap-budget.alert"
  ],
  "ms_to_compose": 1234
}
```

### Field reference

| Path | Meaning |
| --- | --- |
| `schema_version` | Always `1` for this revision. Bump on any breaking shape change. |
| `generated_at_utc` | ISO-8601 UTC timestamp captured before composition starts. |
| `tmux_sessions[]` | One entry per tmux session on `-L codex-fleet`. `[]` when no fleet up. |
| `workers[]` | One entry per tmux pane across all sessions on the socket. |
| `workers[].pane_id` | `<session>:<window>.<pane>` (matches `tmux send-keys -t <pane_id>`). |
| `workers[].agent` | Parsed from pane title (`codex-<name>-<acct>` → `codex-<name>`). `unknown` if unparseable. |
| `workers[].account_email` | Best-effort resolution: per-account staging `env` file → accounts.yml. `null` if unknown. |
| `workers[].tier` | From `accounts.yml`. Empty string if unresolved. |
| `workers[].specialty` | First entry of the account's `specialty[]` list. Empty if unset. |
| `workers[].cwd` | Pane's current working directory. |
| `workers[].last_activity_age_seconds` | Parsed from "Working (Xs)" or "Worked for Xm Ys" in pane capture. `0` when neither present. |
| `workers[].classification` | One of `working`, `waiting-on-prompt`, `errored`, `idle`, `unknown`. |
| `workers[].current_codex_pid` | Pane's foreground pid (codex CLI when active). |
| `workers[].claimed_task` | Inferred via `agent` → `plan_subtasks[].claimed_by_agent`. `null` when no match. |
| `plan` | Active plan summary (`slug` from `.codex-fleet/active-plan` or newest `openspec/plans/*`). |
| `plan.status_histogram` | Counts of subtask statuses. Sourced from `colony plan status` when available, otherwise from `plan.json` on disk. |
| `plan_subtasks[]` | Per-subtask: `index`, `title`, `status`, `claimed_by_agent`, `completed_summary`. |
| `open_prs[]` | gh PRs whose branch matches `^agent/[^/]+/(edge\|si)-` and `state == OPEN`. |
| `merged_prs_for_plan[]` | Same branch filter, `state == MERGED`. |
| `capacity[]` | One entry per JSON in `/tmp/claude-viz/cap-probe-cache/*.json`. `cache_age_s` is `now - probed_at`. |
| `blockers[]` | Stable string list: `cap-budget.alert` flag (if present) + recent `STALL-DISMISS:` / `BLOCKED` lines from `/tmp/claude-viz/stall-watcher.log`. |
| `ms_to_compose` | Wall-clock milliseconds spent composing this snapshot. |

### Classification rules

Applied against the last 30 lines of `tmux capture-pane -p -t <pane>`:

1. Match `Working (Xs|Xm|Xh)` → `working`, age from the parsed duration.
2. Match `ERROR` / `panic:` / `fatal:` / `BLOCKED` (case-insensitive) → `errored`.
3. Match `Do you trust` / `Create a plan?` / `External agent config` → `waiting-on-prompt`.
4. Match `gpt-5.5` chip in capture but no `Working (...)` → `idle`.
5. Otherwise → `unknown`.

### Stability contract

- `schema_version` will only change on breaking shape changes.
- Fields documented above will not be renamed or removed within `schema_version: 1`.
- New optional fields may be added without bumping the version.
- Consumers should treat unknown fields as ignorable.

## Powering SI-1 (fleet-mcp)

The SI-1 stdio MCP server registers a `fleet_status` tool that simply shells
out to this script and returns the parsed JSON. Keep this script's response
time under ~2 seconds for the local fleet — the MCP tool budget is 2 s.

## Tests

`scripts/codex-fleet/test/run-fleet-status.sh`:

- Starts a fixture `tmux new-session -d -s test-fleet-status`.
- Runs `fleet-status.sh` and validates the top-level JSON keys via `jq`.
- Asserts `ms_to_compose < 5000`.
- Cleans up the fixture session on exit.
