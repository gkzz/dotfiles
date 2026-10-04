#!/usr/bin/env bash
set -euo pipefail

repository_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

case "$(uname -s)" in
  Linux*)
    for brew_bin in /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/sbin; do
      [ ! -d "$brew_bin" ] || PATH="$brew_bin:$PATH"
    done
    ;;
  Darwin*)
    for brew_bin in /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin /usr/local/sbin; do
      [ ! -d "$brew_bin" ] || PATH="$brew_bin:$PATH"
    done
    ;;
esac
PATH="$HOME/.local/bin:$PATH"
export PATH

if ! command -v brew >/dev/null 2>&1; then
  command -v git >/dev/null 2>&1 || {
    printf '%s\n' 'error: git is required to install Homebrew; install Git first, then rerun setup' >&2
    exit 1
  }
  command -v curl >/dev/null 2>&1 || { printf 'error: curl is required to install Homebrew\n' >&2; exit 1; }
  [ -x /bin/bash ] || { printf 'error: /bin/bash is required to install Homebrew\n' >&2; exit 1; }

  # Homebrew's official installer is published at a moving HEAD URL.
  installer="$(curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  NONINTERACTIVE=1 /bin/bash -c "$installer"
fi
command -v brew >/dev/null 2>&1 || {
  printf '%s\n' 'error: Homebrew was not found after installation' >&2
  exit 1
}

if [ ! -d "$repository_path/.git" ]; then
  printf 'error: run setup from a Git checkout: %s\n' "$repository_path" >&2
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  "$repository_path/setup/mise-install.sh" --apply
  PATH="$HOME/.local/bin:$PATH"
  export PATH
fi
