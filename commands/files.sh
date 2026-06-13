#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}File Management for Krystal Game Server Manager${END}

Orchestrates file management operations across all instance components.

${UNDERLINE}Usage:${END}
  ${self} <component> <command> <instance>
  ${self} create <instance>
  ${self} remove <instance>

${UNDERLINE}Components:${END}
  management                  Management file operations (create, remove)
  config                      Standalone config operations (install, uninstall)
  ufw                         UFW firewall integration (enable, disable)
  symlink                     Command shortcut integration (enable, disable)
  upnp                        UPnP port forwarding integration (enable, disable)

${UNDERLINE}Quick Commands:${END}
  create <instance>           Create all required files and enabled integrations
  remove <instance>           Remove all files and integrations (for uninstall)
  help [component]            Display help for a specific component

${UNDERLINE}Examples:${END}
  ${self} create factorio-server
  ${self} remove factorio-server
  ${self} management create factorio-server
  ${self} ufw disable factorio-server
  ${self} help management

${UNDERLINE}Notes:${END}
  • Quick commands are configuration-aware and respect config.ini settings
  • Management file and config file are ALWAYS created (required for operation)
  • Optional integrations (ufw, symlink, upnp) follow config.ini defaults
  • Component commands allow manual control after initial instance creation
  • Use 'help <component>' for component-specific documentation
"
}

function show_usage_create() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Create All Files and Integrations${END}

Creates all required files and enabled integrations for a game server instance.

${UNDERLINE}Usage:${END}
  ${self} create <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Creates the complete file structure for the specified instance based on
  your configuration settings in config.ini. This command always creates:

  ${UNDERLINE}Required Files (Always Created):${END}
    • Management script (instance.manage.sh)
    • Standalone configuration file

  ${UNDERLINE}Optional Integrations (Config-Dependent):${END}
    • UFW firewall rules (if enable_firewall_management=true)
    • Command shortcuts/symlinks (if enable_command_shortcuts=true)
    • UPnP port forwarding rules (if enable_port_forwarding=true)

  After initial creation, you can manually enable/disable optional integrations
  using the component-specific commands (e.g., 'files.sh ufw enable').

${UNDERLINE}Examples:${END}
  ${self} create factorio-server
  ${self} create minecraft-modded

${UNDERLINE}Requirements:${END}
  • Valid instance configuration file
  • Write permissions in instance directories
  • Root/sudo permissions (only if UFW is enabled)
"
}

function show_usage_remove() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Remove All Files and Integrations${END}

Removes all files and integrations for a game server instance (for uninstall).

${UNDERLINE}Usage:${END}
  ${self} remove <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Removes all files and integrations created for the specified instance.
  This operation reads the instance configuration to determine which
  integrations are currently enabled and removes them accordingly.

  ${UNDERLINE}Removed Components:${END}
    • UFW firewall rules (if enable_firewall_management=true)
    • Command shortcuts/symlinks (if enable_command_shortcuts=true)
    • UPnP port forwarding rules (if enable_port_forwarding=true)
    • Management script (instance.manage.sh)

  ${UNDERLINE}Preserved Components:${END}
    • Instance configuration file (required for cleanup by other modules)
    • Instance data, saves, backups, and logs

${UNDERLINE}Examples:${END}
  ${self} remove factorio-server
  ${self} remove minecraft-modded

${UNDERLINE}Warning:${END}
  This command is typically called during instance uninstallation.
  For normal operations, use component-specific disable commands instead.

${UNDERLINE}Requirements:${END}
  • Valid instance configuration file
  • Root/sudo permissions (only if UFW integration is enabled)
"
}

# Quick command: create all files
function _cmd_create() {
  local instance_name=""

  # Parse create command options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_create
        return 0
        ;;
      -*)
        __print_error "Invalid option for create command: $1"
        __print_error "Use '${self} create --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    echo "Usage: $self create <instance>"
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  # Load instance configuration
  __source_instance "$instance_name"

  __print_info "Creating files and integrations for instance '$instance_name'..."

  # Create management file
  files.management.sh create "$instance_name" || return $?

  # When creating files, we read the $config_ variables from the KGSM config file.
  # This is necessary to determine if we need to create the firewall rules or
  # command shortcuts.

  if [[ "$config_enable_firewall_management" == "true" ]]; then
    files.ufw.sh enable "$instance_name" || return $?
  fi

  if [[ "$config_enable_command_shortcuts" == "true" ]]; then
    files.symlink.sh enable "$instance_name" || return $?
  fi

  # Emit event
  events.sh emit instance-files-created "${instance_name}"

  __print_success "All files and integrations created successfully"
  return 0
}

# Quick command: remove all files (for uninstall)
function _cmd_remove() {
  local instance_name=""

  # Parse create command options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_create
        return 0
        ;;
      -*)
        __print_error "Invalid option for create command: $1"
        __print_error "Use '${self} create --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    echo "Usage: $self remove <instance>"
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  # Load instance configuration
  __source_instance "$instance_name"

  __print_info "Removing files and integrations for instance '$instance_name'..."

  # When uninstalling files, we read the $instance_ variables from the instance config file.
  # This is necessary to determine if we need to remove the firewall rules or
  # command shortcuts.

  if [[ "$instance_enable_firewall_management" == "true" ]]; then
    __print_info "Disabling firewall integration for instance '$instance_name'..."
    files.ufw.sh disable "$instance_name" || return $?
  fi

  if [[ "$instance_enable_command_shortcuts" == "true" ]]; then
    __print_info "Disabling symlink for instance '$instance_name'..."
    files.symlink.sh disable "$instance_name" || return $?
  fi

  # Remove management file
  files.management.sh remove "$instance_name" || return $?
  # We don't remove the instance config file here, because it's still needed
  # for other modules to work during cleanup.

  # Emit event
  events.sh emit instance-files-removed "${instance_name}"

  __print_success "All files and integrations removed successfully"
  return 0
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
  management)
    files.management.sh "$@"
    exit $?
    ;;
  ufw)
    files.ufw.sh "$@"
    exit $?
    ;;
  symlink)
    files.symlink.sh "$@"
    exit $?
    ;;
  upnp)
    files.upnp.sh "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command or component: $command"
    exit $EC_INVALID_ARG
    ;;
esac
