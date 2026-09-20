#!/usr/bin/env bash

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

configure_github_actions_environment() {
  if [ "${GITHUB_ACTIONS:-}" != "true" ] || [ -z "${RUNNER_TEMP:-}" ]; then
    return 0
  fi
  DOTFILES_SKIP_BREW="${DOTFILES_SKIP_BREW:-1}"
  MISE_DATA_DIR="${MISE_DATA_DIR:-$RUNNER_TEMP/mise-data}"
  MISE_CACHE_DIR="${MISE_CACHE_DIR:-$RUNNER_TEMP/mise-cache}"
  MISE_STATE_DIR="${MISE_STATE_DIR:-$RUNNER_TEMP/mise-state}"
  export DOTFILES_SKIP_BREW MISE_DATA_DIR MISE_CACHE_DIR MISE_STATE_DIR
}

preflight_error() {
  printf 'error: %s\n' "$*" >&2
  # Consumed by lifecycle.bash after validators return.
  # shellcheck disable=SC2034
  PREFLIGHT_FAILED=true
}

check_failure() {
  printf 'check failed: %s\n' "$*" >&2
  # Consumed by lifecycle.bash after all checks finish.
  # shellcheck disable=SC2034
  CHECK_FAILED=true
}

check_error() {
  printf 'check error: %s\n' "$*" >&2
  # Consumed by lifecycle.bash after all checks finish.
  # shellcheck disable=SC2034
  CHECK_FAILED=true
}

report_check_or_preflight() {
  if [ "${CHECK_MODE:-false}" = true ]; then
    check_failure "$*"
  else
    preflight_error "$*"
  fi
}

report_check_error_or_preflight() {
  if [ "${CHECK_MODE:-false}" = true ]; then
    check_error "$*"
  else
    preflight_error "$*"
  fi
}

validate_context() {
  case "$HOME$DOTFILES$CONFIG_HOME$DOTFILES_LOCK_DIR" in
    *$'\t'*|*$'\n'*) report_check_error_or_preflight "HOME, repository, config, and lock paths must not contain tabs or newlines" ;;
  esac
  case "$HOME" in /*) ;; *) report_check_error_or_preflight "HOME must be an absolute path: $HOME" ;; esac
  case "$CONFIG_HOME" in /*) ;; *) report_check_error_or_preflight "XDG_CONFIG_HOME must resolve to an absolute path: $CONFIG_HOME" ;; esac
  [ -d "$HOME" ] || report_check_error_or_preflight "HOME does not exist: $HOME"
  [ -r "$HOME" ] || report_check_error_or_preflight "HOME is not readable: $HOME"
}

validate_platform() {
  if [ "${CHECK_MODE:-false}" = true ] && [ "${CHECK_HAVE_UNAME:-true}" != true ]; then
    return
  fi
  case "$(uname -s)" in Linux|Darwin) ;; *) report_check_error_or_preflight "unsupported OS: $(uname -s)" ;; esac
  case "$(uname -m)" in x86_64|amd64|aarch64|arm64) ;; *) report_check_error_or_preflight "unsupported architecture: $(uname -m)" ;; esac
  if [ "${BASH_VERSINFO[0]}" -lt 3 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
    report_check_error_or_preflight "Bash 3.2 or newer is required"
  fi
}

validate_install_commands() {
  local command_name
  for command_name in bash cp date dirname env git ln mkdir mktemp mv readlink rm uname; do
    have_cmd "$command_name" || preflight_error "required command is missing: $command_name"
  done
}

validate_check_commands() {
  # Most flags are consumed by lifecycle.bash to skip dependent checks.
  # shellcheck disable=SC2034
  CHECK_HAVE_BASH=true
  CHECK_HAVE_CP=true
  CHECK_HAVE_GIT=true
  CHECK_HAVE_MKDIR=true
  CHECK_HAVE_MKTEMP=true
  CHECK_HAVE_READLINK=true
  CHECK_HAVE_RM=true
  CHECK_HAVE_UNAME=true
  have_cmd bash || { check_error "required command is missing: bash"; CHECK_HAVE_BASH=false; }
  # Flags below are consumed by lifecycle.bash to skip dependent checks.
  # shellcheck disable=SC2034
  have_cmd cp || { check_error "required command is missing: cp"; CHECK_HAVE_CP=false; }
  have_cmd env || check_error "required command is missing: env"
  have_cmd git || { check_error "required command is missing: git"; CHECK_HAVE_GIT=false; }
  # shellcheck disable=SC2034
  have_cmd mkdir || { check_error "required command is missing: mkdir"; CHECK_HAVE_MKDIR=false; }
  # shellcheck disable=SC2034
  have_cmd mktemp || { check_error "required command is missing: mktemp"; CHECK_HAVE_MKTEMP=false; }
  # shellcheck disable=SC2034
  have_cmd readlink || { check_error "required command is missing: readlink"; CHECK_HAVE_READLINK=false; }
  # shellcheck disable=SC2034
  have_cmd rm || { check_error "required command is missing: rm"; CHECK_HAVE_RM=false; }
  have_cmd uname || { check_error "required command is missing: uname"; CHECK_HAVE_UNAME=false; }
}

validate_uninstall_commands() {
  have_cmd readlink || preflight_error "required command is missing: readlink"
}

validate_repository() {
  local path
  for path in "$DOTFILES/.bashrc" "$DOTFILES/.bash_profile" "$DOTFILES/.gitconfig" \
    "$DOTFILES/Brewfile" "$MISE_CONFIG_SOURCE" "$MISE_LOCK_SOURCE"; do
    [ -r "$path" ] || report_check_or_preflight "required repository file is not readable: $path"
  done
  if [ -r "$DOTFILES/.bashrc" ] && [ -r "$DOTFILES/.bash_profile" ] &&
    [ "${CHECK_HAVE_BASH:-true}" = true ]; then
    bash -n "$DOTFILES/.bashrc" "$DOTFILES/.bash_profile" "$DOTFILES"/bash/*.bash ||
      report_check_or_preflight "Bash configuration syntax is invalid"
  fi
  if [ -r "$DOTFILES/.gitconfig" ] && [ "${CHECK_HAVE_GIT:-true}" = true ]; then
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      git config --no-includes --file "$DOTFILES/.gitconfig" --list >/dev/null ||
      report_check_or_preflight "Git configuration syntax is invalid: $DOTFILES/.gitconfig"
  fi
}

nearest_existing_parent() {
  local path="$1"
  local parent
  while [ ! -e "$path" ] && [ ! -L "$path" ]; do
    parent="${path%/*}"
    [ "$parent" != "$path" ] || parent=/
    path="$parent"
  done
  printf '%s\n' "$path"
}

validate_destination_parent() {
  local destination="$1"
  local parent
  parent="${destination%/*}"
  [ "$parent" != "$destination" ] || parent=/
  parent="$(nearest_existing_parent "$parent")"
  [ -d "$parent" ] || { preflight_error "destination parent is not a directory: $parent"; return; }
  [ -w "$parent" ] || preflight_error "destination parent is not writable: $parent"
  [ -x "$parent" ] || preflight_error "destination parent is not searchable: $parent"
}
