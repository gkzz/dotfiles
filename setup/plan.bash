#!/usr/bin/env bash

plan_reset() {
  PLAN_TYPES=()
  PLAN_TARGETS=()
  PLAN_DETAILS=()
}

plan_add() {
  PLAN_TYPES[${#PLAN_TYPES[@]}]="$1"
  PLAN_TARGETS[${#PLAN_TARGETS[@]}]="$2"
  PLAN_DETAILS[${#PLAN_DETAILS[@]}]="${3:-}"
}

plan_print() {
  local index
  for ((index = 0; index < ${#PLAN_TYPES[@]}; index++)); do
    if [ -n "${PLAN_DETAILS[$index]}" ]; then
      log "plan: ${PLAN_TYPES[$index]} ${PLAN_TARGETS[$index]} <- ${PLAN_DETAILS[$index]}"
    else
      log "plan: ${PLAN_TYPES[$index]} ${PLAN_TARGETS[$index]}"
    fi
  done
}

plan_execute() {
  local index
  local type
  local target

  for ((index = 0; index < ${#PLAN_TYPES[@]}; index++)); do
    type="${PLAN_TYPES[$index]}"
    target="${PLAN_TARGETS[$index]}"
    case "$type" in
      bootstrap_homebrew) bootstrap_homebrew_action ;;
      bootstrap_mise) bootstrap_mise_action "$target" ;;
      brew_bundle) apply_brew_bundle ;;
      mise_install) apply_mise_tools ;;
      dotfiles_apply) apply_dotfiles_install ;;
      dotfiles_unapply) apply_dotfiles_uninstall ;;
      *) die "unknown action type: $type" ;;
    esac
    log "applied: $type $target"
  done
}
