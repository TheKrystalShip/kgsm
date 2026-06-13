#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOADER_LOADED:-}" ]]; then
  return 0
fi


# Locate files inside $KGSM_ROOT or a specified source directory, or
# print an error and exit with a specific error code if not found.
# Usage: __find_or_fail <file_name> [<source>]
function __find_or_fail() {
  local file_name=$1
  local source=${2:-$KGSM_ROOT}

  local file_path
  file_path="$(find -L "$source" \( -type f -o -type l \) -name "$file_name*" -print -quit)"

  if [[ -z "$file_path" ]]; then
    __print_debug "Could not find $file_name in $source"
    exit $EC_FILE_NOT_FOUND
  fi

  echo "$file_path"
}

export -f __find_or_fail

# Ensure the mikefarah/yq YAML processor (Arch package `go-yq`) is available.
# The unified `<name>.bp.yaml` blueprint format is read EXCLUSIVELY through yq, so
# it is a hard dependency for every blueprint operation. Without this guard a
# yq-less host produces silent, downstream-only failures (empty `blueprint_*`
# vars, a misleading "Invalid YAML syntax", garbled `info` JSON) instead of one
# actionable error.
#
# The check is a process-level invariant (yq either is or isn't on PATH for the
# life of the process), so the first successful verification is memoized via
# KGSM_YQ_VERIFIED — callers may invoke it liberally, including in loops, at zero
# repeat cost. A separate mikefarah-detection guard rejects the unrelated python
# `yq` (a jq wrapper) whose expression syntax differs and would corrupt output.
# Usage: __require_yq   (returns EC_MISSING_DEPENDENCY if unavailable/wrong impl)
function __require_yq() {
  [[ -n "${KGSM_YQ_VERIFIED:-}" ]] && return 0

  if ! command -v yq >/dev/null 2>&1; then
    __print_error "Required dependency 'yq' is not installed. KGSM blueprints are YAML and need mikefarah/yq (Arch package 'go-yq'; see https://github.com/mikefarah/yq)."
    return $EC_MISSING_DEPENDENCY
  fi

  if ! yq --version 2>/dev/null | grep -qi 'mikefarah'; then
    __print_error "The 'yq' on PATH is not mikefarah/yq. KGSM requires mikefarah/yq (Arch package 'go-yq'); a python 'yq' (a jq wrapper) is incompatible."
    return $EC_MISSING_DEPENDENCY
  fi

  declare -g KGSM_YQ_VERIFIED=1
  export KGSM_YQ_VERIFIED
  return 0
}

export -f __require_yq

# Locate a unified blueprint by name and return its absolute path.
# Blueprints are `<name>.bp.yaml` files in a single flat directory; the runtime
# (native|container) is a field inside the file, not a subdirectory. A user
# blueprint ($KGSM_USER_BLUEPRINTS_DIR) shadows a system blueprint
# ($KGSM_SYSTEM_BLUEPRINTS_DIR) of the same name.
# Accepts a bare name, a filename, or an absolute path (the basename is used).
# Usage: __find_blueprint <blueprint_name>
# Returns: absolute path via echo, or EC_FILE_NOT_FOUND.
function __find_blueprint() {
  local blueprint=$1

  if [[ "$blueprint" == /* ]]; then
    blueprint=$(basename "$blueprint")
  fi

  # Normalize to the canonical "<name>.bp.yaml" filename.
  local name
  name=$(__extract_blueprint_name "$blueprint")
  local filename="${name}.bp.yaml"

  # User blueprints shadow system blueprints.
  if [[ -f "${KGSM_USER_BLUEPRINTS_DIR}/${filename}" ]]; then
    echo "${KGSM_USER_BLUEPRINTS_DIR}/${filename}"
    return 0
  fi

  if [[ -f "${KGSM_SYSTEM_BLUEPRINTS_DIR}/${filename}" ]]; then
    echo "${KGSM_SYSTEM_BLUEPRINTS_DIR}/${filename}"
    return 0
  fi

  return $EC_FILE_NOT_FOUND
}

export -f __find_blueprint

function __find_core_module() {
  local library=$1
  [[ "$library" != *.sh ]] && library="${library}.sh"
  __find_or_fail "$library" "$KGSM_CORE_DIR"
}

export -f __find_core_module

# Important: this function cannot make use of __find_or_fail because we need
# an explicit "-maxdepth 1" to avoid searching subdirectories, and incorrectly
# locating a handler script with the same name as a module, which does not work.
# Usage: __find_command <module_name>
function __find_command() {
  local module=$1
  [[ "$module" != *.sh ]] && module="${module}.sh"

  local file_path
  file_path="$(find "$KGSM_COMMANDS_DIR" -maxdepth 1 \( -type f -o -type l \) -name "$module" -print -quit)"

  if [[ -z "$file_path" ]]; then
    __print_error "Could not find $module in $KGSM_COMMANDS_DIR"
    exit $EC_FILE_NOT_FOUND
  fi

  echo "$file_path"
}

export -f __find_command

function __find_command_handler() {
  local library=$1
  [[ "$library" != *.sh ]] && library="${library}.sh"
  __find_or_fail "$library" "$KGSM_HANDLERS_DIR"
}

export -f __find_command_handler

function __find_instance_config() {
  local instance=$1

  # Find config files in the instance directories (through symlinks)
  # The structure is: $KGSM_INSTANCES_DIR/<blueprint>/<instance>/<instance>.config.ini
  # where <instance> is a symlink to the actual working directory
  # Use -L to follow symbolic links during traversal
  local config_file
  config_file="$(__find_or_fail "${instance}.config.ini" "$KGSM_INSTANCES_DIR")"

  if [[ -z "$config_file" ]]; then
    __print_debug "Could not find instance config '$instance' in $KGSM_INSTANCES_DIR"
    exit $EC_FILE_NOT_FOUND
  fi

  # Verify config file exists and is readable
  if [[ ! -f "$config_file" ]]; then
    __print_error "Config file not found at '$config_file'"
    exit $EC_FILE_NOT_FOUND
  fi

  echo "$config_file"
}

export -f __find_instance_config

function __find_template() {
  local template=$1
  [[ "$template" != *.tp ]] && template="${template}.tp"
  __find_or_fail "$template" "$KGSM_TEMPLATES_DIR"
}

export -f __find_template

# Locate the manage module directory for a given runtime.
# Args: $1 = runtime (native|container)
# Returns: path to the module directory via echo, EC_FILE_NOT_FOUND if missing
function __find_manage_module_dir() {
  local runtime="$1"
  local module_dir="${KGSM_TEMPLATES_DIR}/manage.${runtime}.d"
  if [[ -d "$module_dir" ]]; then
    echo "$module_dir"
    return 0
  fi
  return $EC_FILE_NOT_FOUND
}

export -f __find_manage_module_dir

# Find the overrides file for a specific instance.
# Searches in user overrides directory first, then system overrides directory.
function __find_override() {
  local _instance_name=$1

  if [[ -z "$_instance_name" ]]; then
    __print_error "No 'instance_name' specified."
    exit $EC_INVALID_ARG
  fi

  # Locate the instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$_instance_name")

  if [[ -z "$instance_config_file" ]]; then
    __print_error "Instance config file for '$_instance_name' not found."
    exit $EC_FILE_NOT_FOUND
  fi

  # grep the instance blueprint file from the config
  local instance_blueprint_file
  instance_blueprint_file=$(grep -E '^blueprint_file\s*=' "$instance_config_file" | cut -d'=' -f2 | tr -d '"')

  if [[ -z "$instance_blueprint_file" ]]; then
    __print_error "No blueprint file specified for instance '$_instance_name'."
    exit $EC_INVALID_ARG
  fi

  # Extract the blueprint's logical name (the override-binding key). In the
  # unified format `name` is an explicit top-level field for every runtime, so
  # the old grep / container "first service name" workaround is no longer needed.
  local blueprint_name
  blueprint_name=$(yq -r '.name // ""' "$instance_blueprint_file" 2>/dev/null)

  if [[ -z "$blueprint_name" ]]; then
    __print_error "No 'name' variable found in blueprint file '$instance_blueprint_file'."
    exit $EC_INVALID_ARG
  fi

  instance_overrides_file="${blueprint_name}.overrides.sh"

  # Search order:
  # 1. User overrides directory
  # 2. System overrides directory
  local found_override=""

  if [[ -f "${KGSM_USER_OVERRIDES_DIR}/${instance_overrides_file}" ]]; then
    found_override="${KGSM_USER_OVERRIDES_DIR}/${instance_overrides_file}"
  elif [[ -f "${KGSM_SYSTEM_OVERRIDES_DIR}/${instance_overrides_file}" ]]; then
    found_override="${KGSM_SYSTEM_OVERRIDES_DIR}/${instance_overrides_file}"
  else
    # Return expected path for backwards compatibility (caller handles missing files)
    found_override="${KGSM_SYSTEM_OVERRIDES_DIR}/${instance_overrides_file}"
  fi

  echo "$found_override"
}

export -f __find_override

# Read a single yq path from a file, mapping an absent/null result to the empty
# string. Unlike `yq '... // ""'` (jq semantics, which also collapses `false`
# and would mangle boolean fields), this preserves literal `false` and `0`.
# Usage: __bp_yaml_field <file> <yq_path>
function __bp_yaml_field() {
  local value
  value=$(yq -r "$2" "$1" 2>/dev/null)
  [[ "$value" == "null" ]] && value=""
  printf '%s' "$value"
}

export -f __bp_yaml_field

# Read a unified blueprint and export its fields as `blueprint_*` globals.
# Replaces the legacy key=value sourcing: the on-disk format is YAML, read via
# yq. The exported variable set is the stable contract consumers rely on
# (blueprint_name, blueprint_runtime, and the native field family). For a
# container blueprint, blueprint_ports is DERIVED from the embedded compose and
# the native-only fields are emptied so a prior source never leaks through.
# Usage: __source_blueprint <blueprint_file>
function __source_blueprint() {
  local blueprint_file="$1"

  if [[ -z "$blueprint_file" ]]; then
    __print_error "No blueprint file specified."
    exit $EC_INVALID_ARG
  fi

  __require_yq || exit $EC_MISSING_DEPENDENCY

  local bp
  if ! bp=$(__find_blueprint "$blueprint_file"); then
    __print_error "Blueprint file '$blueprint_file' not found."
    exit $EC_FILE_NOT_FOUND
  fi

  if [[ ! -r "$bp" ]]; then
    __print_error "Blueprint file '$blueprint_file' is not readable."
    exit $EC_PERMISSION
  fi

  # Common fields (both runtimes).
  declare -g blueprint_name; blueprint_name=$(__bp_yaml_field "$bp" '.name')
  declare -g blueprint_runtime; blueprint_runtime=$(__bp_yaml_field "$bp" '.runtime')

  # Native field family — default everything empty so a container source (or a
  # re-source of a different blueprint) cannot leak stale values.
  declare -g blueprint_ports=""
  declare -g blueprint_steam_app_id=""
  declare -g blueprint_steamcmd_arguments=""
  declare -g blueprint_is_steam_account_required=""
  declare -g blueprint_platform=""
  declare -g blueprint_level_name=""
  declare -g blueprint_executable_subdirectory=""
  declare -g blueprint_executable_file=""
  declare -g blueprint_executable_arguments=""
  declare -g blueprint_stop_command=""
  declare -g blueprint_save_command=""
  declare -g blueprint_startup_success_regex=""

  if [[ "$blueprint_runtime" == "native" ]]; then
    blueprint_ports=$(__bp_yaml_field "$bp" '.native.ports')
    blueprint_steam_app_id=$(__bp_yaml_field "$bp" '.native.steam_app_id')
    blueprint_steamcmd_arguments=$(__bp_yaml_field "$bp" '.native.steamcmd_arguments')
    blueprint_is_steam_account_required=$(__bp_yaml_field "$bp" '.native.is_steam_account_required')
    blueprint_platform=$(__bp_yaml_field "$bp" '.native.platform')
    blueprint_level_name=$(__bp_yaml_field "$bp" '.native.level_name')
    blueprint_executable_subdirectory=$(__bp_yaml_field "$bp" '.native.executable_subdirectory')
    blueprint_executable_file=$(__bp_yaml_field "$bp" '.native.executable_file')
    blueprint_executable_arguments=$(__bp_yaml_field "$bp" '.native.executable_arguments')
    blueprint_stop_command=$(__bp_yaml_field "$bp" '.native.stop_command')
    blueprint_save_command=$(__bp_yaml_field "$bp" '.native.save_command')
    blueprint_startup_success_regex=$(__bp_yaml_field "$bp" '.native.startup_success_regex')
  elif [[ "$blueprint_runtime" == "container" ]]; then
    blueprint_ports=$(__derive_ufw_ports_from_compose "$bp")
  fi

  export blueprint_name blueprint_runtime blueprint_ports \
    blueprint_steam_app_id blueprint_steamcmd_arguments \
    blueprint_is_steam_account_required blueprint_platform \
    blueprint_level_name blueprint_executable_subdirectory \
    blueprint_executable_file blueprint_executable_arguments \
    blueprint_stop_command blueprint_save_command \
    blueprint_startup_success_regex
}

export -f __source_blueprint

# Source the instance config file for a specific instance.
# This function expects the _instance_name as the first argument.
# Usage: __source_instance <instance_name>
# The instance name can be either an absolute path to the instance config file
# or just the instance name.
function __source_instance() {
  local _instance_name="$1"

  if [[ -z "$_instance_name" ]]; then
    __print_error "No '_instance_name' specified."
    exit $EC_INVALID_ARG
  fi

  local instance_config_file

  # $_instance_name can be either an absolute path, or simply the instance name.
  # If it's an absolute path, we extract the name from it.
  if [[ "$_instance_name" == /* ]]; then
    # If it's an absolute path, we just use it
    instance_config_file="$_instance_name"
  else
    # Otherwise, we find the instance config file
    instance_config_file=$(__find_instance_config "$_instance_name")
  fi

  if [[ -z "$instance_config_file" ]]; then
    __print_error "Instance config file for '$_instance_name' not found."
    exit $EC_FILE_NOT_FOUND
  fi

  # Source the instance config file and prefix all variables with "instance_" if needed
  __source_with_prefix "$instance_config_file" "instance_"
}

export -f __source_instance

# Get a single value from an instance config file without sourcing all variables
# Usage: __get_instance_config_value <instance_name> <config_key>
function __get_instance_config_value() {
  local _instance_name="$1"
  local config_key="$2"

  if [[ -z "$_instance_name" || -z "$config_key" ]]; then
    __print_error "Both instance_name and config_key must be specified."
    exit $EC_INVALID_ARG
  fi

  # Find the instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$_instance_name")

  if [[ -z "$instance_config_file" ]]; then
    __print_error "Instance config file for '$_instance_name' not found."
    exit $EC_FILE_NOT_FOUND
  fi

  # Extract the specific value using grep with proper anchoring
  local value
  value=$(grep -E "^${config_key}\s*=" "$instance_config_file" 2> /dev/null | cut -d'=' -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")

  echo "$value"
}

export -f __get_instance_config_value

function __source_with_prefix() {
  local file_path="$1"
  local prefix="${2:-}"

  if [[ -z "$file_path" ]]; then
    __print_error "No file path specified."
    exit $EC_INVALID_ARG
  fi

  if [[ ! -f "$file_path" ]]; then
    __print_error "File not found: $file_path"
    exit $EC_FILE_NOT_FOUND
  fi

  mapfile -t key_value_pairs < <(grep -E '^[^#[:space:]\[].*=' "$file_path")

  for line in "${key_value_pairs[@]}"; do
    # Parse key=value and set each with a prefix globally and export it
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # Trim whitespace from key and value
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"

      # Remove quotes from value if present
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"

      declare -g "${prefix}${key}=${value}"
      export "${prefix}${key}"
    else
      # Warn about malformed lines that passed grep but failed regex parsing
      __print_warning "Skipping malformed line: $line"
    fi
  done

  unset key_value_pairs
}

export -f __source_with_prefix

declare -g KGSM_LOADER_LOADED=1
export KGSM_LOADER_LOADED
