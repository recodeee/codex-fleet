//! iOS pinned context menu widget for the design-A artboard.
//!
//! This module is intentionally standalone for the 18-way design-speed plan:
//! follow-up integration wires it into `overlay.rs`.

use crate::palette::*;
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Clear, Paragraph, Widget},
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MenuItem<'a> {
    pub icon: &'a str,
    pub label: &'a str,
    pub shortcut: &'a str,
    pub destructive: bool,
}

impl<'a> MenuItem<'a> {
    pub fn new(icon: &'a str, label: &'a str, shortcut: &'a str) -> Self {
        Self {
            icon,
            label,
            shortcut,
            destructive: false,
        }
    }

    pub fn destructive(icon: &'a str, label: &'a str, shortcut: &'a str) -> Self {
        Self {
            icon,
            label,
            shortcut,
            destructive: true,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IosContextMenu<'a> {
    pub items: Vec<MenuItem<'a>>,
    pub anchor: Rect,
}

impl<'a> IosContextMenu<'a> {
    pub const WIDTH: u16 = 42;

    pub fn new(items: Vec<MenuItem<'a>>, anchor: Rect) -> Self {
        Self { items, anchor }
    }

    pub fn height(&self) -> u16 {
        let rows = self.items.len() as u16;
        rows.saturating_add(4)
    }

    fn menu_rect(&self, area: Rect) -> Rect {
        let height = self.height().min(area.height);
        let width = Self::WIDTH.min(area.width);
        let preferred_x = self
            .anchor
            .x
            .saturating_add(self.anchor.width)
            .saturating_add(1);
        let fallback_x = self.anchor.x.saturating_sub(width.saturating_add(1));
        let x = if preferred_x.saturating_add(width) <= area.x.saturating_add(area.width) {
            preferred_x
        } else {
            fallback_x
        }
        .max(area.x)
        .min(area.x.saturating_add(area.width.saturating_sub(width)));
        let y = self
            .anchor
            .y
            .max(area.y)
            .min(area.y.saturating_add(area.height.saturating_sub(height)));

        Rect {
            x,
            y,
            width,
            height,
        }
    }
}

impl Widget for IosContextMenu<'_> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        (&self).render(area, buf);
    }
}

impl Widget for &IosContextMenu<'_> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        if area.width == 0 || area.height == 0 {
            return;
        }

        let rect = self.menu_rect(area);
        shadow(rect, area, buf);
        Clear.render(rect, buf);
        menu_block().render(rect, buf);

        let inner = Rect {
            x: rect.x.saturating_add(2),
            y: rect.y.saturating_add(1),
            width: rect.width.saturating_sub(4),
            height: rect.height.saturating_sub(2),
        };
        if inner.width == 0 || inner.height == 0 {
            return;
        }

        Paragraph::new(Line::from(vec![
            Span::styled("●", Style::default().fg(IOS_GREEN)),
            Span::raw("  "),
            Span::styled(
                "Context Menu",
                Style::default().fg(IOS_FG).add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            Span::styled("LIVE", Style::default().fg(IOS_GREEN)),
        ]))
        .render(
            Rect {
                x: inner.x,
                y: inner.y,
                width: inner.width,
                height: 1,
            },
            buf,
        );

        hairline(inner, inner.y.saturating_add(1), IOS_HAIRLINE_STRONG, buf);
        let visible_rows = inner.height.saturating_sub(2) as usize;
        for (index, item) in self.items.iter().take(visible_rows).enumerate() {
            let y = inner.y.saturating_add(2).saturating_add(index as u16);
            render_item(item, inner, y, index, buf);
        }
    }
}

fn menu_block<'a>() -> Block<'a> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(IOS_HAIRLINE_STRONG).bg(IOS_BG_GLASS))
        .style(Style::default().fg(IOS_FG).bg(IOS_BG_GLASS))
}

fn render_item(item: &MenuItem<'_>, inner: Rect, y: u16, index: usize, buf: &mut Buffer) {
    let bg = if index % 2 == 0 {
        IOS_ROW_BG_DARK
    } else {
        IOS_ROW_BG_LIGHT
    };
    let fg = if item.destructive {
        IOS_DESTRUCTIVE
    } else {
        IOS_FG
    };
    let icon_bg = if item.destructive {
        Color::Rgb(58, 24, 24)
    } else {
        IOS_ICON_CHIP
    };
    let shortcut_width = item.shortcut.chars().count() as u16 + 2;
    let label_width = inner.width.saturating_sub(shortcut_width.saturating_add(1));
    let line = Line::from(vec![
        Span::styled(" ", Style::default().bg(bg)),
        Span::styled(
            format!(" {} ", item.icon),
            Style::default()
                .fg(fg)
                .bg(icon_bg)
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled("  ", Style::default().bg(bg)),
        Span::styled(
            title_case_first(item.label),
            Style::default().fg(fg).bg(bg).add_modifier(Modifier::BOLD),
        ),
    ]);
    Paragraph::new(line).render(
        Rect {
            x: inner.x,
            y,
            width: label_width,
            height: 1,
        },
        buf,
    );

    if inner.width > shortcut_width {
        Paragraph::new(Line::from(Span::styled(
            format!(" {} ", item.shortcut),
            Style::default().fg(IOS_FG_FAINT).bg(IOS_CHIP_BG),
        )))
        .render(
            Rect {
                x: inner.x + inner.width - shortcut_width,
                y,
                width: shortcut_width,
                height: 1,
            },
            buf,
        );
    }
}

fn hairline(inner: Rect, y: u16, color: Color, buf: &mut Buffer) {
    if y >= inner.y.saturating_add(inner.height) {
        return;
    }
    Paragraph::new(Span::styled(
        "─".repeat(inner.width as usize),
        Style::default().fg(color).bg(IOS_BG_GLASS),
    ))
    .render(
        Rect {
            x: inner.x,
            y,
            width: inner.width,
            height: 1,
        },
        buf,
    );
}

fn shadow(rect: Rect, area: Rect, buf: &mut Buffer) {
    let right = rect.x.saturating_add(rect.width);
    if right < area.x.saturating_add(area.width) {
        for y in rect.y.saturating_add(1)..rect.y.saturating_add(rect.height).min(area.height) {
            buf[(right, y)].set_bg(Color::Rgb(12, 12, 14));
        }
    }
    let bottom = rect.y.saturating_add(rect.height);
    if bottom < area.y.saturating_add(area.height) {
        for x in rect.x.saturating_add(1)..rect.x.saturating_add(rect.width).min(area.width) {
            buf[(x, bottom)].set_bg(Color::Rgb(12, 12, 14));
        }
    }
}

fn title_case_first(label: &str) -> String {
    let mut chars = label.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    #[test]
    fn context_menu_default_render_design_a() {
        let mut terminal = Terminal::new(TestBackend::new(72, 18)).unwrap();
        let menu = IosContextMenu::new(
            vec![
                MenuItem::new("↹", "split pane", "S"),
                MenuItem::new("⤢", "zoom pane", "Z"),
                MenuItem::new("⧉", "copy transcript", "C"),
                MenuItem::destructive("×", "kill pane", "⌫"),
            ],
            Rect::new(8, 3, 18, 6),
        );

        terminal
            .draw(|frame| frame.render_widget(&menu, frame.area()))
            .unwrap();

        let rendered = format!("{}", terminal.backend())
            .lines()
            .skip(3)
            .take(8)
            .map(|line| {
                line.chars()
                    .skip(27)
                    .take(44)
                    .collect::<String>()
                    .trim_end()
                    .to_owned()
            })
            .collect::<Vec<_>>()
            .join("\n");

        insta::assert_snapshot!(
            rendered,
            @r###"
╭────────────────────────────────────────╮
│ ●  Context Menu  LIVE                  │
│ ────────────────────────────────────── │
│   ↹   Split pane                    S  │
│   ⤢   Zoom pane                     Z  │
│   ⧉   Copy transcript               C  │
│   ×   Kill pane                     ⌫  │
╰────────────────────────────────────────╯"###
        );
    }

    #[test]
    fn title_case_first_only_changes_first_letter() {
        assert_eq!(title_case_first("split pane"), "Split pane");
    }
}
