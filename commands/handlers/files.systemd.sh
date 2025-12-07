#!/usr/bin/env bash

# KGSM Pure Logic Layer - Systemd Integration Operations
#
# This module contains pure business logic functions for systemd integration operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - EC_SUCCESS_SYSTEMD_ENABLED (208): Systemd integration enabled successfully
# - EC_SUCCESS_SYSTEMD_DISABLED (209): Systemd integration disabled successfully
# - Standard error codes: EC_INVALID_ARG, EC_FILE_NOT_FOUND, EC_SYSTEMD, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck disable=SC1091
  source "$(__find_command_handler files.common.sh)" || return $EC_FAILED_SOURCE
fi

# Enable systemd integration for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_SYSTEMD_ENABLED on success, error code on failure
function __logic_enable_systemd_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get required variables from instance config
  local instance_name instance_launch_dir instance_executable_file instance_working_dir
  instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  instance_launch_dir=$(__get_config_value "$instance_config_file" "launch_dir" 2>/dev/null)
  instance_executable_file=$(__get_config_value "$instance_config_file" "executable_file" 2>/dev/null)
  instance_working_dir=$(__get_config_value "$instance_config_file" "working_dir" 2>/dev/null)

  if [[ -z "$instance_name" ]] || [[ -z "$instance_launch_dir" ]] || [[ -z "$instance_executable_file" ]] || [[ -z "$instance_working_dir" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Get systemd directory from KGSM config
  local config_systemd_files_dir
  config_systemd_files_dir=$(__get_config_value "$CONFIG_FILE" "systemd_files_dir" 2>/dev/null)

  if [[ -z "$config_systemd_files_dir" ]]; then
    return $EC_INVALID_CONFIG
  fi

  local instance_systemd_service_file="${config_systemd_files_dir}/${instance_name}.service"
  local instance_systemd_socket_file="${config_systemd_files_dir}/${instance_name}.socket"
  local temp_service_file="/tmp/${instance_name}.service"
  local temp_socket_file="/tmp/${instance_name}.socket"

  # Export variables required by templates
  local instance_bin_absolute_path="${instance_launch_dir}/${instance_executable_file}"
  export instance_name instance_bin_absolute_path instance_working_dir

  # Create service file from template
  if ! __logic_expand_template "service" "$temp_service_file"; then
    return $EC_FAILED_TEMPLATE
  fi

  # Create socket file from template
  if ! __logic_expand_template "socket" "$temp_socket_file"; then
    rm -f "$temp_service_file" 2>/dev/null
    return $EC_FAILED_TEMPLATE
  fi

  # Determine sudo requirement
  local SUDO=""
  [[ "$EUID" -ne 0 ]] && SUDO="sudo -E"

  # Move files to systemd directory
  if ! $SUDO mv "$temp_service_file" "$instance_systemd_service_file" 2>/dev/null; then
    rm -f "$temp_service_file" "$temp_socket_file" 2>/dev/null
    return $EC_FAILED_MV
  fi

  if ! $SUDO mv "$temp_socket_file" "$instance_systemd_socket_file" 2>/dev/null; then
    rm -f "$temp_socket_file" 2>/dev/null
    $SUDO rm -f "$instance_systemd_service_file" 2>/dev/null
    return $EC_FAILED_MV
  fi

  # Reload systemd daemon
  if ! $SUDO systemctl daemon-reload 2>/dev/null; then
    $SUDO rm -f "$instance_systemd_service_file" "$instance_systemd_socket_file" 2>/dev/null
    return $EC_SYSTEMD
  fi

  # Update instance config with systemd integration details
  if ! __add_or_update_config "$instance_config_file" "enable_systemd" "true"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "lifecycle_manager" "systemd"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "systemd_service_file" "$instance_systemd_service_file"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "systemd_socket_file" "$instance_systemd_socket_file"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_SYSTEMD_ENABLED
}

export -f __logic_enable_systemd_integration

# Disable systemd integration for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_SYSTEMD_DISABLED on success, error code on failure
function __logic_disable_systemd_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get systemd file paths from instance config
  local instance_name instance_systemd_service_file instance_systemd_socket_file
  instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  instance_systemd_service_file=$(__get_config_value "$instance_config_file" "systemd_service_file" 2>/dev/null)
  instance_systemd_socket_file=$(__get_config_value "$instance_config_file" "systemd_socket_file" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # If no systemd files configured, nothing to disable
  if [[ -z "$instance_systemd_service_file" ]] && [[ -z "$instance_systemd_socket_file" ]]; then
    return $EC_SUCCESS_SYSTEMD_DISABLED
  fi

  # Determine sudo requirement
  local SUDO=""
  [[ "$EUID" -ne 0 ]] && SUDO="sudo -E"

  # Stop and disable service if active
  if systemctl is-active "$instance_name" &>/dev/null; then
    if ! $SUDO systemctl stop "$instance_name" 2>/dev/null; then
      return $EC_SYSTEMD
    fi
  fi

  if systemctl is-enabled "$instance_name" &>/dev/null; then
    if ! $SUDO systemctl disable "$instance_name" 2>/dev/null; then
      return $EC_SYSTEMD
    fi
  fi

  # Remove service file if it exists
  if [[ -f "$instance_systemd_service_file" ]]; then
    if ! $SUDO rm -f "$instance_systemd_service_file" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Remove socket file if it exists
  if [[ -f "$instance_systemd_socket_file" ]]; then
    if ! $SUDO rm -f "$instance_systemd_socket_file" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Reload systemd daemon
  if ! $SUDO systemctl daemon-reload 2>/dev/null; then
    return $EC_SYSTEMD
  fi

  # Update instance config to reflect disabled state
  if ! __add_or_update_config "$instance_config_file" "enable_systemd" "false"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "lifecycle_manager" "standalone"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "systemd_service_file" ""; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "systemd_socket_file" ""; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_SYSTEMD_DISABLED
}

export -f __logic_disable_systemd_integration

# Mark module as loaded
export KGSM_LOGIC_FILES_SYSTEMD_LOADED=1
