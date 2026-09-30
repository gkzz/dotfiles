#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$DOTFILES"
test_root="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-e2e.XXXXXX")" && pwd -P)"
trap 'rm -rf "$test_root"' EXIT

# Node must remain available after switching mise data to the isolated test root.
node_binary="$(command -v node)"
node_directory="$(dirname "$node_binary")"
export PATH="$node_directory:$PATH"
export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export MISE_DATA_DIR="$test_root/mise-data"
export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$test_root/mise-cache}"
export MISE_STATE_DIR="$test_root/mise-state"
mkdir -p "$HOME" "$test_root/snapshots" "$MISE_DATA_DIR" "$MISE_STATE_DIR"

# Complete mise's first data migration before checking non-mutation.
# shellcheck source=setup/lib.bash
. "$DOTFILES/setup/lib.bash"
# shellcheck source=setup/context.bash
. "$DOTFILES/setup/context.bash"
# shellcheck source=setup/packages.bash
. "$DOTFILES/setup/packages.bash"
initialize_setup_context
MISE_CMD="$(command -v mise)"
export MISE_CMD
run_repository_mise_apply config --json > /dev/null

tools="$(awk '/^\[tools\]/{in_tools=1;next} /^\[/{in_tools=0} in_tools && /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/ {key=$1; gsub(/[[:space:]]/, "", key); print key}' mise.toml)"

snapshot_root() {
  tests/integration/home-snapshot.sh "$1" "$test_root/snapshots/$2"
}
snapshot_mutable_state() {
  snapshot_root "$HOME" "$1-home"
  snapshot_root "$MISE_DATA_DIR" "$1-data"
  snapshot_root "$MISE_STATE_DIR" "$1-state"
}
compare_snapshot() {
  if ! cmp -s "$test_root/snapshots/$1" "$test_root/snapshots/$2"; then
    diff -u "$test_root/snapshots/$1" "$test_root/snapshots/$2" || true
    return 1
  fi
}
compare_mutable_state() {
  compare_snapshot "$1-home" "$2-home"
  compare_snapshot "$1-data" "$2-data"
  compare_snapshot "$1-state" "$2-state"
}
assert_link() {
  test -L "$1"
  test "$(readlink "$1")" = "$2"
}
plans() {
  grep '^plan:' "$test_root/$1"
}
compare_plans() {
  plans "$1" > "$test_root/$1.plans"
  plans "$2" > "$test_root/$2.plans"
  test -s "$test_root/$1.plans"
  cmp "$test_root/$1.plans" "$test_root/$2.plans"
}

assert_tools_installed() {
  local tool
  for tool in $tools; do
    test -n "$(find "$MISE_DATA_DIR/installs/$tool" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  done
}

printf 'unmanaged\n' > "$HOME/sentinel"
snapshot_mutable_state before-install-dry-run

./bin/dotfiles install --skip-brew > "$test_root/install-dry-run"
cat "$test_root/install-dry-run"
snapshot_mutable_state after-install-dry-run
compare_mutable_state before-install-dry-run after-install-dry-run

./bin/dotfiles install --skip-brew --apply > "$test_root/install-apply"
cat "$test_root/install-apply"
compare_plans install-dry-run install-apply
snapshot_root "$HOME" after-first-apply

checkout=$(pwd -P)
assert_link "$HOME/.dotfiles" "$checkout"
assert_link "$HOME/.bashrc" "$HOME/.dotfiles/.bashrc"
assert_link "$HOME/.bash_profile" "$HOME/.dotfiles/.bash_profile"
assert_link "$HOME/.gitconfig" "$HOME/.dotfiles/.gitconfig"
assert_link "$XDG_CONFIG_HOME/mise/config.toml" "$HOME/.dotfiles/mise.toml"

./bin/dotfiles install --skip-brew --apply
snapshot_root "$HOME" after-second-apply
compare_snapshot after-first-apply after-second-apply

snapshot_mutable_state before-verify
./bin/dotfiles verify --skip-brew
snapshot_mutable_state after-verify
compare_mutable_state before-verify after-verify

rm "$HOME/.bashrc"
snapshot_mutable_state before-missing-link-verify
if ./bin/dotfiles verify --skip-brew > "$test_root/missing-link-verify" 2>&1; then
  echo 'verify unexpectedly succeeded with a missing .bashrc' >&2
  exit 1
fi
cat "$test_root/missing-link-verify"
grep -F '.bashrc' "$test_root/missing-link-verify"
snapshot_mutable_state after-missing-link-verify
compare_mutable_state before-missing-link-verify after-missing-link-verify
test ! -e "$HOME/.bashrc" && test ! -L "$HOME/.bashrc"
./bin/dotfiles install --skip-brew --apply

snapshot_mutable_state before-uninstall-dry-run
./bin/dotfiles uninstall > "$test_root/uninstall-dry-run"
cat "$test_root/uninstall-dry-run"
snapshot_mutable_state after-uninstall-dry-run
compare_mutable_state before-uninstall-dry-run after-uninstall-dry-run

./bin/dotfiles uninstall --apply > "$test_root/uninstall-apply"
cat "$test_root/uninstall-apply"
compare_plans uninstall-dry-run uninstall-apply

for target in \
  "$HOME/.dotfiles" \
  "$HOME/.bashrc" \
  "$HOME/.bash_profile" \
  "$HOME/.gitconfig" \
  "$XDG_CONFIG_HOME/mise/config.toml"; do
  test ! -e "$target" && test ! -L "$target"
done
test -f "$HOME/sentinel"

assert_tools_installed

./bin/dotfiles install --skip-brew
./bin/dotfiles install --skip-brew --apply
./bin/dotfiles verify --skip-brew

assert_tools_installed

printf '%s\n' 'dotfiles lifecycle E2E passed'
