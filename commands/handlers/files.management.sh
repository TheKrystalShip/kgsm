#!/usr/bin/env bash

# KGSM Pure Logic Layer - Management File Operations
#
# This module contains pure business logic functions for management file operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - EC_SUCCESS_MANAGEMENT_FILE_CREATED (206): Management file created successfully
# - EC_SUCCESS_MANAGEMENT_FILE_REMOVED (207): Management file removed successfully
# - Standard error codes: EC_INVALID_ARG, EC_FILE_NOT_FOUND, EC_FAILED_TEMPLATE, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_FILES_MANAGEMENT_LOADED}" ]]; then
  return 0
fi

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck source=files.common.sh
  source "$(__find_command_handler files.common.sh)" || return $EC_FAILED_SOURCE
fi

# Create docker-compose file for container instances
# Args: $1 = instance_config_file
# Returns: 0 on success, error code on failure
function __logic_create_container_compose_file() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get required variables from instance config
  local _instance_name _instance_blueprint_file _instance_working_dir
  _instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  _instance_blueprint_file=$(__get_config_value "$instance_config_file" "blueprint_file" 2>/dev/null)
  _instance_working_dir=$(__get_config_value "$instance_config_file" "working_dir" 2>/dev/null)

  if [[ -z "$_instance_name" ]] || [[ -z "$_instance_blueprint_file" ]] || [[ -z "$_instance_working_dir" ]]; then
    return $EC_INVALID_CONFIG
  fi

  if [[ ! -f "$_instance_blueprint_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  __source_instance "$instance_config_file" || return $EC_FAILED_SOURCE

  local container_file="${_instance_working_dir}/${_instance_name}.docker-compose.yml"

  # Expand template with environment variables
  if ! eval "cat <<EOF
$(<"$_instance_blueprint_file")
EOF
" >"$container_file" 2>/dev/null; then
    return $EC_FAILED_TEMPLATE
  fi

  return 0
}

export -f __logic_create_container_compose_file

# Create management file for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_MANAGEMENT_FILE_CREATED on success, error code on failure
function __logic_create_management_file() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get required variables from instance config
  local _instance_name _instance_runtime _instance_management_file _instance_blueprint_file
  _instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  _instance_runtime=$(__get_config_value "$instance_config_file" "runtime" 2>/dev/null)
  _instance_management_file=$(__get_config_value "$instance_config_file" "management_file" 2>/dev/null)
  _instance_blueprint_file=$(__get_config_value "$instance_config_file" "blueprint_file" 2>/dev/null)

  if [[ -z "$_instance_name" ]] || [[ -z "$_instance_runtime" ]] || [[ -z "$_instance_management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Extract blueprint_name from the blueprint file's 'name' field (not the filename)
  local blueprint_name=""
  if [[ -n "$_instance_blueprint_file" && -f "$_instance_blueprint_file" ]]; then
    blueprint_name=$(__get_config_value "$_instance_blueprint_file" "name" 2>/dev/null)
  fi

  # Assemble management file from modules, resolving overrides per module
  if ! __logic_assemble_management_file "$_instance_runtime" "$blueprint_name" "$_instance_management_file"; then
    return $EC_FAILED_TEMPLATE
  fi

  # Handle runtime-specific operations
  case "$_instance_runtime" in
    native)
      # Native runtime requires no additional files
      ;;
    container)
      # Container runtime requires docker-compose.yml
      if ! __logic_create_container_compose_file "$instance_config_file"; then
        return $EC_FAILED_TEMPLATE
      fi
      ;;
    *)
      return $EC_INVALID_CONFIG
      ;;
  esac

  # Set proper ownership
  if ! __logic_set_file_ownership "$_instance_management_file"; then
    return $EC_PERMISSION
  fi

  # Make executable
  if ! chmod +x "$_instance_management_file" 2>/dev/null; then
    return $EC_PERMISSION
  fi

  return $EC_SUCCESS_MANAGEMENT_FILE_CREATED
}

export -f __logic_create_management_file

# Remove management file for an instance
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_MANAGEMENT_FILE_REMOVED on success, error code on failure
function __logic_remove_management_file() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get management file path from instance config
  local _instance_management_file
  _instance_management_file=$(__get_config_value "$instance_config_file" "management_file" 2>/dev/null)

  if [[ -z "$_instance_management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Remove the management file if it exists
  if [[ -f "$_instance_management_file" ]]; then
    if ! rm -f "$_instance_management_file" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  return $EC_SUCCESS_MANAGEMENT_FILE_REMOVED
}

export -f __logic_remove_management_file

# Mark module as loaded
declare -g KGSM_LOGIC_FILES_MANAGEMENT_LOADED=1
export KGSM_LOGIC_FILES_MANAGEMENT_LOADED
