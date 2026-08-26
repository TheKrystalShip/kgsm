#!/usr/bin/env bash

# Disabling SC2086 globally
# shellcheck disable=SC2086

# Use XDG-compliant paths from core/paths.sh
export CONFIG_FILE="$KGSM_CONFIG_FILE"
export DEFAULT_CONFIG_FILE="$KGSM_DEFAULT_CONFIG_FILE"
export MERGED_CONFIG_FILE="${KGSM_CONFIG_DIR}/config.merged.ini"

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

  # Use grep to pre-filter config file, extracting only non-comment, non-whitespace lines containing '='
  # This now includes support for INI sections while maintaining backward compatibility with flat format
  # Section headers (e.g., [section]) are filtered out by excluding lines with '[' character
  # Use mapfile to read config lines into array directly to iterate over
  mapfile -t config_lines < <(grep -E '^[^#[:space:]\[].*=' "$CONFIG_FILE")

  # Parse each config line and export as global variable
  for line in "${config_lines[@]}"; do
    # Parse key=value and set each config with a prefix globally and export it
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

      declare -g "config_${key}=${value}"
      export "config_${key}"
    else
      # Warn about malformed config lines that passed grep but failed regex parsing
      __print_warning "Skipping malformed config line: $line"
    fi
  done

  unset config_lines

  export KGSM_CONFIG_LOADED=1
fi

# Create numbered backup of config file
function __create_config_backup() {
  local max_backups=10

  # Rotate existing backups (9 -> 10, 8 -> 9, ..., 0 -> 1)
  for ((i=max_backups-1; i>=0; i--)); do
    local current="${CONFIG_FILE}.${i}"
    local next="${CONFIG_FILE}.$((i+1))"

    if [[ -f "$current" ]]; then
      if [[ $i -eq $((max_backups-1)) ]]; then
        # Remove oldest backup
        rm -f "$current"
      else
        # Rotate backup
        mv "$current" "$next" 2>/dev/null || true
      fi
    fi
  done

  # Create new backup at .0
  if ! cp "$CONFIG_FILE" "${CONFIG_FILE}.0" 2>/dev/null; then
    __print_error "Failed to create config backup"
    return $EC_FAILED_BACKUP
  fi

  return 0
}

export -f __create_config_backup

# Run config migrations if schema version differs
function __run_config_migrations() {
  local from_version="$1"
  local to_version="$2"

  # If versions are the same, no migration needed
  if [[ "$from_version" -eq "$to_version" ]]; then
    return 0
  fi

  __print_info "Running config migrations from v${from_version} to v${to_version}..."

  local migrations_dir="$KGSM_ROOT/migrations/config"

  # Check if migrations directory exists
  if [[ ! -d "$migrations_dir" ]]; then
    __print_error "Migrations directory not found: $migrations_dir"
    return $EC_MIGRATION_NOT_FOUND
  fi

  # Run migrations sequentially
  for ((v=from_version; v<to_version; v++)); do
    local next=$((v+1))

    # Find migration script (pattern: *_v<from>_to_v<to>.sh)
    local migration_script
    migration_script=$(find "$migrations_dir" -type f -name "*_v${v}_to_v${next}*.sh" -print -quit 2>/dev/null)

    if [[ -z "$migration_script" ]] || [[ ! -f "$migration_script" ]]; then
      __print_error "Migration script not found for v${v} -> v${next}"
      return $EC_MIGRATION_NOT_FOUND
    fi

    __print_info "Executing migration: $(basename "$migration_script")"

    # Execute migration
    if ! bash "$migration_script" "$CONFIG_FILE"; then
      __print_error "Migration failed: $(basename "$migration_script")"
      return $EC_MIGRATION_FAILED
    fi
  done

  __print_success "All migrations completed successfully"
  return 0
}

export -f __run_config_migrations

# Parse config file and build associative array of key=value pairs
function __parse_config_to_map() {
  local config_file="$1"
  local -n key_map=$2

  # Read config file line by line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines, comments, and section headers
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^\[[^]]+\]$ ]] && continue

    # Parse key=value
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Trim whitespace from key
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"

      # Store in map (value can be empty)
      key_map["$key"]="$value"
    fi
  done < "$config_file"
}

export -f __parse_config_to_map

# Handle deprecated keys found in user config but not in default
function __handle_deprecated_keys() {
  local -n _user_map=$1
  local -n _default_map=$2
  local merged_file="$3"

  local has_deprecated=0

  # Find keys in user config not in default
  for key in "${!_user_map[@]}"; do
    # Skip schema version key
    [[ "$key" == "config_schema_version" ]] && continue

    # Presence, not emptiness: a key the default declares with an empty value is
    # still a live key, and testing its value would report it as deprecated.
    if [[ ! -v _default_map[$key] ]]; then
      # Key is deprecated - add warning section if first deprecated key
      if [[ "$has_deprecated" -eq 0 ]]; then
        cat >> "$merged_file" << 'EOF'


# ============================================================================
# DEPRECATED KEYS
# ============================================================================
# The following keys are no longer used by KGSM and have been preserved
# here for reference. They will be ignored by KGSM.
# ============================================================================

EOF
        has_deprecated=1
      fi

      # Comment out the deprecated key
      echo "# DEPRECATED: ${key}=${_user_map[$key]}" >> "$merged_file"

      __print_warning "Deprecated configuration key found: $key"
    fi
  done

  if [[ "$has_deprecated" -eq 1 ]]; then
    __print_info "Review commented-out deprecated keys in $CONFIG_FILE"
  fi

  return 0
}

export -f __handle_deprecated_keys

# Main merge function - merges user config with default config
function __merge_user_config_with_default() {
  __print_info "Merging configuration..."

  # 1. Create numbered backup
  if ! __create_config_backup; then
    __print_error "Failed to create backup"
    return $EC_FAILED_BACKUP
  fi

  # 2. Check schema versions
  local user_schema current_schema
  user_schema=$(__get_config_value "$CONFIG_FILE" "config_schema_version" 2>/dev/null || echo "0")
  current_schema=$(__get_config_value "$DEFAULT_CONFIG_FILE" "config_schema_version" 2>/dev/null || echo "1")

  # Run migrations if needed
  if [[ "$user_schema" -lt "$current_schema" ]]; then
    if ! __run_config_migrations "$user_schema" "$current_schema"; then
      __print_error "Config migration failed"
      return $EC_MIGRATION_FAILED
    fi
    # Reload user config after migration
    user_schema="$current_schema"
  fi

  # 3. Parse both configs into associative arrays
  declare -A user_keys default_keys
  __parse_config_to_map "$CONFIG_FILE" user_keys
  __parse_config_to_map "$DEFAULT_CONFIG_FILE" default_keys

  # 4. Build merged config by iterating through default config structure
  local merged_file="${CONFIG_FILE}.merged.$$"
  local current_section=""
  local in_comment_block=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Handle section headers
    if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      echo "$line" >> "$merged_file"
      continue
    fi

    # Handle empty lines
    if [[ -z "$line" ]]; then
      echo "" >> "$merged_file"
      continue
    fi

    # Handle comment lines (preserve documentation)
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      echo "$line" >> "$merged_file"
      continue
    fi

    # Handle key=value lines
    if [[ "$line" =~ ^([^=]+)= ]]; then
      local key="${BASH_REMATCH[1]}"
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"

      # Check if user has customized this key
      if [[ -n "${user_keys[$key]+isset}" ]]; then
        # Use user's value
        echo "${key}=${user_keys[$key]}" >> "$merged_file"
      else
        # Use default value (new key)
        echo "$line" >> "$merged_file"
      fi
    else
      # Copy line as-is (shouldn't reach here normally)
      echo "$line" >> "$merged_file"
    fi
  done < "$DEFAULT_CONFIG_FILE"

  # 5. Handle deprecated keys
  __handle_deprecated_keys user_keys default_keys "$merged_file"

  # 6. Atomic replace
  if ! mv "$merged_file" "$CONFIG_FILE"; then
    __print_error "Failed to replace config file"
    rm -f "$merged_file"
    return $EC_ERROR
  fi

  __print_success "Configuration merged successfully"
  __print_info "Backup saved as: ${CONFIG_FILE}.0"
  __print_info "Please review ${CONFIG_FILE} for any changes"

  return $EC_SUCCESS_CONFIG_MERGED
}

export -f __create_config_backup
export -f __run_config_migrations
export -f __parse_config_to_map
export -f __handle_deprecated_keys
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
  # Use -f2- to preserve any '=' characters that may exist in the value (e.g., URLs with query params)
  local value
  value=$(grep -m 1 "^$key=" "$target_file" | cut -d '=' -f2- | tr -d '"')

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
    if [[ -z "$value" && "$key" != "default_library" && "$key" != "STEAM_USERNAME" && "$key" != "STEAM_PASSWORD" && "$key" != "webhook_urls" && "$key" != "webhook_secret" ]]; then
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
    return $EC_ERROR
  fi
}

export -f __open_config_editor

export -f __validate_current_config
