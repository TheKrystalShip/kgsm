#!/usr/bin/env bash

# KGSM Pure Logic Layer - File Management Common Functions
#
# This module contains shared helper functions used by file management logic libraries.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - Standard error codes: EC_FAILED_TEMPLATE, EC_PERMISSION, EC_INVALID_ARG, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_FILES_COMMON_LOADED:-}" ]]; then
  return 0
fi

# Inject override functions into a management file
# Args: $1 = _instance_name, $2 = _instance_management_file
# Returns: 0 on success, error code on failure
function __logic_inject_overrides() {
  local _instance_name="$1"
  local _instance_management_file="$2"

  # Validate input
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -z "$_instance_management_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$_instance_management_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Get blueprint name from instance config
  local instance_config_file
  instance_config_file=$(__find_instance_config "$_instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_INVALID_INSTANCE
  fi

  local blueprint_file
  blueprint_file=$(__get_config_value "$instance_config_file" "blueprint_file" 2> /dev/null)

  if [[ -z "$blueprint_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # If it's a container blueprint, overrides are not supported
  if [[ "$blueprint_file" == *.docker-compose.yml ]]; then
    return 0
  fi

  # Get blueprint name from the blueprint file's 'name' field
  local blueprint_name
  blueprint_name=$(__get_config_value "$blueprint_file" "name" 2> /dev/null)

  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  local instance_overrides_file="${KGSM_SYSTEM_OVERRIDES_DIR}/${blueprint_name}.overrides.sh"

  # If no overrides file exists, nothing to inject (this is valid)
  if [[ ! -f "$instance_overrides_file" ]]; then
    return 0
  fi

  # Source the overrides file to get function definitions
  # shellcheck disable=SC1090
  source "$instance_overrides_file" 2> /dev/null || return $EC_FAILED_SOURCE

  # For each function name declared in the overrides file…
  grep -Po '^function \K[[:alnum:]_]+' "${instance_overrides_file}" | while read -r fn; do

    # Check if the function is defined in the overrides file
    # Since the overrides file is sourced, we can check if the function exists
    if ! declare -F "${fn}" &>/dev/null; then
      continue
    fi

    func_def=$(declare -f "${fn}")

    # Create a temporary file to hold the new function body
    tmp=$(mktemp)
    printf '%s\n' "${func_def}" | sed '1 s|^|function |' >"${tmp}"

    # In-place sed:
    #   1. On the "function NAME" line, `r tmp` will read/insert the new body *below* that line.
    #   2. Then the range delete `/^function NAME.../,/^}/ d` removes the entire old block,
    #      including that matched "function" line and its closing `}`.
    #   The net effect is that the new body (from the tmp file) ends up in place of the old.
    sed -i \
      -e "/^function ${fn}[[:space:]]*(/ r ${tmp}" \
      -e "/^function ${fn}[[:space:]]*(/,/^}/ d" \
      "${_instance_management_file}"

    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
      rm -f "${tmp}" # Clean up the temporary file
      return $EC_FAILED_TEMPLATE
    fi

    # Clean up the temporary file
    rm -f "${tmp}"
  done

  return 0
}

export -f __logic_inject_overrides

# Set file ownership to the appropriate user
# Args: $1 = file_path
# Returns: 0 on success, EC_PERMISSION on failure
function __logic_set_file_ownership() {
  local file_path="$1"

  if [[ -z "$file_path" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -e "$file_path" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  local instance_user=$USER
  if [ "$EUID" -eq 0 ]; then
    instance_user=$SUDO_USER
  fi

  if ! chown "$instance_user":"$instance_user" "$file_path" 2> /dev/null; then
    return $EC_PERMISSION
  fi

  return 0
}

export -f __logic_set_file_ownership

# Mark module as loaded
declare -g KGSM_LOGIC_FILES_COMMON_LOADED=1
export KGSM_LOGIC_FILES_COMMON_LOADED
