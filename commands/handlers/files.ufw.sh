#!/usr/bin/env bash

# KGSM Pure Logic Layer - UFW Firewall Integration Operations
#
# This module contains pure business logic functions for UFW firewall integration operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - EC_SUCCESS_UFW_ENABLED (215): UFW integration enabled successfully
# - EC_SUCCESS_UFW_DISABLED (216): UFW integration disabled successfully
# - Standard error codes: EC_INVALID_ARG, EC_FILE_NOT_FOUND, EC_UFW, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_FILES_UFW_LOADED}" ]]; then
  return 0
fi

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck source=files.common.sh
  source "$(__find_command_handler files.common.sh)" || return $EC_FAILED_SOURCE
fi

# Enable UFW firewall integration for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_UFW_ENABLED on success, error code on failure
function __logic_enable_ufw_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get required variables from instance config
  local _instance_name
  _instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Get firewall rules directory from KGSM config
  local config_firewall_rules_dir
  config_firewall_rules_dir=$(__get_config_value "$CONFIG_FILE" "firewall_rules_dir" 2>/dev/null)

  if [[ -z "$config_firewall_rules_dir" ]]; then
    return $EC_INVALID_CONFIG
  fi

  local instance_firewall_rule_file="${config_firewall_rules_dir}/kgsm-${_instance_name}"
  local temp_ufw_file="/tmp/kgsm-${_instance_name}"

  # If firewall rule file already exists, return error
  if [[ -f "$instance_firewall_rule_file" ]]; then
    return $EC_ERROR
  fi

  # Source instance config to make variables available for template expansion
  # shellcheck disable=SC1090
  __source_instance "$instance_config_file" || return $EC_FAILED_SOURCE

  # Create UFW rule file from template
  if ! __logic_expand_template "ufw" "$temp_ufw_file"; then
    return $EC_FAILED_TEMPLATE
  fi

  # Determine sudo requirement
  local SUDO=""
  [[ "$EUID" -ne 0 ]] && SUDO="sudo -E"

  # Move to UFW directory
  if ! $SUDO mv "$temp_ufw_file" "$instance_firewall_rule_file" 2>/dev/null; then
    rm -f "$temp_ufw_file" 2>/dev/null
    return $EC_FAILED_MV
  fi

  # Set proper ownership (UFW expects root:root)
  if ! $SUDO chown root:root "$instance_firewall_rule_file" 2>/dev/null; then
    $SUDO rm -f "$instance_firewall_rule_file" 2>/dev/null
    return $EC_PERMISSION
  fi

  # Enable firewall rule
  if ! $SUDO ufw allow "$_instance_name" &>/dev/null; then
    $SUDO rm -f "$instance_firewall_rule_file" 2>/dev/null
    return $EC_UFW
  fi

  # Update instance config with UFW integration details
  if ! __add_or_update_config "$instance_config_file" "enable_firewall_management" "true"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "firewall_rule_file" "$instance_firewall_rule_file"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_UFW_ENABLED
}

export -f __logic_enable_ufw_integration

# Disable UFW firewall integration for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_UFW_DISABLED on success, error code on failure
function __logic_disable_ufw_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get firewall rule file path from instance config
  local _instance_name instance_firewall_rule_file
  _instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  instance_firewall_rule_file=$(__get_config_value "$instance_config_file" "firewall_rule_file" 2>/dev/null)

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # If no firewall rule configured, nothing to disable
  if [[ -z "$instance_firewall_rule_file" ]]; then
    return $EC_SUCCESS_UFW_DISABLED
  fi

  # Determine sudo requirement
  local SUDO=""
  [[ "$EUID" -ne 0 ]] && SUDO="sudo -E"

  # Remove UFW rule (may not exist, ignore errors)
  $SUDO ufw delete allow "$_instance_name" &>/dev/null || true

  # Delete firewall rule file if it exists
  if [[ -f "$instance_firewall_rule_file" ]]; then
    if ! $SUDO rm -f "$instance_firewall_rule_file" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  # Update instance config to reflect disabled state
  if ! __add_or_update_config "$instance_config_file" "enable_firewall_management" "false"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if ! __add_or_update_config "$instance_config_file" "firewall_rule_file" ""; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_UFW_DISABLED
}

export -f __logic_disable_ufw_integration

# Mark module as loaded
declare -g KGSM_LOGIC_FILES_UFW_LOADED=1
export KGSM_LOGIC_FILES_UFW_LOADED
