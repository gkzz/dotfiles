#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/fixtures/setup.bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/setup.bash"

fail() {
  printf 'test failed: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -F "$expected" "$file" >/dev/null || fail "missing '$expected' in $file"
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if [ -e "$file" ] && grep -F "$unexpected" "$file" >/dev/null; then
    fail "unexpected '$unexpected' in $file"
  fi
}

assert_exit_2() {
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  [ "$status" -eq 2 ] || fail "expected exit 2, got $status: $*"
}

assert_exit_1() {
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  [ "$status" -eq 1 ] || fail "expected exit 1, got $status: $*"
}

assert_before() {
  local file="$1"
  local first="$2"
  local second="$3"
  local first_line
  local second_line
  first_line="$(grep -n -m 1 -F "$first" "$file" | cut -d: -f1)"
  second_line="$(grep -n -m 1 -F "$second" "$file" | cut -d: -f1)"
  [ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ] ||
    fail "'$first' did not precede '$second' in $file"
}

path_glob_exists() {
  compgen -G "$1" >/dev/null
}

permission_bits() {
  # The test paths are controlled mktemp descendants; ls is portable across GNU/BSD.
  # shellcheck disable=SC2012
  LC_ALL=C ls -ld "$1" | awk '{print $1}'
}
