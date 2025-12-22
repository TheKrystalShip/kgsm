#!/usr/bin/env bash

# Disable shellcheck for double quotes, as it will complain about
# the variables being used in the functions below.
# shellcheck disable=SC2086

# Bootstrap the environment.
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/core/bootstrap.sh"

module_installer="${KGSM_ROOT}/installer.sh"

function check_for_update() {
  "$module_installer" --check-update
}

function get_version() {
  "$module_installer" --version
}

function show_usage() {
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
  -h, --help                  Display this help information
  -v, --version               Display KGSM version
  --check-update              Check for KGSM updates
  --update                    Update KGSM to latest version

${BOLD}${UNDERLINE}Module Commands:${END}
  create <blueprint>          Alias for install
  install <blueprint>         Install a new game server instance
    [--install-dir <path>]    Installation directory
    [--version <version>]     Specific version to install
    [--name <name>]           Custom instance name
  remove <instance>           Alias for uninstall
  uninstall <instance>        Remove a game server instance
  interactive                 Launch interactive menu mode
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

${BOLD}${UNDERLINE}Lifecycle Shortcuts:${END}
  start <instance>            Start a server instance
  stop <instance>             Stop a server instance
  restart <instance>          Restart a server instance
  status <instance>           Show instance status
  logs <instance> [options]   View instance logs
  is-active <instance>        Check if instance is running

${UNDERLINE}For detailed help on any module:${END}
  ${self} <module> help
  ${self} <module> <command> --help

${BOLD}${UNDERLINE}Examples:${END}
  ${BOLD}Installation:${END}
  ${self} install factorio --install-dir /opt/servers --name factorio-01
  ${self} uninstall factorio-01

  ${BOLD}Lifecycle Management:${END}
  ${self} start factorio-01
  ${self} stop factorio-01
  ${self} restart factorio-01
  ${self} status factorio-01
  ${self} logs factorio-01 --follow
  ${self} is-active factorio-01

  ${BOLD}Blueprints:${END}
  ${self} blueprints list
  ${self} blueprints list --json
  ${self} blueprints info factorio

  ${BOLD}Configuration:${END}
  ${self} config list
  ${self} config set enable_logging=true
  ${self} config get enable_systemd
"
}

# Check for updates if configuration allows it
if [[ "${config_auto_update_check:-false}" == "true" ]]; then
  check_for_update
fi

# Version command - display KGSM version
function _cmd_version() {
  echo "KGSM, version $(get_version)
Copyright (C) 2024 TheKrystalShip
License GPL-3.0: GNU GPL version 3 <https://www.gnu.org/licenses/gpl-3.0.en.html>

This is free software; you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law."
  return 0
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;

  # KGSM META COMMANDS
  -h | --help | help)
    show_usage
    exit 0
    ;;
  -v | --version)
    _cmd_version
    exit 0
    ;;
  --check-update)
    "$module_installer" --check-update
    exit $?
    ;;
  --update)
    "$module_installer" --update
    exit $?
    ;;

  # MODULE PASSTHROUGHS
  install | create)
    install.sh "$@"
    exit $?
    ;;
  interactive)
    interactive.sh "$@"
    exit $?
    ;;
  uninstall | remove)
    uninstall.sh "$@"
    exit $?
    ;;
  blueprints)
    blueprints.sh "$@"
    exit $?
    ;;
  config)
    config.sh "$@"
    exit $?
    ;;
  directories)
    directories.sh "$@"
    exit $?
    ;;
  events)
    events.sh "$@"
    exit $?
    ;;
  files)
    files.sh "$@"
    exit $?
    ;;
  instances)
    instances.sh "$@"
    exit $?
    ;;
  lifecycle)
    lifecycle.sh "$@"
    exit $?
    ;;
  network)
    network.sh "$@"
    exit $?
    ;;
  system)
    system.sh "$@"
    exit $?
    ;;
  watcher)
    watcher.sh "$@"
    exit $?
    ;;

  # LIFECYCLE SHORTCUTS
  start | stop | restart | status | logs | is-active)
    lifecycle.sh "$command" "$@"
    exit $?
    ;;

  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$(basename "$0") --help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac
