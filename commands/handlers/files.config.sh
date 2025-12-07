#!/usr/bin/env bash

# KGSM Pure Logic Layer - Configuration File Operations
#
# This module contains pure business logic functions for configuration file operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - EC_SUCCESS_CONFIG_INSTALLED (204): Configuration installed successfully
# - EC_SUCCESS_CONFIG_UNINSTALLED (205): Configuration uninstalled successfully
# - Standard error codes: EC_INVALID_ARG, EC_FILE_NOT_FOUND, EC_FAILED_CP, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck disable=SC1091
  source "$(__find_command_handler files.common.sh)" || return $EC_FAILED_SOURCE
fi

# Install standalone instance configuration
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_CONFIG_INSTALLED on success, error code on failure
function __logic_install_standalone_config() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get required variables from instance config
  local instance_name instance_working_dir
  instance_name=$(basename "$instance_config_file" .ini)
  instance_working_dir=$(__get_config_value "$instance_config_file" "working_dir" 2> /dev/null)

  if [[ -z "$instance_working_dir" ]]; then
    return $EC_INVALID_CONFIG
  fi

  local instance_config_standalone="${instance_working_dir}/${instance_name}.config.ini"

  # Copy the config file to the instance working directory (becomes source of truth)
  if ! cp -f "$instance_config_file" "$instance_config_standalone" 2> /dev/null; then
    return $EC_FAILED_CP
  fi

  # Set proper ownership on the copied config file
  if ! __logic_set_file_ownership "$instance_config_standalone"; then
    return $EC_PERMISSION
  fi

  # Remove existing KGSM symlink/file if it exists
  if [[ -e "$instance_config_file" || -L "$instance_config_file" ]]; then
    if ! rm -f "$instance_config_file" 2> /dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Create symlink from KGSM pointing to the standalone config
  if ! ln -s "$instance_config_standalone" "$instance_config_file" 2> /dev/null; then
    return $EC_FAILED_LN
  fi

  return $EC_SUCCESS_CONFIG_INSTALLED
}

export -f __logic_install_standalone_config

# Uninstall standalone instance configuration
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_CONFIG_UNINSTALLED on success, error code on failure
function __logic_uninstall_standalone_config() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  # Get instance name and working directory
  local instance_name instance_working_dir
  instance_name=$(basename "$instance_config_file" .ini)

  # We need to get working_dir before removing the config
  # Try to read it if the symlink still exists
  if [[ -e "$instance_config_file" ]]; then
    instance_working_dir=$(__get_config_value "$instance_config_file" "working_dir" 2> /dev/null)
  fi

  local instance_config_standalone="${instance_working_dir}/${instance_name}.config.ini"

  # Remove KGSM symlink if it exists
  if [[ -L "$instance_config_file" ]]; then
    if ! rm -f "$instance_config_file" 2> /dev/null; then
      return $EC_FAILED_RM
    fi
  elif [[ -e "$instance_config_file" ]]; then
    # If it's a regular file instead of symlink, still try to remove it
    if ! rm -f "$instance_config_file" 2> /dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Remove the standalone config file from instance directory if it exists
  if [[ -f "$instance_config_standalone" ]]; then
    if ! rm -f "$instance_config_standalone" 2> /dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  return $EC_SUCCESS_CONFIG_UNINSTALLED
}

export -f __logic_uninstall_standalone_config

# Mark module as loaded
export KGSM_LOGIC_FILES_CONFIG_LOADED=1
