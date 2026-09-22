#!/usr/bin/env bash

find_brew() {
  local candidate
  if have_cmd brew && [ -f "$(command -v brew)" ]; then
    BREW_CMD="$(command -v brew)"
    return 0
  fi
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
      BREW_CMD="$candidate"
      return 0
    fi
  done
  BREW_CMD=""
  return 1
}

find_mise() {
  if have_cmd mise; then
    MISE_CMD="$(command -v mise)"
    return 0
  fi
  if [ -f "$MISE_BOOTSTRAP_TARGET" ] && [ -x "$MISE_BOOTSTRAP_TARGET" ]; then
    MISE_CMD="$MISE_BOOTSTRAP_TARGET"
    return 0
  fi
  MISE_CMD=""
  return 1
}

# Result state is reset by the orchestrator, written by the prepare/execute/cleanup
# helper responsible for each field, and read by formatters until the next call.
reset_repository_mise_result() {
  REPOSITORY_MISE_RESULT_STAGE=""
  REPOSITORY_MISE_RESULT_REASON=""
  REPOSITORY_MISE_RESULT_STATUS=""
  REPOSITORY_MISE_RESULT_STDOUT=""
  REPOSITORY_MISE_RESULT_STDERR=""
  REPOSITORY_MISE_RESULT_CLEANUP_STATUS=0
  REPOSITORY_MISE_RESULT_CLEANUP_STDERR=""
  REPOSITORY_MISE_RESULT_TEMP_PATH=""
}

prepare_repository_mise_environment() {
  local output

  if ! output="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise.XXXXXX" 2>&1)"; then
    REPOSITORY_MISE_RESULT_STAGE=prepare
    REPOSITORY_MISE_RESULT_REASON=mktemp
    REPOSITORY_MISE_RESULT_STDERR="$output"
    return 1
  fi
  REPOSITORY_MISE_RESULT_TEMP_PATH="$output"
  if ! output="$(mkdir "$REPOSITORY_MISE_RESULT_TEMP_PATH/system" 2>&1)"; then
    REPOSITORY_MISE_RESULT_STAGE=prepare
    REPOSITORY_MISE_RESULT_REASON="mkdir"
  elif ! output="$(cp "$MISE_CONFIG_SOURCE" "$REPOSITORY_MISE_RESULT_TEMP_PATH/config.toml" 2>&1)"; then
    REPOSITORY_MISE_RESULT_STAGE=prepare
    REPOSITORY_MISE_RESULT_REASON=config-copy
  elif ! output="$(cp "$MISE_LOCK_SOURCE" "$REPOSITORY_MISE_RESULT_TEMP_PATH/mise.lock" 2>&1)"; then
    REPOSITORY_MISE_RESULT_STAGE=prepare
    REPOSITORY_MISE_RESULT_REASON=lock-copy
  else
    return 0
  fi
  REPOSITORY_MISE_RESULT_STDERR="$output"
  return 1
}

execute_repository_mise_capture() {
  local stderr_path="$REPOSITORY_MISE_RESULT_TEMP_PATH/stderr"
  local stdout_path="$REPOSITORY_MISE_RESULT_TEMP_PATH/stdout"
  local status

  if (run_isolated_mise "$REPOSITORY_MISE_RESULT_TEMP_PATH" "$MISE_CMD" \
    "${MISE_DATA_DIR:-}" "${MISE_CACHE_DIR:-}" "${MISE_STATE_DIR:-}" "$@" \
    >"$stdout_path" 2>"$stderr_path"); then
    status=0
  else
    status=$?
  fi
  # The status is part of the diagnostic state consumed by callers/tests.
  # shellcheck disable=SC2034
  REPOSITORY_MISE_RESULT_STATUS="$status"
  REPOSITORY_MISE_RESULT_STDOUT="$(<"$stdout_path")"
  REPOSITORY_MISE_RESULT_STDERR="$(<"$stderr_path")"
  if [ "$status" -ne 0 ]; then
    REPOSITORY_MISE_RESULT_STAGE=mise
    REPOSITORY_MISE_RESULT_REASON=mise
  fi
  return "$status"
}

execute_repository_mise_stream() {
  local status

  if (run_isolated_mise "$REPOSITORY_MISE_RESULT_TEMP_PATH" "$MISE_CMD" \
    "${MISE_DATA_DIR:-}" "${MISE_CACHE_DIR:-}" "${MISE_STATE_DIR:-}" "$@"); then
    status=0
  else
    status=$?
  fi
  # The status is part of the diagnostic state consumed by callers/tests.
  # shellcheck disable=SC2034
  REPOSITORY_MISE_RESULT_STATUS="$status"
  if [ "$status" -ne 0 ]; then
    REPOSITORY_MISE_RESULT_STAGE=mise
    REPOSITORY_MISE_RESULT_REASON=mise
  fi
  return "$status"
}

cleanup_repository_mise_environment() {
  local output
  local status

  [ -n "$REPOSITORY_MISE_RESULT_TEMP_PATH" ] || return 0
  if output="$(rm -rf "$REPOSITORY_MISE_RESULT_TEMP_PATH" 2>&1)"; then
    status=0
  else
    status=$?
  fi
  REPOSITORY_MISE_RESULT_CLEANUP_STATUS="$status"
  REPOSITORY_MISE_RESULT_CLEANUP_STDERR="$output"
  if [ "$status" -ne 0 ] && [ -z "$REPOSITORY_MISE_RESULT_STAGE" ]; then
    REPOSITORY_MISE_RESULT_STAGE=cleanup
    REPOSITORY_MISE_RESULT_REASON=cleanup
  fi
  return "$status"
}

run_repository_mise_with_io() {
  local io_mode="$1"
  local primary_status=0
  shift

  reset_repository_mise_result
  case "$io_mode" in
    capture|stream) ;;
    *)
      printf 'error: unknown repository mise I/O mode: %s\n' "$io_mode" >&2
      return 2
      ;;
  esac
  if prepare_repository_mise_environment; then
    case "$io_mode" in
      capture) execute_repository_mise_capture "$@" || primary_status=$? ;;
      stream) execute_repository_mise_stream "$@" || primary_status=$? ;;
    esac
  else
    primary_status=1
  fi
  cleanup_repository_mise_environment || true
  [ "$primary_status" -eq 0 ] || return "$primary_status"
  [ "$REPOSITORY_MISE_RESULT_CLEANUP_STATUS" -eq 0 ] || return 1
}

run_repository_mise_capture() {
  run_repository_mise_with_io capture "$@"
}

run_repository_mise_apply() {
  run_repository_mise_with_io stream "$@"
}

run_isolated_mise() {
  local mise_project_root="$1"
  local mise_command="$2"
  local mise_data_dir="$3"
  local mise_cache_dir="$4"
  local mise_state_dir="$5"
  local variable_name
  shift 5

  for variable_name in ${!MISE_@}; do
    unset "$variable_name"
  done
  export MISE_CONFIG_DIR="$mise_project_root"
  export MISE_SYSTEM_CONFIG_DIR="$mise_project_root/system"
  export MISE_GLOBAL_CONFIG_FILE="$mise_project_root/config.toml"
  export MISE_GLOBAL_CONFIG_ROOT="$mise_project_root"
  export MISE_CEILING_PATHS="$mise_project_root"
  export MISE_OVERRIDE_CONFIG_FILENAMES=.dotfiles-no-project-config.toml
  export MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES=none
  export MISE_SYSTEM_CONFIG_FILE="$mise_project_root/config.toml"
  export MISE_NO_ENV=1 MISE_NO_HOOKS=1
  MISE_DATA_DIR="$mise_data_dir"
  MISE_CACHE_DIR="$mise_cache_dir"
  MISE_STATE_DIR="$mise_state_dir"
  [ -z "${MISE_DATA_DIR:-}" ] || export MISE_DATA_DIR
  [ -z "${MISE_CACHE_DIR:-}" ] || export MISE_CACHE_DIR
  [ -z "${MISE_STATE_DIR:-}" ] || export MISE_STATE_DIR
  [ -z "${TMPDIR:-}" ] || export TMPDIR
  "$mise_command" --cd "$mise_project_root" "$@"
}

report_repository_mise_check_error() {
  local operation_message="$1"

  case "$REPOSITORY_MISE_RESULT_REASON" in
    mktemp) verify_error "failed to create temporary directory for mise inspection" ;;
    mkdir) verify_error "failed to create temporary mise system directory: path=$REPOSITORY_MISE_RESULT_TEMP_PATH/system" ;;
    config-copy) verify_error "failed to copy mise config into temporary directory: source=$MISE_CONFIG_SOURCE" ;;
    lock-copy) verify_error "failed to copy mise lockfile into temporary directory: source=$MISE_LOCK_SOURCE" ;;
    mise) verify_error "$operation_message" ;;
  esac
  [ -z "$REPOSITORY_MISE_RESULT_STDOUT" ] || printf '%s\n' "$REPOSITORY_MISE_RESULT_STDOUT" >&2
  [ -z "$REPOSITORY_MISE_RESULT_STDERR" ] || printf '%s\n' "$REPOSITORY_MISE_RESULT_STDERR" >&2
  if [ "$REPOSITORY_MISE_RESULT_CLEANUP_STATUS" -ne 0 ]; then
    verify_error "failed to remove temporary mise directory: path=$REPOSITORY_MISE_RESULT_TEMP_PATH"
    [ -z "$REPOSITORY_MISE_RESULT_CLEANUP_STDERR" ] ||
      printf '%s\n' "$REPOSITORY_MISE_RESULT_CLEANUP_STDERR" >&2
  fi
}

report_repository_mise_preflight_error() {
  local operation_message="$1"

  case "$REPOSITORY_MISE_RESULT_REASON" in
    mktemp) preflight_error "failed to create temporary directory for mise inspection" ;;
    mkdir) preflight_error "failed to create temporary mise system directory: path=$REPOSITORY_MISE_RESULT_TEMP_PATH/system" ;;
    config-copy) preflight_error "failed to copy mise config into temporary directory: source=$MISE_CONFIG_SOURCE" ;;
    lock-copy) preflight_error "failed to copy mise lockfile into temporary directory: source=$MISE_LOCK_SOURCE" ;;
    mise) preflight_error "$operation_message" ;;
  esac
  [ -z "$REPOSITORY_MISE_RESULT_STDOUT" ] || printf '%s\n' "$REPOSITORY_MISE_RESULT_STDOUT" >&2
  [ -z "$REPOSITORY_MISE_RESULT_STDERR" ] || printf '%s\n' "$REPOSITORY_MISE_RESULT_STDERR" >&2
  if [ "$REPOSITORY_MISE_RESULT_CLEANUP_STATUS" -ne 0 ]; then
    preflight_error "failed to remove temporary mise directory: path=$REPOSITORY_MISE_RESULT_TEMP_PATH"
    [ -z "$REPOSITORY_MISE_RESULT_CLEANUP_STDERR" ] ||
      printf '%s\n' "$REPOSITORY_MISE_RESULT_CLEANUP_STDERR" >&2
  fi
}

validate_repository_mise_config() {
  run_repository_mise_capture config --json
}

validate_repository_mise_lock() {
  run_repository_mise_capture install --locked --dry-run
}

print_repository_mise_success_stderr() {
  [ -z "$REPOSITORY_MISE_RESULT_STDERR" ] ||
    printf '%s\n' "$REPOSITORY_MISE_RESULT_STDERR" >&2
}

validate_mise_compatibility() {
  local status
  if validate_repository_mise_config; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    report_repository_mise_preflight_error "mise cannot load the isolated repository config"
  else
    print_repository_mise_success_stderr
  fi
  if validate_repository_mise_lock; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    report_repository_mise_preflight_error "mise cannot validate the repository lockfile"
  else
    print_repository_mise_success_stderr
  fi
}

check_mise_compatibility() {
  if validate_repository_mise_config; then
    print_repository_mise_success_stderr
  else
    report_repository_mise_check_error "mise could not load the isolated repository config"
  fi
  if validate_repository_mise_lock; then
    print_repository_mise_success_stderr
  else
    report_repository_mise_check_error "mise could not validate the repository lockfile"
  fi
}

validate_mise_bootstrap() {
  if ! have_cmd curl; then
    preflight_error "mise bootstrap requires curl"
  fi
  if ! have_cmd sha256sum && ! have_cmd shasum; then
    preflight_error "mise bootstrap requires sha256sum or shasum"
  fi
  have_cmd install || preflight_error "mise bootstrap requires install"
  if [ -e "$MISE_BOOTSTRAP_TARGET" ] || [ -L "$MISE_BOOTSTRAP_TARGET" ]; then
    preflight_error "mise bootstrap target conflicts: $MISE_BOOTSTRAP_TARGET"
    return
  fi
  validate_destination_parent "$MISE_BOOTSTRAP_TARGET"
}

validate_mise_with_temporary_bootstrap() {
  local bootstrap_root
  local previous_mise_cmd="${MISE_CMD:-}"

  bootstrap_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise-bootstrap.XXXXXX")" || {
    preflight_error "failed to create temporary directory for mise validation"
    return
  }
  if DOTFILES_MISE_BOOTSTRAP_TARGET="$bootstrap_root/mise" \
    "$DOTFILES/setup/mise-install.sh" --apply >/dev/null 2>&1; then
    MISE_CMD="$bootstrap_root/mise"
    validate_mise_compatibility
  else
    preflight_error "failed to bootstrap temporary mise for lockfile validation"
  fi
  MISE_CMD="$previous_mise_cmd"
  rm -rf "$bootstrap_root"
}

validate_homebrew_bootstrap() {
  have_cmd curl || preflight_error "Homebrew bootstrap requires curl"
  [ -x /bin/bash ] || preflight_error "Homebrew bootstrap requires /bin/bash"
}

bootstrap_homebrew_action() {
  "$DOTFILES/setup/homebrew-install.sh" --apply
  find_brew || die "Homebrew installer completed but brew was not found"
  eval "$("$BREW_CMD" shellenv)"
}

bootstrap_mise_action() {
  local target="$1"
  DOTFILES_MISE_BOOTSTRAP_TARGET="$target" "$DOTFILES/setup/mise-install.sh" --apply
  [ -x "$target" ] || die "mise installer did not create an executable: $target"
  MISE_CMD="$target"
}

apply_brew_bundle() {
  [ -n "${BREW_CMD:-}" ] || find_brew || die "brew is unavailable"
  HOMEBREW_NO_AUTO_UPDATE=1 "$BREW_CMD" bundle --file "$DOTFILES/Brewfile" --no-upgrade
}

apply_mise_tools() {
  local status
  [ -n "${MISE_CMD:-}" ] || find_mise || die "mise is unavailable"
  if run_repository_mise_apply install --locked --yes; then
    return 0
  else
    status=$?
  fi
  case "$REPOSITORY_MISE_RESULT_REASON" in
    mktemp) printf '%s\n' 'failed to create temporary directory for mise inspection' >&2 ;;
    mkdir) printf 'failed to create temporary mise system directory: path=%s/system\n' "$REPOSITORY_MISE_RESULT_TEMP_PATH" >&2 ;;
    config-copy) printf 'failed to copy mise config into temporary directory: source=%s\n' "$MISE_CONFIG_SOURCE" >&2 ;;
    lock-copy) printf 'failed to copy mise lockfile into temporary directory: source=%s\n' "$MISE_LOCK_SOURCE" >&2 ;;
  esac
  case "$REPOSITORY_MISE_RESULT_REASON" in
    mktemp|mkdir|config-copy|lock-copy)
      [ -z "$REPOSITORY_MISE_RESULT_STDERR" ] || printf '%s\n' "$REPOSITORY_MISE_RESULT_STDERR" >&2
      ;;
  esac
  if [ "$REPOSITORY_MISE_RESULT_CLEANUP_STATUS" -ne 0 ]; then
    printf 'failed to remove temporary mise directory: path=%s\n' "$REPOSITORY_MISE_RESULT_TEMP_PATH" >&2
    [ -z "$REPOSITORY_MISE_RESULT_CLEANUP_STDERR" ] ||
      printf '%s\n' "$REPOSITORY_MISE_RESULT_CLEANUP_STDERR" >&2
  fi
  return "$status"
}

check_brew_bundle() {
  if ! find_brew; then
    verify_error "brew is unavailable"
    return
  fi
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$BREW_CMD" bundle check --no-upgrade --file "$DOTFILES/Brewfile"; then
    verify_failure "Brewfile dependencies are not satisfied"
  fi
}

check_mise_tools() {
  local status
  if [ -z "${MISE_CMD:-}" ] && ! find_mise; then
    verify_error "mise is unavailable"
    return
  fi
  if run_repository_mise_capture ls --missing --no-header; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    report_repository_mise_check_error "mise could not inspect tools"
    return
  fi
  [ -z "$REPOSITORY_MISE_RESULT_STDERR" ] || printf '%s\n' "$REPOSITORY_MISE_RESULT_STDERR" >&2
  if [ -n "$REPOSITORY_MISE_RESULT_STDOUT" ]; then
    printf 'verify failed: mise tools are missing:\n%s\n' "$REPOSITORY_MISE_RESULT_STDOUT" >&2
    # Consumed by lifecycle.bash after all checks finish.
    # shellcheck disable=SC2034
    CHECK_FAILED=true
  fi
}
