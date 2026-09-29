#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-lifecycle.XXXXXX")" && pwd -P)"
trap 'rm -rf "$test_root"' EXIT

if ! command -v mise >/dev/null 2>&1; then
  printf '%s\n' 'test failed: pinned mise is required for the dotfiles lifecycle boundary test' >&2
  exit 1
fi

real_mise="$(command -v mise)"
recording_bin="$test_root/bin"
calls="$test_root/mise-calls"
mkdir -p "$recording_bin"
ln -s "$DOTFILES/tests/fixtures/recording-mise.bash" "$recording_bin/mise"
: > "$calls"

export DOTFILES DOTFILES_REAL_MISE="$real_mise" DOTFILES_MISE_CALLS="$calls"
export PATH="$recording_bin:$PATH"
export DOTFILES_SKIP_BREW=1

run_dotfiles_expect_failure() {
  local case_home="$1"
  local config_home="$2"
  local expected="$3"
  shift 3
  if HOME="$case_home" XDG_CONFIG_HOME="$config_home" \
    XDG_STATE_HOME="$case_home/state" MISE_DATA_DIR="$test_root/data" \
    MISE_CACHE_DIR="$test_root/cache" MISE_STATE_DIR="$case_home/mise-state" \
    "$DOTFILES/bin/dotfiles" "$@" >"$test_root/stdout" 2>"$test_root/stderr"; then
    printf 'test failed: command unexpectedly succeeded: %s\n' "$*" >&2
    exit 1
  fi
  if ! grep -F "$expected" "$test_root/stderr" >/dev/null; then
    printf 'test failed: expected diagnostic not found: %s\n' "$expected" >&2
    cat "$test_root/stderr" >&2
    exit 1
  fi
}

assert_unmanaged_targets_absent() {
  local case_home="$1"
  local config_home="$2"
  test ! -e "$case_home/.dotfiles"
  test ! -L "$case_home/.dotfiles"
  test ! -e "$case_home/.bash_profile"
  test ! -L "$case_home/.bash_profile"
  test ! -e "$case_home/.gitconfig"
  test ! -L "$case_home/.gitconfig"
  test ! -e "$config_home/mise/config.toml"
  test ! -L "$config_home/mise/config.toml"
}

# 後段のtargetで競合しても、先行targetを部分適用しない。
conflict_home="$test_root/conflict-home"
conflict_config="$conflict_home/config"
mkdir -p "$conflict_home"
printf '%s\n' 'user gitconfig' > "$conflict_home/.gitconfig"
run_dotfiles_expect_failure "$conflict_home" "$conflict_config" '.gitconfig' install --apply --skip-brew
test "$(cat "$conflict_home/.gitconfig")" = 'user gitconfig'
test ! -e "$conflict_home/.dotfiles" && test ! -L "$conflict_home/.dotfiles"
test ! -e "$conflict_home/.bashrc" && test ! -L "$conflict_home/.bashrc"
test ! -e "$conflict_home/.bash_profile" && test ! -L "$conflict_home/.bash_profile"
test ! -e "$conflict_config/mise/config.toml" && test ! -L "$conflict_config/mise/config.toml"

# XDG targetの親にあるsymlinkを、変更操作が越えない。
parent_home="$test_root/parent-home"
external="$test_root/external"
mkdir -p "$parent_home" "$external"
printf '%s\n' 'outside remains unchanged' > "$external/marker"
ln -s "$external" "$parent_home/config-link"
linked_config="$parent_home/config-link/xdg"
traversal_config="$parent_home/config-link/../xdg"
for operation in install uninstall; do
  for mode in --dry-run --apply; do
    args=("$operation" "$mode")
    if [ "$operation" = install ]; then args+=(--skip-brew); fi
    run_dotfiles_expect_failure "$parent_home" "$linked_config" 'must not be a symlink' "${args[@]}"
    run_dotfiles_expect_failure "$parent_home" "$traversal_config" 'must not contain ..' "${args[@]}"
  done
done
test "$(cat "$external/marker")" = 'outside remains unchanged'
external_entries=("$external"/*)
test "${#external_entries[@]}" -eq 1
test "${external_entries[0]}" = "$external/marker"
assert_unmanaged_targets_absent "$parent_home" "$linked_config"

# The wrapper must never pass mise's destructive --force option.
if grep -Fx 'arg=--force' "$calls" >/dev/null; then
  printf '%s\n' 'test failed: --force was passed to mise' >&2
  exit 1
fi

printf '%s\n' 'dotfiles lifecycle boundary test passed'
