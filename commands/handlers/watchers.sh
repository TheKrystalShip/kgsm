#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# =============================================================================
# Watcher Orchestration Logic Library
# =============================================================================
# Pure logic functions for watcher strategy determination and orchestration.
# No user-facing I/O - returns only exit codes.

# Determine the appropriate watcher strategy for an instance
# Args: $1 = instance_config_file (path to instance .ini file)
# Returns: Echoes "logs" or "ports", returns EC_OKAY on success
#          Returns EC_WATCHER_NO_STRATEGY if no strategy configured
function __logic_determine_strategy() {
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
  local all_ports="$instance_ports"

  # Strategy 1: Log Pattern Matching (preferred)
  if [[ -n "$ready_pattern" ]]; then
    echo "logs"
    return $EC_OKAY
  fi

  # Strategy 2: Port Monitoring (fallback)
  if [[ -n "$all_ports" ]]; then
    echo "ports"
    return $EC_OKAY
  fi

  # No strategy available
  return $EC_WATCHER_NO_STRATEGY
}

export -f __logic_determine_strategy

# Mark module as loaded
export KGSM_LOGIC_WATCHERS_LOADED=1
