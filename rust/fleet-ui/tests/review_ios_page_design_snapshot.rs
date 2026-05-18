mod palette {
    pub use fleet_ui::palette::*;
}

#[path = "../src/review_ios_page_design.rs"]
mod review_ios_page_design;

use ratatui::{backend::TestBackend, layout::Rect, Terminal};
use review_ios_page_design::{AuthLevel, LiveIndicator, ReviewIosPageDesign, ReviewRisk};

fn render_page(widget: ReviewIosPageDesign<'_>, width: u16, height: u16) -> String {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
    terminal
        .draw(|frame| frame.render_widget(widget.clone(), frame.area()))
        .unwrap();
    format!("{}", terminal.backend())
}

fn render_indicator(indicator: LiveIndicator) -> String {
    let mut terminal = Terminal::new(TestBackend::new(48, 3)).unwrap();
    terminal
        .draw(|frame| frame.render_widget(indicator, Rect::new(1, 1, 46, 1)))
        .unwrap();
    format!("{}", terminal.backend())
}

#[test]
fn pending_review_card() {
    let out = render_page(ReviewIosPageDesign::demo_pending(), 132, 32);

    assert!(out.contains("REV-142"), "{out}");
    assert!(out.contains("AUTO-REVIEWER RATIONALE"), "{out}");
    assert!(out.contains("FILES TOUCHED"), "{out}");
    assert!(out.contains("[A] approve"), "{out}");
    assert!(out.contains("RECENT DECISIONS"), "{out}");
    insta::assert_snapshot!(out);
}

#[test]
fn empty_queue() {
    let out = render_page(ReviewIosPageDesign::demo_empty(), 92, 26);

    assert!(out.contains("queue clear"), "{out}");
    assert!(out.contains("auto-reviewer caught up"), "{out}");
    insta::assert_snapshot!(out);
}

#[test]
fn fresh_and_stale_ticks() {
    let fresh = render_indicator(LiveIndicator::from_age_secs(0, 2));
    let stale = render_indicator(LiveIndicator::from_age_secs(2, 44));
    let out = format!("{fresh}\n---\n{stale}");

    assert!(out.contains("● auto-reviewer on · last 2s"), "{out}");
    assert!(out.contains("◎ auto-reviewer on · last 44s"), "{out}");
    insta::assert_snapshot!(out);
}

#[test]
fn pill_colors_match_ios_spec() {
    assert_eq!(
        ReviewRisk::Low.color(),
        ratatui::style::Color::Rgb(0x34, 0xc7, 0x59)
    );
    assert_eq!(
        ReviewRisk::Medium.color(),
        ratatui::style::Color::Rgb(0xff, 0x95, 0x00)
    );
    assert_eq!(
        ReviewRisk::High.color(),
        ratatui::style::Color::Rgb(0xff, 0x3b, 0x30)
    );
    assert_eq!(
        AuthLevel::High.color(),
        ratatui::style::Color::Rgb(0x00, 0x7a, 0xff)
    );
    assert_eq!(
        AuthLevel::Low.color(),
        ratatui::style::Color::Rgb(0x34, 0xc7, 0x59)
    );
}
