#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load systemd integration logic library
logic_library=$(__find_command_handler files.systemd.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load files.systemd logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Systemd Integration for Krystal Game Server Manager${END}

Enable and disable systemd integration for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance>

${UNDERLINE}Commands:${END}
  enable <instance>           Enable systemd integration for the instance
  disable <instance>          Disable systemd integration for the instance
  help [command]              Display help for a specific command

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Examples:${END}
  ${self} enable factorio-space-age
  ${self} disable factorio-space-age
  ${self} help enable

${UNDERLINE}Notes:${END}
  • Systemd integration is optional for game server instances
  • Enable creates systemd service/socket files and updates instance configuration
  • Disable removes systemd files, stops/disables service, updates configuration
  • Requires root/sudo permissions for systemd operations
  • All operations require a valid instance configuration
"
}

function show_usage_enable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Enable Systemd Integration${END}

Creates systemd service and socket files for automatic server management.

${UNDERLINE}Usage:${END}
  ${self} enable <instance>

${UNDERLINE}Description:${END}
  Enables systemd integration for the specified instance by creating
  service and socket files in the systemd directory. This allows the
  server to be managed via systemctl commands and enables automatic
  startup on system boot.

  The instance configuration is updated to reflect systemd as the
  lifecycle manager.

${UNDERLINE}Examples:${END}
  ${self} enable factorio-server
  ${self} enable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Root/sudo permissions
  • Systemd installed and running
  • Valid instance configuration with required paths
"
}

function show_usage_disable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Disable Systemd Integration${END}

Removes systemd service and socket files and stops the service.

${UNDERLINE}Usage:${END}
  ${self} disable <instance>

${UNDERLINE}Description:${END}
  Disables systemd integration for the specified instance by stopping
  and disabling the service, then removing the service and socket files.
  The instance configuration is updated to use standalone lifecycle
  management instead of systemd.

${UNDERLINE}Examples:${END}
  ${self} disable factorio-server
  ${self} disable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Root/sudo permissions
  • Systemd installed and running
"
}

# Command: enable
function _cmd_enable() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo ""
        show_usage_enable
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_enable
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
    show_usage_enable
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Enabling systemd integration for instance '$instance_name'..."

  # Call logic function
  __logic_enable_systemd_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_SYSTEMD_ENABLED)
      __print_success "Systemd integration enabled successfully"
      __print_info "Service can now be managed with: systemctl start/stop/status $instance_name"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration - missing required fields"
      return $exit_code
      ;;
    $EC_FILE_NOT_FOUND)
      __print_error "Required template file not found"
      return $exit_code
      ;;
    $EC_FAILED_TEMPLATE)
      __print_error "Failed to generate systemd service/socket files from template"
      return $exit_code
      ;;
    $EC_FAILED_MV)
      __print_error "Failed to move systemd files to systemd directory"
      return $exit_code
      ;;
    $EC_SYSTEMD)
      __print_error "Failed to reload systemd daemon"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to enable systemd integration (exit code: $exit_code)"
      return $exit_code
      ;;
  esac
}

# Command: disable
function _cmd_disable() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo ""
        show_usage_disable
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_disable
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
    show_usage_disable
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Disabling systemd integration for instance '$instance_name'..."

  # Call logic function
  __logic_disable_systemd_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_SYSTEMD_DISABLED)
      __print_success "Systemd integration disabled successfully"
      __print_info "Instance reverted to standalone lifecycle management"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_SYSTEMD)
      __print_error "Failed to stop/disable systemd service or reload daemon"
      return $exit_code
      ;;
    $EC_FAILED_RM)
      __print_error "Failed to remove systemd service/socket files"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to disable systemd integration (exit code: $exit_code)"
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
    enable)
      show_usage_enable
      ;;
    disable)
      show_usage_disable
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
    exit $EC_GENERAL
    ;;
  -h | --help | help)
    _cmd_help "$@"
    exit $?
    ;;
  enable)
    _cmd_enable "$@"
    exit $?
    ;;
  disable)
    _cmd_disable "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    echo ""
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
