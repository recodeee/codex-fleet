//! Grouped iOS action sheet for the design-C artboard.
//!
//! The sheet is bottom anchored, keeps the cancel affordance visually
//! separate, and uses iOS destructive red for dangerous actions.

use crate::{overlay::card_shadow, palette::*};
use ratatui::{
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Clear, Paragraph},
    Frame,
};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ActionTone {
    #[default]
    Normal,
    Warning,
    Destructive,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActionSheetItem<'a> {
    pub icon: &'a str,
    pub title: &'a str,
    pub detail: &'a str,
    pub shortcut: &'a str,
    pub tone: ActionTone,
}

impl<'a> ActionSheetItem<'a> {
    pub fn new(icon: &'a str, title: &'a str, detail: &'a str) -> Self {
        Self {
            icon,
            title,
            detail,
            shortcut: "",
            tone: ActionTone::Normal,
        }
    }

    pub fn shortcut(mut self, shortcut: &'a str) -> Self {
        self.shortcut = shortcut;
        self
    }

    pub fn warning(mut self) -> Self {
        self.tone = ActionTone::Warning;
        self
    }

    pub fn destructive(icon: &'a str, title: &'a str, detail: &'a str) -> Self {
        Self {
            icon,
            title,
            detail,
            shortcut: "",
            tone: ActionTone::Destructive,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActionGroup<'a> {
    pub title: &'a str,
    pub caption: &'a str,
    pub items: Vec<ActionSheetItem<'a>>,
}

impl<'a> ActionGroup<'a> {
    pub fn new(title: &'a str, caption: &'a str, items: Vec<ActionSheetItem<'a>>) -> Self {
        Self {
            title,
            caption,
            items,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ActionSheetState {
    pub selected: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActionSheet<'a> {
    pub title: &'a str,
    pub groups: Vec<ActionGroup<'a>>,
    pub cancel_label: &'a str,
}

impl<'a> ActionSheet<'a> {
    pub const WIDTH: u16 = 64;

    pub fn new(title: &'a str, groups: Vec<ActionGroup<'a>>) -> Self {
        Self {
            title,
            groups,
            cancel_label: "Cancel",
        }
    }

    pub fn cancel_label(mut self, label: &'a str) -> Self {
        self.cancel_label = label;
        self
    }

    pub fn item_count(&self) -> usize {
        self.groups.iter().map(|group| group.items.len()).sum()
    }

    pub fn height(&self) -> u16 {
        let groups_height = self
            .groups
            .iter()
            .map(group_height)
            .sum::<u16>()
            .saturating_add(2);
        groups_height.saturating_add(1).saturating_add(3)
    }

    pub fn render(&self, frame: &mut Frame, area: Rect, state: &ActionSheetState) {
        if area.width == 0 || area.height == 0 {
            return;
        }

        let width = Self::WIDTH.min(area.width);
        let height = self.height().min(area.height);
        let x = area.x + area.width.saturating_sub(width) / 2;
        let y = area.y + area.height.saturating_sub(height);
        let sheet = Rect {
            x,
            y,
            width,
            height,
        };

        let cancel_rect = Rect {
            x,
            y: sheet.y + sheet.height.saturating_sub(3),
            width,
            height: 3.min(sheet.height),
        };
        let action_rect = Rect {
            x,
            y,
            width,
            height: sheet
                .height
                .saturating_sub(cancel_rect.height)
                .saturating_sub(1),
        };

        card_shadow(frame, action_rect, area);
        card_shadow(frame, cancel_rect, area);
        render_action_card(frame, action_rect, self, state);
        render_cancel_card(
            frame,
            cancel_rect,
            self.cancel_label,
            state.selected >= self.item_count(),
        );
    }
}

fn group_height(group: &ActionGroup<'_>) -> u16 {
    let rows = group.items.len() as u16;
    3u16.saturating_add(rows.saturating_mul(3).saturating_sub(1))
}

fn render_action_card(
    frame: &mut Frame,
    rect: Rect,
    sheet: &ActionSheet<'_>,
    state: &ActionSheetState,
) {
    if rect.width == 0 || rect.height == 0 {
        return;
    }

    frame.render_widget(Clear, rect);
    frame.render_widget(sheet_block(), rect);
    let inner = inset(rect, 2, 1);
    if inner.width == 0 || inner.height == 0 {
        return;
    }

    let mut y = inner.y;
    let mut flat_index = 0usize;
    for (group_index, group) in sheet.groups.iter().enumerate() {
        if group_index > 0 {
            render_hairline(frame, inner, y);
            y = y.saturating_add(1);
        }
        if y >= inner.y + inner.height {
            break;
        }
        render_group_header(frame, inner, y, group, sheet.title);
        y = y.saturating_add(2);
        render_hairline(frame, inner, y);
        y = y.saturating_add(1);

        for (item_index, item) in group.items.iter().enumerate() {
            if y + 1 >= inner.y + inner.height {
                return;
            }
            render_item(frame, inner, y, item, state.selected == flat_index);
            y = y.saturating_add(2);
            flat_index += 1;
            if item_index + 1 < group.items.len() {
                render_hairline(frame, inner, y);
                y = y.saturating_add(1);
            }
        }
    }
}

fn render_group_header(
    frame: &mut Frame,
    inner: Rect,
    y: u16,
    group: &ActionGroup<'_>,
    fallback_title: &str,
) {
    let title = if group.title.is_empty() {
        fallback_title
    } else {
        group.title
    };
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled("●", Style::default().fg(IOS_GREEN).bg(IOS_BG_GLASS)),
            Span::styled("  ", Style::default().bg(IOS_BG_GLASS)),
            Span::styled(
                title,
                Style::default()
                    .fg(IOS_FG)
                    .bg(IOS_BG_GLASS)
                    .add_modifier(Modifier::BOLD),
            ),
        ])),
        Rect {
            x: inner.x,
            y,
            width: inner.width,
            height: 1,
        },
    );

    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            group.caption,
            Style::default().fg(IOS_FG_MUTED).bg(IOS_BG_GLASS),
        ))),
        Rect {
            x: inner.x + 3,
            y: y.saturating_add(1),
            width: inner.width.saturating_sub(3),
            height: 1,
        },
    );
}

fn render_item(frame: &mut Frame, inner: Rect, y: u16, item: &ActionSheetItem<'_>, selected: bool) {
    let row_bg = if selected { IOS_TINT_DARK } else { IOS_CARD_BG };
    let (accent, chip_bg) = tone_colors(item.tone, selected);
    frame.render_widget(
        Block::default().style(Style::default().bg(row_bg)),
        Rect {
            x: inner.x,
            y,
            width: inner.width,
            height: 2,
        },
    );

    let shortcut = if item.shortcut.is_empty() {
        String::new()
    } else {
        format!(" {} ", item.shortcut)
    };
    let shortcut_width = text_width(&shortcut);
    let title_width = inner.width.saturating_sub(shortcut_width.saturating_add(1));
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(" ", Style::default().bg(row_bg)),
            Span::styled(
                format!(" {} ", item.icon),
                Style::default()
                    .fg(accent)
                    .bg(chip_bg)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled("  ", Style::default().bg(row_bg)),
            Span::styled(
                item.title,
                Style::default()
                    .fg(accent)
                    .bg(row_bg)
                    .add_modifier(Modifier::BOLD),
            ),
        ])),
        Rect {
            x: inner.x,
            y,
            width: title_width,
            height: 1,
        },
    );

    if shortcut_width > 0 && inner.width > shortcut_width {
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(
                shortcut,
                Style::default()
                    .fg(IOS_FG)
                    .bg(IOS_CHIP_BG)
                    .add_modifier(Modifier::BOLD),
            ))),
            Rect {
                x: inner.x + inner.width - shortcut_width,
                y,
                width: shortcut_width,
                height: 1,
            },
        );
    }

    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            format!("       {}", item.detail),
            Style::default()
                .fg(detail_color(item.tone, selected))
                .bg(row_bg),
        ))),
        Rect {
            x: inner.x,
            y: y.saturating_add(1),
            width: inner.width,
            height: 1,
        },
    );
}

fn render_cancel_card(frame: &mut Frame, rect: Rect, label: &str, selected: bool) {
    if rect.width == 0 || rect.height == 0 {
        return;
    }

    frame.render_widget(Clear, rect);
    frame.render_widget(cancel_block(selected), rect);
    let inner = inset(rect, 2, 1);
    let label_width = text_width(label);
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            label,
            Style::default()
                .fg(if selected { IOS_FG } else { IOS_DESTRUCTIVE })
                .bg(if selected {
                    IOS_TINT_DARK
                } else {
                    IOS_BG_GLASS
                })
                .add_modifier(Modifier::BOLD),
        ))),
        Rect {
            x: inner.x + inner.width.saturating_sub(label_width) / 2,
            y: inner.y,
            width: label_width.min(inner.width),
            height: 1,
        },
    );
}

fn sheet_block<'a>() -> Block<'a> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(IOS_HAIRLINE_STRONG).bg(IOS_BG_GLASS))
        .style(Style::default().fg(IOS_FG).bg(IOS_BG_GLASS))
}

fn cancel_block<'a>(selected: bool) -> Block<'a> {
    let bg = if selected {
        IOS_TINT_DARK
    } else {
        IOS_BG_GLASS
    };
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(IOS_HAIRLINE_STRONG).bg(bg))
        .style(Style::default().fg(IOS_FG).bg(bg))
}

fn render_hairline(frame: &mut Frame, inner: Rect, y: u16) {
    if y >= inner.y.saturating_add(inner.height) {
        return;
    }
    frame.render_widget(
        Paragraph::new(Span::styled(
            "─".repeat(inner.width as usize),
            Style::default().fg(IOS_HAIRLINE).bg(IOS_BG_GLASS),
        )),
        Rect {
            x: inner.x,
            y,
            width: inner.width,
            height: 1,
        },
    );
}

fn tone_colors(tone: ActionTone, selected: bool) -> (Color, Color) {
    if selected {
        return (IOS_FG, IOS_TINT);
    }
    match tone {
        ActionTone::Normal => (IOS_FG, IOS_ICON_CHIP),
        ActionTone::Warning => (IOS_ORANGE, Color::Rgb(66, 44, 18)),
        ActionTone::Destructive => (IOS_DESTRUCTIVE, Color::Rgb(58, 24, 24)),
    }
}

fn detail_color(tone: ActionTone, selected: bool) -> Color {
    if selected {
        IOS_TINT_SUB
    } else if tone == ActionTone::Destructive {
        Color::Rgb(255, 138, 130)
    } else {
        IOS_FG_MUTED
    }
}

fn inset(rect: Rect, x: u16, y: u16) -> Rect {
    Rect {
        x: rect.x.saturating_add(x),
        y: rect.y.saturating_add(y),
        width: rect.width.saturating_sub(x.saturating_mul(2)),
        height: rect.height.saturating_sub(y.saturating_mul(2)),
    }
}

fn text_width(text: &str) -> u16 {
    text.chars().count() as u16
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    fn sample_sheet() -> ActionSheet<'static> {
        ActionSheet::new(
            "Fleet Actions",
            vec![ActionGroup::new(
                "Pane Actions",
                "Choose an action for the selected worker pane.",
                vec![
                    ActionSheetItem::new("↹", "Split pane", "Open a sibling terminal surface")
                        .shortcut("1"),
                    ActionSheetItem::new("⇄", "Swap pane", "Move this pane to another slot")
                        .shortcut("2"),
                    ActionSheetItem::new("⚠", "Retarget plan", "Pin renderer to another plan")
                        .warning()
                        .shortcut("3"),
                    ActionSheetItem::destructive("×", "Kill pane", "Stop the selected worker")
                        .shortcut("4"),
                ],
            )],
        )
    }

    #[test]
    fn action_sheet_default_render_design_c() {
        let mut terminal = Terminal::new(TestBackend::new(80, 28)).unwrap();
        let sheet = sample_sheet();

        terminal
            .draw(|frame| sheet.render(frame, frame.area(), &ActionSheetState::default()))
            .unwrap();

        let rendered = format!("{}", terminal.backend())
            .lines()
            .skip(8)
            .take(20)
            .map(|line| {
                line.chars()
                    .skip(8)
                    .take(66)
                    .collect::<String>()
                    .trim_end()
                    .to_owned()
            })
            .collect::<Vec<_>>()
            .join("\n");

        insta::assert_snapshot!(
            rendered,
            @r###"
╭──────────────────────────────────────────────────────────────╮
│ ●  Pane Actions                                              │
│    Choose an action for the selected worker pane.            │
│ ──────────────────────────────────────────────────────────── │
│   ↹   Split pane                                          1  │
│        Open a sibling terminal surface                       │
│ ──────────────────────────────────────────────────────────── │
│   ⇄   Swap pane                                           2  │
│        Move this pane to another slot                        │
│ ──────────────────────────────────────────────────────────── │
│   ⚠   Retarget plan                                       3  │
│        Pin renderer to another plan                          │
│ ──────────────────────────────────────────────────────────── │
│   ×   Kill pane                                           4  │
│        Stop the selected worker                              │
╰──────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────╮
│                            Cancel                            │
╰──────────────────────────────────────────────────────────────╯"###
        );
    }

    #[test]
    fn cancel_is_selected_after_all_items() {
        let sheet = sample_sheet();
        assert_eq!(sheet.item_count(), 4);
        assert!(ActionSheetState { selected: 4 }.selected >= sheet.item_count());
    }
}
