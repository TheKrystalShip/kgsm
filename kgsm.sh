#!/usr/bin/env bash

# Disable shellcheck for double quotes, as it will complain about
# the variables being used in the functions below.
# shellcheck disable=SC2086

# Bootstrap the environment.
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/core/bootstrap.sh"

# KGSM_VERSION is declared in core/bootstrap.sh, sourced above, so that every
# entrypoint reports the same version — not just this one.

function show_usage() {
  local self
  self=$(basename "$0")

  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "Krystal Game Server Manager - ${KGSM_VERSION}

Create, install, and manage game servers on Linux.

If you have any problems while using KGSM, please don't hesitate to create an
issue on GitHub: https://github.com/TheKrystalShip/KGSM/issues"

  echo -e "
${UNDERLINE}Usage:${END}
  ${self} <command> [arguments] [options]

${BOLD}${UNDERLINE}Built-in Commands:${END}
  -h, --help                  Display this help information
  -v, --version               Display KGSM version
  --paths [--json]            Display XDG directory layout (--json for machine-readable)

${BOLD}${UNDERLINE}Module Commands:${END}
  create <blueprint>          Alias for install
  install <blueprint>         Install a new game server instance
    [--library <name>]        Library to place the instance in
    [--version <version>]     Specific version to install
    [--name <name>]           Custom instance name
    [--port <port>]           Override the blueprint's primary game port
    [--skip-space-check]      Install without the library free-space check
  remove <instance>           Alias for uninstall
  uninstall <instance>        Remove a game server instance
  interactive                 Launch interactive menu mode
  blueprints <command>        Manage server blueprints
  config <command>            Manage KGSM configuration
  directories <command>       Manage directory structures
  events <command>            Manage event system
  files <command>             Manage instance files
  instances <command>         Manage server instances
  libraries <command>         Manage instance placement libraries
  lifecycle <command>         Control server lifecycle
  autostart <command>         Control boot auto-start (enable, disable, status, list)
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
  ${self} install factorio --library ssd --name factorio-01
  ${self} uninstall factorio-01

  ${BOLD}Lifecycle Management:${END}
  ${self} start factorio-01
  ${self} stop factorio-01
  ${self} restart factorio-01
  ${self} status factorio-01
  ${self} logs factorio-01 --follow
  ${self} is-active factorio-01

  ${BOLD}Libraries:${END}
  ${self} libraries add /mnt/ssd/kgsm --name ssd
  ${self} libraries list
  ${self} instances move factorio-01 --library ssd
  ${self} libraries remove ssd --drain archive
  ${self} libraries remove ssd

  ${BOLD}Blueprints:${END}
  ${self} blueprints list
  ${self} blueprints list --json
  ${self} blueprints info factorio

  ${BOLD}Configuration:${END}
  ${self} config list
  ${self} config set enable_logging=true
  ${self} config get enable_command_shortcuts
"
}

# Version command - display KGSM version
function _cmd_version() {
  echo "KGSM, version ${KGSM_VERSION}
Copyright (C) 2024 TheKrystalShip
License GPL-3.0: GNU GPL version 3 <https://www.gnu.org/licenses/gpl-3.0.en.html>

This is free software; you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law."
  return 0
}

# Paths command - display XDG directory layout
function _cmd_paths() {
  local _json=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        _json=true
        shift
        ;;
      *)
        __print_error "Unknown option for --paths: $1"
        return $EC_INVALID_ARG
        ;;
    esac
  done

  if [[ "$_json" == true ]]; then
    if ! command -v jq > /dev/null 2>&1; then
      __print_error "JSON output requires jq to be installed"
      return $EC_MISSING_DEPENDENCY
    fi
    jq -n \
      --arg KGSM_ROOT "$KGSM_ROOT" \
      --arg KGSM_CORE_DIR "$KGSM_CORE_DIR" \
      --arg KGSM_COMMANDS_DIR "$KGSM_COMMANDS_DIR" \
      --arg KGSM_HANDLERS_DIR "$KGSM_HANDLERS_DIR" \
      --arg KGSM_TEMPLATES_DIR "$KGSM_TEMPLATES_DIR" \
      --arg KGSM_MIGRATIONS_DIR "$KGSM_MIGRATIONS_DIR" \
      --arg KGSM_SYSTEM_BLUEPRINTS_DIR "$KGSM_SYSTEM_BLUEPRINTS_DIR" \
      --arg KGSM_SYSTEM_OVERRIDES_DIR "$KGSM_SYSTEM_OVERRIDES_DIR" \
      --arg KGSM_DEFAULT_CONFIG_FILE "$KGSM_DEFAULT_CONFIG_FILE" \
      --arg KGSM_CONFIG_DIR "$KGSM_CONFIG_DIR" \
      --arg KGSM_CONFIG_FILE "$KGSM_CONFIG_FILE" \
      --arg KGSM_DATA_DIR "$KGSM_DATA_DIR" \
      --arg KGSM_INSTANCES_DIR "$KGSM_INSTANCES_DIR" \
      --arg KGSM_LOGS_DIR "$KGSM_LOGS_DIR" \
      --arg KGSM_USER_BLUEPRINTS_DIR "$KGSM_USER_BLUEPRINTS_DIR" \
      --arg KGSM_USER_OVERRIDES_DIR "$KGSM_USER_OVERRIDES_DIR" \
      '{
        system: {
          KGSM_ROOT: $KGSM_ROOT,
          KGSM_CORE_DIR: $KGSM_CORE_DIR,
          KGSM_COMMANDS_DIR: $KGSM_COMMANDS_DIR,
          KGSM_HANDLERS_DIR: $KGSM_HANDLERS_DIR,
          KGSM_TEMPLATES_DIR: $KGSM_TEMPLATES_DIR,
          KGSM_MIGRATIONS_DIR: $KGSM_MIGRATIONS_DIR,
          KGSM_SYSTEM_BLUEPRINTS_DIR: $KGSM_SYSTEM_BLUEPRINTS_DIR,
          KGSM_SYSTEM_OVERRIDES_DIR: $KGSM_SYSTEM_OVERRIDES_DIR,
          KGSM_DEFAULT_CONFIG_FILE: $KGSM_DEFAULT_CONFIG_FILE
        },
        user: {
          KGSM_CONFIG_DIR: $KGSM_CONFIG_DIR,
          KGSM_CONFIG_FILE: $KGSM_CONFIG_FILE,
          KGSM_DATA_DIR: $KGSM_DATA_DIR,
          KGSM_INSTANCES_DIR: $KGSM_INSTANCES_DIR,
          KGSM_LOGS_DIR: $KGSM_LOGS_DIR,
          KGSM_USER_BLUEPRINTS_DIR: $KGSM_USER_BLUEPRINTS_DIR,
          KGSM_USER_OVERRIDES_DIR: $KGSM_USER_OVERRIDES_DIR
        }
      }'
    return $?
  fi

  echo "KGSM Directory Layout:

System Paths (Read-only):
  KGSM_ROOT:                            $KGSM_ROOT
  KGSM_CORE_DIR:                        $KGSM_CORE_DIR
  KGSM_COMMANDS_DIR:                    $KGSM_COMMANDS_DIR
  KGSM_HANDLERS_DIR:                    $KGSM_HANDLERS_DIR
  KGSM_TEMPLATES_DIR:                   $KGSM_TEMPLATES_DIR
  KGSM_MIGRATIONS_DIR:                  $KGSM_MIGRATIONS_DIR
  KGSM_SYSTEM_BLUEPRINTS_DIR:           $KGSM_SYSTEM_BLUEPRINTS_DIR
  KGSM_SYSTEM_OVERRIDES_DIR:            $KGSM_SYSTEM_OVERRIDES_DIR
  KGSM_DEFAULT_CONFIG_FILE:             $KGSM_DEFAULT_CONFIG_FILE

User Paths (Writable):
  KGSM_CONFIG_DIR:                      $KGSM_CONFIG_DIR
  KGSM_CONFIG_FILE:                     $KGSM_CONFIG_FILE
  KGSM_DATA_DIR:                        $KGSM_DATA_DIR
  KGSM_INSTANCES_DIR:                   $KGSM_INSTANCES_DIR
  KGSM_LOGS_DIR:                        $KGSM_LOGS_DIR
  KGSM_USER_BLUEPRINTS_DIR:             $KGSM_USER_BLUEPRINTS_DIR
  KGSM_USER_OVERRIDES_DIR:              $KGSM_USER_OVERRIDES_DIR"
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
  --paths)
    _cmd_paths "$@"
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
  libraries)
    libraries.sh "$@"
    exit $?
    ;;
  lifecycle)
    lifecycle.sh "$@"
    exit $?
    ;;
  autostart)
    autostart.sh "$@"
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
