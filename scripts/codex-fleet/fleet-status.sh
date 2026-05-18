#!/usr/bin/env bash
# shellcheck shell=bash
#
# fleet-status.sh — one-shot JSON snapshot of the entire codex-fleet.
#
# Composes state from tmux (sessions/panes/captures), local caches
# (/tmp/codex-fleet/<account>, /tmp/claude-viz/cap-probe-cache,
# /tmp/claude-viz/stall-watcher.log, /tmp/claude-viz/cap-budget.alert),
# the active plan (.codex-fleet/active-plan or newest openspec/plans/*),
# Colony (colony plan status) and gh (gh pr list).
#
# Output: a single JSON document on STDOUT (jq -c compact). Stable schema
# versioned at schema_version=1. Exit 0 even when no fleet is up
# (tmux_sessions=[] and best-effort partial data elsewhere).
#
# Usage:
#   fleet-status.sh [--pretty] [--plan <slug>] [--socket <name>]
#
# Flags:
#   --pretty        emit indented JSON (jq .) instead of compact
#   --plan <slug>   force the active plan slug (overrides .codex-fleet/active-plan)
#   --socket <name> tmux -L socket name (default: codex-fleet)
#   -h, --help      print usage
#
# Dependencies: bash, python3, jq, tmux (optional), gh (optional), colony (optional).
# No new Rust deps. Designed to power scripts/codex-fleet/mcp/fleet-mcp.py
# (SI-1) and future ratatui dashboards.

set -u
set -o pipefail

PROG="fleet-status.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SOCKET="${CODEX_FLEET_SOCKET:-codex-fleet}"
PLAN_SLUG_OVERRIDE=""
PRETTY=0

usage() {
    cat <<'USAGE'
Usage: fleet-status.sh [--pretty] [--plan <slug>] [--socket <name>]

Emits a single JSON document describing the entire codex-fleet state:
tmux sessions/panes, workers (with classification + claimed task), the
active plan + subtask status histogram, open/merged PRs, capacity probes,
recent blockers, and elapsed ms_to_compose. Exits 0 even with no fleet up.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pretty)
            PRETTY=1
            shift
            ;;
        --plan)
            shift
            PLAN_SLUG_OVERRIDE="${1:-}"
            shift || true
            ;;
        --socket)
            shift
            SOCKET="${1:-}"
            shift || true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s: unknown flag: %s\n' "$PROG" "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# epoch milliseconds (BSD/GNU date both support %s%3N on Linux GNU date)
now_ms() {
    date +%s%3N
}

START_MS="$(now_ms)"

# --- Defaults / file locations ----------------------------------------------
CAP_PROBE_DIR="${CAP_PROBE_CACHE_DIR:-/tmp/claude-viz/cap-probe-cache}"
STALL_LOG="${STALL_WATCHER_LOG:-/tmp/claude-viz/stall-watcher.log}"
CAP_BUDGET_ALERT="${CAP_BUDGET_ALERT_FILE:-/tmp/claude-viz/cap-budget.alert}"
CODEX_FLEET_STAGING="${CODEX_FLEET_STAGING_ROOT:-/tmp/codex-fleet}"
ACTIVE_PLAN_FILE="${ACTIVE_PLAN_FILE:-$REPO_ROOT/.codex-fleet/active-plan}"
ACCOUNTS_YML="${CODEX_FLEET_ACCOUNTS:-$REPO_ROOT/scripts/codex-fleet/accounts.yml}"

have() { command -v "$1" >/dev/null 2>&1; }

# --- tmux_sessions ----------------------------------------------------------
collect_tmux_sessions() {
    if ! have tmux; then
        printf '[]'
        return
    fi
    local raw
    raw="$(tmux -L "$SOCKET" list-sessions \
        -F '#{session_name}|#{session_windows}|#{?session_attached,true,false}' \
        2>/dev/null || true)"
    if [ -z "$raw" ]; then
        printf '[]'
        return
    fi
    printf '%s\n' "$raw" | python3 -c '
import json, sys
out = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split("|")
    if len(parts) != 3:
        continue
    name, windows, attached = parts
    try:
        windows_n = int(windows)
    except ValueError:
        windows_n = 0
    out.append({"name": name, "windows": windows_n, "attached": attached == "true"})
print(json.dumps(out))
'
}

# --- accounts.yml index (email -> {tier, specialty, id, skills}) ------------
build_accounts_index() {
    if [ ! -r "$ACCOUNTS_YML" ]; then
        printf '{}'
        return
    fi
    python3 - "$ACCOUNTS_YML" <<'PY'
import json, sys, re

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()
except OSError:
    print("{}")
    sys.exit(0)

# Lightweight YAML reader: we only need accounts: [ {id,email,tier,specialty,...} ]
# Avoid pulling in PyYAML. Parse with a tiny state machine geared to the schema
# in accounts.example.yml.
out = {}
cur = None

def flush():
    global cur
    if cur and cur.get("email"):
        out[cur["email"]] = cur
    cur = None

def parse_scalar(v):
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        if not inner:
            return []
        return [x.strip().strip('"').strip("'") for x in inner.split(",") if x.strip()]
    return v.strip('"').strip("'")

in_accounts = False
for raw in lines:
    line = raw.rstrip("\n")
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if stripped == "accounts:":
        in_accounts = True
        continue
    if not in_accounts:
        # Allow top-level keys above accounts without breaking.
        continue
    m = re.match(r"^( *)- *(\w+) *: *(.*)$", line)
    if m:
        flush()
        cur = {}
        key, val = m.group(2), m.group(3)
        cur[key] = parse_scalar(val) if val.strip() else ""
        continue
    m = re.match(r"^( +)(\w+) *: *(.*)$", line)
    if m and cur is not None:
        key, val = m.group(2), m.group(3)
        cur[key] = parse_scalar(val) if val.strip() else ""
        continue
flush()

# Normalize a couple of common typings.
for email, acc in out.items():
    tier = acc.get("tier") or acc.get("rate_limit_tier") or ""
    acc["tier"] = tier if isinstance(tier, str) else ""
    sp = acc.get("specialty") or []
    if isinstance(sp, str):
        sp = [sp] if sp else []
    acc["specialty"] = sp

print(json.dumps(out))
PY
}

# --- per-pane capture + classification (workers list) -----------------------
collect_workers() {
    local accounts_index_json="$1"
    if ! have tmux; then
        printf '[]'
        return
    fi
    local panes
    panes="$(tmux -L "$SOCKET" list-panes -a \
        -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_pid}|#{pane_current_path}|#{pane_active}|#{pane_title}' \
        2>/dev/null || true)"
    if [ -z "$panes" ]; then
        printf '[]'
        return
    fi

    # For each pane: capture last 30 lines and feed everything into python3.
    local tmpdir
    tmpdir="$(mktemp -d -t fleet-status-panes.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN

    local manifest="$tmpdir/manifest"
    : >"$manifest"

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local pane_id pane_pid cwd active title
        pane_id="$(printf '%s' "$line" | cut -d'|' -f1)"
        pane_pid="$(printf '%s' "$line" | cut -d'|' -f2)"
        cwd="$(printf '%s' "$line" | cut -d'|' -f3)"
        active="$(printf '%s' "$line" | cut -d'|' -f4)"
        title="$(printf '%s' "$line" | cut -d'|' -f5-)"

        local safe
        safe="$(printf '%s' "$pane_id" | tr ':/.' '___')"
        local cap_file="$tmpdir/$safe.cap"
        tmux -L "$SOCKET" capture-pane -p -t "$pane_id" -S -30 2>/dev/null >"$cap_file" || : >"$cap_file"

        # Manifest is tab-separated to avoid collisions with pipe in titles.
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$pane_id" "$pane_pid" "$cwd" "$active" "$title" "$cap_file" >>"$manifest"
    done <<EOF
$panes
EOF

    python3 - "$manifest" "$accounts_index_json" "$CODEX_FLEET_STAGING" <<'PY'
import json, os, re, sys, time

manifest_path, accounts_json, staging_root = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    accounts = json.loads(accounts_json) if accounts_json else {}
except Exception:
    accounts = {}

WORKING_RE = re.compile(r"Working\s*\(\s*(\d+)\s*([smh])\s*\)", re.IGNORECASE)
WORKED_RE = re.compile(r"Worked for\s+(?:(\d+)\s*m\s*)?(\d+)\s*s", re.IGNORECASE)


def classify(cap_text):
    """Return (classification, last_activity_age_seconds)."""
    age = 0
    text_lower = cap_text.lower()
    # last_activity_age from "Working (Xs)" or "Worked for Xm Ys"
    m = WORKING_RE.search(cap_text)
    if m:
        n, unit = int(m.group(1)), m.group(2).lower()
        if unit == "s":
            age = n
        elif unit == "m":
            age = n * 60
        elif unit == "h":
            age = n * 3600
        return "working", age
    if ("error" in text_lower
            or "panic:" in text_lower
            or "fatal:" in text_lower
            or "blocked" in text_lower):
        m2 = WORKED_RE.search(cap_text)
        if m2:
            mins = int(m2.group(1) or 0)
            secs = int(m2.group(2) or 0)
            age = mins * 60 + secs
        return "errored", age
    if ("do you trust" in text_lower
            or "create a plan?" in text_lower
            or "external agent config" in text_lower):
        return "waiting-on-prompt", 0
    m2 = WORKED_RE.search(cap_text)
    if m2:
        mins = int(m2.group(1) or 0)
        secs = int(m2.group(2) or 0)
        age = mins * 60 + secs
    if "gpt-5.5" in text_lower:
        return "idle", age
    return "unknown", age


def parse_agent_from_title(title):
    """codex-fleet sets pane title to 'codex-<name>-<acct>'.
    Returns (agent, account_id_guess) where account_id_guess is what comes
    after the second '-' — useful to disambiguate accounts when multiple
    accounts share an agent name.
    """
    if not title:
        return "unknown", None
    title = title.strip()
    if title.lower().startswith("codex-"):
        rest = title[len("codex-"):]
        return f"codex-{rest}", rest
    return title, None


def read_account_email(staging_root, account_guess):
    """Per the spec, account staging dirs live under /tmp/codex-fleet/<acct>.
    Some sites stash an `env` file with KEY=VAL pairs that include the email.
    Return email if found; otherwise None.
    """
    if not account_guess:
        return None
    env_path = os.path.join(staging_root, account_guess, "env")
    if not os.path.isfile(env_path):
        return None
    try:
        with open(env_path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("CODEX_ACCOUNT_EMAIL=") or line.startswith("ACCOUNT_EMAIL="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return None


def match_account_to_index(account_guess, accounts_idx):
    """Try several heuristics to map a pane's account_guess to an email key
    in the accounts.yml index. Falls back to None.
    """
    if not account_guess:
        return None, None
    # Direct hit: account_guess already an email-ish key
    if account_guess in accounts_idx:
        return account_guess, accounts_idx[account_guess]
    # If account_guess looks like "name-domain" (dash-separated by spawn-fleet
    # naming), try emails whose local-part-and-domain hyphenate to this.
    for email, acc in accounts_idx.items():
        if not email:
            continue
        # collapse @ . into - and lowercase
        slug = email.replace("@", "-").replace(".", "-").lower()
        if account_guess.lower().endswith(slug) or slug.endswith(account_guess.lower()):
            return email, acc
        local = email.split("@", 1)[0].lower()
        if account_guess.lower() == local or account_guess.lower().startswith(local + "-"):
            return email, acc
        # accounts.yml `id` field
        aid = (acc.get("id") or "").lower() if isinstance(acc, dict) else ""
        if aid and aid == account_guess.lower():
            return email, acc
    return None, None


workers = []
try:
    with open(manifest_path, "r", encoding="utf-8") as fh:
        rows = [ln.rstrip("\n") for ln in fh if ln.strip()]
except OSError:
    rows = []

for row in rows:
    parts = row.split("\t")
    if len(parts) < 6:
        continue
    pane_id, pane_pid, cwd, _active, title, cap_path = parts[:6]
    try:
        with open(cap_path, "r", encoding="utf-8", errors="replace") as fh:
            cap_text = fh.read()
    except OSError:
        cap_text = ""

    classification, age = classify(cap_text)
    agent, account_guess = parse_agent_from_title(title)

    # Resolve account_email + tier + specialty
    account_email = read_account_email(staging_root, account_guess)
    tier = ""
    specialty = ""
    if not account_email:
        matched_email, matched_acc = match_account_to_index(account_guess, accounts)
        if matched_email:
            account_email = matched_email
            if isinstance(matched_acc, dict):
                tier = matched_acc.get("tier") or ""
                sp = matched_acc.get("specialty") or []
                if isinstance(sp, list):
                    specialty = sp[0] if sp else ""
                elif isinstance(sp, str):
                    specialty = sp
    elif account_email in accounts:
        acc = accounts[account_email]
        if isinstance(acc, dict):
            tier = acc.get("tier") or ""
            sp = acc.get("specialty") or []
            if isinstance(sp, list):
                specialty = sp[0] if sp else ""
            elif isinstance(sp, str):
                specialty = sp

    try:
        codex_pid = int(pane_pid)
    except ValueError:
        codex_pid = 0

    workers.append({
        "pane_id": pane_id,
        "agent": agent,
        "account_email": account_email,
        "tier": tier,
        "specialty": specialty,
        "cwd": cwd,
        "last_activity_age_seconds": int(age),
        "classification": classification,
        "current_codex_pid": codex_pid,
        # claimed_task is filled in by the colony plan status pass downstream;
        # leave a structured null here so consumers have a stable schema.
        "claimed_task": None,
    })

print(json.dumps(workers))
PY
}

# --- resolve plan slug ------------------------------------------------------
resolve_plan_slug() {
    if [ -n "$PLAN_SLUG_OVERRIDE" ]; then
        printf '%s' "$PLAN_SLUG_OVERRIDE"
        return
    fi
    if [ -r "$ACTIVE_PLAN_FILE" ]; then
        local slug
        slug="$(tr -d '\r\n' <"$ACTIVE_PLAN_FILE")"
        if [ -n "$slug" ]; then
            printf '%s' "$slug"
            return
        fi
    fi
    # Fallback: newest dir under openspec/plans/ that has a plan.json
    local plans_root="$REPO_ROOT/openspec/plans"
    if [ -d "$plans_root" ]; then
        # shellcheck disable=SC2012
        local newest
        newest="$(ls -1t "$plans_root" 2>/dev/null | while IFS= read -r d; do
            [ -f "$plans_root/$d/plan.json" ] && { printf '%s\n' "$d"; break; }
        done)"
        if [ -n "$newest" ]; then
            printf '%s' "$newest"
            return
        fi
    fi
    printf ''
}

# --- plan + plan_subtasks ---------------------------------------------------
collect_plan_blocks() {
    local slug="$1"
    if [ -z "$slug" ]; then
        printf '{"plan":null,"plan_subtasks":[]}'
        return
    fi
    local plan_json_path="$REPO_ROOT/openspec/plans/$slug/plan.json"
    local colony_text_file
    colony_text_file="$(mktemp -t fleet-status-colony.XXXXXX)"
    if have colony; then
        colony plan status "$slug" --cwd "$REPO_ROOT" >"$colony_text_file" 2>/dev/null || true
    fi
    python3 - "$slug" "$plan_json_path" "$colony_text_file" <<'PY'
import json, os, sys

slug, plan_path, colony_text_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(colony_text_path, "r", encoding="utf-8", errors="replace") as fh:
        colony_text = fh.read()
except OSError:
    colony_text = ""

try:
    with open(plan_path, "r", encoding="utf-8") as fh:
        plan_doc = json.load(fh)
except (OSError, json.JSONDecodeError):
    plan_doc = None

tasks = (plan_doc or {}).get("tasks") or []
title = (plan_doc or {}).get("title") or ""

# Parse 'colony plan status' textual output for status histogram counts when
# available. The CLI prints e.g. "tasks: 0 completed, 0 claimed, 12 available,
# 0 blocked". Use that for the histogram if we got output; otherwise fall back
# to the plan.json field statuses.
hist = {"available": 0, "claimed": 0, "working": 0, "completed": 0, "blocked": 0}
import re
m = re.search(
    r"tasks:\s*(\d+)\s+completed,\s*(\d+)\s+claimed,\s*(\d+)\s+available,\s*(\d+)\s+blocked",
    colony_text or "",
)
if m:
    hist["completed"] = int(m.group(1))
    hist["claimed"] = int(m.group(2))
    hist["available"] = int(m.group(3))
    hist["blocked"] = int(m.group(4))

subtasks = []
for t in tasks:
    if not isinstance(t, dict):
        continue
    idx = t.get("subtask_index")
    st = t.get("status") or "available"
    if not m:
        hist[st] = hist.get(st, 0) + 1
    subtasks.append({
        "index": idx if isinstance(idx, int) else None,
        "title": t.get("title") or "",
        "status": st,
        "claimed_by_agent": t.get("claimed_by_agent"),
        "completed_summary": t.get("completed_summary"),
    })

plan_block = {
    "slug": slug,
    "title": title,
    "subtask_count": len(subtasks),
    "status_histogram": hist,
}
print(json.dumps({"plan": plan_block, "plan_subtasks": subtasks}))
PY
    rm -f "$colony_text_file"
}

# --- annotate workers with claimed_task from plan_subtasks ------------------
annotate_workers_with_claimed_task() {
    local workers_json="$1"
    local plan_block_json="$2"
    local slug="$3"
    # Pass both JSON blobs on stdin as a tiny envelope so we never inline
    # untrusted JSON into the python script source. Use python3 -c so stdin
    # is genuinely the envelope (with `python3 -` the heredoc would shadow it).
    local envelope
    envelope="$(jq -n \
        --argjson workers "$workers_json" \
        --argjson plan "$plan_block_json" \
        '{workers:$workers, plan:$plan}')"
    printf '%s' "$envelope" | python3 -c '
import json, sys

slug = sys.argv[1]
env = json.load(sys.stdin)
workers = env.get("workers") or []
plan_block = env.get("plan") or {}
subtasks = plan_block.get("plan_subtasks") or []

# Build agent -> claimed subtask map.
agent_to_task = {}
for st in subtasks:
    cb = st.get("claimed_by_agent")
    if not cb:
        continue
    agent_to_task[cb] = {
        "plan_slug": slug,
        "subtask_index": st.get("index"),
        "title": st.get("title") or "",
    }

for w in workers:
    a = w.get("agent")
    if a and a in agent_to_task:
        w["claimed_task"] = agent_to_task[a]

print(json.dumps(workers))
' "$slug"
}

# --- PRs --------------------------------------------------------------------
collect_prs() {
    local slug="$1"
    if ! have gh; then
        printf '{"open_prs":[],"merged_prs_for_plan":[]}'
        return
    fi
    # Best-effort: pull a wide net (50 PRs) and filter in python.
    local raw
    raw="$(gh pr list \
        --state all \
        --json number,title,headRefName,state,mergedAt,mergeable,statusCheckRollup \
        --limit 50 2>/dev/null || printf '[]')"
    if [ -z "$raw" ]; then
        raw='[]'
    fi
    printf '%s' "$raw" | python3 -c '
import json, re, sys

slug = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    prs = json.load(sys.stdin)
except Exception:
    prs = []

# Branch filter: agent/.*/(edge|si)-... — these are the fleet-spawned branches.
BRANCH_RE = re.compile(r"^agent/[^/]+/(?:edge|si)-", re.IGNORECASE)
# Title filter for the active plan: tags like [SI-x], [TE-x], [edge-N], etc.
# Be permissive: any PR whose branch matches the fleet pattern counts as
# fleet-owned for the purposes of open_prs. merged_prs_for_plan is the same
# pattern filtered to state=MERGED.

def rollup_state(rollup):
    if not isinstance(rollup, list) or not rollup:
        return "NONE"
    seen = set()
    for r in rollup:
        if not isinstance(r, dict):
            continue
        status = (r.get("status") or "").upper()
        conclusion = (r.get("conclusion") or "").upper()
        if conclusion:
            seen.add(conclusion)
        elif status:
            seen.add(status)
    if "FAILURE" in seen or "TIMED_OUT" in seen or "CANCELLED" in seen:
        return "FAILURE"
    if "IN_PROGRESS" in seen or "PENDING" in seen or "QUEUED" in seen:
        return "PENDING"
    if "SUCCESS" in seen and not (seen - {"SUCCESS", "NEUTRAL", "SKIPPED"}):
        return "SUCCESS"
    return next(iter(seen)) if seen else "NONE"

open_prs = []
merged_prs = []
for pr in prs:
    if not isinstance(pr, dict):
        continue
    branch = pr.get("headRefName") or ""
    if not BRANCH_RE.match(branch):
        continue
    item = {
        "number": pr.get("number"),
        "title": pr.get("title") or "",
        "branch": branch,
        "mergeable": pr.get("mergeable") or "UNKNOWN",
        "checks_state": rollup_state(pr.get("statusCheckRollup")),
    }
    state = (pr.get("state") or "").upper()
    if state == "OPEN":
        open_prs.append(item)
    elif state == "MERGED":
        merged_prs.append({
            "number": pr.get("number"),
            "title": pr.get("title") or "",
            "merged_at": pr.get("mergedAt") or "",
        })

print(json.dumps({"open_prs": open_prs, "merged_prs_for_plan": merged_prs}))
' "$slug"
}

# --- capacity ---------------------------------------------------------------
collect_capacity() {
    if [ ! -d "$CAP_PROBE_DIR" ]; then
        printf '[]'
        return
    fi
    python3 - "$CAP_PROBE_DIR" <<'PY'
import json, os, sys, time

cap_dir = sys.argv[1]
out = []
now = int(time.time())
try:
    entries = sorted(os.listdir(cap_dir))
except OSError:
    entries = []
for name in entries:
    if not name.endswith(".json"):
        continue
    path = os.path.join(cap_dir, name)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, json.JSONDecodeError):
        continue
    email = name[:-len(".json")]
    probed_at = doc.get("probed_at") or 0
    try:
        probed_at = int(probed_at)
    except (TypeError, ValueError):
        probed_at = 0
    cache_age = max(0, now - probed_at) if probed_at else None
    out.append({
        "account_email": email,
        "last_probe_at": probed_at,
        "last_status": doc.get("verdict") or "unknown",
        "cache_age_s": cache_age,
    })
print(json.dumps(out))
PY
}

# --- blockers ---------------------------------------------------------------
collect_blockers() {
    python3 - "$STALL_LOG" "$CAP_BUDGET_ALERT" <<'PY'
import json, os, sys

stall_log, alert_flag = sys.argv[1], sys.argv[2]
out = []
if os.path.isfile(alert_flag):
    out.append("cap-budget alert flag present: " + alert_flag)
if os.path.isfile(stall_log):
    try:
        with open(stall_log, "r", encoding="utf-8", errors="replace") as fh:
            tail = fh.readlines()[-50:]
    except OSError:
        tail = []
    for line in tail:
        line = line.rstrip("\n")
        low = line.lower()
        if "stall-dismiss" in low or "blocked" in low or "stranded=" in low and "stranded=0" not in low:
            out.append(line)
print(json.dumps(out))
PY
}

# --- compose ----------------------------------------------------------------
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
plan_slug="$(resolve_plan_slug)"
accounts_idx_json="$(build_accounts_index)"
tmux_sessions_json="$(collect_tmux_sessions)"
workers_raw_json="$(collect_workers "$accounts_idx_json")"
plan_block_json="$(collect_plan_blocks "$plan_slug")"
workers_json="$(annotate_workers_with_claimed_task "$workers_raw_json" "$plan_block_json" "$plan_slug")"
prs_block_json="$(collect_prs "$plan_slug")"
capacity_json="$(collect_capacity)"
blockers_json="$(collect_blockers)"

END_MS="$(now_ms)"
ELAPSED_MS=$(( END_MS - START_MS ))

# Final assembly via jq to guarantee valid JSON regardless of any component's
# quoting weirdness. jq --argjson validates every fragment as JSON.
final_json="$(jq -n \
    --arg generated_at "$generated_at" \
    --argjson tmux_sessions "$tmux_sessions_json" \
    --argjson workers "$workers_json" \
    --argjson plan_block "$plan_block_json" \
    --argjson prs_block "$prs_block_json" \
    --argjson capacity "$capacity_json" \
    --argjson blockers "$blockers_json" \
    --argjson ms_to_compose "$ELAPSED_MS" \
    '{
        schema_version: 1,
        generated_at_utc: $generated_at,
        tmux_sessions: $tmux_sessions,
        workers: $workers,
        plan: $plan_block.plan,
        plan_subtasks: ($plan_block.plan_subtasks // []),
        open_prs: ($prs_block.open_prs // []),
        merged_prs_for_plan: ($prs_block.merged_prs_for_plan // []),
        capacity: $capacity,
        blockers: $blockers,
        ms_to_compose: $ms_to_compose,
    }')"

if [ "$PRETTY" -eq 1 ]; then
    printf '%s' "$final_json" | jq .
else
    printf '%s' "$final_json" | jq -c .
fi

exit 0
