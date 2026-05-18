#!/usr/bin/env bash
# full-bringup — one command that brings up a complete codex fleet:
#   * pre-spawn git cleanup
#   * publish the priority plan to Colony if it's only on disk
#   * tmux session `codex-fleet` with overview / fleet / plan / waves windows
#   * sibling `fleet-ticker` session with fleet-tick + cap-swap + state-pump
#
# Designed to be the SINGLE entry point so half-fleets (workers without
# dashboards / published plans / cap-swap) cannot happen.
#
# Usage:
#   bash scripts/codex-fleet/full-bringup.sh [--plan-slug <slug>] [--n <N>] [--no-attach]
#
# If --plan-slug is omitted, picks the newest openspec/plans/* by trailing
# YYYY-MM-DD slug suffix (matches plan-anim-generic.sh / waves-anim-generic.sh).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Autodetect REPO from the clone location; env override wins. Lets the
# same script run from any path (e.g. ~/codex-fleet/) and lets operators
# point CODEX_FLEET_REPO_ROOT at a separate project root for plan lookup.
REPO="${REPO:-${CODEX_FLEET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"

# ----------------------------------------------------------------------------
# Route the fleet onto its dedicated tmux socket.
# ----------------------------------------------------------------------------
# Default: fleet runs on socket `codex-fleet` with the vendored oh-my-tmux
# config from scripts/codex-fleet/tmux/vendor/. Operator's normal tmux server
# (default socket) is unaffected. Opt out with CODEX_FLEET_TMUX_SOCKET="".
#
# The lib/_tmux.sh wrapper defines a `tmux()` bash function that transparently
# rewrites every `tmux ...` call in this script (and any child bash scripts
# that source the wrapper too) to `tmux -L "$CODEX_FLEET_TMUX_SOCKET" ...`.
# When CODEX_FLEET_TMUX_SOCKET is empty/unset, the wrapper is a transparent
# pass-through — behavior identical to pre-#38 fleet bring-up.
export CODEX_FLEET_TMUX_SOCKET="${CODEX_FLEET_TMUX_SOCKET-codex-fleet}"
export CODEX_FLEET_REPO_ROOT="$REPO"  # bindings need this in tmux server env
source "$SCRIPT_DIR/lib/_tmux.sh"

if [[ -n "$CODEX_FLEET_TMUX_SOCKET" ]]; then
  # Ensure vendored oh-my-tmux is present; start the dedicated server with
  # its config so the daemon loads oh-my-tmux's defaults + our overlay.
  # start-server is a no-op when the server is already running. We use
  # `command tmux` here to bypass the wrapper because the wrapper would also
  # append `-L`, which is already present in our invocation — everywhere ELSE
  # in this script the wrapper does the right thing, but here we need a
  # deterministic bootstrap.
  "$SCRIPT_DIR/tmux/setup.sh" > /dev/null
  command tmux -L "$CODEX_FLEET_TMUX_SOCKET" \
    -f "$SCRIPT_DIR/tmux/vendor/oh-my-tmux/.tmux.conf" \
    start-server 2>/dev/null || true
  # Push the repo root into the tmux server's global env so the
  # iOS-style bindings (prefix-m action sheet, prefix-Tab jumper,
  # prefix-C-h help) sourced by codex-fleet-overlay.conf can resolve
  # `${CODEX_FLEET_REPO_ROOT}` at fire time.
  command tmux -L "$CODEX_FLEET_TMUX_SOCKET" \
    set-environment -g CODEX_FLEET_REPO_ROOT "$REPO" 2>/dev/null || true
  # Apply codex-fleet option overrides (mouse on, history-limit, iOS borders).
  # See scripts/codex-fleet/tmux/up.sh for why these are imperative
  # rather than declarative in .tmux.conf.local.
  command tmux -L "$CODEX_FLEET_TMUX_SOCKET" set-option -g mouse on 2>/dev/null || true
  command tmux -L "$CODEX_FLEET_TMUX_SOCKET" set-option -g history-limit 50000 2>/dev/null || true
  command tmux -L "$CODEX_FLEET_TMUX_SOCKET" set-option -g pane-border-style 'fg=#3c3c41' 2>/dev/null || true
  command tmux -L "$CODEX_FLEET_TMUX_SOCKET" set-option -g pane-active-border-style 'fg=#0a84ff' 2>/dev/null || true
  # Source the iOS-style bindings AFTER server init. Done imperatively
  # because oh-my-tmux's `_apply_bindings` runs late and would otherwise
  # re-stamp prefix-m / prefix-Tab / prefix-C-h back to its defaults.
  command tmux -L "$CODEX_FLEET_TMUX_SOCKET" \
    source-file "$SCRIPT_DIR/tmux-bindings.conf" 2>/dev/null || true
fi
WAKE="${WAKE:-/tmp/codex-fleet-wake-prompt.md}"
N_PANES=8
N_PANES_EXPLICIT=0
# Hard ceiling for auto-grown N_PANES so a 100-account user doesn't
# accidentally spawn 100 panes. Override via env if you really do want more.
N_PANES_AUTO_MAX="${CODEX_FLEET_N_PANES_AUTO_MAX:-24}"
ATTACH=1
PLAN_SLUG=""
FLEET_ID="${FLEET_ID:-}"
AUTO_FLEET_ID=0
NO_CAP_CACHE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --plan-slug) PLAN_SLUG="$2"; shift 2 ;;
    --n) N_PANES="$2"; N_PANES_EXPLICIT=1; shift 2 ;;
    --no-attach) ATTACH=0; shift ;;
    --fleet-id) FLEET_ID="$2"; shift 2 ;;
    --auto-fleet-id) AUTO_FLEET_ID=1; shift ;;
    --no-cap-cache) NO_CAP_CACHE=1; shift ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

log() { printf '\033[36m[full-bringup]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[full-bringup]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[full-bringup] FATAL:\033[0m %s\n' "$*"; exit 1; }

# Source the MCP preflight so stage_account() (below) renders a fleet-local
# config.toml driven by FLEET_COLONY_* + FLEET_PATH. The preflight is
# best-effort: an unhealthy Colony degrades the staged config rather than
# failing bringup, matching the worker-prompt's shell-CLI fallback.
preflight_log() { log "preflight: $*"; }
preflight_warn() { warn "preflight: $*"; }
# shellcheck source=lib/mcp-preflight.sh
. "$SCRIPT_DIR/lib/mcp-preflight.sh"

# Ensure the Colony worker daemon (embeddings + viewer + MCP context store)
# is running so every fleet worker can read/write task context from boot.
# Idempotent + non-fatal: if Colony is unhealthy the fleet still spawns and
# falls back to shell-CLI calls, matching the worker-prompt's fallback path.
fleet_ensure_colony_running

FLEET_CONFIG_TMPL="${CODEX_FLEET_CONFIG_TMPL:-$SCRIPT_DIR/fleet-config.toml.tmpl}"

cd "$REPO"

# Fleet ID handling — lets you run multiple parallel fleets on different
# plans. Default (empty FLEET_ID) keeps the original session names
# (`codex-fleet`, `fleet-ticker`) and global `/tmp/claude-viz/` state for
# back-compat. With `--fleet-id N`, sessions become `codex-fleet-N` /
# `fleet-ticker-N` and state moves under `/tmp/claude-viz/fleet-N/`.
#
# `--auto-fleet-id` picks the lowest free integer ≥2 when the default
# session is already up. Use it to bring up a second/third fleet without
# having to remember which IDs are taken.
if [ "$AUTO_FLEET_ID" = "1" ] && [ -z "$FLEET_ID" ]; then
  if tmux has-session -t "codex-fleet" 2>/dev/null; then
    n=2
    while tmux has-session -t "codex-fleet-$n" 2>/dev/null; do n=$((n+1)); done
    FLEET_ID="$n"
    log "auto-picked --fleet-id $FLEET_ID (codex-fleet, codex-fleet-2..$((n-1)) already up)"
  fi
fi

if [ -n "$FLEET_ID" ]; then
  SESSION="${SESSION:-codex-fleet-$FLEET_ID}"
  TICKER_SESSION="${TICKER_SESSION:-fleet-ticker-$FLEET_ID}"
  FLEET_STATE_DIR="${FLEET_STATE_DIR:-/tmp/claude-viz/fleet-$FLEET_ID}"
else
  SESSION="${SESSION:-codex-fleet}"
  TICKER_SESSION="${TICKER_SESSION:-fleet-ticker}"
  FLEET_STATE_DIR="${FLEET_STATE_DIR:-/tmp/claude-viz}"
fi
export FLEET_ID FLEET_STATE_DIR
mkdir -p "$FLEET_STATE_DIR"

# 1. Refuse if fleet already up
if tmux has-session -t "$SESSION" 2>/dev/null; then
  die "tmux session '$SESSION' already exists. Run scripts/codex-fleet/down.sh first, or pass --fleet-id <N> / --auto-fleet-id to start a parallel fleet."
fi

# 2. Pick the priority plan slug
if [ -z "$PLAN_SLUG" ]; then
  PLAN_SLUG=$(python3 - <<PY
import os, re, glob
plans = glob.glob("$REPO/openspec/plans/*/plan.json")
def key(p):
    s = os.path.basename(os.path.dirname(p))
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})$', s)
    d = (int(m[1]),int(m[2]),int(m[3])) if m else (0,0,0)
    return (d, os.path.getmtime(p))
plans.sort(key=key, reverse=True)
print(os.path.basename(os.path.dirname(plans[0])) if plans else "")
PY
)
fi
[ -n "$PLAN_SLUG" ] || die "no plan slug provided and no openspec/plans/* found"
[ -f "openspec/plans/$PLAN_SLUG/plan.json" ] || die "plan workspace missing: openspec/plans/$PLAN_SLUG/plan.json"
log "priority plan: $PLAN_SLUG"

# 2b. Build --add-dir flags from plan metadata.writable_roots (schema:
# scripts/codex-fleet/lib/plan-meta.md). Falls back to the recodee +
# codex-fleet pair when the plan declares nothing.
ADD_DIR_FLAGS=$(PLAN_FILE="openspec/plans/$PLAN_SLUG/plan.json" python3 - <<'PY'
import json, os
p = os.environ["PLAN_FILE"]
try:
    with open(p) as f:
        data = json.load(f)
except Exception:
    data = {}
roots = (data.get("metadata") or {}).get("writable_roots") or []
if not roots:
    roots = ["/home/deadpool/Documents/recodee", "/home/deadpool/Documents/codex-fleet"]
print(" ".join(f"--add-dir {r}" for r in roots))
PY
)
[ -n "$ADD_DIR_FLAGS" ] || die "failed to compute ADD_DIR_FLAGS for plan $PLAN_SLUG"

# Preflight every writable root: must exist + be writable by the current user.
add_count=0
for path in $(printf '%s\n' "$ADD_DIR_FLAGS" | awk '{for(i=1;i<=NF;i++) if($i=="--add-dir"){print $(i+1)}}'); do
  [ -d "$path" ] || die "writable root unreachable: $path (chmod / chown / mount?)"
  [ -w "$path" ] || die "writable root unreachable: $path (chmod / chown / mount?)"
  add_count=$((add_count + 1))
done
log "writable roots ok: $add_count root(s)"

# 3. Pre-spawn git cleanup (prevents 'incorrect old value provided' inside agent-branch-start.sh)
log "pruning stale remote refs"
git -C "$REPO" remote prune origin 2>&1 | sed 's/^/  /' || true
git -C "$REPO" fetch --prune origin 2>&1 | sed 's/^/  /' >/dev/null || true

# 4. Ensure ALL plans on disk are published to Colony so task_plan_list shows them.
#
# Why publish every plan, not just the priority one: this is what unlocks
# fleet parallelism. With 8 worker panes and a single linear plan, panes
# serialize on `task_ready_for_agent` against one task graph. With every
# `openspec/plans/*/plan.json` published, Colony can route concurrent work
# across all of them — workers pull from whichever plan has deps-satisfied
# `available` tasks, not just the priority one. The priority plan stays
# first in the list (used by force-claim's plan-pinning and by 2b's
# writable-roots preflight) but is no longer the only published plan.
#
# 5-min per-slug publish cache short-circuits the second/third bringup of
# the same plan — colony plan publish is idempotent but the round-trip
# costs ~2-3s + an MCP call per plan, which adds up across N plans.
#
# Errors on a single plan are non-fatal: one bad plan.json shouldn't block
# the whole bringup. We warn and continue so the rest of the fleet still
# comes up with the plans that did publish.
ALL_PLAN_SLUGS=$(PRIORITY="$PLAN_SLUG" python3 - <<PY
import os, re, glob
priority = os.environ.get("PRIORITY", "")
plans = glob.glob("$REPO/openspec/plans/*/plan.json")
def key(p):
    s = os.path.basename(os.path.dirname(p))
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})$', s)
    d = (int(m[1]),int(m[2]),int(m[3])) if m else (0,0,0)
    return (d, os.path.getmtime(p))
plans.sort(key=key, reverse=True)
slugs = [os.path.basename(os.path.dirname(p)) for p in plans]
# Stable order: priority first, then everything else newest-by-date desc.
if priority and priority in slugs:
    slugs = [priority] + [s for s in slugs if s != priority]
for s in slugs:
    print(s)
PY
)
mkdir -p /tmp/codex-fleet
plan_publish_total=0
plan_publish_ok=0
plan_publish_cached=0
while IFS= read -r slug; do
  [ -z "$slug" ] && continue
  plan_publish_total=$((plan_publish_total + 1))
  mark_file="/tmp/codex-fleet/.plan-publish.$slug.mark"
  if [ -f "$mark_file" ]; then
    mark_age=$(( $(date +%s) - $(stat -c %Y "$mark_file" 2>/dev/null || echo 0) ))
    if [ "$mark_age" -lt 300 ]; then
      log "plan publish: cache hit ($slug) age=${mark_age}s"
      plan_publish_cached=$((plan_publish_cached + 1))
      continue
    fi
  fi
  log "publishing plan: $slug"
  if colony plan publish "$slug" --agent claude --session "full-bringup-$(date +%s)" 2>&1 | sed 's/^/  /'; then
    touch "$mark_file"
    plan_publish_ok=$((plan_publish_ok + 1))
  else
    warn "publish returned non-zero for $slug; continuing. Workers may not see this plan in task_ready_for_agent."
  fi
done <<< "$ALL_PLAN_SLUGS"
log "published $((plan_publish_ok + plan_publish_cached))/$plan_publish_total plans (priority=$PLAN_SLUG, ok=$plan_publish_ok, cached=$plan_publish_cached)"

# 5. Verify wake prompt exists
if [ ! -f "$WAKE" ]; then
  warn "wake prompt missing at $WAKE; using scripts/codex-fleet/worker-prompt.md"
  WAKE="$SCRIPT_DIR/worker-prompt.md"
  [ -f "$WAKE" ] || die "no wake prompt found at $WAKE either"
fi

# 6. Pick candidate accounts. Two-stage filter:
#    (a) Score by agent-auth's 5h% * weekly% (fast, but unreliable for codex
#        CLI's own rolling cap).
#    (b) Probe each candidate with `codex exec` to detect the *real* cap
#        state. We probe EVERY account that has any meaningful budget left —
#        cap-probe.sh has its own per-email cache so re-probing 30+ accounts
#        on a warm cache is cheap. Skipping the *3 cap is what lets the
#        bringup actually use all 30+ accounts when most are partially used.
#    Override via CODEX_FLEET_TOP_CANDIDATES (default 0 = no cap, probe all
#    that pass the minimum-budget filter). Floors are deliberately permissive
#    (5/5) — anything with a non-trivial budget gets probed; the live
#    `codex exec` ping is the source of truth for "actually usable".
TOP="${CODEX_FLEET_TOP_CANDIDATES:-0}"
MIN_5H="${CODEX_FLEET_MIN_5H_PCT:-5}"
MIN_WEEKLY="${CODEX_FLEET_MIN_WEEKLY_PCT:-5}"
if [ "$TOP" = "0" ]; then
  log "picking ALL candidate accounts with 5h>=${MIN_5H}%, weekly>=${MIN_WEEKLY}% (will probe + spawn min(healthy, $N_PANES) workers)"
else
  log "picking top $TOP candidate accounts with 5h>=${MIN_5H}%, weekly>=${MIN_WEEKLY}% (override via CODEX_FLEET_TOP_CANDIDATES)"
fi
CANDIDATES=$(agent-auth list 2>/dev/null | N="$TOP" MIN_H="$MIN_5H" MIN_W="$MIN_WEEKLY" python3 -c '
import os, sys, re
n = int(os.environ["N"])           # 0 means "no cap, return all"
mh = int(os.environ["MIN_H"])
mw = int(os.environ["MIN_W"])
rows = []
for line in sys.stdin:
    em = re.search(r"([\w.+-]+@[\w.-]+\.[a-z]+)", line)
    if not em: continue
    email = em.group(1)
    h5m = re.search(r"5h=(\d+)%", line); wkm = re.search(r"weekly=(\d+)%", line)
    if not h5m or not wkm: continue
    h, w = int(h5m.group(1)), int(wkm.group(1))
    if h < mh or w < mw: continue
    rows.append((h*w, email))
rows.sort(reverse=True)
out = rows if n == 0 else rows[:n]
for _, email in out:
    print(email)
')
[ -n "$CANDIDATES" ] || die "no candidate accounts found (need 5h>=${MIN_5H}%, wk>=${MIN_WEEKLY}% in agent-auth list — relax via CODEX_FLEET_MIN_5H_PCT / CODEX_FLEET_MIN_WEEKLY_PCT)"
CAND_N=$(printf "%s\n" "$CANDIDATES" | wc -l)
log "ranked $CAND_N candidates by agent-auth score; running live probe..."

# (b) Live probe — keep only candidates whose codex CLI is actually usable.
# 5-min cache short-circuits back-to-back bringups (each probe spawns N codex
# subprocesses and takes 30-90s). Bypass with --no-cap-cache.
CAP_PROBE_CACHE="/tmp/codex-fleet/.cap-probe-cache.json"
mkdir -p /tmp/codex-fleet
HEALTHY_EMAILS=""
cap_cache_hit=0
if [ "$NO_CAP_CACHE" = "0" ] && [ -f "$CAP_PROBE_CACHE" ]; then
  HEALTHY_EMAILS=$(CACHE="$CAP_PROBE_CACHE" python3 - <<'PY'
import json, os, time, sys
try:
    with open(os.environ["CACHE"]) as f:
        data = json.load(f)
    ts = int(data.get("ts", 0))
    age = int(time.time()) - ts
    if age < 300 and isinstance(data.get("emails"), list) and data["emails"]:
        print(age)
        for e in data["emails"]:
            print(e)
except Exception:
    pass
PY
)
  if [ -n "$HEALTHY_EMAILS" ]; then
    cache_age=$(printf "%s\n" "$HEALTHY_EMAILS" | head -n1)
    HEALTHY_EMAILS=$(printf "%s\n" "$HEALTHY_EMAILS" | tail -n +2)
    log "cap-probe cache hit (age=${cache_age}s)"
    cap_cache_hit=1
  fi
fi
if [ "$cap_cache_hit" = "0" ]; then
  HEALTHY_EMAILS=$(bash "$SCRIPT_DIR/cap-probe.sh" "$N_PANES" $CANDIDATES 2>/tmp/cap-probe.err) || true
fi
HEALTHY_N=$(printf "%s\n" "$HEALTHY_EMAILS" | grep -c "@" || true)

# Auto-grow N_PANES to match what the probe actually found, capped by
# CODEX_FLEET_N_PANES_AUTO_MAX (default 24). Triggered only when the
# operator did NOT pass --n explicitly — explicit --n always wins. Without
# this, the bringup historically clamped at the default --n=8 and left
# extra healthy accounts idle in cache instead of spawning them.
if [ "$N_PANES_EXPLICIT" = "0" ] && [ "$HEALTHY_N" -gt "$N_PANES" ]; then
  prev_n="$N_PANES"
  N_PANES="$HEALTHY_N"
  if [ "$N_PANES" -gt "$N_PANES_AUTO_MAX" ]; then
    N_PANES="$N_PANES_AUTO_MAX"
  fi
  log "auto-grow N_PANES: $prev_n → $N_PANES (HEALTHY_N=$HEALTHY_N, cap=$N_PANES_AUTO_MAX). Override with --n or CODEX_FLEET_N_PANES_AUTO_MAX."
  # Truncate HEALTHY_EMAILS to N_PANES so downstream stage/spawn loops
  # don't try to spin more workers than the layout produces.
  HEALTHY_EMAILS=$(printf "%s\n" "$HEALTHY_EMAILS" | head -n "$N_PANES")
  HEALTHY_N=$(printf "%s\n" "$HEALTHY_EMAILS" | grep -c "@" || true)
fi

if [ "$HEALTHY_N" -lt "$N_PANES" ]; then
  warn "cap-probe found only $HEALTHY_N/$N_PANES healthy accounts"
  warn "$(cat /tmp/cap-probe.err 2>/dev/null)"
  [ "$HEALTHY_N" -eq 0 ] && die "no healthy accounts; check /tmp/claude-viz/cap-probe.log"
fi
if [ "$cap_cache_hit" = "0" ] && [ "$HEALTHY_N" -gt 0 ]; then
  # Atomic write: tmp + rename so a concurrent reader never sees half a file.
  CACHE_TMP="${CAP_PROBE_CACHE}.tmp.$$"
  EMAILS="$HEALTHY_EMAILS" python3 - <<PY > "$CACHE_TMP"
import json, os, time
emails = [e.strip() for e in os.environ.get("EMAILS","").splitlines() if e.strip()]
print(json.dumps({"ts": int(time.time()), "emails": emails}))
PY
  mv "$CACHE_TMP" "$CAP_PROBE_CACHE"
fi
log "$HEALTHY_N healthy account(s) confirmed by live probe"

# Map healthy emails to id|email|tier|specialty format. `tier` + `specialty`
# are looked up from accounts.yml by email; missing entries default to
# tier=high (xhigh reasoning) and specialty="" (generalist). The downstream
# stage + spawn loops read 4 fields per line.
ACCOUNTS_YAML="${ACCOUNTS_YAML:-$SCRIPT_DIR/accounts.yml}"
ACCOUNTS=$(printf "%s\n" "$HEALTHY_EMAILS" | ACCOUNTS_YAML="$ACCOUNTS_YAML" python3 -c '
import sys, os, re
acct_yml = os.environ.get("ACCOUNTS_YAML", "")
by_email = {}
if acct_yml and os.path.exists(acct_yml):
    cur = None
    with open(acct_yml) as fh:
        for raw in fh:
            line = raw.rstrip()
            s = line.lstrip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("- id:"):
                if cur is not None and cur.get("email"):
                    by_email[cur["email"]] = cur
                cur = {}
                continue
            if cur is None:
                continue
            mm = re.match(r"^\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(.*?)$", line)
            if not mm: continue
            k, v = mm.group(1), mm.group(2).strip()
            if v.startswith("[") and v.endswith("]"):
                v = [x.strip().strip("\"").strip("\x27") for x in v[1:-1].split(",") if x.strip()]
            else:
                v = v.strip("\"").strip("\x27")
            cur[k] = v
    if cur is not None and cur.get("email"):
        by_email[cur["email"]] = cur
dommap = {"magnoliavilag":"magnolia","gitguardex":"gg","pipacsclub":"pipacs"}
for line in sys.stdin:
    email = line.strip()
    if not email: continue
    part, dom = email.split("@", 1)
    dom = dom.split(".", 1)[0]
    dom = dommap.get(dom, dom)
    aid = f"{part}-{dom}"
    info = by_email.get(email, {})
    tier = info.get("tier", "high")
    spec = info.get("specialty", "")
    if isinstance(spec, list):
        spec = ",".join(spec)
    print(f"{aid}|{email}|{tier}|{spec}")
')
COUNT=$(echo "$ACCOUNTS" | grep -c "|")
log "final account list: $COUNT (tier+specialty from $ACCOUNTS_YAML)"

# 7. Stage CODEX_HOMEs
log "staging per-account CODEX_HOMEs"
# Map tier (from accounts.yml) → codex `model_reasoning_effort`. Consumed by
# fleet_render_config's __REASONING_EFFORT__ substitution.
tier_to_effort() {
  case "$1" in
    low)    echo "low" ;;
    medium) echo "medium" ;;
    *)      echo "xhigh" ;;  # high or unset
  esac
}
while IFS='|' read -r id email tier specialty; do
  [ -z "$id" ] && continue
  d="/tmp/codex-fleet/$id"
  mkdir -p "$d"
  cp "$HOME/.codex/accounts/$email.json" "$d/auth.json"
  chmod 600 "$d/auth.json"
  export FLEET_REASONING_EFFORT="$(tier_to_effort "$tier")"
  # Render a fleet-local config.toml (Colony only, pre-approved, sandbox
  # workspace-write) instead of symlinking the operator's interactive
  # `~/.codex/config.toml`. The old symlink dragged in drawio / recodee /
  # Higgsfield / coolify / hostinger-api / soul-skills MCPs that the
  # worker prompt never calls — and when any of their backends were down
  # (recodee daemon on :2455, @drawio/mcp), every pane blocked 30-60s on
  # MCP startup and tripped the "MCP startup incomplete" banner. A stale
  # symlink target is replaced on every bringup so re-staging fixes a
  # config that drifted.
  if [ -L "$d/config.toml" ] || [ -e "$d/config.toml" ]; then
    rm -f "$d/config.toml"
  fi
  if [ -f "$FLEET_CONFIG_TMPL" ]; then
    if ! fleet_render_config "$FLEET_CONFIG_TMPL" "$d/config.toml"; then
      warn "failed to render fleet config for $id; falling back to symlink"
      ln -s "$HOME/.codex/config.toml" "$d/config.toml"
    fi
  else
    warn "fleet template missing ($FLEET_CONFIG_TMPL); falling back to symlinking ~/.codex/config.toml"
    ln -s "$HOME/.codex/config.toml" "$d/config.toml"
  fi
done <<< "$ACCOUNTS"

# 8. Create the main session with overview window
log "creating tmux session: $SESSION"
tmux new-session -d -s "$SESSION" -n overview -x 274 -y 76
tmux set-option -t "$SESSION" -g mouse on
tmux set-option -w -t "$SESSION:overview" remain-on-exit on

# Status bar styling is owned by style-tabs.sh (iOS-style 3-row tab strip,
# rounded pane borders, sticky right-click menu). It runs after windows are
# created so window-status-format applies to all six tabs. Do NOT set
# per-session `status on/off` here — a boolean session-local value shadows the
# global numeric `status N` style-tabs sets, clamping back to 1 row and
# silently hiding the tab strip.

# 8.5 + 9. Apply the typed overview layout. fleet-layout owns the pane
# topology now; full-bringup only decides operator policy (header rows
# and worker spawn metadata).
#
# The legacy `fleet-tab-strip` Rust binary that used to draw an in-window
# header pane at the top of overview was retired in PR #107. The tmux
# status bar configured by style-tabs.sh (`status-position top`, iOS-style
# pills, window-status-format with range=window markers) is now the single
# canonical nav surface — visible on EVERY window, not just overview.
#
# Opting back into an in-window header pane via CODEX_FLEET_OVERVIEW_HEADER_ROWS
# is still honoured for forward-compat, but defaults to 0 so the bringup
# stops hunting for a binary that no longer exists (previous default of 1
# fell into a warn branch on every fresh checkout → no header pane created
# AND a stale "cargo build -p fleet-tab-strip" message printed for a crate
# the workspace doesn't ship anymore).
HEADER_ROWS="${CODEX_FLEET_OVERVIEW_HEADER_ROWS:-0}"
HEADER_PANE_ID=""
HEADER_CMD=""
if (( HEADER_ROWS > 0 )); then
  warn "CODEX_FLEET_OVERVIEW_HEADER_ROWS=$HEADER_ROWS requested but fleet-tab-strip crate was retired (PR #107) — falling back to status-bar-only nav. Unset the env to silence."
  HEADER_ROWS=0
fi

FLEET_APPLY_LAYOUT_BIN="$REPO/rust/target/release/fleet-apply-layout"
[ -x "$FLEET_APPLY_LAYOUT_BIN" ] || FLEET_APPLY_LAYOUT_BIN="$REPO/rust/target/debug/fleet-apply-layout"
[ -x "$FLEET_APPLY_LAYOUT_BIN" ] || die "fleet-apply-layout not built — run: (cd $REPO/rust && cargo build --release -p fleet-layout)"
LAYOUT_RUNNER=( "$FLEET_APPLY_LAYOUT_BIN" )

LAYOUT_ARGS=(
  --target "$SESSION:overview"
  --preset overview-header-tile
  --header-rows "$HEADER_ROWS"
  --workers "$N_PANES"
)
if [ -n "$HEADER_CMD" ]; then
  LAYOUT_ARGS+=( --header-cmd "$HEADER_CMD" )
fi

# fleet-apply-layout is a Rust binary, so it cannot see the shell `tmux`
# function from lib/_tmux.sh. When full-bringup runs on a dedicated tmux
# socket, put a tiny tmux shim first on PATH for this one command so the
# binary targets the same server as the rest of this script.
LAYOUT_TMUX_SHIM_DIR=""
if [[ -n "$CODEX_FLEET_TMUX_SOCKET" ]]; then
  REAL_TMUX_BIN="$(type -P tmux || true)"
  [ -n "$REAL_TMUX_BIN" ] || die "tmux not found on PATH"
  LAYOUT_TMUX_SHIM_DIR="$(mktemp -d -t codex-fleet-layout-tmux.XXXXXX)"
  cat > "$LAYOUT_TMUX_SHIM_DIR/tmux" <<EOF
#!/usr/bin/env bash
if [ -n "\${CODEX_FLEET_TMUX_SOCKET:-}" ]; then
  exec "$REAL_TMUX_BIN" -L "\$CODEX_FLEET_TMUX_SOCKET" "\$@"
fi
exec "$REAL_TMUX_BIN" "\$@"
EOF
  chmod +x "$LAYOUT_TMUX_SHIM_DIR/tmux"
fi

layout_output=""
if [ -n "$LAYOUT_TMUX_SHIM_DIR" ]; then
  layout_output="$(PATH="$LAYOUT_TMUX_SHIM_DIR:$PATH" "${LAYOUT_RUNNER[@]}" "${LAYOUT_ARGS[@]}" 2>&1)" || {
    rm -rf "$LAYOUT_TMUX_SHIM_DIR"
    die "fleet-apply-layout failed: $layout_output"
  }
  rm -rf "$LAYOUT_TMUX_SHIM_DIR"
else
  layout_output="$("${LAYOUT_RUNNER[@]}" "${LAYOUT_ARGS[@]}" 2>&1)" || \
    die "fleet-apply-layout failed: $layout_output"
fi
log "overview layout applied via fleet-apply-layout (workers=$N_PANES, header_rows=$HEADER_ROWS)"

# Default geometry: retile the 2-column preset into a uniform grid so every
# pane has the same width/height. The Rust preset still owns *topology* (which
# pane is the header, which are workers), we just override the geometry on top.
# Operators who prefer the 2-column shape can set CODEX_FLEET_OVERVIEW_LAYOUT=preset.
case "${CODEX_FLEET_OVERVIEW_LAYOUT:-tiled}" in
  tiled)
    tmux select-layout -t "$SESSION:overview" tiled >/dev/null 2>&1 || true
    log "overview re-tiled into uniform grid (CODEX_FLEET_OVERVIEW_LAYOUT=tiled)"
    ;;
  preset|2col|two-column)
    log "overview keeping fleet-layout 2-column preset (CODEX_FLEET_OVERVIEW_LAYOUT=$CODEX_FLEET_OVERVIEW_LAYOUT)"
    ;;
  *)
    warn "unknown CODEX_FLEET_OVERVIEW_LAYOUT='$CODEX_FLEET_OVERVIEW_LAYOUT' — keeping preset"
    ;;
esac

if (( HEADER_ROWS > 0 )); then
  HEADER_PANE_ID="$(tmux list-panes -t "$SESSION:overview" -F '#{@panel}|#{pane_id}' \
    | awk -F'|' '$1 == "[codex-fleet-tab-strip]" { print $2; exit }')"
  [ -n "$HEADER_PANE_ID" ] || die "fleet-apply-layout did not mark the overview header pane"
  tmux set-option -p -t "$HEADER_PANE_ID" remain-on-exit off
  log "overview header pane installed → $HEADER_PANE_ID ($HEADER_ROWS row(s))"
fi

# 10. Spawn codex into each pane with CODEX_GUARD_BYPASS=1. Filter the
# pane list to exclude the header pane so workers don't get spawned on
# top of the strip.
log "launching $N_PANES codex workers"
PANE_IDS=( $(tmux list-panes -t "$SESSION:overview" -F '#{@panel}|#{pane_id}' \
  | awk -F'|' '$1 != "[codex-fleet-tab-strip]" { print $2 }') )
[ "${#PANE_IDS[@]}" -eq "$N_PANES" ] || die "overview layout produced ${#PANE_IDS[@]} worker panes, expected $N_PANES"
i=0
while IFS='|' read -r id email tier specialty; do
  [ -z "$id" ] && continue
  pid="${PANE_IDS[$i]}"
  tmux set-option -p -t "$pid" '@panel' "[codex-$id]"
  # --add-dir is required when the active plan touches paths outside the
  # codex-fleet repo (e.g. /home/deadpool/Documents/recodee for gx-fleet-*
  # plans). Without it, `workspace-write` blocks all writes and the worker
  # spins on `outside writable roots` / `.git/FETCH_HEAD: Read-only file
  # system` for the entire session.
  # CODEX_FLEET_TIER + CODEX_FLEET_SPECIALTY are read by worker-prompt.md's
  # "Tier + specialty gate" — pane post-skips tasks beyond its tier or
  # outside its specialty prefixes.
  # Runtime selection (CODEX_FLEET_RUNTIME, default codex). spawn-fleet.sh
  # exposes this via `--runtime claude` for the fallback case where the
  # codex account pool is exhausted (every account capped). The claude
  # branch hands off to claude-worker.sh which loops `claude` with the
  # Claude-tailored wake-prompt and applies rate-limit-aware backoff —
  # one-shot `claude --print` would exit after a single task instead of
  # pulling more from Colony.
  case "${CODEX_FLEET_RUNTIME:-codex}" in
    claude)
      tmux respawn-pane -k -t "$pid" \
        "env CLAUDE_FLEET_AGENT_NAME=claude-fleet-$id CLAUDE_FLEET_ACCOUNT_LABEL=$email CLAUDE_FLEET_TIER=${tier:-high} CLAUDE_FLEET_SPECIALTY=\"$specialty\" bash $REPO/scripts/codex-fleet/claude-worker.sh"
      ;;
    *)
      tmux respawn-pane -k -t "$pid" \
        "env CODEX_GUARD_BYPASS=1 CODEX_HOME=/tmp/codex-fleet/$id CODEX_FLEET_AGENT_NAME=codex-$id CODEX_FLEET_ACCOUNT_EMAIL=$email CODEX_FLEET_TIER=${tier:-high} CODEX_FLEET_SPECIALTY=\"$specialty\" codex --dangerously-bypass-approvals-and-sandbox $ADD_DIR_FLAGS \"\$(cat $WAKE)\""
      ;;
  esac
  i=$((i + 1))
done <<< "$ACCOUNTS"

# 10.5  Add a 7-row "mascot strip" at the bottom of the overview window.
#
# Renders a small transparent Claude pixel-art + live fleet stats. The strip
# pane is *added after* worker spawn so we don't disturb the
# fleet-apply-layout topology — split-window -f -v -l 7 carves it from the
# full-window height, then a final tiled retile gives us uniform workers + a
# fixed-height strip. Operator opt-out: CODEX_FLEET_MASCOT_STRIP=0.
#
# Tuning via env: see ~/.local/bin/claude-mascot-strip --help-style comments
# (CLAUDE_STRIP_IMG, CLAUDE_STRIP_INTERVAL, CLAUDE_STRIP_PLACE, …).
if [ "${CODEX_FLEET_MASCOT_STRIP:-1}" = "1" ] && [ -x "$HOME/.local/bin/claude-mascot-strip" ]; then
  # `-P -F '#{pane_id}'` makes split-window print the new pane's id directly,
  # which is reliable. The list-panes + awk approach we tried first looked at
  # `pane_current_command`, but a bash script exec'd from bash keeps the
  # command name as `bash`, so the match silently dropped.
  mascot_pid=$(tmux split-window -d -P -F '#{pane_id}' -f -v -l 7 \
    -t "$SESSION:overview" \
    "exec $HOME/.local/bin/claude-mascot-strip" 2>/dev/null || true)
  if [ -n "$mascot_pid" ]; then
    tmux set-option -p -t "$mascot_pid" '@panel' '[mascot-strip]' >/dev/null 2>&1 || true
    tmux set-option -p -t "$mascot_pid" remain-on-exit on >/dev/null 2>&1 || true
    # Pin the strip height back to 7 — tmux's tiled re-distribution above us
    # would otherwise rescale everything uniformly.
    tmux resize-pane -t "$mascot_pid" -y 7 >/dev/null 2>&1 || true
    log "overview mascot strip spawned → $mascot_pid (CODEX_FLEET_MASCOT_STRIP=0 to disable)"
  else
    warn "overview mascot strip split-window did not return a pane id; strip skipped"
  fi
fi

# 11. Create fleet / plan / waves windows
log "creating fleet / plan / waves windows"

# Open a dashboard window only if its script exists. After the extraction split
# from recodee, not every renderer is present on every install — e.g. the
# codex-fleet repo has `waves-anim.sh` but not the older `waves-anim-generic.sh`;
# `review-board.sh` may or may not have migrated. With `set -eo pipefail`,
# `tmux new-window -d -t SESSION: -n NAME "bash MISSING.sh"` succeeds in
# creating the window, the spawned bash exits status 127, tmux closes the
# window immediately, and the following `set-option -w -t SESSION:NAME` fires
# `no such window` and aborts the bringup before the sibling ticker session is
# created (memory: 2026-05-14 bringup miss on waves).
#
# `open_window` skips silently if the script is missing and only sets the
# remain-on-exit flag once we know the window stuck. The waves slot also tries
# `waves-anim.sh` as a fallback for the historical generic name.
open_window() {
  local name="$1" script="$2" remain="$3"
  if [ ! -f "$script" ]; then
    warn "dashboard script missing: $script — skipping '$name' window"
    return 0
  fi
  # Auto-detect launch shape: .sh → run via bash; anything executable that
  # isn't a .sh (the Rust bins from `cargo build --release`) → exec directly.
  local cmd
  if [[ "$script" == *.sh ]]; then
    cmd="bash $script"
  elif [ -x "$script" ]; then
    cmd="$script"
  else
    cmd="bash $script"
  fi
  tmux new-window -d -t "$SESSION:" -n "$name" "$cmd" || {
    warn "tmux new-window failed for '$name'"
    return 0
  }
  if [ "$remain" = "remain" ]; then
    tmux set-option -w -t "$SESSION:$name" remain-on-exit on 2>/dev/null \
      || warn "could not set remain-on-exit on '$name'"
  fi
}

# Renderer selection: prefer the Rust bins under rust/fleet-*/target/release/
# unless FLEET_DASHBOARD_RENDERER=bash. Each Rust bin is a drop-in replacement
# for its corresponding *-anim.sh — same window name, same tmux placement,
# same pane geometry. The bins draw their own in-binary tab strip and shell
# out `tmux select-window` on click, which is the canonical fix for the
# kitty+tmux click-routing class of bugs (cf. PR #1927 / #1931 / #6).
FLEET_DASHBOARD_RENDERER="${FLEET_DASHBOARD_RENDERER:-rust}"
rust_bin_dir="$REPO/rust/target/release"
use_rust=0
if [ "$FLEET_DASHBOARD_RENDERER" = "rust" ] \
   && [ -x "$rust_bin_dir/fleet-watcher" ] \
   && [ -x "$rust_bin_dir/fleet-state" ]   \
   && [ -x "$rust_bin_dir/fleet-plan-tree" ] \
   && [ -x "$rust_bin_dir/fleet-waves" ]; then
  use_rust=1
  log "FLEET_DASHBOARD_RENDERER=rust (bins under $rust_bin_dir)"
elif [ "$FLEET_DASHBOARD_RENDERER" = "rust" ]; then
  warn "FLEET_DASHBOARD_RENDERER=rust but bins not built; falling back to bash. Build with:"
  warn "  (cd $REPO/rust && cargo build --release)"
fi

waves_script="$SCRIPT_DIR/waves-anim-generic.sh"
[ -f "$waves_script" ] || waves_script="$SCRIPT_DIR/waves-anim.sh"

# Prefer the committed review-anim.sh (sibling of plan-anim / waves-anim)
# when present; fall back to the historical review-board.sh placeholder so
# user-local installs that ship their own variant still work.
review_script="$SCRIPT_DIR/review-anim.sh"
[ -f "$review_script" ] || review_script="$SCRIPT_DIR/review-board.sh"

if [ "$use_rust" = "1" ]; then
  open_window fleet   "$rust_bin_dir/fleet-state"      ""
  # Wrap fleet-plan-tree in env(1) so it resolves the plan from THIS repo
  # (codex-fleet), not the legacy recodee default it was hardcoded to fall
  # back to. The binary still honours /tmp/claude-viz/plan-tree-pin.txt if
  # the operator pins a specific plan via plan-tree-pin.sh.
  open_window plan    "env CODEX_FLEET_PLAN_REPO_ROOT=$REPO $rust_bin_dir/fleet-plan-tree"  remain
  open_window waves   "$rust_bin_dir/fleet-waves"      remain
  open_window review  "$review_script"                 remain
  open_window watcher "$rust_bin_dir/fleet-watcher"    ""
else
  open_window fleet   "$SCRIPT_DIR/fleet-state-anim.sh" ""
  open_window plan    "$SCRIPT_DIR/plan-tree-anim.sh"   remain
  open_window waves   "$waves_script"                   remain
  open_window review  "$review_script"                  remain
  open_window watcher "$SCRIPT_DIR/watcher-board.sh"    ""
fi

# Design preview — fleet-tui-poc renders the glass-dock floating nav + the
# iOS overlay surfaces (ContextMenu / Spotlight / ActionSheet) as a live
# reference for design work inside the running fleet. Optional: skip
# silently when the release bin isn't built so design work doesn't gate
# bringup on a non-essential window. Inside the pane, press 1/2/3 to open
# ContextMenu / Spotlight / ActionSheet and reveal the terminal-backdrop
# preview underneath.
if [ -x "$rust_bin_dir/fleet-tui-poc" ]; then
  open_window design "$rust_bin_dir/fleet-tui-poc" remain
fi

# 11b. Apply canonical iOS-style chrome (3-row tab strip at top, rounded pane
# borders with `▭ #{@panel}` headers, sticky right-click menu). Runs after
# windows exist so window-status-format covers all six tabs.
log "applying iOS-style chrome"
CODEX_FLEET_SESSION="$SESSION" bash "$SCRIPT_DIR/style-tabs.sh" >/dev/null 2>&1 \
  || warn "style-tabs.sh failed (chrome will fall back to tmux defaults)"

# 12. Sibling fleet-ticker session: ticker + cap-swap + state-pump
log "creating sibling session: $TICKER_SESSION"
if tmux has-session -t "$TICKER_SESSION" 2>/dev/null; then
  tmux kill-session -t "$TICKER_SESSION"
fi

# Reset stale supervisor + active-account state so zombie takeover events from
# prior fleet runs don't immediately re-spawn `codex-takeover-*` kitty windows
# the moment supervisor.sh starts its tail -F. (Symptom seen 2026-05-14: 322
# queued events from a 2h-old run fired 7+ kittys before any new event landed.)
log "resetting stale supervisor + active-account state"
: > "$FLEET_STATE_DIR/supervisor-queue.jsonl" 2>/dev/null || true
: > "$FLEET_STATE_DIR/fleet-active-accounts.txt" 2>/dev/null || true
mkdir -p "$FLEET_STATE_DIR/supervisor"
: > "$FLEET_STATE_DIR/supervisor/processed.keys" 2>/dev/null || true
# ticker uses fleet-tick-daemon.sh wrapper — re-spawn-safe vs the raw
# fleet-tick.sh which `set -eo pipefail`-crashes mid-tick on any failed
# regex / capture-pane and silently halts the live viz.
# ticker_window — open a ticker daemon window. Set remain-on-exit so a
# crashed daemon stays visible as a dead window with its last stderr,
# instead of silently disappearing (the 2026-05-14 force-claim/state-pump/
# review-detector regression: their windows vanished the moment bash
# exited non-zero because no remain-on-exit was attached, leaving the
# operator with a fleet that idled forever while looking healthy).
ticker_window() {
  local name="$1" cmd="$2"
  tmux new-window -d -t "$TICKER_SESSION:" -n "$name" "$cmd" || {
    warn "ticker window create failed: $name"
    return 0
  }
  tmux set-option -w -t "$TICKER_SESSION:$name" remain-on-exit on 2>/dev/null || true
}
tmux new-session -d -s "$TICKER_SESSION" -n ticker "bash $SCRIPT_DIR/fleet-tick-daemon.sh"
tmux set-option -w -t "$TICKER_SESSION:ticker" remain-on-exit on 2>/dev/null || true
ticker_window cap-swap "bash $SCRIPT_DIR/cap-swap-daemon.sh"
# state-pump + review-detector — guard the spawn: their scripts may not
# exist on every install (script extracted out of recodee inherited a
# subset of daemons). Skip silently when missing so the window doesn't
# create-then-die and pollute the strip with a dead tab.
if [ -f "$SCRIPT_DIR/colony-state-pump.sh" ]; then
  ticker_window state-pump "bash $SCRIPT_DIR/colony-state-pump.sh"
fi
if [ -f "$SCRIPT_DIR/plan-complete-detector.sh" ]; then
  ticker_window review-detector "bash $SCRIPT_DIR/plan-complete-detector.sh"
fi
# Review approval queue: producer collapses events → snapshot; scanner walks
# the worker panes for Codex auto-reviewer output and emits events. Both are
# guarded so a checkout missing either script doesn't create a dead ticker
# window. The scanner is pointed at the overview window (where the codex
# worker panes live) by REVIEW_SCANNER_WINDOW; override at the fleet level if
# the worker pane layout changes.
if [ -f "$SCRIPT_DIR/review-queue.sh" ]; then
  ticker_window review-queue "bash $SCRIPT_DIR/review-queue.sh daemon"
fi
if [ -f "$SCRIPT_DIR/review-pane-scanner.sh" ]; then
  ticker_window review-scanner "REVIEW_SCANNER_SESSION=$SESSION REVIEW_SCANNER_WINDOW=overview bash $SCRIPT_DIR/review-pane-scanner.sh"
fi
# force-claim scans ALL openspec plans every 15s, finds deps-satisfied
# `available` tasks, and dispatches them onto idle codex panes via
# tmux send-keys. Keeps the fleet pulled into ready work when its
# originally-pinned plan completes.
#
# FORCE_CLAIM_WINDOW must point at the window that hosts the codex worker
# panes (currently `overview`). Default `1` from force-claim.sh's own env
# is wrong here because we have 6 windows and `1` maps to `fleet`, the
# state-anim viz pane — so without this override the daemon reported
# "no idle codex panes" forever while the actual workers idled in window 0.
#
# FORCE_CLAIM_REPO must pin the disk-plan scan to codex-fleet. Without it,
# the daemon honours CODEX_FLEET_REPO_ROOT (set globally by codex-fleet-2
# to recodee for cross-repo work), and dispatches workers onto plans whose
# files are inside recodee — which the panes then try to claim against
# a cwd of codex-fleet, hitting the writable-root preflight blocker on
# every cycle (2026-05-14 stuck-fleet regression).
#
# CODEX_FLEET_CLAIM_MODE=poll forces poll-only, skipping the event-driven
# claim-trigger.sh subprocess that requires inotifywait (not always
# installed; without it claim-trigger crashes immediately and force-claim
# logs "claim-trigger exited early status=127").
ticker_window force-claim "FORCE_CLAIM_WINDOW=overview FORCE_CLAIM_REPO=$REPO CODEX_FLEET_CLAIM_MODE=poll bash $SCRIPT_DIR/force-claim.sh --loop --interval=15"

# claim-release-supervisor scans all openspec plans every 60s, finds claims
# held by agents whose codex pane has gone back to the default prompt
# placeholder (i.e. they finished or dropped the work without marking the
# sub-task done in Colony), and releases those claims via colony rescue
# stranded --apply so force-claim can re-route them. Distinct from
# supervisor.sh (kitty-spawning quota replacement, opt-in via
# CODEX_FLEET_SUPERVISOR=1) — this watcher only mutates Colony state.
ticker_window claim-release "CR_SUP_SESSION=$SESSION CR_SUP_WINDOW=overview bash $SCRIPT_DIR/claim-release-supervisor.sh --loop --interval=60"

# plan-watcher: every 30s, scans `colony plan status` for plans with
# available sub-tasks and tmux-send-keys an OVERRIDE prompt to any idle
# worker pane (detected by recent "no claimable work" / "polls returned"
# stdout). Closes the gap between `colony plan publish` and workers
# actually picking up the new plan — without this, a freshly-published
# plan would sit untouched until an operator manually triggers each pane.
# Cooldown prevents re-prompting the same worker on the same plan.
ticker_window plan-watcher "CODEX_FLEET_SESSION=$SESSION CODEX_FLEET_REPO_ROOT=$REPO bash $SCRIPT_DIR/plan-watcher.sh --loop --interval=30"

# auto-reviewer: every 5m, reviews merged PRs attached to completed plan
# sub-tasks. Slow cadence keeps Claude call cost bounded while still catching
# new completions within the hour.
ticker_window auto-reviewer "bash $SCRIPT_DIR/auto-reviewer.sh --loop --interval=300"

# stall-watcher: every 60s, `colony rescue stranded --apply` releases claims
# held > 30m without progress, then enqueues a takeover_recommended event
# per rescued agent into /tmp/claude-viz/supervisor-queue.jsonl.
# supervisor (opt-in): consumes that queue and spawns fresh kitty + codex
# workers. Disabled by default because it spawns N separate kitty windows
# per takeover event, which conflicts with the single-kitty-with-tmux-tabs
# fleet UX. Re-enable per-bringup with CODEX_FLEET_SUPERVISOR=1, or run
# `bash scripts/codex-fleet/supervisor.sh` manually when auto-rescue is wanted.
ticker_window stall-watcher "bash $SCRIPT_DIR/stall-watcher.sh"
if [ "${CODEX_FLEET_SUPERVISOR:-0}" = "1" ]; then
  ticker_window supervisor "bash $SCRIPT_DIR/supervisor.sh"
else
  log "supervisor window skipped (set CODEX_FLEET_SUPERVISOR=1 to enable auto-takeover spawns)"
fi

# 12b. Chrome the ticker session too so attaching to it shows the same iOS
# tab strip / rounded pane borders / sticky menu as the main session.
CODEX_FLEET_SESSION="$TICKER_SESSION" bash "$SCRIPT_DIR/style-tabs.sh" >/dev/null 2>&1 \
  || warn "style-tabs.sh failed for $TICKER_SESSION"

# 12c. Verify chrome actually rendered (catches the session-local `status on`
# shadow regression where tmux clamps the bar away and silently hides the tab
# strip). The acceptable height is whatever STYLE_TABS_HEIGHT asked for —
# default 1 (single-row, clicks work), 2-5 for opt-in floating-dock padding.
#
# Older revisions of this check read the per-client `status_height` format
# var and fell back to `client_height - window_height` when it was empty.
# Both are client-scoped — when full-bringup runs with no client attached
# (--no-attach, or while we're still spawning the ticker session) tmux
# returns `''` for status_height and `-<window_height>` for the subtraction
# (we logged `-76`), tripping the alarm even though the chrome was fine.
#
# Instead, read the GLOBAL `status` option directly: `on`/`off`/`1..5`.
# style-tabs.sh wipes the session-local override before re-setting the
# global, so any non-`off` global value means the chrome is in place.
expected_h="${STYLE_TABS_HEIGHT:-1}"
chrome_status=$(tmux show-options -gv status 2>/dev/null || echo "")
chrome_position=$(tmux show-options -gv status-position 2>/dev/null || echo "")
case "$chrome_status" in
  ''|off|0)
    # Auto-correct: re-assert the bare minimum (status on, top-docked) so
    # the operator gets a visible nav header even if style-tabs.sh partially
    # failed. Previously the chrome was just `warn`-ed and left hidden,
    # which surfaces as "the navigation header is not visible by default".
    warn "iOS chrome verify: global status='$chrome_status' — forcing status=on, status-position=top"
    tmux set-option -g status on >/dev/null 2>&1 || true
    tmux set-option -g status-position top >/dev/null 2>&1 || true
    tmux set-option -t "$SESSION" -u status >/dev/null 2>&1 || true
    tmux set-option -t "$SESSION" -u status-position >/dev/null 2>&1 || true
    tmux refresh-client -S >/dev/null 2>&1 || true
    ;;
  *)
    if [ "$chrome_position" != "top" ]; then
      warn "iOS chrome verify: status-position='$chrome_position' — forcing top"
      tmux set-option -g status-position top >/dev/null 2>&1 || true
      tmux set-option -t "$SESSION" -u status-position >/dev/null 2>&1 || true
      tmux refresh-client -S >/dev/null 2>&1 || true
    fi
    log "iOS chrome verified: status=$chrome_status position=${chrome_position:-top} (target on/${expected_h}, top)"
    ;;
esac

log "DONE."
log "  main session:    tmux attach -t $SESSION"
log "  ticker session:  tmux attach -t $TICKER_SESSION"
log "  cap-swap log:    tail -f /tmp/claude-viz/cap-swap.log"
log "  state pump log:  tail -f /tmp/claude-viz/colony-state-pump.log"
log "  force-claim:     tmux attach -t $TICKER_SESSION \\; select-window -t force-claim"

if [ "$ATTACH" = "1" ] && [ -t 1 ]; then
  exec tmux attach -t "$SESSION"
fi
