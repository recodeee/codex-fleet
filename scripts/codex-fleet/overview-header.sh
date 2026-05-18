#!/usr/bin/env bash
# overview-header.sh - retired compatibility shim.
#
# Plan codex-fleet-glass-menu-drop-tabstrip-2026-05-15 removed the
# standalone `fleet-tab-strip` Rust header pane. The iOS-style nav strip
# configured by style-tabs.sh (`status-position top` +
# window-status-format pills) is now the canonical nav surface. The status
# bar is visible on every window, so the dedicated header pane is no longer
# needed.
#
# Kept as a no-op for backwards-compat: anything still wired to call this
# (e.g. older operator runbooks, sibling sessions like codex-fleet-2.sh)
# just gets a clean log line and continues, instead of a hard error from
# the missing binary lookup.
#
# The old implementation first checked for an existing header pane before
# splitting the overview window:
#
#   tmux list-panes -t "$target" -F '#{@panel}' \
#     | grep -qFx '[codex-fleet-tab-strip]'
#
# This shim deliberately treats every invocation as the skip path: no binary
# lookup, no split-window/select-pane, and no pane @panel marker writes.
#
# Usage:
#   bash scripts/codex-fleet/overview-header.sh        # no-op, exits 0
set -eo pipefail

log() { printf '\033[36m[overview-header]\033[0m %s\n' "$*"; }

log "overview-header: tab strip removed (see plan codex-fleet-glass-menu-drop-tabstrip-2026-05-15)"
exit 0
