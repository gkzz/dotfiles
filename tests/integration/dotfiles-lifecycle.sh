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

read_dotfiles_env() (
  local config="$1"
  local variable_name
  local config_root
  config_root="$(dirname "$config")"
  for variable_name in ${!MISE_@}; do
    unset "$variable_name"
  done
  MISE_CONFIG_DIR="$test_root/empty-config" \
    MISE_SYSTEM_CONFIG_DIR="$test_root/empty-system" \
    MISE_GLOBAL_CONFIG_FILE="$config" \
    MISE_CEILING_PATHS="$config_root" \
    MISE_OVERRIDE_CONFIG_FILENAMES=.dotfiles-no-project-config.toml \
    MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES=none \
    MISE_NO_HOOKS=1 \
    "$real_mise" --cd "$config_root" env --json
)

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

# A regular-file conflict must stop before any other target is applied.
conflict_home="$test_root/conflict-home"
conflict_config="$conflict_home/config"
mkdir -p "$conflict_home"
printf '%s\n' 'user bashrc' > "$conflict_home/.bashrc"
run_dotfiles_expect_failure "$conflict_home" "$conflict_config" '.bashrc' install --dry-run --skip-brew
test "$(cat "$conflict_home/.bashrc")" = 'user bashrc'
assert_unmanaged_targets_absent "$conflict_home" "$conflict_config"
run_dotfiles_expect_failure "$conflict_home" "$conflict_config" '.bashrc' install --apply --skip-brew
test "$(cat "$conflict_home/.bashrc")" = 'user bashrc'
assert_unmanaged_targets_absent "$conflict_home" "$conflict_config"

# A symlink in an XDG target parent must reject every mutating lifecycle path.
parent_home="$test_root/parent-home"
external="$test_root/external"
mkdir -p "$parent_home" "$external"
printf '%s\n' 'outside remains unchanged' > "$external/marker"
ln -s "$external" "$parent_home/config-link"
linked_config="$parent_home/config-link/xdg"
run_dotfiles_expect_failure "$parent_home" "$linked_config" 'must not be a symlink' install --dry-run --skip-brew
run_dotfiles_expect_failure "$parent_home" "$linked_config" 'must not be a symlink' install --apply --skip-brew
run_dotfiles_expect_failure "$parent_home" "$linked_config" 'must not be a symlink' uninstall --dry-run
run_dotfiles_expect_failure "$parent_home" "$linked_config" 'must not be a symlink' uninstall --apply
traversal_config="$parent_home/config-link/../xdg"
run_dotfiles_expect_failure "$parent_home" "$traversal_config" 'must not contain ..' install --dry-run --skip-brew
run_dotfiles_expect_failure "$parent_home" "$traversal_config" 'must not contain ..' install --apply --skip-brew
run_dotfiles_expect_failure "$parent_home" "$traversal_config" 'must not contain ..' uninstall --dry-run
run_dotfiles_expect_failure "$parent_home" "$traversal_config" 'must not contain ..' uninstall --apply
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

# DOTFILES must resolve to the checkout through both config loading paths.
route_home="$test_root/route-home"
route_config="$route_home/xdg"
mkdir -p "$route_home"
export HOME="$route_home" XDG_CONFIG_HOME="$route_config"
export XDG_STATE_HOME="$route_home/state" MISE_STATE_DIR="$route_home/mise-state"
export MISE_DATA_DIR="$test_root/data" MISE_CACHE_DIR="$test_root/cache"
# shellcheck source=setup/lib.bash
. "$DOTFILES/setup/lib.bash"
# shellcheck source=setup/context.bash
. "$DOTFILES/setup/context.bash"
# shellcheck source=setup/dotfiles.bash
. "$DOTFILES/setup/dotfiles.bash"
initialize_setup_context
MISE_CMD="$recording_bin/mise"
apply_dotfiles_install
test "$(readlink "$XDG_CONFIG_HOME/mise/config.toml")" = "$route_home/.dotfiles/mise.toml"
direct_env="$(read_dotfiles_env "$DOTFILES/mise.toml")"
global_env="$(read_dotfiles_env "$XDG_CONFIG_HOME/mise/config.toml")"
printf '%s\n' "$direct_env" | grep -F '"DOTFILES": "'"$DOTFILES"'"' >/dev/null
printf '%s\n' "$global_env" | grep -F '"DOTFILES": "'"$DOTFILES"'"' >/dev/null
apply_dotfiles_uninstall

printf '%s\n' 'dotfiles lifecycle boundary test passed'
