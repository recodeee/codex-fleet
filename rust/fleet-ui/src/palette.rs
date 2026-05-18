//! iOS system colour palette (dark UIKit variants).
//!
//! Ported from `scripts/codex-fleet/fleet-tick.sh`'s `IOS_*` block and the
//! `GLASS` object in the iOS terminal-design bundle. These RGB triples
//! are the source of truth for every chip / rail / card / overlay in the
//! fleet-ui crate, so port consumers reference them by name rather than
//! re-typing hex literals.
//!
//! Hex equivalents (Apple SwiftUI `.system*` names in parens):
//!
//! | Const               | Hex       | SwiftUI               |
//! |---------------------|-----------|-----------------------|
//! | `IOS_TINT`          | `#0a84ff` | `.systemBlue` (dark)  |
//! | `IOS_DESTRUCTIVE`   | `#ff453a` | `.systemRed` (dark)   |
//! | `IOS_GREEN`         | `#30d158` | `.systemGreen` (dark) |
//! | `IOS_ORANGE`        | `#ff9f0a` | `.systemOrange` (dark)|
//! | `IOS_YELLOW`        | `#ffd60a` | `.systemYellow` (dark)|
//! | `IOS_PURPLE`        | `#bf5af2` | `.systemPurple` (dark)|
//! | `IOS_FG`            | `#f2f2f7` | `.label` (dark)       |
//! | `IOS_FG_MUTED`      | `#a0a0aa` | `.secondaryLabel`     |
//! | `IOS_FG_FAINT`      | `#6e6e78` | `.tertiaryLabel`      |
//! | `IOS_BG_GLASS`      | `#262628` | `.menuBackground`     |
//! | `IOS_BG_SOLID`      | `#1c1c1e` | `.systemBackground`   |
//! | `IOS_HAIRLINE`      | `#3c3c41` | `.separator`          |
//! | `IOS_HAIRLINE_STRONG` | `#55555a` | `.opaqueSeparator`  |
//! | `IOS_HAIRLINE_BORDER` | `#3c3c41` | card border hairline|
//! | `IOS_CHIP_BG`       | `#36363a` | shortcut-chip fill    |
//! | `IOS_CARD_BG`       | `#2c2c30` | grouped section bg    |
//! | `IOS_ROW_BG_LIGHT`  | `#2c2c30` | alternating row fill  |
//! | `IOS_ROW_BG_DARK`   | `#262628` | alternating row fill  |
//! | `IOS_ICON_CHIP`     | `#46464c` | 30×30 icon tile bg    |
//! | `IOS_TINT_DARK`     | `#0764dc` | active-pill shadow    |
//! | `IOS_TINT_SUB`      | `#d2e0ff` | Top-Hit subtitle fg   |
//! | `IOS_CANVAS_BG`     | `#0b0d12` | dashboard canvas      |
//! | `IOS_TERMINAL_FG`   | `#c9d1d9` | transcript fg         |
//! | `IOS_TERMINAL_MUTED` | `#7d8590` | transcript muted fg  |
//! | `IOS_TERMINAL_BLUE` | `#58a6ff` | transcript link fg    |
//! | `IOS_FILL_04`       | `#15171b` | 4% white fill bucket  |
//! | `IOS_FILL_06`       | `#1a1c20` | 6% white fill bucket  |
//! | `IOS_FILL_08`       | `#1f2025` | 8% white fill bucket  |
//! | `IOS_HAIRLINE_ALPHA_14` | `#2d2f33` | 14% white hairline |
//! | `IOS_HAIRLINE_ALPHA_22` | `#414246` | 22% white hairline |
//! | `IOS_HAIRLINE_ALPHA_25` | `#484a4d` | 25% white hairline |
//! | `IOS_SUCCESS_SOFT`  | `#7adf95` | secondary success     |
//! | `IOS_WARNING_SOFT`  | `#ffc068` | secondary warning     |
//! | `IOS_WARNING_SOFT_BRIGHT` | `#ffe070` | bright warning   |
//! | `IOS_DANGER_SOFT`   | `#ff8a82` | secondary danger      |

use ratatui::style::Color;

// Accents
pub const IOS_TINT: Color = Color::Rgb(10, 132, 255);
pub const IOS_DESTRUCTIVE: Color = Color::Rgb(255, 69, 58);
pub const IOS_GREEN: Color = Color::Rgb(48, 209, 88);
pub const IOS_ORANGE: Color = Color::Rgb(255, 159, 10);
pub const IOS_YELLOW: Color = Color::Rgb(255, 214, 10);
pub const IOS_PURPLE: Color = Color::Rgb(191, 90, 242);

// Labels
pub const IOS_FG: Color = Color::Rgb(242, 242, 247);
pub const IOS_FG_MUTED: Color = Color::Rgb(160, 160, 170);
pub const IOS_FG_FAINT: Color = Color::Rgb(110, 110, 120);

// Surfaces
pub const IOS_BG_GLASS: Color = Color::Rgb(38, 38, 40);
pub const IOS_BG_SOLID: Color = Color::Rgb(28, 28, 30);
pub const IOS_HAIRLINE: Color = Color::Rgb(60, 60, 65);
pub const IOS_HAIRLINE_STRONG: Color = Color::Rgb(85, 85, 90);
pub const IOS_HAIRLINE_BORDER: Color = Color::Rgb(60, 60, 65);
pub const IOS_CHIP_BG: Color = Color::Rgb(54, 54, 58);
pub const IOS_CARD_BG: Color = Color::Rgb(44, 44, 48);
pub const IOS_ROW_BG_LIGHT: Color = Color::Rgb(44, 44, 48);
pub const IOS_ROW_BG_DARK: Color = Color::Rgb(38, 38, 40);
pub const IOS_ICON_CHIP: Color = Color::Rgb(70, 70, 76);

// Tint variants
pub const IOS_TINT_DARK: Color = Color::Rgb(7, 100, 220);
pub const IOS_TINT_SUB: Color = Color::Rgb(210, 224, 255);

// Design-token follow-up buckets
pub const IOS_CANVAS_BG: Color = Color::Rgb(11, 13, 18);
pub const IOS_TERMINAL_FG: Color = Color::Rgb(201, 209, 217);
pub const IOS_TERMINAL_MUTED: Color = Color::Rgb(125, 133, 144);
pub const IOS_TERMINAL_BLUE: Color = Color::Rgb(88, 166, 255);

// Opaque approximations of white-alpha fills over IOS_CANVAS_BG.
pub const IOS_FILL_04: Color = Color::Rgb(21, 23, 27);
pub const IOS_FILL_06: Color = Color::Rgb(26, 28, 32);
pub const IOS_FILL_08: Color = Color::Rgb(31, 32, 37);
pub const IOS_HAIRLINE_ALPHA: Color = Color::Rgb(45, 47, 51);
pub const IOS_HAIRLINE_ALPHA_14: Color = IOS_HAIRLINE_ALPHA;
pub const IOS_HAIRLINE_ALPHA_22: Color = Color::Rgb(65, 66, 70);
pub const IOS_HAIRLINE_ALPHA_25: Color = Color::Rgb(72, 74, 77);

// Softer status tones for larger fills and timeline/review accents.
pub const IOS_SUCCESS_SOFT: Color = Color::Rgb(122, 223, 149);
pub const IOS_WARNING_SOFT: Color = Color::Rgb(255, 192, 104);
pub const IOS_WARNING_SOFT_BRIGHT: Color = Color::Rgb(255, 224, 112);
pub const IOS_DANGER_SOFT: Color = Color::Rgb(255, 138, 130);

#[cfg(test)]
mod tests {
    use super::*;

    /// Hex-table parity guard. If any const drifts, this asserts which one.
    #[test]
    fn palette_hex_parity() {
        assert_eq!(
            IOS_TINT,
            Color::Rgb(0x0a, 0x84, 0xff),
            "IOS_TINT must be #0a84ff"
        );
        assert_eq!(
            IOS_DESTRUCTIVE,
            Color::Rgb(0xff, 0x45, 0x3a),
            "IOS_DESTRUCTIVE must be #ff453a"
        );
        assert_eq!(
            IOS_GREEN,
            Color::Rgb(0x30, 0xd1, 0x58),
            "IOS_GREEN must be #30d158"
        );
        assert_eq!(
            IOS_ORANGE,
            Color::Rgb(0xff, 0x9f, 0x0a),
            "IOS_ORANGE must be #ff9f0a"
        );
        assert_eq!(
            IOS_YELLOW,
            Color::Rgb(0xff, 0xd6, 0x0a),
            "IOS_YELLOW must be #ffd60a"
        );
        assert_eq!(
            IOS_PURPLE,
            Color::Rgb(0xbf, 0x5a, 0xf2),
            "IOS_PURPLE must be #bf5af2"
        );
        assert_eq!(
            IOS_FG,
            Color::Rgb(0xf2, 0xf2, 0xf7),
            "IOS_FG must be #f2f2f7"
        );
        assert_eq!(
            IOS_BG_SOLID,
            Color::Rgb(0x1c, 0x1c, 0x1e),
            "IOS_BG_SOLID must be #1c1c1e"
        );
        assert_eq!(
            IOS_HAIRLINE_BORDER,
            Color::Rgb(0x3c, 0x3c, 0x41),
            "IOS_HAIRLINE_BORDER must be #3c3c41"
        );
        assert_eq!(
            IOS_ROW_BG_LIGHT,
            Color::Rgb(0x2c, 0x2c, 0x30),
            "IOS_ROW_BG_LIGHT must be #2c2c30"
        );
        assert_eq!(
            IOS_ROW_BG_DARK,
            Color::Rgb(0x26, 0x26, 0x28),
            "IOS_ROW_BG_DARK must be #262628"
        );
        // Extended coverage: every constant that per-binary `ios_page_design.rs`
        // modules import via `palette::*`. If any drifts the migration loses
        // its canonical anchor.
        assert_eq!(
            IOS_FG_MUTED,
            Color::Rgb(0xa0, 0xa0, 0xaa),
            "IOS_FG_MUTED must be #a0a0aa"
        );
        assert_eq!(
            IOS_FG_FAINT,
            Color::Rgb(0x6e, 0x6e, 0x78),
            "IOS_FG_FAINT must be #6e6e78"
        );
        assert_eq!(
            IOS_BG_GLASS,
            Color::Rgb(0x26, 0x26, 0x28),
            "IOS_BG_GLASS must be #262628"
        );
        assert_eq!(
            IOS_HAIRLINE,
            Color::Rgb(0x3c, 0x3c, 0x41),
            "IOS_HAIRLINE must be #3c3c41"
        );
        assert_eq!(
            IOS_HAIRLINE_STRONG,
            Color::Rgb(0x55, 0x55, 0x5a),
            "IOS_HAIRLINE_STRONG must be #55555a"
        );
        assert_eq!(
            IOS_CHIP_BG,
            Color::Rgb(0x36, 0x36, 0x3a),
            "IOS_CHIP_BG must be #36363a"
        );
        assert_eq!(
            IOS_CARD_BG,
            Color::Rgb(0x2c, 0x2c, 0x30),
            "IOS_CARD_BG must be #2c2c30"
        );
        assert_eq!(
            IOS_ICON_CHIP,
            Color::Rgb(0x46, 0x46, 0x4c),
            "IOS_ICON_CHIP must be #46464c"
        );
        assert_eq!(
            IOS_TINT_DARK,
            Color::Rgb(0x07, 0x64, 0xdc),
            "IOS_TINT_DARK must be #0764dc"
        );
        assert_eq!(
            IOS_TINT_SUB,
            Color::Rgb(0xd2, 0xe0, 0xff),
            "IOS_TINT_SUB must be #d2e0ff"
        );
    }

    #[test]
    fn palette_design_gap_tokens() {
        let cases = [
            ("IOS_CANVAS_BG", IOS_CANVAS_BG, Color::Rgb(0x0b, 0x0d, 0x12)),
            (
                "IOS_TERMINAL_FG",
                IOS_TERMINAL_FG,
                Color::Rgb(0xc9, 0xd1, 0xd9),
            ),
            (
                "IOS_TERMINAL_MUTED",
                IOS_TERMINAL_MUTED,
                Color::Rgb(0x7d, 0x85, 0x90),
            ),
            (
                "IOS_TERMINAL_BLUE",
                IOS_TERMINAL_BLUE,
                Color::Rgb(0x58, 0xa6, 0xff),
            ),
            ("IOS_FILL_04", IOS_FILL_04, Color::Rgb(0x15, 0x17, 0x1b)),
            ("IOS_FILL_06", IOS_FILL_06, Color::Rgb(0x1a, 0x1c, 0x20)),
            ("IOS_FILL_08", IOS_FILL_08, Color::Rgb(0x1f, 0x20, 0x25)),
            (
                "IOS_HAIRLINE_ALPHA",
                IOS_HAIRLINE_ALPHA,
                Color::Rgb(0x2d, 0x2f, 0x33),
            ),
            (
                "IOS_HAIRLINE_ALPHA_14",
                IOS_HAIRLINE_ALPHA_14,
                Color::Rgb(0x2d, 0x2f, 0x33),
            ),
            (
                "IOS_HAIRLINE_ALPHA_22",
                IOS_HAIRLINE_ALPHA_22,
                Color::Rgb(0x41, 0x42, 0x46),
            ),
            (
                "IOS_HAIRLINE_ALPHA_25",
                IOS_HAIRLINE_ALPHA_25,
                Color::Rgb(0x48, 0x4a, 0x4d),
            ),
            (
                "IOS_SUCCESS_SOFT",
                IOS_SUCCESS_SOFT,
                Color::Rgb(0x7a, 0xdf, 0x95),
            ),
            (
                "IOS_WARNING_SOFT",
                IOS_WARNING_SOFT,
                Color::Rgb(0xff, 0xc0, 0x68),
            ),
            (
                "IOS_WARNING_SOFT_BRIGHT",
                IOS_WARNING_SOFT_BRIGHT,
                Color::Rgb(0xff, 0xe0, 0x70),
            ),
            (
                "IOS_DANGER_SOFT",
                IOS_DANGER_SOFT,
                Color::Rgb(0xff, 0x8a, 0x82),
            ),
        ];

        for (name, actual, expected) in cases {
            assert_eq!(
                actual, expected,
                "{name} must stay anchored to docs/design-tokens.md"
            );
        }
    }
}
