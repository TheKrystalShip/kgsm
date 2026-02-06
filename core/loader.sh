#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOADER_LOADED:-}" ]]; then
  return 0
fi

# Blueprints (*.bp) are stored here
export BLUEPRINTS_SOURCE_DIR=$KGSM_ROOT/blueprints

export BLUEPRINTS_NATIVE_DIR=$BLUEPRINTS_SOURCE_DIR/native
export BLUEPRINTS_CONTAINER_DIR=$BLUEPRINTS_SOURCE_DIR/container

export BLUEPRINTS_NATIVE_DEFAULT_DIR=$BLUEPRINTS_NATIVE_DIR/default
export BLUEPRINTS_NATIVE_CUSTOM_DIR=$BLUEPRINTS_NATIVE_DIR/custom

export BLUEPRINTS_CONTAINER_DEFAULT_DIR=$BLUEPRINTS_CONTAINER_DIR/default
export BLUEPRINTS_CONTAINER_CUSTOM_DIR=$BLUEPRINTS_CONTAINER_DIR/custom

# Specific game server overrides ([service].overrides.sh) are stored here
export OVERRIDES_SOURCE_DIR=$KGSM_ROOT/overrides

# Templates (*.tp) are stored here
export TEMPLATES_SOURCE_DIR=$KGSM_ROOT/templates

# All other scripts (*.sh) are stored here
export COMMANDS_SOURCE_DIR=$KGSM_ROOT/commands

# Command handler scripts (*.sh) are stored here
export COMMAND_HANDLERS_SOURCE_DIR=$COMMANDS_SOURCE_DIR/handlers

# Core scripts (*.sh) are stored here
export CORE_SOURCE_DIR=$KGSM_ROOT/core

# Directory where instances and their config is stored
export INSTANCES_SOURCE_DIR=$KGSM_ROOT/instances

# Locate files inside $KGSM_ROOT or a specified source directory, or
# print an error and exit with a specific error code if not found.
# Usage: __find_or_fail <file_name> [<source>]
function __find_or_fail() {
  local file_name=$1
  local source=${2:-$KGSM_ROOT}

  local file_path
  file_path="$(find "$source" \( -type f -o -type l \) -name "$file_name" -print -quit)"

  if [[ -z "$file_path" ]]; then
    __print_error "Could not find $file_name in $source"
    exit $EC_FILE_NOT_FOUND
  fi

  echo "$file_path"
}

export -f __find_or_fail

# Function to load native, default blueprints
function __find_native_default_blueprint() {
  local blueprint=$1
  [[ "$blueprint" != *.bp ]] && blueprint="${blueprint}.bp"
  __find_or_fail "$blueprint" "$BLUEPRINTS_NATIVE_DEFAULT_DIR"
}

export -f __find_native_default_blueprint

# Function to load container, default blueprints
function __find_default_container_blueprint() {
  local blueprint=$1
  [[ "$blueprint" != *.docker-compose.yml ]] && blueprint="${blueprint}.docker-compose.yml"
  __find_or_fail "$blueprint" "$BLUEPRINTS_CONTAINER_DEFAULT_DIR"
}

export -f __find_default_container_blueprint

# Function to load default blueprints, both native and container
function __find_default_blueprint() {
  local blueprint=$1

  # First try to find a native blueprint
  local loaded_blueprint
  loaded_blueprint=$(__find_native_default_blueprint "$blueprint")

  # If not found, try to find a container blueprint
  if [[ -z "$loaded_blueprint" ]]; then
    loaded_blueprint=$(__find_default_container_blueprint "$blueprint")
  fi

  # Don't print an error if no blueprint is found, just return empty
  echo "$loaded_blueprint"
}

export -f __find_default_blueprint

# Function to load native, custom blueprints
function __find_custom_native_blueprint() {
  local blueprint=$1
  [[ "$blueprint" != *.bp ]] && blueprint="${blueprint}.bp"
  __find_or_fail "$blueprint" "$BLUEPRINTS_NATIVE_CUSTOM_DIR"
}

export -f __find_custom_native_blueprint

# Function to load container, custom blueprints
function __find_custom_container_blueprint() {
  local blueprint=$1
  [[ "$blueprint" != *.docker-compose.yml ]] && blueprint="${blueprint}.docker-compose.yml"
  __find_or_fail "$blueprint" "$BLUEPRINTS_CONTAINER_CUSTOM_DIR"
}

export -f __find_custom_container_blueprint

# Function to load custom blueprints, both native and container
function __find_custom_blueprint() {
  local blueprint=$1

  # First try to find a custom native blueprint
  local loaded_blueprint
  loaded_blueprint=$(__find_custom_native_blueprint "$blueprint")

  # If not found, try to find a custom container blueprint
  if [[ -z "$loaded_blueprint" ]]; then
    loaded_blueprint=$(__find_custom_container_blueprint "$blueprint")
  fi

  # Don't print an error if no blueprint is found, just return empty
  echo "$loaded_blueprint"
}

export -f __find_custom_blueprint

# This function needs to look in both the native blueprints directory
# and the container blueprints directory and return the first match,
# or if there is a match in each directory, return the native one.
# It will return the absolute path to the blueprint file.
# Usage: __find_blueprint <blueprint_name>
# The blueprint name can be either an absolute path or just the name.
function __find_blueprint() {
  local blueprint=$1

  # $blueprint can be either an absolute path, or simply the blueprint name.
  # If it's an absolute path, we extract the name from it.
  if [[ "$blueprint" == /* ]]; then
    # If it's an absolute path, we just use the basename
    blueprint=$(basename "$blueprint")
  fi

  # Load the blueprint file in this order:
  # 1. Custom native blueprint
  # 2. Custom container blueprint
  # 3. Default native blueprint
  # 4. Default container blueprint

  # First try to find a custom blueprint
  local loaded_blueprint
  loaded_blueprint=$(__find_custom_blueprint "$blueprint" 2> /dev/null)

  # If no custom blueprint is found, try to find the default blueprint
  if [[ -z "$loaded_blueprint" ]]; then
    loaded_blueprint=$(__find_default_blueprint "$blueprint" 2> /dev/null)
  fi

  # If no blueprint is found, we return an error code
  if [[ -z "$loaded_blueprint" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # If we found a blueprint, we return it
  echo "$loaded_blueprint"
}

export -f __find_blueprint

function __find_core_module() {
  local library=$1
  [[ "$library" != *.sh ]] && library="${library}.sh"
  __find_or_fail "$library" "$CORE_SOURCE_DIR"
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
  file_path="$(find "$COMMANDS_SOURCE_DIR" -maxdepth 1 \( -type f -o -type l \) -name "$module" -print -quit)"

  if [[ -z "$file_path" ]]; then
    __print_error "Could not find $module in $COMMANDS_SOURCE_DIR"
    exit $EC_FILE_NOT_FOUND
  fi

  echo "$file_path"
}

export -f __find_command

function __find_command_handler() {
  local library=$1
  [[ "$library" != *.sh ]] && library="${library}.sh"
  __find_or_fail "$library" "$COMMAND_HANDLERS_SOURCE_DIR"
}

export -f __find_command_handler

function __find_instance_config() {
  local instance=$1
  [[ "$instance" != *.ini ]] && instance="${instance}.ini"
  __find_or_fail "$instance" "$INSTANCES_SOURCE_DIR"
}

export -f __find_instance_config

function __find_template() {
  local template=$1
  [[ "$template" != *.tp ]] && template="${template}.tp"
  __find_or_fail "$template" "$TEMPLATES_SOURCE_DIR"
}

export -f __find_template

# Find the overrides file for a specific instance.
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

  # Extract the blueprint name from the blueprint file's "name" variable
  # This works for native blueprints, but not for container blueprints
  local blueprint_name
  blueprint_name=$(grep -E '^name\s*=' "$instance_blueprint_file" | cut -d'=' -f2 | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # For container blueprints, we need to extract the blueprint name from the first service name
  # found right after the "services:" line in the docker-compose.yml file
  # This is a workaround for the fact that the blueprint name is not stored in the blueprint file.
  if [[ "$instance_blueprint_file" == *.docker-compose.yml ]]; then
    blueprint_name=$(grep -C 1 -E '^services:' "$instance_blueprint_file" | tail -n1 | cut -d ':' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  if [[ -z "$blueprint_name" ]]; then
    __print_error "No 'name' variable found in blueprint file '$instance_blueprint_file'."
    exit $EC_INVALID_ARG
  fi

  instance_overrides_file="${blueprint_name}.overrides.sh"

  # Instead of using __find_or_fail which exits on missing files,
  # construct the expected path and let the caller handle missing files
  echo "${OVERRIDES_SOURCE_DIR}/${instance_overrides_file}"
}

export -f __find_override

# This function sources a blueprint file and prefixes all variables with "blueprint_".
# It also checks if the blueprint file exists and is readable.
# If the blueprint file is not found, it returns an error.
# Usage: __source_blueprint <blueprint_file> [<prefix>] [--force-reload]
function __source_blueprint() {
  local blueprint_file="$1"

  if [[ -z "$blueprint_file" ]]; then
    __print_error "No blueprint file specified."
    exit $EC_INVALID_ARG
  fi

  # Use the __find_blueprint function to find the blueprint file.
  # This gives the absolute path to the blueprint file.
  local blueprint_absolute_path
  if ! blueprint_absolute_path=$(__find_blueprint "$blueprint_file"); then
    __print_error "Blueprint file '$blueprint_file' not found."
    exit $EC_FILE_NOT_FOUND
  fi

  # Check if the blueprint file is readable
  if [[ ! -r "$blueprint_absolute_path" ]]; then
    __print_error "Blueprint file '$blueprint_file' is not readable."
    exit $EC_PERMISSION
  fi

  __source_with_prefix "$blueprint_absolute_path" "blueprint_"
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
