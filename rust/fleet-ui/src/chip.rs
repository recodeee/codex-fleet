//! iOS-style status pill — `◖ ● working ◗`.
//!
//! Ported from `scripts/codex-fleet/fleet-tick.sh::ios_worker_chip` plus the
//! fleet-tui-poc `ios_chip()` helper. Each pill has the same three-Span
//! shape:
//!
//! ```text
//! ◖ ● working ◗
//! └─┘ └────────┘ └─┘
//!  cap   label    cap
//! ```
//!
//! - Caps (`◖` / `◗`) render with `bg = IOS_BG_SOLID` and `fg = <kind colour>`
//!   so they punch a coloured half-circle out of the base surface.
//! - Label (` ● <text> `) gets `bg = <kind colour>`, a contrast-safe `fg`,
//!   and bold text.
//!
//! The dot glyph and width-padding match the bash regression in
//! `scripts/codex-fleet/test/test-status-chips.sh`.

use crate::palette::*;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::Span;

const CAP_LEFT: &str = "◖";
const CAP_RIGHT: &str = "◗";

const BG: Color = IOS_BG_SOLID;

/// The status of a fleet pane (worker), as classified by `fleet-data::panes`.
/// Each kind gets a fixed colour + glyph so the bash regression suite's
/// expected strings carry over verbatim.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChipKind {
    Working,
    Idle,
    Polling,
    Done,
    Live,
    Blocked,
    Capped,
    Approval,
    Boot,
    Dead,
}

impl ChipKind {
    /// Pill background colour. Matches `IOS_*` consts in `palette`.
    pub fn bg(self) -> Color {
        match self {
            ChipKind::Working => IOS_TINT,
            ChipKind::Idle => IOS_CHIP_BG,
            ChipKind::Polling => IOS_ORANGE,
            ChipKind::Done => IOS_GREEN,
            ChipKind::Live => IOS_GREEN,
            ChipKind::Blocked | ChipKind::Capped => IOS_DESTRUCTIVE,
            ChipKind::Approval => IOS_YELLOW,
            ChipKind::Boot => IOS_PURPLE,
            ChipKind::Dead => IOS_HAIRLINE_STRONG,
        }
    }

    /// Pill foreground colour. Bright iOS fills need dark text to keep the
    /// status labels readable; the neutral idle chip uses muted text.
    pub fn fg(self) -> Color {
        match self {
            ChipKind::Idle => IOS_FG_MUTED,
            ChipKind::Dead => IOS_FG,
            _ => IOS_BG_SOLID,
        }
    }

    /// Status glyph inside the pill.
    pub fn dot(self) -> &'static str {
        match self {
            ChipKind::Idle => "◌",
            ChipKind::Blocked => "■",
            ChipKind::Capped => "▲",
            ChipKind::Dead => "✕",
            _ => "●",
        }
    }

    /// Lowercase label, padded to a fixed visible width so adjacent pills
    /// have aligned right caps. Width = 7 (matches longest variant
    /// "polling").
    pub fn label(self) -> &'static str {
        match self {
            ChipKind::Working => "working",
            ChipKind::Idle => "idle   ",
            ChipKind::Polling => "polling",
            ChipKind::Done => "done   ",
            ChipKind::Live => "live   ",
            ChipKind::Blocked => "blocked",
            ChipKind::Capped => "capped ",
            ChipKind::Approval => "review ",
            ChipKind::Boot => "boot   ",
            ChipKind::Dead => "dead   ",
        }
    }
}

/// Render a status chip as a three-Span sequence: `◖`, ` ● label `, `◗`.
///
/// Caller is responsible for inserting separators between chips. The label
/// has built-in horizontal padding (one space on each side of `● text`) so
/// adjacent caps butt against the label without extra spans.
pub fn status_chip(kind: ChipKind) -> Vec<Span<'static>> {
    let bg = kind.bg();
    let fg = kind.fg();
    vec![
        Span::styled(CAP_LEFT, Style::default().fg(bg).bg(BG)),
        Span::styled(
            format!(" {} {} ", kind.dot(), kind.label()),
            Style::default().fg(fg).bg(bg).add_modifier(Modifier::BOLD),
        ),
        Span::styled(CAP_RIGHT, Style::default().fg(bg).bg(BG)),
    ]
}

/// Width in cells of a rendered chip (cap + ` ● label ` + cap = 1+10+1 = 12).
pub const CHIP_WIDTH: u16 = 1 + 1 + 1 + 1 + 7 + 1 + 1; // ◖ + space + dot + space + label + space + ◗

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chip_renders_three_spans() {
        let spans = status_chip(ChipKind::Working);
        assert_eq!(
            spans.len(),
            3,
            "chip must be exactly 3 spans (cap, label, cap)"
        );
        assert_eq!(spans[0].content, "◖");
        assert_eq!(spans[2].content, "◗");
    }

    #[test]
    fn label_visible_width_matches_seven() {
        for kind in [
            ChipKind::Working,
            ChipKind::Idle,
            ChipKind::Polling,
            ChipKind::Done,
            ChipKind::Live,
            ChipKind::Blocked,
            ChipKind::Capped,
            ChipKind::Approval,
            ChipKind::Boot,
            ChipKind::Dead,
        ] {
            assert_eq!(
                kind.label().chars().count(),
                7,
                "label({:?}) must be 7 chars wide for alignment",
                kind
            );
        }
    }

    #[test]
    fn working_chip_uses_systemblue() {
        assert_eq!(ChipKind::Working.bg(), IOS_TINT);
    }

    #[test]
    fn live_chip_uses_systemgreen() {
        assert_eq!(ChipKind::Live.bg(), IOS_GREEN);
    }

    #[test]
    fn capped_chip_uses_systemred() {
        assert_eq!(ChipKind::Capped.bg(), IOS_DESTRUCTIVE);
    }

    #[test]
    fn idle_chip_uses_muted_foreground() {
        assert_eq!(ChipKind::Idle.fg(), IOS_FG_MUTED);
    }

    #[test]
    fn status_chip_label_foregrounds_are_accessible() {
        for kind in [
            ChipKind::Working,
            ChipKind::Idle,
            ChipKind::Polling,
            ChipKind::Done,
            ChipKind::Live,
            ChipKind::Blocked,
            ChipKind::Capped,
            ChipKind::Approval,
            ChipKind::Boot,
            ChipKind::Dead,
        ] {
            assert!(
                contrast_ratio(kind.fg(), kind.bg()) >= 4.5,
                "{:?} foreground must contrast with its fill",
                kind
            );
        }
    }

    #[test]
    fn status_chip_uses_kind_foreground_on_label_span() {
        let spans = status_chip(ChipKind::Live);
        assert_eq!(spans[1].style.fg, Some(ChipKind::Live.fg()));
        assert_eq!(spans[1].style.bg, Some(ChipKind::Live.bg()));
    }

    fn contrast_ratio(fg: Color, bg: Color) -> f64 {
        let fg = relative_luminance(fg);
        let bg = relative_luminance(bg);
        (fg.max(bg) + 0.05) / (fg.min(bg) + 0.05)
    }

    fn relative_luminance(color: Color) -> f64 {
        let Color::Rgb(r, g, b) = color else {
            panic!("chip colours must be RGB constants");
        };
        let [r, g, b] = [r, g, b].map(|channel| {
            let channel = f64::from(channel) / 255.0;
            if channel <= 0.039_28 {
                channel / 12.92
            } else {
                ((channel + 0.055) / 1.055).powf(2.4)
            }
        });
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
