#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise-isolation.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

if ! command -v mise >/dev/null 2>&1; then
  printf '%s\n' 'test failed: pinned mise is required for the isolation regression test' >&2
  exit 1
fi

test_home="$test_root/home"
caller_dir="$test_root/caller/project"
mkdir -p "$test_home/.config/mise" "$caller_dir"

cat > "$test_home/.config/mise/miserc.toml" <<'EOF'
env = ["hostile"]
EOF
cat > "$test_home/.config/mise/config.hostile.toml" <<'EOF'
[tools]
ruby = "3.3.0"
EOF
cat > "$caller_dir/mise.toml" <<'EOF'
[tools]
rust = "1.90.0"
EOF

export DOTFILES
export HOME="$test_home"
export PATH
export MISE_CONFIG_DIR="$test_home/.config/mise"
export MISE_SYSTEM_CONFIG_DIR="$test_home/.config/mise"
export MISE_ENV=hostile
export MISE_DATA_DIR="$test_root/data"
export MISE_CACHE_DIR="$test_root/cache"
export MISE_STATE_DIR="$test_root/state"

# shellcheck source=setup/context.bash
. "$DOTFILES/setup/context.bash"
# shellcheck source=setup/packages.bash
. "$DOTFILES/setup/packages.bash"

initialize_setup_context
MISE_CMD="$(command -v mise)"

cd "$caller_dir"
config_json="$(run_repository_mise_apply config --json)"
source_checksum_before="$(cksum "$DOTFILES/.config/mise/mise.lock")"
run_repository_mise_apply install --locked --yes --dry-run >/dev/null
source_checksum_after="$(cksum "$DOTFILES/.config/mise/mise.lock")"
test "$source_checksum_after" = "$source_checksum_before"

if printf '%s\n' "$config_json" | grep -E 'ruby|rust|config\.hostile\.toml|miserc\.toml|conf\.d|config\.local' >/dev/null; then
  printf '%s\n' 'test failed: caller or HOME mise configuration crossed the repository isolation boundary' >&2
  printf '%s\n' "$config_json" >&2
  exit 1
fi

# Repository-local discovery files are excluded by copying only the canonical pair.
isolated_repo="$test_root/repository"
mkdir -p "$isolated_repo/.config/mise/conf.d"
cp "$DOTFILES/.config/mise/config.toml" "$isolated_repo/.config/mise/config.toml"
cp "$DOTFILES/.config/mise/mise.lock" "$isolated_repo/.config/mise/mise.lock"
cat > "$isolated_repo/.config/mise/conf.d/local.toml" <<'EOF'
[tools]
ruby = "3.3.0"
EOF
cat > "$isolated_repo/.config/mise/.miserc.toml" <<'EOF'
env = ["hostile"]
EOF
DOTFILES="$isolated_repo"
initialize_setup_context
isolated_json="$(run_repository_mise_apply config --json)"
if printf '%s\n' "$isolated_json" | grep -E 'ruby|local\.toml|miserc\.toml' >/dev/null; then
  printf '%s\n' 'test failed: repository-local discovery files crossed the temporary project boundary' >&2
  printf '%s\n' "$isolated_json" >&2
  exit 1
fi

printf '%s\n' 'mise isolation test passed'
