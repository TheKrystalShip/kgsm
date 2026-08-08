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

# Audits the host-firewall edges the lifecycle handlers just applied, so a port
# opening or closing is recorded the same way a router forward already is.
#
# The handlers record an edge only when KGSM performed the bring-up or teardown
# itself; the resident supervisor emits its own event for the instances it
# supervises, so draining the record here can never audit one start twice. Both
# edges of a restart drain together, in the order they happened.
#
# The payload is the instance's declared port spec, which the event renders as the
# canonical structured array. An instance that declares none opened nothing, so
# there is nothing to report.
# Args: $1 = instance name
function __emit_firewall_edges() {
  local _instance_name="$1"

  [[ -z "$KGSM_FIREWALL_APPLIED_EDGES" ]] && return 0

  local _config_file
  _config_file=$(__find_instance_config "$_instance_name" 2> /dev/null)
  if [[ -f "$_config_file" ]]; then
    local _ports
    _ports=$(__get_config_value "$_config_file" "ports" 2> /dev/null)

    if [[ -n "$_ports" ]]; then
      local _event
      while read -r _event; do
        [[ -z "$_event" ]] && continue
        __emit_event "$_event" "$_instance_name" "$_ports"
      done <<< "$KGSM_FIREWALL_APPLIED_EDGES"
    fi
  fi

  __firewall_edges_reset
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

  # Before the start's own event, so the trail reads in the order it happened: the
  # door opened, then the server came up. Drained on a failed start too — the ports
  # are open either way, and a rule that exists is a fact the trail must carry.
  __emit_firewall_edges "$instance_name"

  # Handle results based on exit code
  case $exit_code in
    $EC_SUCCESS_INSTANCE_STARTED)
      __print_success "Instance $instance_name started successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
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

  # A stop is not instant: the supervisor sends the game its stop command and then waits for the
  # process to drain, which for a game that saves its world on the way out is seconds to a minute,
  # and up to the instance's whole stop timeout when the game ignores it. These bracket that wait so
  # a consumer can show the instance as stopping while it happens, whichever entrypoint drove it —
  # the same bracket `instances update` carries. Finished is emitted on every outcome: it says the
  # run ENDED, while instance_stopped (emitted below, on success only) says the instance is down.
  __emit_event instance-stop-started "$instance_name"

  local exit_code
  __logic_instance_stop "$instance_name"
  exit_code=$?

  # Before instance-stopped, mirroring the order the supervisor emits its own pair
  # in: the ports are released as part of the teardown, not after the instance is
  # already reported down.
  __emit_firewall_edges "$instance_name"

  # Handle results based on exit code
  local result=$EC_SUCCESS
  case $exit_code in
    $EC_SUCCESS_INSTANCE_STOPPED)
      __print_success "Instance $instance_name stopped successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      ;;
    *)
      __print_error "Failed to stop instance $instance_name"
      result=$exit_code
      ;;
  esac

  # Emitted LAST, after instance-stopped on the success path: a consumer that reads "the run ended"
  # and re-reads the instance must find the outcome already recorded, or it briefly reports the state
  # the instance was in before the stop.
  __emit_event instance-stop-finished "$instance_name"

  return $result
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

  # A restart is a stop and a start back to back, so it lasts at least as long as the shutdown drain
  # plus the game's boot — the longest of the lifecycle verbs. It runs through the pure logic
  # functions rather than the stop and start COMMANDS, so none of their events fire along the way and
  # instance-restarted at the end is the only thing a consumer would otherwise see. These bracket the
  # whole thing, the same way stop and update are bracketed. Finished is emitted on every outcome: it
  # says the run ENDED, while instance-restarted says the instance came back.
  __emit_event instance-restart-started "$instance_name"

  local exit_code
  __logic_instance_restart "$instance_name"
  exit_code=$?

  # A restart crosses both edges, so this drains the close and the re-open together,
  # in the order they happened.
  __emit_firewall_edges "$instance_name"

  # Handle results based on exit code
  local result=$EC_SUCCESS
  case $exit_code in
    $EC_SUCCESS_INSTANCE_RESTARTED)
      __print_success "Instance $instance_name restarted successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      ;;
    *)
      __print_error "Failed to restart instance $instance_name"
      result=$exit_code
      ;;
  esac

  # Emitted LAST, after instance-restarted on the success path, for the same reason the stop bracket
  # is: a consumer that reads "the run ended" and re-reads the instance must find the outcome already
  # recorded rather than the state it was in before.
  __emit_event instance-restart-finished "$instance_name"

  return $result
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
