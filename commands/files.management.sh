#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load management file logic library
logic_library=$(__find_command_handler files.management.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load files.management logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Management File Operations for Krystal Game Server Manager${END}

Create and remove management files for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance>

${UNDERLINE}Commands:${END}
  create <instance> Create management file for the specified instance
  remove <instance> Remove management file for the specified instance
  help [command]               Display help for a specific command

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Examples:${END}
  ${self} create factorio-space-age
  ${self} remove factorio-space-age
  ${self} help create

${UNDERLINE}Notes:${END}
  • Management files are required for all instances
  • Creates appropriate management script based on instance runtime (native/container)
  • Automatically injects override functions from blueprint-specific override files
  • All operations require a valid instance configuration
"
}

function show_usage_create() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Create Management File${END}

Generates the management script for a game server instance.

${UNDERLINE}Usage:${END}
  ${self} create <instance>

${UNDERLINE}Description:${END}
  Creates a management script (instance.manage.sh) for the specified instance.
  The script is generated from a template based on the instance runtime type
  (native or container) and includes any blueprint-specific override functions.

${UNDERLINE}Examples:${END}
  ${self} create factorio-server
  ${self} create minecraft-modded
"
}

function show_usage_remove() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Remove Management File${END}

Removes the management script for a game server instance.

${UNDERLINE}Usage:${END}
  ${self} remove <instance>

${UNDERLINE}Description:${END}
  Removes the management script (instance.manage.sh) for the specified instance.
  This operation is typically performed during instance uninstallation.

${UNDERLINE}Examples:${END}
  ${self} remove factorio-server
  ${self} remove minecraft-modded
"
}

# Command: create
function _cmd_create() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_create
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_create
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        ;;
    esac
  done

  # Validate instance name provided
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    show_usage_create
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Creating management file for instance '$instance_name'..."

  # Call logic function
  __logic_create_management_file "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_MANAGEMENT_FILE_CREATED)
      __print_success "Management file created successfully"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FILE_NOT_FOUND)
      __print_error "Required template or file not found"
      return $exit_code
      ;;
    $EC_FAILED_TEMPLATE)
      __print_error "Failed to generate management file from template"
      return $exit_code
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied while setting file ownership or permissions"
      return $exit_code
      ;;
    *)
      __print_error "Failed to create management file (exit code: $exit_code)"
      return $exit_code
      ;;
  esac
}

# Command: remove
function _cmd_remove() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_remove
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_remove
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        ;;
    esac
  done

  # Validate instance name provided
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    show_usage_remove
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Removing management file for instance '$instance_name'..."

  # Call logic function
  __logic_remove_management_file "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_MANAGEMENT_FILE_REMOVED)
      __print_success "Management file removed successfully"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FAILED_RM)
      __print_error "Failed to remove management file"
      return $exit_code
      ;;
    *)
      __print_error "Failed to remove management file (exit code: $exit_code)"
      return $exit_code
      ;;
  esac
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return 0
  fi

  case "$command" in
    create)
      show_usage_create
      ;;
    remove)
      show_usage_remove
      ;;
    *)
      __print_error "Unknown command: $command"
      echo ""
      show_usage
      return $EC_INVALID_ARG
      ;;
  esac
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  -h | --help | help)
    _cmd_help "$@"
    exit $?
    ;;
  create)
    _cmd_create "$@"
    exit $?
    ;;
  remove)
    _cmd_remove "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    echo ""
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
