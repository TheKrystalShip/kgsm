#!/usr/bin/env bash

# Disable shellcheck for double quotes, as it will complain about
# the variables being used in the functions below.
# shellcheck disable=SC2086

# Bootstrap the environment.
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/lib/bootstrap.sh"

# Load essential modules early
module_interactive=$(__find_module interactive.sh)

installer_script="$(__find_or_fail installer.sh)"

if [[ ! -f "$installer_script" ]]; then
  __print_error "installer.sh missing, won't be able to check for updates"
  __print_error "Installation might be compromised, please reinstall KGSM"
  exit $EC_GENERAL
fi

function check_for_update() {
  "$installer_script" --check-update
}

function update_script() {
  "$installer_script" --update
}

function get_version() {
  "$installer_script" --version
}


function usage() {
  local self
  self=$(basename "$0")

  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "Krystal Game Server Manager - $(get_version)

Create, install, and manage game servers on Linux.

If you have any problems while using KGSM, please don't hesitate to create an
issue on GitHub: https://github.com/TheKrystalShip/KGSM/issues"

  echo -e "
${UNDERLINE}Usage:${END}
  ${self} <command> [arguments] [options]

${BOLD}${UNDERLINE}Built-in Commands:${END}
  create <blueprint>          Alias for install
  install <blueprint>         Install a new game server instance
    [--install-dir <path>]    Installation directory (default: from config)
    [--version <version>]     Specific version to install (default: latest)
    [--name <name>]           Custom instance name (default: auto-generated)

  remove <instance>           Alias for uninstall
  uninstall <instance>        Remove a game server instance completely

  interactive                 Launch interactive menu mode

  -h, --help                  Display this help information
  -v, --version               Display KGSM version
  --check-update              Check for KGSM updates
  --update                    Update KGSM to latest version

${BOLD}${UNDERLINE}Module Commands:${END}
  blueprints <command>        Manage server blueprints
  config <command>            Manage KGSM configuration
  directories <command>       Manage directory structures
  events <command>            Manage event system
  files <command>             Manage instance files
  instances <command>         Manage server instances
  lifecycle <command>         Control server lifecycle
  network <command>           Manage network and ports
  system <command>            Manage system operations
  watcher <command>           Manage monitoring watchers

${UNDERLINE}For detailed help on any module:${END}
  ${self} <module> help
  ${self} <module> <command> --help

${BOLD}${UNDERLINE}Examples:${END}
  ${BOLD}Installation:${END}
  ${self} install factorio --install-dir /opt/servers --name factorio-01
  ${self} uninstall factorio-01

  ${BOLD}Blueprints:${END}
  ${self} blueprints list
  ${self} blueprints list --json
  ${self} blueprints info factorio

  ${BOLD}Configuration:${END}
  ${self} config list
  ${self} config set enable_logging=true
  ${self} config get enable_systemd

  ${BOLD}Instances:${END}
  ${self} instances list
  ${self} instances list factorio
  ${self} instances info factorio-01
  ${self} instances status factorio-01
  ${self} instances regenerate management-script

  ${BOLD}Lifecycle:${END}
  ${self} lifecycle start factorio-01
  ${self} lifecycle stop factorio-01
  ${self} lifecycle restart factorio-01
  ${self} lifecycle logs factorio-01 --follow

  ${BOLD}Network:${END}
  ${self} network ip
  ${self} network ports check 27015
  ${self} network ports conflicts
  ${self} network test-port 27015
  ${self} network test-all

  ${BOLD}System:${END}
  ${self} system info
  ${self} system info --json
  ${self} system uptime
  ${self} system shutdown 10
  ${self} system restart 5

  ${BOLD}Directories & Files:${END}
  ${self} directories create --instance factorio-01
  ${self} files create systemd --instance factorio-01
  ${self} files remove ufw --instance factorio-01

  ${BOLD}Events:${END}
  ${self} events status
  ${self} events test-all
  ${self} events webhook configure
"
}

# Check for updates if configuration allows it
if [[ -n "$config_auto_update_check" && "$config_auto_update_check" == "true" ]]; then
  check_for_update
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -h | --help)
    shift
    [[ -z "$1" ]] && usage && exit 0
    case "$1" in
    --interactive)
      "$module_interactive" --description
      exit $?
      ;;
    *)
      __print_error "Invalid argument $1" && exit $EC_INVALID_ARG
      ;;
    esac
    ;;
  --interactive)
    "$module_interactive" -i
    exit $?
    ;;
  --check-update)
    check_for_update
    exit $?
    ;;
  --update)
    update_script
    exit $?
    ;;
  *)
    break
    ;;
  esac
  shift
done

# ============================================================================
# BUILT-IN COMMAND FUNCTIONS
# ============================================================================

# Install command - orchestrates instance creation across multiple modules
function _cmd_install() {
  local blueprint=$1
  shift

  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Usage: $(basename "$0") install <blueprint> [--install-dir <path>] [--version <version>] [--name <name>]"
    exit $EC_MISSING_ARG
  fi

  # shellcheck disable=SC2154
  local install_dir=$config_default_install_directory
  local version=0  # 0 means get latest
  local identifier=

  # Parse optional arguments
  while [[ $# -ne 0 ]]; do
    case "$1" in
    --install-dir)
      shift
      if [[ -z "$1" ]]; then
        __print_error "Missing argument for --install-dir"
        exit $EC_MISSING_ARG
      fi
      install_dir="$1"
      ;;
    --version)
      shift
      if [[ -z "$1" ]]; then
        __print_error "Missing argument for --version"
        exit $EC_MISSING_ARG
      fi
      version=$1
      ;;
    --name)
      shift
      if [[ -z "$1" ]]; then
        __print_error "Missing argument for --name"
        exit $EC_MISSING_ARG
      fi
      identifier=$1
      ;;
    *)
      __print_error "Invalid argument: $1"
      exit $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  if [[ -z "$install_dir" ]]; then
    __print_error "Installation directory not specified and no default configured"
    exit $EC_MISSING_ARG
  fi

  __print_info "Creating a new instance of $blueprint in $install_dir..."

  local instance

  # Create instance configuration
  instance="$(
    "$(__find_module instances.sh)" \
      create "$blueprint" \
      --install-dir "$install_dir" \
      ${identifier:+--name $identifier}
  )"

  # Emit after the instance has been created, so we can use the identifier
  "$module_events" --emit --instance-installation-started "${instance}" "${blueprint}"

  # Create directory structure
  "$(__find_module directories.sh)" create --instance "$instance" || return $?

  # Create instance files
  "$(__find_module files.sh)" -i "$instance" --create || return $?

  # Load instance config to access variables
  __source_instance "$instance"

  # Determine version
  if [[ "$version" == 0 ]]; then
    # shellcheck disable=SC2154
    version=$("$instance_management_file" --version --latest)
  fi

  local module_events
  module_events="$(__find_module events.sh)"

  # Download game files
  "$module_events" --emit --instance-download-started "${instance}"
  "$instance_management_file" --download "${version}" || return $EC_FAILED_DOWNLOAD
  "$module_events" --emit --instance-download-finished "${instance}"
  "$module_events" --emit --instance-downloaded "${instance}"

  # Deploy the instance
  "$module_events" --emit --instance-deploy-started "${instance}"
  "$instance_management_file" --deploy || return $EC_FAILED_DEPLOY
  "$module_events" --emit --instance-deploy-finished "${instance}"
  "$module_events" --emit --instance-deployed "${instance}"

  # Save version
  "$instance_management_file" --version --save "$version" || return $EC_FAILED_VERSION_SAVE
  "$module_events" --emit --instance-version-updated "${instance}" "0" "${version}"

  "$module_events" --emit --instance-installation-finished "${instance}" "${blueprint}"

  __print_success "Instance '${instance}', version '${version}', has been created in '${install_dir}'"
  "$module_events" --emit --instance-installed "${instance}" "${blueprint}"

  return 0
}

# Uninstall command - orchestrates instance removal across multiple modules
function _cmd_uninstall() {
  local instance=$1

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Usage: $(basename "$0") uninstall <instance>"
    exit $EC_MISSING_ARG
  fi

  local module_events
  module_events="$(__find_module events.sh)"

  "$module_events" --emit --instance-uninstall-started "${instance}"

  "$(__find_module files.sh)" -i "$instance" --remove || return $?
  "$(__find_module directories.sh)" remove --instance "$instance" || return $?
  "$(__find_module instances.sh)" remove "$instance" || return $?

  "$module_events" --emit --instance-uninstall-finished "${instance}"

  __print_success "Instance '${instance}' uninstalled"

  "$module_events" --emit --instance-uninstalled "${instance}"

  return 0
}

# Version command - display KGSM version
function _cmd_version() {
  echo "KGSM, version $(get_version)
Copyright (C) 2024 TheKrystalShip
License GPL-3.0: GNU GPL version 3 <https://www.gnu.org/licenses/gpl-3.0.en.html>

This is free software; you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law."
  return 0
}

# Interactive mode function moved to modules/interactive.sh
# If it's started with no args, default to interactive mode
if [[ "$#" -eq 0 ]]; then
  "$module_interactive" -i
  exit $?
fi

# ============================================================================
# MAIN ARGUMENT PROCESSING
# ============================================================================
command="$1"
shift

case "$command" in
  # BUILT-IN COMMANDS
  install | create)
    _cmd_install "$@"
    exit $?
    ;;
  uninstall | remove)
    _cmd_uninstall "$@"
    exit $?
    ;;
  interactive)
    "$module_interactive" -i
    exit $?
    ;;

  # KGSM META COMMANDS
  -h | --help)
    usage
    exit 0
    ;;
  -v | --version)
    _cmd_version
    exit 0
    ;;
  --check-update)
    check_for_update
    exit $?
    ;;
  --update)
    update_script "$@"
    exit $?
    ;;

  # MODULE PASSTHROUGHS
  blueprints)
    "$(__find_module blueprints.sh)" "$@"
    exit $?
    ;;
  config)
    "$(__find_module config.sh)" "$@"
    exit $?
    ;;
  directories)
    "$(__find_module directories.sh)" "$@"
    exit $?
    ;;
  events)
    "$(__find_module events.sh)" "$@"
    exit $?
    ;;
  files)
    "$(__find_module files.sh)" "$@"
    exit $?
    ;;
  instances)
    "$(__find_module instances.sh)" "$@"
    exit $?
    ;;
  lifecycle)
    "$(__find_module lifecycle.sh)" "$@"
    exit $?
    ;;
  network)
    "$(__find_module network.sh)" "$@"
    exit $?
    ;;
  system)
    "$(__find_module system.sh)" "$@"
    exit $?
    ;;
  watcher)
    "$(__find_module watcher.sh)" "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$(basename "$0") --help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac

exit 0
