#!/usr/bin/env bash

# KGSM Pure Logic Layer - UPnP Port Forwarding Integration Operations
#
# This module contains pure business logic functions for UPnP integration operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - EC_SUCCESS_UPNP_ENABLED (219): UPnP integration enabled successfully
# - EC_SUCCESS_UPNP_ENABLED (219): UPnP integration disabled successfully (config-only)
# - Standard error codes: EC_INVALID_ARG, EC_FILE_NOT_FOUND, etc.
#
# Note: UPnP integration is config-only - no external files are created or removed.
#       Actual port forwarding is handled by the game server management process.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Enable UPnP port forwarding for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_UPNP_ENABLED on success, error code on failure
function __logic_enable_upnp_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Update instance config to enable port forwarding
  if ! __add_or_update_config "$instance_config_file" "enable_port_forwarding" "true"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_UPNP_ENABLED
}

export -f __logic_enable_upnp_integration

# Disable UPnP port forwarding for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_UPNP_ENABLED on success, error code on failure
function __logic_disable_upnp_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Update instance config to disable port forwarding
  if ! __add_or_update_config "$instance_config_file" "enable_port_forwarding" "false"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_UPNP_ENABLED
}

export -f __logic_disable_upnp_integration

# Mark module as loaded
export KGSM_LOGIC_FILES_UPNP_LOADED=1
