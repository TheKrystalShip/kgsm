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

if [[ -n "${KGSM_LOGIC_INSTANCES_LOADED}" ]]; then
  return 0
fi

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
  if [[ ! -f "$KGSM_INSTANCES_DIR/${blueprint_name}/${blueprint_name}/${blueprint_name}.config.ini" ]]; then
    echo "$blueprint_name"
    return 0
  fi

  # Generate unique name with random suffix
  local _instance_name
  while :; do
    _instance_name=$(tr -dc 0-9 </dev/urandom | head -c "${config_instance_suffix_length:-2}")
    _instance_name="${blueprint_name}-${_instance_name}"

    if [[ ! -f "$KGSM_INSTANCES_DIR/$blueprint_name/${_instance_name}/${_instance_name}.config.ini" ]]; then
      echo "$_instance_name"
      return 0
    fi
  done
}

export -f __logic_generate_unique_instance_name

# Check if an instance config file exists
# Args: $1 = _instance_name, $2 = blueprint_name
# Returns: 0 if exists, 1 if not
function __logic_instance_config_exists() {
  local _instance_name="$1"
  local blueprint_name="$2"

  if [[ -z "$_instance_name" || -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -f "${KGSM_INSTANCES_DIR}/${blueprint_name}/${_instance_name}/${_instance_name}.config.ini" ]]; then
    return 0
  fi

  return 1
}

export -f __logic_instance_config_exists

# Create an instance config file
# Args: $1 = _instance_name, $2 = blueprint_name
# Returns: Echoes config file path, returns 0 on success or error code
function __logic_create_instance_config_file() {
  local _instance_name="$1"
  local blueprint_name="$2"

  if [[ -z "$_instance_name" || -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # The instance directory at $KGSM_INSTANCES_DIR/$blueprint_name/$instance_name
  # should already exist as a symlink to the actual working directory
  local instance_dir_path="${KGSM_INSTANCES_DIR}/${blueprint_name}/${_instance_name}"

  # Verify the instance directory exists (either as directory or symlink)
  if [[ ! -e "$instance_dir_path" ]]; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  # Create instance config file inside the instance directory
  # (which resolves through symlink to the actual working directory)
  local instance_config_file="${instance_dir_path}/${_instance_name}.config.ini"
  if ! __create_file "$instance_config_file" >/dev/null 2>&1; then
    return $EC_FAILED_TOUCH
  fi

  echo "$instance_config_file"
  return 0
}

export -f __logic_create_instance_config_file

# Create base instance configuration
# Args: $1 = instance_config_file, $2 = _instance_name, $3 = blueprint_abs_path, $4 = install_dir
# Returns: 0 on success, error code on failure
function __logic_create_base_instance() {
  local instance_config_file="$1"
  local _instance_name="$2"
  local blueprint_abs_path="$3"
  local install_dir="$4"

  if [[ -z "$instance_config_file" || -z "$_instance_name" || -z "$blueprint_abs_path" || -z "$install_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  # Read the unified blueprint (yq-backed). Populates blueprint_* for both
  # runtimes, including blueprint_runtime and — for containers — the UFW
  # blueprint_ports derived from the embedded compose.
  if ! __source_blueprint "$blueprint_abs_path" >/dev/null 2>&1; then
    return $EC_FAILED_SOURCE
  fi

  # Set instance variables
  export _instance_name=$_instance_name
  export instance_blueprint_file=$blueprint_abs_path

  local instance_blueprint_name
  instance_blueprint_name="$(__extract_blueprint_name "$blueprint_abs_path")"
  export instance_working_dir="${install_dir}/${instance_blueprint_name}/${_instance_name}"

  # shellcheck disable=SC2155
  export instance_install_datetime="$(date +"%Y-%m-%dT%H:%M:%S")"
  export instance_version_file="${instance_working_dir}/.${_instance_name}.version"
  export instance_manage_file="${instance_working_dir}/${_instance_name}.manage.sh"
  export instance_auto_update_before_start="${config_instance_auto_update_before_start:-false}"

  # Process management files
  export instance_pid_file="${instance_working_dir}/.${_instance_name}.pid"
  export instance_socket_file="${instance_working_dir}/.${_instance_name}.sock"
  export instance_log_file="${instance_working_dir}/${_instance_name}.log"
  export instance_port_forwarding_state_file="${instance_working_dir}/.${_instance_name}.upnp_enabled"

  export instance_startup_success_regex="${blueprint_startup_success_regex:-}"

  export instance_install_subdir
  instance_install_subdir="${blueprint_executable_subdirectory:-}"

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

  # Runtime is now an explicit blueprint field, not inferred from the extension.
  # blueprint_ports already holds the correct UFW spec for both runtimes (the
  # native `ports` field, or the compose-derived ports for containers).
  if [[ "${blueprint_runtime:-}" == "native" ]]; then

    instance_runtime="native"
    instance_compose_file=""

    instance_upnp_ports=()
    if [[ -n "${blueprint_ports:-}" ]]; then
      if ! output=$(__parse_ufw_to_upnp_ports "$blueprint_ports") || ! read -ra instance_upnp_ports <<<"$output"; then
        export instance_enable_port_forwarding="false"
      fi
    fi

  elif [[ "${blueprint_runtime:-}" == "container" ]]; then

    instance_runtime="container"
    instance_compose_file="${instance_working_dir}/${_instance_name}.docker-compose.yml"

    instance_upnp_ports=()
    if [[ -n "${blueprint_ports:-}" ]]; then
      if ! output=$(__parse_ufw_to_upnp_ports "$blueprint_ports") || ! read -ra instance_upnp_ports <<<"$output"; then
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
# Returns: Echoes _instance_name on success (EC_SUCCESS_INSTANCE_CREATED), error code on failure
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
      return $EC_DIRECTORY_NOT_FOUND
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
  local _instance_name
  if [[ -z "$identifier" ]]; then
    _instance_name="$(__logic_generate_unique_instance_name "$blueprint_name")"
  else
    _instance_name="$identifier"
    # Check if instance already exists
    if __logic_instance_config_exists "$_instance_name" "$blueprint_name"; then
      return $EC_INVALID_INSTANCE
    fi
  fi

  # Create instance config file
  local instance_config_file
  instance_config_file="$(__logic_create_instance_config_file "$_instance_name" "$blueprint_name" "$install_dir")"
  exit_code=$?

  if [[ $exit_code -ne 0 || -z "$instance_config_file" ]]; then
    return $exit_code
  fi

  # Create base instance configuration
  if ! __logic_create_base_instance "$instance_config_file" "$_instance_name" "$blueprint_abs_path" "$install_dir"; then
    return $?
  fi

  # Success - echo instance name for caller
  echo "$_instance_name"
  return $EC_SUCCESS_INSTANCE_CREATED
}

export -f __logic_create_instance

# Remove an instance configuration
# Args: $1 = _instance_name
# Returns: EC_SUCCESS_INSTANCE_REMOVED on success, error code on failure
function __logic_remove_instance() {
  local instance=$1

  if [[ -z "$instance" ]]; then
    return $EC_INVALID_ARG
  fi

  # Find instance config file (inside the symlinked directory)
  local instance_config_file
  if ! instance_config_file=$(__find_instance_config "$instance"); then
    return $EC_NOT_FOUND
  fi

  # Extract the directory symlink path (parent of config file)
  local instance_symlink_dir
  instance_symlink_dir="$(dirname "$instance_config_file")"

  # Verify it's actually a symlink
  if [[ ! -L "$instance_symlink_dir" ]]; then
    return $EC_INVALID_INSTANCE
  fi

  # Extract blueprint name from symlink path
  local blueprint_name
  blueprint_name="$(basename "$(dirname "$instance_symlink_dir")")"

  # Remove the directory symlink
  if ! rm "$instance_symlink_dir" 2>/dev/null; then
    return $EC_FAILED_RM
  fi

  # Remove blueprint directory if empty
  # The directory will be a symlink, expect to be broken after removing the
  # instance, so check if it's a symlink or empty directory before removing.
  local instances_dir="${KGSM_INSTANCES_DIR}/${blueprint_name}"

  # Broken symlink means safe to remove
  if [[ ! -e "$instances_dir" ]]; then
    rm "$instances_dir" 2>/dev/null || true
  # If it's a directory, only remove if empty
  elif [[ -d "$instances_dir" && -z "$(ls -A "$instances_dir")" ]]; then
    rmdir "$instances_dir" 2>/dev/null || true
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

  local -a instance_dirs=()
  if [[ -z "$blueprint" ]]; then
    # Find all directory symlinks at depth 2 (blueprint/instance)
    instance_dirs=("$KGSM_INSTANCES_DIR"/*/*/)
  else
    instance_dirs=("$KGSM_INSTANCES_DIR/$blueprint"/*/)
  fi

  # Extract just the instance names (basename of directory)
  for instance_dir in "${instance_dirs[@]}"; do
    # Remove trailing slash
    instance_dir="${instance_dir%/}"
    # Check if it's a symlink (skip regular directories)
    if [[ -L "$instance_dir" ]]; then
      echo "$(basename "$instance_dir")"
    fi
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

  local -a instance_dirs=()
  if [[ -z "$blueprint" ]]; then
    instance_dirs=("$KGSM_INSTANCES_DIR"/*/*/)
  else
    instance_dirs=("$KGSM_INSTANCES_DIR/$blueprint"/*/)
  fi

  # Echo full paths to config files inside symlinked directories
  for instance_dir in "${instance_dirs[@]}"; do
    # Remove trailing slash
    instance_dir="${instance_dir%/}"
    # Check if it's a symlink (skip regular directories)
    if [[ -L "$instance_dir" ]]; then
      local instance_name="$(basename "$instance_dir")"
      local config_file="${instance_dir}/${instance_name}.config.ini"
      # Only output if config file exists
      if [[ -f "$config_file" ]]; then
        echo "$config_file"
      fi
    fi
  done

  return 0
}

export -f __logic_get_instance_paths

# Determine whether a key is unsafe to set through the instance config setter.
# Args: $1 = key
# Returns: 0 if the key is protected (must not be set), 1 otherwise.
#
# Three classes are refused:
#   - identity/structural keys, where a raw edit corrupts the instance;
#   - the filesystem paths KGSM owns and manages (every *_dir / *_file, plus
#     executable_subdirectory);
#   - the side-effecting toggles, which have dedicated enable/disable flows
#     (`kgsm files <firewall|upnp|symlink> enable|disable <instance>`) — writing the
#     flag alone would desync KGSM from the actual firewall/UPnP/symlink state.
# Everything else (auto_update, executable_arguments, level_name, stop_command,
# the *_timeout_seconds values, startup_success_regex, …) is a plain runtime
# value that KGSM simply re-reads, and is therefore settable.
function __is_protected_instance_config_key() {
  local key="$1"

  case "$key" in
    name | blueprint_file | runtime | platform | install_datetime | \
      is_steam_account_required | steam_app_id | ports | upnp_ports)
      return 0
      ;;
    *_dir | *_file | executable_subdirectory)
      return 0
      ;;
    enable_firewall_management | enable_port_forwarding | enable_command_shortcuts)
      return 0
      ;;
  esac

  return 1
}

export -f __is_protected_instance_config_key

# Set a single key=value in an instance's .config.ini.
# Args: $1 = instance_name, $2 = key, $3 = value (may be the empty string)
# Returns: 0 on success (no event), EC_* on failure.
#
# The value is written as key="value" (quoted) to match the format KGSM's own
# parsers expect (__source_with_prefix / the management script's
# __source_instance_config), and is handed to awk through the environment rather
# than via -v so that backslashes and other escapes in the value — e.g. a
# startup_success_regex — are written verbatim instead of being interpreted by
# awk's -v assignment processing.
function __set_instance_config_value() {
  local _instance_name="$1"
  local key="$2"
  local value="$3"

  if [[ -z "$_instance_name" || -z "$key" ]]; then
    return $EC_INVALID_ARG
  fi

  # The key must be a valid identifier. The management script refuses to source
  # a config containing any other key shape, so writing one would brick the
  # instance — reject it up front.
  if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    return $EC_INVALID_ARG
  fi

  # Refuse keys that are unsafe to set directly.
  if __is_protected_instance_config_key "$key"; then
    return $EC_INVALID_ARG
  fi

  local config_file
  config_file="$(__find_instance_config "$_instance_name")"
  if [[ -z "$config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # The instance directory is a symlink to the working dir; resolve it so the
  # write lands on the real file and the temp file shares its filesystem.
  local target_file="$config_file"
  if [[ -L "$config_file" ]]; then
    target_file="$(readlink -f "$config_file")"
  fi

  # Write to a temp file in the SAME directory so the final mv is an atomic,
  # same-filesystem rename, and copy the original's permissions onto it (mktemp
  # creates 0600, which would otherwise regress the config's mode).
  local tmp_file
  tmp_file="$(mktemp "${target_file}.XXXXXX")" || return $EC_FAILED_TOUCH
  chmod --reference="$target_file" "$tmp_file" 2>/dev/null || true

  if ! KGSM_CONFIG_SET_VALUE="$value" awk -v key="$key" '
    BEGIN { value = ENVIRON["KGSM_CONFIG_SET_VALUE"]; found = 0 }
    $0 ~ ("^" key "[ \t]*=") {
      print key "=\"" value "\""
      found = 1
      next
    }
    { print }
    END { if (!found) print key "=\"" value "\"" }
  ' "$target_file" > "$tmp_file"; then
    rm -f "$tmp_file"
    return $EC_FAILED_SED
  fi

  if ! mv "$tmp_file" "$target_file"; then
    rm -f "$tmp_file"
    return $EC_FAILED_MV
  fi

  return 0
}

export -f __set_instance_config_value

# Mark module as loaded
declare -g KGSM_LOGIC_INSTANCES_LOADED=1
export KGSM_LOGIC_INSTANCES_LOADED
