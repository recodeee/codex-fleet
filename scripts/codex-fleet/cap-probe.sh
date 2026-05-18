#!/usr/bin/env bash
# cap-probe — verify each candidate codex account is actually usable.
# Remembers per-account verdict + reset timestamp; skips re-probing an
# account known to be capped until its reset time has actually arrived.
#
# Cache format: /tmp/claude-viz/cap-probe-cache/<email>.json
#   {"verdict":"healthy"|"capped",
#    "until_epoch": <unix-ts or 0 for healthy/unknown>,
#    "until_text": "May 27th, 2026 12:43 PM",
#    "probed_at": <unix-ts>}
#
# Cache policy:
#   - healthy:  re-probe after CACHE_TTL_HEALTHY (default 300s)
#   - capped:   skip until until_epoch; once past it, drop to unknown
#   - unknown:  re-probe after CACHE_TTL_UNKNOWN (default 120s)
#
# Usage: bash cap-probe.sh <need_n> email1 email2 ...
set -eo pipefail

NEED="${1:-1}"; shift

CACHE_DIR="${CACHE_DIR:-/tmp/claude-viz/cap-probe-cache}"
# F2 — Cap-cache TTL hardening. Live FLEET_ID=3 observation: first bringup
# found 5/6 healthy; a fresh `--no-cap-cache` probe ~5min later found 8/8.
# The 300s healthy TTL outlived actual quota recovery, leaving the pool
# falsely thin. Drop default healthy TTL to 60s. Operators can pin a
# different TTL via CODEX_FLEET_CAP_CACHE_TTL without touching the script.
# Also: if the bringup-failure marker exists, treat cache as cold and
# re-probe regardless of age — a prior failed bringup is exactly the
# moment when stale cache is most dangerous.
CACHE_TTL_HEALTHY="${CACHE_TTL_HEALTHY:-${CODEX_FLEET_CAP_CACHE_TTL:-60}}"
# Re-probe "unknown" verdicts after 60s instead of 120s; an unknown is
# usually a one-off timeout, not a stable state, and we don't want the
# pool to look empty for 2 minutes after a single transient probe miss.
CACHE_TTL_UNKNOWN="${CACHE_TTL_UNKNOWN:-60}"
BRINGUP_FAILURE_MARKER="${BRINGUP_FAILURE_MARKER:-/tmp/claude-viz/bringup-failure.marker}"
if [ -f "$BRINGUP_FAILURE_MARKER" ]; then
  # Force a cold probe on the next run by zeroing the healthy TTL.
  # cache_check still serves capped accounts (because until_epoch >> now)
  # but treats healthy/unknown as stale.
  CACHE_TTL_HEALTHY=0
  CACHE_TTL_UNKNOWN=0
fi
# A healthy `codex exec ping` round-trip takes 30-60s under MCP-server
# boot + first model token. The previous 15s default timed out every
# probe as "unknown" during the May 14 stall, leaving the cap-swap
# daemon with 0 candidates while every account was actually healthy.
PROBE_TIMEOUT="${PROBE_TIMEOUT:-60}"
mkdir -p "$CACHE_DIR"
LOG="${LOG:-/tmp/claude-viz/cap-probe.log}"
mkdir -p "$(dirname "$LOG")"

ts() { date +%H:%M:%S; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

source "$(dirname "${BASH_SOURCE[0]}")/lib/agents.sh"

# Returns one of: healthy | capped | stale (re-probe).
# Sets globals VERDICT, UNTIL_TEXT, UNTIL_EPOCH for the caller.
cache_check() {
  local email="$1" cf="$CACHE_DIR/${email}.json"
  VERDICT=""; UNTIL_TEXT=""; UNTIL_EPOCH=0
  [ -f "$cf" ] || return 1
  local now=$(date +%s)
  read VERDICT UNTIL_EPOCH UNTIL_TEXT < <(python3 -c "
import json, sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    print('stale 0 ',end=''); sys.exit()
v=d.get('verdict','unknown')
ut=d.get('until_epoch',0) or 0
pa=d.get('probed_at',0) or 0
print(f\"{v} {ut} {d.get('until_text','')}\")
" "$cf")
  case "$VERDICT" in
    healthy)
      local age=$((now - $(stat -c %Y "$cf" 2>/dev/null || echo 0)))
      [ "$age" -lt "$CACHE_TTL_HEALTHY" ] && return 0
      return 1 ;;
    capped)
      if [ "$UNTIL_EPOCH" -gt "$now" ]; then return 0; fi
      return 1 ;;
    *)
      local age=$((now - $(stat -c %Y "$cf" 2>/dev/null || echo 0)))
      [ "$age" -lt "$CACHE_TTL_UNKNOWN" ] && return 0
      return 1 ;;
  esac
}

cache_write() {
  python3 -c "
import json, sys, os
email, verdict, until_text = sys.argv[1], sys.argv[2], sys.argv[3]
until_epoch = int(sys.argv[4])
cf = f'$CACHE_DIR/{email}.json'
import time
json.dump({'verdict': verdict, 'until_epoch': until_epoch, 'until_text': until_text, 'probed_at': int(time.time())},
          open(cf, 'w'))
" "$1" "$2" "$3" "$4"
}

stage_probe_home() {
  local id="$1" email="$2" d="/tmp/codex-fleet/$id"
  if [ ! -f "$d/auth.json" ]; then
    mkdir -p "$d"
    cp "$HOME/.codex/accounts/$email.json" "$d/auth.json"
    chmod 600 "$d/auth.json"
    [ -e "$d/config.toml" ] || ln -s "$HOME/.codex/config.toml" "$d/config.toml"
  fi
}

# Parse a codex "try again at <DATE>" message into a unix epoch using python's dateutil
parse_until() {
  local txt="$1"
  python3 -c "
import sys, re, datetime, time, calendar
m = re.search(r'try again at ([A-Z][a-z]+ \d+\w*, \d+ \d+:\d+ [AP]M)', sys.argv[1])
if not m: print(0); sys.exit()
s = m.group(1)
# strip the ordinal suffix in date (e.g. May 27th -> May 27)
s = re.sub(r'(\d+)(st|nd|rd|th)', r'\1', s)
try:
    dt = datetime.datetime.strptime(s, '%B %d, %Y %I:%M %p')
    print(int(time.mktime(dt.timetuple())))
except Exception:
    print(0)
" "$txt"
}

probe_one() {
  local email="$1" id out verdict until_text="" until_epoch=0
  id=$(email_to_id "$email")
  stage_probe_home "$id" "$email"
  out=$(timeout "$PROBE_TIMEOUT" \
    env CODEX_GUARD_BYPASS=1 \
        CODEX_HOME="/tmp/codex-fleet/$id" \
        codex exec --skip-git-repo-check "ping" 2>&1) || true
  if printf '%s' "$out" | grep -qE "You've hit your usage limit|Rate limit reached|429"; then
    verdict="capped"
    until_text=$(printf '%s' "$out" | grep -oE "try again at [^.]+" | head -1 | sed 's/^try again at //')
    until_epoch=$(parse_until "$out")
  elif printf '%s' "$out" | grep -qE "^codex$|tokens used"; then
    verdict="healthy"
  else
    verdict="unknown"
  fi
  cache_write "$email" "$verdict" "$until_text" "$until_epoch"
  echo "$verdict" > "$TMPDIR_PROBE/$email.verdict"
  if [ "$verdict" = "capped" ]; then
    log "probe $email -> capped (until $until_text / epoch $until_epoch)"
  else
    log "probe $email -> $verdict"
  fi
}

DECISIONS=()
TO_PROBE=()
for email in "$@"; do
  if cache_check "$email"; then
    DECISIONS+=("$email $VERDICT")
    if [ "$VERDICT" = "capped" ]; then
      log "cache HIT capped: $email (until $UNTIL_TEXT)"
    else
      log "cache HIT $VERDICT: $email"
    fi
  else
    TO_PROBE+=("$email")
  fi
done

if [ "${#TO_PROBE[@]}" -gt 0 ]; then
  TMPDIR_PROBE=$(mktemp -d); export TMPDIR_PROBE
  log "probing ${#TO_PROBE[@]} fresh candidates (timeout=${PROBE_TIMEOUT}s, parallel)"
  declare -A PIDS
  for email in "${TO_PROBE[@]}"; do
    probe_one "$email" &
    PIDS["$email"]=$!
  done
  for email in "${TO_PROBE[@]}"; do
    wait "${PIDS[$email]}" || true
  done
  for email in "${TO_PROBE[@]}"; do
    v=$(cat "$TMPDIR_PROBE/$email.verdict" 2>/dev/null || echo unknown)
    DECISIONS+=("$email $v")
  done
  rm -rf "$TMPDIR_PROBE"
fi

# Emit healthy emails (up to NEED), preserving input order
declare -A SEEN
n=0
for email in "$@"; do
  for d in "${DECISIONS[@]}"; do
    de="${d% *}"; dv="${d#* }"
    if [ "$de" = "$email" ] && [ "$dv" = "healthy" ] && [ -z "${SEEN[$email]}" ]; then
      SEEN["$email"]=1
      echo "$email"
      n=$((n + 1))
      [ "$n" -ge "$NEED" ] && break 2
    fi
  done
done

if [ "$n" -lt "$NEED" ]; then
  echo "[cap-probe] only $n/$NEED healthy accounts (capped or unknown skipped); see $LOG" >&2
  exit 3
fi
