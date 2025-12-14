#!/usr/bin/env bash

# KGSM Pure Logic Layer - Instance Management
#
# This module contains pure business logic functions for instance operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - 200-299: Success with event emission
# - Standard error codes: EC_INVALID_ARG, EC_BLUEPRINT_NOT_FOUND, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Generate a unique instance name for a blueprint
# Args: $1 = blueprint_name
# Returns: Echoes unique instance name, returns 0 on success
function __logic_generate_unique_instance_name() {
  local blueprint_name="$1"

  # Validate input
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # If no instance with the same name as the blueprint exists, use blueprint name
  if [[ ! -f "$INSTANCES_SOURCE_DIR/$blueprint_name/${blueprint_name}.ini" ]]; then
    echo "$blueprint_name"
    return 0
  fi

  # Generate unique name with random suffix
  local instance_name
  while :; do
    instance_name=$(tr -dc 0-9 </dev/urandom | head -c "${config_instance_suffix_length:-2}")
    instance_name="${blueprint_name}-${instance_name}"

    if [[ ! -f "$INSTANCES_SOURCE_DIR/$blueprint_name/${instance_name}.ini" ]]; then
      echo "$instance_name"
      return 0
    fi
  done
}

export -f __logic_generate_unique_instance_name

# Check if an instance config file exists
# Args: $1 = instance_name, $2 = blueprint_name
# Returns: 0 if exists, 1 if not
function __logic_instance_config_exists() {
  local instance_name="$1"
  local blueprint_name="$2"

  if [[ -z "$instance_name" || -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Append .ini if not present
  if [[ ! "$instance_name" =~ \.ini$ ]]; then
    instance_name="${instance_name}.ini"
  fi

  local instance_config_file="${INSTANCES_SOURCE_DIR}/${blueprint_name}/${instance_name}.ini"

  [[ -f "$instance_config_file" ]] && return 0 || return 1
}

export -f __logic_instance_config_exists

# Create an instance config file
# Args: $1 = instance_name, $2 = blueprint_name
# Returns: Echoes config file path, returns 0 on success or error code
function __logic_create_instance_config_file() {
  local instance_name="$1"
  local blueprint_name="$2"

  if [[ -z "$instance_name" || -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Create instance directory
  local instance_dir_path="${INSTANCES_SOURCE_DIR}/${blueprint_name}"
  if ! __create_dir "$instance_dir_path" >/dev/null 2>&1; then
    return $EC_FAILED_MKDIR
  fi

  # Create instance config file
  local instance_config_file="${instance_dir_path}/${instance_name}.ini"
  if ! __create_file "$instance_config_file" >/dev/null 2>&1; then
    return $EC_FAILED_CREATE_FILE
  fi

  echo "$instance_config_file"
  return 0
}

export -f __logic_create_instance_config_file

# Create base instance configuration
# Args: $1 = instance_config_file, $2 = instance_name, $3 = blueprint_abs_path, $4 = install_dir
# Returns: 0 on success, error code on failure
function __logic_create_base_instance() {
  local instance_config_file="$1"
  local instance_name="$2"
  local blueprint_abs_path="$3"
  local install_dir="$4"

  if [[ -z "$instance_config_file" || -z "$instance_name" || -z "$blueprint_abs_path" || -z "$install_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  # Source the blueprint file for native instances
  if [[ "$blueprint_abs_path" == *.bp ]]; then
    if ! __source_blueprint "$blueprint_abs_path" >/dev/null 2>&1; then
      return $EC_FAILED_SOURCE
    fi
  fi

  # Set instance variables
  export instance_name=$instance_name
  export instance_blueprint_file=$blueprint_abs_path
  export instance_working_dir="${install_dir}/${instance_name}"

  # shellcheck disable=SC2155
  export instance_install_datetime="$(date +"%Y-%m-%dT%H:%M:%S")"
  export instance_version_file="${instance_working_dir}/.${instance_name}.version"
  export instance_lifecycle_manager="standalone"
  export instance_manage_file="${instance_working_dir}/${instance_name}.manage.sh"
  export instance_auto_update_before_start="${config_instance_auto_update_before_start:-false}"

  # Process management files
  export instance_pid_file="${instance_working_dir}/.${instance_name}.pid"
  export instance_socket_file="${instance_working_dir}/.${instance_name}.sock"
  export instance_log_file="${instance_working_dir}/${instance_name}.log"
  export instance_port_forwarding_state_file="${instance_working_dir}/.${instance_name}.upnp_enabled"

  export instance_startup_success_regex="${blueprint_startup_success_regex:-}"

  export instance_install_subdir
  instance_install_subdir=$(grep "executable_subdirectory=" <"$blueprint_abs_path" | cut -d "=" -f2 | tr -d '"')

  export instance_launch_dir="${instance_working_dir}/install"
  if [[ -n "$instance_install_subdir" ]]; then
    instance_launch_dir="${instance_launch_dir}/${instance_install_subdir}"
  fi

  export instance_ports="${blueprint_ports:-}"
  export instance_stop_command="${blueprint_stop_command:-}"
  export instance_save_command="${blueprint_save_command:-}"
  export instance_platform="${blueprint_platform:-linux}"
  export instance_level_name="${blueprint_level_name:-default}"
  export instance_steam_app_id="${blueprint_steam_app_id:-0}"
  export instance_steamcmd_arguments="${blueprint_steamcmd_arguments:-}"
  export instance_is_steam_account_required="${blueprint_is_steam_account_required:-false}"

  export instance_save_command_timeout_seconds="${config_instance_save_command_timeout_seconds:-5}"
  export instance_stop_command_timeout_seconds="${config_instance_stop_command_timeout_seconds:-30}"
  export instance_compress_backups="${config_enable_backup_compression:-false}"
  export instance_enable_port_forwarding="${config_instance_enable_port_forwarding:-false}"

  local instance_executable_file

  # The executable file needs "./" appended to it if it's not a global bin
  # like java, python, wine64, etc.
  case "${blueprint_executable_file:-}" in
  java | python | wine64 | wine32 | wine | mono | mono64 | mono-wine | mono-wine64 | mono-wine32 | mono-wine-wine64 | mono-wine-wine32 | mono-wine-wine)
    instance_executable_file="${blueprint_executable_file}"
    ;;
  *)
    instance_executable_file="./${blueprint_executable_file}"
    ;;
  esac
  export instance_executable_file
  export instance_executable_arguments="${blueprint_executable_arguments:-}"

  # Some variables need to be extracted and parsed from the blueprint file
  # but because of the way container based blueprints are set up, we need
  # different logic for native and container instances.

  if [[ "$blueprint_abs_path" == *.bp ]]; then

    # Native instance
    instance_runtime="native"
    instance_compose_file=""

    instance_upnp_ports=()
    if [[ -n "${blueprint_ports:-}" ]]; then
      if ! output=$(__parse_ufw_to_upnp_ports "$blueprint_ports") || ! read -ra instance_upnp_ports <<<"$output"; then
        export instance_enable_port_forwarding="false"
      fi
    fi

  elif
    [[ "$blueprint_abs_path" == *.docker-compose.yml ]] || [[ "$blueprint_abs_path" == *.yaml ]]
  then

    # Container instance
    instance_runtime="container"
    instance_compose_file="${instance_working_dir}/${instance_name}.docker-compose.yml"

    local blueprint_parsed_ports
    if ! blueprint_parsed_ports=$(__parse_docker_compose_to_ufw_ports "$blueprint_abs_path"); then
      return $EC_INVALID_ARG
    fi

    export instance_ports="$blueprint_parsed_ports"

    instance_upnp_ports=()
    if [[ -n "${blueprint_parsed_ports:-}" ]]; then
      if ! output=$(__parse_ufw_to_upnp_ports "$blueprint_parsed_ports") || ! read -ra instance_upnp_ports <<<"$output"; then
        export instance_enable_port_forwarding="false"
      fi
    fi

  else
    return $EC_INVALID_BLUEPRINT
  fi

  export instance_runtime
  export instance_compose_file
  export instance_upnp_ports

  # Get template
  local instance_config_file_template
  if ! instance_config_file_template=$(__find_template instance.tp); then
    return $EC_FILE_NOT_FOUND
  fi

  # Generate config from template
  if ! eval "cat <<EOF
$(<"$instance_config_file_template")
EOF
" >"$instance_config_file" 2>/dev/null; then
    return $EC_FAILED_TEMPLATE
  fi

  return 0
}

export -f __logic_create_base_instance

# Create a complete instance
# Args: $1 = blueprint, $2 = install_dir, $3 = identifier (optional)
# Returns: Echoes instance_name on success (EC_SUCCESS_INSTANCE_CREATED), error code on failure
function __logic_create_instance() {
  local blueprint=$1
  local install_dir=$2
  local identifier=${3:-}

  # Validate blueprint
  if ! validate_blueprint "$blueprint" >/dev/null 2>&1; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Validate install directory
  if [[ -n "$install_dir" ]]; then
    if ! validate_directory_exists "$install_dir" "install directory" >/dev/null 2>&1; then
      return $EC_FILE_NOT_FOUND
    fi
    if ! validate_directory_writable "$install_dir" "install directory" >/dev/null 2>&1; then
      return $EC_PERMISSION
    fi
  fi

  # Get blueprint path
  local blueprint_abs_path
  if ! blueprint_abs_path="$(__find_blueprint "$blueprint")"; then
    return $EC_FILE_NOT_FOUND
  fi

  # Extract blueprint name
  local blueprint_name
  blueprint_name="$(__extract_blueprint_name "$blueprint_abs_path")"

  # Generate or validate instance name
  local instance_name
  if [[ -z "$identifier" ]]; then
    instance_name="$(__logic_generate_unique_instance_name "$blueprint_name")"
  else
    instance_name="$identifier"
    # Check if instance already exists
    if __logic_instance_config_exists "$instance_name" "$blueprint_name"; then
      return $EC_INVALID_INSTANCE
    fi
  fi

  # Create instance config file
  local instance_config_file
  if ! instance_config_file="$(__logic_create_instance_config_file "$instance_name" "$blueprint_name")"; then
    return $?
  fi

  # Create base instance configuration
  if ! __logic_create_base_instance "$instance_config_file" "$instance_name" "$blueprint_abs_path" "$install_dir"; then
    return $?
  fi

  # Success - echo instance name for caller
  echo "$instance_name"
  return $EC_SUCCESS_INSTANCE_CREATED
}

export -f __logic_create_instance

# Remove an instance configuration
# Args: $1 = instance_name
# Returns: EC_SUCCESS_INSTANCE_REMOVED on success, error code on failure
function __logic_remove_instance() {
  local instance=$1

  if [[ -z "$instance" ]]; then
    return $EC_INVALID_ARG
  fi

  # Find instance config symlink
  local instance_config_symlink
  if ! instance_config_symlink=$(__find_instance_config "$instance"); then
    return $EC_NOT_FOUND
  fi

  # Extract blueprint name from symlink path
  local blueprint_name
  blueprint_name="$(basename "$(dirname "$instance_config_symlink")")"

  # Remove the symlink
  if ! rm "$instance_config_symlink" 2>/dev/null; then
    return $EC_FAILED_RM
  fi

  # Remove directory if empty
  local instances_dir="${INSTANCES_SOURCE_DIR}/${blueprint_name}"
  if [[ -d "$instances_dir" ]] && [[ -z "$(ls -A "$instances_dir" 2>/dev/null)" ]]; then
    rmdir "$instances_dir" 2>/dev/null || true  # Don't fail if this fails
  fi

  return $EC_SUCCESS_INSTANCE_REMOVED
}

export -f __logic_remove_instance

# Get list of instance names (optionally filtered by blueprint)
# Args: $1 = blueprint_name (optional)
# Returns: Echoes newline-separated list of instance names, returns 0
function __logic_get_instances() {
  local blueprint=${1:-}

  shopt -s extglob nullglob

  local -a instances=()
  if [[ -z "$blueprint" ]]; then
    instances=("$INSTANCES_SOURCE_DIR"/**/*.ini)
  else
    instances=("$INSTANCES_SOURCE_DIR/$blueprint"/*.ini)
  fi

  # Extract just the instance names (no path, no extension)
  for instance_path in "${instances[@]}"; do
    local filename
    filename="$(basename "$instance_path")"
    echo "${filename%.ini}"
  done

  return 0
}

export -f __logic_get_instances

# Get list of instance config file paths (optionally filtered by blueprint)
# Args: $1 = blueprint_name (optional)
# Returns: Echoes newline-separated list of instance config paths, returns 0
function __logic_get_instance_paths() {
  local blueprint=${1:-}

  shopt -s extglob nullglob

  local -a instances=()
  if [[ -z "$blueprint" ]]; then
    instances=("$INSTANCES_SOURCE_DIR"/**/*.ini)
  else
    instances=("$INSTANCES_SOURCE_DIR/$blueprint"/*.ini)
  fi

  # Echo full paths
  printf '%s\n' "${instances[@]}"

  return 0
}

export -f __logic_get_instance_paths

# Mark module as loaded
export KGSM_LOGIC_INSTANCES_LOADED=1
