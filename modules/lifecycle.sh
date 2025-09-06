#!/usr/bin/env bash

# KGSM Lifecycle Management CLI Orchestrator
#
# This module provides a standardized CLI interface for lifecycle operations.
# It calls pure logic functions and handles user interaction, event dispatching,
# and provides comprehensive help system.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../lib/bootstrap.sh"

# Main usage function
function usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "${UNDERLINE}Lifecycle Management for Krystal Game Server Manager${END}

Controls the operational state and monitoring of game server instances.

${UNDERLINE}Usage:${END}
  $(basename "$0") <command> <instance> [options]

${UNDERLINE}Commands:${END}
  start <instance>                Launch a game server instance
  stop <instance>                 Gracefully shut down a running server
  restart <instance>              Perform a complete stop and start sequence
  status <instance>               Display comprehensive runtime status
  is-active <instance>            Check if instance is currently running
  logs <instance>                 Display instance log entries
  help [command]                  Display help information

${UNDERLINE}Global Options:${END}
  -h, --help                      Display this help information
  --debug                         Enable debug output

${UNDERLINE}Examples:${END}
  $(basename "$0") start valheim-03
  $(basename "$0") logs factorio-01 --follow --tail 50
  $(basename "$0") restart minecraft-survival
  $(basename "$0") is-active valheim-03
  $(basename "$0") help start

For detailed help on a specific command, use:
  $(basename "$0") help <command>
"
}

# Usage function for start command
function usage_start() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Start Command${END}

Launch a game server instance and make it available to players.

${UNDERLINE}Usage:${END}
  $(basename "$0") start <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  $(basename "$0") start valheim-03
  $(basename "$0") start minecraft-survival
"
}

# Usage function for stop command
function usage_stop() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Stop Command${END}

Gracefully shut down a running server instance with proper save and cleanup.

${UNDERLINE}Usage:${END}
  $(basename "$0") stop <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  $(basename "$0") stop valheim-03
  $(basename "$0") stop minecraft-survival
"
}

# Usage function for restart command
function usage_restart() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Restart Command${END}

Perform a complete stop and start sequence. Useful after configuration changes.

${UNDERLINE}Usage:${END}
  $(basename "$0") restart <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  $(basename "$0") restart valheim-03
  $(basename "$0") restart minecraft-survival
"
}

# Usage function for status command
function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Status Command${END}

Display comprehensive runtime status information for an instance.

${UNDERLINE}Usage:${END}
  $(basename "$0") status <instance> [options]

${UNDERLINE}Options:${END}
  --json                          Output status information as JSON
  --fast                          Skip update checking for faster response
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  $(basename "$0") status valheim-03
  $(basename "$0") status minecraft-survival --json
  $(basename "$0") status factorio-01 --fast
"
}

# Usage function for is-active command
function usage_is_active() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Is-Active Command${END}

Check if an instance is currently running. Returns exit code 0 if active, 1 if inactive.

${UNDERLINE}Usage:${END}
  $(basename "$0") is-active <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  $(basename "$0") is-active valheim-03
  $(basename "$0") is-active minecraft-survival
"
}

# Usage function for logs command
function usage_logs() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Logs Command${END}

Display instance log entries with various formatting options.

${UNDERLINE}Usage:${END}
  $(basename "$0") logs <instance> [options]

${UNDERLINE}Options:${END}
  -f, --follow                    Continuously monitor log output in real-time
  --tail <number>                 Display last <number> lines (default: 10)
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  $(basename "$0") logs valheim-03
  $(basename "$0") logs factorio-01 --follow
  $(basename "$0") logs minecraft-survival --tail 50
  $(basename "$0") logs valheim-03 --follow --tail 100
"
}

# Show usage and exit if no arguments provided
[[ $# -eq 0 ]] && usage && exit 1

# Handle global help and debug options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h | --help)
      usage && exit 0
      ;;
    --debug)
      export PS4='+(\033[0;33m${BASH_SOURCE}:${LINENO}\033[0m): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
      set -x
      shift
      ;;
    *)
      break
      ;;
  esac
done

# Get required modules
module_watcher="$(__find_module watcher.sh)"

# Load the internal logic library
source "$(__find_library lifecycle.sh)" || {
  __print_error "Failed to load lifecycle.sh library"
  exit $EC_FAILED_SOURCE
}

# Start command implementation
function _cmd_start() {
  local instance_name="$1"
  shift

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$(basename "$0") start --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Parse remaining options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        usage_start && exit 0
        ;;
      *)
        __print_error "Invalid option for start command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Call pure logic function
  __print_info "Starting instance $instance_name"
  local exit_code
  __logic_instance_start "$instance_name"
  exit_code=$?

  # Handle results based on exit code
  case $exit_code in
    $EC_SUCCESS_INSTANCE_STARTED)
      __print_success "Instance $instance_name started successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"

      # Start watcher if available
      if [[ -n "$module_watcher" ]]; then
        "$module_watcher" --start-watch "$instance_name" > /dev/null 2>&1 || true
      fi

      exit 0
      ;;
    *)
      __print_error "Failed to start instance $instance_name"
      exit $exit_code
      ;;
  esac
}

# Stop command implementation
function _cmd_stop() {
  local instance_name="$1"
  shift

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$(basename "$0") stop --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Parse remaining options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        usage_stop && exit 0
        ;;
      *)
        __print_error "Invalid option for stop command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Call pure logic function
  __print_info "Stopping instance $instance_name"
  local exit_code
  __logic_instance_stop "$instance_name"
  exit_code=$?

  # Handle results based on exit code
  case $exit_code in
    $EC_SUCCESS_INSTANCE_STOPPED)
      __print_success "Instance $instance_name stopped successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      exit 0
      ;;
    *)
      __print_error "Failed to stop instance $instance_name"
      exit $exit_code
      ;;
  esac
}

# Restart command implementation
function _cmd_restart() {
  local instance_name="$1"
  shift

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$(basename "$0") restart --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Parse remaining options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        usage_restart && exit 0
        ;;
      *)
        __print_error "Invalid option for restart command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Call pure logic function
  __print_info "Restarting instance $instance_name"
  local exit_code
  __logic_instance_restart "$instance_name"
  exit_code=$?

  # Handle results based on exit code
  case $exit_code in
    $EC_SUCCESS_INSTANCE_RESTARTED)
      __print_success "Instance $instance_name restarted successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      exit 0
      ;;
    *)
      __print_error "Failed to restart instance $instance_name"
      exit $exit_code
      ;;
  esac
}

# Status command implementation
function _cmd_status() {
  local instance_name="$1"
  shift
  local json_format=""
  local fast_mode=""

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$(basename "$0") status --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Parse remaining options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --json)
        json_format="true"
        ;;
      --fast)
        fast_mode="true"
        ;;
      --help)
        usage_status && exit 0
        ;;
      *)
        __print_error "Invalid option for status command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Call pure logic function
  local exit_code
  __logic_instance_status "$instance_name" "$json_format" "$fast_mode"
  exit_code=$?

  # Handle results
  if [[ $exit_code -eq 0 ]]; then
    exit 0
  else
    __print_error "Failed to get status for instance $instance_name"
    exit $exit_code
  fi
}

# Is-active command implementation
function _cmd_is_active() {
  local instance_name="$1"
  shift

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$(basename "$0") is-active --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Parse remaining options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        usage_is_active && exit 0
        ;;
      *)
        __print_error "Invalid option for is-active command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Call pure logic function
  local exit_code
  __logic_instance_is_active "$instance_name"
  exit_code=$?

  # Handle results - is-active returns 0 for active, 1 for inactive
  if [[ $exit_code -eq 0 ]]; then
    __print_info "Instance $instance_name is active"
    exit 0
  elif [[ $exit_code -eq 1 ]]; then
    __print_info "Instance $instance_name is inactive"
    exit 1
  else
    __print_error "Failed to check status for instance $instance_name"
    exit $exit_code
  fi
}

# Logs command implementation
function _cmd_logs() {
  local instance_name="$1"
  shift
  local follow_flag="false"
  local line_count="10"

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$(basename "$0") logs --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Parse remaining options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -f | --follow)
        follow_flag="true"
        ;;
      --tail)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --tail" && exit $EC_MISSING_ARG
        if [[ ! "$1" =~ ^[0-9]+$ ]]; then
          __print_error "Invalid number for --tail: $1"
          exit $EC_INVALID_ARG
        fi
        line_count="$1"
        ;;
      --help)
        usage_logs && exit 0
        ;;
      *)
        __print_error "Invalid option for logs command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Call pure logic function
  local exit_code
  __logic_instance_logs "$instance_name" "$follow_flag" "$line_count"
  exit_code=$?

  # Handle results
  if [[ $exit_code -eq 0 ]]; then
    exit 0
  else
    __print_error "Failed to get logs for instance $instance_name"
    exit $exit_code
  fi
}

# Mark module as loaded
export KGSM_LIFECYCLE_MODULE_LOADED=1

# Main command parsing
command="$1"
shift

case "$command" in
  start)
    _cmd_start "$@"
    ;;
  stop)
    _cmd_stop "$@"
    ;;
  restart)
    _cmd_restart "$@"
    ;;
  status)
    _cmd_status "$@"
    ;;
  is-active)
    _cmd_is_active "$@"
    ;;
  logs)
    _cmd_logs "$@"
    ;;
  help)
    if [[ -n "$1" ]]; then
      case "$1" in
        start)
          usage_start && exit 0
          ;;
        stop)
          usage_stop && exit 0
          ;;
        restart)
          usage_restart && exit 0
          ;;
        status)
          usage_status && exit 0
          ;;
        is-active)
          usage_is_active && exit 0
          ;;
        logs)
          usage_logs && exit 0
          ;;
        *)
          __print_error "Unknown command: $1"
          __print_error "Use '$(basename "$0") help' for available commands"
          exit $EC_INVALID_ARG
          ;;
      esac
    else
      usage && exit 0
    fi
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$(basename "$0") help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac
