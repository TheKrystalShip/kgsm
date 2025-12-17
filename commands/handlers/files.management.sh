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

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck disable=SC1091
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
  local instance_name instance_blueprint_file instance_working_dir
  instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  instance_blueprint_file=$(__get_config_value "$instance_config_file" "blueprint_file" 2>/dev/null)
  instance_working_dir=$(__get_config_value "$instance_config_file" "working_dir" 2>/dev/null)

  if [[ -z "$instance_name" ]] || [[ -z "$instance_blueprint_file" ]] || [[ -z "$instance_working_dir" ]]; then
    return $EC_INVALID_CONFIG
  fi

  if [[ ! -f "$instance_blueprint_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  __source_instance "$instance_config_file" || return $EC_FAILED_SOURCE

  local container_file="${instance_working_dir}/${instance_name}.docker-compose.yml"

  # Expand template with environment variables
  if ! eval "cat <<EOF
$(<"$instance_blueprint_file")
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
  local instance_name instance_runtime instance_management_file
  instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)
  instance_runtime=$(__get_config_value "$instance_config_file" "runtime" 2>/dev/null)
  instance_management_file=$(__get_config_value "$instance_config_file" "management_file" 2>/dev/null)

  if [[ -z "$instance_name" ]] || [[ -z "$instance_runtime" ]] || [[ -z "$instance_management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Find appropriate template based on runtime
  local manage_template_file
  manage_template_file=$(__find_template "manage.${instance_runtime}" 2>/dev/null)

  if [[ ! -f "$manage_template_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Create the new management file from template
  if ! cp -f "$manage_template_file" "$instance_management_file" 2>/dev/null; then
    return $EC_FAILED_TEMPLATE
  fi

  # Handle runtime-specific operations
  case "$instance_runtime" in
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

  # Inject overrides into management file
  if ! __logic_inject_overrides "$instance_name" "$instance_management_file"; then
    return $EC_FAILED_TEMPLATE
  fi

  # Set proper ownership
  if ! __logic_set_file_ownership "$instance_management_file"; then
    return $EC_PERMISSION
  fi

  # Make executable
  if ! chmod +x "$instance_management_file" 2>/dev/null; then
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
  local instance_management_file
  instance_management_file=$(__get_config_value "$instance_config_file" "management_file" 2>/dev/null)

  if [[ -z "$instance_management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Remove the management file if it exists
  if [[ -f "$instance_management_file" ]]; then
    if ! rm -f "$instance_management_file" 2>/dev/null; then
      return $EC_FAILED_RM
    fi
  fi

  return $EC_SUCCESS_MANAGEMENT_FILE_REMOVED
}

export -f __logic_remove_management_file

# Mark module as loaded
export KGSM_LOGIC_FILES_MANAGEMENT_LOADED=1
