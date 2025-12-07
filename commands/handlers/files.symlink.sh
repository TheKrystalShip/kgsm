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

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck disable=SC1091
  source "$(__find_command_handler files.common.sh)" || return $EC_FAILED_SOURCE
fi

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
  local instance_name instance_management_file
  instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  instance_management_file=$(__get_config_value "$instance_config_file" "management_file" 2>/dev/null)

  if [[ -z "$instance_name" ]] || [[ -z "$instance_management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  if [[ ! -f "$instance_management_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get command shortcuts directory from KGSM config
  local config_command_shortcuts_directory
  config_command_shortcuts_directory=$(__get_config_value "$CONFIG_FILE" "command_shortcuts_directory" 2>/dev/null)

  if [[ -z "$config_command_shortcuts_directory" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Check if the symlink directory exists
  if [[ ! -d "$config_command_shortcuts_directory" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  local symlink_path="${config_command_shortcuts_directory}/${instance_name}"

  # If symlink already exists, remove it first
  if [[ -L "$symlink_path" ]]; then
    # Determine sudo requirement
    local SUDO=""
    [[ "$EUID" -ne 0 ]] && SUDO="sudo -E"

    if ! $SUDO rm "$symlink_path" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Determine sudo requirement
  local SUDO=""
  [[ "$EUID" -ne 0 ]] && SUDO="sudo -E"

  # Create the symlink
  if ! $SUDO ln -s "$instance_management_file" "$symlink_path" 2>/dev/null; then
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

  # Determine sudo requirement
  local SUDO=""
  [[ "$EUID" -ne 0 ]] && SUDO="sudo -E"

  # Remove symlink if it exists
  if [[ -L "$instance_command_shortcut_file" ]]; then
    if ! $SUDO rm "$instance_command_shortcut_file" 2>/dev/null; then
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
export KGSM_LOGIC_FILES_SYMLINK_LOADED=1
