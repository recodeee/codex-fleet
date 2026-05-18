#!/usr/bin/env python3
"""fleet-mcp.py - stdio MCP server exposing Colony + tmux state.

Implements MCP JSON-RPC 2.0 over stdio with 6 tools:

  * fleet_status            -- shells out to scripts/codex-fleet/fleet-status.sh
  * colony_plan_status      -- wraps `colony plan status <slug>` + parses
                               openspec/plans/<slug>/plan.json
  * tmux_pane_state         -- tmux list-panes + capture-pane + classifier
  * tmux_pane_send_keys     -- tmux send-keys with destructive-key safety
  * worker_dismiss_prompts  -- detect known prompts, send the right keys
  * pr_list_for_plan        -- gh pr list scoped to the plan branch prefix

Each tool returns within ~2s for the local fleet. Tool errors are returned
as `{"error": "..."}` JSON payloads, never as raised exceptions.

The MCP SDK is not assumed to be installed; protocol is hand-rolled because
it is small. Speaks the subset of MCP that Claude Desktop / Codex / Cursor
actually call: initialize, tools/list, tools/call, plus a no-op
notifications/initialized handler.

SI-1 of openspec/plans/supervisor-improvements-2026-05-18/plan.json.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SERVER_NAME = "fleet-mcp"
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSION = "2024-11-05"

# Cap any child subprocess at this many seconds so we honor the
# "respond within 2s" contract even if tmux / gh / colony hang.
DEFAULT_TIMEOUT_S = 1.8

# Default tmux socket the fleet uses everywhere.
TMUX_SOCKET = "codex-fleet"

# Repo root: assume this script lives at scripts/codex-fleet/mcp/fleet-mcp.py.
SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parent.parent.parent.parent

FLEET_STATUS_SH = REPO_ROOT / "scripts" / "codex-fleet" / "fleet-status.sh"

# Keys we refuse to send without confirm_destructive=true.
DESTRUCTIVE_KEYS = {"C-c", "C-d", "C-\\", "C-z"}


# ---------------------------------------------------------------------------
# Subprocess helpers
# ---------------------------------------------------------------------------


def _run(
    cmd: list[str],
    *,
    timeout: float = DEFAULT_TIMEOUT_S,
    cwd: str | os.PathLike[str] | None = None,
    input_bytes: bytes | None = None,
) -> tuple[int, str, str]:
    """Run a command and return (rc, stdout, stderr). Never raises."""
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            timeout=timeout,
            cwd=str(cwd) if cwd is not None else None,
            input=input_bytes,
            check=False,
        )
        return (
            proc.returncode,
            proc.stdout.decode("utf-8", errors="replace"),
            proc.stderr.decode("utf-8", errors="replace"),
        )
    except subprocess.TimeoutExpired:
        return (124, "", f"timeout after {timeout}s: {' '.join(cmd)}")
    except FileNotFoundError as exc:
        return (127, "", f"command not found: {exc}")
    except Exception as exc:  # pragma: no cover - defensive
        return (1, "", f"unexpected error running {cmd!r}: {exc}")


def _err(msg: str) -> dict[str, Any]:
    return {"error": msg}


# ---------------------------------------------------------------------------
# Tool: fleet_status
# ---------------------------------------------------------------------------


def tool_fleet_status(_args: dict[str, Any]) -> dict[str, Any]:
    if not FLEET_STATUS_SH.exists():
        return _err("fleet-status.sh not installed yet, run SI-4")
    if not os.access(FLEET_STATUS_SH, os.X_OK):
        return _err(
            f"fleet-status.sh exists at {FLEET_STATUS_SH} but is not executable"
        )
    rc, out, stderr = _run([str(FLEET_STATUS_SH)])
    if rc != 0:
        return _err(f"fleet-status.sh exited {rc}: {stderr.strip()[:400]}")
    out = out.strip()
    if not out:
        return _err("fleet-status.sh produced no output")
    try:
        return json.loads(out)
    except json.JSONDecodeError as exc:
        return _err(f"fleet-status.sh produced invalid JSON: {exc}")


# ---------------------------------------------------------------------------
# Tool: colony_plan_status
# ---------------------------------------------------------------------------


def _find_plan_json(slug: str) -> Path | None:
    """Look for openspec/plans/<slug>/plan.json under REPO_ROOT and CWD."""
    candidates = [
        REPO_ROOT / "openspec" / "plans" / slug / "plan.json",
        Path.cwd() / "openspec" / "plans" / slug / "plan.json",
    ]
    for p in candidates:
        if p.is_file():
            return p
    return None


def tool_colony_plan_status(args: dict[str, Any]) -> dict[str, Any]:
    slug = args.get("slug")
    if not isinstance(slug, str) or not slug:
        return _err("missing required string arg 'slug'")

    # Always shell out to colony so we surface the same warnings/errors a
    # human would see, but also parse plan.json directly because the text
    # output of `colony plan status` is unstable.
    rc, raw_out, raw_err = _run(
        ["colony", "plan", "status", slug],
        cwd=REPO_ROOT,
        timeout=DEFAULT_TIMEOUT_S,
    )
    cli_output = (raw_out + raw_err).strip()

    plan_path = _find_plan_json(slug)
    if plan_path is None:
        return _err(
            f"plan {slug!r} not found: colony said: {cli_output[:300] or '(no output)'}"
        )

    try:
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return _err(f"could not read {plan_path}: {exc}")

    subtasks: list[dict[str, Any]] = []
    for raw in plan.get("tasks", []) or []:
        if not isinstance(raw, dict):
            continue
        subtasks.append(
            {
                "index": raw.get("subtask_index"),
                "title": raw.get("title"),
                "status": raw.get("status"),
                "claimed_by": raw.get("claimed_by_agent")
                or raw.get("claimed_by_session_id"),
                "completed_summary": raw.get("completed_summary"),
            }
        )

    histogram: dict[str, int] = {}
    for st in subtasks:
        s = st.get("status") or "unknown"
        histogram[s] = histogram.get(s, 0) + 1

    return {
        "slug": slug,
        "title": plan.get("title"),
        "plan_path": str(plan_path),
        "subtask_count": len(subtasks),
        "status_histogram": histogram,
        "subtasks": subtasks,
        "colony_cli_rc": rc,
        "colony_cli_output": cli_output[:1000],
    }


# ---------------------------------------------------------------------------
# Tool: tmux_pane_state
# ---------------------------------------------------------------------------


# Classification rule patterns (case-sensitive substrings unless noted).
_PROMPT_TRUST = "Do you trust"
_PROMPT_PLAN = "Create a plan?"
_PROMPT_EXTERNAL_AGENT = "External agent config"
_TOKEN_WORKING = "Working"
_TOKEN_ERROR_HARD = ("panic", "fatal")
_TOKEN_ERROR_SOFT = "ERROR"
_TOKEN_DONE = "done"  # informational; not currently a primary signal
_TOKEN_GPT_CHIP = "gpt-5.5"


def _classify_pane(text: str) -> tuple[str, list[str]]:
    """Return (classification, detected_prompts)."""
    detected: list[str] = []
    if _PROMPT_TRUST in text:
        detected.append("trust-directory")
    if _PROMPT_EXTERNAL_AGENT in text:
        detected.append("external-agent-config")
    if _PROMPT_PLAN in text:
        detected.append("create-a-plan")

    if detected:
        return "waiting-on-prompt", detected

    if _TOKEN_WORKING in text:
        return "working", detected

    # Hard error tokens (lowercase substrings)
    lowered = text.lower()
    if any(tok in lowered for tok in _TOKEN_ERROR_HARD):
        return "errored", detected
    if _TOKEN_ERROR_SOFT in text:
        return "errored", detected

    if _TOKEN_GPT_CHIP in text and _TOKEN_WORKING not in text:
        return "idle", detected

    return "idle", detected


def _list_panes(session: str | None) -> tuple[list[dict[str, Any]] | None, str]:
    fmt = "#{session_name}|#{window_index}|#{pane_index}|#{pane_id}|#{pane_pid}"
    cmd = ["tmux", "-L", TMUX_SOCKET, "list-panes", "-a", "-F", fmt]
    if session:
        cmd = ["tmux", "-L", TMUX_SOCKET, "list-panes", "-t", session, "-F", fmt]
    rc, out, stderr = _run(cmd)
    if rc != 0:
        return None, stderr.strip() or f"tmux list-panes exited {rc}"
    panes: list[dict[str, Any]] = []
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) != 5:
            continue
        s, w, p, pid_str, proc_pid = parts
        panes.append(
            {
                "session": s,
                "window_index": int(w) if w.isdigit() else w,
                "pane_index": int(p) if p.isdigit() else p,
                "pane_id": pid_str,
                "pane_pid": int(proc_pid) if proc_pid.isdigit() else proc_pid,
                "target": f"{s}:{w}.{p}",
            }
        )
    return panes, ""


def _capture_pane(target: str, lines: int = 30) -> tuple[str | None, str]:
    cmd = [
        "tmux",
        "-L",
        TMUX_SOCKET,
        "capture-pane",
        "-p",
        "-t",
        target,
        "-S",
        f"-{lines}",
    ]
    rc, out, stderr = _run(cmd)
    if rc != 0:
        return None, stderr.strip() or f"tmux capture-pane exited {rc}"
    return out, ""


def tool_tmux_pane_state(args: dict[str, Any]) -> dict[str, Any]:
    session = args.get("session")
    pane = args.get("pane")
    if session is not None and not isinstance(session, str):
        return _err("'session' must be a string if provided")
    if pane is not None and not isinstance(pane, str):
        return _err("'pane' must be a string if provided")

    panes, err = _list_panes(session)
    if panes is None:
        # No tmux server running is not an error from the supervisor's
        # standpoint -- return empty list with a note.
        if "no server running" in err.lower() or "error connecting" in err.lower():
            return {"panes": [], "note": err}
        return _err(f"tmux list-panes failed: {err}")

    if pane:
        panes = [p for p in panes if p["target"] == pane or p["pane_id"] == pane]

    results: list[dict[str, Any]] = []
    for p in panes:
        text, cap_err = _capture_pane(p["target"])
        if text is None:
            results.append({**p, "classification": "unknown", "capture_error": cap_err})
            continue
        last30 = "\n".join(text.splitlines()[-30:])
        cls, prompts = _classify_pane(last30)
        results.append(
            {
                **p,
                "classification": cls,
                "detected_prompts": prompts,
                "capture_tail": last30,
            }
        )
    return {"panes": results}


# ---------------------------------------------------------------------------
# Tool: tmux_pane_send_keys
# ---------------------------------------------------------------------------


def tool_tmux_pane_send_keys(args: dict[str, Any]) -> dict[str, Any]:
    session = args.get("session")
    pane = args.get("pane")
    keys = args.get("keys")
    enter = bool(args.get("enter", False))
    confirm_destructive = bool(args.get("confirm_destructive", False))

    if not isinstance(session, str) or not session:
        return _err("missing required string arg 'session'")
    if not isinstance(pane, str) or not pane:
        return _err("missing required string arg 'pane'")
    if not isinstance(keys, str):
        return _err("missing required string arg 'keys'")

    # Refuse destructive sequences unless explicitly confirmed.
    if not confirm_destructive:
        for tok in DESTRUCTIVE_KEYS:
            if tok in keys.split():
                return _err(
                    f"refusing to send destructive key {tok!r} without "
                    f"confirm_destructive=true"
                )

    target = pane if ":" in pane else f"{session}:{pane}"
    cmd = ["tmux", "-L", TMUX_SOCKET, "send-keys", "-t", target]
    cmd.extend(keys.split())
    if enter:
        cmd.append("Enter")

    rc, out, stderr = _run(cmd)
    if rc != 0:
        return _err(f"tmux send-keys exited {rc}: {stderr.strip()}")
    return {
        "ok": True,
        "target": target,
        "sent_keys": keys,
        "enter": enter,
        "stdout": out.strip(),
    }


# ---------------------------------------------------------------------------
# Tool: worker_dismiss_prompts
# ---------------------------------------------------------------------------


# Map: prompt-name -> (keys to send, append Enter?)
# "Create a plan?" dismissal: Enter (Esc was observed not to work on some
# codex-CLI versions; Enter accepts the default = no plan mode).
# "Do you trust this directory?": "1" + Enter.
# "External agent config detected": "3" + Enter (Don't ask again).
_DISMISSAL_TABLE: dict[str, tuple[str, bool]] = {
    "trust-directory": ("1", True),
    "external-agent-config": ("3", True),
    "create-a-plan": ("", True),  # bare Enter
}


def tool_worker_dismiss_prompts(args: dict[str, Any]) -> dict[str, Any]:
    pane = args.get("pane")
    if pane is not None and not isinstance(pane, str):
        return _err("'pane' must be a string if provided")

    state = tool_tmux_pane_state({"pane": pane} if pane else {})
    if "error" in state:
        return state

    dismissals: list[dict[str, Any]] = []
    for p in state.get("panes", []):
        prompts = p.get("detected_prompts") or []
        if not prompts:
            continue
        # Pick the highest-priority known prompt:
        # trust-directory > external-agent-config > create-a-plan
        chosen: str | None = None
        for name in ("trust-directory", "external-agent-config", "create-a-plan"):
            if name in prompts:
                chosen = name
                break
        if chosen is None:
            continue
        keys, with_enter = _DISMISSAL_TABLE[chosen]
        target = p["target"]
        cmd = ["tmux", "-L", TMUX_SOCKET, "send-keys", "-t", target]
        if keys:
            cmd.extend(keys.split())
        if with_enter:
            cmd.append("Enter")
        rc, out, stderr = _run(cmd)
        dismissals.append(
            {
                "target": target,
                "prompt": chosen,
                "keys": keys,
                "enter": with_enter,
                "ok": rc == 0,
                "error": stderr.strip() if rc != 0 else None,
            }
        )
    return {"dismissals": dismissals, "count": len(dismissals)}


# ---------------------------------------------------------------------------
# Tool: pr_list_for_plan
# ---------------------------------------------------------------------------


# Branch convention from SI-8: edge-(te|sp|bk|rk|cm|ma|ni|ns|ra|cv|ex)<N>-<slug>
# For the generic supervisor we accept any plan-slug-derived prefix.
def _branch_prefix_for_plan(slug: str) -> str:
    # Best-effort: prefer "edge-" (the trading-edge convention) when slug
    # starts with "trading-edge". Otherwise use the first dash-segment.
    if slug.startswith("trading-edge"):
        return "edge-"
    return slug.split("-", 1)[0] + "-"


def tool_pr_list_for_plan(args: dict[str, Any]) -> dict[str, Any]:
    slug = args.get("slug")
    if not isinstance(slug, str) or not slug:
        return _err("missing required string arg 'slug'")

    if shutil.which("gh") is None:
        return _err("gh CLI not installed")

    prefix = args.get("branch_prefix")
    if not isinstance(prefix, str) or not prefix:
        prefix = _branch_prefix_for_plan(slug)

    cmd = [
        "gh",
        "pr",
        "list",
        "--search",
        prefix,
        "--json",
        "number,title,headRefName,state,statusCheckRollup",
        "--limit",
        "50",
    ]
    rc, out, stderr = _run(cmd, cwd=REPO_ROOT, timeout=DEFAULT_TIMEOUT_S)
    if rc != 0:
        return _err(f"gh pr list exited {rc}: {stderr.strip()[:300]}")
    try:
        prs = json.loads(out or "[]")
    except json.JSONDecodeError as exc:
        return _err(f"gh pr list produced invalid JSON: {exc}")
    # Best-effort filter by branch prefix in case gh's text search is loose.
    if isinstance(prs, list):
        prs = [
            p
            for p in prs
            if isinstance(p, dict)
            and isinstance(p.get("headRefName"), str)
            and p["headRefName"].startswith(prefix)
        ]
    return {"slug": slug, "branch_prefix": prefix, "prs": prs, "count": len(prs)}


# ---------------------------------------------------------------------------
# Tool registry
# ---------------------------------------------------------------------------


TOOLS: dict[str, dict[str, Any]] = {
    "fleet_status": {
        "description": (
            "Return the full fleet-status.sh JSON document (SI-4). "
            "If SI-4 is not yet installed, returns {error: 'fleet-status.sh "
            "not installed yet, run SI-4'}."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
        "handler": tool_fleet_status,
    },
    "colony_plan_status": {
        "description": (
            "Return per-subtask state for a Colony plan slug: "
            "{subtasks: [{index, title, status, claimed_by, completed_summary}]}. "
            "Reads openspec/plans/<slug>/plan.json directly for stable parsing."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {"slug": {"type": "string"}},
            "required": ["slug"],
            "additionalProperties": False,
        },
        "handler": tool_colony_plan_status,
    },
    "tmux_pane_state": {
        "description": (
            "List tmux panes on the 'codex-fleet' socket and classify each as "
            "one of idle/waiting-on-prompt/working/errored. Optional 'session' "
            "and 'pane' (e.g. 'fleet:1.0' or '%37') filters."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "session": {"type": "string"},
                "pane": {"type": "string"},
            },
            "additionalProperties": False,
        },
        "handler": tool_tmux_pane_state,
    },
    "tmux_pane_send_keys": {
        "description": (
            "Send keystrokes to a tmux pane on the 'codex-fleet' socket. "
            "Refuses Ctrl-C / Ctrl-D / Ctrl-\\ / Ctrl-Z unless "
            "confirm_destructive=true is passed."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "session": {"type": "string"},
                "pane": {"type": "string"},
                "keys": {"type": "string"},
                "enter": {"type": "boolean", "default": False},
                "confirm_destructive": {"type": "boolean", "default": False},
            },
            "required": ["session", "pane", "keys"],
            "additionalProperties": False,
        },
        "handler": tool_tmux_pane_send_keys,
    },
    "worker_dismiss_prompts": {
        "description": (
            "Detect known interactive prompts in worker panes and dispatch "
            "the correct dismissal: 'Do you trust' -> '1' + Enter; "
            "'External agent config' -> '3' + Enter; "
            "'Create a plan?' -> Enter."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {"pane": {"type": "string"}},
            "additionalProperties": False,
        },
        "handler": tool_worker_dismiss_prompts,
    },
    "pr_list_for_plan": {
        "description": (
            "List open/recent GitHub PRs whose branch matches the plan's "
            "branch prefix (e.g. 'edge-' for trading-edge plans). Returns "
            "number, title, headRefName, state, statusCheckRollup."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "slug": {"type": "string"},
                "branch_prefix": {"type": "string"},
            },
            "required": ["slug"],
            "additionalProperties": False,
        },
        "handler": tool_pr_list_for_plan,
    },
}


# ---------------------------------------------------------------------------
# JSON-RPC 2.0 over stdio
# ---------------------------------------------------------------------------


def _jsonrpc_result(req_id: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def _jsonrpc_error(req_id: Any, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": code, "message": message},
    }


def _tools_list_payload() -> dict[str, Any]:
    return {
        "tools": [
            {
                "name": name,
                "description": meta["description"],
                "inputSchema": meta["inputSchema"],
            }
            for name, meta in TOOLS.items()
        ]
    }


def _tools_call(params: dict[str, Any]) -> dict[str, Any]:
    name = params.get("name")
    args = params.get("arguments") or {}
    if not isinstance(name, str) or name not in TOOLS:
        payload = _err(f"unknown tool {name!r}")
    else:
        try:
            payload = TOOLS[name]["handler"](args)
        except Exception as exc:  # pragma: no cover - defensive
            payload = _err(f"handler {name} crashed: {type(exc).__name__}: {exc}")
    text = json.dumps(payload, default=str)
    return {
        "content": [{"type": "text", "text": text}],
        "isError": "error" in payload,
    }


def _handle(req: dict[str, Any]) -> dict[str, Any] | None:
    method = req.get("method")
    req_id = req.get("id")
    params = req.get("params") or {}

    if method == "initialize":
        return _jsonrpc_result(
            req_id,
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        )
    if method == "notifications/initialized":
        return None  # notification, no reply
    if method == "ping":
        return _jsonrpc_result(req_id, {})
    if method == "tools/list":
        return _jsonrpc_result(req_id, _tools_list_payload())
    if method == "tools/call":
        return _jsonrpc_result(req_id, _tools_call(params))
    if method == "shutdown":
        return _jsonrpc_result(req_id, {})
    # Notifications have no id; do not reply.
    if req_id is None:
        return None
    return _jsonrpc_error(req_id, -32601, f"method not found: {method}")


def _serve() -> None:
    # Line-delimited JSON-RPC: one JSON object per line on stdin.
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            req = json.loads(raw)
        except json.JSONDecodeError as exc:
            sys.stdout.write(
                json.dumps(_jsonrpc_error(None, -32700, f"parse error: {exc}")) + "\n"
            )
            sys.stdout.flush()
            continue
        if isinstance(req, list):
            # Batch requests
            replies = []
            for sub in req:
                if not isinstance(sub, dict):
                    continue
                reply = _handle(sub)
                if reply is not None:
                    replies.append(reply)
            if replies:
                sys.stdout.write(json.dumps(replies) + "\n")
                sys.stdout.flush()
            continue
        if not isinstance(req, dict):
            sys.stdout.write(
                json.dumps(_jsonrpc_error(None, -32600, "invalid request")) + "\n"
            )
            sys.stdout.flush()
            continue
        reply = _handle(req)
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


# ---------------------------------------------------------------------------
# CLI helpers (for the smoke test)
# ---------------------------------------------------------------------------


def _print_help() -> None:
    sys.stdout.write(
        "fleet-mcp.py - stdio MCP server\n\n"
        "Usage:\n"
        "  fleet-mcp.py                 Run the MCP server on stdio (default).\n"
        "  fleet-mcp.py --list-tools    Print the tools/list payload as JSON.\n"
        "  fleet-mcp.py --call TOOL [JSON]\n"
        "                               Call a tool with optional JSON args and\n"
        "                               print the result. Useful for ad-hoc\n"
        "                               testing without speaking JSON-RPC.\n"
        "  fleet-mcp.py --help          Show this help.\n"
    )


def _cli_dispatch(argv: list[str]) -> int:
    if not argv:
        _serve()
        return 0
    cmd = argv[0]
    if cmd in {"-h", "--help", "help"}:
        _print_help()
        return 0
    if cmd == "--list-tools":
        sys.stdout.write(json.dumps(_tools_list_payload(), indent=2) + "\n")
        return 0
    if cmd == "--call":
        if len(argv) < 2:
            sys.stderr.write("--call requires a tool name\n")
            return 2
        tool = argv[1]
        args_obj: dict[str, Any] = {}
        if len(argv) >= 3:
            try:
                args_obj = json.loads(argv[2])
            except json.JSONDecodeError as exc:
                sys.stderr.write(f"invalid JSON for args: {exc}\n")
                return 2
        if tool not in TOOLS:
            sys.stderr.write(f"unknown tool: {tool}\n")
            return 2
        result = TOOLS[tool]["handler"](args_obj)
        sys.stdout.write(json.dumps(result, indent=2, default=str) + "\n")
        return 1 if "error" in result else 0
    sys.stderr.write(f"unknown flag: {cmd}\n")
    _print_help()
    return 2


def main() -> None:
    sys.exit(_cli_dispatch(sys.argv[1:]))


if __name__ == "__main__":
    main()
