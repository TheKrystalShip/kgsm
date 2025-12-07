#!/usr/bin/env bash

# Disabling SC2086 globally
# shellcheck disable=SC2086

# Check for KGSM_ROOT
if [[ -z "$KGSM_ROOT" ]]; then
  # Absolute path to this script file
  SELF_PATH="$(dirname "$(readlink -f "$0")")"
  echo "$SELF_PATH"
  while [[ "$SELF_PATH" != "/" ]]; do
    [[ -f "$SELF_PATH/kgsm.sh" ]] && KGSM_ROOT="$SELF_PATH" && break
    SELF_PATH="$(dirname "$SELF_PATH")"
  done

  if [[ -z "$KGSM_ROOT" ]]; then
    echo "${0##*/} ERROR: Could not locate kgsm.sh. Ensure the directory structure is intact." && exit 1
  fi

  export KGSM_ROOT
fi

export CONFIG_FILE="$KGSM_ROOT/config.ini"
export DEFAULT_CONFIG_FILE="$KGSM_ROOT/config.default.ini"
export MERGED_CONFIG_FILE="$KGSM_ROOT/config.merged.ini"

# Avoid reloading config if it's already been loaded once
if [[ -z "$KGSM_CONFIG_LOADED" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
      cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
      echo "${0##*/} WARNING: config.ini not found, created new file" >&2
      echo "${0##*/} INFO: Please ensure configuration is correct before running the script again" >&2
      exit 0
    else
      echo "${0##*/} ERROR: Could not find config.default.ini, install might be broken" >&2
      exit 1
    fi
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    # Ignore comment lines and empty lines
    if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]]; then continue; fi
    # Parse key=value and set each config with a prefix globally and export it
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      declare -g "config_${key}=${value}"
      export "config_${key}"
    fi
  done <"$CONFIG_FILE"

  export KGSM_CONFIG_LOADED=1
fi

function __merge_user_config_with_default() {

  backup_file="${CONFIG_FILE}.$(get_version).bak"

  __print_info "Updating ${CONFIG_FILE} ..."

  # Back up existing config
  cp "$CONFIG_FILE" "${backup_file}"

  # Start with an empty merged file
  touch "$MERGED_CONFIG_FILE"

  # Temporary variables for holding block content
  block=""
  varname=""

  # Read the default config line by line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      # Process the block when we reach an empty line
      varname=$(echo "$block" | grep -oP '^[^#=\n]+(?==)')

      if [[ -n "$varname" ]]; then
        # Check if the variable exists in user config
        user_value=$(grep -m 1 "^$varname=" "$CONFIG_FILE")

        if [[ -n "$user_value" ]]; then
          # Output the commented block only if it's not already commented
          echo "$block" | sed '/^#/! s/^/# /' >>"$MERGED_CONFIG_FILE"
          echo "$user_value" >>"$MERGED_CONFIG_FILE"
        else
          # Use the block as is
          echo "$block" >>"$MERGED_CONFIG_FILE"
        fi
      else
        # No variable in the block, just copy it
        echo "$block" >>"$MERGED_CONFIG_FILE"
      fi

      # Append a newline after processing each block
      echo >>"$MERGED_CONFIG_FILE"

      # Reset the block
      block=""
    else
      # Accumulate lines into the block
      block+="$line"$'\n'
    fi
  done <"$DEFAULT_CONFIG_FILE"

  # Handle the last block (if file does not end with a newline)
  if [[ -n "$block" ]]; then
    varname=$(echo "$block" | grep -oP '^[^#=\n]+(?==)')

    if [[ -n "$varname" ]]; then
      user_value=$(grep -m 1 "^$varname=" "$CONFIG_FILE")

      if [[ -n "$user_value" ]]; then
        echo "$block" | sed '/^#/! s/^/# /' >>"$MERGED_CONFIG_FILE"
        echo "$user_value" >>"$MERGED_CONFIG_FILE"
      else
        echo "$block" >>"$MERGED_CONFIG_FILE"
      fi
    else
      echo "$block" >>"$MERGED_CONFIG_FILE"
    fi
  fi

  mv "$MERGED_CONFIG_FILE" "$CONFIG_FILE"

  __print_success "Configuration update completed. Backup saved as ${backup_file}."

  __print_info "Please check ${CONFIG_FILE} for modified/new options"

  # Global error trap system removed - errors handled explicitly
}

export -f __merge_user_config_with_default

# Function to add or update a config key in an instance config file
function __add_or_update_config() {
  local config_file="$1"
  local key="$2"
  local value="$3"
  local after_key="${4:-}"

  if [[ -z "$config_file" ]]; then
    __print_error "Config file must be provided."
    return $EC_INVALID_ARG
  fi

  if [[ -z "$key" ]]; then
    __print_error "Key must be provided."
    return $EC_INVALID_ARG
  fi

  # We don't check for value because it can be explicitly set to ""

  # Check if the config file exists
  if [[ ! -f "$config_file" ]]; then
    __print_error "Config file '$config_file' does not exist."
    return $EC_FILE_NOT_FOUND
  fi

  # Resolve symlinks to preserve bidirectional updates
  local target_file="$config_file"
  if [[ -L "$config_file" ]]; then
    target_file="$(readlink -f "$config_file")"
  fi

  # Check if the key already exists in the config file
  if grep -q "^$key=" "$target_file"; then
    # If it exists, modify in-place on the target file
    if ! sed -i "/^$key=/c$key=$value" "$target_file" >/dev/null; then
      __print_error "Failed to update key '$key' in '$target_file'."
      return $EC_FAILED_SED
    fi
  else
    # If it doesn't exist, append after the specified key or at the end
    if [[ -n "$after_key" ]] && grep -q "^$after_key=" "$target_file"; then
      sed -i "/^$after_key=/a$key=$value" "$target_file"
    else
      echo "$key=$value" >>"$target_file"
    fi
  fi
}

export -f __add_or_update_config

function __remove_config() {
  local config_file="$1"
  local key="$2"

  # Check if the key and config file are provided
  if [[ -z "$key" || -z "$config_file" ]]; then
    __print_error "Invalid arguments provided to __remove_config_key."
    return $EC_INVALID_ARG
  fi

  # Check if the config file exists
  if [[ ! -f "$config_file" ]]; then
    __print_error "Config file '$config_file' does not exist."
    return $EC_FILE_NOT_FOUND
  fi

  # Resolve symlinks to preserve bidirectional updates
  local target_file="$config_file"
  if [[ -L "$config_file" ]]; then
    target_file="$(readlink -f "$config_file")"
  fi

  # Check if the file is readable
  if [[ ! -r "$target_file" ]]; then
    __print_error "Config file '$target_file' is not readable."
    return $EC_PERMISSION
  fi

  # Check if the file is writable
  if [[ ! -w "$target_file" ]]; then
    __print_error "Config file '$target_file' is not writable."
    return $EC_PERMISSION
  fi

  # Check if the key exists in the config file
  if ! grep -q "^$key=" "$target_file"; then
    __print_error "Key '$key' does not exist in '$target_file'."
    return $EC_KEY_NOT_FOUND
  fi

  # Remove the key from the config file
  if ! sed -i "/^$key=/d" "$target_file" >/dev/null; then
    __print_error "Failed to remove key '$key' from '$target_file'."
    return $EC_FAILED_SED
  fi

  return 0
}

export -f __remove_config

# Extract the value from a config file, given a key and a path to the config file
function __get_config_value() {
  local config_file="$1"
  local key="$2"

  # Verify that the config file and key are provided
  if [[ -z "$config_file" ]]; then
    __print_error "Config file must be provided to extract value."
    return $EC_INVALID_ARG
  fi
  if [[ -z "$key" ]]; then
    __print_error "Key must be provided to extract value."
    return $EC_INVALID_ARG
  fi

  # Check if the config file exists
  if [[ ! -f "$config_file" ]]; then
    __print_error "Config file '$config_file' does not exist."
    return $EC_FILE_NOT_FOUND
  fi

  # Resolve symlinks to preserve bidirectional updates
  local target_file="$config_file"
  if [[ -L "$config_file" ]]; then
    target_file="$(readlink -f "$config_file")"
  fi

  # Extract the value using grep and cut
  local value
  value=$(grep -m 1 "^$key=" "$target_file" | cut -d '=' -f2 | tr -d '"')

  # Check if the key was found
  if [[ -z "$value" ]]; then
    __print_error "Key '$key' not found in '$target_file'."
    return $EC_KEY_NOT_FOUND
  fi

  echo "$value"
}

export -f __get_config_value

# ============================================================================
# CONFIG VALIDATION FUNCTIONS
# ============================================================================

# Validate if a config key exists in the default config
function __validate_config_key() {
  local key="$1"

  if [[ -z "$key" ]]; then
    __print_error "Config key must be provided."
    return $EC_INVALID_ARG
  fi

  # Check if the key exists in the default config file
  if grep -q "^$key=" "$DEFAULT_CONFIG_FILE" 2>/dev/null; then
    return 0
  else
    __print_error "Unknown configuration key: '$key'"
    __print_error "Use '--list' to see all available configuration keys"
    return $EC_KEY_NOT_FOUND
  fi
}

export -f __validate_config_key

# Validate config value based on key type
function __validate_config_value() {
  local key="$1"
  local value="$2"

  if [[ -z "$key" ]]; then
    __print_error "Config key must be provided for validation."
    return $EC_INVALID_ARG
  fi

  # Get the expected value type and constraints from the default config
  local expected_type="string"
  local min_value=""
  local max_value=""

  # Determine value type and constraints based on key patterns
  case "$key" in
  # Boolean values
  enable_* | auto_*)
    expected_type="boolean"
    ;;
  # Integer values with ranges
  instance_suffix_length)
    expected_type="integer"
    min_value="1"
    max_value="10"
    ;;
  webhook_timeout_seconds)
    expected_type="integer"
    min_value="1"
    max_value="300"
    ;;
  wget_timeout_seconds)
    expected_type="integer"
    min_value="1"
    max_value="3600"
    ;;
  webhook_retry_count)
    expected_type="integer"
    min_value="0"
    max_value="5"
    ;;
  log_max_size_kb | instance_save_command_timeout_seconds | instance_stop_command_timeout_seconds)
    expected_type="integer"
    min_value="1"
    ;;
  # URL validation
  webhook_urls)
    expected_type="url_list"
    ;;
  # String values (default)
  *)
    expected_type="string"
    ;;
  esac

  # Validate based on type
  case "$expected_type" in
  boolean)
    # Only accept exactly 'true' or 'false' (strict validation)
    if [[ "$value" != "true" && "$value" != "false" ]]; then
      __print_error "Invalid boolean value for '$key': '$value'"
      __print_error "Expected: 'true' or 'false'"
      return $EC_INVALID_ARG
    fi
    ;;
  integer)
    # Only accept positive integers (min_value >= 1)
    # First check if it's a valid positive integer
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
      __print_error "Invalid integer value for '$key': '$value'"
      __print_error "Expected: positive integer"
      return $EC_INVALID_ARG
    fi
    # Allow zero for retry count, reject for other fields
    if [[ "$key" != "webhook_retry_count" && "$value" -eq 0 ]]; then
      __print_error "Value for '$key' cannot be zero, got: $value"
      return $EC_INVALID_ARG
    fi
    # Check range constraints
    if [[ -n "$min_value" ]] && ((value < min_value)); then
      __print_error "Value for '$key' must be at least $min_value, got: $value"
      return $EC_INVALID_ARG
    fi
    if [[ -n "$max_value" ]] && ((value > max_value)); then
      __print_error "Value for '$key' must be at most $max_value, got: $value"
      return $EC_INVALID_ARG
    fi
    ;;
  url)
    # URL validation - allow empty for optional URLs
    if [[ -n "$value" ]]; then
      if ! [[ "$value" =~ ^https?://[a-zA-Z0-9.-]+[a-zA-Z0-9]+(:[0-9]+)?(/.*)?$ ]]; then
        __print_error "Invalid URL for '$key': '$value'"
        __print_error "Expected: valid HTTP or HTTPS URL"
        return $EC_INVALID_ARG
      fi
    fi
    ;;
  url_list)
    # URL list validation - allow empty for optional URLs, validate each URL in comma-separated list
    if [[ -n "$value" ]]; then
      IFS=',' read -ra url_list <<< "$value"
      for url in "${url_list[@]}"; do
        # Trim whitespace
        url=$(echo "$url" | xargs)
        if [[ -n "$url" ]]; then
          if ! [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+[a-zA-Z0-9]+(:[0-9]+)?(/.*)?$ ]]; then
            __print_error "Invalid URL in list for '$key': '$url'"
            __print_error "Expected: valid HTTP or HTTPS URL"
            return $EC_INVALID_ARG
          fi
        fi
      done
    fi
    ;;
  string)
    # For strings, check if it's not empty (unless explicitly allowed)
    if [[ -z "$value" && "$key" != "default_install_directory" && "$key" != "STEAM_USERNAME" && "$key" != "STEAM_PASSWORD" && "$key" != "webhook_urls" && "$key" != "webhook_secret" ]]; then
      __print_error "Value for '$key' cannot be empty"
      return $EC_INVALID_ARG
    fi
    ;;
  esac

  return 0
}

export -f __validate_config_value

# Get all config keys from the default config file
function __get_all_config_keys() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    __print_error "Default config file not found: $CONFIG_FILE"
    return $EC_FILE_NOT_FOUND
  fi

  # Extract all key=value pairs from the default config
  grep -E '^[^#=]+=' "$CONFIG_FILE" | cut -d'=' -f1
}

export -f __get_all_config_keys

# List all current config values
function __list_config_values() {
  local json_format="${1:-}"

  if [[ -n "$json_format" ]]; then
    # Use jq for JSON output
    local json_data=""
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue

      local value
      value=$(__get_config_value "$CONFIG_FILE" "$key" 2>/dev/null || echo "")

      # Handle different value types for JSON
      if [[ -z "$value" ]]; then
        json_data+="\"$key\": null,"
      elif [[ "$value" == "true" || "$value" == "false" ]]; then
        # Boolean values
        json_data+="\"$key\": $value,"
      elif [[ "$value" =~ ^[0-9]+$ ]]; then
        # Numeric values
        json_data+="\"$key\": $value,"
      else
        # String values - escape quotes and backslashes
        escaped_value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
        json_data+="\"$key\": \"$escaped_value\","
      fi
    done < <(__get_all_config_keys)

    # Remove trailing comma and wrap in braces, then pipe to jq for formatting
    json_data="{${json_data%,}}"
    echo "$json_data" | jq .
  else
    # Human-readable format
    echo "Current KGSM Configuration:"
    echo "============================"
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue

      local value
      value=$(__get_config_value "$CONFIG_FILE" "$key" 2>/dev/null || echo "NOT SET")
      echo "$key = $value"
    done < <(__get_all_config_keys)
  fi
}

export -f __list_config_values

# Set a config value with validation
function __set_config_value() {
  local key="$1"
  local value="$2"

  if [[ -z "$key" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate the key exists (capture exit code directly)
  __validate_config_key "$key"
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Validate the value (capture exit code directly)
  __validate_config_value "$key" "$value"
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Set the value in the config file
  __add_or_update_config "$CONFIG_FILE" "$key" "$value"
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Return success event code to signal that an event should be emitted
  return $EC_SUCCESS_CONFIG_SET
}

export -f __set_config_value

# Get a config value
function __get_config_value_safe() {
  local key="$1"

  if [[ -z "$key" ]]; then
    __print_error "Config key must be provided."
    return $EC_INVALID_ARG
  fi

  # Validate the key exists (capture exit code directly)
  __validate_config_key "$key"
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Get the value
  local value
  value=$(__get_config_value "$CONFIG_FILE" "$key")
  result=$?
  if [[ $result -eq 0 ]]; then
    echo "$value"
    return $result
  else
    return $result
  fi
}

export -f __get_config_value_safe

# Reset config to defaults
function __reset_config() {
  if [[ ! -f "$DEFAULT_CONFIG_FILE" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Create backup
  local backup_file; backup_file="${CONFIG_FILE}.$(date +%Y%m%d_%H%M%S).bak"
  cp "$CONFIG_FILE" "$backup_file"

  # Copy default config
  cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"

  # Return success event code to signal that an event should be emitted
  return $EC_SUCCESS_CONFIG_RESET
}

export -f __reset_config

# Validate current configuration
function __validate_current_config() {
  local errors=0
  local warnings=0

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue

    local value
    value=$(__get_config_value "$CONFIG_FILE" "$key" 2>/dev/null)
    result=$?

    if [[ $result -ne 0 ]]; then
      ((warnings++))
      continue
    fi

    # Validate the current value
    if ! __validate_config_value "$key" "$value"; then
      ((errors++))
    fi
  done < <(__get_all_config_keys)

  if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
    # Return success event code to signal that an event should be emitted
    return $EC_SUCCESS_CONFIG_VALIDATED
  elif [[ $errors -eq 0 ]]; then
    # Success with warnings - still return success event code
    return $EC_SUCCESS_CONFIG_VALIDATED
  else
    # Validation failed with errors
    return 1
  fi
}

# Open configuration file in editor
function __open_config_editor() {
  # Validate that CONFIG_FILE is set and exists
  if [[ -z "$CONFIG_FILE" ]]; then
    return $EC_INVALID_CONFIG
  fi

  if [[ ! -f "$CONFIG_FILE" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Check if config file is readable and writable
  if [[ ! -r "$CONFIG_FILE" ]]; then
    return $EC_PERMISSION
  fi

  if [[ ! -w "$CONFIG_FILE" ]]; then
    return $EC_PERMISSION
  fi

  # Determine editor to use (EDITOR environment variable or vim as fallback)
  local editor="${EDITOR:-vim}"

  # Check if the editor command exists
  if ! command -v "$editor" >/dev/null 2>&1; then
    # If EDITOR is set but not found, try vim
    if [[ -n "$EDITOR" ]]; then
      editor="vim"
      if ! command -v "$editor" >/dev/null 2>&1; then
        return $EC_MISSING_DEPENDENCY
      fi
    else
      return $EC_MISSING_DEPENDENCY
    fi
  fi

  # Open the config file in the editor
  "$editor" "$CONFIG_FILE"
  local editor_exit_code=$?

  # Return appropriate exit code based on editor result
  if [[ $editor_exit_code -eq 0 ]]; then
    return 0
  else
    return $EC_GENERAL
  fi
}

export -f __open_config_editor

export -f __validate_current_config
