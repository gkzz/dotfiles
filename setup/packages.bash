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
  local mise_command="$MISE_CMD"
  local mise_data_dir="${MISE_DATA_DIR:-}"
  local mise_cache_dir="${MISE_CACHE_DIR:-}"
  local mise_state_dir="${MISE_STATE_DIR:-}"

  mise_project_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise.XXXXXX")" || return 1
  mkdir "$mise_project_root/system" || { rm -rf "$mise_project_root"; return 1; }
  if ! cp "$MISE_CONFIG_SOURCE" "$mise_project_root/config.toml" ||
    ! cp "$MISE_LOCK_SOURCE" "$mise_project_root/mise.lock"; then
    rm -rf "$mise_project_root"
    return 1
  fi

  if (
    local variable_name
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
  ); then
    status=0
  else
    status=$?
  fi
  rm -rf "$mise_project_root"
  return "$status"
}

validate_mise_compatibility() {
  local diagnostic
  if ! diagnostic="$(run_repository_mise config --json 2>&1)"; then
    preflight_error "mise cannot load the isolated repository config: $diagnostic"
  fi
  if ! diagnostic="$(run_repository_mise install --locked --dry-run 2>&1)"; then
    preflight_error "mise cannot validate the repository lockfile: $diagnostic"
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
  [ -n "${MISE_CMD:-}" ] || find_mise || die "mise is unavailable"
  run_repository_mise install --locked --yes
}

check_brew_bundle() {
  if ! find_brew; then
    printf 'check failed: brew is unavailable\n' >&2
    CHECK_FAILED=true
    return
  fi
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$BREW_CMD" bundle check --no-upgrade --file "$DOTFILES/Brewfile"; then
    printf 'check failed: Brewfile dependencies are not satisfied\n' >&2
    CHECK_FAILED=true
  fi
}

check_mise_tools() {
  local missing
  if ! find_mise; then
    printf 'check failed: mise is unavailable\n' >&2
    CHECK_FAILED=true
    return
  fi
  if ! missing="$(run_repository_mise ls --missing --no-header 2>&1)"; then
    printf 'check failed: mise could not inspect tools: %s\n' "$missing" >&2
    CHECK_FAILED=true
    return
  fi
  if [ -n "$missing" ]; then
    printf 'check failed: mise tools are missing:\n%s\n' "$missing" >&2
    # Consumed by lifecycle.bash after all checks finish.
    # shellcheck disable=SC2034
    CHECK_FAILED=true
  fi
}
