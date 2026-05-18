---
name: codex-fleet
description: "Manage the multi-account Codex fleet: lifecycle, task assignment, status, and stalled-lane recovery."
---

# codex-fleet — orchestrator skill

You are the **host Claude session** acting as the orchestrator for the
codex-fleet defined in `scripts/codex-fleet/`. The fleet is N parallel
codex worker panes in a tmux session, each logged in under a different
`~/.codex/accounts/<email>.json` account in an isolated `CODEX_HOME`,
all polling tasks from the shared Colony queue.

Your job is to: bring the fleet up/down when asked, propose tasks via
Colony MCP tools, monitor for stalled lanes and rate-limit blockers,
and dedupe near-duplicate handoffs before showing the user a list.

## When this skill applies

Trigger phrases (Hungarian or English):

- "fleet", "codex fleet", "fleet status", "fleet up", "fleet down"
- "spin up workers", "spawn codex workers", "parallel codex"
- "tear down fleet", "stop the fleet"
- "give the fleet [task]", "have the fleet do [task]"
- "show me what the fleet is doing", "fleet attention"

Do NOT trigger this skill for:

- General codex-CLI questions unrelated to the fleet
- Manual single-account codex usage
- Colony task work that does not involve the fleet (use Colony MCP
  tools directly)

## Canonical bringup (always use `full-bringup.sh`)

One command, no ad-hoc panes:

```bash
bash scripts/codex-fleet/full-bringup.sh           # default: newest plan, 8 workers
bash scripts/codex-fleet/full-bringup.sh --plan-slug <slug> --n 8 --no-attach
```

`full-bringup.sh` atomically: prunes stale `refs/remotes/origin/<base>` → picks newest plan → `colony plan publish <slug>` (idempotent) → ranks 3N candidates by `agent-auth list` → runs `cap-probe.sh` to verify each candidate live → stages CODEX_HOMEs → creates `codex-fleet` session with FIVE windows in this order: `0 watcher` / `1 overview` / `2 fleet` / `3 plan` / `4 waves` → creates sibling `fleet-ticker` session with `ticker` + `cap-swap` + `state-pump` → attaches. Refuses to start if a `codex-fleet` session already exists.

## Canonical visual design (lock this in)

This is the operator-approved design language as of 2026-05-14. Do NOT regress to simpler renderers unless explicitly asked.

| Tab | Renderer (Rust default `FLEET_DASHBOARD_RENDERER=rust`) | Bash fallback (`FLEET_DASHBOARD_RENDERER=bash`) | Visual |
|-----|--------------------------------------|--------------------------------------|--------|
| `0 watcher`  | `rust/target/release/fleet-watcher` | `scripts/codex-fleet/watcher-board.sh`     | Header banner (ALL CLEAR/DEGRADED/STALLED) + 4 stat cards (PANES/CAPPED/SWAPPED/RANKED) + account-pool summary + per-pane table + CAP POOL sorted by reset ETA + filtered recent activity |
| `1 overview` | 8 codex worker panes                | (unchanged)                                | 2×4 grid; each pane runs codex with `CODEX_GUARD_BYPASS=1`         |
| `2 fleet`    | `rust/target/release/fleet-state`   | `scripts/codex-fleet/fleet-state-anim.sh`  | iOS cockpit: rounded card header (palette=#0a84ff/#30d158/#ff453a/#ff9f0a), ACTIVE table (account · 5h · WEEKLY · WORKER · WORKING ON), RESERVE table, FLEET FOOTER (active workers · refresh · tick) |
| `3 plan`     | `rust/target/release/fleet-plan-tree`| `scripts/codex-fleet/plan-tree-anim.sh`    | PLAN TREE header + W1→Wn DAG of sub-task chips → PROPOSALS rounded cards (file · deps · 👤worker · ✓PR# badge) + TOTAL bar + LEGEND (`● done · ◐ claimed · ✕ blocked · ◇ available`) |
| `4 waves`    | `rust/target/release/fleet-waves`   | `scripts/codex-fleet/waves-anim-generic.sh`| Vertical wave flow `W1 → W2 → … → Wn`, each sub-N with status dot + title + `done` / `claimed` / `available` tag |

**Rust renderer self-contained tab clicks:** every Rust bin renders its own
in-binary tab strip at the top of its frame. Clicking a tab dispatches a
`tmux select-window` call via the bin's crossterm mouse handler — bypasses
tmux's `MouseDown1Status` routing entirely and works in kitty+tmux even
when status-bar click routing fails (cf. fleet-tui-ratatui-port-2026-05-14
acceptance criterion #8).

**Build the Rust bins** (one-time per fresh clone or after a pull):

```bash
cd "$CODEX_FLEET_REPO_ROOT/rust" && cargo build --release
```

The bash `*-anim.sh` scripts stay one release as the `FLEET_DASHBOARD_RENDERER=bash` fallback in case a Rust bin regresses; after one quiet release they're deleted (Phase 6 of the migration plan).

**Palette (iOS dark UIKit on black) — canonical hex set defined in `rust/fleet-ui/src/palette.rs`:**

| Token        | Hex      | Use                          |
|--------------|----------|------------------------------|
| systemBlue   | `#0a84ff`| `working` chip background    |
| systemGreen  | `#30d158`| `done`, `running`, healthy   |
| systemRed    | `#ff453a`| `blocked`, capped, error     |
| systemOrange | `#ff9f0a`| `polling`, mid-tier warning  |
| systemYellow | `#ffd60a`| `claimed` spinner pulse      |
| systemPurple | `#bf5af2`| spawn / boot                 |
| label        | `#f2f2f7`| primary fg                   |
| secondaryLabel | `#a0a0aa`| muted labels               |

**Chrome rules:**

- Rounded ASCII frames (`╭─╮ ╰─╯` or `┌─┐ └─┘`) with 2-space horizontal padding inside.
- Pill-style status chips: solid bg color + bold white fg + 1-char padding on either side. Examples: `[ running ]` green, `[ working ]` blue, `[ idle ]` gray, `[ polling ]` orange.
- Per-row progress bars: solid `█` filled, shade `░` empty; color shifts green→orange→red as percent declines.
- Header banner format: `WATCHER · <session> · ●live · <time> · last sweep <ts> · next in Ns · <STATUS>`.
- Tab order in `codex-fleet`: `0 watcher / 1 overview / 2 fleet / 3 plan / 4 waves` — watcher first so it's the default landing.

**Hard rules baked into bringup (don't bypass):**

1. Every codex spawn line includes `CODEX_GUARD_BYPASS=1` to avoid the codex-guard branch-collision storm when N panes spawn within the same second.
2. Pre-spawn `git remote prune origin && git fetch --prune origin` to clear stale `refs/remotes/origin/<base>`.
3. Plan publish (`colony plan publish <slug>`) is non-negotiable — workers can only claim from registered plans.
4. Account selection runs through `cap-probe.sh` (live `codex exec` probe), not raw `agent-auth list` percentages — codex CLI's rolling cap is separate from the API meter.
5. Capped accounts are remembered with their reset epoch at `/tmp/claude-viz/cap-probe-cache/<email>.json`; cache lookups skip re-probing for the duration (could be hours, days, or weeks).
6. The cap-swap daemon runs in `fleet-ticker:cap-swap` as the autonomous global watcher — never spawn a separate Claude session to "watch the fleet".

## Lifecycle commands

All commands assume CWD = the codex-fleet clone root (`$CODEX_FLEET_REPO_ROOT`).
The fleet config lives at `scripts/codex-fleet/accounts.yml` (user-edited from
`accounts.example.yml`; gitignored). Verify it exists before any `up`.

### `up` — spawn the fleet

```bash
bash scripts/codex-fleet/up.sh --no-attach
tmux ls
```

Expect `codex-fleet: 1 windows (...)` and stdout that lists
`[codex-fleet] staged <id> (<email>) -> /tmp/codex-fleet/<id>`. If
`accounts.yml` is missing or unreadable, the script exits with
`fatal: config not found` — copy from the example template first:

```bash
cp scripts/codex-fleet/accounts.example.yml scripts/codex-fleet/accounts.yml
$EDITOR scripts/codex-fleet/accounts.yml
```

Verify each `email:` field matches an existing auth file before `up`:

```bash
for f in $(awk -F': ' '/email:/{print $2}' scripts/codex-fleet/accounts.yml); do
  test -f "$HOME/.codex/accounts/$f.json" && echo "OK $f" || echo "MISSING $f"
done
```

### `attach` — see what the fleet is doing

When the user asks to **see / show / open / visualize the live fleet
panel** ("show me the fleet UI", "open the fleet", "live panel", "nyisd
meg a fleetet", "i want to see the panels"), do NOT capture-pane into a
static text file under `/tmp/claude-viz/`. That is frozen text and the
user immediately complains it isn't live. Instead, **spawn a detached
kitty window that runs `tmux attach -t codex-fleet`**:

```bash
setsid kitty --title "codex-fleet live" \
  tmux attach -t codex-fleet </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
```

That gives the user the real session with live-updating panels
(watcher refreshes every 30s, fleet-state-anim animates), interactive
codex panes they can click into, and the rounded iOS tab strip with
clickable tabs. After spawning, **immediately re-apply tab-strip chrome
and click bindings** because newly-spawned attaches sometimes land
before / after `style-tabs.sh` finalized status height and per-window
status format:

```bash
CODEX_FLEET_SESSION=codex-fleet bash scripts/codex-fleet/style-tabs.sh
```

`style-tabs.sh` is the single source of truth for the iOS tab strip,
rounded pane borders, and the `tmux bind-key -T root MouseDown1Status`
handler that turns tab clicks into `select-window`. If clicks do
nothing, run that script — don't hand-set `status-format` or
`window-status-format`.

Inside tmux: `Ctrl+B` then `D` to detach without killing the session.
`Ctrl+B` then arrow keys to move between panes. `Ctrl+B` then `Z` to
zoom one pane to fill the screen.

The bottom status bar shows the window tabs
(`0:overview 1:fleet 2:plan 3:waves 4:review 5:watcher`); switch with
`Ctrl+B` then the digit, `Ctrl+B n`/`p` for next/prev, or **left-click
the tab name** (the click handler is installed by `style-tabs.sh`).
`full-bringup.sh` forces the status bar on with a high-contrast style
right after `tmux new-session`, so it stays visible even when the user's
global `~/.tmux.conf` hides or restyles the default bar.

If `full-bringup.sh` warned `iOS chrome looks wrong: status_height=-76
(expected 3)`, the chrome regressed to defaults. Re-run
`style-tabs.sh` (command above) — it idempotently re-renders the 3-row
tab strip and click handlers on the live session without restarting.

When the user reports "i can't click tabs", "menu doesn't work",
"can't move between tabs" — the fix is always the same: rerun
`style-tabs.sh`. Don't suggest tearing down the fleet.

The watcher's `FLEET PANES` card has two quota-related columns:

- `5h-LIVE` — verdict from the cap-probe cache (`/tmp/claude-viz/cap-probe-cache/<email>.json`), set by an actual `codex exec` round-trip during the sweep. `✓ OK` green if healthy, `✕ <eta>` red if capped (eta is time until reset, e.g. `6d`), `? ??` gray if unknown. This is the authoritative "is this account usable right now" signal — agent-auth's `5h=` column is the API meter and reads 100% even when the rolling cap is fine, so the watcher does **not** display that value directly.
- `WK-USED` — raw `weekly=N%` value parsed from `agent-auth list`, no inversion. Green ≤40%, yellow ≤75%, red above. Reads identically to what the operator sees in their shell.

### `down` — tear it down

```bash
bash scripts/codex-fleet/down.sh
```

Preserves `/tmp/codex-fleet/<id>/auth.json` so the next `up` is fast.
Pass `--purge` to wipe the staged auth files when rotating accounts.

### `status` — quick check

```bash
tmux ls 2>&1 | grep -c codex-fleet     # 0 or 1
curl -s localhost:8100/healthz | jq -r '.backend'   # ort-cuda-minilm
colony config get embedding.provider   # "codex-gpu"
```

All three should be green before assuming the fleet is healthy. If
embedder is `cpu-stub` or Colony is `"local"`, see Troubleshooting.

### Claude-fallback workers (when codex caps run out)

When `cap-probe.sh` cannot find enough healthy codex accounts to fill
the requested pane count, fill the remaining slots with Claude Code
workers. Codex workers use isolated `CODEX_HOME`s and one ChatGPT seat
per pane; Claude workers all share the user's single Anthropic
subscription, so this is a backup — useful when the codex pool is
exhausted, not the primary spawn path.

Files (already on disk):

- `scripts/codex-fleet/claude-worker.sh` — wrapper that runs
  `claude --dangerously-skip-permissions` against the adapted prompt
  and re-launches on exit. Logs to `/tmp/claude-viz/claude-worker-<id>.log`.
- `scripts/codex-fleet/claude-wake-prompt.md` — Claude-tailored copy
  of the codex worker prompt (renames env refs from `$CODEX_*` to
  `$CLAUDE_FLEET_*`, names the same Colony MCP loop).

Spawn manually (one pane):

```bash
tmux split-window -h -t codex-fleet:overview -c "$CODEX_FLEET_REPO_ROOT" \
  "CLAUDE_FLEET_AGENT_NAME=claude-fleet-1 \
   CLAUDE_FLEET_ACCOUNT_LABEL=<account-tag> \
   bash $CODEX_FLEET_REPO_ROOT/scripts/codex-fleet/claude-worker.sh"
```

Spawn from the orchestrator: **the Claude Code permission gate blocks
this for the orchestrator session itself** (the worker invokes
`--dangerously-skip-permissions`, which is correctly classified as an
autonomous tool-call loop). The operator must run the command manually
from a shell, OR add a project-scoped permission rule in
`.claude/settings.local.json` allowing the specific
`bash scripts/codex-fleet/claude-worker.sh ...` invocation.

Quota model: every Claude worker counts against the same Anthropic
subscription. N parallel Claude workers ≈ N× the API spend on one
account, unlike codex where each pane has its own seat. Size the
Claude fallback small (1–2 panes) unless you have multiple Anthropic
API keys staged via separate `~/.claude/` configs.

Rate-limit handling: when scrollback contains `429` / `rate-limit` /
`usage-limit`, the wrapper sleeps `RATE_LIMIT_DELAY_SEC` (default 300s)
before relaunching, instead of the normal `RESTART_DELAY_SEC` (30s).

Identification in Colony: Claude panes report as
`claude-fleet-<id>` (versus codex panes which report as
`codex-<id>`). Use this to spot which engine handled which sub-task in
`task_timeline`.

Not yet integrated into `full-bringup.sh`: cap-probe shortfall currently
leaves empty slots rather than auto-falling back. Until that's wired,
the operator runs the manual `tmux split-window` above when they want
the slack filled.

## Task assignment

The fleet does NOT execute Claude-orchestrator messages directly. Each
pane pulls work from the Colony queue independently. Your job is to
**propose tasks via Colony MCP** and let the panes self-claim.

When the user gives you a parallel-work request, decompose into N
sub-tasks (one per pane, ideally), then for each:

```
mcp__colony__task_propose({
  repo_root: "$CODEX_FLEET_REPO_ROOT",
  branch: "<an agent branch the worker will create>",
  summary: "<one line, action-first>",
  rationale: "<2-3 sentences: why this task, what evidence to produce>",
  touches_files: ["path/a", "path/b"],   // best-effort hint
  session_id: "<your session id>"
})
```

Hint the right skill set in the rationale when it matters (e.g. "needs
code-review skill" → matches the `review` account's skills array in
`accounts.yml`).

The fleet panes call `mcp__colony__task_ready_for_agent` on a 60s loop
and auto-claim the next ready sub-task. You do NOT push directly to a
specific pane.

## Continuous supervision (sidetask — always on while fleet is up)

When the fleet is up, you are not idle between user messages — you are
the **supervisor on duty**. The pull model means workers won't ask you
for help; you have to look. Run the supervisor loop below whenever you
have free turns (between tool calls the user asked for, after every
status check, on every notification).

### The supervisor loop (one pass = ~10 seconds of work)

1. **Snapshot.** Call `fleet-status.sh` (SI-4) once. If `fleet-mcp` (SI-1)
   is registered, prefer `fleet_status` MCP tool — it's the same JSON
   but doesn't shell out. Parse the result.

2. **Classify every worker.** From the snapshot's `workers[]`:
   - `working` with a `claimed_task` → healthy; note the age
   - `working` with no `claimed_task` for > 3 minutes → probably stuck
     on the worker prompt or chasing a bad task; capture pane + read
   - `waiting-on-prompt` → SI-2 stall-watcher should dismiss within
     5s; if it's still there after 30s, SI-2 has a fixture gap — note
     the prompt text and add it as a fixture
   - `errored` → check the BLOCKED reason; if it's `preflight=writable-root`
     the worker got routed to a foreign plan (specialty filter missed) —
     `colony plan archive` the stale plan OR send an explicit OVERRIDE
     prompt with `task_plan_claim_subtask` pinned to the priority plan
   - `idle` → wait one cycle; if still idle after two cycles AND there
     are `available` subtasks for the priority plan, send an explicit
     claim prompt

3. **Read the daemon logs.** Tail these and look for new entries since
   last pass:
   - `/tmp/claude-viz/stall-watcher.log` — SI-2 dismissals (expected)
   - `/tmp/claude-viz/cap-budget-alerts.log` — SI-10 transitions (act
     on `breach`)
   - `/tmp/claude-viz/cap-swap.log` — 429 hand-offs
   - `/tmp/claude-viz/conductor-broadcasts.jsonl` — any operator
     messages routed through the conductor
   - `/tmp/claude-viz/cap-budget.alert` — flag file from SI-10; if
     present, a majority of accounts are 429

4. **Read PR state for the active plan.** `gh pr list --search 'agent/
   in:branch' --json number,headRefName,statusCheckRollup,state`.
   For each open PR:
   - CI passing + mergeable → SI-8 pr-babysitter (or the repo's own
     auto-merge workflow) handles it; verify it's progressing
   - CI failing → SI-8 should hand off; if it didn't (e.g. the PR was
     opened before SI-8 was wired), open a Colony note manually and
     release the claim
   - Mergeable but stalled (no auto-merge enabled on the repo) → flag
     it to the user with the PR URL and a one-line summary

5. **Brainstorm improvements as you go.** Every time you do something
   manually that the daemons *should* have done, that's a future SI-N
   proposal. Keep a running list in the active conversation's tasks
   (`TaskCreate` with subject prefixed `[supervisor-idea]`) — at the
   end of the run, propose them as a new
   `openspec/plans/supervisor-improvements-<date>/plan.json` and
   either implement directly (via parallel Claude Code sub-agents,
   per the 2026-05-18 precedent) or hand the plan to the next codex
   fleet bringup.

### What "managing agents" actually means

The fleet's contract is pull-based: workers pick tasks. As supervisor
you do the things workers cannot do for themselves:

- **Routing override.** When `task_ready_for_agent` keeps returning
  foreign-plan tasks that fail writable-root preflight, the workers
  loop on BLOCKED notes forever. Detect the loop (≥2 BLOCKED notes
  for the same `task_id` from the same agent within 5 minutes) and:
  (a) archive the offending plan if it's truly stale, OR (b) send an
  explicit `task_plan_claim_subtask` prompt pinning the worker to a
  subtask of the priority plan.
- **Stuck-worker rescue.** A worker stuck on an interactive prompt
  that SI-2 doesn't know about is a new fixture. Send the right key
  sequence manually, then capture the prompt as a stall-watcher
  fixture under `scripts/codex-fleet/test/stall-fixtures/`.
- **Cross-claim deconfliction.** If two workers somehow claim the
  same subtask despite SI-6 claim-fence (rare race), one of them
  should `task_hand_off` and let the other finish.
- **Plan exhaustion.** When the priority plan has 0 `available`
  subtasks and workers are idle, either publish the next plan or
  tear down. Idle workers spinning task_ready_for_agent at 60s
  intervals burn quota for nothing.
- **Capacity coordination.** SI-10 surfaces the >50% 429 alert; you
  decide whether to scale workers down (`--n 2` next bringup), wait
  for cooldown, or run only the cheapest tier accounts until reset.

### What never to do as supervisor

- **Never silently kill a worker mid-claim** unless you've reassigned
  the task. Use `task_hand_off` then send an interrupt, not the other
  way around.
- **Never commit to `main` directly to "fix" what a worker is doing**
  — that breaks the audit trail. Open an `agent/<owner>/` branch
  yourself, push, PR.
- **Never edit a worker's CODEX_HOME or auth.json** while the fleet
  is up — kill the fleet first.
- **Never delete an `openspec/plans/<slug>/plan.json` while workers
  are claimed against it.** Archive the plan instead
  (`colony plan close <slug>` once subtasks are completed-or-released).

### Cadence

- **Every operator turn.** One supervisor-loop pass between handling
  the user's request.
- **Every notification.** When a sub-agent or background command
  completes, one pass.
- **Idle window.** If the user is silent for > 5 minutes and the
  fleet is up, run a pass + report any new findings in a single
  terse message. Do not spam.

### Carrying state across turns

Use the `memory/` lane (file-based) for durable supervisor knowledge:
new fixtures for SI-2, new prompts the workers ask, new failure modes
in CI, account-tier discoveries. Each gets a small memory file and a
`MEMORY.md` index entry. Do **not** stuff this into Colony — Colony
is for tasks, not supervisor notes.

## Monitoring

### Quick status

```
mcp__colony__attention_inbox({
  session_id: "<your session id>",
  agent: "claude",
  repo_root: "$CODEX_FLEET_REPO_ROOT"
})
```

Look at `stalled_lanes`, `pending_handoff_count`, `unread_message_count`.
A pane that has been idle > 5 min is likely either: (a) waiting for the
next ready task — fine, (b) hit a 429 and is sleeping the 5-minute
release window, or (c) crashed — `tmux ls` to confirm pane count.

### Dedupe near-duplicate handoffs

When `attention_inbox` returns many `needs_reply` items, cluster them
before showing the user a long list:

```
mcp__colony__cluster_observations({
  ids: [<handoff observation_ids from attention_inbox>],
  threshold: 0.85
})
```

Show the user only the `canonical_id` of each cluster plus
`"+N similar handoffs"`. Hydrate canonical bodies with
`mcp__colony__get_observations` for the few that need detail.

### Semantic recall

To answer "what has the fleet learned about X?" use the pure-vector
tool — keyword search alone misses cross-pane vocabulary drift:

```
mcp__colony__semantic_search({
  query: "<concept the user is asking about>",
  limit: 20
})
```

## Reading and triggering panes from Claude

The pull model is the contract: workers self-claim from Colony. But the
host Claude session frequently needs to **inspect** what a pane is
doing (debugging a stalled lane, diffing scrollback against an expected
worker-prompt step, confirming a 429 sleep is really happening), and
occasionally — when the operator pre-authorizes it — needs to **inject**
a prompt into a specific pane (force-claim, manual rescue, copy-paste a
multi-line directive the worker prompt cannot encode).

This section is the canonical surface for both. Prefer `panels.sh`
(once landed; see proposal #6) over raw tmux invocations; the raw form
is documented here so the helper has a spec to match.

### Pane addressing

Three stable handles, in order of preference:

| Handle              | Example                                     | Stable across …   |
|---------------------|---------------------------------------------|-------------------|
| tmux pane id        | `%30`                                       | retiles, kills    |
| `@panel` option     | `[codex-pia-magnolia]` (set by spawn script)| pane-id reuse     |
| index               | `codex-fleet-2:overview.3`                  | nothing — shifts on every split/kill |

The spawn scripts (`up.sh`, `add-workers.sh`, `full-bringup.sh`) set
`tmux set-option -p -t <pid> '@panel' '[codex-<aid>]'` on every spawn,
so `@panel` lookups survive layout retiles. Resolve agent-name → pid:

```bash
tmux list-panes -t codex-fleet-2:overview -F '#{pane_id} #{@panel}' \
  | awk -v want='[codex-pia-magnolia]' '$2==want{print $1}'
```

### Reading: `tmux capture-pane`

Read-only, always safe. Use `-S -N` to scroll back N lines:

```bash
# Last 40 lines of one pane:
tmux capture-pane -p -t codex-fleet-2:overview.3 -S -40

# All panes in a window, with headers:
for p in $(tmux list-panes -t codex-fleet-2:overview -F '#{pane_index}'); do
  echo "=== pane $p ==="
  tmux capture-pane -p -t "codex-fleet-2:overview.$p" -S -8
done

# Detect dead/idle panes (matches add-workers.sh find_dead_pane patterns):
tmux capture-pane -p -t <pid> -S -80 \
  | grep -E 'hit your usage limit|Please run .codex login.|\[Process completed\]|\[exited\]|session has ended'
```

Use this before any `send-keys` to confirm the pane is at a codex idle
prompt (`›`) and not mid-execution. Sending into a busy codex pane
appends to the queued input and is rarely what you want.

### Sending: `tmux send-keys` (operator-authorized only)

Default policy: **do not send unless the operator pre-authorized it**
in this conversation, in CLAUDE.md, or via memory. The orchestrator
contract is pull-only. Authorized cases (recorded so far):

- The operator says "dispatch this prompt to pane X" / "tell pane
  codex-vrzi-mite to run /review" / similar explicit instruction.
- Memory `feedback_gx_fleet_dispatch_authorized` flags the operator as
  pre-approving `tmux send-keys` for gx-fleet pane prompt injection;
  the codex-fleet panes inherit the same authorization when the
  operator explicitly asks for fleet-pane dispatch.
- Memory `feedback_codex_pane_approval_authorized` flags pre-approval
  for clicking codex approval gates inside fleet panes for safe MCP
  and read calls.

When authorized, send literal text and terminate with `Enter`:

```bash
# Single-line prompt:
tmux send-keys -t codex-fleet-2:overview.3 'task_ready_for_agent for codex-pia-magnolia' Enter

# Multi-line: use one send-keys per logical line, or paste via buffer:
printf '%s' "$LONG_PROMPT" | tmux load-buffer -
tmux paste-buffer -t codex-fleet-2:overview.3
tmux send-keys  -t codex-fleet-2:overview.3 Enter
```

Hard rules when sending:

1. **Capture first, send second.** Confirm the pane is at `›` idle.
2. **Never send to a `bash` pane** — those are dead codex-guard panes,
   and shell-evaluating the prompt as a command can do arbitrary harm.
   Filter with `tmux list-panes -F '#{pane_current_command}'` first.
3. **Dedupe by content hash.** If you're sending the same prompt to N
   panes in a fan-out, hash it and skip panes whose last-200-line tail
   already contains the hash.

### Respawning: kill + spawn with `CODEX_GUARD_BYPASS=1`

When a pane is dead (`bash` shell, branch-collision message, "hit your
usage limit" stuck for >10 min and the cap-swap daemon hasn't picked it
up yet), respawn in-place instead of splitting (which shrinks every
neighbor):

```bash
AID=pia-magnolia
EMAIL=pia@magnoliavilag.hu
HOME_DIR=/tmp/codex-fleet/$AID
PROMPT_FILE=/tmp/codex-fleet/wake-prompts/$(ls -t /tmp/codex-fleet/wake-prompts/ | head -1)

PANE_CMD="env CODEX_GUARD_BYPASS=1 \
  CODEX_HOME='$HOME_DIR' \
  CODEX_FLEET_AGENT_NAME='codex-$AID' \
  CODEX_FLEET_ACCOUNT_EMAIL='$EMAIL' \
  codex \"\$(cat '$PROMPT_FILE')\""

tmux respawn-pane -k -t codex-fleet-2:overview.3 "$PANE_CMD"
tmux set-option -p -t codex-fleet-2:overview.3 '@panel' "[codex-$AID]"
```

`CODEX_GUARD_BYPASS=1` is **mandatory**. Without it codex-guard
auto-generates `agent/codex/codex-task-<timestamp>` branch slugs and N
panes spawned in the same second collide on the same slug; N−1 die
with `fatal: a branch named ... already exists`. Memory:
`feedback_codex_guard_bypass_for_parallel_spawns`. `add-workers.sh`
currently forgets this env (proposal #5 fixes it); until that ships,
prefer the inline `respawn-pane` above for new spawns.

### `panels.sh` helper (planned)

`scripts/codex-fleet/panels.sh` (proposal #6) wraps the above with
subcommands:

| Subcommand                       | Behavior                                                              |
|----------------------------------|-----------------------------------------------------------------------|
| `panels.sh list [--session S]`   | One row per pane: index · pane_id · agent-name (`@panel`) · last line |
| `panels.sh read <addr> [-n N]`   | `capture-pane -p -S -N` against `<addr>` (index, id, or agent-name)   |
| `panels.sh send <addr> '<text>'` | Gated by `FLEET_PANELS_ALLOW_SEND=1`; capture-then-send; refuses bash |
| `panels.sh respawn <addr> <aid>` | Kill + respawn with `CODEX_GUARD_BYPASS=1` and staged home lookup     |

Use this helper from any orchestrator session (Claude, codex
supervisor, ad-hoc shell). Until it lands, the raw tmux invocations
above are the contract.

## Troubleshooting

### Pane exits immediately on `up`

Likely `codex` got `EOF` from stdin and exited. The current `up.sh`
passes the prompt as a positional arg; if you see the bug recur after a
codex CLI upgrade that changes positional arg behavior, fall back to
`codex` with stdin held open via a heredoc kept alive by `sleep
infinity`. Edit `scripts/codex-fleet/up.sh` `pane_cmd=` line.

### codex-gpu embedder / workspace-build `colony` reinstall

Both of these are recodee-internal — the `codex-gpu-embedder` binary
and the workspace-build `colony` CLI live inside the recodee product
tree. See `docs/recodee-extras.md` for the rebuild recipes. Public
consumers of codex-fleet do not need them.

### One pane is stuck on a 429 / rate-limit

The pane's worker-prompt instructs it to release the claim and sleep
5 min. The released task should be picked up by another pane with a
different account. Verify:

```
mcp__colony__attention_inbox(...)  # check `stalled_lanes` for the
                                   # released claim being re-picked
```

If the released task is still stuck after ~6 min, manually re-propose
it with a different skill hint that biases routing away from the
exhausted account.

### Fleet up but Colony shows no agent activity

Each pane needs the Colony MCP server registered in its CODEX_HOME.
Check:

```bash
ls /tmp/codex-fleet/<pane-id>/config.toml
# This should be a symlink to ~/.codex/config.toml. If missing, the
# pane's codex won't know about Colony MCP at all.
```

If the symlink is broken, re-run `down --purge` then `up` to re-stage.

## Limits worth being honest about

- **Single-host only.** All panes on one machine. No remote workers.
- **No automatic rate-limit failover policy.** The worker-prompt
  prescribes "release + sleep 5 min"; smarter routing would need a
  Colony-side per-account quota tracker that does not exist yet.
- **No live aggregate dashboard.** `colony viewer` web UI shows the
  task queue; tmux shows the panes. No single pane shows the whole
  fleet. Acceptable for now; build a TUI if it becomes a real pain.
- **You cannot push to a specific pane.** The pull model is by design.
  If you need account-specific routing, encode it in the task
  rationale and Colony's skill matcher does the rest.

## What to NOT do

- Do not `tmux send-keys` directly into a pane unless the user
  explicitly asks. The pull model is the contract. When the operator
  *does* authorize sending (or memory marks them pre-authorized for
  this fleet), follow the procedure in "Reading and triggering panes
  from Claude" — capture first, refuse `bash` panes, dedupe by hash.
- Do not edit `~/.codex/auth.json` while the fleet is up. The panes
  use their own `CODEX_HOME` and the shared file is irrelevant to
  them — touching it just confuses future non-fleet codex sessions.
- Do not run `up.sh` while a previous session is still alive. The
  script aborts with a clear message; respect it and run `down` first.
- Do not propose tasks faster than the panes can claim them. The
  ready-poll cycle is ~60s; queueing 200 tasks at once is fine
  (Colony handles), but it makes monitoring noisy.
