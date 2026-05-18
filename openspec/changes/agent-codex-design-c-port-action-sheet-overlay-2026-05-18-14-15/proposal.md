## Why

- The design-match lane needs a reusable fleet-ui action sheet matching the design-C grouped/cancel surface so later integration can open destructive or contextual pane actions without editing the overlay monolith.

## What Changes

- Adds `fleet_ui::action_sheet_overlay` with grouped action rows, warning/destructive tones, selected-row state, bottom anchoring, a separate cancel card, hairline dividers, and a focused inline snapshot test.
- Exports the module from `fleet-ui/src/lib.rs`.

## Impact

- Affects only the shared `fleet-ui` crate. The new module is not wired into runtime binaries in this lane.
- Verification: `RUSTC_WRAPPER= cargo test -p fleet-ui --lib`.
