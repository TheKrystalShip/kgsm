#!/usr/bin/env bash

# KGSM Validation Module
#
# This module provides validation functions to ensure consistent behavior
# across KGSM commands, addressing the behavioral uncertainty discovery.
#
# All validation functions follow these principles:
# 1. Return 0 (success) for valid inputs
# 2. Return non-zero exit codes for invalid inputs
# 3. Provide clear, actionable error messages
# 4. Log validation attempts for debugging

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# =============================================================================
# VALIDATION CONSTANTS
# =============================================================================

# Use existing error codes from errors.sh
# EC_FILE_NOT_FOUND=5 (blueprint not found)
# EC_INVALID_ARG=8 (invalid format, empty, corrupted)
# EC_PERMISSION=16 (not readable)

# =============================================================================
# BLUEPRINT VALIDATION FUNCTIONS
# =============================================================================

# Validate that a blueprint exists and is properly formatted
# Usage: validate_blueprint <blueprint_name_or_path>
# Returns: 0 if valid, non-zero if invalid
function validate_blueprint() {
  local blueprint_input="$1"

  if [[ -z "$blueprint_input" ]]; then
    __print_error "validate_blueprint: Blueprint name cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Step 1: Check if blueprint exists
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint_input")
  local exists_result=$?
  if [[ $exists_result -ne 0 ]]; then
    return $exists_result
  fi

  # Step 2: Check if blueprint is readable
  validate_blueprint_readable "$blueprint_path"
  local readable_result=$?
  if [[ $readable_result -ne 0 ]]; then
    return $readable_result
  fi

  # Step 3: Check if blueprint is properly formatted
  validate_blueprint_format "$blueprint_path"
  local format_result=$?
  if [[ $format_result -ne 0 ]]; then
    return $format_result
  fi
  return 0
}

export -f validate_blueprint

# Check if a blueprint exists (handles both native .bp and container .docker-compose.yml)
# Usage: validate_blueprint_exists <blueprint_name_or_path>
# Returns: 0 if exists, prints path to stdout; non-zero if not found
function validate_blueprint_exists() {
  local blueprint_input="$1"

  if [[ -z "$blueprint_input" ]]; then
    __print_error "validate_blueprint_exists: Blueprint name cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Try to find the blueprint using the existing __find_blueprint function
  local blueprint_path
  if blueprint_path=$(__find_blueprint "$blueprint_input" 2>/dev/null); then
    # Blueprint found, return the path
    echo "$blueprint_path"
    return 0
  else
    # Blueprint not found, provide helpful error message
    __print_error "Blueprint '$blueprint_input' not found"
    __print_error "Searched in:"
    __print_error "  - Custom native: $BLUEPRINTS_NATIVE_CUSTOM_DIR"
    __print_error "  - Custom container: $BLUEPRINTS_CONTAINER_CUSTOM_DIR"
    __print_error "  - Default native: $BLUEPRINTS_NATIVE_DEFAULT_DIR"
    __print_error "  - Default container: $BLUEPRINTS_CONTAINER_DEFAULT_DIR"
    return $EC_FILE_NOT_FOUND
  fi
}

export -f validate_blueprint_exists

# Check if a blueprint file is readable
# Usage: validate_blueprint_readable <blueprint_path>
# Returns: 0 if readable, non-zero if not
function validate_blueprint_readable() {
  local blueprint_path="$1"

  if [[ -z "$blueprint_path" ]]; then
    __print_error "validate_blueprint_readable: Blueprint path cannot be empty"
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$blueprint_path" ]]; then
    __print_error "Blueprint file does not exist: $blueprint_path"
    return $EC_FILE_NOT_FOUND
  fi

  if [[ ! -r "$blueprint_path" ]]; then
    __print_error "Blueprint file is not readable: $blueprint_path"
    __print_error "Check file permissions and ownership"
    return $EC_PERMISSION
  fi

  return 0
}

export -f validate_blueprint_readable

# Validate blueprint format based on file type
# Usage: validate_blueprint_format <blueprint_path>
# Returns: 0 if valid format, non-zero if invalid
function validate_blueprint_format() {
  local blueprint_path="$1"

  if [[ -z "$blueprint_path" ]]; then
    __print_error "validate_blueprint_format: Blueprint path cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Determine blueprint type by extension
  if [[ "$blueprint_path" == *.bp ]]; then
    validate_native_blueprint_format "$blueprint_path"
  elif [[ "$blueprint_path" == *.docker-compose.yml ]] || [[ "$blueprint_path" == *.docker-compose.yaml ]]; then
    validate_container_blueprint_format "$blueprint_path"
  else
    __print_error "Unknown blueprint format: $blueprint_path"
    __print_error "Supported formats: .bp, .docker-compose.yml, .docker-compose.yaml"
    return $EC_INVALID_ARG
  fi
}

export -f validate_blueprint_format

# Validate native blueprint (.bp) format
# Usage: validate_native_blueprint_format <blueprint_path>
# Returns: 0 if valid, non-zero if invalid
function validate_native_blueprint_format() {
  local blueprint_path="$1"

  if [[ -z "$blueprint_path" ]]; then
    __print_error "validate_native_blueprint_format: Blueprint path cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Check if file is empty
  if [[ ! -s "$blueprint_path" ]]; then
    __print_error "Blueprint file is empty: $blueprint_path"
    return $EC_INVALID_ARG
  fi

  # Check for basic required fields in native blueprints
  local required_fields=(
    "name"
    "executable_file"
    "executable_arguments"
  )

  local missing_fields=()

  for field in "${required_fields[@]}"; do
    if ! grep -q "^${field}=" "$blueprint_path"; then
      missing_fields+=("$field")
    fi
  done

  if [[ ${#missing_fields[@]} -gt 0 ]]; then
    __print_error "Blueprint missing required fields: ${missing_fields[*]}"
    __print_error "Blueprint path: $blueprint_path"
    return $EC_INVALID_ARG
  fi

  # Check for malformed key=value pairs
  local line_number=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number++))

    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Check if line follows key=value format
    if [[ ! "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
      __print_error "Invalid format at line $line_number: $line"
      __print_error "Expected format: key=value"
      __print_error "Blueprint path: $blueprint_path"
      return $EC_INVALID_ARG
    fi
  done <"$blueprint_path"

  return 0
}

export -f validate_native_blueprint_format

# Validate container blueprint (docker-compose.yml) format
# Usage: validate_container_blueprint_format <blueprint_path>
# Returns: 0 if valid, non-zero if invalid
function validate_container_blueprint_format() {
  local blueprint_path="$1"

  if [[ -z "$blueprint_path" ]]; then
    __print_error "validate_container_blueprint_format: Blueprint path cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Check if file is empty
  if [[ ! -s "$blueprint_path" ]]; then
    __print_error "Blueprint file is empty: $blueprint_path"
    return $EC_INVALID_ARG
  fi

  # Basic YAML syntax validation if yq is available
  if command -v yq >/dev/null 2>&1; then
    if ! yq eval '.' "$blueprint_path" >/dev/null 2>&1; then
      __print_error "Invalid YAML syntax in blueprint: $blueprint_path"
      return $EC_INVALID_ARG
    fi
  else
    # Fallback: basic checks without yq
    if ! grep -q "services:" "$blueprint_path"; then
      __print_error "Missing 'services:' field in docker-compose blueprint: $blueprint_path"
      return $EC_INVALID_ARG
    fi
  fi

  return 0
}

export -f validate_container_blueprint_format

# =============================================================================
# UTILITY VALIDATION FUNCTIONS
# =============================================================================

# Validate that a string is not empty
# Usage: validate_not_empty <value> <field_name>
# Returns: 0 if not empty, non-zero if empty
function validate_not_empty() {
  local value="$1"
  local field_name="${2:-value}"

  if [[ -z "$value" ]]; then
    __print_error "Validation failed: $field_name cannot be empty"
    return $EC_INVALID_ARG
  fi

  return 0
}

export -f validate_not_empty

# Validate that a directory exists
# Usage: validate_directory_exists <directory_path> [<field_name>]
# Returns: 0 if exists, non-zero if not
function validate_directory_exists() {
  local directory_path="$1"
  local field_name="${2:-directory}"

  if [[ -z "$directory_path" ]]; then
    __print_error "Validation failed: $field_name path cannot be empty"
    return $EC_INVALID_ARG
  fi

  if [[ ! -d "$directory_path" ]]; then
    __print_error "Validation failed: $field_name does not exist: $directory_path"
    return $EC_FILE_NOT_FOUND
  fi

  return 0
}

export -f validate_directory_exists

# Validate that a directory is writable
# Usage: validate_directory_writable <directory_path> [<field_name>]
# Returns: 0 if writable, non-zero if not
function validate_directory_writable() {
  local directory_path="$1"
  local field_name="${2:-directory}"

  if [[ -z "$directory_path" ]]; then
    __print_error "Validation failed: $field_name path cannot be empty"
    return $EC_INVALID_ARG
  fi

  if [[ ! -w "$directory_path" ]]; then
    __print_error "Validation failed: $field_name is not writable: $directory_path"
    __print_error "Check directory permissions and ownership"
    return $EC_PERMISSION
  fi

  return 0
}

export -f validate_directory_writable

# =============================================================================
# INSTANCE VALIDATION FUNCTIONS
# =============================================================================

# Validates instance name and returns config file path
# Usage: validate_instance_name <instance_name>
# Returns: 0 on success, error code on failure
# Outputs: instance_config_file path to stdout
function validate_instance_name() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    __print_error "validate_instance_name: Instance name cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Try to find the instance config file
  local instance_config_file
  if ! instance_config_file=$(__find_instance_config "$instance_name" 2>/dev/null); then
    __print_error "Instance '$instance_name' not found"
    __print_error "Available instances can be found in: $INSTANCES_SOURCE_DIR"
    return $EC_FILE_NOT_FOUND
  fi

  # Check if the config file is readable
  if [[ ! -r "$instance_config_file" ]]; then
    __print_error "Instance config file is not readable: $instance_config_file"
    __print_error "Check file permissions and ownership"
    return $EC_PERMISSION
  fi

  # Output the config file path
  echo "$instance_config_file"
  return 0
}

export -f validate_instance_name

# Validates that working directory is properly configured
# Usage: validate_working_directory <instance_config_file>
# Returns: 0 on success, error code on failure
# Outputs: instance_working_dir path to stdout
function validate_working_directory() {
  local instance_config_file="$1"

  if [[ -z "$instance_config_file" ]]; then
    __print_error "validate_working_directory: Instance config file path cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Check if the config file exists
  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance config file does not exist: $instance_config_file"
    return $EC_FILE_NOT_FOUND
  fi

  # Extract the working directory from the config file
  local instance_working_dir
  instance_working_dir=$(__get_config_value "$instance_config_file" "working_dir" 2>/dev/null)
  local result=$?

  if [[ $result -ne 0 ]]; then
    __print_error "Failed to read working_dir from config file: $instance_config_file"
    return $result
  fi

  # Check if working_dir is set
  if [[ -z "$instance_working_dir" ]]; then
    __print_error "working_dir is not set in the instance config file: $instance_config_file"
    return $EC_INVALID_CONFIG
  fi

  # Ensure working_dir is an absolute path
  if [[ ! "$instance_working_dir" = /* ]]; then
    __print_error "working_dir must be an absolute path, got: $instance_working_dir"
    __print_error "Config file: $instance_config_file"
    return $EC_INVALID_CONFIG
  fi

  # Output the working directory path
  echo "$instance_working_dir"
  return 0
}

export -f validate_working_directory

# =============================================================================
# VALIDATION REPORTING
# =============================================================================

# Print validation summary for debugging
# Usage: print_validation_summary <operation> <result>
function print_validation_summary() {
  local operation="$1"
  local result="$2"

  if [[ "$result" -eq 0 ]]; then
    __print_success "Validation passed: $operation"
  else
    __print_error "Validation failed: $operation (exit code: $result)"
  fi
}

export -f print_validation_summary

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Export validation constants for use in other modules
export EC_INVALID_ARG
export EC_INVALID_ARG
export EC_INVALID_ARG

# Mark module as loaded
export KGSM_VALIDATION_LOADED=1
