//! `fleet-worker-header --pane <id>` — emit one iOS-style status line for the
//! given tmux pane.
//!
//! The line is written verbatim to stdout. The intended caller pipes the
//! result into `tmux set-option -t <pane> pane-title "$(…)"`, which replaces
//! codex-CLI's noisy bottom-bar suggestions with a single, glanceable summary.
//!
//! Data sources (all best-effort; none are required for the binary to exit 0):
//!
//! - `/tmp/claude-viz/cap-probe-cache/*.json` — per-account cap state.
//! - `scripts/codex-fleet/fleet-status.sh --pane <id>` (when present) — the
//!   SI-4 JSON surface, sliced to this pane.
//! - `tmux capture-pane -p -t <pane>` — fallback when fleet-status.sh is
//!   absent or returns no useful data.
//!
//! Environment overrides honored:
//!
//! - `CODEX_FLEET_HEADER_FLEET_STATUS` — path to fleet-status.sh
//!   (default: `scripts/codex-fleet/fleet-status.sh`).
//! - `CODEX_FLEET_HEADER_CAP_DIR` — path to cap-probe cache dir
//!   (default: `/tmp/claude-viz/cap-probe-cache`).
//! - `CODEX_FLEET_HEADER_WIDTH` — width budget in columns (default: 80).
//! - `CODEX_FLEET_AGENT_NAME` — fallback agent name when fleet-status.sh
//!   can't supply one.
//! - `CODEX_FLEET_TIER` — fallback tier label.
//! - `CODEX_FLEET_ACCOUNT_EMAIL` — used to pick the right cap-probe cache
//!   entry when fleet-status.sh isn't authoritative.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::SystemTime;

use clap::Parser;
use fleet_worker_header::{render, CapState, HeaderState};
use serde_json::Value;

const DEFAULT_CAP_DIR: &str = "/tmp/claude-viz/cap-probe-cache";
const DEFAULT_FLEET_STATUS: &str = "scripts/codex-fleet/fleet-status.sh";

#[derive(Parser, Debug)]
#[command(
    name = "fleet-worker-header",
    about = "Render an iOS-style status header line for one codex-fleet worker pane.",
    long_about = "Composes per-worker state from /tmp/claude-viz/cap-probe-cache + \
                  scripts/codex-fleet/fleet-status.sh (or tmux capture-pane as a \
                  fallback) and emits a single UTF-8 line on stdout suitable for \
                  piping into `tmux set-option -t <pane> pane-title`."
)]
struct Args {
    /// The tmux pane id (e.g. `%337`) to render the header for.
    #[arg(long)]
    pane: String,

    /// Override the width budget. Falls back to `CODEX_FLEET_HEADER_WIDTH`
    /// then 80.
    #[arg(long)]
    width: Option<u16>,

    /// Print the gathered [`HeaderState`] as JSON instead of rendering.
    /// Useful for debugging the data pipeline without invoking ratatui.
    #[arg(long)]
    json: bool,
}

fn main() {
    let args = Args::parse();
    let state = gather_state(&args.pane);
    let width = args
        .width
        .or_else(|| {
            std::env::var("CODEX_FLEET_HEADER_WIDTH")
                .ok()
                .and_then(|v| v.parse().ok())
        })
        .unwrap_or(80);

    if args.json {
        match serde_json::to_string_pretty(&state) {
            Ok(s) => println!("{s}"),
            Err(e) => eprintln!("fleet-worker-header: json error: {e}"),
        }
        return;
    }

    println!("{}", render(&state, width));
}

fn gather_state(pane: &str) -> HeaderState {
    // 1. Start from the env fallbacks. fleet-status.sh, when present, will
    //    overwrite these with authoritative values.
    let mut state = HeaderState {
        agent_name: std::env::var("CODEX_FLEET_AGENT_NAME").unwrap_or_default(),
        tier: std::env::var("CODEX_FLEET_TIER").unwrap_or_default(),
        task_title: None,
        last_activity_age_secs: None,
        cap: CapState::Unknown,
    };

    // 2. Try fleet-status.sh --pane <id>.
    let status_path = std::env::var("CODEX_FLEET_HEADER_FLEET_STATUS")
        .unwrap_or_else(|_| DEFAULT_FLEET_STATUS.to_string());
    if Path::new(&status_path).is_file() {
        if let Some(json) = run_fleet_status(&status_path, pane) {
            apply_fleet_status(&mut state, &json, pane);
        }
    }

    // 3. If fleet-status didn't provide a last-activity age, fall back to
    //    parsing tmux capture-pane (look for trailing `Working (Xs)` blocks).
    if state.last_activity_age_secs.is_none() {
        if let Some(secs) = tmux_pane_activity_age(pane) {
            state.last_activity_age_secs = Some(secs);
        }
    }

    // 4. Always cross-check the cap-probe cache for this account. fleet-status
    //    might be stale by minutes; the cap-probe cache is poked every ~30s.
    let cap_dir =
        std::env::var("CODEX_FLEET_HEADER_CAP_DIR").unwrap_or_else(|_| DEFAULT_CAP_DIR.to_string());
    let account_email = std::env::var("CODEX_FLEET_ACCOUNT_EMAIL").unwrap_or_default();
    if let Some(cap) = read_cap_state(Path::new(&cap_dir), &account_email) {
        state.cap = cap;
    }

    state
}

fn run_fleet_status(path: &str, pane: &str) -> Option<Value> {
    // First try `--pane <id>` so the script can serve a slim slice.
    let pane_attempt = Command::new(path).args(["--pane", pane]).output().ok();
    if let Some(out) = pane_attempt {
        if out.status.success() && !out.stdout.is_empty() {
            if let Ok(v) = serde_json::from_slice::<Value>(&out.stdout) {
                return Some(v);
            }
        }
    }
    // Fallback: run with no args and let the caller pluck the worker.
    let bare = Command::new(path).output().ok()?;
    if !bare.status.success() {
        return None;
    }
    serde_json::from_slice::<Value>(&bare.stdout).ok()
}

fn apply_fleet_status(state: &mut HeaderState, json: &Value, pane: &str) {
    // The SI-4 schema places workers under `.workers[]`. When fleet-status was
    // invoked with --pane, the script may also return a single-worker object
    // directly. Handle both shapes.
    let worker = if json.get("pane_id").is_some() {
        Some(json)
    } else {
        json.get("workers")
            .and_then(Value::as_array)
            .and_then(|arr| {
                arr.iter()
                    .find(|w| w.get("pane_id").and_then(Value::as_str) == Some(pane))
            })
    };
    let Some(worker) = worker else { return };

    if let Some(agent) = worker.get("agent").and_then(Value::as_str) {
        if !agent.is_empty() {
            state.agent_name = agent.to_string();
        }
    }
    if let Some(tier) = worker.get("tier").and_then(Value::as_str) {
        if !tier.is_empty() {
            state.tier = tier.to_string();
        }
    }
    if let Some(age) = worker
        .get("last_activity_age_seconds")
        .and_then(Value::as_u64)
    {
        state.last_activity_age_secs = Some(age);
    }
    if let Some(task) = worker.get("claimed_task") {
        if task.is_object() {
            let title = task.get("title").and_then(Value::as_str).unwrap_or("");
            if !title.is_empty() {
                state.task_title = Some(title.to_string());
            }
        }
    }
}

fn tmux_pane_activity_age(pane: &str) -> Option<u64> {
    // `tmux display-message -p -t <pane> "#{pane_activity}"` returns a
    // unix timestamp for the last activity. If tmux is missing, return None.
    let out = Command::new("tmux")
        .args(["display-message", "-p", "-t", pane, "#{pane_activity}"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let ts: u64 = String::from_utf8_lossy(&out.stdout).trim().parse().ok()?;
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .ok()?
        .as_secs();
    Some(now.saturating_sub(ts))
}

fn read_cap_state(cap_dir: &Path, account_email: &str) -> Option<CapState> {
    let path: PathBuf = if account_email.is_empty() {
        // No email known — pick the freshest cache entry as a best-effort.
        freshest_cap_file(cap_dir)?
    } else {
        cap_dir.join(format!("{account_email}.json"))
    };
    let text = fs::read_to_string(&path).ok()?;
    let v: Value = serde_json::from_str(&text).ok()?;
    let verdict = v.get("verdict").and_then(Value::as_str)?;
    Some(match verdict {
        "healthy" | "ok" => CapState::Ok,
        "rate_limited" | "throttled" | "429" => CapState::RateLimited,
        "cooldown" => CapState::Cooldown,
        _ => CapState::Unknown,
    })
}

fn freshest_cap_file(cap_dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(cap_dir).ok()?;
    let mut best: Option<(SystemTime, PathBuf)> = None;
    for entry in entries.flatten() {
        let p = entry.path();
        if p.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let Ok(meta) = entry.metadata() else { continue };
        let Ok(mtime) = meta.modified() else { continue };
        match &best {
            None => best = Some((mtime, p)),
            Some((cur, _)) if mtime > *cur => best = Some((mtime, p)),
            _ => {}
        }
    }
    best.map(|(_, p)| p)
}
