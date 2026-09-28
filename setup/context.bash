#!/usr/bin/env bash

initialize_setup_context() {
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  MISE_CONFIG_SOURCE="$DOTFILES/mise.toml"
  MISE_LOCK_SOURCE="$DOTFILES/mise.lock"
  MISE_CONFIG_TARGET="$CONFIG_HOME/mise/config.toml"
  DOTFILES_ANCHOR_TARGET="$HOME/.dotfiles"
  MISE_BOOTSTRAP_TARGET="$HOME/.local/bin/mise"
  # Keep coordination anchored to HOME so differing XDG_STATE_HOME values cannot
  # create concurrent writers for the same managed destinations.
  DOTFILES_LOCK_DIR="$HOME/.dotfiles-lifecycle.lock"

  export CONFIG_HOME MISE_CONFIG_SOURCE MISE_LOCK_SOURCE MISE_CONFIG_TARGET DOTFILES_ANCHOR_TARGET
  export MISE_BOOTSTRAP_TARGET DOTFILES_LOCK_DIR
}
