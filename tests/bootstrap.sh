#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/test-helper.bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-helper.bash"

# The bootstrap wrapper ignores ambient version overrides and verifies a pinned release asset.
# shellcheck source=setup/mise.env
. "$DOTFILES/setup/mise.env"
bootstrap_dry_run="$test_root/bootstrap-dry-run.out"
env HOME="$test_root/bootstrap-dry-run-home" MISE_VERSION=v0.0.0 MISE_INSTALL_PATH=/tmp/unmanaged-mise \
  "$DOTFILES/setup/mise-install.sh" --dry-run > "$bootstrap_dry_run"
assert_contains "$bootstrap_dry_run" "MISE_VERSION=$MISE_VERSION"
assert_contains "$bootstrap_dry_run" "MISE_INSTALL_PATH=$test_root/bootstrap-dry-run-home/.local/bin/mise"
assert_contains "$DOTFILES/setup/mise-install.sh" 'github.com/jdx/mise/releases/download'
assert_contains "$DOTFILES/setup/mise-install.sh" 'sha256sum -c -'

# Homebrew bootstrap uses the official installer and stops on download or installer failure.
homebrew_test_home="$test_root/homebrew-bootstrap-home"
homebrew_test_bin="$test_root/homebrew-bootstrap-bin"
mkdir -p "$homebrew_test_home" "$homebrew_test_bin"
cat > "$homebrew_test_bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >> "$HOME/homebrew-calls"
[ "${FAIL_CURL:-0}" != "1" ] || exit 1
printf '%s\n' '[ "${FAIL_INSTALLER:-0}" != "1" ] || exit 1' \
  'touch "$HOME/homebrew-installer-ran"'
CURL
chmod +x "$homebrew_test_bin/curl"
env HOME="$homebrew_test_home" PATH="$homebrew_test_bin:/usr/bin:/bin" \
  "$DOTFILES/setup/homebrew-install.sh" --apply
assert_contains "$homebrew_test_home/homebrew-calls" \
  "Homebrew/install/HEAD/install.sh"
test -e "$homebrew_test_home/homebrew-installer-ran"
if env HOME="$homebrew_test_home" PATH="$homebrew_test_bin:/usr/bin:/bin" FAIL_CURL=1 \
  "$DOTFILES/setup/homebrew-install.sh" --apply >/dev/null 2>&1; then
  fail "Homebrew bootstrap ignored download failure"
fi
if env HOME="$homebrew_test_home" PATH="$homebrew_test_bin:/usr/bin:/bin" FAIL_INSTALLER=1 \
  "$DOTFILES/setup/homebrew-install.sh" --apply >/dev/null 2>&1; then
  fail "Homebrew bootstrap ignored installer failure"
fi

# Homebrew bootstrap hands off to the newly discovered brew command and evaluates shellenv.
homebrew_handoff_root="$test_root/homebrew-handoff"
mkdir -p "$homebrew_handoff_root/repository/setup" "$homebrew_handoff_root/bin"
cat > "$homebrew_handoff_root/repository/setup/homebrew-install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
printf 'installer %s\n' "$*" >> "$HOME/homebrew-handoff-calls"
INSTALL
cat > "$homebrew_handoff_root/bin/brew" <<'BREW_HANDOFF'
#!/usr/bin/env bash
set -euo pipefail
printf 'brew %s\n' "$*" >> "$HOME/homebrew-handoff-calls"
case "${1:-}" in
  shellenv) printf '%s\n' 'export HOMEBREW_HANDOFF_COMPLETE=1' ;;
  *) exit 1 ;;
esac
BREW_HANDOFF
chmod +x "$homebrew_handoff_root/repository/setup/homebrew-install.sh" \
  "$homebrew_handoff_root/bin/brew"
# Variables in this snippet are expanded by the child Bash process.
# shellcheck disable=SC2016
env HOME="$homebrew_test_home" PATH="$homebrew_handoff_root/bin:/usr/bin:/bin" \
  TEST_DOTFILES="$homebrew_handoff_root/repository" LIB_FILE="$DOTFILES/setup/lib.bash" \
  PACKAGES_FILE="$DOTFILES/setup/packages.bash" \
  bash -c '. "$LIB_FILE"; . "$PACKAGES_FILE"; DOTFILES="$TEST_DOTFILES"; bootstrap_homebrew_action; [ "$HOMEBREW_HANDOFF_COMPLETE" = 1 ]'
assert_contains "$homebrew_test_home/homebrew-handoff-calls" "installer --apply"
assert_contains "$homebrew_test_home/homebrew-handoff-calls" "brew shellenv"

# A missing mise is bootstrapped only in a temporary directory for lockfile validation.
mise_validation_root="$test_root/mise-bootstrap-validation"
mkdir -p "$mise_validation_root/repository/setup"
printf '%s\n' '[tools]' > "$mise_validation_root/repository/config.toml"
printf '%s\n' '[tools]' > "$mise_validation_root/repository/mise.lock"
cat > "$mise_validation_root/repository/setup/mise-install.sh" <<'MISE_INSTALL'
#!/usr/bin/env bash
set -euo pipefail
target="$DOTFILES_MISE_BOOTSTRAP_TARGET"
cat > "$target" <<'MISE'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--cd" ]; then shift 2; fi
case "${1:-}" in
  config) printf '%s\n' '{}' ;;
  install) [ "${FAIL_LOCK_VALIDATION:-0}" != "1" ] ;;
  *) exit 1 ;;
esac
MISE
chmod +x "$target"
MISE_INSTALL
chmod +x "$mise_validation_root/repository/setup/mise-install.sh"
# Variables in this snippet are expanded by the child Bash process.
# shellcheck disable=SC2016
env HOME="$homebrew_test_home" DOTFILES="$mise_validation_root/repository" \
  MISE_CONFIG_SOURCE="$mise_validation_root/repository/config.toml" \
  MISE_LOCK_SOURCE="$mise_validation_root/repository/mise.lock" \
  LIB_FILE="$DOTFILES/setup/lib.bash" PACKAGES_FILE="$DOTFILES/setup/packages.bash" \
  bash -c '. "$LIB_FILE"; . "$PACKAGES_FILE"; PREFLIGHT_FAILED=false; MISE_CMD=; validate_mise_with_temporary_bootstrap; [ "$PREFLIGHT_FAILED" = false ]; [ -z "$MISE_CMD" ]'
# Variables in this snippet are expanded by the child Bash process.
# shellcheck disable=SC2016
if env HOME="$homebrew_test_home" DOTFILES="$mise_validation_root/repository" \
  MISE_CONFIG_SOURCE="$mise_validation_root/repository/config.toml" \
  MISE_LOCK_SOURCE="$mise_validation_root/repository/mise.lock" FAIL_LOCK_VALIDATION=1 \
  LIB_FILE="$DOTFILES/setup/lib.bash" PACKAGES_FILE="$DOTFILES/setup/packages.bash" \
  bash -c '. "$LIB_FILE"; . "$PACKAGES_FILE"; PREFLIGHT_FAILED=false; MISE_CMD=; validate_mise_with_temporary_bootstrap; [ "$PREFLIGHT_FAILED" = false ]' \
  >/dev/null 2>&1; then
  fail "temporary mise accepted an invalid lockfile"
fi

# The composite action maps its private install path to the wrapper's explicit boundary.
action_target="$test_root/action-mise-bin/mise"
action_dry_run="$test_root/action-bootstrap-dry-run.out"
env HOME="$test_root/action-home" MISE_INSTALL_PATH=/tmp/ambient-mise \
  DOTFILES_MISE_BOOTSTRAP_TARGET="$action_target" \
  "$DOTFILES/setup/mise-install.sh" --dry-run > "$action_dry_run"
assert_contains "$action_dry_run" "MISE_INSTALL_PATH=$action_target"
# The dollar expression must remain literal in the composite action.
# shellcheck disable=SC2016
assert_contains "$DOTFILES/.github/actions/setup-mise/action.yml" \
  'DOTFILES_MISE_BOOTSTRAP_TARGET="$MISE_INSTALL_PATH"'
assert_contains "$DOTFILES/.github/actions/setup-mise/action.yml" 'setup/mise.env'

# A non-executable bootstrap target is always a hard conflict.
bootstrap_home="$test_root/bootstrap-home"
new_home "$bootstrap_home"
mkdir -p "$bootstrap_home/.local/bin"
printf '%s\n' 'unmanaged binary' > "$bootstrap_home/.local/bin/mise"
if env HOME="$bootstrap_home" XDG_CONFIG_HOME="$bootstrap_home/.config" \
  XDG_STATE_HOME="$bootstrap_home/.local/state" PATH="/usr/bin:/bin" DOTFILES="$DOTFILES" \
  "$DOTFILES/bin/dotfiles" install --skip-brew --dry-run >/dev/null 2>&1; then
  fail "bootstrap target conflict was accepted"
fi
test "$(cat "$bootstrap_home/.local/bin/mise")" = "unmanaged binary"

printf '%s\n' 'bootstrap tests passed'
