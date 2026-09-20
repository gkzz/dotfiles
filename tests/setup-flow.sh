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
    if [ "${FAIL_MISE_CONFIG:-0}" = "1" ]; then
      printf '%s\n' 'fake mise config failure' >&2
      exit 17
    fi
    [ ! -e "$MISE_DATA_DIR/incompatible" ] || exit 1
    printf '%s\n' "$MISE_GLOBAL_CONFIG_FILE"
    ;;
  install)
    if [ "${FAIL_MISE_LOCK:-0}" = "1" ] && case " $* " in *' --dry-run '*) true ;; *) false ;; esac; then
      printf '%s\n' 'fake mise lock failure' >&2
      exit 18
    fi
    case " $* " in
      *' --dry-run '*) ;;
      *)
        mkdir -p "$MISE_DATA_DIR"
        touch "$MISE_DATA_DIR/tools-installed"
        ;;
    esac
    ;;
  ls)
    if [ -n "${FAIL_MISE_LS_STATUS:-}" ]; then
      printf 'fake mise ls status %s\n' "$FAIL_MISE_LS_STATUS" >&2
      exit "$FAIL_MISE_LS_STATUS"
    fi
    if [ "${FAIL_MISE_LS:-0}" = "1" ]; then
      printf '%s\n' 'fake mise ls failure' >&2
      exit 19
    fi
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

# Check distinguishes managed-link state mismatches without repairing them.
link_check_home="$test_root/link-check-home"
new_home "$link_check_home"
run_dotfiles "$link_check_home" install --apply >/dev/null
rm "$link_check_home/.bashrc"
link_check_output="$test_root/link-check-missing.out"
if run_dotfiles "$link_check_home" check --skip-brew >"$link_check_output" 2>&1; then
  fail "check accepted a missing managed symlink"
fi
assert_contains "$link_check_output" \
  "check failed: managed symlink is missing: path=$link_check_home/.bashrc expected=$DOTFILES/.bashrc"
test ! -e "$link_check_home/.bashrc"

printf '%s\n' 'keep this local file' > "$link_check_home/.bashrc"
link_check_output="$test_root/link-check-file.out"
if run_dotfiles "$link_check_home" check --skip-brew >"$link_check_output" 2>&1; then
  fail "check accepted a regular-file managed destination"
fi
assert_contains "$link_check_output" \
  "check failed: managed destination is not a symlink: path=$link_check_home/.bashrc expected=$DOTFILES/.bashrc"
test "$(cat "$link_check_home/.bashrc")" = "keep this local file"

rm "$link_check_home/.bashrc"
mkdir "$link_check_home/.bashrc"
link_check_output="$test_root/link-check-directory.out"
if run_dotfiles "$link_check_home" check --skip-brew >"$link_check_output" 2>&1; then
  fail "check accepted a directory managed destination"
fi
assert_contains "$link_check_output" \
  "check failed: managed destination is not a symlink: path=$link_check_home/.bashrc expected=$DOTFILES/.bashrc"
test -d "$link_check_home/.bashrc"

rmdir "$link_check_home/.bashrc"
ln -s "$link_check_home/wrong-target" "$link_check_home/.bashrc"
link_check_output="$test_root/link-check-target.out"
if run_dotfiles "$link_check_home" check --skip-brew >"$link_check_output" 2>&1; then
  fail "check accepted a wrong managed symlink target"
fi
assert_contains "$link_check_output" \
  "check failed: managed symlink target differs: path=$link_check_home/.bashrc expected=$DOTFILES/.bashrc actual=$link_check_home/wrong-target"
test "$(readlink "$link_check_home/.bashrc")" = "$link_check_home/wrong-target"

check_failure_bin="$test_root/check-failure-bin"
mkdir -p "$check_failure_bin"
cat > "$check_failure_bin/readlink" <<'READLINK'
#!/usr/bin/env bash
set -euo pipefail
if [ "${FAIL_READLINK_PATH:-}" = "${1:-}" ]; then
  printf '%s\n' 'fake readlink failure' >&2
  exit 20
fi
exec /usr/bin/readlink "$@"
READLINK
cat > "$check_failure_bin/rm" <<'RM'
#!/usr/bin/env bash
set -euo pipefail
if [ "${FAIL_MISE_CLEANUP:-0}" = "1" ]; then
  case " $* " in
    *dotfiles-mise.*)
      printf '%s\n' 'fake cleanup failure' >&2
      exit 21
      ;;
  esac
fi
exec /bin/rm "$@"
RM
chmod +x "$check_failure_bin/readlink" "$check_failure_bin/rm"

link_check_output="$test_root/link-check-readlink.out"
if TEST_PATH_PREFIX="$check_failure_bin" FAIL_READLINK_PATH="$link_check_home/.bashrc" \
  run_dotfiles "$link_check_home" check --skip-brew >"$link_check_output" 2>&1; then
  fail "check accepted a readlink execution failure"
fi
assert_contains "$link_check_output" \
  "check error: failed to read managed symlink target: path=$link_check_home/.bashrc"
assert_not_contains "$link_check_output" "managed symlink target differs: path=$link_check_home/.bashrc"

cleanup_check_output="$test_root/mise-check-cleanup.out"
if TEST_PATH_PREFIX="$check_failure_bin" FAIL_MISE_CLEANUP=1 \
  run_dotfiles "$home" check --skip-brew >"$cleanup_check_output" 2>&1; then
  fail "check accepted a mise cleanup failure"
fi
assert_contains "$cleanup_check_output" "check error: failed to remove temporary mise directory: path="
assert_contains "$cleanup_check_output" "fake cleanup failure"
assert_not_contains "$cleanup_check_output" "check complete"
while IFS= read -r cleanup_path; do
  case "$cleanup_path" in
    "${TMPDIR:-/tmp}"/dotfiles-mise.*) /bin/rm -rf "$cleanup_path" ;;
    *) fail "unexpected cleanup test path: $cleanup_path" ;;
  esac
done < <(sed -n 's/^check error: failed to remove temporary mise directory: path=//p' "$cleanup_check_output")

# Each mise helper failure is classified without leaking check-only prefixes into install.
for helper_stage in mktemp mkdir config-copy lock-copy cleanup; do
  helper_output="$test_root/mise-helper-$helper_stage.out"
  set +e
  # Variables in this single-quoted script are intentionally expanded by the child shell.
  # shellcheck disable=SC2016
  env HELPER_STAGE="$helper_stage" LIB_FILE="$DOTFILES/setup/lib.bash" \
    PACKAGES_FILE="$DOTFILES/setup/packages.bash" CONFIG_SOURCE="$DOTFILES/.config/mise/config.toml" \
    LOCK_SOURCE="$DOTFILES/.config/mise/mise.lock" bash -c '
      . "$LIB_FILE"
      . "$PACKAGES_FILE"
      CHECK_FAILED=false
      CHECK_MODE=true
      MISE_CMD=/bin/true
      MISE_CONFIG_SOURCE="$CONFIG_SOURCE"
      MISE_LOCK_SOURCE="$LOCK_SOURCE"
      mktemp() { [ "$HELPER_STAGE" != mktemp ] || { printf "%s\n" "fake mktemp failure" >&2; return 1; }; command mktemp "$@"; }
      mkdir() { [ "$HELPER_STAGE" != mkdir ] || { printf "%s\n" "fake mkdir failure" >&2; return 1; }; command mkdir "$@"; }
      cp() {
        if { [ "$HELPER_STAGE" = config-copy ] && [ "$1" = "$MISE_CONFIG_SOURCE" ]; } ||
          { [ "$HELPER_STAGE" = lock-copy ] && [ "$1" = "$MISE_LOCK_SOURCE" ]; }; then
          printf "%s\n" "fake cp failure" >&2
          return 1
        fi
        command cp "$@"
      }
      rm() {
        if [ "$HELPER_STAGE" = cleanup ]; then
          command rm "$@"
          printf "%s\n" "fake cleanup failure" >&2
          return 1
        fi
        command rm "$@"
      }
      check_mise_tools
      [ "$CHECK_FAILED" = true ]
    ' >"$helper_output" 2>&1
  helper_status=$?
  set -e
  [ "$helper_status" -eq 0 ] || fail "mise helper test failed: $helper_stage"
done
assert_contains "$test_root/mise-helper-mktemp.out" "check error: failed to create temporary directory for mise inspection"
assert_contains "$test_root/mise-helper-mkdir.out" "check error: failed to create temporary mise system directory: path="
assert_contains "$test_root/mise-helper-config-copy.out" "check error: failed to copy mise config into temporary directory: source=$DOTFILES/.config/mise/config.toml"
assert_contains "$test_root/mise-helper-lock-copy.out" "check error: failed to copy mise lockfile into temporary directory: source=$DOTFILES/.config/mise/mise.lock"
assert_contains "$test_root/mise-helper-cleanup.out" "check error: failed to remove temporary mise directory: path="

install_helper_output="$test_root/mise-helper-install.out"
set +e
# Variables in this single-quoted script are intentionally expanded by the child shell.
# shellcheck disable=SC2016
env LIB_FILE="$DOTFILES/setup/lib.bash" PACKAGES_FILE="$DOTFILES/setup/packages.bash" \
  CONFIG_SOURCE="$DOTFILES/.config/mise/config.toml" LOCK_SOURCE="$DOTFILES/.config/mise/mise.lock" bash -c '
    . "$LIB_FILE"
    . "$PACKAGES_FILE"
    MISE_CMD=/bin/true
    MISE_CONFIG_SOURCE="$CONFIG_SOURCE"
    MISE_LOCK_SOURCE="$LOCK_SOURCE"
    mktemp() { printf "%s\n" "fake install mktemp failure" >&2; return 1; }
    apply_mise_tools
  ' >"$install_helper_output" 2>&1
install_helper_status=$?
set -e
[ "$install_helper_status" -ne 0 ] || fail "install accepted a mise helper failure"
assert_contains "$install_helper_output" "failed to create temporary directory for mise inspection"
assert_not_contains "$install_helper_output" "check error:"

# Missing repository inputs are reported once and dependent mise checks are skipped.
missing_source_repository="$test_root/missing-source-repository"
cp -R "$DOTFILES" "$missing_source_repository"
rm "$missing_source_repository/.config/mise/config.toml"
missing_source_home="$test_root/missing-source-home"
new_home "$missing_source_home"
mkdir -p "$missing_source_home/.config/mise"
ln -s "$missing_source_repository/.config/mise/config.toml" \
  "$missing_source_home/.config/mise/config.toml"
missing_source_output="$test_root/missing-source.out"
set +e
env HOME="$missing_source_home" XDG_CONFIG_HOME="$missing_source_home/.config" \
  MISE_DATA_DIR="$missing_source_home/mise-data" MISE_CACHE_DIR="$missing_source_home/mise-cache" \
  MISE_STATE_DIR="$missing_source_home/mise-state" DOTFILES_SKIP_BREW=1 \
  PATH="$fake_bin:/usr/bin:/bin" DOTFILES="$missing_source_repository" \
  "$missing_source_repository/bin/dotfiles" check >"$missing_source_output" 2>&1
missing_source_status=$?
set -e
[ "$missing_source_status" -eq 1 ] || fail "missing mise source did not exit 1"
test "$(grep -F -c "required repository file is not readable: $missing_source_repository/.config/mise/config.toml" "$missing_source_output")" -eq 1
assert_not_contains "$missing_source_output" "managed symlink source is missing"
assert_not_contains "$missing_source_output" "failed to copy mise config"
assert_not_contains "$missing_source_output" "mise could not inspect tools"
test "$(readlink "$missing_source_home/.config/mise/config.toml")" = \
  "$missing_source_repository/.config/mise/config.toml"

# A missing command prevents only its dependent repository validator from running.
command_check_output="$test_root/missing-command.out"
# Variables in this single-quoted script are intentionally expanded by the child shell.
# shellcheck disable=SC2016
env LIB_FILE="$DOTFILES/setup/lib.bash" REPOSITORY="$DOTFILES" bash -c '
  . "$LIB_FILE"
  CHECK_FAILED=false
  CHECK_MODE=true
  DOTFILES="$REPOSITORY"
  MISE_CONFIG_SOURCE="$REPOSITORY/.config/mise/config.toml"
  MISE_LOCK_SOURCE="$REPOSITORY/.config/mise/mise.lock"
  have_cmd() { [ "$1" != git ]; }
  git() { printf "%s\n" "git validator unexpectedly ran"; return 1; }
  validate_check_commands
  validate_repository
  [ "$CHECK_FAILED" = true ]
' >"$command_check_output" 2>&1
assert_contains "$command_check_output" "check error: required command is missing: git"
assert_not_contains "$command_check_output" "git validator unexpectedly ran"
assert_not_contains "$command_check_output" "Git configuration syntax is invalid"

# mise command failures are execution errors and preserve the original stderr.
mise_check_output="$test_root/mise-check-config.out"
if FAIL_MISE_CONFIG=1 run_dotfiles "$home" check --skip-brew >"$mise_check_output" 2>&1; then
  fail "check accepted a mise config failure"
fi
assert_contains "$mise_check_output" "check error: mise could not load the isolated repository config"
assert_contains "$mise_check_output" "fake mise config failure"

mise_check_output="$test_root/mise-check-lock.out"
if FAIL_MISE_LOCK=1 run_dotfiles "$home" check --skip-brew >"$mise_check_output" 2>&1; then
  fail "check accepted a mise lockfile failure"
fi
assert_contains "$mise_check_output" "check error: mise could not validate the repository lockfile"
assert_contains "$mise_check_output" "fake mise lock failure"

mise_check_output="$test_root/mise-check-ls.out"
if FAIL_MISE_LS=1 run_dotfiles "$home" check --skip-brew >"$mise_check_output" 2>&1; then
  fail "check accepted a mise inspection failure"
fi
assert_contains "$mise_check_output" "check error: mise could not inspect tools"
assert_contains "$mise_check_output" "fake mise ls failure"
assert_not_contains "$mise_check_output" "mise tools are missing"

for mise_status in 90 91 92 93 94 95; do
  mise_check_output="$test_root/mise-check-status-$mise_status.out"
  if FAIL_MISE_LS_STATUS="$mise_status" run_dotfiles "$home" check --skip-brew >"$mise_check_output" 2>&1; then
    fail "check accepted mise exit status $mise_status"
  fi
  assert_contains "$mise_check_output" "check error: mise could not inspect tools"
  assert_contains "$mise_check_output" "fake mise ls status $mise_status"
  assert_not_contains "$mise_check_output" "failed to create temporary directory for mise inspection"
  assert_not_contains "$mise_check_output" "failed to create temporary mise system directory"
  assert_not_contains "$mise_check_output" "failed to copy mise"
  assert_not_contains "$mise_check_output" "failed to remove temporary mise directory"
done

rm "$home/mise-data/tools-installed"
mise_check_output="$test_root/mise-check-missing-tools.out"
if run_dotfiles "$home" check --skip-brew >"$mise_check_output" 2>&1; then
  fail "check accepted missing mise tools"
fi
assert_contains "$mise_check_output" "check failed: mise tools are missing:"
assert_contains "$mise_check_output" "node 24.19.0 missing"
touch "$home/mise-data/tools-installed"

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
