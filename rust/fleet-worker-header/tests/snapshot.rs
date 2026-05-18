//! Snapshot tests for the renderer at widths 60, 80, 120 for three fleet
//! states: idle, working-on-task, capped-429. Insta captures the rendered
//! line verbatim so any future change to layout, glyphs, or truncation
//! produces a visible diff.

use fleet_worker_header::{render, CapState, HeaderState};

fn idle() -> HeaderState {
    HeaderState {
        agent_name: "codex-zazrifka".into(),
        tier: "high".into(),
        task_title: None,
        last_activity_age_secs: None,
        cap: CapState::Ok,
    }
}

fn working() -> HeaderState {
    HeaderState {
        agent_name: "codex-zazrifka".into(),
        tier: "high".into(),
        task_title: Some("TE-2 src/edge module tree stubs".into()),
        last_activity_age_secs: Some(134),
        cap: CapState::Ok,
    }
}

fn capped_429() -> HeaderState {
    HeaderState {
        agent_name: "codex-pyrit".into(),
        tier: "medium".into(),
        task_title: Some("SI-3 retry colony plan publish with --auto-archive".into()),
        last_activity_age_secs: Some(420),
        cap: CapState::RateLimited,
    }
}

#[test]
fn snapshot_idle_60() {
    insta::assert_snapshot!(render(&idle(), 60));
}

#[test]
fn snapshot_idle_80() {
    insta::assert_snapshot!(render(&idle(), 80));
}

#[test]
fn snapshot_idle_120() {
    insta::assert_snapshot!(render(&idle(), 120));
}

#[test]
fn snapshot_working_60() {
    insta::assert_snapshot!(render(&working(), 60));
}

#[test]
fn snapshot_working_80() {
    insta::assert_snapshot!(render(&working(), 80));
}

#[test]
fn snapshot_working_120() {
    insta::assert_snapshot!(render(&working(), 120));
}

#[test]
fn snapshot_capped_60() {
    insta::assert_snapshot!(render(&capped_429(), 60));
}

#[test]
fn snapshot_capped_80() {
    insta::assert_snapshot!(render(&capped_429(), 80));
}

#[test]
fn snapshot_capped_120() {
    insta::assert_snapshot!(render(&capped_429(), 120));
}
