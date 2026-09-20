#!/usr/bin/env bash
set -euo pipefail

printf 'brew %s\n' "$*" >> "$HOME/calls"
case "${1:-}" in
  bundle)
    if [ "${2:-}" = "check" ]; then
      test -e "$HOME/.fake-brew-installed"
    else
      touch "$HOME/.fake-brew-installed"
    fi
    ;;
  # The fake output is evaluated by the caller, so keep PATH literal here.
  # shellcheck disable=SC2016
  shellenv) printf '%s\n' 'export PATH="$PATH"' ;;
  *) printf 'unexpected brew command: %s\n' "$*" >&2; exit 1 ;;
esac
