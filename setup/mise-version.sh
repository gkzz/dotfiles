#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="$repository_root/.config/mise/config.toml"
version="$(sed -n 's/^min_version = "\([^"]*\)"$/\1/p' "$config_file")"

if [ -z "$version" ] || [[ "$version" == *$'\n'* ]]; then
  printf 'error: expected exactly one min_version in mise config: %s\n' "$config_file" >&2
  exit 1
fi

printf '%s\n' "$version"
