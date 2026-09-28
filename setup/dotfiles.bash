#!/usr/bin/env bash

toml_basic_string() {
  local value="$1"
  local output=''
  local character
  local code
  local index

  local LC_ALL=C
  for ((index = 0; index < ${#value}; index++)); do
    character="${value:index:1}"
    # The quoted backslash pattern is intentional here.
    # shellcheck disable=SC1003
    case "$character" in
      '"') output="$output\\\"" ;;
      '\') output="$output\\\\" ;;
      $'\b') output="$output\\b" ;;
      $'\t') output="$output\\t" ;;
      $'\n') output="$output\\n" ;;
      $'\f') output="$output\\f" ;;
      $'\r') output="$output\\r" ;;
      *)
        printf -v code '%d' "'$character"
        if [ "$code" -lt 32 ] || [ "$code" -eq 127 ]; then
          printf -v character '\\u%04x' "$code"
        fi
        output="$output$character"
        ;;
    esac
  done
  printf '"%s"' "$output"
}

write_dotfiles_config() {
  local config="$1"
  local anchor_source="$2"
  local anchor_target="$3"
  local global_source="$4"
  local global_target="$5"
  local include_static="${6:-false}"

  {
    printf '%s\n' '[dotfiles]'
    printf '%s = { source = %s }\n' \
      "$(toml_basic_string "$anchor_target")" "$(toml_basic_string "$anchor_source")"
    printf '%s = { source = %s }\n' \
      "$(toml_basic_string "$global_target")" "$(toml_basic_string "$global_source")"
    if [ "$include_static" = true ]; then
      printf '%s = { source = %s }\n' \
        "$(toml_basic_string "$HOME/.bashrc")" "$(toml_basic_string "$DOTFILES/.bashrc")"
      printf '%s = { source = %s }\n' \
        "$(toml_basic_string "$HOME/.bash_profile")" "$(toml_basic_string "$DOTFILES/.bash_profile")"
      printf '%s = { source = %s }\n' \
        "$(toml_basic_string "$HOME/.gitconfig")" "$(toml_basic_string "$DOTFILES/.gitconfig")"
    fi
  } > "$config"
}

normalize_absolute_path() {
  local path="$1"
  local component
  local normalized=''
  local -a components=()

  case "$path" in /*) ;; *) return 1 ;; esac
  IFS=/ read -r -a components <<< "$path"
  for component in "${components[@]}"; do
    case "$component" in
      ''|.) ;;
      ..)
        return 1
        ;;
      *) normalized="$normalized/$component" ;;
    esac
  done
  printf '%s\n' "${normalized:-/}"
}

validate_dotfile_target_parent() {
  local target="$1"
  local reporter="${2:-preflight_error}"
  local parent
  local current=''
  local component
  local -a components=()

  case "$target" in
    */..|*/../*)
      "$reporter" "dotfile target must not contain ..: $target"
      return
      ;;
  esac
  parent="${target%/*}"
  [ "$parent" != "$target" ] || parent=/
  case "$parent" in
    */..|*/../*)
      "$reporter" "dotfile target parent must not contain ..: $parent"
      return
      ;;
  esac
  parent="$(normalize_absolute_path "$parent")" || {
    "$reporter" "dotfile target parent must be absolute: $parent"
    return
  }
  IFS=/ read -r -a components <<< "$parent"
  for component in "${components[@]}"; do
    [ -n "$component" ] || continue
    current="$current/$component"
    if [ -L "$current" ]; then
      "$reporter" "dotfile target parent component must not be a symlink: $current"
      return
    fi
    if [ -e "$current" ]; then
      if [ ! -d "$current" ]; then
        "$reporter" "dotfile target parent component is not a directory: $current"
        return
      fi
    else
      return 0
    fi
  done
  return 0
}

validate_dotfile_target_parents() {
  local reporter="${1:-preflight_error}"
  local target
  for target in "$DOTFILES_ANCHOR_TARGET" "$MISE_CONFIG_TARGET" \
    "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.gitconfig"; do
    validate_dotfile_target_parent "$target" "$reporter"
  done
}

run_dotfiles_mise() (
  local config="$1"
  local variable_name
  local config_root
  local mise_command="$MISE_CMD"
  local data_dir="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
  local cache_dir="${MISE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mise}"
  local state_dir="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}"
  shift

  config_root="$(dirname "$config")"
  for variable_name in ${!MISE_@}; do
    unset "$variable_name"
  done
  export MISE_CONFIG_DIR="$config_root/.dotfiles-config"
  export MISE_SYSTEM_CONFIG_DIR="$config_root/.dotfiles-system"
  export MISE_GLOBAL_CONFIG_FILE="$config"
  export MISE_GLOBAL_CONFIG_ROOT="$config_root"
  export MISE_CEILING_PATHS="$config_root"
  export MISE_OVERRIDE_CONFIG_FILENAMES=.dotfiles-no-project-config.toml
  export MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES=none
  export MISE_SYSTEM_CONFIG_FILE="$config_root/.dotfiles-system.toml"
  export MISE_NO_ENV=1 MISE_NO_HOOKS=1
  export MISE_DATA_DIR="$data_dir" MISE_CACHE_DIR="$cache_dir" MISE_STATE_DIR="$state_dir"
  [ -z "${TMPDIR:-}" ] || export TMPDIR
  "$mise_command" --cd "$config_root" "$@"
)

prepare_dotfiles_config() {
  local global_source="$DOTFILES/mise.toml"
  if [ "${DOTFILES_CONFIG_USE_ANCHOR:-false}" = true ]; then
    global_source="$DOTFILES_ANCHOR_TARGET/mise.toml"
  fi
  DOTFILES_CONFIG_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-mise-config.XXXXXX")" ||
    die "failed to create temporary directory for dotfiles config"
  DOTFILES_CONFIG_TEMP="$DOTFILES_CONFIG_TEMP_DIR/config.toml"
  write_dotfiles_config "$DOTFILES_CONFIG_TEMP" "$DOTFILES" "$DOTFILES_ANCHOR_TARGET" \
    "$global_source" "$MISE_CONFIG_TARGET" false
}

cleanup_dotfiles_config() {
  [ -z "${DOTFILES_CONFIG_TEMP_DIR:-}" ] || rm -rf "$DOTFILES_CONFIG_TEMP_DIR"
  DOTFILES_CONFIG_TEMP_DIR=''
  DOTFILES_CONFIG_TEMP=''
}

run_generated_dotfiles_mise() {
  local include_static="$1"
  shift
  if [ "$include_static" = true ]; then
    DOTFILES_CONFIG_USE_ANCHOR=false
  else
    DOTFILES_CONFIG_USE_ANCHOR=true
  fi
  prepare_dotfiles_config
  if [ "$include_static" = true ]; then
    write_dotfiles_config "$DOTFILES_CONFIG_TEMP" "$DOTFILES" "$DOTFILES_ANCHOR_TARGET" \
      "$DOTFILES/mise.toml" "$MISE_CONFIG_TARGET" true
  fi
  local status=0
  run_dotfiles_mise "$DOTFILES_CONFIG_TEMP" "$@" || status=$?
  cleanup_dotfiles_config
  unset DOTFILES_CONFIG_USE_ANCHOR
  return "$status"
}

preflight_dotfiles_install() {
  validate_dotfile_target_parents preflight_error
  [ "$PREFLIGHT_FAILED" = false ] || return 1
  run_generated_dotfiles_mise true bootstrap dotfiles apply --dry-run || {
    preflight_error "mise dotfiles preflight failed"
    return 1
  }
}

apply_dotfiles_install() {
  validate_dotfile_target_parents die
  run_generated_dotfiles_mise false bootstrap dotfiles apply --yes "$DOTFILES_ANCHOR_TARGET"
  validate_dotfile_target_parents die
  run_generated_dotfiles_mise false bootstrap dotfiles apply --yes "$MISE_CONFIG_TARGET"
  validate_dotfile_target_parents die
  run_dotfiles_mise "$MISE_CONFIG_SOURCE" bootstrap dotfiles apply --yes
}

dry_run_dotfiles_install() {
  validate_dotfile_target_parents die
  # Validate and display the complete target set from the checkout. A dry-run
  # cannot create ~/.dotfiles first, so the installed global config would refer
  # to sources below an anchor that does not exist yet on a fresh HOME.
  run_generated_dotfiles_mise true bootstrap dotfiles apply --dry-run
}

check_dotfiles() {
  local failed=false
  validate_dotfile_target_parents verify_error
  run_generated_dotfiles_mise false bootstrap dotfiles status --missing || failed=true
  run_dotfiles_mise "$MISE_CONFIG_SOURCE" bootstrap dotfiles status --missing || failed=true
  if [ "$failed" = true ]; then
    # This state is consumed by lifecycle.bash after all checks finish.
    # shellcheck disable=SC2034
    CHECK_FAILED=true
  fi
}

apply_dotfiles_uninstall() {
  validate_dotfile_target_parents die
  run_dotfiles_mise "$MISE_CONFIG_SOURCE" bootstrap dotfiles unapply --yes
  validate_dotfile_target_parents die
  run_generated_dotfiles_mise false bootstrap dotfiles unapply --yes "$MISE_CONFIG_TARGET"
  validate_dotfile_target_parents die
  run_generated_dotfiles_mise false bootstrap dotfiles unapply --yes "$DOTFILES_ANCHOR_TARGET"
}

dry_run_dotfiles_uninstall() {
  validate_dotfile_target_parents die
  run_dotfiles_mise "$MISE_CONFIG_SOURCE" bootstrap dotfiles unapply --dry-run
  run_generated_dotfiles_mise true bootstrap dotfiles unapply --dry-run "$MISE_CONFIG_TARGET"
  run_generated_dotfiles_mise true bootstrap dotfiles unapply --dry-run "$DOTFILES_ANCHOR_TARGET"
}
