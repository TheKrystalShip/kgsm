#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# =============================================================================
# Log Pattern Watcher Logic Library
# =============================================================================
# Pure logic functions for log pattern matching readiness detection.
# No user-facing I/O - returns only exit codes.

if [[ -n "${KGSM_LOGIC_WATCHERS_LOGS_LOADED:-}" ]]; then
  return 0
fi

# Execute log pattern watching
# Args: $1 = instance (instance name with .ini)
#       $2 = server_pid (PID of server process)
#       $3 = ready_pattern (regex pattern to match)
#       $4 = log_file (path to log file)
#       $5 = timeout_seconds (timeout in seconds)
#       $6 = watcher_log_file (path to watcher log file)
# Returns: EC_SUCCESS_INSTANCE_READY on pattern match
#          EC_WATCHER_TIMEOUT on timeout
#          EC_ERROR if server process stopped
#          Other error codes on failure
function __logic_execute_log_watch() {
  local instance="$1"
  local server_pid="$2"
  local ready_pattern="$3"
  local log_file="$4"
  local timeout_seconds="${5:-600}"
  local watcher_log_file="$6"

  __print_info_file_only "$watcher_log_file" "Watching log file '$log_file' for pattern '$ready_pattern'"
  __print_info_file_only "$watcher_log_file" "Instance: '$instance', PID: $server_pid, Timeout: ${timeout_seconds}s"

  # Use timeout to enforce global timeout and tail to follow the log
  if timeout "${timeout_seconds}s" bash -c '
    tail -n 50 -f --pid="$1" "$2" | grep --line-buffered -q -m 1 -e "$3"
  ' -- "$server_pid" "$log_file" "$ready_pattern"; then
    __print_success_file_only "$watcher_log_file" "Instance '$instance' is ready. Log pattern matched: '$ready_pattern'"
    return $EC_SUCCESS_INSTANCE_READY
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      __print_warning_file_only "$watcher_log_file" "Log watch for '$instance' timed out after ${timeout_seconds}s"
      return $EC_WATCHER_TIMEOUT
    elif [[ $exit_code -eq 1 ]]; then
      __print_info_file_only "$watcher_log_file" "Server process for '$instance' stopped. Aborting log watch."
      return $EC_ERROR
    else
      __print_error_file_only "$watcher_log_file" "Log watch for '$instance' failed with exit code $exit_code"
      return $exit_code
    fi
  fi
}

export -f __logic_execute_log_watch

# Test log pattern matching configuration
# Args: $1 = instance_config_file (path to instance .ini file)
# Returns: EC_SUCCESS if pattern found in current log
#          EC_WATCHER_PATTERN_NOT_FOUND if not found
#          EC_WATCHER_LOG_FILE_MISSING if log file doesn't exist
#          Other error codes on failure
function __logic_test_log_pattern() {
  local instance_config_file="$1"

  if [[ -z "$instance_config_file" ]]; then
    return $EC_MISSING_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Source the instance configuration
  # shellcheck disable=SC1090
  source "$instance_config_file" 2>/dev/null || return $EC_FAILED_SOURCE

  local ready_pattern="$instance_startup_success_regex"
  if [[ -z "$ready_pattern" ]]; then
    return $EC_WATCHER_PATTERN_NOT_FOUND
  fi

  if [[ ! -f "$instance_log_file" ]]; then
    return $EC_WATCHER_LOG_FILE_MISSING
  fi

  # Check if pattern exists in current log
  if grep -q "$ready_pattern" "$instance_log_file" 2>/dev/null; then
    return $EC_SUCCESS
  else
    return $EC_WATCHER_PATTERN_NOT_FOUND
  fi
}

export -f __logic_test_log_pattern

# Get log watcher status data
# Args: $1 = instance_config_file (path to instance .ini file)
# Returns: Echoes status data in format: pattern|log_file|log_exists|pattern_found
#          Returns EC_SUCCESS on success, error codes on failure
function __logic_get_log_status_data() {
  local instance_config_file="$1"

  if [[ -z "$instance_config_file" ]]; then
    return $EC_MISSING_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Source the instance configuration
  # shellcheck disable=SC1090
  source "$instance_config_file" 2>/dev/null || return $EC_FAILED_SOURCE

  local ready_pattern="$instance_startup_success_regex"
  local log_file="$instance_log_file"
  local log_exists="false"
  local pattern_found="false"

  if [[ -f "$log_file" ]]; then
    log_exists="true"
    if [[ -n "$ready_pattern" ]] && grep -q "$ready_pattern" "$log_file" 2>/dev/null; then
      pattern_found="true"
    fi
  fi

  echo "${ready_pattern}|${log_file}|${log_exists}|${pattern_found}"
  return $EC_SUCCESS
}

export -f __logic_get_log_status_data

# Mark module as loaded
declare -g KGSM_LOGIC_WATCHERS_LOGS_LOADED=1
export KGSM_LOGIC_WATCHERS_LOGS_LOADED
