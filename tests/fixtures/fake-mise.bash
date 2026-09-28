#!/usr/bin/env bash
set -euo pipefail

dotfiles_entries() {
  sed -n 's/^"\([^"]*\)" = { source = "\([^"]*\)" }$/\1\t\2/p' "$MISE_GLOBAL_CONFIG_FILE"
}

expand_home() {
  case "$1" in
    '~') printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

fake_dotfiles() {
  local action="$1"
  shift
  local dry_run=false
  local selected=''
  local target source actual_target actual_source
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run|--missing) dry_run=true ;;
      --yes) ;;
      *) selected="$selected|$1" ;;
    esac
    shift
  done
  local failed=false
  while IFS=$'\t' read -r target source; do
    actual_target="$(expand_home "$target")"
    actual_source="$(expand_home "$source")"
    if [ -n "$selected" ] && ! case "$selected" in *"|$actual_target"*) true ;; *) false ;; esac; then
      continue
    fi
    case "$action" in
      apply)
        printf 'dotfiles apply %s -> %s%s\n' "$actual_target" "$actual_source" "$([ "$dry_run" = true ] && printf ' (dry-run)')"
        if [ "$dry_run" = false ]; then
          if [ -e "$actual_target" ] || [ -L "$actual_target" ]; then
            if [ ! -L "$actual_target" ] || { [ "$(readlink "$actual_target")" != "$actual_source" ] && ! [ "$actual_target" -ef "$actual_source" ]; }; then
              printf 'dotfile conflict: %s\n' "$actual_target" >&2
              return 1
            fi
          else
            mkdir -p "${actual_target%/*}"
            ln -s "$actual_source" "$actual_target"
          fi
        elif [ -e "$actual_target" ] && { [ ! -L "$actual_target" ] || { [ "$(readlink "$actual_target")" != "$actual_source" ] && ! [ "$actual_target" -ef "$actual_source" ]; }; }; then
          printf 'dotfile conflict: %s\n' "$actual_target" >&2
          return 1
        fi
        ;;
      status)
        if [ ! -L "$actual_target" ] || [ "$(readlink "$actual_target" 2>/dev/null || true)" != "$actual_source" ]; then
          printf 'missing %s\n' "$actual_target"
          failed=true
        fi
        ;;
      unapply)
        printf 'dotfiles unapply %s%s\n' "$actual_target" "$([ "$dry_run" = true ] && printf ' (dry-run)')"
        if [ "$dry_run" = false ] && [ -L "$actual_target" ] && [ "$(readlink "$actual_target")" = "$actual_source" ]; then
          rm "$actual_target"
        fi
        ;;
    esac
  done < <(dotfiles_entries)
  [ "$failed" = false ]
}

if [ "${1:-}" = "--cd" ]; then
  printf 'mise-cwd=%s\n' "$2" >> "$HOME/calls"
  shift 2
fi
printf 'mise %s node-version=%s config=%s mise-env=%s\n' \
  "$*" "${MISE_NODE_VERSION-unset}" "${MISE_GLOBAL_CONFIG_FILE-unset}" "${MISE_ENV-unset}" >> "$HOME/calls"
case "${1:-}" in
  bootstrap)
    [ "${2:-}" = dotfiles ] || exit 1
    fake_dotfiles "${3:-}" "${@:4}"
    ;;
  config)
    if [ "${FAIL_MISE_CONFIG:-0}" = "1" ]; then
      printf '%s\n' 'fake mise config failure' >&2
      exit 17
    fi
    [ ! -e "$MISE_DATA_DIR/incompatible" ] || exit 1
    printf '%s\n' "$MISE_GLOBAL_CONFIG_FILE"
    ;;
  install)
    if [ "${FAIL_MISE_LOCK:-0}" = "1" ] && case " $* " in *' --dry-run '*) true ;; *) false ;; esac; then
      printf '%s\n' 'fake mise lock failure' >&2
      exit 18
    fi
    case " $* " in
      *' --dry-run '*)
        if [ -n "${CREATE_DESTINATION_DURING_PREFLIGHT:-}" ]; then
          printf '%s\n' 'created during package validation' > "$CREATE_DESTINATION_DURING_PREFLIGHT"
        fi
        ;;
      *)
        if [ -n "${STREAM_MARKER:-}" ]; then
          printf '%s\n' "$STREAM_MARKER"
          while [ ! -e "$STREAM_RELEASE_FILE" ]; do sleep 0.05; done
        fi
        mkdir -p "$MISE_DATA_DIR"
        touch "$MISE_DATA_DIR/tools-installed"
        ;;
    esac
    ;;
  ls)
    if [ "${FAKE_MISE_LS_WARNING:-0}" = "1" ]; then
      printf '%s\n' 'fake mise ls warning' >&2
    fi
    if [ -n "${FAIL_MISE_LS_STATUS:-}" ]; then
      printf 'fake mise ls status %s\n' "$FAIL_MISE_LS_STATUS" >&2
      exit "$FAIL_MISE_LS_STATUS"
    fi
    if [ "${FAIL_MISE_LS:-0}" = "1" ]; then
      printf '%s\n' 'fake mise ls failure' >&2
      exit 19
    fi
    if [ ! -e "$MISE_DATA_DIR/tools-installed" ]; then
      node_version="$(awk '
        /^[[:space:]]*\[[[:space:]]*tools[[:space:]]*\][[:space:]]*(#.*)?$/ {
          tools_section = 1
          next
        }
        tools_section && /^[[:space:]]*\[/ { exit }
        tools_section && /^[[:space:]]*node[[:space:]]*=/ {
          value = $0
          sub(/^[[:space:]]*node[[:space:]]*=[[:space:]]*"/, "", value)
          if (value == $0) next
          sub(/"[[:space:]]*(#.*)?$/, "", value)
          print value
          exit
        }
      ' "$MISE_GLOBAL_CONFIG_FILE")"
      if [ -z "$node_version" ]; then
        printf 'fake mise could not read the Node.js version: %s\n' "$MISE_GLOBAL_CONFIG_FILE" >&2
        exit 1
      fi
      printf 'node %s missing\n' "$node_version"
    fi
    ;;
  version|--version) printf '%s\n' '2026.8.6 linux-x64' ;;
  *) printf 'unexpected mise command: %s\n' "$*" >&2; exit 1 ;;
esac
