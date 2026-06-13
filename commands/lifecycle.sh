#!/usr/bin/env bash

# KGSM Lifecycle Management CLI Orchestrator
#
# This module provides a standardized CLI interface for lifecycle operations.
# It calls pure logic functions and handles user interaction, event dispatching,
# and provides comprehensive help system.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Main usage function
function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "${UNDERLINE}Lifecycle Management for Krystal Game Server Manager${END}

Controls the operational state and monitoring of game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance> [options]

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
  ${self} start valheim-03
  ${self} logs factorio-01 --follow --tail 50
  ${self} restart minecraft-survival
  ${self} is-active valheim-03
  ${self} help start

For detailed help on a specific command, use:
  ${self} help <command>
"
}

# Usage function for start command
function show_usage_start() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Start Command${END}

Launch a game server instance and make it available to players.

${UNDERLINE}Usage:${END}
  ${self} start <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  ${self} start valheim-03
  ${self} start minecraft-survival
"
}

# Usage function for stop command
function show_usage_stop() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Stop Command${END}

Gracefully shut down a running server instance with proper save and cleanup.

${UNDERLINE}Usage:${END}
  ${self} stop <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  ${self} stop valheim-03
  ${self} stop minecraft-survival
"
}

# Usage function for restart command
function show_usage_restart() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Restart Command${END}

Perform a complete stop and start sequence. Useful after configuration changes.

${UNDERLINE}Usage:${END}
  ${self} restart <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  ${self} restart valheim-03
  ${self} restart minecraft-survival
"
}

# Usage function for status command
function show_usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Status Command${END}

Display comprehensive runtime status information for an instance.

${UNDERLINE}Usage:${END}
  ${self} status <instance> [options]

${UNDERLINE}Options:${END}
  --json                          Output status information as JSON
  --fast                          Skip update checking for faster response
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  ${self} status valheim-03
  ${self} status minecraft-survival --json
  ${self} status factorio-01 --fast
"
}

# Usage function for is-active command
function show_usage_is_active() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Is-Active Command${END}

Check if an instance is currently running. Returns exit code 0 if active, 1 if inactive.

${UNDERLINE}Usage:${END}
  ${self} is-active <instance>

${UNDERLINE}Options:${END}
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  ${self} is-active valheim-03
  ${self} is-active minecraft-survival
"
}

# Usage function for logs command
function show_usage_logs() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Logs Command${END}

Display instance log entries with various formatting options.

${UNDERLINE}Usage:${END}
  ${self} logs <instance> [options]

${UNDERLINE}Options:${END}
  -f, --follow                    Continuously monitor log output in real-time
  --tail <number>                 Display last <number> lines (default: 10)
  --help                          Display this help information

${UNDERLINE}Examples:${END}
  ${self} logs valheim-03
  ${self} logs factorio-01 --follow
  ${self} logs minecraft-survival --tail 50
  ${self} logs valheim-03 --follow --tail 100
"
}

# Load the internal logic library
# shellcheck source=handlers/lifecycle.sh
source "$(__find_command_handler lifecycle.sh)" || {
  __print_error "Failed to load lifecycle.sh library"
  exit $EC_FAILED_SOURCE
}

# Start command implementation
function _cmd_start() {
  local instance_name=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_start
        return 0
        ;;
      -*)
        __print_error "Invalid option for start command: $1"
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        break
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} start --help' for usage information"
    return $EC_MISSING_ARG
  fi

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
      watcher.sh start "$instance_name" --detach > /dev/null 2>&1 || true

      return $EC_SUCCESS
      ;;
    *)
      __print_error "Failed to start instance $instance_name"
      return $exit_code
      ;;
  esac
}

# Stop command implementation
function _cmd_stop() {
  local instance_name=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_stop
        return 0
        ;;
      -*)
        __print_error "Invalid option for stop command: $1"
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        break
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} stop --help' for usage information"
    return $EC_MISSING_ARG
  fi

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
      return $EC_SUCCESS
      ;;
    *)
      __print_error "Failed to stop instance $instance_name"
      return $exit_code
      ;;
  esac
}

# Restart command implementation
function _cmd_restart() {
  local instance_name=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_restart
        return 0
        ;;
      *)
        instance_name="$1"
        shift
        break
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} restart --help' for usage information"
    return $EC_MISSING_ARG
  fi

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
      return 0
      ;;
    *)
      __print_error "Failed to restart instance $instance_name"
      return $exit_code
      ;;
  esac
}

# Status command implementation
function _cmd_status() {
  local instance_name=""
  local json_format="false"
  local fast_mode="false"

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_status
        return 0
        ;;
      --json)
        json_format="true"
        ;;
      --fast)
        fast_mode="true"
        ;;
      -*)
        __print_error "Invalid option for status command: $1"
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        break
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} status --help' for usage information"
    exit $EC_MISSING_ARG
  fi

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
  local instance_name=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_is_active
        return 0
        ;;
      *)
        instance_name="$1"
        shift
        break
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} is-active --help' for usage information"
    return $EC_MISSING_ARG
  fi

  # Call pure logic function
  local exit_code
  __logic_instance_is_active "$instance_name"
  exit_code=$?

  # Handle results - is-active returns 0 for active, 1 for inactive
  if [[ $exit_code -eq 0 ]]; then
    __print_info "Instance $instance_name is active"
    return 0
  elif [[ $exit_code -eq 1 ]]; then
    __print_info "Instance $instance_name is inactive"
    return $EC_ERROR
  else
    __print_error "Failed to check status for instance $instance_name"
    return $exit_code
  fi
}

# Logs command implementation
function _cmd_logs() {
  local instance_name=""
  local follow_flag="false"
  local line_count="10"

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_logs
        return 0
        ;;
      -f | --follow)
        follow_flag="true"
        ;;
      -t | -n | --tail)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --tail" && return $EC_MISSING_ARG
        if [[ ! "$1" =~ ^[0-9]+$ ]]; then
          __print_error "Invalid number for --tail: $1"
          return $EC_INVALID_ARG
        fi
        line_count="$1"
        ;;
      *)
        instance_name="$1"
        shift
        break
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} logs --help' for usage information"
    return $EC_MISSING_ARG
  fi

  # Call pure logic function
  __logic_instance_logs "$instance_name" "$follow_flag" "$line_count"
}

function _cmd_help() {
  if [[ -z "$1" ]]; then
    show_usage
    return $EC_SUCCESS
  fi

  case "$1" in
    start)
      show_usage_start
      return $EC_SUCCESS
      ;;
    stop)
      show_usage_stop
      return $EC_SUCCESS
      ;;
    restart)
      show_usage_restart
      return $EC_SUCCESS
      ;;
    status)
      show_usage_status
      return $EC_SUCCESS
      ;;
    is-active)
      show_usage_is_active
      return $EC_SUCCESS
      ;;
    logs)
      show_usage_logs
      return $EC_SUCCESS
      ;;
    *)
      __print_error "Unknown command: $1"
      __print_error "Use '${self} help' for available commands"
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
  start)
    _cmd_start "$@"
    exit $?
    ;;
  stop)
    _cmd_stop "$@"
    exit $?
    ;;
  restart)
    _cmd_restart "$@"
    exit $?
    ;;
  status)
    _cmd_status "$@"
    exit $?
    ;;
  is-active)
    _cmd_is_active "$@"
    exit $?
    ;;
  logs)
    _cmd_logs "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '${self} help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac
