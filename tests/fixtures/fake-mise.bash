#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--cd" ]; then
  printf 'mise-cwd=%s\n' "$2" >> "$HOME/calls"
  shift 2
fi
printf 'mise %s node-version=%s config=%s mise-env=%s\n' \
  "$*" "${MISE_NODE_VERSION-unset}" "${MISE_GLOBAL_CONFIG_FILE-unset}" "${MISE_ENV-unset}" >> "$HOME/calls"

case "${1:-}" in
  bootstrap)
    # Dotfilesの意味論は再現せず、ラッパーが呼び出した事実だけを記録する。
    [ "${2:-}" = dotfiles ] || exit 1
    ;;
  config)
    if [ "${FAIL_MISE_CONFIG:-0}" = "1" ]; then
      printf '%s\n' 'fake mise config failure' >&2
      exit 17
    fi
    printf '%s\n' '{}'
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
        if [ "${FAIL_MISE_INSTALL:-0}" = "1" ]; then
          printf '%s\n' 'fake mise install failure' >&2
          exit 23
        fi
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
    [ "${FAKE_MISE_LS_WARNING:-0}" != "1" ] || printf '%s\n' 'fake mise ls warning' >&2
    if [ -n "${FAIL_MISE_LS_STATUS:-}" ]; then
      printf 'fake mise ls status %s\n' "$FAIL_MISE_LS_STATUS" >&2
      exit "$FAIL_MISE_LS_STATUS"
    fi
    if [ ! -e "$MISE_DATA_DIR/tools-installed" ]; then
      printf '%s\n' "${FAKE_MISE_MISSING_OUTPUT:-node missing}"
    fi
    ;;
  version|--version) printf '%s\n' '2026.8.6 linux-x64' ;;
  *) printf 'unexpected mise command: %s\n' "$*" >&2; exit 1 ;;
esac
