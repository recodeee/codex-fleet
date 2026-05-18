#!/usr/bin/env bash
# overview-header.sh — RETIRED.
#
# This script used to split the overview window to host an in-binary
# `fleet-tab-strip` Rust header pane. That crate was retired in PR #107;
# the iOS-style nav strip configured by style-tabs.sh
# (`status-position top` + window-status-format pills) is now the single
# canonical nav surface. The status bar is visible on every window — not
# just overview — so the dedicated header pane is no longer needed.
#
# Kept as a no-op for backwards-compat: anything still wired to call this
# (e.g. older operator runbooks, sibling sessions like codex-fleet-2.sh)
# just gets a clean log line and continues, instead of a hard error from
# the missing binary lookup.
#
# Usage:
#   bash scripts/codex-fleet/overview-header.sh        # no-op, exits 0
set -eo pipefail

log() { printf '\033[36m[overview-header]\033[0m %s\n' "$*"; }

log "no-op (fleet-tab-strip retired PR #107) — tmux status bar owns the nav now (see style-tabs.sh)"
exit 0
