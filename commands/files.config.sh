#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load configuration file logic library
logic_library=$(__find_command_handler files.config.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load files.config logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Configuration File Operations for Krystal Game Server Manager${END}

Install and uninstall standalone configuration files for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance>

${UNDERLINE}Commands:${END}
  install <instance>          Install standalone configuration file for the instance
  uninstall <instance>        Uninstall standalone configuration file for the instance
  help [command]              Display help for a specific command

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Examples:${END}
  ${self} install factorio-space-age
  ${self} uninstall factorio-space-age
  ${self} help install

${UNDERLINE}Notes:${END}
  • Standalone configs are required for proper instance operation
  • Install creates config in instance working directory and symlinks from KGSM
  • Uninstall removes both the standalone config and KGSM symlink
  • All operations require a valid instance configuration
"
}

function show_usage_install() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Install Standalone Configuration${END}

Copies the instance configuration to the working directory and creates a symlink.

${UNDERLINE}Usage:${END}
  ${self} install <instance>

${UNDERLINE}Description:${END}
  Installs a standalone configuration file in the instance's working directory.
  This becomes the source of truth for the instance configuration. A symlink
  is created from KGSM's instances directory to this standalone config.

${UNDERLINE}Examples:${END}
  ${self} install factorio-server
  ${self} install minecraft-modded
"
}

function show_usage_uninstall() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Uninstall Standalone Configuration${END}

Removes the standalone configuration file and KGSM symlink.

${UNDERLINE}Usage:${END}
  ${self} uninstall <instance>

${UNDERLINE}Description:${END}
  Removes the standalone configuration file from the instance's working
  directory and the symlink from KGSM's instances directory. This operation
  is typically performed during instance uninstallation.

${UNDERLINE}Examples:${END}
  ${self} uninstall factorio-server
  ${self} uninstall minecraft-modded
"
}

# Command: install
function _cmd_install() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_install
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_install
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        break
        ;;
    esac
    shift
  done

  # Validate instance name provided
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    show_usage_install
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Installing standalone configuration for instance '$instance_name'..."

  # Call logic function
  __logic_install_standalone_config "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_CONFIG_INSTALLED)
      __print_success "Standalone configuration installed successfully"
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FAILED_CP)
      __print_error "Failed to copy configuration file"
      return $exit_code
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied while setting file ownership"
      return $exit_code
      ;;
    $EC_FAILED_RM)
      __print_error "Failed to remove existing KGSM config file/symlink"
      return $exit_code
      ;;
    $EC_FAILED_LN)
      __print_error "Failed to create KGSM symlink"
      return $exit_code
      ;;
    *)
      __print_error "Failed to install standalone configuration (exit code: $exit_code)"
      return $exit_code
      ;;
  esac
}

# Command: uninstall
function _cmd_uninstall() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_uninstall
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_uninstall
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        break
        ;;
    esac
    shift
  done

  # Validate instance name provided
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    show_usage_uninstall
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Uninstalling standalone configuration for instance '$instance_name'..."

  # Call logic function
  __logic_uninstall_standalone_config "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_CONFIG_UNINSTALLED)
      __print_success "Standalone configuration uninstalled successfully"
      return 0
      ;;
    $EC_FAILED_RM)
      __print_error "Failed to remove configuration file or symlink"
      return $exit_code
      ;;
    *)
      __print_error "Failed to uninstall standalone configuration (exit code: $exit_code)"
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
    install)
      show_usage_install
      ;;
    uninstall)
      show_usage_uninstall
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
  install)
    _cmd_install "$@"
    exit $?
    ;;
  uninstall)
    _cmd_uninstall "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    echo ""
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
