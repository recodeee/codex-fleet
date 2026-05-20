#!/usr/bin/env bash
# version.sh — shared --help / --version plumbing for codex-fleet scripts.
#
# Source via:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/version.sh"
#
# Exports:
#   FLEET_VERSION              version string (env override > nearest git tag > "0.0.0-dev")
#   print_usage_and_exit USAGE print USAGE to stdout and exit 0
#   handle_help_version_flags  scan "$@" for --help/-h/--version; if found,
#                              print the appropriate banner and exit 0
#
# Conventions:
#   - Scripts pre-set FLEET_USAGE (a heredoc string) before sourcing or before
#     calling handle_help_version_flags.
#   - $0's basename is used in the --version banner.

# Resolve FLEET_VERSION once per process. Env wins so CI can pin without git.
if [ -z "${FLEET_VERSION:-}" ]; then
  _fleet_version_git=""
  if command -v git >/dev/null 2>&1; then
    _fleet_version_git=$(git -C "$(dirname "${BASH_SOURCE[0]}")" describe --tags --abbrev=0 2>/dev/null || true)
  fi
  if [ -n "$_fleet_version_git" ]; then
    FLEET_VERSION="$_fleet_version_git"
  else
    FLEET_VERSION="0.0.0-dev"
  fi
  unset _fleet_version_git
fi
export FLEET_VERSION

print_usage_and_exit() {
  printf '%s\n' "$1"
  exit 0
}

# Scan args for --help/-h or --version and act on the first match.
# Callers MUST set FLEET_USAGE before invoking. Returns silently if no match
# so the host script keeps processing its real flags.
handle_help_version_flags() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        print_usage_and_exit "${FLEET_USAGE:-no usage text provided}"
        ;;
      --version)
        printf '%s %s\n' "$(basename "$0")" "$FLEET_VERSION"
        exit 0
        ;;
    esac
  done
}
