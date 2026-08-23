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
  firewall                    Firewall integration (enable, disable)
  symlink                     Command shortcut integration (enable, disable)

${UNDERLINE}Quick Commands:${END}
  create <instance>           Create all required files and enabled integrations
  remove <instance>           Remove all files and integrations (for uninstall)
  help [component]            Display help for a specific component

${UNDERLINE}Examples:${END}
  ${self} create factorio-server
  ${self} remove factorio-server
  ${self} management create factorio-server
  ${self} firewall disable factorio-server
  ${self} help management

${UNDERLINE}Notes:${END}
  • Quick commands are configuration-aware and respect config.ini settings
  • Management file and config file are ALWAYS created (required for operation)
  • Optional integrations (firewall, symlink) follow config.ini defaults
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
    • Firewall rules via kgsm-firewall (if enable_firewall_management=true)
    • Command shortcuts/symlinks (if enable_command_shortcuts=true)

  After initial creation, you can manually enable/disable optional integrations
  using the component-specific commands (e.g., 'files.sh firewall enable').

${UNDERLINE}Examples:${END}
  ${self} create factorio-server
  ${self} create minecraft-modded

${UNDERLINE}Requirements:${END}
  • Valid instance configuration file
  • Write permissions in instance directories
  • A reachable kgsm-firewall authority (only if firewall management is on)
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
    • Firewall rules via kgsm-firewall (if enable_firewall_management=true)
    • Command shortcuts/symlinks (if enable_command_shortcuts=true)
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
  • A reachable kgsm-firewall authority (only if firewall management is on)
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
    files.firewall.sh enable "$instance_name" || return $?
  fi

  if [[ "$config_enable_command_shortcuts" == "true" ]]; then
    # Command shortcuts are a convenience, not a security control. If the
    # configured directory can't be used — not writable (EC_PERMISSION) or
    # absent and not auto-creatable, i.e. outside $HOME (EC_FILE_NOT_FOUND) —
    # skip with a warning instead of escalating to sudo or aborting the whole
    # creation. The management file and instance config already exist by this
    # point, so those are the only ways the symlink step yields those two codes
    # here; any other failure still aborts. Contrast the firewall step above,
    # which hard-fails by design.
    files.symlink.sh enable "$instance_name"
    local _symlink_rc=$?
    if [[ $_symlink_rc -ne 0 ]]; then
      if [[ $_symlink_rc -eq $EC_PERMISSION ]] ||
        [[ $_symlink_rc -eq $EC_FILE_NOT_FOUND ]]; then
        __print_warning "Command shortcuts directory is not usable (not writable or missing); skipping shortcuts (no sudo). Instance created without them."
      else
        return $_symlink_rc
      fi
    fi
  fi

  # Emit event
  __emit_event instance-files-created "${instance_name}"

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

  # Every step is attempted, whatever the ones before it did. This runs as part of
  # an uninstall, which treats a failure here as a warning and goes on to delete
  # the instance's directories — so returning at the first failed step left the
  # later integrations behind on a host the instance was about to vanish from: a
  # firewall rule or a symlink for a server that no longer exists, and nobody
  # looking for them. The failure is still reported; it just no longer decides
  # how much cleanup happens.
  local failed=0

  if [[ "$instance_enable_firewall_management" == "true" ]]; then
    __print_info "Disabling firewall integration for instance '$instance_name'..."
    files.firewall.sh disable "$instance_name" || failed=$?
  fi

  if [[ "$instance_enable_command_shortcuts" == "true" ]]; then
    __print_info "Disabling symlink for instance '$instance_name'..."
    files.symlink.sh disable "$instance_name" || failed=$?
  fi

  # Remove management file
  files.management.sh remove "$instance_name" || failed=$?
  # We don't remove the instance config file here, because it's still needed
  # for other modules to work during cleanup.

  if [[ $failed -ne 0 ]]; then
    __print_error "Some files or integrations could not be removed"
    return $failed
  fi

  # Emitted only when everything really is gone: the event says the instance's
  # files were removed, and a partial cleanup has not earned that sentence.
  __emit_event instance-files-removed "${instance_name}"

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

# `create` and `remove` name an instance first and accept its display name as
# well as its id, resolved here so nothing inward sees anything but an id. The
# nested groups (management, firewall, symlink) take a subcommand first and
# resolve their own instance argument deeper in. An id resolves to itself.
case "$command" in
  create | remove)
    if [[ -n "${1:-}" ]] && [[ "$1" != -* ]]; then
      resolved_instance="$(__resolve_instance_id "$1")" || exit $?
      set -- "$resolved_instance" "${@:2}"
    fi
    ;;
esac

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
  firewall)
    files.firewall.sh "$@"
    exit $?
    ;;
  symlink)
    files.symlink.sh "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command or component: $command"
    exit $EC_INVALID_ARG
    ;;
esac
