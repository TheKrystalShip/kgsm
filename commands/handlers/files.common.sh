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

# Override injection is now handled during module assembly.
# This function is retained for backward compatibility and is a no-op.
function __logic_inject_overrides() {
  return 0
}

export -f __logic_inject_overrides

# Resolve which file to use for a given module, applying override priority.
# Non-overridable modules (00, 01, 02, 12, 13) always use the default template.
# For overridable modules (03-11): user overrides dir > system overrides dir > default.
# Args: $1 = blueprint_name, $2 = runtime (native|container), $3 = module_basename (e.g. 05-version.sh)
# Returns: absolute path to resolved module file via echo, EC_FILE_NOT_FOUND if no file found
function __resolve_module() {
  local blueprint_name="$1"
  local runtime="$2"
  local module_basename="$3"

  local default_path="${KGSM_TEMPLATES_DIR}/manage.${runtime}.d/${module_basename}"

  # Extract the numeric prefix to determine if this module is overridable
  local module_num="${module_basename%%-*}"

  # Non-overridable modules: 00, 01, 02, 12, 13
  case "$module_num" in
    00|01|02|12|13)
      if [[ ! -f "$default_path" ]]; then
        return $EC_FILE_NOT_FOUND
      fi

      echo "$default_path"
      return 0
      ;;
  esac

  # Overridable: check user dir first, then system dir, then default
  if [[ -n "$blueprint_name" ]]; then
    local user_override="${KGSM_USER_OVERRIDES_DIR}/${blueprint_name}/${module_basename}"
    local system_override="${KGSM_SYSTEM_OVERRIDES_DIR}/${blueprint_name}/${module_basename}"

    if [[ -f "$user_override" ]]; then
      echo "$user_override"
      return 0
    elif [[ -f "$system_override" ]]; then
      echo "$system_override"
      return 0
    fi
  fi

  if [[ ! -f "$default_path" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  echo "$default_path"
  return 0
}

export -f __resolve_module

# Assemble a management file by concatenating modules in sorted order, resolving
# overrides for each module before concatenation.
# Args: $1 = runtime (native|container), $2 = blueprint_name, $3 = output_file
# Returns: 0 on success, error code on failure
function __logic_assemble_management_file() {
  local runtime="$1"
  local blueprint_name="$2"
  local output_file="$3"

  if [[ -z "$runtime" || -z "$output_file" ]]; then
    return $EC_INVALID_ARG
  fi

  local module_dir
  module_dir=$(__find_manage_module_dir "$runtime") || return $EC_FILE_NOT_FOUND

  # Truncate (or create) the output file
  : >"$output_file" || return $EC_FAILED_TEMPLATE

  # Iterate modules in sorted order
  local module_file module_basename resolved
  while IFS= read -r -d '' module_file; do
    module_basename=$(basename "$module_file")

    resolved=$(__resolve_module "$blueprint_name" "$runtime" "$module_basename") || return $EC_FILE_NOT_FOUND

    cat "$resolved" >>"$output_file" || return $EC_FAILED_TEMPLATE
  done < <(find "$module_dir" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

  # Check if output file is non-empty after assembly
  if [[ ! -s "$output_file" ]]; then
    return $EC_FAILED_TEMPLATE
  fi

  return 0
}

export -f __logic_assemble_management_file

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
