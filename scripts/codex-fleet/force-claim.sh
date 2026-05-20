#!/usr/bin/env bash
# force-claim — dispatch available plan sub-tasks across ALL non-empty plans
# onto idle codex panes.
#
# Why multi-plan:
#   When one plan is complete, workers pinned to it idle ("plan already
#   complete"). The watcher should instead route them to ready work in
#   any other openspec plan. force-claim now scans every plan.json
#   under openspec/plans/, picks tasks whose deps are satisfied, and
#   dispatches across the pool.
#
# Behavior:
#   1. Enumerate plan.json under openspec/plans/*/
#   2. For each non-empty plan, list (slug, idx, title) for tasks whose
#      status=="available" and whose depends_on are all completed.
#   3. Sort plans by newest-first (date suffix tiebreaker on mtime).
#   4. Find idle codex panes (default-prompt placeholder, no Working /
#      Reviewing approval state).
#   5. NEW (wave-parallel + token-aware): for the priority (newest) plan
#      query `colony task ready` per healthy pane, group readys by
#      `wave_index`, pick the lowest wave with work, and round-robin
#      dispatch ALL ready sub-tasks in that wave to distinct healthy
#      idle panes in a single tick. Panes near their 5h or weekly cap
#      are skipped via token-meter.sh --json (graceful fallback if
#      token-meter is unavailable).
#   6. Fall back to the legacy plan.json scan when colony returns no
#      ready items (covers the "colony unavailable" path).
#
# Loop mode now starts claim-trigger.sh for event-driven wakeups and keeps this
# script's polling pass as a slow backstop.
#
# Operator-pre-approved: dispatching prompts into gx-fleet/codex-fleet
# panes is an allowed flow (see ~/.claude memory feedback_gx_fleet_dispatch_authorized).
#
# Usage:
#   bash scripts/codex-fleet/force-claim.sh                 # one-shot
#   bash scripts/codex-fleet/force-claim.sh --dry-run       # show plan, no dispatch
#   bash scripts/codex-fleet/force-claim.sh --loop          # event + poll every 15s
#   bash scripts/codex-fleet/force-claim.sh --no-token-check
#                                                            # bypass token-meter skip
#                                                            # (debug / meter is broken)
#   bash scripts/codex-fleet/force-claim.sh --loop --quit-when-empty
#                                                            # exit 0 after 3 consecutive
#                                                            # passes with no available/claimed
#                                                            # work across any plan
#   bash scripts/codex-fleet/force-claim.sh --loop --empty-threshold=5
#                                                            # require 5 consecutive empties
#   FORCE_CLAIM_SESSION=codex-fleet ...                      # tmux session override
#   FORCE_CLAIM_WINDOW=overview     ...                      # window with codex panes
#   FORCE_CLAIM_PLAN_JSON=/path/plan.json                    # pin to single plan
#   FORCE_CLAIM_EMPTY_THRESHOLD=3                            # env equivalent
#   CODEX_FLEET_CLAIM_MODE=both|event|poll                   # default: both
set -eo pipefail

# --help / --version plumbing (see lib/version.sh). Handled before sourcing
# _tmux.sh / claim-fence.sh so docs work even when those libs misbehave.
FLEET_USAGE="force-claim.sh — dispatch ready plan sub-tasks across all
non-empty openspec plans onto idle codex panes.

Usage:
  bash scripts/codex-fleet/force-claim.sh                 # one-shot
  bash scripts/codex-fleet/force-claim.sh --dry-run       # show plan, no dispatch
  bash scripts/codex-fleet/force-claim.sh --loop          # event + poll every 15s
  bash scripts/codex-fleet/force-claim.sh --loop --quit-when-empty
  bash scripts/codex-fleet/force-claim.sh --loop --empty-threshold=5
  bash scripts/codex-fleet/force-claim.sh --no-token-check
  bash scripts/codex-fleet/force-claim.sh --help | --version

Env:
  FORCE_CLAIM_REPO / CODEX_FLEET_REPO_ROOT   repo root (default: derived)
  FORCE_CLAIM_SESSION                        tmux session (default: codex-fleet)
  FORCE_CLAIM_WINDOW                         tmux window  (default: overview)
  FORCE_CLAIM_PLAN_JSON                      pin to a single plan
  FORCE_CLAIM_INTERVAL                       loop poll seconds (default: 15)
  FORCE_CLAIM_EMPTY_THRESHOLD                consecutive empties to quit (default: 3)
  CODEX_FLEET_CLAIM_MODE                     both | event | poll (default: both)
  FORCE_CLAIM_TOKEN_METER                    path to token-meter.sh
  FORCE_CLAIM_TOKEN_MIN_5H / _MIN_WK         cap thresholds for skipping panes
  FORCE_CLAIM_SKIP_READY_CHECK=1             bypass worker-ready gate

Flags:
  --dry-run                       show plan; do not dispatch
  --loop                          event + poll backstop
  --interval=N                    poll interval (seconds)
  --quit-when-empty               exit 0 after empty-streak
  --empty-threshold=N             consecutive empty passes required
  --no-token-check                bypass token-meter cap filter
  -h, --help                      print this help and exit 0
  --version                       print '<basename> <FLEET_VERSION>' and exit 0"
source "$(dirname "${BASH_SOURCE[0]}")/lib/version.sh"
handle_help_version_flags "$@"

# Route every `tmux ...` call through scripts/codex-fleet/lib/_tmux.sh — when
# CODEX_FLEET_TMUX_SOCKET is set in the env (e.g. by full-bringup.sh), this
# transparently rewrites the call to `tmux -L $SOCKET ...`. Default behavior
# (env unset) is identical to the prior `tmux` binary call.
source "$(dirname "${BASH_SOURCE[0]}")/lib/_tmux.sh"
# SI-6: 5-second pre-claim staleness fence. dispatch() re-checks Colony
# state via plan.json after a short sleep so two panes can't both be told
# to claim the same sub-task while neither has actually issued the RPC.
source "$(dirname "${BASH_SOURCE[0]}")/lib/claim-fence.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Autodetect REPO from the clone location; env override wins.
REPO="${FORCE_CLAIM_REPO:-${CODEX_FLEET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"
SESSION="${FORCE_CLAIM_SESSION:-codex-fleet}"
WINDOW="${FORCE_CLAIM_WINDOW:-overview}"
LOOP=0
DRY=0
NO_TOKEN_CHECK=0
INTERVAL="${FORCE_CLAIM_INTERVAL:-15}"
CLAIM_MODE="${CODEX_FLEET_CLAIM_MODE:-both}"
FLEET_STATE_DIR="${FLEET_STATE_DIR:-/tmp/claude-viz}"
CLAIM_TRIGGER_LOG="${CLAIM_TRIGGER_LOG:-$FLEET_STATE_DIR/claim-trigger.log}"
CLAIM_TRIGGER_PID=""
TOKEN_METER="${FORCE_CLAIM_TOKEN_METER:-$SCRIPT_DIR/token-meter.sh}"
# Thresholds match token-meter.sh is_hot() so cockpit and dispatcher agree
# on what "near cap" means. 5h%<20 or wk%<15 = skip.
TOKEN_MIN_5H="${FORCE_CLAIM_TOKEN_MIN_5H:-20}"
TOKEN_MIN_WK="${FORCE_CLAIM_TOKEN_MIN_WK:-15}"
# --quit-when-empty: exit 0 after N consecutive passes where every plan is
# fully complete (no `available` and no `claimed` tasks anywhere). N comes
# from --empty-threshold or env FORCE_CLAIM_EMPTY_THRESHOLD (default 3) so
# a brief race where a new plan is being published doesn't kill the daemon.
QUIT_EMPTY=0
EMPTY_THRESHOLD="${FORCE_CLAIM_EMPTY_THRESHOLD:-3}"
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --loop)    LOOP=1 ;;
    --interval=*) INTERVAL="${a#--interval=}" ;;
    --quit-when-empty) QUIT_EMPTY=1 ;;
    --empty-threshold=*) EMPTY_THRESHOLD="${a#--empty-threshold=}" ;;
    --no-token-check) NO_TOKEN_CHECK=1 ;;
  esac
done

case "$CLAIM_MODE" in
  both|event|poll) ;;
  *)
    printf 'force-claim: invalid CODEX_FLEET_CLAIM_MODE=%s (expected both|event|poll)\n' "$CLAIM_MODE" >&2
    exit 2
    ;;
esac

# Emit ready (slug \t sub_idx \t title) across every non-empty plan, newest-first.
# Pin via FORCE_CLAIM_PLAN_JSON if the operator wants single-plan behaviour.
ready_tasks_all() {
  python3 - "$REPO" "${FORCE_CLAIM_PLAN_JSON:-}" <<'PYEOF'
import os, sys, re, glob, json
repo, pin = sys.argv[1], sys.argv[2]

if pin:
    plans = [pin] if os.path.isfile(pin) else []
else:
    plans = glob.glob(f"{repo}/openspec/plans/*/plan.json")

def keyfn(p):
    s = os.path.basename(os.path.dirname(p))
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})$', s)
    d = (int(m[1]), int(m[2]), int(m[3])) if m else (0, 0, 0)
    try:
        mt = os.path.getmtime(p)
    except OSError:
        mt = 0
    return (d, mt)

plans.sort(key=keyfn, reverse=True)

for p in plans:
    try:
        data = json.load(open(p))
    except Exception:
        continue
    tasks = data.get("tasks") or []
    if not tasks:
        continue
    slug = os.path.basename(os.path.dirname(p))
    status = {str(t["subtask_index"]): (t.get("status") or "available") for t in tasks}
    for t in sorted(tasks, key=lambda x: x.get("subtask_index", 0)):
        st = t.get("status") or "available"
        if st != "available":
            continue
        deps = t.get("depends_on") or []
        if not all(status.get(str(d)) == "completed" for d in deps):
            continue
        title = (t.get("title") or "").replace("\t", " ")
        wave = t.get("wave_index")
        wave = -1 if wave is None else int(wave)
        print(f"{slug}\t{t.get('subtask_index')}\t{wave}\t{title}")
PYEOF
}

# Resolve the priority plan slug = newest under openspec/plans/* (or the
# pinned single plan). Used to scope wave-parallel dispatch to one plan
# per tick. Other plans still get the legacy serial fallback below.
priority_plan_slug() {
  python3 - "$REPO" "${FORCE_CLAIM_PLAN_JSON:-}" <<'PYEOF'
import os, sys, re, glob
repo, pin = sys.argv[1], sys.argv[2]
if pin and os.path.isfile(pin):
    print(os.path.basename(os.path.dirname(pin)))
    sys.exit(0)
plans = glob.glob(f"{repo}/openspec/plans/*/plan.json")
def keyfn(p):
    s = os.path.basename(os.path.dirname(p))
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})$', s)
    d = (int(m[1]), int(m[2]), int(m[3])) if m else (0, 0, 0)
    try: mt = os.path.getmtime(p)
    except OSError: mt = 0
    return (d, mt)
plans.sort(key=keyfn, reverse=True)
if plans:
    print(os.path.basename(os.path.dirname(plans[0])))
PYEOF
}

# Aggregate (available, claimed, completed, blocked) counts across every plan.
# Prints one line: "<available>\t<claimed>\t<completed>\t<blocked>". Used by
# the --quit-when-empty loop to decide when the fleet has truly run dry.
plans_status_summary() {
  python3 - "$REPO" "${FORCE_CLAIM_PLAN_JSON:-}" <<'PYEOF'
import os, sys, glob, json
repo, pin = sys.argv[1], sys.argv[2]
plans = [pin] if (pin and os.path.isfile(pin)) else glob.glob(f"{repo}/openspec/plans/*/plan.json")
avail = claimed = completed = blocked = 0
for p in plans:
    try:
        data = json.load(open(p))
    except Exception:
        continue
    for t in (data.get("tasks") or []):
        st = (t.get("status") or "available")
        if   st == "available": avail     += 1
        elif st == "claimed":   claimed   += 1
        elif st == "completed": completed += 1
        elif st == "blocked":   blocked   += 1
print(f"{avail}\t{claimed}\t{completed}\t{blocked}")
PYEOF
}

# Read CODEX_FLEET_AGENT_NAME from a pane's /proc tree (walk children).
# Mirrors token-meter.sh resolve_pane() but trimmed to just the agent.
pane_agent_name() {
  local pane_idx="$1"
  local pane_pid
  pane_pid=$(tmux display-message -p -t "$SESSION:$WINDOW.$pane_idx" '#{pane_pid}' 2>/dev/null || true)
  [[ -z "$pane_pid" ]] && { echo ""; return; }
  local q="$pane_pid" next p kids val
  while [[ -n "$q" ]]; do
    next=""
    for p in $q; do
      if [[ -r "/proc/$p/environ" ]]; then
        val=$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null \
              | awk -F= '$1=="CODEX_FLEET_AGENT_NAME" {print substr($0,length($1)+2); exit}')
        if [[ -n "$val" ]]; then echo "$val"; return; fi
      fi
      kids=$(pgrep -P "$p" 2>/dev/null || true)
      [[ -n "$kids" ]] && next="$next $kids"
    done
    q="$next"
  done
  echo ""
}

# Identify idle codex panes — last 12 lines show the default-prompt placeholder,
# no `Working (…)`, no `Reviewing approval request`. Emits TSV: pane_idx \t agent.
# (agent may be empty if /proc env was unreadable — caller handles fallback.)
idle_panes() {
  while read -r pane_idx; do
    [[ -z "$pane_idx" ]] && continue
    local tail
    tail=$(tmux capture-pane -t "$SESSION:$WINDOW.$pane_idx" -p -S -12 2>/dev/null | sed 's/\x1B\[[0-9;]*m//g')
    if echo "$tail" | grep -qE "Working \([0-9]+[ms]"; then continue; fi
    if echo "$tail" | grep -qE "Reviewing approval request"; then continue; fi
    if echo "$tail" | grep -qE "^› (Find and fix|Use /skills|Run /review|Improve documentation|Implement|Summarize|Explain|Write tests)"; then
      local agent
      agent=$(pane_agent_name "$pane_idx")
      printf '%s\t%s\n' "$pane_idx" "$agent"
    fi
  done < <(tmux list-panes -t "$SESSION:$WINDOW" -F '#{pane_index}' 2>/dev/null)
}

# Run token-meter.sh --json and emit TSV: agent \t 5h_pct \t wk_pct.
# Strips trailing %; "n/a" → -1. Empty stdout on error (caller treats as
# "no signal — keep all panes" so token-meter outages don't stall dispatch).
token_meter_snapshot() {
  if (( NO_TOKEN_CHECK == 1 )); then
    return 0
  fi
  if [[ ! -x "$TOKEN_METER" && ! -f "$TOKEN_METER" ]]; then
    printf 'force-claim: token-meter not at %s — skipping cap filter (graceful)\n' "$TOKEN_METER" >&2
    return 0
  fi
  local raw
  raw=$(bash "$TOKEN_METER" --json --session "$SESSION" 2>/dev/null || true)
  [[ -z "$raw" ]] && {
    printf 'force-claim: token-meter --json returned nothing — skipping cap filter\n' >&2
    return 0
  }
  # NOTE: pipe stdin → python via -c (NOT `python3 - <<HEREDOC` — that form
  # uses the heredoc itself as stdin, so the JSON pipe would be ignored).
  printf '%s' "$raw" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception as e:
    sys.stderr.write(f"force-claim: token-meter JSON parse failed ({e})\n")
    sys.exit(0)
def pct(v):
    if v is None: return -1
    s = str(v).strip().rstrip("%")
    if not s or s.lower() == "n/a": return -1
    try: return int(float(s))
    except: return -1
for row in data.get("agents", []) or []:
    agent = row.get("agent") or ""
    if not agent: continue
    fh = pct(row.get("five_hour_pct"))
    wk = pct(row.get("weekly_pct"))
    print(f"{agent}\t{fh}\t{wk}")
'
}

# Filter idle panes against token-meter caps. Inputs:
#   $1 = TSV "pane_idx\tagent" lines
#   $2 = TSV "agent\tfh\twk" lines (may be empty → no filter applied)
# Outputs (stdout): healthy "pane_idx\tagent" TSV.
# Side-channel: prints "[skip] pane=X agent=Y 5h=Z wk=W" for each dropped pane
# to stderr and sets SKIPPED_CAPPED via tmp file path (see one_pass()).
filter_panes_by_cap() {
  local idle_tsv="$1" meter_tsv="$2" skip_path="$3"
  IDLE="$idle_tsv" METER="$meter_tsv" MIN5H="$TOKEN_MIN_5H" MINWK="$TOKEN_MIN_WK" \
    SKIP_PATH="$skip_path" NO_CHECK="$NO_TOKEN_CHECK" python3 - <<'PYEOF'
import os, sys
idle = os.environ["IDLE"]
meter = os.environ["METER"]
min5h = int(os.environ["MIN5H"])
minwk = int(os.environ["MINWK"])
skip_path = os.environ["SKIP_PATH"]
no_check = os.environ.get("NO_CHECK","0") == "1"
caps = {}
for line in meter.splitlines():
    parts = line.split("\t")
    if len(parts) != 3: continue
    agent, fh, wk = parts
    try:
        caps[agent] = (int(fh), int(wk))
    except ValueError:
        continue
skipped = 0
kept_lines = []
skip_lines = []
have_meter = bool(caps) and not no_check
for line in idle.splitlines():
    if not line.strip(): continue
    parts = line.split("\t")
    if len(parts) < 2:
        kept_lines.append(line)
        continue
    pane_idx, agent = parts[0], parts[1]
    if no_check or not have_meter or not agent or agent not in caps:
        kept_lines.append(line)
        continue
    fh, wk = caps[agent]
    # fh==-1 / wk==-1 means token-meter has no signal → keep the pane.
    cap_5h = fh != -1 and fh < min5h
    cap_wk = wk != -1 and wk < minwk
    if cap_5h or cap_wk:
        skipped += 1
        skip_lines.append(f"[skip] pane={pane_idx} agent={agent} 5h={fh}% wk={wk}% (min 5h>={min5h} wk>={minwk})")
        continue
    kept_lines.append(line)
print("\n".join(kept_lines))
with open(skip_path, "w") as f:
    f.write(str(skipped))
    if skip_lines:
        f.write("\n" + "\n".join(skip_lines))
PYEOF
}

# Query Colony for ready items in the priority plan, using each healthy
# pane's agent name as the lens. Returns TSV "sub_idx\twave_idx\ttitle"
# de-duplicated. Caller filters to lowest wave + round-robins to panes.
#
# We pick the agent slug of the first healthy pane (any pane will do —
# `task_ready_for_agent` reports global readiness, the agent argument
# just sets the routing lens). If colony is unreachable or returns no
# rows, this function emits nothing and the legacy plan.json scan takes
# over.
colony_ready_for_plan() {
  local plan_slug="$1" agent="$2"
  [[ -z "$plan_slug" || -z "$agent" ]] && return 0
  if ! command -v colony >/dev/null 2>&1; then
    return 0
  fi
  local raw
  raw=$(colony task ready \
          --agent "$agent" \
          --session "force-claim-${SESSION}" \
          --repo-root "$REPO" \
          --limit 50 \
          --json 2>/dev/null || true)
  [[ -z "$raw" ]] && return 0
  # See token_meter_snapshot for why we use `python3 -c` instead of
  # `python3 - <<HEREDOC` (heredoc would replace the JSON on stdin).
  printf '%s' "$raw" | PLAN="$plan_slug" python3 -c '
import json, os, sys
plan = os.environ["PLAN"]
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
ready = data.get("ready") or []
seen = set()
out = []
for r in ready:
    if r.get("plan_slug") != plan: continue
    si = r.get("subtask_index")
    if si is None or si in seen: continue
    seen.add(si)
    wave = r.get("wave_index")
    if wave is None: wave = -1
    title = (r.get("title") or "").replace("\t", " ")
    out.append((int(wave), int(si), title))
out.sort()
for w, s, t in out:
    print(f"{s}\t{w}\t{t}")
'
}

dispatch() {
  local pane_idx="$1" slug="$2" sub_idx="$3" title="$4"
  # SI-6: pre-claim staleness fence. Re-read plan.json after a short sleep
  # to make sure nobody else grabbed this sub-task while we were composing
  # the dispatch batch. Non-zero exit = skip; the next force-claim tick will
  # pick a new candidate. DRY mode still fences so dry-run output reflects
  # actual race behaviour.
  if ! claim_fence_check "$slug" "$sub_idx"; then
    printf '[fence] skip %s/sub-%s -> pane=%s (status/race; see stderr)\n' \
      "$slug" "$sub_idx" "$pane_idx"
    return 0
  fi
  # Prompt explicitly overrides any pinned-plan worker prompt — workers
  # that were told "PRIORITY plan = X" must switch to the named plan when
  # the watcher dispatches.
  local prompt
  prompt="OVERRIDE current plan pinning. Claim sub-task ${sub_idx} of plan ${slug} via Colony task_plan_claim_subtask (force the agent slug to your CODEX_FLEET_AGENT_NAME). Title: ${title}. Implement it on a fresh agent worktree per AGENTS.md, run the narrowest verification, open + merge a PR, post a Colony note with evidence (branch, PR URL, MERGED state), then mark the sub-task completed."
  if (( DRY == 1 )); then
    printf '[dry] dispatched %s/sub-%s -> pane=%s title=%s\n' "$slug" "$sub_idx" "$pane_idx" "$title"
    return
  fi
  # F5 — Worker-ready gate. Codex panes that are mid-task or sitting in a
  # first-launch interactive prompt reject `send-keys -l` with "not in a
  # mode" and the dispatch is silently lost — and yet the Colony claim has
  # already been consumed by the caller. Detect those cases up front and
  # defer instead of pretending the dispatch landed.
  #
  # Two failure modes we filter out:
  #   1. tmux copy-mode / scroll-back active (`pane_in_mode == 1`).
  #   2. Codex pane not at its `›` input prompt yet — either still booting
  #      or busy working. The bare `›` glyph in the last few visible lines
  #      is a load-bearing signal that the input box is editable.
  if [ "${FORCE_CLAIM_SKIP_READY_CHECK:-0}" != "1" ]; then
    local in_mode
    in_mode=$(tmux display-message -p -t "$SESSION:$WINDOW.$pane_idx" '#{pane_in_mode}' 2>/dev/null || echo "0")
    if [ "$in_mode" = "1" ]; then
      printf '[defer] pane %s in copy-mode; skipping %s/sub-%s (will retry next tick)\n' \
        "$pane_idx" "$slug" "$sub_idx" >&2
      return 1
    fi
    local visible
    visible=$(tmux capture-pane -p -t "$SESSION:$WINDOW.$pane_idx" 2>/dev/null | tail -10)
    if [ -z "$visible" ]; then
      printf '[defer] pane %s blank capture; skipping %s/sub-%s\n' \
        "$pane_idx" "$slug" "$sub_idx" >&2
      return 1
    fi
    if ! printf '%s' "$visible" | grep -qE '›|tab to queue message'; then
      printf '[defer] pane %s not at Codex input prompt; skipping %s/sub-%s\n' \
        "$pane_idx" "$slug" "$sub_idx" >&2
      return 1
    fi
    if printf '%s' "$visible" | grep -qE 'Working \([0-9]+|esc to interrupt'; then
      printf '[defer] pane %s busy working; skipping %s/sub-%s\n' \
        "$pane_idx" "$slug" "$sub_idx" >&2
      return 1
    fi
  fi
  tmux send-keys -t "$SESSION:$WINDOW.$pane_idx" -l "$prompt"
  tmux send-keys -t "$SESSION:$WINDOW.$pane_idx" Enter
  printf 'dispatched %s/sub-%s -> pane=%s title=%s\n' "$slug" "$sub_idx" "$pane_idx" "$title"
}

# Single dispatch tick = (a) inventory idle panes, (b) token-cap filter,
# (c) plan + wave selection via Colony for the priority plan,
# (d) wave-parallel round-robin send-keys. Falls back to the legacy
# plan.json scan when Colony has no rows for the priority plan (covers
# multi-plan + colony-down paths).
one_pass() {
  local ts; ts=$(date +%T)

  # (a) Inventory: idle panes as "pane_idx\tagent"
  local idle_raw=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    idle_raw+="$line"$'\n'
  done < <(idle_panes)

  if [[ -z "$idle_raw" ]]; then
    printf '[%s] no idle codex panes\n' "$ts"
    return
  fi

  # (b) Pane filter: drop panes near 5h/wk cap.
  local meter_tsv=""
  if (( NO_TOKEN_CHECK == 0 )); then
    meter_tsv=$(token_meter_snapshot || true)
  fi
  local skip_tmp; skip_tmp=$(mktemp)
  local healthy_raw
  healthy_raw=$(filter_panes_by_cap "$idle_raw" "$meter_tsv" "$skip_tmp")

  local skipped_count=0
  if [[ -s "$skip_tmp" ]]; then
    skipped_count=$(head -n1 "$skip_tmp" 2>/dev/null || echo 0)
    # Echo per-pane skip reasons (only first line is the counter). The
    # `|| [[ -n $sl ]]` guard catches the last line when the file has no
    # trailing newline.
    while IFS= read -r sl || [[ -n "$sl" ]]; do
      [[ -n "$sl" ]] && printf '%s\n' "$sl"
    done < <(tail -n +2 "$skip_tmp" 2>/dev/null)
  fi
  rm -f "$skip_tmp"

  local -a healthy_panes=() healthy_agents=()
  while IFS=$'\t' read -r p a; do
    [[ -z "$p" ]] && continue
    healthy_panes+=("$p")
    healthy_agents+=("$a")
  done <<<"$healthy_raw"

  if (( ${#healthy_panes[@]} == 0 )); then
    printf 'tick: claimed 0 of 0 ready (wave=-); skipped %s capped panes\n' "$skipped_count"
    return
  fi

  # (c) Plan selection: priority plan = newest. Query Colony per first
  # healthy agent, then group by wave_index → pick lowest wave with work.
  local priority_slug
  priority_slug=$(priority_plan_slug)
  local lens_agent=""
  local i
  for i in "${!healthy_agents[@]}"; do
    if [[ -n "${healthy_agents[$i]}" ]]; then
      lens_agent="${healthy_agents[$i]}"; break
    fi
  done

  local colony_tsv=""
  if [[ -n "$priority_slug" && -n "$lens_agent" ]]; then
    colony_tsv=$(colony_ready_for_plan "$priority_slug" "$lens_agent" || true)
  fi

  # Decide wave-parallel batch.
  local wave_pick=-1
  local -a batch_sub=() batch_title=()
  if [[ -n "$colony_tsv" ]]; then
    # Pick lowest wave_idx with any ready items.
    wave_pick=$(printf '%s\n' "$colony_tsv" | awk -F'\t' 'NF>=2 {print $2}' | sort -n | head -1)
    if [[ -n "$wave_pick" ]]; then
      while IFS=$'\t' read -r s w t; do
        [[ -z "$s" ]] && continue
        [[ "$w" != "$wave_pick" ]] && continue
        batch_sub+=("$s")
        batch_title+=("$t")
      done < <(printf '%s\n' "$colony_tsv")
    fi
  fi

  # Fallback: legacy plan.json scan. Used when Colony returned nothing
  # for the priority plan (colony unreachable, priority plan exhausted,
  # or pane agent slugs not yet resolvable). We still try to keep the
  # wave-parallel shape: if the priority plan has any ready tasks in the
  # plan.json scan, batch its lowest-wave group; otherwise fall back to
  # the cross-plan list (older multi-plan path).
  if (( ${#batch_sub[@]} == 0 )); then
    local -a fb_slugs=() fb_subs=() fb_titles=() fb_waves=()
    while IFS=$'\t' read -r slug idx wave title; do
      [[ -z "$slug" ]] && continue
      fb_slugs+=("$slug")
      fb_subs+=("$idx")
      fb_waves+=("$wave")
      fb_titles+=("$title")
    done < <(ready_tasks_all)
    if (( ${#fb_subs[@]} == 0 )); then
      printf '[%s] no ready tasks across any plan\n' "$ts"
      printf 'tick: claimed 0 of 0 ready (wave=-); skipped %s capped panes\n' "$skipped_count"
      return
    fi

    # Prefer rows on the priority plan, grouped by lowest wave_idx.
    if [[ -n "$priority_slug" ]]; then
      local lowest_wave=""
      local -a prio_sub=() prio_title=()
      local fi
      for fi in "${!fb_slugs[@]}"; do
        [[ "${fb_slugs[$fi]}" != "$priority_slug" ]] && continue
        local w="${fb_waves[$fi]}"
        if [[ -z "$lowest_wave" ]] || (( w < lowest_wave )); then
          lowest_wave="$w"
        fi
      done
      if [[ -n "$lowest_wave" ]]; then
        for fi in "${!fb_slugs[@]}"; do
          [[ "${fb_slugs[$fi]}" != "$priority_slug" ]] && continue
          [[ "${fb_waves[$fi]}" != "$lowest_wave" ]] && continue
          prio_sub+=("${fb_subs[$fi]}")
          prio_title+=("${fb_titles[$fi]}")
        done
        if (( ${#prio_sub[@]} > 0 )); then
          local total_ready=${#prio_sub[@]}
          local n=$total_ready
          (( ${#healthy_panes[@]} < n )) && n=${#healthy_panes[@]}
          local idx
          for ((idx=0; idx<n; idx++)); do
            dispatch "${healthy_panes[$idx]}" "$priority_slug" "${prio_sub[$idx]}" "${prio_title[$idx]}"
          done
          printf 'tick: claimed %d of %d ready (wave=%s); skipped %s capped panes\n' \
            "$n" "$total_ready" "$lowest_wave" "$skipped_count"
          return
        fi
      fi
    fi

    # Cross-plan fallback (older multi-plan path). Round-robin 1:1.
    local total_ready=${#fb_subs[@]}
    local n=$total_ready
    (( ${#healthy_panes[@]} < n )) && n=${#healthy_panes[@]}
    local idx
    for ((idx=0; idx<n; idx++)); do
      dispatch "${healthy_panes[$idx]}" "${fb_slugs[$idx]}" "${fb_subs[$idx]}" "${fb_titles[$idx]}"
    done
    printf 'tick: claimed %d of %d ready (wave=mixed-fallback); skipped %s capped panes\n' \
      "$n" "$total_ready" "$skipped_count"
    return
  fi

  # (d) Wave-parallel dispatch for priority plan.
  local total_ready=${#batch_sub[@]}
  local n=$total_ready
  (( ${#healthy_panes[@]} < n )) && n=${#healthy_panes[@]}
  local idx
  for ((idx=0; idx<n; idx++)); do
    dispatch "${healthy_panes[$idx]}" "$priority_slug" "${batch_sub[$idx]}" "${batch_title[$idx]}"
  done
  printf 'tick: claimed %d of %d ready (wave=%s); skipped %s capped panes\n' \
    "$n" "$total_ready" "$wave_pick" "$skipped_count"
}

start_claim_trigger() {
  if [[ "$CLAIM_MODE" == "poll" ]]; then
    return 0
  fi
  if (( DRY == 1 )); then
    printf '[%s] claim-trigger skipped in dry-run mode (mode=%s)\n' "$(date +%T)" "$CLAIM_MODE"
    return 0
  fi

  local trigger="$SCRIPT_DIR/claim-trigger.sh"
  if [[ ! -x "$trigger" ]]; then
    printf '[%s] claim-trigger unavailable at %s; continuing with poll mode\n' "$(date +%T)" "$trigger" >&2
    return 0
  fi

  mkdir -p "$(dirname "$CLAIM_TRIGGER_LOG")"
  CLAIM_TRIGGER_REPO="$REPO" \
    CLAIM_TRIGGER_SESSION="$SESSION" \
    CLAIM_TRIGGER_WINDOW="$WINDOW" \
    CLAIM_TRIGGER_LOG="$CLAIM_TRIGGER_LOG" \
    "$trigger" >>"$CLAIM_TRIGGER_LOG" 2>&1 &
  CLAIM_TRIGGER_PID="$!"
  printf '[%s] claim-trigger started pid=%s mode=%s log=%s\n' \
    "$(date +%T)" "$CLAIM_TRIGGER_PID" "$CLAIM_MODE" "$CLAIM_TRIGGER_LOG"

  sleep 0.1
  if ! kill -0 "$CLAIM_TRIGGER_PID" 2>/dev/null; then
    local ec=0
    wait "$CLAIM_TRIGGER_PID" || ec=$?
    printf '[%s] claim-trigger exited early status=%s; poll backstop remains active\n' "$(date +%T)" "$ec" >&2
    CLAIM_TRIGGER_PID=""
  fi
}

stop_claim_trigger() {
  if [[ -n "$CLAIM_TRIGGER_PID" ]] && kill -0 "$CLAIM_TRIGGER_PID" 2>/dev/null; then
    kill "$CLAIM_TRIGGER_PID" 2>/dev/null || true
    wait "$CLAIM_TRIGGER_PID" 2>/dev/null || true
  fi
}

if (( LOOP == 1 )); then
  trap 'stop_claim_trigger' EXIT
  trap 'stop_claim_trigger; echo force-claim: stopping >&2; exit 0' INT TERM
  start_claim_trigger
  if [[ "$CLAIM_MODE" == "event" ]]; then
    if (( DRY == 1 )); then
      one_pass
      exit 0
    fi
    if [[ -z "$CLAIM_TRIGGER_PID" ]]; then
      printf 'force-claim: event mode requested but claim-trigger is not running\n' >&2
      exit 1
    fi
    wait "$CLAIM_TRIGGER_PID"
    exit $?
  fi

  empty_streak=0
  while true; do
    one_pass
    if (( QUIT_EMPTY == 1 )); then
      # Plans-rolled-up status. Quit only when no available AND no claimed
      # work remains across every plan — completed-only or blocked-only is
      # a stable end state.
      IFS=$'\t' read -r avail claimed completed blocked < <(plans_status_summary)
      if (( avail == 0 && claimed == 0 )); then
        empty_streak=$(( empty_streak + 1 ))
        printf '[%s] empty-streak=%d/%d  completed=%d blocked=%d\n' \
          "$(date +%T)" "$empty_streak" "$EMPTY_THRESHOLD" "$completed" "$blocked"
        if (( empty_streak >= EMPTY_THRESHOLD )); then
          printf '[%s] all plans drained — exiting cleanly\n' "$(date +%T)"
          exit 0
        fi
      else
        empty_streak=0
      fi
    fi
    sleep "$INTERVAL"
  done
else
  one_pass
fi
