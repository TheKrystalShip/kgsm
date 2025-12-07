#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load symlink logic library
logic_library=$(__find_command_handler files.symlink.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load files.symlink logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Command Shortcut Integration for Krystal Game Server Manager${END}

Enable and disable command shortcut integration for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance>

${UNDERLINE}Commands:${END}
  enable <instance>           Enable command shortcuts for the instance
  disable <instance>          Disable command shortcuts for the instance
  help [command]              Display help for a specific command

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Examples:${END}
  ${self} enable factorio-space-age
  ${self} disable factorio-space-age
  ${self} help enable

${UNDERLINE}Notes:${END}
  • Command shortcuts are optional for game server instances
  • Enable creates symlinks in the configured shortcuts directory
  • Shortcuts provide quick CLI access to instance management
  • Disable removes the symlinks for the instance
  • All operations require a valid instance configuration
"
}

function show_usage_enable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Enable Command Shortcut Integration${END}

Creates command shortcuts (symlinks) for the instance.

${UNDERLINE}Usage:${END}
  ${self} enable <instance>

${UNDERLINE}Description:${END}
  Enables command shortcut integration for the specified instance by
  creating symbolic links in the configured shortcuts directory. This
  allows you to manage the instance using short, convenient commands
  from the terminal.

  The instance configuration is updated to reflect that command
  shortcuts are enabled.

${UNDERLINE}Examples:${END}
  ${self} enable factorio-server
  ${self} enable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Valid instance configuration
  • Configured command shortcuts directory
  • Write permissions in shortcuts directory
"
}

function show_usage_disable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Disable Command Shortcut Integration${END}

Removes command shortcuts for the instance.

${UNDERLINE}Usage:${END}
  ${self} disable <instance>

${UNDERLINE}Description:${END}
  Disables command shortcut integration for the specified instance by
  removing the symbolic links from the shortcuts directory. The instance
  configuration is updated to reflect that command shortcuts are disabled.

${UNDERLINE}Examples:${END}
  ${self} disable factorio-server
  ${self} disable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Valid instance configuration
"
}

# Command: enable
function _cmd_enable() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_enable
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
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

  __print_info "Enabling command shortcut integration for instance '$instance_name'..."

  # Call logic function
  __logic_enable_symlink_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_SYMLINK_CREATED)
      __print_success "Command shortcut integration enabled successfully"
      __print_info "Symlink created in shortcuts directory"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration - missing required fields"
      return $exit_code
      ;;
    $EC_GENERAL)
      __print_error "Symlink already exists for this instance"
      return $exit_code
      ;;
    $EC_DIR_NOT_FOUND)
      __print_error "Command shortcuts directory not found"
      return $exit_code
      ;;
    $EC_FAILED_SYMLINK)
      __print_error "Failed to create symlink"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to enable symlink integration (exit code: $exit_code)"
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
        show_usage_disable
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
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

  __print_info "Disabling command shortcut integration for instance '$instance_name'..."

  # Call logic function
  __logic_disable_symlink_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_SYMLINK_REMOVED)
      __print_success "Command shortcut integration disabled successfully"
      __print_info "Symlink removed from shortcuts directory"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FAILED_RM)
      __print_error "Failed to remove symlink"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to disable symlink integration (exit code: $exit_code)"
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
      __print_error "Unknown command for help: $command"
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
