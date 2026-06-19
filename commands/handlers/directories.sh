#!/usr/bin/env bash

# KGSM Pure Logic Layer - Directory Management
#
# This module contains pure business logic functions for directory operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - 200: Directories created successfully (emit instance-directories-created)
# - 201: Directories removed successfully (emit instance-directories-removed)
# - Standard error codes: EC_FAILED_MKDIR, EC_FAILED_RM, EC_PERMISSION, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_DIRECTORIES_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# DIRECTORY STRUCTURE MANAGEMENT
# =============================================================================

# Creates directory structure for an instance
# Args: $1 = _instance_name, $2 = instance_config_file, $3 = instance_working_dir
# Returns: EC_SUCCESS_DIRECTORIES_CREATED on success (triggers directories-created event), error codes on failure
function __logic_create_directories() {
  local _instance_name="$1"
  local instance_config_file="$2"
  local instance_working_dir="$3"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -z "$instance_working_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  # Ensure instance_working_dir is an absolute path
  if [[ ! "$instance_working_dir" = /* ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Define directory structure
  # events_dir: a DIRECTORY bind-mounted to /run/kgsm in container instances. The
  # in-container player-presence shim writes events.ndjson inside it; created
  # here (not pre-touched as a file) so it exists with correct ownership before
  # the container starts and Docker mounts a real directory, never a stray file.
  declare -A DIR_ARRAY=(
    ["working_dir"]="$instance_working_dir"
    ["backups_dir"]="${instance_working_dir}/backups"
    ["install_dir"]="${instance_working_dir}/install"
    ["saves_dir"]="${instance_working_dir}/saves"
    ["temp_dir"]="${instance_working_dir}/temp"
    ["logs_dir"]="${instance_working_dir}/logs"
    ["events_dir"]="${instance_working_dir}/events"
  )

  # Create directories and update config
  for dir_key in "${!DIR_ARRAY[@]}"; do
    local dir_value="${DIR_ARRAY[$dir_key]}"

    # Create directory - suppress all output since this is pure logic
    if ! __create_dir "$dir_value" >/dev/null 2>&1; then
      return $EC_FAILED_MKDIR
    fi

    # Update config file - suppress all output since this is pure logic
    if ! __add_or_update_config "$instance_config_file" "$dir_key" "\"$dir_value\"" >/dev/null 2>&1; then
      return $EC_FAILED_UPDATE_CONFIG
    fi
  done

  # Return success event code
  return $EC_SUCCESS_DIRECTORIES_CREATED
}

export -f __logic_create_directories

# Removes directory structure for an instance
# Args: $1 = instance_working_dir
# Returns: EC_SUCCESS_DIRECTORIES_REMOVED on success (triggers directories-removed event), error codes on failure
function __logic_remove_directories() {
  local _instance_name="$1"
  local instance_working_dir="$2"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -z "$instance_working_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  # Ensure instance_working_dir is an absolute path for safety
  if [[ ! "$instance_working_dir" = /* ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Remove main working directory (this removes all subdirectories)
  if ! rm -rf "${instance_working_dir?}" 2>/dev/null; then
    return $EC_FAILED_RM
  fi

  # Return success event code
  return $EC_SUCCESS_DIRECTORIES_REMOVED
}

export -f __logic_remove_directories

# Creates a symlink from KGSM's instances directory to the actual working directory
# Args: $1 = blueprint_name, $2 = instance_name, $3 = working_dir
# Returns: EC_SUCCESS on success, error codes on failure
function __logic_create_instance_symlink() {
  local blueprint_name="$1"
  local instance_name="$2"
  local working_dir="$3"

  # Validate required parameters
  if [[ -z "$blueprint_name" || -z "$instance_name" || -z "$working_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  # Ensure working_dir is an absolute path
  if [[ ! "$working_dir" = /* ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Calculate symlink paths
  local symlink_parent_dir="${KGSM_INSTANCES_DIR}/${blueprint_name}"
  local symlink_path="${symlink_parent_dir}/${instance_name}"

  # Create parent directory for blueprint if it doesn't exist
  if ! __create_dir "$symlink_parent_dir" >/dev/null 2>&1; then
    return $EC_FAILED_MKDIR
  fi

  # Check if symlink already exists
  if [[ -L "$symlink_path" ]]; then
    # Symlink exists - check if it points to the correct location
    local current_target
    current_target="$(readlink -f "$symlink_path")"
    if [[ "$current_target" != "$working_dir" ]]; then
      # Symlink points to wrong location - remove and recreate
      rm -f "$symlink_path" 2>/dev/null || return $EC_FAILED_RM
    else
      # Symlink already correct - nothing to do
      return $EC_SUCCESS
    fi
  elif [[ -e "$symlink_path" ]]; then
    # Path exists but is not a symlink - error
    return $EC_ERROR
  fi

  # Create the symlink
  if ! ln -s "$working_dir" "$symlink_path" 2>/dev/null; then
    return $EC_FAILED_LN
  fi

  return $EC_SUCCESS
}

export -f __logic_create_instance_symlink

# Removes a symlink from KGSM's instances directory
# Args: $1 = blueprint_name, $2 = instance_name
# Returns: EC_SUCCESS on success, error codes on failure
function __logic_remove_instance_symlink() {
  local blueprint_name="$1"
  local instance_name="$2"

  # Validate required parameters
  if [[ -z "$blueprint_name" || -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Calculate symlink path
  local symlink_path="${KGSM_INSTANCES_DIR}/${blueprint_name}/${instance_name}"

  # Check if symlink exists
  if [[ ! -L "$symlink_path" ]]; then
    # Symlink doesn't exist - success (idempotent)
    return $EC_SUCCESS
  fi

  # Remove the symlink
  if ! rm -f "$symlink_path" 2>/dev/null; then
    return $EC_FAILED_RM
  fi

  # Try to remove parent directory if empty
  rmdir "${KGSM_INSTANCES_DIR}/${blueprint_name}" 2>/dev/null || true

  return $EC_SUCCESS
}

export -f __logic_remove_instance_symlink

# Mark module as loaded
declare -g KGSM_LOGIC_DIRECTORIES_LOADED=1
export KGSM_LOGIC_DIRECTORIES_LOADED
