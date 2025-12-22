#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load UFW firewall logic library
logic_library=$(__find_command_handler files.ufw.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load files.ufw logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}UFW Firewall Integration for Krystal Game Server Manager${END}

Enable and disable UFW firewall integration for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance>

${UNDERLINE}Commands:${END}
  enable <instance>           Enable UFW firewall rules for the instance
  disable <instance>          Disable UFW firewall rules for the instance
  help [command]              Display help for a specific command

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Examples:${END}
  ${self} enable factorio-space-age
  ${self} disable factorio-space-age
  ${self} help enable

${UNDERLINE}Notes:${END}
  • UFW integration is optional for game server instances
  • Enable creates UFW rule file and enables the rule for instance ports
  • Disable removes UFW rules and deletes the rule file
  • Requires root/sudo permissions for UFW operations
  • All operations require a valid instance configuration
"
}

function show_usage_enable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Enable UFW Firewall Integration${END}

Creates UFW firewall rules for the instance's network ports.

${UNDERLINE}Usage:${END}
  ${self} enable <instance>

${UNDERLINE}Description:${END}
  Enables UFW firewall integration for the specified instance by creating
  a UFW application rule file and allowing traffic through the firewall.
  This ensures proper network connectivity for the game server.

  The instance configuration is updated to reflect that firewall
  management is enabled.

${UNDERLINE}Examples:${END}
  ${self} enable factorio-server
  ${self} enable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Root/sudo permissions
  • UFW installed and enabled
  • Valid instance configuration with port information
"
}

function show_usage_disable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Disable UFW Firewall Integration${END}

Removes UFW firewall rules for the instance.

${UNDERLINE}Usage:${END}
  ${self} disable <instance>

${UNDERLINE}Description:${END}
  Disables UFW firewall integration for the specified instance by
  removing the UFW rule and deleting the application rule file.
  The instance configuration is updated to reflect that firewall
  management is disabled.

${UNDERLINE}Examples:${END}
  ${self} disable factorio-server
  ${self} disable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Root/sudo permissions
  • UFW installed and enabled
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

  __print_info "Enabling UFW firewall integration for instance '$instance_name'..."

  # Call logic function
  __logic_enable_ufw_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_UFW_ENABLED)
      __print_success "UFW firewall integration enabled successfully"
      __print_info "Firewall rules created and activated for instance ports"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration - missing required fields"
      return $exit_code
      ;;
    $EC_ERROR)
      __print_error "Firewall rule file already exists"
      return $exit_code
      ;;
    $EC_FAILED_TEMPLATE)
      __print_error "Failed to generate UFW rule file from template"
      return $exit_code
      ;;
    $EC_FAILED_MV)
      __print_error "Failed to move UFW rule file to firewall directory"
      return $exit_code
      ;;
    $EC_PERMISSION)
      __print_error "Failed to set proper ownership on UFW rule file"
      return $exit_code
      ;;
    $EC_UFW)
      __print_error "Failed to enable UFW rule"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to enable UFW integration (exit code: $exit_code)"
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

  __print_info "Disabling UFW firewall integration for instance '$instance_name'..."

  # Call logic function
  __logic_disable_ufw_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_UFW_DISABLED)
      __print_success "UFW firewall integration disabled successfully"
      __print_info "Firewall rules removed for instance"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FAILED_RM)
      __print_error "Failed to remove UFW rule file"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to disable UFW integration (exit code: $exit_code)"
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
    exit $EC_ERROR
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
