#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/test-helper.bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-helper.bash"

home="$test_root/home"
create_converged_home "$home"

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

# Primary preparation and mise failures keep precedence while cleanup failures are also reported.
for combined_failure in prepare mise; do
  combined_output="$test_root/mise-combined-$combined_failure.out"
  set +e
  # Variables in this single-quoted script are intentionally expanded by the child shell.
  # shellcheck disable=SC2016
  env COMBINED_FAILURE="$combined_failure" LIB_FILE="$DOTFILES/setup/lib.bash" \
    PACKAGES_FILE="$DOTFILES/setup/packages.bash" CONFIG_SOURCE="$DOTFILES/.config/mise/config.toml" \
    LOCK_SOURCE="$DOTFILES/.config/mise/mise.lock" bash -c '
      . "$LIB_FILE"
      . "$PACKAGES_FILE"
      CHECK_FAILED=false
      fake_combined_mise() { return 37; }
      MISE_CMD=fake_combined_mise
      MISE_CONFIG_SOURCE="$CONFIG_SOURCE"
      MISE_LOCK_SOURCE="$LOCK_SOURCE"
      mkdir() {
        if [ "$COMBINED_FAILURE" = prepare ]; then
          printf "%s\n" "fake combined mkdir failure" >&2
          return 1
        fi
        command mkdir "$@"
      }
      rm() {
        command rm "$@"
        printf "%s\n" "fake combined cleanup failure" >&2
        return 1
      }
      if run_repository_mise_capture config --json; then
        printf "%s\n" "combined failure unexpectedly succeeded" >&2
        exit 1
      else
        primary_status=$?
      fi
      report_repository_mise_check_error "mise could not load the isolated repository config"
      if [ "$COMBINED_FAILURE" = prepare ]; then
        [ "$primary_status" -eq 1 ]
      else
        [ "$primary_status" -eq 37 ]
      fi
      [ "$REPOSITORY_MISE_RESULT_CLEANUP_STATUS" -ne 0 ]
      [ "$CHECK_FAILED" = true ]
    ' >"$combined_output" 2>&1
  combined_status=$?
  set -e
  [ "$combined_status" -eq 0 ] || fail "combined mise failure test failed: $combined_failure"
done
assert_contains "$test_root/mise-combined-prepare.out" \
  "check error: failed to create temporary mise system directory: path="
assert_contains "$test_root/mise-combined-prepare.out" "fake combined mkdir failure"
assert_contains "$test_root/mise-combined-prepare.out" "check error: failed to remove temporary mise directory: path="
assert_contains "$test_root/mise-combined-prepare.out" "fake combined cleanup failure"
assert_contains "$test_root/mise-combined-mise.out" \
  "check error: mise could not load the isolated repository config"
assert_contains "$test_root/mise-combined-mise.out" "check error: failed to remove temporary mise directory: path="
assert_contains "$test_root/mise-combined-mise.out" "fake combined cleanup failure"

set +e
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

# Check aggregates missing state without repairing it.
rm "$home/.bashrc" "$home/mise-data/tools-installed"
if run_dotfiles "$home" check >/dev/null 2>&1; then fail "check accepted missing resources"; fi
test ! -e "$home/.bashrc"
test ! -e "$home/mise-data/tools-installed"
ln -s "$DOTFILES/.bashrc" "$home/.bashrc"
touch "$home/mise-data/tools-installed"

printf '%s\n' 'check diagnostic tests passed'
