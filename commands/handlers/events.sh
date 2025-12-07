#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# KGSM Events Logic Library
#
# This module provides pure logic functions for event validation and management.
# No user-facing I/O (no __print_* functions).
# Returns meaningful exit codes for all operations.

# Guard against multiple sourcing
if [[ -n "${KGSM_LOGIC_EVENTS_LOADED:-}" ]]; then
  return 0
fi

# Event type constants
declare -g -r EVENT_INSTANCE_CREATED="instance_created"
export EVENT_INSTANCE_CREATED

declare -g -r EVENT_INSTANCE_DIRECTORIES_CREATED="instance_directories_created"
export EVENT_INSTANCE_DIRECTORIES_CREATED

declare -g -r EVENT_INSTANCE_FILES_CREATED="instance_files_created"
export EVENT_INSTANCE_FILES_CREATED

declare -g -r EVENT_INSTANCE_DOWNLOAD_STARTED="instance_download_started"
export EVENT_INSTANCE_DOWNLOAD_STARTED

declare -g -r EVENT_INSTANCE_DOWNLOAD_FINISHED="instance_download_finished"
export EVENT_INSTANCE_DOWNLOAD_FINISHED

declare -g -r EVENT_INSTANCE_DOWNLOADED="instance_downloaded"
export EVENT_INSTANCE_DOWNLOADED

declare -g -r EVENT_INSTANCE_DEPLOY_STARTED="instance_deploy_started"
export EVENT_INSTANCE_DEPLOY_STARTED

declare -g -r EVENT_INSTANCE_DEPLOY_FINISHED="instance_deploy_finished"
export EVENT_INSTANCE_DEPLOY_FINISHED

declare -g -r EVENT_INSTANCE_DEPLOYED="instance_deployed"
export EVENT_INSTANCE_DEPLOYED

declare -g -r EVENT_INSTANCE_UPDATE_STARTED="instance_update_started"
export EVENT_INSTANCE_UPDATE_STARTED

declare -g -r EVENT_INSTANCE_UPDATE_FINISHED="instance_update_finished"
export EVENT_INSTANCE_UPDATE_FINISHED

declare -g -r EVENT_INSTANCE_UPDATED="instance_updated"
export EVENT_INSTANCE_UPDATED

declare -g -r EVENT_INSTANCE_VERSION_UPDATED="instance_version_updated"
export EVENT_INSTANCE_VERSION_UPDATED

declare -g -r EVENT_INSTANCE_INSTALLATION_STARTED="instance_installation_started"
export EVENT_INSTANCE_INSTALLATION_STARTED

declare -g -r EVENT_INSTANCE_INSTALLATION_FINISHED="instance_installation_finished"
export EVENT_INSTANCE_INSTALLATION_FINISHED

declare -g -r EVENT_INSTANCE_INSTALLED="instance_installed"
export EVENT_INSTANCE_INSTALLED

declare -g -r EVENT_INSTANCE_STARTED="instance_started"
export EVENT_INSTANCE_STARTED

declare -g -r EVENT_INSTANCE_STOPPED="instance_stopped"
export EVENT_INSTANCE_STOPPED

declare -g -r EVENT_INSTANCE_READY="instance_ready"
export EVENT_INSTANCE_READY

declare -g -r EVENT_INSTANCE_BACKUP_CREATED="instance_backup_created"
export EVENT_INSTANCE_BACKUP_CREATED

declare -g -r EVENT_INSTANCE_BACKUP_RESTORED="instance_backup_restored"
export EVENT_INSTANCE_BACKUP_RESTORED

declare -g -r EVENT_INSTANCE_FILES_REMOVED="instance_files_removed"
export EVENT_INSTANCE_FILES_REMOVED

declare -g -r EVENT_INSTANCE_DIRECTORIES_REMOVED="instance_directories_removed"
export EVENT_INSTANCE_DIRECTORIES_REMOVED

declare -g -r EVENT_INSTANCE_REMOVED="instance_removed"
export EVENT_INSTANCE_REMOVED

declare -g -r EVENT_INSTANCE_UNINSTALL_STARTED="instance_uninstall_started"
export EVENT_INSTANCE_UNINSTALL_STARTED

declare -g -r EVENT_INSTANCE_UNINSTALL_FINISHED="instance_uninstall_finished"
export EVENT_INSTANCE_UNINSTALL_FINISHED

declare -g -r EVENT_INSTANCE_UNINSTALLED="instance_uninstalled"
export EVENT_INSTANCE_UNINSTALLED

# Event parameter specifications
declare -g -A EVENT_CONFIGS=(
  ["$EVENT_INSTANCE_CREATED"]="instance blueprint"
  ["$EVENT_INSTANCE_DIRECTORIES_CREATED"]="instance"
  ["$EVENT_INSTANCE_FILES_CREATED"]="instance"
  ["$EVENT_INSTANCE_DOWNLOAD_STARTED"]="instance"
  ["$EVENT_INSTANCE_DOWNLOAD_FINISHED"]="instance"
  ["$EVENT_INSTANCE_DOWNLOADED"]="instance"
  ["$EVENT_INSTANCE_DEPLOY_STARTED"]="instance"
  ["$EVENT_INSTANCE_DEPLOY_FINISHED"]="instance"
  ["$EVENT_INSTANCE_DEPLOYED"]="instance"
  ["$EVENT_INSTANCE_UPDATE_STARTED"]="instance"
  ["$EVENT_INSTANCE_UPDATE_FINISHED"]="instance"
  ["$EVENT_INSTANCE_UPDATED"]="instance"
  ["$EVENT_INSTANCE_VERSION_UPDATED"]="instance old_version new_version"
  ["$EVENT_INSTANCE_INSTALLATION_STARTED"]="instance blueprint"
  ["$EVENT_INSTANCE_INSTALLATION_FINISHED"]="instance blueprint"
  ["$EVENT_INSTANCE_INSTALLED"]="instance blueprint"
  ["$EVENT_INSTANCE_STARTED"]="instance lifecycle_manager"
  ["$EVENT_INSTANCE_STOPPED"]="instance lifecycle_manager"
  ["$EVENT_INSTANCE_READY"]="instance"
  ["$EVENT_INSTANCE_BACKUP_CREATED"]="instance source version"
  ["$EVENT_INSTANCE_BACKUP_RESTORED"]="instance source version"
  ["$EVENT_INSTANCE_FILES_REMOVED"]="instance"
  ["$EVENT_INSTANCE_DIRECTORIES_REMOVED"]="instance"
  ["$EVENT_INSTANCE_REMOVED"]="instance"
  ["$EVENT_INSTANCE_UNINSTALL_STARTED"]="instance"
  ["$EVENT_INSTANCE_UNINSTALL_FINISHED"]="instance"
  ["$EVENT_INSTANCE_UNINSTALLED"]="instance"
)

# Validates that an event type is supported
# Args: $1 = event_type (e.g., "instance_created")
# Returns: EC_OKAY if valid, EC_EVENT_TYPE_INVALID if not
function __logic_validate_event_type() {
  local event_type="$1"

  if [[ -z "$event_type" ]]; then
    return $EC_EVENT_TYPE_INVALID
  fi

  # Check if event type exists in configuration
  if [[ -z "${EVENT_CONFIGS[$event_type]}" ]]; then
    return $EC_EVENT_TYPE_INVALID
  fi

  return $EC_OKAY
}

export -f __logic_validate_event_type

# Validates event parameters match the required specification
# Args: $1 = event_type, $2... = parameters
# Returns: EC_OKAY if valid, EC_EVENT_PARAMS_INVALID if not
function __logic_validate_event_params() {
  local event_type="$1"
  shift
  local params=("$@")

  # Validate event type first
  if ! __logic_validate_event_type "$event_type"; then
    return $EC_EVENT_TYPE_INVALID
  fi

  # Get required parameters
  local required_params=(${EVENT_CONFIGS[$event_type]})

  # Validate parameter count
  if [[ ${#params[@]} -lt ${#required_params[@]} ]]; then
    return $EC_EVENT_PARAMS_INVALID
  fi

  # Validate each required parameter is non-empty
  for i in "${!required_params[@]}"; do
    local param_value="${params[$i]}"
    if [[ -z "$param_value" ]]; then
      return $EC_EVENT_PARAMS_INVALID
    fi
  done

  return $EC_OKAY
}

export -f __logic_validate_event_params

# Returns the parameter specification for an event type
# Args: $1 = event_type
# Returns: EC_OKAY and echoes param spec (space-separated), or EC_EVENT_TYPE_INVALID
function __logic_get_event_param_spec() {
  local event_type="$1"

  # Validate event type first
  if ! __logic_validate_event_type "$event_type"; then
    return $EC_EVENT_TYPE_INVALID
  fi

  echo "${EVENT_CONFIGS[$event_type]}"
  return $EC_OKAY
}

export -f __logic_get_event_param_spec

# Converts dash-separated event name to underscore constant
# Args: $1 = event_name (e.g., "instance-created")
# Returns: EC_OKAY and echoes constant name (e.g., "instance_created"), or EC_EVENT_TYPE_INVALID
function __logic_event_name_to_type() {
  local event_name="$1"

  if [[ -z "$event_name" ]]; then
    return $EC_EVENT_TYPE_INVALID
  fi

  # Convert dashes to underscores
  local event_type="${event_name//-/_}"

  # Validate the resulting type exists
  if ! __logic_validate_event_type "$event_type"; then
    return $EC_EVENT_TYPE_INVALID
  fi

  echo "$event_type"
  return $EC_OKAY
}

export -f __logic_event_name_to_type

# Mark module as loaded
export KGSM_LOGIC_EVENTS_LOADED=1
