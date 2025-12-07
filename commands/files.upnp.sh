#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load UPnP logic library
logic_library=$(__find_command_handler files.upnp.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load files.upnp logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}UPnP Port Forwarding Integration for Krystal Game Server Manager${END}

Enable and disable UPnP port forwarding integration for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance>

${UNDERLINE}Commands:${END}
  enable <instance>           Enable UPnP port forwarding for the instance
  disable <instance>          Disable UPnP port forwarding for the instance
  help [command]              Display help for a specific command

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Examples:${END}
  ${self} enable factorio-space-age
  ${self} disable factorio-space-age
  ${self} help enable

${UNDERLINE}Notes:${END}
  • UPnP integration is optional for game server instances
  • Enable sets configuration flag for port forwarding
  • Actual port forwarding occurs during lifecycle operations
  • Disable removes the configuration flag
  • All operations require a valid instance configuration
"
}

function show_usage_enable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Enable UPnP Port Forwarding Integration${END}

Enables UPnP port forwarding configuration for the instance.

${UNDERLINE}Usage:${END}
  ${self} enable <instance>

${UNDERLINE}Description:${END}
  Enables UPnP port forwarding integration for the specified instance by
  setting the enable_port_forwarding configuration flag. When enabled,
  the instance will automatically attempt to forward its ports using UPnP
  during start operations.

  This is a configuration-only operation and does not perform immediate
  port forwarding. Actual forwarding occurs when the instance starts.

${UNDERLINE}Examples:${END}
  ${self} enable factorio-server
  ${self} enable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Valid instance configuration
  • UPnP-capable router on the network
"
}

function show_usage_disable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Disable UPnP Port Forwarding Integration${END}

Disables UPnP port forwarding configuration for the instance.

${UNDERLINE}Usage:${END}
  ${self} disable <instance>

${UNDERLINE}Description:${END}
  Disables UPnP port forwarding integration for the specified instance by
  removing the enable_port_forwarding configuration flag. The instance will
  no longer attempt to forward ports via UPnP during lifecycle operations.

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

  __print_info "Enabling UPnP port forwarding integration for instance '$instance_name'..."

  # Call logic function
  __logic_enable_upnp_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_UPNP_ENABLED)
      __print_success "UPnP port forwarding integration enabled successfully"
      __print_info "Port forwarding will be activated when instance starts"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to enable UPnP integration (exit code: $exit_code)"
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

  __print_info "Disabling UPnP port forwarding integration for instance '$instance_name'..."

  # Call logic function
  __logic_disable_upnp_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_UPNP_DISABLED)
      __print_success "UPnP port forwarding integration disabled successfully"
      __print_info "Port forwarding will no longer occur during lifecycle operations"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to disable UPnP integration (exit code: $exit_code)"
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
