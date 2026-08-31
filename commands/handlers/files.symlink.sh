#!/usr/bin/env bash

# KGSM Pure Logic Layer - Command Shortcut (Symlink) Integration Operations
#
# This module contains pure business logic functions for command shortcut integration operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - EC_SUCCESS_SYMLINK_CREATED (217): Symlink integration enabled successfully
# - EC_SUCCESS_SYMLINK_REMOVED (218): Symlink integration disabled successfully
# - Standard error codes: EC_INVALID_ARG, EC_FILE_NOT_FOUND, EC_FAILED_LN, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_FILES_SYMLINK_LOADED:-}" ]]; then
  return 0
fi

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck source=files.common.sh
  source "$(__find_command_handler files.common.sh)" || return $EC_FAILED_SOURCE
fi

# Expand a leading ~ or $HOME/${HOME} in a path to the absolute home directory.
# Config values are stored verbatim and are not shell-expanded when read, so a
# user-friendly default like "$HOME/.local/bin" must be resolved here.
# Args: $1 = path
# Outputs: echoes the expanded path
function __expand_home_path() {
  local path="$1"

  # The leading ~ is matched as a literal here (we resolve it ourselves rather
  # than relying on shell tilde expansion), so SC2088 does not apply.
  # shellcheck disable=SC2088
  case "$path" in
    "~") path="$HOME" ;;
    "~/"*) path="${HOME}/${path#\~/}" ;;
  esac

  path="${path//\$\{HOME\}/$HOME}"
  path="${path//\$HOME/$HOME}"

  echo "$path"
}

export -f __expand_home_path

# Enable command shortcut (symlink) integration for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_SYMLINK_CREATED on success, error code on failure
function __logic_enable_symlink_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get required variables from instance config
  local _instance_name _instance_management_file
  _instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  _instance_management_file=$(__get_config_value "$instance_config_file" "management_file" 2>/dev/null)

  if [[ -z "$_instance_name" ]] || [[ -z "$_instance_management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  if [[ ! -f "$_instance_management_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get command shortcuts directory from KGSM config
  local config_command_shortcuts_directory
  config_command_shortcuts_directory=$(__get_config_value "$CONFIG_FILE" "command_shortcuts_directory" 2>/dev/null)

  if [[ -z "$config_command_shortcuts_directory" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Resolve a leading ~ or $HOME so the directory points at the right place.
  config_command_shortcuts_directory=$(__expand_home_path "$config_command_shortcuts_directory")

  # Auto-create the shortcuts directory only when it lives under the user's
  # home (e.g. the default ~/.local/bin); never create or escalate into a
  # system directory.
  if [[ ! -d "$config_command_shortcuts_directory" ]] &&
    [[ "$config_command_shortcuts_directory" == "$HOME"/* ]]; then
    mkdir -p "$config_command_shortcuts_directory" 2>/dev/null || true
  fi

  # Check if the symlink directory exists. Distinct from the missing management
  # file above: the caller reports a missing shortcuts directory as a
  # configuration problem the operator can fix, and a missing management file as
  # a broken instance.
  if [[ ! -d "$config_command_shortcuts_directory" ]]; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  # KGSM never escalates to create shortcuts: a non-writable directory is a
  # clear, defined failure rather than a sudo prompt that would block headless
  # callers. For a system-wide shortcut, make the directory writable by the
  # KGSM user (or choose a writable directory on your PATH).
  if [[ ! -w "$config_command_shortcuts_directory" ]]; then
    return $EC_PERMISSION
  fi

  local symlink_path="${config_command_shortcuts_directory}/${_instance_name}"

  # If symlink already exists, remove it first
  if [[ -L "$symlink_path" ]]; then
    if ! rm "$symlink_path" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Create the symlink (no sudo: the directory is writable by us)
  if ! ln -s "$_instance_management_file" "$symlink_path" 2>/dev/null; then
    return $EC_FAILED_LN
  fi

  # Update instance config with symlink integration details
  if ! __add_or_update_config "$instance_config_file" "enable_command_shortcuts" "true"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "command_shortcut_file" "$symlink_path"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_SYMLINK_CREATED
}

export -f __logic_enable_symlink_integration

# Disable command shortcut (symlink) integration for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_SYMLINK_REMOVED on success, error code on failure
function __logic_disable_symlink_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get symlink path from instance config
  local instance_command_shortcut_file
  instance_command_shortcut_file=$(__get_config_value "$instance_config_file" "command_shortcut_file" 2>/dev/null)

  # If no symlink configured, nothing to disable
  if [[ -z "$instance_command_shortcut_file" ]]; then
    return $EC_SUCCESS_SYMLINK_REMOVED
  fi

  # Remove symlink if it exists (no sudo: shortcuts live in a user-writable
  # directory, so removal never escalates).
  if [[ -L "$instance_command_shortcut_file" ]]; then
    if ! rm "$instance_command_shortcut_file" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Update instance config to reflect disabled state
  if ! __add_or_update_config "$instance_config_file" "enable_command_shortcuts" "false"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "command_shortcut_file" ""; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_SYMLINK_REMOVED
}

export -f __logic_disable_symlink_integration

# Mark module as loaded
declare -g KGSM_LOGIC_FILES_SYMLINK_LOADED=1
export KGSM_LOGIC_FILES_SYMLINK_LOADED
