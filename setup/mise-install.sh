#!/usr/bin/env bash
set -euo pipefail

mode="${1:---dry-run}"
case "$mode" in
  --dry-run) ;;
  --apply) ;;
  -h|--help)
    printf '%s\n' 'usage: ./setup/mise-install.sh [--dry-run|--apply]'
    exit 0
    ;;
  *) printf '%s\n' 'usage: ./setup/mise-install.sh [--dry-run|--apply]' >&2; exit 2 ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=setup/mise.env
. "$script_dir/mise.env"

install_path="${DOTFILES_MISE_BOOTSTRAP_TARGET:-$HOME/.local/bin/mise}"
case "$install_path" in
  /*) ;;
  *) printf 'error: mise install path must be absolute: %s\n' "$install_path" >&2; exit 1 ;;
esac

printf 'MISE_VERSION=%s\n' "$MISE_VERSION"
printf 'MISE_INSTALL_PATH=%s\n' "$install_path"

if [ -e "$install_path" ] || [ -L "$install_path" ]; then
  printf 'error: mise bootstrap target conflicts: %s\n' "$install_path" >&2
  exit 1
fi

if [ "$mode" = "--dry-run" ]; then
  printf 'plan: bootstrap_mise %s\n' "$install_path"
  exit 0
fi

case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64)
    mise_platform="linux-x64"
    mise_sha256="$MISE_SHA256_LINUX_X64"
    ;;
  Linux:aarch64|Linux:arm64)
    mise_platform="linux-arm64"
    mise_sha256="$MISE_SHA256_LINUX_ARM64"
    ;;
  Darwin:x86_64|Darwin:amd64)
    mise_platform="macos-x64"
    mise_sha256="$MISE_SHA256_MACOS_X64"
    ;;
  Darwin:arm64|Darwin:aarch64)
    mise_platform="macos-arm64"
    mise_sha256="$MISE_SHA256_MACOS_ARM64"
    ;;
  *)
    printf 'error: unsupported mise platform: %s/%s\n' "$(uname -s)" "$(uname -m)" >&2
    exit 1
    ;;
esac

bootstrap_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise-bootstrap.XXXXXX")" || {
  printf '%s\n' 'error: failed to create temporary directory for mise bootstrap' >&2
  exit 1
}
trap 'rm -rf "$bootstrap_root"' EXIT

mise_asset="mise-v${MISE_VERSION}-${mise_platform}"
curl -fsSL -o "$bootstrap_root/mise" \
  "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/${mise_asset}"
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s  %s\n' "$mise_sha256" "$bootstrap_root/mise" | sha256sum -c -
else
  printf '%s  %s\n' "$mise_sha256" "$bootstrap_root/mise" | shasum -a 256 -c -
fi
install -d "$(dirname "$install_path")"
install -m 755 "$bootstrap_root/mise" "$install_path"
