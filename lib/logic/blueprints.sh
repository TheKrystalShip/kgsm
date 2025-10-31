#!/usr/bin/env bash

# KGSM Pure Logic Layer - Blueprint Management
#
# This module contains pure business logic functions for blueprint operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - Standard error codes: EC_BLUEPRINT_NOT_FOUND, EC_INVALID_BLUEPRINT, EC_PERMISSION, etc.
#
# Note: The blueprint module is primarily an orchestration layer that combines
# results from blueprints.native.sh and blueprints.container.sh modules.
# Most blueprint operations are delegated to those specialized modules.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Validates a blueprint name and returns its type (native or container)
# Args: $1 = blueprint_name
# Returns: 0 and echoes "native" or "container", or error code on failure
function __logic_get_blueprint_type() {
  local blueprint_name="$1"

  # Validate parameter
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate blueprint exists (using existing validation from lib/validation.sh)
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint_name" 2>/dev/null)
  local validation_result=$?

  if [[ $validation_result -ne 0 ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Determine blueprint type based on file extension
  if [[ "$blueprint_path" == *.bp ]]; then
    echo "native"
    return 0
  elif [[ "$blueprint_path" == *docker-compose.yml ]] || [[ "$blueprint_path" == *docker-compose.yaml ]]; then
    echo "container"
    return 0
  else
    return $EC_INVALID_BLUEPRINT
  fi
}

export -f __logic_get_blueprint_type

# Validates that a blueprint exists and is properly formatted
# Args: $1 = blueprint_name
# Returns: 0 on success, error codes on failure
function __logic_validate_blueprint() {
  local blueprint_name="$1"

  # Validate parameter
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Use existing comprehensive validation from lib/validation.sh
  # This checks existence, readability, and format
  validate_blueprint "$blueprint_name" >/dev/null 2>&1
  return $?
}

export -f __logic_validate_blueprint

# Gets the absolute path to a blueprint file
# Args: $1 = blueprint_name
# Returns: 0 and echoes path, or error code on failure
function __logic_get_blueprint_path() {
  local blueprint_name="$1"

  # Validate parameter
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate blueprint and get path
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint_name" 2>/dev/null)
  local validation_result=$?

  if [[ $validation_result -ne 0 ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Validate the blueprint is readable and properly formatted
  if ! validate_blueprint "$blueprint_name" >/dev/null 2>&1; then
    return $EC_INVALID_BLUEPRINT
  fi

  echo "$blueprint_path"
  return 0
}

export -f __logic_get_blueprint_path

# Mark module as loaded
export KGSM_LOGIC_BLUEPRINTS_LOADED=1
