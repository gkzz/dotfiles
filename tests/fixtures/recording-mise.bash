#!/usr/bin/env bash
set -euo pipefail

: "${DOTFILES_REAL_MISE:?DOTFILES_REAL_MISE is required}"
: "${DOTFILES_MISE_CALLS:?DOTFILES_MISE_CALLS is required}"

{
  printf '%s\n' 'call:'
  printf 'arg=%s\n' "$@"
} >> "$DOTFILES_MISE_CALLS"

exec "$DOTFILES_REAL_MISE" "$@"
