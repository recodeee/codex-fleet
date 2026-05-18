# fleet-mcp

Stdio MCP server that exposes Colony + tmux state to an LLM supervisor.

SI-1 of `openspec/plans/supervisor-improvements-2026-05-18/plan.json`.

## What it is

`fleet-mcp.py` is a hand-rolled JSON-RPC 2.0 MCP server (one Python file,
stdlib only) that registers six tools. The host LLM supervisor running
the codex-fleet can read Colony plan state, classify tmux panes, dismiss
known interactive prompts, and list PRs through structured tool calls
instead of composing five shell pipelines on every poll. Tool results
return as `{"error": "..."}` JSON when something is wrong; the server
never raises out of a handler.

## Tools

| Name | Args | Purpose |
| --- | --- | --- |
| `fleet_status` | _none_ | Shells out to `scripts/codex-fleet/fleet-status.sh` (SI-4). Returns `{"error":"fleet-status.sh not installed yet, run SI-4"}` until SI-4 lands. |
| `colony_plan_status` | `slug` | Returns `{slug, title, subtask_count, status_histogram, subtasks:[{index,title,status,claimed_by,completed_summary}], ...}`. Reads `openspec/plans/<slug>/plan.json` directly because the `colony plan status` text output is unstable. |
| `tmux_pane_state` | `session?`, `pane?` | Lists panes on the `codex-fleet` tmux socket, captures the last 30 lines per pane, classifies each as `idle` / `waiting-on-prompt` / `working` / `errored`, and reports which known prompts were detected. |
| `tmux_pane_send_keys` | `session`, `pane`, `keys`, `enter?`, `confirm_destructive?` | Wraps `tmux send-keys`. Refuses `C-c` / `C-d` / `C-\\` / `C-z` unless `confirm_destructive=true`. |
| `worker_dismiss_prompts` | `pane?` | Detects known prompts via `tmux_pane_state` and sends the right dismissal: `Do you trust` -> `1`+Enter; `External agent config` -> `3`+Enter; `Create a plan?` -> Enter (Esc was observed not to work on some codex-CLI versions). |
| `pr_list_for_plan` | `slug`, `branch_prefix?` | Wraps `gh pr list --search <prefix> --json number,title,headRefName,state,statusCheckRollup`. Default prefix is derived from the slug; trading-edge plans default to `edge-`. |

### Classifier rules (`tmux_pane_state`)

Run against the **last 30 lines** of `tmux capture-pane`:

| Signal | Class |
| --- | --- |
| Contains `Do you trust` / `Create a plan?` / `External agent config` | `waiting-on-prompt` (plus a `detected_prompts` list) |
| Contains `Working` and no prompt signal | `working` |
| Contains `panic` / `fatal` (case-insensitive) or `ERROR` | `errored` |
| Contains the `gpt-5.5` chip and no `Working` | `idle` |
| Otherwise | `idle` |

Prompt detection takes priority over `Working` so a worker that's mid-think
but blocked on `Create a plan?` still classifies as `waiting-on-prompt`.

### Latency budget

Every tool is built to return within 2s for the local fleet. Each
subprocess invocation has a 1.8s hard timeout via Python's
`subprocess.run(timeout=...)`. Measured on a no-fleet local box:

```
fleet_status              0.05s
colony_plan_status        0.25s
tmux_pane_state           0.16s
worker_dismiss_prompts    0.15s
pr_list_for_plan          0.57s   # gh round-trip
```

## Running

```bash
# As an MCP server (the normal mode; speaks JSON-RPC over stdio):
python3 scripts/codex-fleet/mcp/fleet-mcp.py

# Inspect the tools/list payload without speaking JSON-RPC:
python3 scripts/codex-fleet/mcp/fleet-mcp.py --list-tools

# Call a single tool directly (handy for debugging):
python3 scripts/codex-fleet/mcp/fleet-mcp.py --call colony_plan_status \
    '{"slug":"supervisor-improvements-2026-05-18"}'

# Run the smoke test (asserts non-error or documented sentinel error
# for each of the 6 tools):
scripts/codex-fleet/mcp/test-fleet-mcp.sh
```

## Registering with a host

See [`docs/fleet-mcp-registration.md`](../../../docs/fleet-mcp-registration.md)
for Claude Desktop / Codex / Cursor config snippets.

## Dependencies

- Python 3.10+ (stdlib only -- no `mcp` package required).
- `tmux` on `PATH`.
- `colony` on `PATH` for `colony_plan_status` (the tool still works
  without it -- it falls back to reading `plan.json` directly).
- `gh` on `PATH` for `pr_list_for_plan`.
- `jq` on `PATH` for the smoke test only.

## Protocol notes

The server implements the minimum MCP surface a real host actually
calls:

- `initialize` -> reports `protocolVersion: "2024-11-05"`, `capabilities.tools: {}`.
- `notifications/initialized` -> no-op.
- `tools/list` -> returns the 6 tools above with JSON-Schema `inputSchema`.
- `tools/call` -> dispatches to the handler and wraps the JSON result in
  `content: [{type:"text", text:<json>}]` with `isError: true` when the
  payload carries an `error` field.
- `ping` / `shutdown` -> minimal responses.
- Unknown methods get JSON-RPC error `-32601`.

Requests are line-delimited JSON objects on stdin; responses are written
one JSON object per line on stdout. Batch requests (a JSON array of
request objects) are supported.
