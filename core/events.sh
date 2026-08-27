#!/usr/bin/env bash

# Disable SC2254 and SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe both unquoted and
# as case patterns. Declared here, before any code, so the directives cover the
# whole file rather than only the command that follows them.
# shellcheck disable=SC2254,SC2086

# KGSM Event Dispatcher Library
#
# This module provides centralized event dispatching based on exit codes
# to eliminate code duplication across modules and kgsm.sh.
#
# The dispatcher maps success-event exit codes (200+) to specific event emissions.

if [[ -n "${KGSM_EVENTS_LIBRARY_LOADED:-}" ]]; then
  return 0
fi

# Success event exit codes are now centralized in core/errors.sh
# They are automatically available through the bootstrap process

# Emits an event from inside the running KGSM process.
#
# Emission happens in-process rather than by re-executing `events.sh emit`:
# that re-exec costs a full bash bootstrap per event, which dominates the cost
# of emitting one. The events logic library is sourced on first use — every
# invocation loads this core module, but only the few that complete a
# lifecycle action ever emit.
#
# Args: $1 = event_name, $2... = event parameters
# Returns: EC_SUCCESS, EC_FAILED_SOURCE, or the failing stage's code
function __emit_event() {
  # The event TABLE, not the loaded flag, is what says this process can emit.
  # The flag is exported and EVENT_CONFIGS cannot be — bash exports strings,
  # never associative arrays — so a child process inherits "already loaded"
  # without the table, skips the source on that claim, and then every event type
  # it emits is rejected as invalid. That is any module reached through the
  # delegator (`files.sh remove`, `directories.sh remove`) and anything a
  # management script shells out to: their events stopped being recorded with
  # nothing anywhere reporting a failure.
  if [[ -z "${KGSM_LOGIC_EVENTS_LOADED:-}" ]] || [[ "${#EVENT_CONFIGS[@]}" -eq 0 ]]; then
    local _handler
    _handler="$(__find_command_handler events.sh)" || return $EC_FAILED_SOURCE

    # shellcheck disable=SC1090
    source "$_handler" || return $EC_FAILED_SOURCE
  fi

  local _result=$EC_SUCCESS
  __logic_emit_event "$@" || _result=$?

  # A journal write that fails is never silent: the operation itself already
  # happened, and an unrecorded operation that looks recorded is the failure
  # mode the journal exists to prevent. The caller decides what to do with the
  # code — callers on the completion path deliberately do not fail an
  # already-completed operation just because recording it did not work.
  if [[ $_result -eq $EC_EVENT_JOURNAL_FAILED ]]; then
    __print_warning "Event '${1:-}' was NOT recorded: the journal at $(__logic_journal_dir) could not be written"
  fi

  # A rejected event name is a bug in the caller, and it was the quietest failure
  # here: nothing was written, nothing was said, and the operation carried on
  # looking recorded. Warn on every non-journal failure for the same reason the
  # journal one warns.
  if [[ $_result -ne $EC_SUCCESS ]] && [[ $_result -ne $EC_EVENT_JOURNAL_FAILED ]]; then
    __print_warning "Event '${1:-}' was NOT recorded (code $_result)"
  fi

  # An actor that no reader can parse is dropped rather than written, and saying so
  # is the whole point: the event is on record with no actor, and only this line
  # says the caller meant to name one. Silence here would read as an action nobody
  # claimed, which is the same thing an unattributed event looks like.
  if [[ -n "${__logic_emit_actor_warning_out:-}" ]]; then
    __print_warning "KGSM_EVENT_ACTOR='${__logic_emit_actor_warning_out}' is not 'provider:name'; event '${1:-}' was recorded with no actor"
    __logic_emit_actor_warning_out=""
  fi

  return $_result
}

export -f __emit_event

# Dispatches events based on exit codes from logic functions
# Args: $1 = exit_code, $2 = instance_name, $3... = additional parameters
# Returns: 0 on success, error code on failure
function __dispatch_event_from_exit_code() {
  local exit_code="$1"
  local instance_name="$2"
  shift 2
  local additional_params=("$@")

  # Validate required parameters
  if [[ -z "$exit_code" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -z "$instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Map exit codes to event emissions
  case $exit_code in
    $EC_SUCCESS_DIRECTORIES_CREATED)
      __emit_event instance-directories-created "$instance_name"
      return $?
      ;;
    $EC_SUCCESS_DIRECTORIES_REMOVED)
      __emit_event instance-directories-removed "$instance_name"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_CREATED)
      __emit_event instance-created "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_REMOVED)
      __emit_event instance-removed "$instance_name"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_STARTED)
      __emit_event instance-started "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_STOPPED)
      __emit_event instance-stopped "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_RESTARTED)
      __emit_event instance-restarted "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_READY)
      __emit_event instance-ready "$instance_name"
      return $?
      ;;
    $EC_SUCCESS_CONFIG_SET)
      # TODO: Implement global config events when global event infrastructure is ready
      # events.sh emit config-set "$key" "$value"
      return 0
      ;;
    $EC_SUCCESS_CONFIG_RESET)
      # TODO: Implement global config events when global event infrastructure is ready
      # events.sh emit config-reset
      return 0
      ;;
    $EC_SUCCESS_CONFIG_VALIDATED)
      # TODO: Implement global config events when global event infrastructure is ready
      # events.sh emit config-validated
      return 0
      ;;
    $EC_SUCCESS_SYSTEM_SHUTDOWN)
      # TODO: Implement global system events when global event infrastructure is ready
      # events.sh emit system-shutdown "${additional_params[@]}"
      return 0
      ;;
    $EC_SUCCESS_SYSTEM_RESTART)
      # TODO: Implement global system events when global event infrastructure is ready
      # events.sh emit system-restart "${additional_params[@]}"
      return 0
      ;;
    $EC_SUCCESS_SYSTEM_INFO_RETRIEVED)
      # No event emission needed for info retrieval
      return 0
      ;;
    $EC_SUCCESS_NETWORK_PORT_CHECKED | $EC_SUCCESS_NETWORK_PORT_FREE | $EC_SUCCESS_NETWORK_PORT_IN_USE)
      # No event emission needed for port checks
      return 0
      ;;
    $EC_SUCCESS_BLUEPRINT_LISTED | $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED | $EC_SUCCESS_BLUEPRINT_FOUND | $EC_SUCCESS_BLUEPRINT_VALIDATED)
      # No event emission needed for blueprint read-only operations
      return 0
      ;;
    *)
      # No event needed for other exit codes
      return 0
      ;;
  esac
}

export -f __dispatch_event_from_exit_code

# Mark module as loaded
declare -g KGSM_EVENTS_LIBRARY_LOADED=1
export KGSM_EVENTS_LIBRARY_LOADED
