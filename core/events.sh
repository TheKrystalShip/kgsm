#!/usr/bin/env bash

# Disable SC2254 globally:
# Exit code variables are guaranteed to be numeric and safe for use in case statements.
# shellcheck disable=SC2254

# KGSM Event Dispatcher Library
#
# This module provides centralized event dispatching based on exit codes
# to eliminate code duplication across modules and kgsm.sh.
#
# The dispatcher maps success-event exit codes (200+) to specific event emissions.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Success event exit codes are now centralized in core/errors.sh
# They are automatically available through the bootstrap process

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
      events.sh emit instance-directories-created "$instance_name"
      return $?
      ;;
    $EC_SUCCESS_DIRECTORIES_REMOVED)
      events.sh emit instance-directories-removed "$instance_name"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_CREATED)
      events.sh emit instance-created "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_REMOVED)
      events.sh emit instance-removed "$instance_name"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_STARTED)
      events.sh emit instance-started "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_STOPPED)
      events.sh emit instance-stopped "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_RESTARTED)
      events.sh emit instance-restarted "$instance_name" "${additional_params[@]}"
      return $?
      ;;
    $EC_SUCCESS_INSTANCE_READY)
      events.sh emit instance-ready "$instance_name"
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
export KGSM_EVENTS_LIBRARY_LOADED=1
