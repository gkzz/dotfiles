#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s HOME OUTPUT\n' "$0" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
home=${1%/}
output=$2

case "$home" in
  ''|/) printf 'error: HOME must be an absolute directory other than /: %s\n' "$1" >&2; exit 2 ;;
  /*) ;;
  *) printf 'error: HOME must be an absolute directory other than /: %s\n' "$1" >&2; exit 2 ;;
esac
[ -d "$home" ] && [ ! -L "$home" ] || {
  printf 'error: HOME must be an existing physical directory: %s\n' "$1" >&2
  exit 2
}
physical_home=$(cd "$home" && pwd -P)
[ "$physical_home" = "$home" ] || {
  printf 'error: HOME must not contain symlinked path components: %s\n' "$1" >&2
  exit 2
}

case "$output" in
  /*) ;;
  *) printf 'error: OUTPUT must be an absolute path: %s\n' "$output" >&2; exit 2 ;;
esac
output_parent=$(dirname "$output")
[ -d "$output_parent" ] || {
  printf 'error: OUTPUT parent must exist: %s\n' "$output_parent" >&2
  exit 2
}
physical_output_parent=$(cd "$output_parent" && pwd -P)
physical_output="$physical_output_parent/$(basename "$output")"
case "$physical_output" in
  "$physical_home"|"$physical_home"/*)
    printf 'error: OUTPUT must be outside HOME: %s\n' "$output" >&2
    exit 2
    ;;
esac

entry_list=$(mktemp "$physical_output_parent/.home-snapshot-entries.XXXXXX")
temporary_output=$(mktemp "$physical_output_parent/.home-snapshot-output.XXXXXX")
trap 'rm -f "$entry_list" "$temporary_output"' EXIT

find "$physical_home" -mindepth 1 -print0 >"$entry_list"

snapshot_helper="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" && pwd)/home-snapshot.js"
node "$snapshot_helper" "$physical_home" "$entry_list" >"$temporary_output"

mv "$temporary_output" "$physical_output"
rm -f "$entry_list"
trap - EXIT
