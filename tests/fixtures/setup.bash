#!/usr/bin/env bash

fixtures_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-setup-flow.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cp "$fixtures_dir/fake-mise.bash" "$fake_bin/mise"
cp "$fixtures_dir/fake-brew.bash" "$fake_bin/brew"
chmod +x "$fake_bin/mise" "$fake_bin/brew"

new_home() {
  local path="$1"
  mkdir -p "$path/mise-data" "$path/mise-cache" "$path/mise-state"
}

run_dotfiles() {
  local target_home="$1"
  shift
  env \
    HOME="$target_home" \
    XDG_CONFIG_HOME="$target_home/.config" \
    XDG_STATE_HOME="$target_home/.local/state" \
    MISE_DATA_DIR="$target_home/mise-data" \
    MISE_CACHE_DIR="$target_home/mise-cache" \
    MISE_STATE_DIR="$target_home/mise-state" \
    MISE_NODE_VERSION=ambient-must-not-leak \
    DOTFILES_SKIP_BREW=0 \
    GITHUB_ACTIONS=false \
    PATH="${TEST_PATH_PREFIX:+$TEST_PATH_PREFIX:}$fake_bin:/usr/bin:/bin" \
    DOTFILES="$DOTFILES" \
    "$DOTFILES/bin/dotfiles" "$@"
}

create_converged_home() {
  local target_home="$1"
  new_home "$target_home"
  run_dotfiles "$target_home" install --apply >/dev/null
}
