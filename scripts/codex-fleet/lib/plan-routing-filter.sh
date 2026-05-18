#!/usr/bin/env bash
# shellcheck shell=bash
#
# plan-routing-filter.sh — auto-derive CODEX_FLEET_SPECIALTY for the active
# fleet bringup so workers do not get routed into stale plans whose
# writable_roots fall outside the codex-fleet repo family.
#
# Observed pain point (2026-05-18 03:30 UTC+2): when a fleet was brought up
# on a plan whose metadata.writable_roots pointed at /home/deadpool/Documents/polymarket-cli
# (a foreign repo), Colony's task_ready_for_agent matchmaker still ranked
# older codex-fleetui plans higher. Workers got routed onto those stale
# plans, failed the writable-root preflight, posted BLOCKED, and looped.
#
# Fix: when the priority plan's writable_roots is "foreign" (outside the
# codex-fleet repo family — i.e. not /home/deadpool/Documents/codex-fleetui
# and not /home/deadpool/Documents/recodee), force every worker's
# CODEX_FLEET_SPECIALTY to the priority plan slug. The worker prompt's
# "Tier + specialty gate" then auto-skips any non-matching plan.
#
# Usage (sourceable):
#   . scripts/codex-fleet/lib/plan-routing-filter.sh
#   value="$(compute_specialty "<plan_slug>" "<path-to-plan.json>")"
#   # echoes the value to export as CODEX_FLEET_SPECIALTY (may be empty).
#
# Precedence (highest wins):
#   1. CODEX_FLEET_SPECIALTY already non-empty in the environment → respect it.
#   2. metadata.writable_roots includes a path under codex-fleetui or recodee
#      → echo empty (generalist mode is correct; matchmaker can route across
#      all fleet-family plans).
#   3. Otherwise → echo the plan_slug (force matchmaker to only return tasks
#      from this slug).
#
# Dependencies: bash, python3 (for JSON parsing; jq is also available but
# python3 keeps this self-contained alongside the rest of full-bringup.sh).

# Roots that count as "fleet-family". Plans whose writable_roots include
# any path under one of these are allowed to run in generalist mode.
PLAN_ROUTING_FLEET_FAMILY_ROOTS=(
    "/home/deadpool/Documents/codex-fleetui"
    "/home/deadpool/Documents/recodee"
)

# compute_specialty <plan_slug> <plan_json_path>
# Echoes the value to set CODEX_FLEET_SPECIALTY to (possibly empty).
compute_specialty() {
    local plan_slug="$1"
    local plan_json="$2"

    if [ -z "$plan_slug" ]; then
        return 1
    fi
    if [ ! -f "$plan_json" ]; then
        return 1
    fi

    # User-set CODEX_FLEET_SPECIALTY wins.
    if [ -n "${CODEX_FLEET_SPECIALTY:-}" ]; then
        printf '%s' "$CODEX_FLEET_SPECIALTY"
        return 0
    fi

    local family_list
    family_list=$(printf '%s\n' "${PLAN_ROUTING_FLEET_FAMILY_ROOTS[@]}")

    local is_family
    is_family=$(PLAN_FILE="$plan_json" FAMILY="$family_list" python3 - <<'PY'
import json, os, sys

p = os.environ["PLAN_FILE"]
family = [l for l in os.environ.get("FAMILY", "").splitlines() if l.strip()]
try:
    with open(p) as f:
        data = json.load(f)
except Exception:
    print("0")
    sys.exit(0)

roots = ((data.get("metadata") or {}).get("writable_roots") or [])
hit = 0
for r in roots:
    if not isinstance(r, str):
        continue
    rn = r.rstrip("/")
    for fam in family:
        fn = fam.rstrip("/")
        if rn == fn or rn.startswith(fn + "/"):
            hit = 1
            break
    if hit:
        break
print(hit)
PY
)

    if [ "$is_family" = "1" ]; then
        # Fleet-family writable_roots — generalist mode is correct.
        printf ''
        return 0
    fi

    # Foreign writable_roots — pin matchmaker to this plan only.
    printf '%s' "$plan_slug"
    return 0
}
