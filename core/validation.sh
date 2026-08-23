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

if [[ -n "${KGSM_VALIDATION_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# VALIDATION CONSTANTS
# =============================================================================

# Use existing error codes from errors.sh
# EC_FILE_NOT_FOUND=5 (blueprint not found)
# EC_INVALID_ARG=8 (invalid format, empty, corrupted)
# EC_PERMISSION=16 (not readable)

# Every message recorded by the most recent validate_blueprint_format call.
# Reset on each call, so it reflects one validation and never accumulates.
# Bash arrays do not survive `export`, so a reader must run in the same shell as
# the validation — the blueprints handler builds its JSON verdict in-process for
# exactly this reason.
declare -g -a KGSM_BLUEPRINT_VALIDATION_ERRORS=()

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

# Check if a blueprint exists (unified `<name>.bp.yaml`, either runtime)
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
    __print_error "  - User: $KGSM_USER_BLUEPRINTS_DIR"
    __print_error "  - System: $KGSM_SYSTEM_BLUEPRINTS_DIR"
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

# Records a blueprint format error: appends it to the collected-error array and
# prints it. Callers that only inspect the return code are unaffected; callers
# that want the full list read KGSM_BLUEPRINT_VALIDATION_ERRORS afterwards.
# Usage: __record_blueprint_error <message>
function __record_blueprint_error() {
  local message="$1"

  KGSM_BLUEPRINT_VALIDATION_ERRORS+=("$message")
  __print_error "$message"
}

export -f __record_blueprint_error

# Validate a unified blueprint's format and required fields.
# All blueprints are YAML (`<name>.bp.yaml`); `runtime` discriminates the body.
# Required: `name`, `runtime` (native|container); native requires
# `native.executable_file`; container requires a `container.compose` with at
# least one service, every service on `network_mode: host` (KGSM containers are
# host-networked so their firewall/UPnP behaviour matches native instances; a
# bridge service's published ports would bypass the host firewall). (`level_name`
# / `executable_arguments` are optional — they default during instance creation.)
#
# Every failure is recorded in the KGSM_BLUEPRINT_VALIDATION_ERRORS array, reset
# on entry. The field checks all run so the array holds the complete list of
# problems — an editor showing a rejected save reports every one at once instead
# of making the user fix them one round-trip at a time. The gates above them
# (empty file, missing yq, unparseable YAML) return on the spot: nothing further
# can be inspected once one of those fails.
# Usage: validate_blueprint_format <blueprint_path>
# Returns: 0 if valid format, non-zero if invalid
function validate_blueprint_format() {
  local blueprint_path="$1"

  KGSM_BLUEPRINT_VALIDATION_ERRORS=()

  if [[ -z "$blueprint_path" ]]; then
    __record_blueprint_error "validate_blueprint_format: Blueprint path cannot be empty"
    return $EC_INVALID_ARG
  fi

  # Check if file is empty
  if [[ ! -s "$blueprint_path" ]]; then
    __record_blueprint_error "Blueprint file is empty: $blueprint_path"
    return $EC_INVALID_ARG
  fi

  # yq is a hard dependency — fail with an actionable message before the syntax
  # check (which would otherwise misreport a yq-less host as "Invalid YAML").
  # __require_yq prints its own message, so record without reprinting.
  if ! __require_yq; then
    KGSM_BLUEPRINT_VALIDATION_ERRORS+=("yq is required to validate blueprints but is not installed")
    return $EC_MISSING_DEPENDENCY
  fi

  # YAML syntax (yq is a hard dependency)
  if ! yq eval '.' "$blueprint_path" >/dev/null 2>&1; then
    __record_blueprint_error "Invalid YAML syntax in blueprint: $blueprint_path"
    return $EC_INVALID_ARG
  fi

  # Required common fields
  local name runtime
  name=$(yq -r '.name // ""' "$blueprint_path" 2>/dev/null)
  runtime=$(yq -r '.runtime // ""' "$blueprint_path" 2>/dev/null)

  if [[ -z "$name" ]]; then
    __record_blueprint_error "Blueprint missing required field 'name': $blueprint_path"
  fi

  case "$runtime" in
    native)
      local executable_file
      executable_file=$(yq -r '.native.executable_file // ""' "$blueprint_path" 2>/dev/null)
      if [[ -z "$executable_file" ]]; then
        __record_blueprint_error "Native blueprint missing required field 'native.executable_file': $blueprint_path"
      fi
      ;;
    container)
      local compose service_count
      compose=$(yq -r '.container.compose // ""' "$blueprint_path" 2>/dev/null)
      if [[ -z "$compose" ]]; then
        __record_blueprint_error "Container blueprint missing required field 'container.compose': $blueprint_path"
        return $EC_INVALID_ARG
      fi
      service_count=$(printf '%s' "$compose" | yq -r '.services | length' 2>/dev/null)
      if [[ ! "$service_count" =~ ^[0-9]+$ ]] || ((service_count < 1)); then
        __record_blueprint_error "Container blueprint 'container.compose' defines no services: $blueprint_path"
        return $EC_INVALID_ARG
      fi
      # KGSM containers are host-networked (`network_mode: host`). Under host
      # networking the compose `ports:` block is NOT a Docker publish — Docker
      # ignores it and the game process listens straight on the host's network
      # stack, so ufw/kgsm-firewall's INPUT rules govern the instance exactly
      # like a native one. `ports:` stays the declarative source of truth for the
      # host-firewall rule and router UPnP (kgsm-watchdog reads it). A bridge
      # service with the same `ports:` would instead DNAT-publish into the
      # FORWARD/DOCKER-USER path, which bypasses ufw's INPUT chain — an unfiltered
      # hole on a DMZ host. Require host networking on every service so that can
      # never reach an instance.
      local non_host_services
      non_host_services=$(printf '%s' "$compose" \
        | yq -r '[.services.* | select(.network_mode != "host")] | length' 2>/dev/null)
      if [[ ! "$non_host_services" =~ ^[0-9]+$ ]] || ((non_host_services > 0)); then
        __record_blueprint_error "Container blueprint service missing 'network_mode: host' (KGSM containers are host-networked; a bridge service's published ports bypass the host firewall): $blueprint_path"
      fi
      ;;
    *)
      __record_blueprint_error "Blueprint has invalid or missing 'runtime' (expected native|container): $blueprint_path"
      ;;
  esac

  if [[ ${#KGSM_BLUEPRINT_VALIDATION_ERRORS[@]} -gt 0 ]]; then
    return $EC_INVALID_ARG
  fi

  return 0
}

export -f validate_blueprint_format

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

# Validates the character set an instance id must satisfy.
#
# The id is a path component, a file basename, a registry symlink name and a
# cgroup directory name all at once, so it is restricted to what every one of
# those accepts: it opens with a letter or digit and carries only letters,
# digits, '.', '_' and '-', up to 64 characters. This is checked on every id a
# caller supplies and on none that KGSM generates — a generated id is drawn from
# the blueprint name and digits, which is already inside this set.
#
# Usage: validate_instance_id_format <instance_id>
# Returns: 0 when the id is usable, EC_INVALID_ARG otherwise
function validate_instance_id_format() {
  local instance_id="$1"

  if [[ -z "$instance_id" ]]; then
    __print_error "Instance id cannot be empty"
    return $EC_INVALID_ARG
  fi

  if [[ ! "$instance_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
    __print_error "Invalid instance id '$instance_id'"
    __print_error "An id starts with a letter or digit and may contain letters, digits, '.', '_' and '-', up to 64 characters"
    return $EC_INVALID_ARG
  fi

  return 0
}

export -f validate_instance_id_format

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

  # An argument that is not an id may be a display name, which resolves to one
  # when exactly one instance carries it. The resolver echoes the argument back
  # unchanged when nothing matches, so the not-found message below still names
  # what the caller actually typed.
  instance_name="$(__resolve_instance_id "$instance_name")" || return $?

  # Try to find the instance config file
  local instance_config_file
  if ! instance_config_file=$(__find_instance_config "$instance_name" 2>/dev/null); then
    __print_error "Instance '$instance_name' not found"
    __print_error "Available instances can be found in: $KGSM_INSTANCES_DIR"
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

# Mark module as loaded
declare -g KGSM_VALIDATION_LOADED=1
export KGSM_VALIDATION_LOADED
