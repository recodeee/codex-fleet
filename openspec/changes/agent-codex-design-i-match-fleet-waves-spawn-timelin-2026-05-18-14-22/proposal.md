## Why

The fleet-waves dashboard needs to match the design-I spawn timeline reference more closely so operators can scan wave sequencing, task completion, and agent assignment in one pass.

## What Changes

- Polish `rust/fleet-waves/src/main.rs` Gantt rows with proportional timeline bars.
- Add timeline tick markers and right-side `TASKS` / `AGENTS` columns.
- Add an active-wave shimmer sweep and regression coverage for active-wave and proportional-width helpers.

## Impact

Risk is limited to the `fleet-waves` TUI binary. Verification is `RUSTC_WRAPPER= cargo test -p fleet-waves`.
