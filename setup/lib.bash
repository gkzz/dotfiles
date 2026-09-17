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

validate_context() {
  case "$HOME$DOTFILES$CONFIG_HOME$DOTFILES_LOCK_DIR" in
    *$'\t'*|*$'\n'*) preflight_error "HOME, repository, config, and lock paths must not contain tabs or newlines" ;;
  esac
  case "$HOME" in /*) ;; *) preflight_error "HOME must be an absolute path: $HOME" ;; esac
  case "$CONFIG_HOME" in /*) ;; *) preflight_error "XDG_CONFIG_HOME must resolve to an absolute path: $CONFIG_HOME" ;; esac
  [ -d "$HOME" ] || preflight_error "HOME does not exist: $HOME"
  [ -r "$HOME" ] || preflight_error "HOME is not readable: $HOME"
}

validate_platform() {
  case "$(uname -s)" in Linux|Darwin) ;; *) preflight_error "unsupported OS: $(uname -s)" ;; esac
  case "$(uname -m)" in x86_64|amd64|aarch64|arm64) ;; *) preflight_error "unsupported architecture: $(uname -m)" ;; esac
  if [ "${BASH_VERSINFO[0]}" -lt 3 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
    preflight_error "Bash 3.2 or newer is required"
  fi
}

validate_install_commands() {
  local command_name
  for command_name in bash cp date dirname env git ln mkdir mktemp mv readlink rm uname; do
    have_cmd "$command_name" || preflight_error "required command is missing: $command_name"
  done
}

validate_check_commands() {
  local command_name
  for command_name in bash cp env git mkdir mktemp readlink rm uname; do
    have_cmd "$command_name" || preflight_error "required command is missing: $command_name"
  done
}

validate_uninstall_commands() {
  have_cmd readlink || preflight_error "required command is missing: readlink"
}

validate_repository() {
  local path
  for path in "$DOTFILES/.bashrc" "$DOTFILES/.bash_profile" "$DOTFILES/.gitconfig" \
    "$DOTFILES/Brewfile" "$MISE_CONFIG_SOURCE" "$MISE_LOCK_SOURCE"; do
    [ -r "$path" ] || preflight_error "required repository file is not readable: $path"
  done
  if [ -r "$DOTFILES/.bashrc" ] && [ -r "$DOTFILES/.bash_profile" ]; then
    bash -n "$DOTFILES/.bashrc" "$DOTFILES/.bash_profile" "$DOTFILES"/bash/*.bash ||
      preflight_error "Bash configuration syntax is invalid"
  fi
  if [ -r "$DOTFILES/.gitconfig" ]; then
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      git config --no-includes --file "$DOTFILES/.gitconfig" --list >/dev/null ||
      preflight_error "Git configuration syntax is invalid: $DOTFILES/.gitconfig"
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
