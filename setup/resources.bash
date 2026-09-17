#!/usr/bin/env bash

link_status() {
  local src="$1"
  local dst="$2"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    printf 'expected\n'
  elif [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    printf 'missing\n'
  elif [ -f "$dst" ] || [ -L "$dst" ]; then
    printf 'replaceable_conflict\n'
  else
    printf 'fatal_conflict\n'
  fi
}

next_backup_path() {
  local dst="$1"
  local timestamp
  local backup
  local suffix=0

  timestamp="$(date +%Y%m%d%H%M%S)"
  backup="$dst.backup.$timestamp"
  while [ -e "$backup" ] || [ -L "$backup" ]; do
    suffix=$((suffix + 1))
    backup="$dst.backup.$timestamp.$suffix"
  done
  printf '%s\n' "$backup"
}

restore_backup_without_clobber() {
  local backup="$1"
  local dst="$2"
  local target

  if [ -L "$backup" ]; then
    target="$(readlink "$backup")" || return 1
    ln -s "$target" "$dst" || return 1
  elif [ -f "$backup" ]; then
    ln "$backup" "$dst" || return 1
  else
    return 1
  fi
  rm "$backup" || return 1
}

preflight_managed_links() {
  local index
  local src
  local dst
  local status

  MANAGED_LINK_STATUSES=()

  for ((index = 0; index < ${#MANAGED_SOURCES[@]}; index++)); do
    src="${MANAGED_SOURCES[$index]}"
    dst="${MANAGED_DESTINATIONS[$index]}"
    [ -e "$src" ] || { preflight_error "symlink source does not exist: $src"; continue; }
    status="$(link_status "$src" "$dst")"
    MANAGED_LINK_STATUSES[index]="$status"
    case "$status" in
      expected) log "ok: $dst -> $src" ;;
      missing)
        validate_destination_parent "$dst"
        ;;
      replaceable_conflict)
        validate_destination_parent "$dst"
        if [ "$src" = "$dst" ] || { [ -e "$dst" ] && [ "$src" -ef "$dst" ]; }; then
          preflight_error "symlink source and destination are the same file: $dst"
        fi
        if "${force:-false}"; then
          :
        else
          preflight_error "destination conflict: $dst (rerun install with --force)"
        fi
        ;;
      fatal_conflict) preflight_error "destination is not replaceable: $dst" ;;
    esac
  done
}

plan_managed_links() {
  local index
  local src
  local dst
  local status

  for ((index = 0; index < ${#MANAGED_SOURCES[@]}; index++)); do
    src="${MANAGED_SOURCES[$index]}"
    dst="${MANAGED_DESTINATIONS[$index]}"
    status="${MANAGED_LINK_STATUSES[$index]}"
    case "$status" in
      missing) plan_add ensure_symlink "$dst" "$src" ;;
      replaceable_conflict) plan_add replace_symlink "$dst" "$src" ;;
    esac
  done
}

ensure_symlink() {
  local src="$1"
  local dst="$2"
  local planned_type="${3:-replace_symlink}"
  local status
  local backup=""

  [ -e "$src" ] || die "symlink source disappeared: $src"
  status="$(link_status "$src" "$dst")"
  case "$status" in
    expected)
      log "ok: $dst -> $src"
      return 0
      ;;
    missing)
      [ "$planned_type" = "ensure_symlink" ] ||
        die "destination changed before symlink creation: $dst"
      mkdir -p "$(dirname "$dst")"
      ln -s "$src" "$dst" || die "failed to create symlink: $dst"
      ;;
    replaceable_conflict)
      [ "$planned_type" = "replace_symlink" ] ||
        die "destination changed to a conflict before planned symlink creation: $dst"
      backup="$(next_backup_path "$dst")"
      mv "$dst" "$backup" || die "failed to back up destination: $dst"
      if ! ln -s "$src" "$dst"; then
        if [ -e "$dst" ] || [ -L "$dst" ]; then
          die "failed to create symlink: $dst; destination reappeared, backup preserved: $backup"
        fi
        if restore_backup_without_clobber "$backup" "$dst"; then
          die "failed to create symlink: $dst; restored previous destination"
        fi
        die "failed to create symlink: $dst; rollback failed: $backup"
      fi
      log "backup: $backup"
      ;;
    fatal_conflict) die "destination changed to a non-replaceable type: $dst" ;;
  esac
  log "linked: $dst -> $src"
}

preflight_uninstall_links() {
  local index
  local src
  local dst

  for ((index = 0; index < ${#MANAGED_SOURCES[@]}; index++)); do
    src="${MANAGED_SOURCES[$index]}"
    dst="${MANAGED_DESTINATIONS[$index]}"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      validate_destination_parent "$dst"
      plan_add remove_symlink "$dst" "$src"
    else
      log "skip: unmanaged destination: $dst"
    fi
  done
}

remove_symlink() {
  local src="$1"
  local dst="$2"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    rm "$dst" || die "failed to remove managed symlink: $dst"
    log "removed: $dst"
  else
    log "skip: destination changed after preflight: $dst"
  fi
}

check_managed_links() {
  local index
  local src
  local dst

  for ((index = 0; index < ${#MANAGED_SOURCES[@]}; index++)); do
    src="${MANAGED_SOURCES[$index]}"
    dst="${MANAGED_DESTINATIONS[$index]}"
    if [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "$src" ]; then
      printf 'check failed: %s is not linked to %s\n' "$dst" "$src" >&2
      # Consumed by lifecycle.bash after all checks finish.
      # shellcheck disable=SC2034
      CHECK_FAILED=true
    fi
  done
}
