//! Renders a single-line iOS-style status header for a codex-fleet worker pane.
//!
//! Layout (left-to-right, separated by `│`):
//!
//! ```text
//! ▲ <agent_name> │ <tier> │ <task_title or '— idle —'> │ <last_activity_age> │ cap: <state>
//! ```
//!
//! The renderer is deliberately pure: it takes a [`HeaderState`] and returns a
//! `String`. The caller (typically `main.rs`) is responsible for gathering the
//! state from `/tmp/claude-viz/cap-probe-cache/*.json`, `fleet-status.sh`, or
//! `tmux capture-pane` and piping the result into
//! `tmux set-option -t <pane> pane-title`.
//!
//! The output is plain UTF-8 — tmux pane titles do not support ANSI escapes,
//! so style is encoded as glyphs (`▲` for the agent badge, `│` as separator,
//! `cap: ok/429/cooldown`). Width-aware ellipsis truncation keeps the line
//! within the terminal width budget passed in by the caller.

use serde::{Deserialize, Serialize};

/// Capacity state for the worker's account, derived from
/// `/tmp/claude-viz/cap-probe-cache/<email>.json`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CapState {
    /// Probe says the account is healthy.
    Ok,
    /// Provider returned 429 on the last probe.
    #[serde(rename = "429")]
    RateLimited,
    /// Within a cooldown window after a 429.
    Cooldown,
    /// Probe stale or unreadable.
    #[default]
    Unknown,
}

impl CapState {
    /// Short label rendered after the `cap:` glyph.
    pub fn label(self) -> &'static str {
        match self {
            CapState::Ok => "ok",
            CapState::RateLimited => "429",
            CapState::Cooldown => "cooldown",
            CapState::Unknown => "?",
        }
    }
}

/// Tier label as set by `CODEX_FLEET_TIER`. We do not constrain the values
/// here — workers may use site-specific tiers — but the renderer truncates
/// long ones so the line still fits on narrow terminals.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tier(pub String);

/// Everything the renderer needs to produce one header line.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct HeaderState {
    /// Colony agent id for the worker, e.g. `codex-zazrifka`.
    pub agent_name: String,
    /// Account tier, e.g. `high`, `medium`, `low`.
    pub tier: String,
    /// Current Colony task title, or `None` for idle.
    pub task_title: Option<String>,
    /// Last activity, in seconds before "now". `None` when unknown.
    pub last_activity_age_secs: Option<u64>,
    /// Capacity state from the cap-probe cache.
    pub cap: CapState,
}

/// Render the header line, clamped to `width` columns.
///
/// `width` is in *display columns*. We approximate display width as
/// `chars().count()` — adequate for the ASCII + box-drawing glyphs we emit
/// and for the small set of unicode characters likely to appear in agent
/// names / task titles. Anything over budget is ellipsized in the task-title
/// field first (it is the most variable), then in agent_name, then in tier.
pub fn render(state: &HeaderState, width: u16) -> String {
    let sep = " │ ";

    let agent = if state.agent_name.is_empty() {
        "—".to_string()
    } else {
        state.agent_name.clone()
    };
    let tier = if state.tier.is_empty() {
        "—".to_string()
    } else {
        state.tier.clone()
    };
    let title = match &state.task_title {
        Some(t) if !t.is_empty() => t.clone(),
        _ => "— idle —".to_string(),
    };
    let age = format_age(state.last_activity_age_secs);
    let cap = format!("cap: {}", state.cap.label());

    // Build at full width first so we know the deficit.
    let parts = ["▲ ".to_string() + &agent, tier, title, age, cap];
    let full = parts.join(sep);
    let full_w = visible_width(&full);
    if width == 0 {
        return String::new();
    }
    if full_w as u16 <= width {
        return full;
    }

    // Over budget: shrink the most-variable fields, in order:
    //   1. task title
    //   2. agent name (after the "▲ ")
    //   3. tier
    //   4. age
    // We never shrink "cap: …" — it is fixed-form and load-bearing.
    let mut agent_buf = parts[0].clone(); // already includes leading "▲ "
    let mut tier_buf = parts[1].clone();
    let mut title_buf = parts[2].clone();
    let mut age_buf = parts[3].clone();
    let cap_buf = parts[4].clone();

    // Helper: assemble + measure.
    let assemble =
        |a: &str, t: &str, ti: &str, ag: &str, ca: &str| -> String { [a, t, ti, ag, ca].join(sep) };

    let fits = |s: &str| visible_width(s) as u16 <= width;

    // 1) Shrink task title down to a 6-char minimum (plus ellipsis).
    while !fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) && visible_width(&title_buf) > 7
    {
        title_buf = clip_one(&title_buf);
    }
    if fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) {
        return assemble(&agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf);
    }

    // 2) Shrink agent name (keep the leading "▲ " glyph + space = 2 cols).
    while !fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) && visible_width(&agent_buf) > 5
    {
        agent_buf = clip_one(&agent_buf);
    }
    if fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) {
        return assemble(&agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf);
    }

    // 3) Shrink tier to a 2-char minimum.
    while !fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) && visible_width(&tier_buf) > 2
    {
        tier_buf = clip_one(&tier_buf);
    }
    if fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) {
        return assemble(&agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf);
    }

    // 4) Shrink age to a 3-char minimum.
    while !fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) && visible_width(&age_buf) > 3
    {
        age_buf = clip_one(&age_buf);
    }
    if fits(&assemble(
        &agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf,
    )) {
        return assemble(&agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf);
    }

    // 5) Final hard clip on the whole line as a last resort.
    hard_clip(
        &assemble(&agent_buf, &tier_buf, &title_buf, &age_buf, &cap_buf),
        width,
    )
}

/// Format an age in seconds into a compact label, e.g. `2m 14s`, `45s`,
/// `1h 03m`. `None` renders as `—`.
pub fn format_age(secs: Option<u64>) -> String {
    let Some(s) = secs else { return "—".into() };
    if s < 60 {
        return format!("{s}s");
    }
    if s < 3600 {
        let m = s / 60;
        let r = s % 60;
        return format!("{m}m {r:02}s");
    }
    if s < 86_400 {
        let h = s / 3600;
        let m = (s % 3600) / 60;
        return format!("{h}h {m:02}m");
    }
    let d = s / 86_400;
    format!("{d}d+")
}

/// Visible-column width. For our character set (latin + box drawing +
/// occasional emoji-free unicode), `chars().count()` is a close enough
/// approximation. Wide-CJK input is out of scope.
fn visible_width(s: &str) -> usize {
    s.chars().count()
}

/// Trim one display column from a label, replacing the last char with `…`.
/// If the label already ends in `…`, drop the preceding char and re-add `…`.
fn clip_one(s: &str) -> String {
    let mut chars: Vec<char> = s.chars().collect();
    if chars.is_empty() {
        return String::new();
    }
    if chars.last() == Some(&'…') {
        chars.pop();
        if chars.is_empty() {
            return "…".into();
        }
        chars.pop();
        chars.push('…');
        return chars.into_iter().collect();
    }
    chars.pop();
    chars.push('…');
    chars.into_iter().collect()
}

/// Hard-clip a string to `width` columns with a trailing ellipsis.
fn hard_clip(s: &str, width: u16) -> String {
    let w = width as usize;
    if w == 0 {
        return String::new();
    }
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= w {
        return s.to_string();
    }
    if w == 1 {
        return "…".into();
    }
    let mut out: String = chars.into_iter().take(w - 1).collect();
    out.push('…');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_age_buckets() {
        assert_eq!(format_age(None), "—");
        assert_eq!(format_age(Some(0)), "0s");
        assert_eq!(format_age(Some(45)), "45s");
        assert_eq!(format_age(Some(134)), "2m 14s");
        assert_eq!(format_age(Some(3_600)), "1h 00m");
        assert_eq!(format_age(Some(3_780)), "1h 03m");
        assert_eq!(format_age(Some(86_400 * 2)), "2d+");
    }

    #[test]
    fn cap_state_labels() {
        assert_eq!(CapState::Ok.label(), "ok");
        assert_eq!(CapState::RateLimited.label(), "429");
        assert_eq!(CapState::Cooldown.label(), "cooldown");
        assert_eq!(CapState::Unknown.label(), "?");
    }

    #[test]
    fn idle_state_renders_em_idle_em() {
        let s = HeaderState {
            agent_name: "codex-zazrifka".into(),
            tier: "high".into(),
            task_title: None,
            last_activity_age_secs: None,
            cap: CapState::Ok,
        };
        let out = render(&s, 200);
        assert!(out.contains("— idle —"), "got: {out}");
        assert!(out.contains("cap: ok"), "got: {out}");
        assert!(out.contains("▲ codex-zazrifka"), "got: {out}");
    }

    #[test]
    fn working_state_renders_task_title() {
        let s = HeaderState {
            agent_name: "codex-zazrifka".into(),
            tier: "high".into(),
            task_title: Some("TE-2 src/edge module tree stubs".into()),
            last_activity_age_secs: Some(134),
            cap: CapState::Ok,
        };
        let out = render(&s, 200);
        assert!(out.contains("TE-2 src/edge module tree stubs"));
        assert!(out.contains("2m 14s"));
    }

    #[test]
    fn capped_state_renders_429() {
        let s = HeaderState {
            agent_name: "codex-pyrit".into(),
            tier: "medium".into(),
            task_title: None,
            last_activity_age_secs: Some(420),
            cap: CapState::RateLimited,
        };
        let out = render(&s, 200);
        assert!(out.contains("cap: 429"), "got: {out}");
    }

    #[test]
    fn width_60_clips_task_title_first() {
        let s = HeaderState {
            agent_name: "codex-zazrifka".into(),
            tier: "high".into(),
            task_title: Some(
                "TE-2 src/edge module tree stubs with a very long suffix to force truncation"
                    .into(),
            ),
            last_activity_age_secs: Some(134),
            cap: CapState::Ok,
        };
        let out = render(&s, 60);
        assert!(visible_width(&out) <= 60, "out too wide: {out:?}");
        assert!(out.contains("cap: ok"), "cap dropped: {out}");
        assert!(out.contains("▲ codex-zazrifka"), "agent dropped: {out}");
    }

    #[test]
    fn width_zero_yields_empty() {
        let s = HeaderState::default();
        assert_eq!(render(&s, 0), "");
    }
}
