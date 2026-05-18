# Registering fleet-mcp with an MCP host

`scripts/codex-fleet/mcp/fleet-mcp.py` is a stdio MCP server. Any host
that can launch a local command and speak JSON-RPC over its stdin/stdout
can use it. Below are config snippets for the three hosts we care about
(Claude Desktop / Claude Code, Codex, Cursor).

> Replace `/home/deadpool/Documents/codex-fleetui` with your repo path
> wherever it appears.

## Claude Code / Claude Desktop

Add an entry to `~/.claude/mcp_servers.json` (Claude Code) or
`~/Library/Application Support/Claude/claude_desktop_config.json` (Claude
Desktop on macOS).

```jsonc
{
  "mcpServers": {
    "fleet-mcp": {
      "command": "python3",
      "args": [
        "/home/deadpool/Documents/codex-fleetui/scripts/codex-fleet/mcp/fleet-mcp.py"
      ],
      "env": {}
    }
  }
}
```

After saving, restart the host. The six tools (`fleet_status`,
`colony_plan_status`, `tmux_pane_state`, `tmux_pane_send_keys`,
`worker_dismiss_prompts`, `pr_list_for_plan`) appear under the
`fleet-mcp` server name.

### Project-scoped permissions

If your `~/.claude/settings.json` (or the project-level
`.claude/settings.local.json`) uses an allow-list for MCP tool calls,
add:

```jsonc
{
  "permissions": {
    "allow": [
      "mcp__fleet-mcp__fleet_status",
      "mcp__fleet-mcp__colony_plan_status",
      "mcp__fleet-mcp__tmux_pane_state",
      "mcp__fleet-mcp__worker_dismiss_prompts",
      "mcp__fleet-mcp__pr_list_for_plan"
    ],
    "deny": [
      "mcp__fleet-mcp__tmux_pane_send_keys"
    ]
  }
}
```

`tmux_pane_send_keys` is intentionally on the deny list by default --
the supervisor should prefer `worker_dismiss_prompts` for the safe
common-case dismissals, and only use raw `send_keys` after a human
inspection. Add it to `allow` when you're confident.

## Codex CLI

Codex picks up MCP servers from `~/.codex/mcp_servers.json` (same shape
as Claude's). The snippet above works verbatim. If you maintain
per-account CODEX_HOMEs (`scripts/codex-fleet/full-bringup.sh` does),
either symlink the file into every account home or duplicate it.

## Cursor

Cursor uses `~/.cursor/mcp.json`:

```jsonc
{
  "mcpServers": {
    "fleet-mcp": {
      "command": "python3",
      "args": [
        "/home/deadpool/Documents/codex-fleetui/scripts/codex-fleet/mcp/fleet-mcp.py"
      ]
    }
  }
}
```

## Smoke test after registration

Run the local smoke test first to confirm the server is healthy:

```bash
scripts/codex-fleet/mcp/test-fleet-mcp.sh
```

It pipes one JSON-RPC `tools/call` per registered tool and asserts that
each reply is structurally valid. Tools that depend on infrastructure
that isn't up yet (e.g. `fleet-status.sh` before SI-4 lands, or `tmux`
when no fleet is running) return documented error sentinels rather than
crashing; the smoke test treats those sentinels as a pass.

Then from inside the host, ask the supervisor LLM something like:

> Use `mcp__fleet-mcp__colony_plan_status` to list subtasks for
> `supervisor-improvements-2026-05-18`.

You should see the 11 subtasks with their `status` and `claimed_by`
fields.

## Troubleshooting

- **`command not found: python3`** -- some hosts launch with a minimal
  PATH. Set `"command": "/usr/bin/python3"` (or the absolute path from
  `which python3`) instead.
- **`fleet-status.sh not installed yet`** -- expected until SI-4 lands.
- **`no server running` on tmux tools** -- the codex-fleet tmux server
  is down. `scripts/codex-fleet/full-bringup.sh` brings it up.
- **`gh pr list exited 4`** -- `gh` isn't authenticated. Run
  `gh auth login` (the supervisor account just needs `repo:read`).
