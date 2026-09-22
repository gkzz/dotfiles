#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--cd" ]; then
  printf 'mise-cwd=%s\n' "$2" >> "$HOME/calls"
  shift 2
fi
printf 'mise %s node-version=%s config=%s mise-env=%s\n' \
  "$*" "${MISE_NODE_VERSION-unset}" "${MISE_GLOBAL_CONFIG_FILE-unset}" "${MISE_ENV-unset}" >> "$HOME/calls"
case "${1:-}" in
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
