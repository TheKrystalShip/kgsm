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

if [[ -z "${KGSM_BLUEPRINT_TYPE_NATIVE}" ]]; then
  declare -g -r KGSM_BLUEPRINT_TYPE_NATIVE="native"
  export KGSM_BLUEPRINT_TYPE_NATIVE
fi

if [[ -z "${KGSM_BLUEPRINT_TYPE_CONTAINER}" ]]; then
  declare -g -r KGSM_BLUEPRINT_TYPE_CONTAINER="container"
  export KGSM_BLUEPRINT_TYPE_CONTAINER
fi

# Validates a blueprint name and returns its type (native or container)
# Args: $1 = blueprint_name
# Returns: 0 and echoes "native" or "container", or error code on failure
function __logic_get_blueprint_type() {
  local blueprint_name="$1"

  # Validate parameter
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate blueprint exists (using existing validation from core/validation.sh)
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint_name" 2> /dev/null)
  local validation_result=$?

  if [[ $validation_result -ne 0 ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Determine blueprint type based on file extension
  if [[ "$blueprint_path" == *.bp ]]; then
    echo "$KGSM_BLUEPRINT_TYPE_NATIVE"
    return 0
  elif [[ "$blueprint_path" == *docker-compose.yml ]] || [[ "$blueprint_path" == *docker-compose.yaml ]]; then
    echo "$KGSM_BLUEPRINT_TYPE_CONTAINER"
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

  # This checks existence, readability, and format
  validate_blueprint "$blueprint_name" > /dev/null 2>&1
  exit_code=$?

  # Convert file not found to blueprint not found for consistency
  if [[ $exit_code -eq $EC_FILE_NOT_FOUND ]]; then
    exit_code=$EC_BLUEPRINT_NOT_FOUND
  fi

  return $exit_code
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
  blueprint_path=$(validate_blueprint_exists "$blueprint_name" 2> /dev/null)
  local validation_result=$?

  if [[ $validation_result -ne 0 ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Validate the blueprint is readable and properly formatted
  if ! validate_blueprint "$blueprint_name" > /dev/null 2>&1; then
    return $EC_INVALID_BLUEPRINT
  fi

  echo "$blueprint_path"
  return 0
}

export -f __logic_get_blueprint_path

# Lists all blueprints (both native and container)
# Args: $1 = source ("custom", "default", or "all") - optional, defaults to "all"
# Returns: Success code and echoes newline-separated list, or error code
function __logic_list_blueprints() {
  local source="${1:-all}"

  local -a all_blueprints=()

  # Get native blueprints
  local native_list
  native_list=$(__logic_list_native_blueprints "$source" 2>/dev/null)
  if [[ -n "$native_list" ]]; then
    while IFS= read -r blueprint; do
      [[ -n "$blueprint" ]] && all_blueprints+=("$blueprint")
    done <<< "$native_list"
  fi

  # Get container blueprints
  local container_list
  container_list=$(__logic_list_container_blueprints "$source" 2>/dev/null)
  if [[ -n "$container_list" ]]; then
    while IFS= read -r blueprint; do
      [[ -n "$blueprint" ]] && all_blueprints+=("$blueprint")
    done <<< "$container_list"
  fi

  # Remove duplicates and sort
  if [[ ${#all_blueprints[@]} -gt 0 ]]; then
    printf "%s\n" "${all_blueprints[@]}" | sort -u
  fi

  return $EC_SUCCESS_BLUEPRINT_LISTED
}

export -f __logic_list_blueprints

# =============================================================================
# NATIVE BLUEPRINT LOGIC FUNCTIONS
# =============================================================================

# Finds a native blueprint file path
# Args: $1 = blueprint_name
# Returns: Success code and echoes path, or EC_BLUEPRINT_NOT_FOUND
function __logic_find_native_blueprint() {
  local blueprint="$1"

  if [[ -z "$blueprint" ]]; then
    return $EC_INVALID_ARG
  fi

  # Strip .bp extension if present
  [[ "$blueprint" == *.bp ]] && blueprint="${blueprint%.bp}"

  # Check custom blueprints first (user-made blueprints take priority)
  local bp_path="$BLUEPRINTS_NATIVE_CUSTOM_DIR/$blueprint.bp"
  if [[ -f "$bp_path" ]]; then
    echo "$bp_path"
    return $EC_SUCCESS_BLUEPRINT_FOUND
  fi

  # Check default blueprints (included with KGSM)
  bp_path="$BLUEPRINTS_NATIVE_DEFAULT_DIR/$blueprint.bp"
  if [[ -f "$bp_path" ]]; then
    echo "$bp_path"
    return $EC_SUCCESS_BLUEPRINT_FOUND
  fi

  return $EC_BLUEPRINT_NOT_FOUND
}

export -f __logic_find_native_blueprint

# Lists native blueprints from a specific location
# Args: $1 = source ("custom", "default", or "all")
# Returns: Success code and echoes newline-separated list, or error code
function __logic_list_native_blueprints() {
  local source="${1:-all}"

  if [[ -z "$source" ]]; then
    return $EC_INVALID_ARG
  fi

  local source_dir=""
  case "$source" in
    custom)
      source_dir="$BLUEPRINTS_NATIVE_CUSTOM_DIR"
      ;;
    default)
      source_dir="$BLUEPRINTS_NATIVE_DEFAULT_DIR"
      ;;
    all)
      # Will be handled by combining both
      ;;
    *)
      return $EC_INVALID_ARG
      ;;
  esac

  if [[ "$source" == "all" ]]; then
    # Combine both sources
    local -a blueprints=()

    # Get custom blueprints
    if [[ -d "$BLUEPRINTS_NATIVE_CUSTOM_DIR" ]]; then
      while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        basename="${basename%.bp}"
        [[ -n "$basename" ]] && blueprints+=("$basename")
      done < <(find "$BLUEPRINTS_NATIVE_CUSTOM_DIR" -maxdepth 1 -name "*.bp" -type f -print0 2>/dev/null)
    fi

    # Get default blueprints
    if [[ -d "$BLUEPRINTS_NATIVE_DEFAULT_DIR" ]]; then
      while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        basename="${basename%.bp}"
        [[ -n "$basename" ]] && blueprints+=("$basename")
      done < <(find "$BLUEPRINTS_NATIVE_DEFAULT_DIR" -maxdepth 1 -name "*.bp" -type f -print0 2>/dev/null)
    fi

    # Remove duplicates and sort
    if [[ ${#blueprints[@]} -gt 0 ]]; then
      printf "%s\n" "${blueprints[@]}" | sort -u
      return $EC_SUCCESS_BLUEPRINT_LISTED
    fi

    return $EC_SUCCESS_BLUEPRINT_LISTED  # Empty list is still success
  else
    # Single source
    if [[ ! -d "$source_dir" ]]; then
      return $EC_SUCCESS_BLUEPRINT_LISTED  # Empty list is success
    fi

    local -a blueprints=()
    while IFS= read -r -d '' file; do
      local basename="${file##*/}"
      basename="${basename%.bp}"
      [[ -n "$basename" ]] && blueprints+=("$basename")
    done < <(find "$source_dir" -maxdepth 1 -name "*.bp" -type f -print0 2>/dev/null)

    if [[ ${#blueprints[@]} -gt 0 ]]; then
      printf "%s\n" "${blueprints[@]}" | sort -u
    fi

    return $EC_SUCCESS_BLUEPRINT_LISTED
  fi
}

export -f __logic_list_native_blueprints

# Gets native blueprint metadata
# Args: $1 = blueprint_name
# Returns: Success code and echoes structured data (key=value format), or error code
function __logic_get_native_blueprint_info() {
  local blueprint="$1"

  if [[ -z "$blueprint" ]]; then
    return $EC_INVALID_ARG
  fi

  # Find the blueprint
  local blueprint_path
  blueprint_path=$(__logic_find_native_blueprint "$blueprint")
  local result=$?

  if [[ $result -ne $EC_SUCCESS_BLUEPRINT_FOUND ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Validate it's readable
  if [[ ! -r "$blueprint_path" ]]; then
    return $EC_PERMISSION
  fi

  # Source the blueprint to get variables
  if ! __source_blueprint "$blueprint" >/dev/null 2>&1; then
    return $EC_INVALID_BLUEPRINT
  fi

  # Return structured data (key=value format, parseable by module layer)
  # shellcheck disable=SC2154
  # The blueprint_* variables are created dynamically when sourcing the blueprint file
  cat <<EOF
name=$blueprint_name
ports=$blueprint_ports
steam_app_id=$blueprint_steam_app_id
is_steam_account_required=$blueprint_is_steam_account_required
executable_file=$blueprint_executable_file
level_name=$blueprint_level_name
executable_subdirectory=$blueprint_executable_subdirectory
executable_arguments=$blueprint_executable_arguments
stop_command=$blueprint_stop_command
save_command=$blueprint_save_command
blueprint_type=native
blueprint_path=$blueprint_path
EOF

  return $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED
}

export -f __logic_get_native_blueprint_info

# =============================================================================
# CONTAINER BLUEPRINT LOGIC FUNCTIONS
# =============================================================================

# Finds a container blueprint file path
# Args: $1 = blueprint_name
# Returns: Success code and echoes path, or EC_BLUEPRINT_NOT_FOUND
function __logic_find_container_blueprint() {
  local blueprint="$1"

  if [[ -z "$blueprint" ]]; then
    return $EC_INVALID_ARG
  fi

  # Strip .docker-compose.yml extension if present
  [[ "$blueprint" == *.docker-compose.yml ]] && blueprint="${blueprint%.docker-compose.yml}"

  # Check custom blueprints first
  local bp_path="$BLUEPRINTS_CONTAINER_CUSTOM_DIR/$blueprint.docker-compose.yml"
  if [[ -f "$bp_path" ]]; then
    echo "$bp_path"
    return $EC_SUCCESS_BLUEPRINT_FOUND
  fi

  # Check default blueprints
  bp_path="$BLUEPRINTS_CONTAINER_DEFAULT_DIR/$blueprint.docker-compose.yml"
  if [[ -f "$bp_path" ]]; then
    echo "$bp_path"
    return $EC_SUCCESS_BLUEPRINT_FOUND
  fi

  return $EC_BLUEPRINT_NOT_FOUND
}

export -f __logic_find_container_blueprint

# Lists container blueprints from a specific location
# Args: $1 = source ("custom", "default", or "all")
# Returns: Success code and echoes newline-separated list, or error code
function __logic_list_container_blueprints() {
  local source="${1:-all}"

  if [[ -z "$source" ]]; then
    return $EC_INVALID_ARG
  fi

  local source_dir=""
  case "$source" in
    custom)
      source_dir="$BLUEPRINTS_CONTAINER_CUSTOM_DIR"
      ;;
    default)
      source_dir="$BLUEPRINTS_CONTAINER_DEFAULT_DIR"
      ;;
    all)
      # Will be handled by combining both
      ;;
    *)
      return $EC_INVALID_ARG
      ;;
  esac

  if [[ "$source" == "all" ]]; then
    # Combine both sources
    local -a blueprints=()

    # Get custom blueprints
    if [[ -d "$BLUEPRINTS_CONTAINER_CUSTOM_DIR" ]]; then
      while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        basename="${basename%.docker-compose.yml}"
        [[ -n "$basename" ]] && blueprints+=("$basename")
      done < <(find "$BLUEPRINTS_CONTAINER_CUSTOM_DIR" -maxdepth 1 -name "*.docker-compose.yml" -type f -print0 2>/dev/null)
    fi

    # Get default blueprints
    if [[ -d "$BLUEPRINTS_CONTAINER_DEFAULT_DIR" ]]; then
      while IFS= read -r -d '' file; do
        local basename="${file##*/}"
        basename="${basename%.docker-compose.yml}"
        [[ -n "$basename" ]] && blueprints+=("$basename")
      done < <(find "$BLUEPRINTS_CONTAINER_DEFAULT_DIR" -maxdepth 1 -name "*.docker-compose.yml" -type f -print0 2>/dev/null)
    fi

    # Remove duplicates and sort
    if [[ ${#blueprints[@]} -gt 0 ]]; then
      printf "%s\n" "${blueprints[@]}" | sort -u
      return $EC_SUCCESS_BLUEPRINT_LISTED
    fi

    return $EC_SUCCESS_BLUEPRINT_LISTED  # Empty list is still success
  else
    # Single source
    if [[ ! -d "$source_dir" ]]; then
      return $EC_SUCCESS_BLUEPRINT_LISTED  # Empty list is success
    fi

    local -a blueprints=()
    while IFS= read -r -d '' file; do
      local basename="${file##*/}"
      basename="${basename%.docker-compose.yml}"
      [[ -n "$basename" ]] && blueprints+=("$basename")
    done < <(find "$source_dir" -maxdepth 1 -name "*.docker-compose.yml" -type f -print0 2>/dev/null)

    if [[ ${#blueprints[@]} -gt 0 ]]; then
      printf "%s\n" "${blueprints[@]}" | sort -u
    fi

    return $EC_SUCCESS_BLUEPRINT_LISTED
  fi
}

export -f __logic_list_container_blueprints

# Gets container blueprint metadata
# Args: $1 = blueprint_name
# Returns: Success code and echoes structured data (key=value format), or error code
function __logic_get_container_blueprint_info() {
  local blueprint="$1"

  if [[ -z "$blueprint" ]]; then
    return $EC_INVALID_ARG
  fi

  # Find the blueprint
  local blueprint_path
  blueprint_path=$(__logic_find_container_blueprint "$blueprint")
  local result=$?

  if [[ $result -ne $EC_SUCCESS_BLUEPRINT_FOUND ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Validate it's readable
  if [[ ! -r "$blueprint_path" ]]; then
    return $EC_PERMISSION
  fi

  # Extract ports from docker-compose.yml using existing parser
  local ports=""
  if command -v __parse_docker_compose_to_ufw_ports >/dev/null 2>&1; then
    ports=$(__parse_docker_compose_to_ufw_ports "$blueprint_path" 2>/dev/null || echo "")
  fi

  # Return structured data (key=value format)
  cat <<EOF
name=$blueprint
ports=$ports
steam_app_id=
is_steam_account_required=
executable_file=
level_name=
executable_subdirectory=
executable_arguments=
stop_command=
save_command=
blueprint_type=container
blueprint_path=$blueprint_path
EOF

  return $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED
}

export -f __logic_get_container_blueprint_info

# Mark module as loaded
export KGSM_LOGIC_BLUEPRINTS_LOADED=1
