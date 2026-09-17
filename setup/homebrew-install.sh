#!/usr/bin/env bash
set -euo pipefail

mode="${1:---dry-run}"
case "$mode" in
  --dry-run) ;;
  --apply) ;;
  -h|--help)
    printf '%s\n' 'usage: ./setup/homebrew-install.sh [--dry-run|--apply]'
    exit 0
    ;;
  *) printf '%s\n' 'usage: ./setup/homebrew-install.sh [--dry-run|--apply]' >&2; exit 2 ;;
esac

if [ "$mode" = "--dry-run" ]; then
  printf '%s\n' 'plan: bootstrap_homebrew'
  exit 0
fi

command -v curl >/dev/null 2>&1 || { printf 'error: curl is required\n' >&2; exit 1; }
[ -x /bin/bash ] || { printf 'error: /bin/bash is required\n' >&2; exit 1; }

# Homebrew's official install command uses HEAD; keep the same URL intentionally.
installer="$(curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
NONINTERACTIVE=1 /bin/bash -c "$installer"
