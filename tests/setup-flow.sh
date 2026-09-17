#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-setup-flow.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/mise" <<'MISE'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--cd" ]; then
  printf 'mise-cwd=%s\n' "$2" >> "$HOME/calls"
  shift 2
fi
printf 'mise %s node-version=%s config=%s mise-env=%s\n' \
  "$*" "${MISE_NODE_VERSION-unset}" "${MISE_GLOBAL_CONFIG_FILE-unset}" "${MISE_ENV-unset}" >> "$HOME/calls"
case "${1:-}" in
  config)
    [ ! -e "$MISE_DATA_DIR/incompatible" ] || exit 1
    printf '%s\n' "$MISE_GLOBAL_CONFIG_FILE"
    ;;
  install)
    case " $* " in
      *' --dry-run '*) ;;
      *)
        mkdir -p "$MISE_DATA_DIR"
        touch "$MISE_DATA_DIR/tools-installed"
        ;;
    esac
    ;;
  ls)
    if [ ! -e "$MISE_DATA_DIR/tools-installed" ]; then
      printf '%s\n' 'node 24.19.0 missing'
    fi
    ;;
  version|--version) printf '%s\n' '2026.8.6 linux-x64' ;;
  *) printf 'unexpected mise command: %s\n' "$*" >&2; exit 1 ;;
esac
MISE

cat > "$fake_bin/brew" <<'BREW'
#!/usr/bin/env bash
set -euo pipefail
printf 'brew %s\n' "$*" >> "$HOME/calls"
case "${1:-}" in
  bundle)
    if [ "${2:-}" = "check" ]; then
      test -e "$HOME/.fake-brew-installed"
    else
      touch "$HOME/.fake-brew-installed"
    fi
    ;;
  shellenv) printf '%s\n' 'export PATH="$PATH"' ;;
  *) printf 'unexpected brew command: %s\n' "$*" >&2; exit 1 ;;
esac
BREW
chmod +x "$fake_bin/mise" "$fake_bin/brew"

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
    PATH="$fake_bin:/usr/bin:/bin" \
    DOTFILES="$DOTFILES" \
    "$DOTFILES/bin/dotfiles" "$@"
}

# Parser and removed legacy options fail explicitly.
if "$DOTFILES/bin/dotfiles" >/dev/null 2>&1; then fail "empty CLI was accepted"; fi
if "$DOTFILES/bin/dotfiles" --prepare >/dev/null 2>&1; then fail "legacy phase was accepted"; fi
if "$DOTFILES/bin/dotfiles" install --target /tmp >/dev/null 2>&1; then fail "--target was accepted"; fi
if "$DOTFILES/bin/dotfiles" check --apply >/dev/null 2>&1; then fail "check --apply was accepted"; fi
if "$DOTFILES/bin/dotfiles" uninstall --force >/dev/null 2>&1; then fail "uninstall --force was accepted"; fi
assert_exit_2 "$DOTFILES/bin/dotfiles" install --apply --dry-run
assert_exit_2 "$DOTFILES/bin/dotfiles" install --dry-run --apply
assert_exit_2 "$DOTFILES/bin/dotfiles" check --dry-run

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

# Dry-run produces a complete plan without creating HOME state.
home="$test_root/home"
new_home "$home"
dry_output="$test_root/dry.out"
run_dotfiles "$home" install --dry-run > "$dry_output"
assert_contains "$dry_output" "plan: brew_bundle $DOTFILES/Brewfile"
assert_contains "$dry_output" "plan: mise_install $DOTFILES/.config/mise/config.toml"
assert_contains "$dry_output" "plan: ensure_symlink $home/.bashrc <- $DOTFILES/.bashrc"
test ! -e "$home/.bashrc"
test ! -e "$home/.local/state/dotfiles"
assert_not_contains "$home/calls" "brew bundle"
assert_contains "$home/calls" "mise install --locked --dry-run"
assert_contains "$home/calls" "mise-env=unset"

# Apply prints the same semantic plan, calls package managers first, and creates links.
apply_output="$test_root/apply.out"
run_dotfiles "$home" install --apply > "$apply_output"
grep '^plan:' "$dry_output" > "$test_root/dry.plan"
grep '^plan:' "$apply_output" > "$test_root/apply.plan"
cmp "$test_root/dry.plan" "$test_root/apply.plan"
test -L "$home/.bashrc"
test -L "$home/.bash_profile"
test -L "$home/.gitconfig"
test -L "$home/.config/mise/config.toml"
test "$(readlink "$home/.bashrc")" = "$DOTFILES/.bashrc"
test ! -e "$home/.local/state/dotfiles/resources.tsv"
test ! -e "$home/.local/state/dotfiles/lifecycle.lock"
assert_contains "$home/calls" "brew bundle --file $DOTFILES/Brewfile --no-upgrade"
assert_contains "$home/calls" "mise install --locked --yes node-version=unset"
assert_not_contains "$home/calls" "config=$DOTFILES/.config/mise/config.toml"
assert_before "$home/calls" "brew bundle --file" "mise install --locked --yes"
assert_before "$dry_output" "plan: mise_install" "plan: ensure_symlink"

# Check uses upstream checkers and succeeds after convergence.
run_dotfiles "$home" check >/dev/null
assert_contains "$home/calls" "brew bundle check --no-upgrade --file $DOTFILES/Brewfile"
assert_contains "$home/calls" "mise ls --missing --no-header node-version=unset"

# Repeated apply is idempotent and creates no backup.
run_dotfiles "$home" install --apply >/dev/null
if path_glob_exists "$home/.bashrc.backup.*"; then fail "idempotent apply created a backup"; fi

# A conflict fails before any package action.
rm "$home/.gitconfig"
printf '%s\n' 'local git config' > "$home/.gitconfig"
: > "$home/calls"
if run_dotfiles "$home" install --apply >/dev/null 2>&1; then fail "conflict was accepted without --force"; fi
test "$(cat "$home/.gitconfig")" = "local git config"
test ! -e "$home/.local/state/dotfiles/lifecycle.lock"
assert_not_contains "$home/calls" "brew bundle"
assert_not_contains "$home/calls" "mise install"
assert_not_contains "$home/calls" "brew "
assert_not_contains "$home/calls" "mise "

# --force backs up regular files and converges.
force_dry_run="$test_root/force-dry-run.out"
run_dotfiles "$home" install --force --dry-run > "$force_dry_run"
assert_contains "$force_dry_run" "plan: replace_symlink $home/.gitconfig <- $DOTFILES/.gitconfig"
test ! -L "$home/.gitconfig"
if path_glob_exists "$home/.gitconfig.backup.*"; then fail "force dry-run created a backup"; fi
run_dotfiles "$home" install --force --apply >/dev/null
test -L "$home/.gitconfig"
path_glob_exists "$home/.gitconfig.backup.*" || fail "force did not create a backup"

# A failed symlink creation restores the file moved to the backup path.
rollback_home="$test_root/rollback-home"
mkdir -p "$rollback_home"
printf '%s\n' 'restore me' > "$rollback_home/.bashrc"
if bash -c '
  . "$1/setup/lib.bash"
  . "$1/setup/resources.bash"
  force=true
  ln() {
    [ "$1" != "-s" ] && { command ln "$@"; return; }
    return 1
  }
  ensure_symlink "$1/.bashrc" "$2/.bashrc"
' _ "$DOTFILES" "$rollback_home" >/dev/null 2>&1; then
  fail "simulated symlink failure succeeded"
fi
test "$(cat "$rollback_home/.bashrc")" = "restore me"
if path_glob_exists "$rollback_home/.bashrc.backup.*"; then fail "rollback left an orphan backup"; fi

# A destination created by another process during rollback is never overwritten.
concurrent_home="$test_root/concurrent-home"
mkdir -p "$concurrent_home"
printf '%s\n' 'preserve in backup' > "$concurrent_home/.bashrc"
if bash -c '
  . "$1/setup/lib.bash"
  . "$1/setup/resources.bash"
  force=true
  ln() {
    if [ "$1" = "-s" ]; then
      printf "%s\n" "concurrent replacement" > "$3"
      return 1
    fi
    command ln "$@"
  }
  ensure_symlink "$1/.bashrc" "$2/.bashrc"
' _ "$DOTFILES" "$concurrent_home" >/dev/null 2>&1; then
  fail "simulated concurrent symlink failure succeeded"
fi
test "$(cat "$concurrent_home/.bashrc")" = "concurrent replacement"
concurrent_backup="$(compgen -G "$concurrent_home/.bashrc.backup.*" | head -n 1)"
[ -n "$concurrent_backup" ] || fail "concurrent rollback did not preserve the backup"
test "$(cat "$concurrent_backup")" = "preserve in backup"

# A missing destination must not be upgraded to a replacement when it appears after planning.
planned_missing_home="$test_root/planned-missing-home"
mkdir -p "$planned_missing_home"
if bash -c '
  . "$1/setup/lib.bash"
  . "$1/setup/resources.bash"
  ln() { printf "%s\n" "concurrent missing-plan replacement" > "$3"; return 1; }
  ensure_symlink "$1/.bashrc" "$2/.bashrc" ensure_symlink
' _ "$DOTFILES" "$planned_missing_home" >/dev/null 2>&1; then
  fail "missing symlink plan accepted a concurrent replacement"
fi
test "$(cat "$planned_missing_home/.bashrc")" = "concurrent missing-plan replacement"
if path_glob_exists "$planned_missing_home/.bashrc.backup.*"; then
  fail "missing symlink plan created a backup"
fi

# Directory conflicts remain fatal even with --force.
rm "$home/.bash_profile"
mkdir "$home/.bash_profile"
: > "$home/calls"
if run_dotfiles "$home" install --force --apply >/dev/null 2>&1; then fail "directory conflict was accepted"; fi
test -d "$home/.bash_profile"
assert_not_contains "$home/calls" "brew bundle"
assert_not_contains "$home/calls" "mise install"
rmdir "$home/.bash_profile"
ln -s "$DOTFILES/.bash_profile" "$home/.bash_profile"

# Existing lifecycle lock prevents mutation.
lock_home="$test_root/lock-home"
new_home "$lock_home"
mkdir -p "$lock_home/.dotfiles-lifecycle.lock"
printf '%s\n' "$$" > "$lock_home/.dotfiles-lifecycle.lock/pid"
if env HOME="$lock_home" XDG_CONFIG_HOME="$lock_home/.config" \
  XDG_STATE_HOME="$lock_home/alternate-state" MISE_DATA_DIR="$lock_home/mise-data" \
  MISE_CACHE_DIR="$lock_home/mise-cache" MISE_STATE_DIR="$lock_home/mise-state" \
  PATH="$fake_bin:/usr/bin:/bin" DOTFILES="$DOTFILES" \
  "$DOTFILES/bin/dotfiles" install --apply >/dev/null 2>&1; then
  fail "existing HOME-scoped lock was ignored with a different XDG_STATE_HOME"
fi
test ! -e "$lock_home/.bashrc"
test ! -e "$lock_home/calls"

# A failed PID write does not leave an unusable lifecycle lock behind.
pid_failure_home="$test_root/pid-failure-home"
mkdir -p "$pid_failure_home"
if bash -c '
  DOTFILES="$1"
  HOME="$2"
  . "$DOTFILES/setup/lifecycle.bash"
  initialize_setup_context
  printf() { return 1; }
  lifecycle_lock_acquire
' _ "$DOTFILES" "$pid_failure_home" >/dev/null 2>&1; then
  fail "simulated lifecycle PID write failure succeeded"
fi
test ! -e "$pid_failure_home/.dotfiles-lifecycle.lock"

# A dead or malformed lock owner is recovered before mutation.
stale_lock_home="$test_root/stale-lock-home"
mkdir -p "$stale_lock_home/.dotfiles-lifecycle.lock"
printf '%s\n' '99999999' > "$stale_lock_home/.dotfiles-lifecycle.lock/pid"
stale_output="$test_root/stale-lock.out"
run_dotfiles "$stale_lock_home" uninstall --apply > "$stale_output"
assert_contains "$stale_output" "recovered stale lifecycle lock"
test ! -e "$stale_lock_home/.dotfiles-lifecycle.lock"

# A stale lock with unexpected entries keeps its PID metadata for manual recovery.
blocked_stale_home="$test_root/blocked-stale-lock-home"
mkdir -p "$blocked_stale_home/.dotfiles-lifecycle.lock"
printf '%s\n' '99999999' > "$blocked_stale_home/.dotfiles-lifecycle.lock/pid"
printf '%s\n' 'unexpected' > "$blocked_stale_home/.dotfiles-lifecycle.lock/extra"
if run_dotfiles "$blocked_stale_home" uninstall --apply >/dev/null 2>&1; then
  fail "stale lock with unexpected entries was recovered"
fi
test "$(cat "$blocked_stale_home/.dotfiles-lifecycle.lock/pid")" = "99999999"
test "$(cat "$blocked_stale_home/.dotfiles-lifecycle.lock/extra")" = "unexpected"

# A no-op uninstall does not leave lock-only state in a clean HOME.
noop_home="$test_root/noop-home"
mkdir -p "$noop_home"
run_dotfiles "$noop_home" uninstall --apply >/dev/null
test ! -e "$noop_home/.local"

# Lock acquisition rejects a symlinked parent without touching its target.
symlink_lock_home="$test_root/symlink-lock-home"
symlink_lock_target="$test_root/symlink-lock-target"
mkdir -p "$symlink_lock_home" "$symlink_lock_target"
chmod 755 "$symlink_lock_target"
ln -s "$symlink_lock_target" "$symlink_lock_home/.dotfiles-lifecycle.lock"
target_mode_before="$(permission_bits "$symlink_lock_target")"
if run_dotfiles "$symlink_lock_home" uninstall --apply >/dev/null 2>&1; then
  fail "symlinked lifecycle lock parent was accepted"
fi
target_mode_after="$(permission_bits "$symlink_lock_target")"
test "$target_mode_after" = "$target_mode_before"
test ! -e "$symlink_lock_target/lifecycle.lock"

# A symlinked HOME is rejected, but symlinks above HOME are outside the lock boundary.
real_lock_home="$test_root/real-lock-home"
symlink_home="$test_root/symlink-home"
mkdir -p "$real_lock_home"
ln -s "$real_lock_home" "$symlink_home"
if run_dotfiles "$symlink_home" uninstall --apply >/dev/null 2>&1; then
  fail "symlinked HOME was accepted for lifecycle locking"
fi
test ! -e "$real_lock_home/.dotfiles-lifecycle.lock"

# The lock directory itself cannot redirect stale recovery through a symlink.
symlink_lock_dir_home="$test_root/symlink-lock-dir-home"
symlink_lock_dir_target="$test_root/symlink-lock-dir-target"
mkdir -p "$symlink_lock_dir_home" "$symlink_lock_dir_target"
printf '%s\n' '99999999' > "$symlink_lock_dir_target/pid"
ln -s "$symlink_lock_dir_target" "$symlink_lock_dir_home/.dotfiles-lifecycle.lock"
if run_dotfiles "$symlink_lock_dir_home" uninstall --apply >/dev/null 2>&1; then
  fail "symlinked lifecycle lock directory was accepted"
fi
test "$(cat "$symlink_lock_dir_target/pid")" = "99999999"

# Lock acquisition does not rewrite permissions on an existing parent directory.
mode_lock_home="$test_root/mode-lock-home"
mkdir -p "$mode_lock_home"
chmod 755 "$mode_lock_home"
parent_mode_before="$(permission_bits "$mode_lock_home")"
run_dotfiles "$mode_lock_home" uninstall --apply >/dev/null
parent_mode_after="$(permission_bits "$mode_lock_home")"
test "$parent_mode_after" = "$parent_mode_before"

# A relative HOME fails before any lock path is created.
relative_home="$test_root/relative-home"
mkdir -p "$relative_home"
if (
  cd "$test_root"
  env HOME=relative-home XDG_CONFIG_HOME="$relative_home/.config" \
    XDG_STATE_HOME="$relative_home/.state" PATH="$fake_bin:/usr/bin:/bin" DOTFILES="$DOTFILES" \
    "$DOTFILES/bin/dotfiles" uninstall --apply >/dev/null 2>&1
); then
  fail "relative HOME was accepted for lifecycle locking"
fi
test ! -e "$relative_home/.local"

# --skip-brew removes every Homebrew inspection/action.
skip_home="$test_root/skip-home"
new_home "$skip_home"
run_dotfiles "$skip_home" install --skip-brew --apply >/dev/null
assert_not_contains "$skip_home/calls" "brew "

# Check aggregates missing state without repairing it.
rm "$home/.bashrc" "$home/mise-data/tools-installed"
if run_dotfiles "$home" check >/dev/null 2>&1; then fail "check accepted missing resources"; fi
test ! -e "$home/.bashrc"
test ! -e "$home/mise-data/tools-installed"
ln -s "$DOTFILES/.bashrc" "$home/.bashrc"
touch "$home/mise-data/tools-installed"

# Uninstall dry-run/apply use the same plan and preserve packages, backups, state, and drift.
old_state="$home/.local/state/dotfiles/resources.tsv"
mkdir -p "$(dirname "$old_state")"
printf '%s\n' 'legacy state remains untouched' > "$old_state"
old_state_checksum="$(cksum "$old_state")"
rm "$home/.gitconfig"
printf '%s\n' 'user replacement' > "$home/.gitconfig"
uninstall_dry="$test_root/uninstall-dry.out"
uninstall_apply="$test_root/uninstall-apply.out"
run_dotfiles "$home" uninstall --dry-run > "$uninstall_dry"
run_dotfiles "$home" uninstall --apply > "$uninstall_apply"
grep '^plan:' "$uninstall_dry" > "$test_root/uninstall-dry.plan"
grep '^plan:' "$uninstall_apply" > "$test_root/uninstall-apply.plan"
cmp "$test_root/uninstall-dry.plan" "$test_root/uninstall-apply.plan"
test ! -e "$home/.bashrc"
test ! -e "$home/.bash_profile"
test ! -e "$home/.config/mise/config.toml"
test "$(cat "$home/.gitconfig")" = "user replacement"
test -e "$home/.fake-brew-installed"
test -e "$home/mise-data/tools-installed"
test "$(cksum "$old_state")" = "$old_state_checksum"
path_glob_exists "$home/.gitconfig.backup.*" || fail "uninstall removed backup"

# Uninstall remains usable without Git or package-manager commands.
minimal_bin="$test_root/minimal-bin"
mkdir -p "$minimal_bin"
for command_name in bash mkdir readlink rm rmdir; do
  ln -s "$(command -v "$command_name")" "$minimal_bin/$command_name"
done
minimal_home="$test_root/minimal-home"
mkdir -p "$minimal_home"
ln -s "$DOTFILES/.bashrc" "$minimal_home/.bashrc"
env HOME="$minimal_home" XDG_CONFIG_HOME="$minimal_home/.config" \
  XDG_STATE_HOME="$minimal_home/.state" PATH="$minimal_bin" DOTFILES="$DOTFILES" \
  "$DOTFILES/bin/dotfiles" uninstall --apply >/dev/null
test ! -e "$minimal_home/.bashrc"

# .bashrc discovers the repository from its absolute symlink.
discovery_home="$test_root/discovery-home"
mkdir -p "$discovery_home"
ln -s "$DOTFILES/.bashrc" "$discovery_home/.bashrc"
# Expansion is intentionally deferred to the child Bash process.
# shellcheck disable=SC2016
discovered="$(env -u DOTFILES HOME="$discovery_home" bash --noprofile --norc -c '. "$HOME/.bashrc"; printf "%s" "$DOTFILES"')"
test "$discovered" = "$DOTFILES"

assert_not_contains "$DOTFILES/.bashrc" 'github.com/gkzz/dotfiles'
assert_not_contains "$DOTFILES/.config/mise/config.toml" 'github.com/gkzz/dotfiles'
assert_contains "$DOTFILES/.config/mise/config.toml" \
  "DOTFILES = \"{{ [xdg_config_home, 'mise', 'config.toml'] | join_path | canonicalize | dirname | dirname | dirname }}\""

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

printf '%s\n' 'setup flow tests passed'
