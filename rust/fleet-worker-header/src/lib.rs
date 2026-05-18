//! Library facade for `fleet-worker-header`.
//!
//! The binary ([`main.rs`](../bin/fleet-worker-header)) drives the renderer
//! over IO; tests and downstream crates import the pure renderer from here.

pub mod render;

pub use render::{format_age, render, CapState, HeaderState};
