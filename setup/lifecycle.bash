#!/usr/bin/env bash

# shellcheck source=setup/lib.bash
. "$DOTFILES/setup/lib.bash"
# shellcheck source=setup/context.bash
. "$DOTFILES/setup/context.bash"
# shellcheck source=setup/plan.bash
. "$DOTFILES/setup/plan.bash"
# shellcheck source=setup/symlinks.bash
. "$DOTFILES/setup/symlinks.bash"
# shellcheck source=setup/packages.bash
. "$DOTFILES/setup/packages.bash"

LIFECYCLE_LOCK_HELD=false
lifecycle_lock_release() {
  if [ "$LIFECYCLE_LOCK_HELD" = "true" ]; then
    rm -f "$DOTFILES_LOCK_DIR/pid"
    rmdir "$DOTFILES_LOCK_DIR" 2>/dev/null || true
    LIFECYCLE_LOCK_HELD=false
  fi
}

lifecycle_lock_validate() {
  local command_name
  local path

  case "$HOME" in
    /*) ;;
    *) die "HOME must be an absolute path before acquiring the lifecycle lock: $HOME" ;;
  esac
  [ -d "$HOME" ] || die "HOME does not exist: $HOME"
  case "$HOME$DOTFILES_LOCK_DIR" in
    *$'\t'*|*$'\n'*) die "HOME and lock paths must not contain tabs or newlines" ;;
  esac
  for command_name in kill mkdir rm rmdir; do
    have_cmd "$command_name" || die "required lock command is missing: $command_name"
  done
  path="$DOTFILES_LOCK_DIR"
  while :; do
    [ ! -L "$path" ] || die "lifecycle lock path component must not be a symlink: $path"
    [ "$path" = "$HOME" ] && break
    case "$path" in
      "$HOME"/*) ;;
      *) die "lifecycle lock path must be inside HOME: $path" ;;
    esac
    path="${path%/*}"
  done
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    die "lifecycle lock path component is not a directory: $path"
  fi
}

obsolete_lifecycle_lock_remove_if_stale() {
  local recorded_pid=""

  if [ -L "$DOTFILES_LOCK_DIR/pid" ] ||
    { [ -e "$DOTFILES_LOCK_DIR/pid" ] && [ ! -f "$DOTFILES_LOCK_DIR/pid" ]; }; then
    return 1
  fi
  if [ -r "$DOTFILES_LOCK_DIR/pid" ]; then
    local line
    local line_count=0
    while IFS= read -r line || [ -n "$line" ]; do
      line_count=$((line_count + 1))
      [ "$line_count" -eq 1 ] || return 1
      recorded_pid="$line"
    done < "$DOTFILES_LOCK_DIR/pid"
    [ "$line_count" -eq 1 ] || return 1
  fi
  case "$recorded_pid" in
    ''|0|*[!0-9]*) return 1 ;;
    *)
      if kill -0 "$recorded_pid" 2>/dev/null; then
        return 1
      fi
      ;;
  esac

  rm -f "$DOTFILES_LOCK_DIR/pid" || return 1
  if ! rmdir "$DOTFILES_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$recorded_pid" > "$DOTFILES_LOCK_DIR/pid" 2>/dev/null || true
    return 1
  fi
  log "recovered stale lifecycle lock: $DOTFILES_LOCK_DIR"
}

lifecycle_lock_acquire() {
  lifecycle_lock_validate
  if ! (umask 077 && mkdir "$DOTFILES_LOCK_DIR") 2>/dev/null; then
    obsolete_lifecycle_lock_remove_if_stale ||
      die "lifecycle lock exists; verify the owner and remove it manually if stale: $DOTFILES_LOCK_DIR"
    (umask 077 && mkdir "$DOTFILES_LOCK_DIR") 2>/dev/null ||
      die "failed to reclaim lifecycle lock: $DOTFILES_LOCK_DIR"
  fi
  if ! printf '%s\n' "$$" > "$DOTFILES_LOCK_DIR/pid"; then
    rm -f "$DOTFILES_LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$DOTFILES_LOCK_DIR" 2>/dev/null || true
    die "failed to initialize lifecycle lock: $DOTFILES_LOCK_DIR"
  fi
  LIFECYCLE_LOCK_HELD=true
  trap lifecycle_lock_release EXIT
  trap 'exit 130' HUP INT TERM
}

preflight_common() {
  local command_validator="$1"
  local execution_reporter="$2"
  local state_reporter="$3"
  PREFLIGHT_FAILED=false
  validate_managed_resources_definition
  validate_context "$execution_reporter"
  "$command_validator"
  validate_platform "$execution_reporter"
  validate_repository "$state_reporter"
}

preflight_install() {
  plan_reset
  HOMEBREW_BOOTSTRAP_NEEDED=false
  MISE_BOOTSTRAP_NEEDED=false
  preflight_common validate_install_commands preflight_error preflight_error
  preflight_managed_links

  # A known filesystem conflict must stop package-manager inspection and apply.
  [ "$PREFLIGHT_FAILED" = "false" ] || return 1

  if "${skip_brew:-false}" || [ "${DOTFILES_SKIP_BREW:-}" = "1" ]; then
    log "skip: Homebrew inspection and actions disabled"
  else
    if find_brew; then
      :
    else
      validate_homebrew_bootstrap
      HOMEBREW_BOOTSTRAP_NEEDED=true
    fi
  fi

  if find_mise; then
    validate_mise_compatibility
  else
    validate_mise_bootstrap
    [ "$PREFLIGHT_FAILED" = "true" ] || validate_mise_with_temporary_bootstrap
    MISE_BOOTSTRAP_NEEDED=true
  fi

  [ "$PREFLIGHT_FAILED" = "false" ] || return 1
  build_install_plan
  [ "$PREFLIGHT_FAILED" = "false" ]
}

build_install_plan() {
  if ! "${skip_brew:-false}" && [ "${DOTFILES_SKIP_BREW:-}" != "1" ]; then
    [ "${HOMEBREW_BOOTSTRAP_NEEDED:-false}" = "true" ] &&
      plan_add bootstrap_homebrew brew
  fi
  [ "${MISE_BOOTSTRAP_NEEDED:-false}" = "true" ] &&
    plan_add bootstrap_mise "$MISE_BOOTSTRAP_TARGET"
  if ! "${skip_brew:-false}" && [ "${DOTFILES_SKIP_BREW:-}" != "1" ]; then
    plan_add brew_bundle "$DOTFILES/Brewfile"
  fi
  plan_add mise_install "$MISE_CONFIG_SOURCE"
  plan_managed_links
}

install_lifecycle() {
  if ! "${dry_run:-true}"; then
    lifecycle_lock_acquire
  fi
  if ! preflight_install; then
    die "install preflight failed"
  fi
  plan_print
  "${dry_run:-true}" && return 0
  plan_execute
}

check_lifecycle() {
  CHECK_FAILED=false
  preflight_common validate_check_commands check_error check_failure
  if [ "$PREFLIGHT_FAILED" = "true" ]; then
    CHECK_FAILED=true
  fi

  if [ "${CHECK_HAVE_READLINK:-true}" = true ]; then
    check_managed_links
  fi
  if ! "${skip_brew:-false}" && [ "${DOTFILES_SKIP_BREW:-}" != "1" ] &&
    [ -r "$DOTFILES/Brewfile" ]; then
    check_brew_bundle
  fi
  if [ -r "$MISE_CONFIG_SOURCE" ] && [ -r "$MISE_LOCK_SOURCE" ] &&
    [ "${CHECK_HAVE_CP:-true}" = true ] && [ "${CHECK_HAVE_MKDIR:-true}" = true ] &&
    [ "${CHECK_HAVE_MKTEMP:-true}" = true ] && [ "${CHECK_HAVE_RM:-true}" = true ]; then
    if find_mise; then
      check_mise_compatibility
      check_mise_tools
    else
      check_error "mise is unavailable"
    fi
  fi

  [ "$CHECK_FAILED" = "false" ] || return 1
  log "check complete"
}

preflight_uninstall() {
  plan_reset
  PREFLIGHT_FAILED=false
  validate_managed_resources_definition
  validate_context preflight_error
  validate_uninstall_commands
  preflight_uninstall_links
  [ "$PREFLIGHT_FAILED" = "false" ]
}

uninstall_lifecycle() {
  if ! "${dry_run:-true}"; then
    lifecycle_lock_acquire
  fi
  if ! preflight_uninstall; then
    die "uninstall preflight failed"
  fi
  plan_print
  "${dry_run:-true}" && return 0
  plan_execute
}
