#!/usr/bin/env bash
set -euo pipefail

dry_run=true
helper="manager"
credential_store="cache"

usage() {
    cat >&2 <<'USAGE'
usage: ./setup/gcm.sh [--dry-run|--apply] [--helper HELPER] [--credential-store STORE]

Default is --dry-run. Use --apply when git pull/push fails after replacing
~/.gitconfig or when Git Credential Manager needs to be configured.

Options:
  --helper HELPER   Credential helper to configure; default: manager
  --credential-store STORE
                    Git Credential Manager store; default: cache

Examples:
  ./setup/gcm.sh
  ./setup/gcm.sh --apply
  ./setup/gcm.sh --apply --helper manager --credential-store cache
USAGE
}

normalize_helper() {
    case "$1" in
        ""|!*)
            return 1
            ;;
        /*)
            printf '%s\n' "$1"
            ;;
        git-credential-*)
            printf '%s\n' "${1#git-credential-}"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

helper_command() {
    case "$1" in
        /*)
            printf '%s\n' "${1%% *}"
            ;;
        *)
            printf 'git-credential-%s\n' "${1%% *}"
            ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            dry_run=true
            shift
            ;;
        --apply)
            dry_run=false
            shift
            ;;
        --helper)
            if [ "$#" -lt 2 ]; then
                printf 'error: --helper requires a value\n' >&2
                exit 2
            fi
            helper="$2"
            shift 2
            ;;
        --credential-store)
            if [ "$#" -lt 2 ]; then
                printf 'error: --credential-store requires a value\n' >&2
                exit 2
            fi
            credential_store="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DOTFILES

# shellcheck source=setup/lib.bash
. "$DOTFILES/setup/lib.bash"

if ! have_cmd git; then
    if "$dry_run"; then
        log "[dry-run] git is not installed; install Git before configuring Git Credential Manager"
        exit 0
    fi
    die "git is required. Install Git first, then rerun ./setup/gcm.sh --apply"
fi

credential_helper="$(normalize_helper "$helper" || true)"

if [ -z "$credential_helper" ]; then
    die "--helper must be a credential helper name or executable path, not empty or a shell snippet"
fi

if [ -z "$credential_store" ]; then
    die "--credential-store must not be empty"
fi

helper_cmd="$(helper_command "$credential_helper")"

if "$dry_run"; then
    if have_cmd "$helper_cmd"; then
        log "[dry-run] $helper_cmd is installed"
    else
        log "[dry-run] $helper_cmd is not installed; install the requested credential helper before applying"
    fi
    log "[dry-run] git config --global --unset-all credential.helper"
    log "[dry-run] git config --global --unset-all credential.credentialStore"
    log "[dry-run] git config --global credential.helper $credential_helper"
    log "[dry-run] git config --global credential.credentialStore $credential_store"
    log "[dry-run] git config --global --get-all credential.helper"
    log "[dry-run] git config --global --get-all credential.credentialStore"
    exit 0
fi

if ! have_cmd "$helper_cmd"; then
    die "$helper_cmd is required. Install the requested credential helper, then rerun ./setup/gcm.sh --apply"
fi

git config --global --unset-all credential.helper || true
git config --global --unset-all credential.credentialStore || true
git config --global credential.helper "$credential_helper"
git config --global credential.credentialStore "$credential_store"
git config --global --get-all credential.helper || true
git config --global --get-all credential.credentialStore || true

log "Git Credential Manager setup complete"
