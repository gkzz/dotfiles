#!/usr/bin/env bash

initialize_setup_context() {
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  MISE_CONFIG_SOURCE="$DOTFILES/.config/mise/config.toml"
  MISE_LOCK_SOURCE="$DOTFILES/.config/mise/mise.lock"
  MISE_CONFIG_TARGET="$CONFIG_HOME/mise/config.toml"
  MISE_BOOTSTRAP_TARGET="$HOME/.local/bin/mise"
  # Keep coordination anchored to HOME so differing XDG_STATE_HOME values cannot
  # create concurrent writers for the same managed destinations.
  DOTFILES_LOCK_DIR="$HOME/.dotfiles-lifecycle.lock"

  # Consumed by resources.bash after context initialization.
  # shellcheck disable=SC2034
  MANAGED_SOURCES=(
    "$DOTFILES/.bashrc"
    "$DOTFILES/.bash_profile"
    "$DOTFILES/.gitconfig"
    "$MISE_CONFIG_SOURCE"
  )
  # shellcheck disable=SC2034
  MANAGED_DESTINATIONS=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.gitconfig"
    "$MISE_CONFIG_TARGET"
  )

  export CONFIG_HOME MISE_CONFIG_SOURCE MISE_LOCK_SOURCE MISE_CONFIG_TARGET
  export MISE_BOOTSTRAP_TARGET DOTFILES_LOCK_DIR
}
