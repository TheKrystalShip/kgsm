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
  ${self} start <instance> [--force]

${UNDERLINE}Options:${END}
  --force                         Start even if the node does not have room for it
  --help                          Display this help information

${UNDERLINE}Description:${END}
  A start is refused when it would leave the node with less free memory than
  memory_gate_headroom_mb. What the instance needs is its own memory_cap_mb when
  set, otherwise its blueprint's advisory metadata.min_ram_mb; with neither
  declared the check cannot run and the start proceeds.

  --force skips that check. It exists because the blueprint figure is an estimate
  that can overstate what a game actually uses. It does not make more memory
  available: forcing a start the node genuinely cannot fit invites the OOM killer,
  which may take down a different server, or the watchdog supervising them all.

${UNDERLINE}Examples:${END}
  ${self} start valheim-03
  ${self} start minecraft-survival
  ${self} start projectzomboid --force
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
  ${self} restart <instance> [--force]

${UNDERLINE}Options:${END}
  --force                         Start even if the node does not have room for it
  --help                          Display this help information

${UNDERLINE}Description:${END}
  The start half is subject to the same node capacity check as '${self} start',
  measured after the stop — so this instance's own memory has already been
  returned to the node by the time the check runs.

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

# Library logic, for the placement key an instance created before libraries
# existed does not carry.
# shellcheck source=handlers/libraries.sh
source "$(__find_command_handler libraries.sh)" || {
  __print_error "Failed to load libraries logic library"
  exit $EC_FAILED_SOURCE
}

# Instance-config logic, for the keys an instance stamps on first use.
# shellcheck source=handlers/instances.sh
source "$(__find_command_handler instances.sh)" || {
  __print_error "Failed to load instances logic library"
  exit $EC_FAILED_SOURCE
}

# Records the library root of an instance created before instances recorded one.
# Placed on the lifecycle verbs so the key lands on first use rather than needing
# a migration pass over every instance on the host.
function _stamp_library_dir() {
  local instance="$1"

  local instance_config_file
  instance_config_file="$(__find_instance_config "$instance" 2> /dev/null)"
  [[ -n "$instance_config_file" ]] || return 0

  __logic_stamp_instance_library_dir "$instance_config_file" || return 0
  return 0
}

# Records what an instance does on a clock as one maintenance-window list.
# Placed on the lifecycle verbs so the key lands on first use rather than needing
# a migration pass over every instance on the host.
function _stamp_maintenance_windows() {
  local instance="$1"

  __logic_stamp_instance_maintenance_windows "$instance" || return 0
  return 0
}

# Refuses a lifecycle verb while the instance's library is not mounted, naming
# the library and where it is expected to be.
#
# Every verb here needs the instance's own files — its management script, its
# game binaries, its saves — so none of them can do anything at all until the
# disk is back. Refused here, up front, rather than left to fail somewhere in
# the middle of a start with an error about a missing file.
#
# Args: $1 = instance name
# Returns: EC_SUCCESS when the verb may proceed, EC_LIBRARY_OFFLINE otherwise
function _refuse_when_library_offline() {
  local instance="$1"

  __logic_instance_library_state "$instance" > /dev/null

  [[ "$__instance_library_state_out" == "offline" ]] || return $EC_SUCCESS

  __print_error "Instance '$instance' is in library '${__instance_library_name_out}', which is not reachable at ${__instance_library_path_out}"
  __print_error "Mount it and try again. Nothing about the instance has been changed or forgotten."
  return $EC_LIBRARY_OFFLINE
}

# Whether the instance is running RIGHT NOW, sampled before a lifecycle verb runs:
# "active", "inactive", or "unknown" when the probe itself could not answer.
#
# The lifecycle verbs are idempotent by design — the supervisor answers a stop for
# an already-stopped instance, or a start for an already-running one, with success,
# and it is right to. But the command layer turns that success into a state-change
# event, and a stop that stopped nothing is not a fact: it put "server stopped" in
# the audit trail of an instance that had been down for hours, and a start that
# started nothing would tell every surface a healthy server had just begun booting.
#
# So the event is emitted on a real TRANSITION, sampled here, and never on the verb's
# exit code alone. `unknown` is deliberately treated as "emit": suppressing on
# ignorance would lose a real transition, while emitting on ignorance at worst
# repeats one the consumer already knows about.
#
# Args: $1 = instance_name
function _run_state_before() {
  local _instance="$1"

  __logic_instance_is_active "$_instance" > /dev/null 2>&1
  case $? in
    0) echo "active" ;;
    1) echo "inactive" ;;
    *) echo "unknown" ;;
  esac
}

# Start command implementation
function _cmd_start() {
  local instance_name=""
  local force=false

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_start
        return 0
        ;;
      --force)
        force=true
        ;;
      -*)
        __print_error "Invalid option for start command: $1"
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        # --force is accepted on either side of the instance name, so the flag can
        # be appended to a command already typed out.
        while [[ "$#" -gt 0 ]]; do
          case $1 in
            --force) force=true ;;
            *) break ;;
          esac
          shift
        done
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
  _refuse_when_library_offline "$instance_name" || return $?
  _stamp_library_dir "$instance_name"
  _stamp_maintenance_windows "$instance_name"

  __print_info "Starting instance $instance_name"

  local before
  before="$(_run_state_before "$instance_name")"

  local exit_code
  __logic_instance_start "$instance_name" "$force"
  exit_code=$?


  # Handle results based on exit code
  case $exit_code in
    $EC_SUCCESS_INSTANCE_STARTED)
      __print_success "Instance $instance_name started successfully"
      # Only when a run actually began. The supervisor answers a start for an
      # already-running instance with success, and an event there would tell every
      # consumer a healthy server had just begun booting.
      if [[ "$before" == "active" ]]; then
        __print_info "Instance $instance_name was already running"
      else
        __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      fi
      return $EC_SUCCESS
      ;;
    $EC_INSUFFICIENT_MEMORY)
      # The gate has already said what it needs, what the node has, and what to do
      # about it. "Failed to start" on top of that adds nothing and reads like a
      # fault in the instance, which this is not.
      return $exit_code
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
  _refuse_when_library_offline "$instance_name" || return $?
  _stamp_library_dir "$instance_name"
  _stamp_maintenance_windows "$instance_name"

  __print_info "Stopping instance $instance_name"

  # A stop is not instant: the supervisor sends the game its stop command and then waits for the
  # process to drain, which for a game that saves its world on the way out is seconds to a minute,
  # and up to the instance's whole stop timeout when the game ignores it. These bracket that wait so
  # a consumer can show the instance as stopping while it happens, whichever entrypoint drove it —
  # the same bracket `instances update` carries. Finished is emitted on every outcome: it says the
  # run ENDED, while instance_stopped (emitted below, on success only) says the instance is down.
  local before
  before="$(_run_state_before "$instance_name")"

  __emit_event instance-stop-started "$instance_name"

  local exit_code
  __logic_instance_stop "$instance_name"
  exit_code=$?


  # Handle results based on exit code
  local result=$EC_SUCCESS
  case $exit_code in
    $EC_SUCCESS_INSTANCE_STOPPED)
      __print_success "Instance $instance_name stopped successfully"
      # Only when there was a run to end. A stop of an already-stopped instance
      # succeeds — it is idempotent — but nothing changed, and saying "stopped"
      # about a server that has been down for hours is a fact about nothing. The
      # uninstall path made this visible: it stops before removing, so every
      # uninstall of a stopped instance recorded a stop that never happened.
      if [[ "$before" == "inactive" ]]; then
        __print_info "Instance $instance_name was already stopped"
      else
        __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      fi
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

# The hook _cmd_restart hands to the restart logic — called once the stop half is down, with the
# instance name. Exported because the logic function it is passed to is itself exported and may run
# in a subshell, where an unexported hook name resolves to nothing and the event silently vanishes.
#
# Silent when the instance was not running when the restart began: there was no old run to bring
# down, so the middle of this restart is not a state anything passed through. KGSM_RESTART_WAS_ACTIVE
# carries that sample from _cmd_restart, because the hook runs in whatever shell the logic function
# is in and cannot take an argument of its own.
# Args: $1 = instance_name
# shellcheck disable=SC2329 # invoked by name, through __logic_instance_restart's hook
function __emit_restart_stopped() {
  [[ "${KGSM_RESTART_WAS_ACTIVE:-}" == "active" ]] || return 0
  __emit_event instance-restart-stopped "$1"
}

export -f __emit_restart_stopped

# Restart command implementation
function _cmd_restart() {
  local instance_name=""
  local force=false

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_restart
        return 0
        ;;
      --force)
        force=true
        ;;
      *)
        instance_name="$1"
        shift
        # --force is accepted on either side of the instance name (see _cmd_start).
        while [[ "$#" -gt 0 ]]; do
          case $1 in
            --force) force=true ;;
            *) break ;;
          esac
          shift
        done
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
  _refuse_when_library_offline "$instance_name" || return $?
  _stamp_library_dir "$instance_name"
  _stamp_maintenance_windows "$instance_name"

  __print_info "Restarting instance $instance_name"

  # A restart is a stop and a start back to back, so it lasts at least as long as the shutdown drain
  # plus the game's boot — the longest of the lifecycle verbs. It runs through the pure logic
  # functions rather than the stop and start COMMANDS, so none of their events fire along the way.
  # These bracket the whole thing, the same way stop and update are bracketed. Finished is emitted on
  # every outcome: it says the run ENDED, while instance-restarted says the instance came back.
  __emit_event instance-restart-started "$instance_name"

  # …and the middle is reported as it happens: instance-restart-stopped when the old run is down,
  # instance-restarted when the new one is up. Between them the process genuinely does not exist,
  # which is a thing consumers show and act on, and the bracket alone cannot say it — a consumer that
  # heard only "a restart is running" has to keep reporting the state from before the restart for the
  # whole shutdown. Emitted from here rather than from the logic layer, which stays pure.
  #
  # Restarting an instance that was already down has no such middle — there is no old run to end —
  # so the sample decides whether the hook says anything at all.
  local exit_code
  KGSM_RESTART_WAS_ACTIVE="$(_run_state_before "$instance_name")" \
    __logic_instance_restart "$instance_name" __emit_restart_stopped "$force"
  exit_code=$?


  # Handle results based on exit code
  local result=$EC_SUCCESS
  case $exit_code in
    $EC_SUCCESS_INSTANCE_RESTARTED)
      __print_success "Instance $instance_name restarted successfully"
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      ;;
    $EC_INSUFFICIENT_MEMORY)
      # The stop half succeeded and the start half was refused, which leaves the
      # instance DOWN. Say so plainly: an operator reading only the gate's message
      # could reasonably assume the restart was refused before anything happened.
      __print_error "Instance $instance_name was stopped but could not be started again, and is now down."
      result=$exit_code
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

  _refuse_when_library_offline "$instance_name" || exit $?

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

  _refuse_when_library_offline "$instance_name" || return $?

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

  _refuse_when_library_offline "$instance_name" || return $?

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

# Every verb here takes an instance first, and accepts its display name as well
# as its id. Resolved in one place so nothing inward of this line sees anything
# but an id.
case "$command" in
  start | stop | restart | status | is-active | logs)
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
