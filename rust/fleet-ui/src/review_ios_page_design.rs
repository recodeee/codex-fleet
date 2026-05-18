//! iOS-styled auto-review approval queue page.
//!
//! This module is intentionally standalone for the review-page design pass:
//! downstream pages can path-include or export it later without changing the
//! existing fleet-ui review surfaces during this lane.

use crate::palette::*;
use ratatui::{
    buffer::Buffer,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Paragraph, Widget, Wrap},
};

const IOS_BLUE: Color = Color::Rgb(0x00, 0x7a, 0xff);
const IOS_GREEN_STRICT: Color = Color::Rgb(0x34, 0xc7, 0x59);
const IOS_ORANGE_STRICT: Color = Color::Rgb(0xff, 0x95, 0x00);
const IOS_RED_STRICT: Color = Color::Rgb(0xff, 0x3b, 0x30);
const CARD_BG: Color = Color::Rgb(0x24, 0x24, 0x28);
const PANEL_BG: Color = Color::Rgb(0x1f, 0x1f, 0x23);
const BLUE_SOFT: Color = Color::Rgb(0x0d, 0x24, 0x3d);
const GREEN_SOFT: Color = Color::Rgb(0x0f, 0x2f, 0x1e);
const ORANGE_SOFT: Color = Color::Rgb(0x34, 0x25, 0x0f);
const RED_SOFT: Color = Color::Rgb(0x35, 0x14, 0x12);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ReviewRisk {
    Low,
    Medium,
    High,
}

impl ReviewRisk {
    pub fn color(self) -> Color {
        match self {
            Self::Low => IOS_GREEN_STRICT,
            Self::Medium => IOS_ORANGE_STRICT,
            Self::High => IOS_RED_STRICT,
        }
    }

    fn soft_bg(self) -> Color {
        match self {
            Self::Low => GREEN_SOFT,
            Self::Medium => ORANGE_SOFT,
            Self::High => RED_SOFT,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Low => "LOW",
            Self::Medium => "MED",
            Self::High => "HIGH",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthLevel {
    Low,
    High,
}

impl AuthLevel {
    pub fn color(self) -> Color {
        match self {
            Self::Low => IOS_GREEN_STRICT,
            Self::High => IOS_BLUE,
        }
    }

    fn soft_bg(self) -> Color {
        match self {
            Self::Low => GREEN_SOFT,
            Self::High => BLUE_SOFT,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Low => "AUTH LOW",
            Self::High => "AUTH HIGH",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Freshness {
    Fresh,
    Idle,
    Stale,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LiveIndicator {
    tick: u64,
    age_secs: u64,
}

impl LiveIndicator {
    pub fn from_age_secs(tick: u64, age_secs: u64) -> Self {
        Self { tick, age_secs }
    }

    pub fn fresh(tick: u64) -> Self {
        Self { tick, age_secs: 0 }
    }

    fn freshness(self) -> Freshness {
        if self.age_secs <= 5 {
            Freshness::Fresh
        } else if self.age_secs >= 30 {
            Freshness::Stale
        } else {
            Freshness::Idle
        }
    }

    fn glyph(self) -> &'static str {
        match self.tick % 3 {
            0 => "●",
            1 => "◉",
            _ => "◎",
        }
    }

    fn color(self) -> Color {
        match self.freshness() {
            Freshness::Fresh => IOS_GREEN_STRICT,
            Freshness::Idle => IOS_ORANGE_STRICT,
            Freshness::Stale => IOS_RED_STRICT,
        }
    }

    pub fn label(self) -> String {
        format!(
            "{} auto-reviewer on · last {}s",
            self.glyph(),
            self.age_secs
        )
    }

    fn width(self) -> u16 {
        visible_width(&self.label()) + 4
    }
}

impl Widget for LiveIndicator {
    fn render(self, area: Rect, buf: &mut Buffer) {
        if area.width == 0 || area.height == 0 {
            return;
        }
        let line = Line::from(vec![
            Span::styled("◖", Style::default().fg(self.color()).bg(IOS_BG_SOLID)),
            Span::styled(
                format!(" {} ", self.label()),
                Style::default()
                    .fg(IOS_FG)
                    .bg(self.color())
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled("◗", Style::default().fg(self.color()).bg(IOS_BG_SOLID)),
        ]);
        Paragraph::new(line).render(area, buf);
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ReviewItem<'a> {
    pub id: &'a str,
    pub title: &'a str,
    pub risk: ReviewRisk,
    pub auth: AuthLevel,
    pub rationale: &'a str,
    pub files: Vec<&'a str>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RecentDecision<'a> {
    pub id: &'a str,
    pub risk: ReviewRisk,
    pub decision: &'a str,
    pub age: &'a str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ReviewIosPageDesign<'a> {
    queue: Vec<ReviewItem<'a>>,
    recent: Vec<RecentDecision<'a>>,
    live: LiveIndicator,
}

impl<'a> ReviewIosPageDesign<'a> {
    pub fn new(queue: Vec<ReviewItem<'a>>, recent: Vec<RecentDecision<'a>>) -> Self {
        Self {
            queue,
            recent,
            live: LiveIndicator::fresh(0),
        }
    }

    pub fn demo_pending() -> Self {
        Self::new(
            vec![ReviewItem {
                id: "REV-142",
                title: "full-bringup removes stale tab strip pane",
                risk: ReviewRisk::Medium,
                auth: AuthLevel::High,
                rationale: "Diff is isolated to tmux launch plumbing; smoke evidence shows the worker grid owns all panes and no tab-strip panel remains.",
                files: vec![
                    "scripts/codex-fleet/full-bringup.sh",
                    "scripts/codex-fleet/overview-header.sh",
                    "openspec/changes/codex-fleet-glass-menu-drop-tabstrip-2026-05-15/CHANGE.md",
                ],
            }],
            demo_recent(),
        )
        .live(LiveIndicator::from_age_secs(0, 2))
    }

    pub fn demo_empty() -> Self {
        Self::new(Vec::new(), demo_recent()).live(LiveIndicator::from_age_secs(2, 41))
    }

    pub fn live(mut self, live: LiveIndicator) -> Self {
        self.live = live;
        self
    }
}

impl Widget for ReviewIosPageDesign<'_> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        fill(area, IOS_BG_SOLID, buf);
        if area.width < 56 || area.height < 18 {
            return;
        }

        let root_block = rounded_block(Some("REVIEW"), IOS_HAIRLINE_STRONG, IOS_BG_SOLID, false);
        let root = root_block.inner(area);
        root_block.render(area, buf);
        fill(root, IOS_BG_SOLID, buf);
        render_palette_strip(Rect::new(root.x, root.y, root.width, 1), buf);

        let content = Rect::new(
            root.x.saturating_add(2),
            root.y.saturating_add(2),
            root.width.saturating_sub(4),
            root.height.saturating_sub(3),
        );
        if content.width == 0 || content.height == 0 {
            return;
        }

        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(3), Constraint::Min(0)])
            .split(content);
        render_header(rows[0], buf, self.queue.len(), self.live);

        if rows[1].width >= 116 {
            let cols = Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Percentage(68), Constraint::Percentage(32)])
                .split(rows[1]);
            render_queue(cols[0], buf, &self.queue);
            render_recent(cols[1], buf, &self.recent);
        } else {
            let body = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Percentage(62), Constraint::Percentage(38)])
                .split(rows[1]);
            render_queue(body[0], buf, &self.queue);
            render_recent(body[1], buf, &self.recent);
        }
    }
}

fn demo_recent<'a>() -> Vec<RecentDecision<'a>> {
    vec![
        RecentDecision {
            id: "REV-141",
            risk: ReviewRisk::Low,
            decision: "approved",
            age: "4m",
        },
        RecentDecision {
            id: "REV-140",
            risk: ReviewRisk::High,
            decision: "denied",
            age: "11m",
        },
        RecentDecision {
            id: "REV-139",
            risk: ReviewRisk::Medium,
            decision: "verified",
            age: "18m",
        },
    ]
}

fn render_header(area: Rect, buf: &mut Buffer, pending: usize, live: LiveIndicator) {
    if area.width == 0 || area.height == 0 {
        return;
    }
    let live_w = live.width().min(area.width);
    let cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Min(0), Constraint::Length(live_w)])
        .split(Rect::new(area.x, area.y, area.width, 1));

    Paragraph::new(Line::from(vec![
        Span::styled(
            "REVIEW QUEUE",
            Style::default().fg(IOS_FG).add_modifier(Modifier::BOLD),
        ),
        Span::styled(
            format!("  ·  {pending} pending"),
            Style::default().fg(IOS_FG_MUTED),
        ),
    ]))
    .render(cols[0], buf);
    live.render(cols[1], buf);

    if area.height > 1 {
        Paragraph::new(Line::from(Span::styled(
            "approval queue · auto-reviewer rationale · file risk",
            Style::default()
                .fg(IOS_FG_FAINT)
                .add_modifier(Modifier::BOLD),
        )))
        .render(Rect::new(area.x, area.y + 2, area.width, 1), buf);
    }
}

fn render_queue(area: Rect, buf: &mut Buffer, queue: &[ReviewItem<'_>]) {
    if area.width < 36 || area.height < 6 {
        return;
    }
    let block = rounded_block(Some("APPROVAL QUEUE"), IOS_BLUE, PANEL_BG, false);
    let inner = block.inner(area);
    block.render(area, buf);
    fill(inner, PANEL_BG, buf);

    if queue.is_empty() {
        Paragraph::new(Line::from(vec![
            Span::styled(
                "queue clear",
                Style::default()
                    .fg(IOS_FG)
                    .bg(PANEL_BG)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                " · auto-reviewer caught up",
                Style::default().fg(IOS_FG_MUTED).bg(PANEL_BG),
            ),
        ]))
        .alignment(Alignment::Center)
        .render(center_line(inner), buf);
        return;
    }

    let mut y = inner.y.saturating_add(1);
    for item in queue.iter().take(2) {
        let remaining = inner.y + inner.height;
        if y >= remaining {
            break;
        }
        let h = 12.min(remaining.saturating_sub(y));
        render_review_card(
            Rect::new(inner.x + 1, y, inner.width.saturating_sub(2), h),
            buf,
            item,
        );
        y = y.saturating_add(h + 1);
    }
}

fn render_review_card(area: Rect, buf: &mut Buffer, item: &ReviewItem<'_>) {
    if area.width < 30 || area.height < 6 {
        return;
    }
    let block = rounded_block(Some(item.id), item.risk.color(), CARD_BG, true);
    let inner = block.inner(area);
    block.render(area, buf);
    fill(inner, CARD_BG, buf);

    let mut y = inner.y;
    line(
        buf,
        Rect::new(inner.x + 1, y, inner.width.saturating_sub(2), 1),
        Line::from(vec![
            Span::styled(
                fit(item.title, inner.width.saturating_sub(28)),
                Style::default()
                    .fg(IOS_FG)
                    .bg(CARD_BG)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            pill(item.risk.label(), item.risk.color(), item.risk.soft_bg()),
            Span::raw(" "),
            pill(item.auth.label(), item.auth.color(), item.auth.soft_bg()),
        ]),
    );
    y += 2;

    render_labeled_block(
        Rect::new(inner.x + 1, y, inner.width.saturating_sub(2), 3),
        buf,
        "AUTO-REVIEWER RATIONALE",
        item.rationale,
        CARD_BG,
    );
    y += 4;

    if y < inner.y + inner.height {
        line(
            buf,
            Rect::new(inner.x + 1, y, inner.width.saturating_sub(2), 1),
            Line::from(Span::styled(
                "FILES TOUCHED",
                Style::default()
                    .fg(IOS_FG_FAINT)
                    .bg(CARD_BG)
                    .add_modifier(Modifier::BOLD),
            )),
        );
        y += 1;
    }

    for file in item.files.iter().take(2) {
        if y >= inner.y + inner.height.saturating_sub(1) {
            break;
        }
        line(
            buf,
            Rect::new(inner.x + 1, y, inner.width.saturating_sub(2), 1),
            Line::from(vec![
                Span::styled("• ", Style::default().fg(IOS_BLUE).bg(CARD_BG)),
                Span::styled(
                    fit(file, inner.width.saturating_sub(4)),
                    Style::default().fg(IOS_FG_MUTED).bg(CARD_BG),
                ),
            ]),
        );
        y += 1;
    }

    if inner.height > 1 {
        let action_y = inner.y + inner.height.saturating_sub(1);
        line(
            buf,
            Rect::new(inner.x + 1, action_y, inner.width.saturating_sub(2), 1),
            Line::from(vec![
                keycap("A", "approve", IOS_GREEN_STRICT),
                Span::raw("  "),
                keycap("V", "verify", IOS_BLUE),
                Span::raw("  "),
                keycap("D", "deny", IOS_RED_STRICT),
            ]),
        );
    }
}

fn render_recent(area: Rect, buf: &mut Buffer, recent: &[RecentDecision<'_>]) {
    if area.width < 26 || area.height < 6 {
        return;
    }
    let block = rounded_block(
        Some("RECENT DECISIONS"),
        IOS_HAIRLINE_STRONG,
        PANEL_BG,
        false,
    );
    let inner = block.inner(area);
    block.render(area, buf);
    fill(inner, PANEL_BG, buf);

    let max = inner.height as usize;
    for (idx, item) in recent.iter().take(max).enumerate() {
        let y = inner.y + idx as u16;
        line(
            buf,
            Rect::new(inner.x + 1, y, inner.width.saturating_sub(2), 1),
            Line::from(vec![
                pill(item.risk.label(), item.risk.color(), item.risk.soft_bg()),
                Span::styled(
                    format!(" {} ", item.id),
                    Style::default()
                        .fg(IOS_FG)
                        .bg(PANEL_BG)
                        .add_modifier(Modifier::BOLD),
                ),
                Span::styled(
                    fit(item.decision, inner.width.saturating_sub(22)),
                    Style::default().fg(IOS_FG_MUTED).bg(PANEL_BG),
                ),
                Span::styled(
                    format!(" {}", item.age),
                    Style::default().fg(IOS_FG_FAINT).bg(PANEL_BG),
                ),
            ]),
        );
    }
}

fn render_labeled_block(area: Rect, buf: &mut Buffer, title: &str, body: &str, bg: Color) {
    if area.width == 0 || area.height == 0 {
        return;
    }
    line(
        buf,
        Rect::new(area.x, area.y, area.width, 1),
        Line::from(Span::styled(
            title,
            Style::default()
                .fg(IOS_BLUE)
                .bg(bg)
                .add_modifier(Modifier::BOLD),
        )),
    );
    if area.height > 1 {
        Paragraph::new(Line::from(Span::styled(
            body,
            Style::default().fg(IOS_FG_MUTED).bg(bg),
        )))
        .wrap(Wrap { trim: true })
        .render(
            Rect::new(area.x, area.y + 1, area.width, area.height - 1),
            buf,
        );
    }
}

fn rounded_block<'a>(title: Option<&'a str>, border: Color, bg: Color, bold: bool) -> Block<'a> {
    let mut style = Style::default().fg(border).bg(bg);
    if bold {
        style = style.add_modifier(Modifier::BOLD);
    }
    let mut block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(style)
        .style(Style::default().bg(bg));
    if let Some(title) = title {
        block = block.title(Span::styled(
            format!(" {title} "),
            Style::default()
                .fg(IOS_FG)
                .bg(bg)
                .add_modifier(Modifier::BOLD),
        ));
    }
    block
}

fn render_palette_strip(area: Rect, buf: &mut Buffer) {
    if area.width == 0 || area.height == 0 {
        return;
    }
    let swatches = [
        IOS_BLUE,
        IOS_GREEN_STRICT,
        IOS_ORANGE_STRICT,
        IOS_RED_STRICT,
        IOS_PURPLE,
    ];
    for dx in 0..area.width {
        let color = swatches[dx as usize % swatches.len()];
        buf[(area.x + dx, area.y)]
            .set_symbol(" ")
            .set_bg(color)
            .set_fg(color);
    }
}

fn pill<'a>(label: &'a str, fg: Color, bg: Color) -> Span<'a> {
    Span::styled(
        format!(" {label} "),
        Style::default().fg(fg).bg(bg).add_modifier(Modifier::BOLD),
    )
}

fn keycap<'a>(key: &'a str, label: &'a str, accent: Color) -> Span<'a> {
    Span::styled(
        format!("[{key}] {label}"),
        Style::default()
            .fg(accent)
            .bg(CARD_BG)
            .add_modifier(Modifier::BOLD),
    )
}

fn line(buf: &mut Buffer, area: Rect, line: Line<'_>) {
    if area.width == 0 || area.height == 0 {
        return;
    }
    Paragraph::new(line).render(area, buf);
}

fn fill(area: Rect, color: Color, buf: &mut Buffer) {
    for y in area.y..area.y.saturating_add(area.height) {
        for x in area.x..area.x.saturating_add(area.width) {
            buf[(x, y)].set_bg(color);
        }
    }
}

fn center_line(area: Rect) -> Rect {
    Rect::new(
        area.x,
        area.y + area.height.saturating_sub(1) / 2,
        area.width,
        1,
    )
}

fn fit(text: &str, width: u16) -> String {
    let width = width as usize;
    if width == 0 {
        return String::new();
    }
    let mut out = String::new();
    for ch in text.chars().take(width) {
        out.push(ch);
    }
    if text.chars().count() > width && width >= 1 {
        out.pop();
        out.push('…');
    }
    out
}

fn visible_width(text: &str) -> u16 {
    text.chars().count() as u16
}
