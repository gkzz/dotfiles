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

run_repository_mise() {
  local mise_project_root
  local status
  local cleanup_output
  local operation_output
  local mise_command="$MISE_CMD"
  local mise_data_dir="${MISE_DATA_DIR:-}"
  local mise_cache_dir="${MISE_CACHE_DIR:-}"
  local mise_state_dir="${MISE_STATE_DIR:-}"

  RUN_REPOSITORY_MISE_FAILURE=""
  RUN_REPOSITORY_MISE_OUTPUT=""
  RUN_REPOSITORY_MISE_CLEANUP_FAILED=false
  RUN_REPOSITORY_MISE_CLEANUP_OUTPUT=""
  RUN_REPOSITORY_MISE_TEMP_PATH=""

  if ! mise_project_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise.XXXXXX" 2>&1)"; then
    RUN_REPOSITORY_MISE_FAILURE=mktemp
    RUN_REPOSITORY_MISE_OUTPUT="$mise_project_root"
    if [ "${RUN_REPOSITORY_MISE_CAPTURE:-false}" != true ]; then
      printf '%s\n' 'failed to create temporary directory for mise inspection' "$mise_project_root" >&2
    fi
    return 1
  fi
  RUN_REPOSITORY_MISE_TEMP_PATH="$mise_project_root"
  if ! operation_output="$(mkdir "$mise_project_root/system" 2>&1)"; then
    RUN_REPOSITORY_MISE_FAILURE="mkdir"
    RUN_REPOSITORY_MISE_OUTPUT="$operation_output"
    status=1
  elif ! operation_output="$(cp "$MISE_CONFIG_SOURCE" "$mise_project_root/config.toml" 2>&1)"; then
    RUN_REPOSITORY_MISE_FAILURE=config-copy
    RUN_REPOSITORY_MISE_OUTPUT="$operation_output"
    status=1
  elif ! operation_output="$(cp "$MISE_LOCK_SOURCE" "$mise_project_root/mise.lock" 2>&1)"; then
    RUN_REPOSITORY_MISE_FAILURE=lock-copy
    RUN_REPOSITORY_MISE_OUTPUT="$operation_output"
    status=1
  else
    status=0
  fi

  if [ "$status" -eq 0 ]; then
    if [ "${RUN_REPOSITORY_MISE_CAPTURE:-false}" = true ]; then
      if RUN_REPOSITORY_MISE_OUTPUT="$(run_isolated_mise "$mise_project_root" "$mise_command" \
        "$mise_data_dir" "$mise_cache_dir" "$mise_state_dir" "$@" 2>&1)"; then
        status=0
      else
        status=$?
      fi
    else
      if (run_isolated_mise "$mise_project_root" "$mise_command" \
        "$mise_data_dir" "$mise_cache_dir" "$mise_state_dir" "$@"); then
        status=0
      else
        status=$?
      fi
    fi
    if [ "$status" -ne 0 ]; then
      RUN_REPOSITORY_MISE_FAILURE=mise
    fi
  fi
  if [ "${RUN_REPOSITORY_MISE_CAPTURE:-false}" != true ]; then
    case "$RUN_REPOSITORY_MISE_FAILURE" in
      mkdir) printf 'failed to create temporary mise system directory: path=%s\n' "$mise_project_root/system" >&2 ;;
      config-copy) printf 'failed to copy mise config into temporary directory: source=%s\n' "$MISE_CONFIG_SOURCE" >&2 ;;
      lock-copy) printf 'failed to copy mise lockfile into temporary directory: source=%s\n' "$MISE_LOCK_SOURCE" >&2 ;;
    esac
    case "$RUN_REPOSITORY_MISE_FAILURE" in
      mkdir|config-copy|lock-copy) [ -z "$RUN_REPOSITORY_MISE_OUTPUT" ] || printf '%s\n' "$RUN_REPOSITORY_MISE_OUTPUT" >&2 ;;
    esac
  fi
  if ! cleanup_output="$(rm -rf "$mise_project_root" 2>&1)"; then
    RUN_REPOSITORY_MISE_CLEANUP_FAILED=true
    RUN_REPOSITORY_MISE_CLEANUP_OUTPUT="$cleanup_output"
    RUN_REPOSITORY_MISE_CLEANUP_PATH="$mise_project_root"
    if [ "${RUN_REPOSITORY_MISE_CAPTURE:-false}" != true ]; then
      printf 'failed to remove temporary mise directory: path=%s\n' "$mise_project_root" >&2
      [ -z "$cleanup_output" ] || printf '%s\n' "$cleanup_output" >&2
    fi
    if [ "$status" -eq 0 ]; then
      status=1
    fi
  fi
  return "$status"
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

  case "$RUN_REPOSITORY_MISE_FAILURE" in
    mktemp) check_error "failed to create temporary directory for mise inspection" ;;
    mkdir) check_error "failed to create temporary mise system directory: path=$RUN_REPOSITORY_MISE_TEMP_PATH/system" ;;
    config-copy) check_error "failed to copy mise config into temporary directory: source=$MISE_CONFIG_SOURCE" ;;
    lock-copy) check_error "failed to copy mise lockfile into temporary directory: source=$MISE_LOCK_SOURCE" ;;
    mise) check_error "$operation_message" ;;
  esac
  [ -z "$RUN_REPOSITORY_MISE_OUTPUT" ] || printf '%s\n' "$RUN_REPOSITORY_MISE_OUTPUT" >&2
  if [ "$RUN_REPOSITORY_MISE_CLEANUP_FAILED" = true ]; then
    check_error "failed to remove temporary mise directory: path=$RUN_REPOSITORY_MISE_CLEANUP_PATH"
    [ -z "$RUN_REPOSITORY_MISE_CLEANUP_OUTPUT" ] || printf '%s\n' "$RUN_REPOSITORY_MISE_CLEANUP_OUTPUT" >&2
  fi
}

validate_mise_compatibility() {
  local status
  RUN_REPOSITORY_MISE_CAPTURE=true
  if run_repository_mise config --json; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    if [ "${CHECK_MODE:-false}" = true ]; then
      report_repository_mise_check_error "mise could not load the isolated repository config"
    else
      preflight_error "mise cannot load the isolated repository config: $RUN_REPOSITORY_MISE_OUTPUT"
    fi
  fi
  if run_repository_mise install --locked --dry-run; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    if [ "${CHECK_MODE:-false}" = true ]; then
      report_repository_mise_check_error "mise could not validate the repository lockfile"
    else
      preflight_error "mise cannot validate the repository lockfile: $RUN_REPOSITORY_MISE_OUTPUT"
    fi
  fi
  RUN_REPOSITORY_MISE_CAPTURE=false
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
  [ -n "${MISE_CMD:-}" ] || find_mise || die "mise is unavailable"
  run_repository_mise install --locked --yes
}

check_brew_bundle() {
  if ! find_brew; then
    check_error "brew is unavailable"
    return
  fi
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$BREW_CMD" bundle check --no-upgrade --file "$DOTFILES/Brewfile"; then
    check_failure "Brewfile dependencies are not satisfied"
  fi
}

check_mise_tools() {
  local status
  if [ -z "${MISE_CMD:-}" ] && ! find_mise; then
    check_error "mise is unavailable"
    return
  fi
  RUN_REPOSITORY_MISE_CAPTURE=true
  if run_repository_mise ls --missing --no-header; then
    status=0
  else
    status=$?
  fi
  if [ "$status" -ne 0 ]; then
    report_repository_mise_check_error "mise could not inspect tools"
    RUN_REPOSITORY_MISE_CAPTURE=false
    return
  fi
  if [ -n "$RUN_REPOSITORY_MISE_OUTPUT" ]; then
    printf 'check failed: mise tools are missing:\n%s\n' "$RUN_REPOSITORY_MISE_OUTPUT" >&2
    # Consumed by lifecycle.bash after all checks finish.
    # shellcheck disable=SC2034
    CHECK_FAILED=true
  fi
  RUN_REPOSITORY_MISE_CAPTURE=false
}
