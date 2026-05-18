// fleet-waves — Gantt-style spawn-timeline view of the active openspec plan.
//
// Layout (no in-binary tab strip per PR #30 — tmux's status bar owns nav):
//   rows 0..=2:  header card — caption "WAVES", big "Wn · status · NN% of
//                plan", right-aligned action pills (Re-spawn / Spawn next
//                wave). Pills are visual only — wiring needs a dispatcher
//                this binary doesn't have yet.
//   rows 3..=n:  gantt grid wrapped in a rounded IOS_HAIRLINE block, one row
//                per Kahn topological wave. Each row: wave label, status
//                chip, proportional cascade bar with the wave's first task
//                title, TASKS and AGENTS columns on the right.
//
// Data: fleet-data::plan (newest plan.json under openspec/plans/*). Waves
// come from a Kahn topological sort of `Subtask.depends_on`, provided by
// `fleet_data::toposort::waves`.
//
// Visual notes:
//   - Idle bars use IOS_CARD_BG (#2c2c30) — slightly above the background
//     so the row reads as a card, with IOS_FG text for readable contrast.
//     v1 used IOS_CHIP_BG (#36363a) + muted text and was hard to read on a
//     monitor.
//   - Done bars use IOS_GREEN with dark-on-bright bold text.
//   - Working bars draw a darker-tint base and overlay a brighter IOS_TINT
//     fill on the left for the wave's completed-task fraction; the bar is
//     bold-white throughout so the inner split is hue-only.
//   - Bar x-positions cascade by wave index. There is no per-wave timestamp
//     in plan.json today, so the mockup's "+Nm" duration axis is omitted
//     rather than rendered with a fake number.

use std::{
    collections::HashMap,
    io,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[cfg(test)]
use fleet_data::plan::Subtask;
use fleet_data::plan::{self, Plan};
use fleet_data::toposort::waves;
use fleet_ui::{
    chip::{status_chip, ChipKind, CHIP_WIDTH},
    palette::*,
    spotlight_overlay::{
        shared_spotlight_filter, Spotlight, SpotlightState, SHARED_SPOTLIGHT_ITEMS,
    },
};
use tuirealm::application::{Application, PollStrategy};
use tuirealm::command::{Cmd, CmdResult};
use tuirealm::component::{AppComponent, Component};
use tuirealm::event::{Event, Key, KeyEvent, NoUserEvent};
use tuirealm::listener::EventListenerCfg;
use tuirealm::props::{AttrValue, Attribute, Props, QueryResult};
use tuirealm::ratatui::layout::{Constraint, Direction, Layout, Rect};
use tuirealm::ratatui::style::{Color, Modifier, Style};
use tuirealm::ratatui::text::{Line, Span};
use tuirealm::ratatui::widgets::{Block, BorderType, Borders, Paragraph, Sparkline};
use tuirealm::ratatui::Frame;
use tuirealm::state::State;
use tuirealm::subscription::{EventClause, Sub, SubClause};
use tuirealm::terminal::{CrosstermTerminalAdapter, TerminalAdapter};

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Msg {
    Tick,
    Quit,
}

#[derive(Debug, Eq, PartialEq, Clone, Hash)]
pub enum Id {
    Waves,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Overlay {
    #[default]
    None,
    Spotlight,
}

struct App {
    plan: Option<Plan>,
    props: Props,
    tick: u64,
    timeline: Box<dyn TimelineFeed>,
    overlay: Overlay,
    spotlight: Spotlight<'static>,
    spotlight_state: SpotlightState,
}

impl Default for App {
    fn default() -> Self {
        let mut roots: Vec<PathBuf> = Vec::new();
        if let Ok(root) = std::env::var("FLEET_PLAN_REPO_ROOT") {
            roots.push(PathBuf::from(root));
        }
        if let Ok(root) = std::env::current_dir() {
            roots.push(root);
        }
        roots.push(PathBuf::from("/home/deadpool/Documents/codex-fleetui"));
        roots.push(PathBuf::from("/home/deadpool/Documents/recodee"));

        let plan = roots
            .into_iter()
            .find_map(|root| plan::newest_plan(&root).ok().flatten())
            .and_then(|p| plan::load(&p).ok());
        Self::with_timeline(plan, Box::<CommandTimelineFeed>::default())
    }
}

impl App {
    fn with_timeline(plan: Option<Plan>, timeline: Box<dyn TimelineFeed>) -> Self {
        Self {
            plan,
            props: Props::default(),
            tick: 0,
            timeline,
            overlay: Overlay::None,
            spotlight: Spotlight::new(SHARED_SPOTLIGHT_ITEMS.to_vec()),
            spotlight_state: SpotlightState::default(),
        }
    }

    fn open_spotlight(&mut self) {
        self.overlay = Overlay::Spotlight;
        self.spotlight_state.query.clear();
        self.spotlight_state.selected = 0;
    }

    fn close_spotlight(&mut self) {
        self.overlay = Overlay::None;
        self.spotlight_state.query.clear();
        self.spotlight_state.selected = 0;
    }
}

impl std::fmt::Debug for App {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("App")
            .field("plan", &self.plan)
            .field("tick", &self.tick)
            .finish()
    }
}

impl Component for App {
    fn view(&mut self, frame: &mut Frame, area: Rect) {
        render(frame, area, self);
    }

    fn query(&self, attr: Attribute) -> Option<QueryResult<'_>> {
        self.props.get(attr).map(|v| QueryResult::from(v.clone()))
    }

    fn attr(&mut self, attr: Attribute, value: AttrValue) {
        self.props.set(attr, value);
    }

    fn state(&self) -> State {
        State::None
    }

    fn perform(&mut self, _cmd: Cmd) -> CmdResult {
        CmdResult::NoChange
    }
}

impl AppComponent<Msg, NoUserEvent> for App {
    fn on(&mut self, ev: &Event<NoUserEvent>) -> Option<Msg> {
        match ev {
            Event::Keyboard(KeyEvent {
                code: Key::Char('q'),
                ..
            })
            | Event::Keyboard(KeyEvent { code: Key::Esc, .. })
                if self.overlay == Overlay::Spotlight =>
            {
                self.close_spotlight();
                Some(Msg::Tick)
            }
            Event::Keyboard(KeyEvent {
                code: Key::Enter, ..
            }) if self.overlay == Overlay::Spotlight => {
                self.close_spotlight();
                Some(Msg::Tick)
            }
            Event::Keyboard(KeyEvent {
                code: Key::Backspace,
                ..
            }) if self.overlay == Overlay::Spotlight => {
                self.spotlight_state.query.pop();
                self.spotlight_state.selected = 0;
                Some(Msg::Tick)
            }
            Event::Keyboard(KeyEvent { code: Key::Up, .. })
                if self.overlay == Overlay::Spotlight =>
            {
                self.spotlight_state.selected = self.spotlight_state.selected.saturating_sub(1);
                Some(Msg::Tick)
            }
            Event::Keyboard(KeyEvent {
                code: Key::Down, ..
            }) if self.overlay == Overlay::Spotlight => {
                let max = shared_spotlight_filter(&self.spotlight_state.query)
                    .len()
                    .saturating_sub(1);
                self.spotlight_state.selected = (self.spotlight_state.selected + 1).min(max);
                Some(Msg::Tick)
            }
            Event::Keyboard(KeyEvent {
                code: Key::Char(c), ..
            }) if self.overlay == Overlay::Spotlight && !c.is_control() => {
                self.spotlight_state.query.push(*c);
                self.spotlight_state.selected = 0;
                Some(Msg::Tick)
            }
            Event::Keyboard(KeyEvent {
                code: Key::Char('/'),
                ..
            })
            | Event::Keyboard(KeyEvent {
                code: Key::Char('?'),
                ..
            }) => {
                self.open_spotlight();
                Some(Msg::Tick)
            }
            Event::Keyboard(KeyEvent {
                code: Key::Char('q'),
                ..
            })
            | Event::Keyboard(KeyEvent { code: Key::Esc, .. }) => Some(Msg::Quit),
            Event::Tick => {
                self.tick = self.tick.wrapping_add(1);
                self.spotlight_state.tick = self.tick;
                Some(Msg::Tick)
            }
            _ => None,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum WaveStatus {
    Done,
    Working,
    Idle,
}

fn wave_status(indices: &[u32], plan: &Plan) -> WaveStatus {
    let statuses: Vec<&str> = indices
        .iter()
        .filter_map(|i| {
            plan.tasks
                .iter()
                .find(|t| t.subtask_index == *i)
                .map(|t| t.status.as_str())
        })
        .collect();
    if !statuses.is_empty() && statuses.iter().all(|s| *s == "completed") {
        WaveStatus::Done
    } else if statuses.iter().any(|s| *s == "claimed") {
        WaveStatus::Working
    } else {
        WaveStatus::Idle
    }
}

fn first_task_title<'a>(indices: &[u32], plan: &'a Plan) -> &'a str {
    indices
        .iter()
        .filter_map(|i| plan.tasks.iter().find(|t| t.subtask_index == *i))
        .next()
        .map(|t| t.title.as_str())
        .unwrap_or("—")
}

fn wave_progress(indices: &[u32], plan: &Plan) -> (u32, u32) {
    let mut done = 0u32;
    let mut total = 0u32;
    for i in indices {
        if let Some(t) = plan.tasks.iter().find(|t| t.subtask_index == *i) {
            total += 1;
            if t.status == "completed" {
                done += 1;
            }
        }
    }
    (done, total)
}

fn active_wave_index(waves_v: &[Vec<u32>], plan: &Plan) -> Option<usize> {
    waves_v
        .iter()
        .position(|indices| matches!(wave_status(indices, plan), WaveStatus::Working))
        .or_else(|| {
            waves_v
                .iter()
                .position(|indices| !matches!(wave_status(indices, plan), WaveStatus::Done))
        })
}

fn wave_bar_width(indices: &[u32], track_w: u16, max_tasks: u16) -> u16 {
    if track_w == 0 {
        return 0;
    }
    let min_w = track_w.min(10);
    let max_w = (((track_w as u32) * 72 + 50) / 100)
        .max(min_w as u32)
        .min(track_w as u32) as u16;
    if max_tasks == 0 || max_w <= min_w {
        return min_w;
    }
    let count = indices.len().max(1).min(max_tasks as usize) as u16;
    min_w + (((max_w - min_w) as u32 * count as u32) / max_tasks as u32) as u16
}

fn agents_in_wave(indices: &[u32], plan: &Plan) -> (Vec<char>, u32) {
    let mut seen: Vec<char> = Vec::new();
    let mut count = 0u32;
    for i in indices {
        if let Some(t) = plan.tasks.iter().find(|t| t.subtask_index == *i) {
            if let Some(agent) = t.claimed_by_agent.as_deref() {
                count += 1;
                if let Some(c) = agent.chars().next().map(|c| c.to_ascii_uppercase()) {
                    if !seen.contains(&c) && seen.len() < 2 {
                        seen.push(c);
                    }
                }
            }
        }
    }
    (seen, count)
}

fn active_wave_info(waves: &[Vec<u32>], plan: &Plan) -> (usize, &'static str, u32) {
    let total = plan.tasks.len() as u32;
    let done = plan
        .tasks
        .iter()
        .filter(|t| t.status == "completed")
        .count() as u32;
    let pct = if total == 0 { 0 } else { done * 100 / total };
    for (i, indices) in waves.iter().enumerate() {
        match wave_status(indices, plan) {
            WaveStatus::Done => continue,
            WaveStatus::Working => return (i + 1, "in flight", pct),
            WaveStatus::Idle => return (i + 1, "queued", pct),
        }
    }
    (waves.len().max(1), "done", pct)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TimelineAction {
    Claim,
    Complete,
    Blocked,
    Handoff,
}

impl TimelineAction {
    fn label(self) -> &'static str {
        match self {
            TimelineAction::Claim => "claimed",
            TimelineAction::Complete => "completed",
            TimelineAction::Blocked => "blocked",
            TimelineAction::Handoff => "handed off",
        }
    }

    fn color(self) -> Color {
        match self {
            TimelineAction::Claim => IOS_TINT,
            TimelineAction::Complete => IOS_GREEN,
            TimelineAction::Blocked => IOS_DESTRUCTIVE,
            TimelineAction::Handoff => IOS_FG_MUTED,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct TimelineEvent {
    minute: String,
    agent: String,
    action: TimelineAction,
    title: String,
}

trait TimelineFeed {
    fn events(&mut self, plan_slug: &str, plan: &Plan) -> Vec<TimelineEvent>;
}

#[derive(Default)]
struct CommandTimelineFeed {
    cache_slug: Option<String>,
    cache_at: Option<Instant>,
    cache_events: Vec<TimelineEvent>,
}

impl TimelineFeed for CommandTimelineFeed {
    fn events(&mut self, plan_slug: &str, plan: &Plan) -> Vec<TimelineEvent> {
        if self.cache_slug.as_deref() == Some(plan_slug)
            && self
                .cache_at
                .map(|t| t.elapsed() < Duration::from_secs(1))
                .unwrap_or(false)
        {
            return self.cache_events.clone();
        }

        let mut events = Command::new("colony")
            .args([
                "task",
                "timeline",
                "--plan-slug",
                plan_slug,
                "--limit",
                "12",
            ])
            .output()
            .ok()
            .filter(|out| out.status.success())
            .and_then(|out| String::from_utf8(out.stdout).ok())
            .map(|stdout| parse_timeline_output(&stdout, plan))
            .unwrap_or_default();

        if events.is_empty() {
            events = plan_fallback_events(plan);
        }

        events.truncate(12);
        self.cache_slug = Some(plan_slug.to_string());
        self.cache_at = Some(Instant::now());
        self.cache_events = events.clone();
        events
    }
}

fn parse_timeline_output(output: &str, plan: &Plan) -> Vec<TimelineEvent> {
    output
        .lines()
        .filter_map(|line| parse_timeline_line(line, plan))
        .take(12)
        .collect()
}

fn parse_timeline_line(line: &str, plan: &Plan) -> Option<TimelineEvent> {
    let lower = line.to_ascii_lowercase();
    let action = if lower.contains("handoff") || lower.contains("hand off") {
        TimelineAction::Handoff
    } else if lower.contains("blocked") || lower.contains("blocker") {
        TimelineAction::Blocked
    } else if lower.contains("completed") || lower.contains("complete") || lower.contains("done") {
        TimelineAction::Complete
    } else if lower.contains("claim") {
        TimelineAction::Claim
    } else {
        return None;
    };

    Some(TimelineEvent {
        minute: find_minute(line).unwrap_or_else(current_hh_mm),
        agent: find_agent(line).unwrap_or_else(|| "colony".to_string()),
        action,
        title: find_task_title(line, plan).unwrap_or_else(|| clip(line.trim(), 42)),
    })
}

fn plan_fallback_events(plan: &Plan) -> Vec<TimelineEvent> {
    plan.tasks
        .iter()
        .rev()
        .filter_map(|task| {
            let action = match task.status.as_str() {
                "claimed" => TimelineAction::Claim,
                "completed" => TimelineAction::Complete,
                "blocked" => TimelineAction::Blocked,
                _ => return None,
            };
            Some(TimelineEvent {
                minute: current_hh_mm(),
                agent: task
                    .claimed_by_agent
                    .clone()
                    .unwrap_or_else(|| "plan".to_string()),
                action,
                title: task.title.clone(),
            })
        })
        .take(12)
        .collect()
}

fn find_minute(line: &str) -> Option<String> {
    line.split(|c: char| c.is_whitespace() || c == '[' || c == ']')
        .find(|part| {
            part.len() >= 5
                && part.as_bytes().get(2) == Some(&b':')
                && part.chars().take(5).all(|c| c.is_ascii_digit() || c == ':')
        })
        .map(|part| part.chars().take(5).collect())
}

fn find_agent(line: &str) -> Option<String> {
    for key in ["agent=", "by=", "from=", "owner="] {
        if let Some(pos) = line.find(key) {
            return line[pos + key.len()..]
                .split_whitespace()
                .next()
                .map(clean_agent)
                .filter(|s| !s.is_empty());
        }
    }
    line.split_once("HANDOFF from ")
        .and_then(|(_, rest)| rest.split_whitespace().next())
        .map(clean_agent)
        .filter(|s| !s.is_empty())
}

fn clean_agent(raw: &str) -> String {
    raw.trim_matches(|c: char| !(c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '@' | '.')))
        .to_string()
}

fn find_task_title(line: &str, plan: &Plan) -> Option<String> {
    for task in &plan.tasks {
        let sub = format!("sub-{}", task.subtask_index);
        let subtask = format!("subtask_index={}", task.subtask_index);
        if line.contains(&sub) || line.contains(&subtask) || line.contains(&task.title) {
            return Some(task.title.clone());
        }
    }
    None
}

fn current_hh_mm() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let mins = (secs / 60) % (24 * 60);
    format!("{:02}:{:02}", mins / 60, mins % 60)
}

#[derive(Clone, Debug)]
struct AgentScore {
    agent: String,
    count: u64,
    sparkline: Vec<u64>,
}

fn leaderboard(plan: &Plan) -> Vec<AgentScore> {
    let mut completed: HashMap<String, u64> = HashMap::new();
    let mut claimed: HashMap<String, u64> = HashMap::new();
    let mut completed_bins: HashMap<String, Vec<u64>> = HashMap::new();
    let mut claimed_bins: HashMap<String, Vec<u64>> = HashMap::new();
    let total = plan.tasks.len().max(1);

    for (i, task) in plan.tasks.iter().enumerate() {
        let Some(agent) = task.claimed_by_agent.as_deref().filter(|s| !s.is_empty()) else {
            continue;
        };
        let bin = ((i * 12) / total).min(11);
        *claimed.entry(agent.to_string()).or_default() += 1;
        claimed_bins
            .entry(agent.to_string())
            .or_insert_with(|| vec![0; 12])[bin] += 1;
        if task.status == "completed" {
            *completed.entry(agent.to_string()).or_default() += 1;
            completed_bins
                .entry(agent.to_string())
                .or_insert_with(|| vec![0; 12])[bin] += 1;
        }
    }

    let (counts, bins) = if completed.is_empty() {
        (claimed, claimed_bins)
    } else {
        (completed, completed_bins)
    };

    let mut rows: Vec<AgentScore> = counts
        .into_iter()
        .map(|(agent, count)| AgentScore {
            sparkline: bins.get(&agent).cloned().unwrap_or_else(|| vec![0; 12]),
            agent,
            count,
        })
        .collect();
    rows.sort_by(|a, b| b.count.cmp(&a.count).then(a.agent.cmp(&b.agent)));
    rows.truncate(6);
    rows
}

fn clip(s: &str, max: u16) -> String {
    if max == 0 {
        return String::new();
    }
    let chars: Vec<char> = s.chars().collect();
    if (chars.len() as u16) <= max {
        return s.to_string();
    }
    if max <= 1 {
        return chars.into_iter().take(max as usize).collect();
    }
    let mut out: String = chars.into_iter().take((max - 1) as usize).collect();
    out.push('…');
    out
}

fn pad_visible(s: &str, width: u16) -> String {
    let cur = s.chars().count() as u16;
    if cur >= width {
        s.chars().take(width as usize).collect()
    } else {
        let mut out = s.to_string();
        for _ in cur..width {
            out.push(' ');
        }
        out
    }
}

fn right_aligned(s: &str, width: u16) -> String {
    let clipped = clip(s, width);
    let cur = clipped.chars().count() as u16;
    if cur >= width {
        clipped
    } else {
        let mut out = String::new();
        for _ in cur..width {
            out.push(' ');
        }
        out.push_str(&clipped);
        out
    }
}

// iOS-style pill: ◖ <label> ◗ with caps in the fill colour against IOS_BG.
fn pill_spans(label: &str, fill: Color, fg: Color) -> Vec<Span<'static>> {
    vec![
        Span::styled("◖", Style::default().fg(fill).bg(Color::Rgb(0, 0, 0))),
        Span::styled(
            label.to_string(),
            Style::default()
                .fg(fg)
                .bg(fill)
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled("◗", Style::default().fg(fill).bg(Color::Rgb(0, 0, 0))),
    ]
}

fn pill_visible_width(label: &str) -> u16 {
    (label.chars().count() as u16) + 2
}

fn render_header(frame: &mut Frame, area: Rect, plan: Option<&Plan>, waves_v: &[Vec<u32>]) {
    let (wave_n, status_word, pct) = match plan {
        Some(p) => active_wave_info(waves_v, p),
        None => (0, "no plan", 0),
    };

    // Row 0: "WAVES" caption — uppercase, muted, with a leading systemBlue tick.
    let cap_row = Rect {
        x: area.x + 1,
        y: area.y,
        width: area.width.saturating_sub(2),
        height: 1,
    };
    let cap_spans = vec![
        Span::styled("· ", Style::default().fg(IOS_TINT)),
        Span::styled(
            "WAVES",
            Style::default()
                .fg(IOS_FG_MUTED)
                .add_modifier(Modifier::BOLD),
        ),
    ];
    frame.render_widget(Paragraph::new(Line::from(cap_spans)), cap_row);

    // Row 1: big title + right-aligned action pills.
    let title_row = Rect {
        x: area.x + 1,
        y: area.y + 1,
        width: area.width.saturating_sub(2),
        height: 1,
    };
    let title = if plan.is_some() && wave_n > 0 {
        format!("W{} · {} · {}% of plan", wave_n, status_word, pct)
    } else {
        "no plan loaded".to_string()
    };
    frame.render_widget(
        Paragraph::new(Span::styled(
            title,
            Style::default().fg(IOS_FG).add_modifier(Modifier::BOLD),
        )),
        title_row,
    );

    let respawn = pill_spans(" ↻ Re-spawn ", IOS_CHIP_BG, IOS_FG);
    let spawn_next = pill_spans(" ▶ Spawn next wave ", IOS_TINT, IOS_FG);
    let pills_width =
        pill_visible_width(" ↻ Re-spawn ") + 1 + pill_visible_width(" ▶ Spawn next wave ");
    if title_row.width > pills_width {
        let pills_x = title_row.x + title_row.width - pills_width;
        let pills_area = Rect {
            x: pills_x,
            y: title_row.y,
            width: pills_width,
            height: 1,
        };
        let mut spans: Vec<Span<'static>> = Vec::new();
        spans.extend(respawn);
        spans.push(Span::raw(" "));
        spans.extend(spawn_next);
        frame.render_widget(Paragraph::new(Line::from(spans)), pills_area);
    }
}

fn render_timeline_header(
    frame: &mut Frame,
    track_area: Rect,
    tasks_area: Rect,
    agents_area: Rect,
) {
    if track_area.width > 0 {
        let mut chars = vec!['─'; track_area.width as usize];
        for pct in [0u16, 25, 50, 75, 100] {
            let x = if track_area.width == 1 {
                0
            } else {
                ((track_area.width - 1) as u32 * pct as u32 / 100) as usize
            };
            chars[x] = '┬';
        }
        let ticks: String = chars.into_iter().collect();
        frame.render_widget(
            Paragraph::new(Span::styled(
                ticks,
                Style::default().fg(IOS_HAIRLINE_STRONG),
            )),
            track_area,
        );
    }
    frame.render_widget(
        Paragraph::new(Span::styled(
            right_aligned("TASKS", tasks_area.width),
            Style::default()
                .fg(IOS_FG_MUTED)
                .add_modifier(Modifier::BOLD),
        )),
        tasks_area,
    );
    frame.render_widget(
        Paragraph::new(Span::styled(
            right_aligned("AGENTS", agents_area.width),
            Style::default()
                .fg(IOS_FG_MUTED)
                .add_modifier(Modifier::BOLD),
        )),
        agents_area,
    );
}

fn render_gantt(frame: &mut Frame, area: Rect, plan: &Plan, waves_v: &[Vec<u32>], tick: u64) {
    if area.height == 0 || waves_v.is_empty() {
        return;
    }

    // Outer card — rounded hairline border, matches the mockup's enclosing frame.
    let outer = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(IOS_HAIRLINE));
    let inner = outer.inner(area);
    frame.render_widget(outer, area);

    // Per-row column budget inside the card:
    //   [W-label 4] [chip CHIP_WIDTH] [gap 2] [bar track variable]
    //   [gap 2] [TASKS 9] [gap 2] [AGENTS 8]
    const LABEL_W: u16 = 4;
    const GAP: u16 = 2;
    const TASKS_W: u16 = 9;
    const AGENTS_W: u16 = 8;
    let fixed = LABEL_W + CHIP_WIDTH + GAP + GAP + TASKS_W + GAP + AGENTS_W;
    if inner.width <= fixed + 4 || inner.height < 2 {
        return;
    }
    let track_x = inner.x + LABEL_W + CHIP_WIDTH + GAP;
    let agents_x = inner.x + inner.width - AGENTS_W;
    let tasks_x = agents_x.saturating_sub(GAP + TASKS_W);
    let track_w = tasks_x.saturating_sub(track_x + GAP);
    if track_w == 0 {
        return;
    }

    let total = waves_v.len();
    let max_tasks = waves_v
        .iter()
        .map(|indices| indices.len() as u16)
        .max()
        .unwrap_or(1);
    let active = active_wave_index(waves_v, plan);

    render_timeline_header(
        frame,
        Rect {
            x: track_x,
            y: inner.y,
            width: track_w,
            height: 1,
        },
        Rect {
            x: tasks_x,
            y: inner.y,
            width: TASKS_W,
            height: 1,
        },
        Rect {
            x: agents_x,
            y: inner.y,
            width: AGENTS_W,
            height: 1,
        },
    );

    for (i, indices) in waves_v.iter().enumerate() {
        let y = inner.y + 1 + i as u16;
        if y >= inner.y + inner.height {
            break;
        }

        let label_area = Rect {
            x: inner.x,
            y,
            width: LABEL_W,
            height: 1,
        };
        let chip_area = Rect {
            x: inner.x + LABEL_W,
            y,
            width: CHIP_WIDTH,
            height: 1,
        };
        let tasks_area = Rect {
            x: tasks_x,
            y,
            width: TASKS_W,
            height: 1,
        };
        let agents_area = Rect {
            x: agents_x,
            y,
            width: AGENTS_W,
            height: 1,
        };

        // W-label — bright white bold so the row anchor reads at a glance.
        frame.render_widget(
            Paragraph::new(Span::styled(
                format!("W{}", i + 1),
                Style::default().fg(IOS_FG).add_modifier(Modifier::BOLD),
            )),
            label_area,
        );

        let ws = wave_status(indices, plan);
        let kind = match ws {
            WaveStatus::Done => ChipKind::Done,
            WaveStatus::Working => ChipKind::Working,
            WaveStatus::Idle => ChipKind::Idle,
        };
        frame.render_widget(Paragraph::new(Line::from(status_chip(kind))), chip_area);

        let bar_w = wave_bar_width(indices, track_w, max_tasks);
        let max_offset = track_w.saturating_sub(bar_w);
        let step = if total > 1 {
            (max_offset as f32) / ((total - 1) as f32)
        } else {
            0.0
        };
        let offset = (step * i as f32).round() as u16;
        let bar_x = track_x + offset.min(max_offset);
        let bar_area = Rect {
            x: bar_x,
            y,
            width: bar_w,
            height: 1,
        };
        render_wave_bar(
            frame,
            bar_area,
            indices,
            plan,
            ws,
            active == Some(i),
            tick + i as u64,
        );

        let (done, total_tasks) = wave_progress(indices, plan);
        let task_style = if total_tasks > 0 && done == total_tasks {
            Style::default().fg(IOS_GREEN).add_modifier(Modifier::BOLD)
        } else if matches!(ws, WaveStatus::Working) {
            Style::default().fg(IOS_TINT).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(IOS_FG_MUTED)
        };
        frame.render_widget(
            Paragraph::new(Span::styled(
                right_aligned(&format!("{done}/{total_tasks}"), tasks_area.width),
                task_style,
            )),
            tasks_area,
        );

        let (initials, count) = agents_in_wave(indices, plan);
        let agent_label = if count == 0 {
            "—".to_string()
        } else {
            let letters: String = initials.iter().collect();
            format!(
                "{} {}",
                if letters.is_empty() {
                    "?".to_string()
                } else {
                    letters
                },
                count
            )
        };
        let agent_style = if count == 0 {
            Style::default().fg(IOS_FG_FAINT)
        } else {
            Style::default().fg(IOS_TINT).add_modifier(Modifier::BOLD)
        };
        frame.render_widget(
            Paragraph::new(Span::styled(
                right_aligned(&agent_label, agents_area.width),
                agent_style,
            )),
            agents_area,
        );
    }
}

fn render_wave_bar(
    frame: &mut Frame,
    bar_area: Rect,
    indices: &[u32],
    plan: &Plan,
    ws: WaveStatus,
    active: bool,
    shimmer_phase: u64,
) {
    let title = first_task_title(indices, plan);
    let inner_w = bar_area.width.saturating_sub(2);
    let clipped = clip(title, inner_w);
    let padded = format!(" {} ", clipped);
    let base_text = pad_visible(&padded, bar_area.width);

    // Base bar colours — readable text on each surface, BOLD for the
    // active states (Done / Working) so they read as foreground items
    // against the muted Idle rows.
    let (bg, fg, bold) = match ws {
        WaveStatus::Done => (IOS_GREEN, Color::Rgb(12, 12, 14), true),
        WaveStatus::Working => (IOS_TINT_DARK, IOS_FG, true),
        WaveStatus::Idle => (IOS_CARD_BG, IOS_FG, false),
    };
    let mut style = Style::default().fg(fg).bg(bg);
    if bold {
        style = style.add_modifier(Modifier::BOLD);
    }
    frame.render_widget(
        Paragraph::new(Span::styled(base_text.clone(), style)),
        bar_area,
    );

    // Working wave: overlay a brighter IOS_TINT fill on the left portion
    // showing the wave's completed-task fraction. Two-pass render — second
    // pass overwrites the first within fill_area.
    if matches!(ws, WaveStatus::Working) {
        let (done, total) = wave_progress(indices, plan);
        let pct = if total == 0 {
            0.0
        } else {
            done as f32 / total as f32
        };
        let fill_w = ((bar_area.width as f32) * pct).round() as u16;
        if fill_w > 0 {
            let fill_area = Rect {
                x: bar_area.x,
                y: bar_area.y,
                width: fill_w,
                height: 1,
            };
            let fill_text = pad_visible(&clip(&padded, fill_w), fill_w);
            frame.render_widget(
                Paragraph::new(Span::styled(
                    fill_text,
                    Style::default()
                        .fg(IOS_FG)
                        .bg(IOS_TINT)
                        .add_modifier(Modifier::BOLD),
                )),
                fill_area,
            );
        }
    }

    if active && matches!(ws, WaveStatus::Working) && bar_area.width > 4 {
        let sweep_w = 3.min(bar_area.width);
        let travel = bar_area.width.saturating_sub(sweep_w).max(1);
        let sweep_x = (shimmer_phase as u16 % travel).min(travel);
        let sweep_text: String = base_text
            .chars()
            .skip(sweep_x as usize)
            .take(sweep_w as usize)
            .collect();
        frame.render_widget(
            Paragraph::new(Span::styled(
                pad_visible(&sweep_text, sweep_w),
                Style::default()
                    .fg(IOS_FG)
                    .bg(IOS_TINT)
                    .add_modifier(Modifier::BOLD),
            )),
            Rect {
                x: bar_area.x + sweep_x,
                y: bar_area.y,
                width: sweep_w,
                height: 1,
            },
        );
    }
}

fn ios_subcard<'a>(title: &'a str) -> Block<'a> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(IOS_HAIRLINE))
        .style(Style::default().fg(IOS_FG).bg(IOS_CARD_BG))
        .title(Span::styled(
            format!(" {} ", title),
            Style::default()
                .fg(IOS_FG)
                .bg(IOS_CARD_BG)
                .add_modifier(Modifier::BOLD),
        ))
}

fn agent_chip(agent: &str, width: u16) -> Span<'static> {
    let body = clip(agent, width.saturating_sub(2));
    Span::styled(
        pad_visible(&format!(" {} ", body), width),
        Style::default()
            .fg(IOS_FG)
            .bg(IOS_CHIP_BG)
            .add_modifier(Modifier::BOLD),
    )
}

fn render_live_feed(frame: &mut Frame, area: Rect, events: &[TimelineEvent]) {
    if area.width < 24 || area.height < 3 {
        return;
    }
    let block = ios_subcard("LIVE FEED");
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.width == 0 || inner.height == 0 {
        return;
    }

    if events.is_empty() {
        frame.render_widget(
            Paragraph::new(Line::from(vec![
                Span::styled(
                    format!("{} · ", current_hh_mm()),
                    Style::default().fg(IOS_FG_FAINT),
                ),
                agent_chip("colony", 10),
                Span::styled(
                    " waiting for task_timeline",
                    Style::default().fg(IOS_FG_MUTED),
                ),
            ])),
            Rect {
                x: inner.x,
                y: inner.y,
                width: inner.width,
                height: 1,
            },
        );
        return;
    }

    let chip_w = inner.width.min(13).max(8);
    for (row, event) in events.iter().take(inner.height as usize).enumerate() {
        let y = inner.y + row as u16;
        let fixed = 8 + chip_w + event.action.label().chars().count() as u16 + 10;
        let title_w = inner.width.saturating_sub(fixed);
        let title = clip(&event.title, title_w);
        let mut spans = vec![
            Span::styled(
                format!("{} · ", event.minute),
                Style::default().fg(IOS_FG_FAINT),
            ),
            agent_chip(&event.agent, chip_w),
            Span::raw(" "),
            Span::styled(
                event.action.label(),
                Style::default().fg(event.action.color()),
            ),
            Span::styled(" sub-task ", Style::default().fg(IOS_FG_MUTED)),
            Span::styled(title, Style::default().fg(IOS_FG)),
        ];
        if row == inner.height.saturating_sub(1) as usize && events.len() > inner.height as usize {
            spans = vec![Span::styled(
                format!(
                    "… {} newer events hidden by pane height",
                    events.len() - row
                ),
                Style::default().fg(IOS_FG_FAINT),
            )];
        }
        frame.render_widget(
            Paragraph::new(Line::from(spans)),
            Rect {
                x: inner.x,
                y,
                width: inner.width,
                height: 1,
            },
        );
    }
}

fn render_leaderboard(frame: &mut Frame, area: Rect, plan: &Plan) {
    if area.width < 24 || area.height < 3 {
        return;
    }
    let block = ios_subcard("AGENT LEADERBOARD");
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.width == 0 || inner.height == 0 {
        return;
    }

    let scores = leaderboard(plan);
    if scores.is_empty() {
        frame.render_widget(
            Paragraph::new(Span::styled(
                "  no claimed or completed sub-tasks yet",
                Style::default().fg(IOS_FG_MUTED),
            )),
            Rect {
                x: inner.x,
                y: inner.y,
                width: inner.width,
                height: 1,
            },
        );
        return;
    }

    for (row, score) in scores.iter().take(inner.height as usize).enumerate() {
        let y = inner.y + row as u16;
        let rank_w = 4;
        let count_w = 6;
        let spark_w = inner.width.saturating_sub(rank_w + count_w + 14).min(18);
        let agent_w = inner.width.saturating_sub(rank_w + count_w + spark_w + 2);

        frame.render_widget(
            Paragraph::new(Span::styled(
                format!("#{}", row + 1),
                Style::default()
                    .fg(IOS_FG_FAINT)
                    .add_modifier(Modifier::BOLD),
            )),
            Rect {
                x: inner.x,
                y,
                width: rank_w,
                height: 1,
            },
        );
        frame.render_widget(
            Paragraph::new(Span::styled(
                clip(&score.agent, agent_w),
                Style::default().fg(IOS_FG).add_modifier(Modifier::BOLD),
            )),
            Rect {
                x: inner.x + rank_w,
                y,
                width: agent_w,
                height: 1,
            },
        );
        frame.render_widget(
            Paragraph::new(Span::styled(
                format!("{:>2} done", score.count),
                Style::default().fg(IOS_GREEN),
            )),
            Rect {
                x: inner.x + rank_w + agent_w,
                y,
                width: count_w + 2,
                height: 1,
            },
        );
        if spark_w > 0 {
            frame.render_widget(
                Sparkline::default()
                    .data(&score.sparkline)
                    .style(Style::default().fg(IOS_TINT).bg(IOS_CARD_BG)),
                Rect {
                    x: inner.x + inner.width - spark_w,
                    y,
                    width: spark_w,
                    height: 1,
                },
            );
        }
    }
}

fn render_live_region(frame: &mut Frame, area: Rect, plan: &Plan, events: &[TimelineEvent]) {
    if area.height == 0 {
        return;
    }
    let gap = if area.width >= 72 { 1 } else { 0 };
    let cols = if area.width >= 72 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage(55),
                Constraint::Length(gap),
                Constraint::Percentage(45),
            ])
            .split(area)
    } else {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Percentage(55), Constraint::Percentage(45)])
            .split(area)
    };
    render_live_feed(frame, cols[0], events);
    let leaderboard_area = if area.width >= 72 { cols[2] } else { cols[1] };
    render_leaderboard(frame, leaderboard_area, plan);
}

fn render_footer(frame: &mut Frame, area: Rect, plan: Option<&Plan>) {
    if area.height == 0 {
        return;
    }
    let text = match plan {
        Some(plan) => format!(" q quit · live feed cache 1s · {}", plan.plan_slug),
        None => " q quit · no active plan".to_string(),
    };
    frame.render_widget(
        Paragraph::new(Span::styled(
            clip(&text, area.width),
            Style::default().fg(IOS_FG_FAINT),
        )),
        area,
    );
}

fn gantt_height(area: Rect, waves_v: &[Vec<u32>]) -> u16 {
    let desired = (waves_v.len() as u16).saturating_add(2).max(4);
    let max_fixed = area.height.saturating_sub(5);
    desired.min(max_fixed)
}

fn render(frame: &mut Frame, area: Rect, app: &mut App) {
    if area.width < 40 || area.height < 6 {
        return;
    }
    frame.render_widget(
        Block::default().style(Style::default().bg(IOS_BG_GLASS)),
        area,
    );

    let waves_v: Vec<Vec<u32>> = match app.plan.as_ref() {
        Some(p) => waves(&p.tasks),
        None => Vec::new(),
    };
    let gantt_h = gantt_height(area, &waves_v);
    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4), // header: caption + title + breathing room
            Constraint::Length(gantt_h),
            Constraint::Min(0), // live feed + leaderboard absorb slack
            Constraint::Length(1),
        ])
        .split(area);

    render_header(frame, rows[0], app.plan.as_ref(), &waves_v);

    if app.plan.is_some() {
        let plan = app.plan.as_ref().unwrap();
        render_gantt(frame, rows[1], plan, &waves_v, app.tick);
    } else {
        frame.render_widget(
            Paragraph::new(Span::styled(
                "  no plan.json under openspec/plans/*/plan.json",
                Style::default().fg(IOS_FG_FAINT),
            )),
            rows[1],
        );
    }

    if app.plan.is_some() {
        let plan = app.plan.clone().unwrap();
        let events = app.timeline.events(&plan.plan_slug, &plan);
        render_live_region(frame, rows[2], &plan, &events);
    }

    render_footer(frame, rows[3], app.plan.as_ref());

    if app.overlay == Overlay::Spotlight {
        app.spotlight.render(frame, area, &app.spotlight_state);
    }
}

// ---------- Model (tuirealm M-V-U) ----------

struct Model<T: TerminalAdapter> {
    app: Application<Id, Msg, NoUserEvent>,
    terminal: T,
    quit: bool,
    redraw: bool,
}

impl Model<CrosstermTerminalAdapter> {
    fn new() -> io::Result<Self> {
        let app = Self::init_app().map_err(|e| io::Error::other(format!("init app: {e:?}")))?;
        let terminal =
            Self::init_adapter().map_err(|e| io::Error::other(format!("init adapter: {e:?}")))?;
        Ok(Self {
            app,
            terminal,
            quit: false,
            redraw: true,
        })
    }

    fn init_app() -> Result<Application<Id, Msg, NoUserEvent>, Box<dyn std::error::Error>> {
        let mut app: Application<Id, Msg, NoUserEvent> = Application::init(
            EventListenerCfg::default()
                .crossterm_input_listener(Duration::from_millis(100), 3)
                .tick_interval(Duration::from_millis(500)),
        );
        app.mount(
            Id::Waves,
            Box::new(App::default()),
            vec![Sub::new(EventClause::Tick, SubClause::Always)],
        )?;
        app.active(&Id::Waves)?;
        Ok(app)
    }

    fn init_adapter() -> Result<CrosstermTerminalAdapter, Box<dyn std::error::Error>> {
        let mut adapter = CrosstermTerminalAdapter::new()?;
        adapter.enable_raw_mode()?;
        adapter.enter_alternate_screen()?;
        Ok(adapter)
    }
}

impl<T: TerminalAdapter> Model<T> {
    fn view(&mut self) {
        let _ = self.terminal.draw(|frame| {
            let area = frame.area();
            let _ = self.app.view(&Id::Waves, frame, area);
        });
    }

    fn update(&mut self, msg: Msg) {
        self.redraw = true;
        match msg {
            Msg::Quit => self.quit = true,
            Msg::Tick => {}
        }
    }
}

fn main() -> io::Result<()> {
    let mut model = Model::<CrosstermTerminalAdapter>::new()?;
    let result = (|| -> io::Result<()> {
        while !model.quit {
            if let Ok(messages) = model
                .app
                .tick(PollStrategy::Once(Duration::from_millis(100)))
            {
                for msg in messages {
                    model.update(msg);
                }
            }
            if model.redraw {
                model.view();
                model.redraw = false;
            }
        }
        Ok(())
    })();
    let _ = model.terminal.disable_raw_mode();
    let _ = model.terminal.leave_alternate_screen();
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use tuirealm::ratatui::{backend::TestBackend, Terminal};

    fn lively_plan() -> Plan {
        let mut tasks = Vec::new();
        for i in 0..9 {
            let status = match i {
                0 | 1 | 2 => "completed",
                3 | 4 => "claimed",
                5 => "blocked",
                _ => "available",
            };
            tasks.push(Subtask {
                subtask_index: i,
                title: format!("Lane {} with deliberately long title for clipping", i),
                description: "demo".into(),
                file_scope: vec![],
                depends_on: if i == 0 { vec![] } else { vec![i - 1] },
                capability_hint: None,
                spec_row_id: None,
                status: status.into(),
                claimed_by_session_id: None,
                claimed_by_agent: match i % 3 {
                    0 => Some("codex-alpha".into()),
                    1 => Some("codex-beta".into()),
                    _ => Some("claude".into()),
                },
                completed_summary: None,
            });
        }
        Plan {
            schema_version: 1,
            plan_slug: "codex-fleet-waves-review-lively-2026-05-15".into(),
            title: "Lively Waves".into(),
            problem: "demo".into(),
            acceptance_criteria: vec![],
            roles: vec![],
            created_at: None,
            updated_at: None,
            published: None,
            tasks,
        }
    }

    struct StubFeed {
        events: Vec<TimelineEvent>,
    }

    impl TimelineFeed for StubFeed {
        fn events(&mut self, _plan_slug: &str, _plan: &Plan) -> Vec<TimelineEvent> {
            self.events.clone()
        }
    }

    fn overflow_events() -> Vec<TimelineEvent> {
        (0..50)
            .map(|i| TimelineEvent {
                minute: format!("12:{:02}", i),
                agent: if i % 2 == 0 { "codex-alpha" } else { "claude" }.into(),
                action: match i % 4 {
                    0 => TimelineAction::Claim,
                    1 => TimelineAction::Complete,
                    2 => TimelineAction::Blocked,
                    _ => TimelineAction::Handoff,
                },
                title: format!("Lane {} with deliberately long title for clipping", i),
            })
            .collect()
    }

    #[test]
    fn live_region_render_snapshot_covers_empty_partial_and_overflow() {
        let plan = lively_plan();
        let mut app = App::with_timeline(
            Some(plan),
            Box::new(StubFeed {
                events: overflow_events(),
            }),
        );
        app.tick = 7;
        let mut terminal = Terminal::new(TestBackend::new(100, 60)).unwrap();
        terminal
            .draw(|frame| render(frame, frame.area(), &mut app))
            .unwrap();
        let rendered = format!("{}", terminal.backend());
        insta::assert_snapshot!(rendered, @r###"
" · WAVES                                                                                            "
" W4 · in flight · 33% of plan                                  ◖ ↻ Re-spawn ◗ ◖ ▶ Spawn next wave ◗ "
"                                                                                                    "
"                                                                                                    "
"╭──────────────────────────────────────────────────────────────────────────────────────────────────╮"
"│                   ┬─────────────┬─────────────┬─────────────┬──────────────┬      TASKS    AGENTS│"
"│W1  ◖ ● done    ◗   Lane 0 with deliberately long title for…                         1/1       C 1│"
"│W2  ◖ ● done    ◗     Lane 1 with deliberately long title for…                       1/1       C 1│"
"│W3  ◖ ● done    ◗       Lane 2 with deliberately long title for…                     1/1       C 1│"
"│W4  ◖ ● working ◗         Lane 3 with deliberately long title for…                   0/1       C 1│"
"│W5  ◖ ● working ◗           Lane 4 with deliberately long title for…                 0/1       C 1│"
"│W6  ◖ ◌ idle    ◗             Lane 5 with deliberately long title for…               0/1       C 1│"
"│W7  ◖ ◌ idle    ◗               Lane 6 with deliberately long title for…             0/1       C 1│"
"│W8  ◖ ◌ idle    ◗                 Lane 7 with deliberately long title for…           0/1       C 1│"
"╰──────────────────────────────────────────────────────────────────────────────────────────────────╯"
"╭ LIVE FEED ─────────────────────────────────────────╮ ╭ AGENT LEADERBOARD ────────────────────────╮"
"│12:00 ·  codex-alpha  claimed sub-task Lane 0 with d│ │#1  claude        1 done   █               │"
"│12:01 ·  claude       completed sub-task Lane 1 with│ │#2  codex-alpha   1 done █                 │"
"│12:02 ·  codex-alpha  blocked sub-task Lane 2 with d│ │#3  codex-beta    1 done  █                │"
"│12:03 ·  claude       handed off sub-task Lane 3 wit│ │                                           │"
"│12:04 ·  codex-alpha  claimed sub-task Lane 4 with d│ │                                           │"
"│12:05 ·  claude       completed sub-task Lane 5 with│ │                                           │"
"│12:06 ·  codex-alpha  blocked sub-task Lane 6 with d│ │                                           │"
"│12:07 ·  claude       handed off sub-task Lane 7 wit│ │                                           │"
"│12:08 ·  codex-alpha  claimed sub-task Lane 8 with d│ │                                           │"
"│12:09 ·  claude       completed sub-task Lane 9 with│ │                                           │"
"│12:10 ·  codex-alpha  blocked sub-task Lane 10 with │ │                                           │"
"│12:11 ·  claude       handed off sub-task Lane 11 wi│ │                                           │"
"│12:12 ·  codex-alpha  claimed sub-task Lane 12 with │ │                                           │"
"│12:13 ·  claude       completed sub-task Lane 13 wit│ │                                           │"
"│12:14 ·  codex-alpha  blocked sub-task Lane 14 with │ │                                           │"
"│12:15 ·  claude       handed off sub-task Lane 15 wi│ │                                           │"
"│12:16 ·  codex-alpha  claimed sub-task Lane 16 with │ │                                           │"
"│12:17 ·  claude       completed sub-task Lane 17 wit│ │                                           │"
"│12:18 ·  codex-alpha  blocked sub-task Lane 18 with │ │                                           │"
"│12:19 ·  claude       handed off sub-task Lane 19 wi│ │                                           │"
"│12:20 ·  codex-alpha  claimed sub-task Lane 20 with │ │                                           │"
"│12:21 ·  claude       completed sub-task Lane 21 wit│ │                                           │"
"│12:22 ·  codex-alpha  blocked sub-task Lane 22 with │ │                                           │"
"│12:23 ·  claude       handed off sub-task Lane 23 wi│ │                                           │"
"│12:24 ·  codex-alpha  claimed sub-task Lane 24 with │ │                                           │"
"│12:25 ·  claude       completed sub-task Lane 25 wit│ │                                           │"
"│12:26 ·  codex-alpha  blocked sub-task Lane 26 with │ │                                           │"
"│12:27 ·  claude       handed off sub-task Lane 27 wi│ │                                           │"
"│12:28 ·  codex-alpha  claimed sub-task Lane 28 with │ │                                           │"
"│12:29 ·  claude       completed sub-task Lane 29 wit│ │                                           │"
"│12:30 ·  codex-alpha  blocked sub-task Lane 30 with │ │                                           │"
"│12:31 ·  claude       handed off sub-task Lane 31 wi│ │                                           │"
"│12:32 ·  codex-alpha  claimed sub-task Lane 32 with │ │                                           │"
"│12:33 ·  claude       completed sub-task Lane 33 wit│ │                                           │"
"│12:34 ·  codex-alpha  blocked sub-task Lane 34 with │ │                                           │"
"│12:35 ·  claude       handed off sub-task Lane 35 wi│ │                                           │"
"│12:36 ·  codex-alpha  claimed sub-task Lane 36 with │ │                                           │"
"│12:37 ·  claude       completed sub-task Lane 37 wit│ │                                           │"
"│12:38 ·  codex-alpha  blocked sub-task Lane 38 with │ │                                           │"
"│12:39 ·  claude       handed off sub-task Lane 39 wi│ │                                           │"
"│12:40 ·  codex-alpha  claimed sub-task Lane 40 with │ │                                           │"
"│… 9 newer events hidden by pane height              │ │                                           │"
"╰────────────────────────────────────────────────────╯ ╰───────────────────────────────────────────╯"
" q quit · live feed cache 1s · codex-fleet-waves-review-lively-2026-05-15                           "
"###);
    }

    #[test]
    fn spotlight_catalogue_matches_fleet_dashboard_order() {
        let hits = shared_spotlight_filter("");
        assert_eq!(hits.len(), SHARED_SPOTLIGHT_ITEMS.len());
        assert_eq!(hits.first().unwrap().title, "Horizontal split");
        assert_eq!(hits.last().unwrap().title, "Switch worktree…");
    }

    #[test]
    fn spotlight_open_and_close_reset_state() {
        let mut app = App::with_timeline(None, Box::new(StubFeed { events: vec![] }));

        app.spotlight_state.query = "zoom".into();
        app.spotlight_state.selected = 2;
        app.open_spotlight();
        assert_eq!(app.overlay, Overlay::Spotlight);
        assert!(app.spotlight_state.query.is_empty());
        assert_eq!(app.spotlight_state.selected, 0);

        app.spotlight_state.query = "split".into();
        app.spotlight_state.selected = 1;
        app.close_spotlight();
        assert_eq!(app.overlay, Overlay::None);
        assert!(app.spotlight_state.query.is_empty());
        assert_eq!(app.spotlight_state.selected, 0);
    }

    #[test]
    fn active_wave_prefers_claimed_over_next_idle() {
        let plan = lively_plan();
        let waves_v = waves(&plan.tasks);
        assert_eq!(active_wave_index(&waves_v, &plan), Some(3));
    }

    #[test]
    fn wave_bar_width_scales_with_task_count() {
        let narrow = vec![0];
        let wide = vec![0, 1, 2, 3];
        assert!(wave_bar_width(&wide, 80, 4) > wave_bar_width(&narrow, 80, 4));
        assert!(wave_bar_width(&wide, 80, 4) <= 80);
    }
}
