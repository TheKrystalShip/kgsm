#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Configuration Management for Krystal Game Server Manager${END}

Manages KGSM configuration settings through command-line interface.

${UNDERLINE}Usage:${END}
  $self [command] [arguments] [options]

${UNDERLINE}Commands:${END}
  set <key=value>             Set a configuration value
  get <key>                   Get a configuration value
  list                        List all configuration values
  reset                       Reset configuration to defaults
  validate                    Validate current configuration
  merge                       Merge user config with updated defaults
  rollback [generation]       Rollback config to previous backup
  diff [generation]           Show differences from backup
  edit                        Open configuration file in editor
  help [command]              Show help information

${UNDERLINE}Options:${END}
  --json                      Output in JSON format (for list command)
  -h, --help                  Show help and exit

${UNDERLINE}Examples:${END}
  $self set enable_logging=true
  $self set instance_suffix_length=3
  $self get enable_systemd
  $self list
  $self list --json
  $self reset
  $self validate
  $self merge
  $self rollback 0
  $self diff 0
  $self edit
  $self help set

${UNDERLINE}Notes:${END}
  • All configuration changes are validated before being applied
  • Boolean values must be 'true' or 'false'
  • Integer values must be positive numbers
  • Use 'list' command to see all available configuration keys
  • Configuration is automatically backed up before changes
"
}

function show_usage_set() {
  echo -e "Usage: $self set <key=value>

  Set a configuration value.

  Arguments:
    key=value    Configuration key and value pair

  Examples:
    $self set enable_logging=true
    $self set instance_suffix_length=3
"
}

function show_usage_get() {
  echo -e "Usage: $self get <key>

  Get a configuration value.

  Arguments:
    key          Configuration key to retrieve

  Examples:
    $self get enable_logging
    $self get instance_suffix_length
"
}

function show_usage_list() {
  echo -e "Usage: $self list [--json]

  List all configuration values.

  Options:
    --json       Output in JSON format

  Examples:
    $self list
    $self list --json
"
}

function show_usage_reset() {
  echo -e "Usage: $self reset

  Reset configuration to defaults.

  Examples:
    $self reset
"
}

function show_usage_validate() {
  echo -e "Usage: $self validate

  Validate current configuration.

  Examples:
    $self validate
"
}

function show_usage_edit() {
  echo -e "Usage: $self edit

  Open configuration file in editor.

  Examples:
    $self edit
"
}

function show_usage_merge() {
  echo -e "Usage: $self merge

  Merge user configuration with updated defaults.

  This command:
    • Creates a numbered backup (.0)
    • Runs any pending schema migrations
    • Preserves user customizations
    • Adds new keys from updated default config
    • Comments out deprecated keys with warnings

  Examples:
    $self merge
"
}

function show_usage_rollback() {
  echo -e "Usage: $self rollback [generation]

  Rollback configuration to a previous backup.

  Arguments:
    generation   Backup generation number (0-9, default: 0)
                 0 = most recent, 9 = oldest

  Examples:
    $self rollback          # Rollback to most recent backup (.0)
    $self rollback 0        # Same as above
    $self rollback 2        # Rollback to third most recent (.2)
"
}

function show_usage_diff() {
  echo -e "Usage: $self diff [generation]

  Show differences between current config and backup.

  Arguments:
    generation   Backup generation number (0-9, default: 0)

  Examples:
    $self diff              # Compare with most recent backup (.0)
    $self diff 1            # Compare with second most recent (.1)
"
}

# Global variables
json_format=""

# Command handler functions that call pure logic and manage I/O
function _cmd_set() {
  local key_value=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_set
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_set
        return $EC_INVALID_ARG
        ;;
      *)
        key_value="$1"
        shift
        ;;
    esac
  done

  # Use centralized validation for key=value argument
  if ! validate_not_empty "$key_value" "KEY=VALUE argument"; then
    __print_error "Missing required argument"
    __print_error "Missing argument: KEY=VALUE. Example: set enable_logging=true"
    return $EC_MISSING_ARG
  fi

  # Parse key=value
  if [[ ! "$key_value" =~ ^([^=]+)=(.*)$ ]]; then
    __print_error "Invalid argument provided"
    __print_error "Invalid format: '$key_value'. Expected format: KEY=VALUE"
    return $EC_INVALID_ARG
  fi

  local key="${BASH_REMATCH[1]}"
  local value="${BASH_REMATCH[2]}"

  # Call pure logic function and handle result
  __set_config_value "$key" "$value"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_CONFIG_SET)
      __print_success "Configuration updated: $key=$value"
      __dispatch_event_from_exit_code "$exit_code" "system" "$key=$value"
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid argument provided"
      __print_error "Key: $key, Value: $value"
      ;;
    $EC_KEY_NOT_FOUND)
      __print_error "Configuration key not found"
      __print_error "Key: $key"
      __print_error "Use 'config.sh list' to see all available configuration keys"
      ;;
    $EC_FILE_NOT_FOUND)
      __print_error "File not found"
      __print_error "Configuration file could not be accessed"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied"
      __print_error "Cannot write to configuration file"
      ;;
    *)
      __print_error "Operation failed: set"
      __print_error "Key: $key, Value: $value"
      ;;
  esac

  return $exit_code
}

function _cmd_get() {
  local key=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_get
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_get
        return $EC_INVALID_ARG
        ;;
      *)
        key="$1"
        shift
        ;;
    esac
  done

  # Use centralized validation for key argument
  if ! validate_not_empty "$key" "KEY argument"; then
    __print_error "Missing required argument"
    __print_error "Missing argument: KEY. Example: get enable_logging"
    return $EC_MISSING_ARG
  fi

  # Call pure logic function and handle result
  local value
  value=$(__get_config_value_safe "$key")
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "$value"
  else
    case $exit_code in
      $EC_KEY_NOT_FOUND)
        __print_error "Configuration key not found"
        __print_error "Key: $key"
        __print_error "Use 'config.sh list' to see all available configuration keys"
        ;;
      $EC_FILE_NOT_FOUND)
        __print_error "File not found"
        __print_error "Configuration file could not be accessed"
        ;;
      $EC_PERMISSION)
        __print_error "Permission denied"
        __print_error "Cannot read configuration file"
        ;;
      *)
        __print_error "Operation failed: get"
        __print_error "Key: $key"
        ;;
    esac
  fi

  return $exit_code
}

function _cmd_list() {

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_list
        return 0
        ;;
      *)
        __print_error "Unknown option: $1"
        show_usage_list
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Call pure logic function and handle result
  __list_config_values "$json_format"
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    case $exit_code in
      $EC_FILE_NOT_FOUND)
        __print_error "File not found"
        __print_error "Configuration file could not be accessed"
        ;;
      $EC_PERMISSION)
        __print_error "Permission denied"
        __print_error "Cannot read configuration file"
        ;;
      $EC_MISSING_DEPENDENCY)
        __print_error "Missing required dependency"
        __print_error "JSON formatting requires jq to be installed"
        ;;
      *)
        __print_error "Operation failed: list"
        ;;
    esac
  fi

  return $exit_code
}

function _cmd_reset() {

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_reset
        return 0
        ;;
      *)
        __print_error "Unknown option: $1"
        show_usage_reset
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Call pure logic function and handle result
  __reset_config
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_CONFIG_RESET)
      __print_success "Configuration reset to defaults"
      __print_info "Backup saved with timestamp"
      __dispatch_event_from_exit_code "$exit_code" "system"
      ;;
    $EC_FILE_NOT_FOUND)
      __print_error "File not found"
      __print_error "Configuration file could not be accessed"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied"
      __print_error "Cannot write to configuration file"
      ;;
    *)
      __print_error "Operation failed: reset"
      ;;
  esac

  return $exit_code
}

function _cmd_validate() {

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_validate
        return 0
        ;;
      *)
        __print_error "Unknown option: $1"
        show_usage_validate
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Call pure logic function and handle result
  __validate_current_config
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_CONFIG_VALIDATED)
      __print_success "Configuration validation passed"
      __dispatch_event_from_exit_code "$exit_code" "system"
      ;;
    $EC_FILE_NOT_FOUND)
      __print_error "File not found"
      __print_error "Configuration file could not be accessed"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied"
      __print_error "Cannot read configuration file"
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid argument provided"
      __print_error "Configuration validation failed"
      ;;
    *)
      __print_error "Operation failed: validate"
      ;;
  esac

  return $exit_code
}

function _cmd_edit() {

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_edit
        return 0
        ;;
      *)
        __print_error "Unknown option: $1"
        show_usage_edit
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Call pure logic function and handle result
  __open_config_editor
  local exit_code=$?

  case $exit_code in
    $EC_OKAY)
      # Nothing to do
      return 0
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "EDITOR could not be used"
      __print_error "Set EDITOR variable to fix this error"
      ;;
    *)
      __print_error "Operation failed: edit"
      ;;
  esac

  return $exit_code
}

function _cmd_merge() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_merge
        return 0
        ;;
      *)
        __print_error "Unknown option: $1"
        show_usage_merge
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Call merge function from core/config.sh
  __merge_user_config_with_default
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_CONFIG_MERGED)
      __print_success "Configuration merged successfully"
      __print_info "Review $CONFIG_FILE for changes"
      __print_info "Backup saved as ${CONFIG_FILE}.0"
      ;;
    $EC_FAILED_BACKUP)
      __print_error "Failed to create backup"
      ;;
    $EC_MIGRATION_FAILED)
      __print_error "Config migration failed"
      ;;
    *)
      __print_error "Merge operation failed"
      ;;
  esac

  return $exit_code
}

function _cmd_rollback() {
  local generation="${1:-0}"

  # Validate generation number
  if ! [[ "$generation" =~ ^[0-9]$ ]]; then
    __print_error "Invalid generation number: $generation"
    __print_error "Must be 0-9"
    show_usage_rollback
    return $EC_INVALID_ARG
  fi

  local backup_file="${CONFIG_FILE}.${generation}"

  # Check if backup exists
  if [[ ! -f "$backup_file" ]]; then
    __print_error "Backup not found: $backup_file"
    __print_error "Available backups:"
    for i in {0..9}; do
      if [[ -f "${CONFIG_FILE}.${i}" ]]; then
        __print_info "  .${i} - $(stat -c %y "${CONFIG_FILE}.${i}" 2>/dev/null | cut -d' ' -f1)"
      fi
    done
    return $EC_FILE_NOT_FOUND
  fi

  # Save backup content to temp file BEFORE creating safety backup
  # (which would rotate the backup files)
  local temp_restore="${CONFIG_FILE}.restore.$$"
  if ! cp "$backup_file" "$temp_restore"; then
    __print_error "Failed to read backup file"
    return $EC_GENERAL
  fi

  # Create backup of current config before rollback
  if ! __create_config_backup; then
    __print_error "Failed to create safety backup before rollback"
    rm -f "$temp_restore"
    return $EC_FAILED_BACKUP
  fi

  # Restore backup from temp file
  if cp "$temp_restore" "$CONFIG_FILE"; then
    rm -f "$temp_restore"
    __print_success "Configuration rolled back to generation $generation"
    __print_info "Previous config backed up as ${CONFIG_FILE}.0"
    __print_info "Rolled back from: $backup_file"
    return $EC_OKAY
  else
    __print_error "Failed to restore backup"
    return $EC_GENERAL
  fi
}

function _cmd_diff() {
  local generation="${1:-0}"

  # Validate generation number
  if ! [[ "$generation" =~ ^[0-9]$ ]]; then
    __print_error "Invalid generation number: $generation"
    __print_error "Must be 0-9"
    show_usage_diff
    return $EC_INVALID_ARG
  fi

  local backup_file="${CONFIG_FILE}.${generation}"

  # Check if backup exists
  if [[ ! -f "$backup_file" ]]; then
    __print_error "Backup not found: $backup_file"
    return $EC_FILE_NOT_FOUND
  fi

  # Show diff
  __print_info "Differences between current config and generation $generation:"
  echo ""

  if command -v diff &> /dev/null; then
    diff -u --color=auto "$backup_file" "$CONFIG_FILE" || true
  else
    # Fallback if diff doesn't support --color
    diff -u "$backup_file" "$CONFIG_FILE" || true
  fi

  return $EC_OKAY
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return 0
  fi

  case "$command" in
    set)
      show_usage_set
      ;;
    get)
      show_usage_get
      ;;
    list)
      show_usage_list
      ;;
    reset)
      show_usage_reset
      ;;
    validate)
      show_usage_validate
      ;;
    merge)
      show_usage_merge
      ;;
    rollback)
      show_usage_rollback
      ;;
    diff)
      show_usage_diff
      ;;
    edit)
      show_usage_edit
      ;;
    *)
      __print_error "Unknown command for help: $command"
      echo ""
      show_usage
      return $EC_INVALID_ARG
      ;;
  esac

  return 0
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

# Handle --json option for list command
if [[ "$command" == "list" ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json_format="1"
        shift
        ;;
      *)
        break
        ;;
    esac
  done
fi

case "$command" in
  "")
    show_usage
    exit $EC_GENERAL
    ;;
  -h | --help | help)
    _cmd_help "$@"
    exit $?
    ;;
  set)
    _cmd_set "$@"
    exit $?
    ;;
  get)
    _cmd_get "$@"
    exit $?
    ;;
  list)
    _cmd_list "$@"
    exit $?
    ;;
  reset)
    _cmd_reset "$@"
    exit $?
    ;;
  validate)
    _cmd_validate "$@"
    exit $?
    ;;
  merge)
    _cmd_merge "$@"
    exit $?
    ;;
  rollback)
    _cmd_rollback "$@"
    exit $?
    ;;
  diff)
    _cmd_diff "$@"
    exit $?
    ;;
  edit)
    _cmd_edit "$@"
    exit $?
    ;;
  *)
    __print_error "Invalid command '$command'"
    __print_error "Use '$self help' to see all available commands"
    exit $EC_INVALID_ARG
    ;;
esac
