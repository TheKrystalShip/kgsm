#!/usr/bin/env bash

# KGSM Pure Logic Layer - Lifecycle Management
#
# This module contains pure business logic functions for lifecycle operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - 211: Instance started successfully (emit instance-started)
# - 212: Instance stopped successfully (emit instance-stopped)
# - 213: Instance restarted successfully (emit instance-restarted)
# - Standard error codes: EC_INVALID_ARG, EC_INVALID_CONFIG, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_LIFECYCLE_LOADED}" ]]; then
  return 0
fi

# Load watchdog routing logic (native lifecycle -> resident supervisor daemon
# when present). These helpers self-gate on the daemon's availability, so the
# direct management-script path is used unchanged when it is absent.
if [[ -z "${KGSM_LOGIC_WATCHDOG_LOADED}" ]]; then
  # shellcheck source=watchdog.sh
  source "$(__find_command_handler watchdog.sh)" || return $EC_FAILED_SOURCE
fi

# Load firewall integration logic (__logic_ensure_firewall_open), so a bring-up
# can re-assert the instance's host firewall rule before the server comes up.
if [[ -z "${KGSM_LOGIC_FILES_FIREWALL_LOADED}" ]]; then
  # shellcheck source=files.firewall.sh
  source "$(__find_command_handler files.firewall.sh)" || return $EC_FAILED_SOURCE
fi

# Success event exit codes are now centralized in core/errors.sh
# They are automatically available through the bootstrap process

# Starts an instance
# Args: $1 = _instance_name
# Returns: 211 on success (triggers instance-started event), error codes on failure
function __logic_instance_start() {
  local _instance_name="$1"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Load instance configuration using centralized validation
  local _instance_config_file
  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Open the host firewall for the run that is starting — an instance's ports are
  # open exactly while it is running. A no-op for an instance with firewall
  # management off or no ports, and deliberately not fatal: a firewall authority
  # that is down must not keep a game server off the air, and the authority's own
  # stderr already says so.
  __logic_ensure_firewall_open "$_instance_config_file"

  # Native instances are the only kind KGSM starts here (the watchdog, or the
  # direct management script when it is absent). Container instances run their own
  # path; systemd is no longer a lifecycle manager.
  __logic_start_standalone_instance "$_instance_name" "$_instance_config_file"
  return $?
}

export -f __logic_instance_start

# Helper function to start standalone instance
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 211 on success, error codes on failure
function __logic_start_standalone_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

  # Route to the resident watchdog when present + ready; it owns the cgroup
  # spawn and crash-restart. Falls back to the direct management-script path
  # below when the daemon is absent/unreachable.
  #
  # Known limitation (orphan re-adoption, a documented future gap): if this exact
  # instance is ALREADY running as a direct-path orphan (started before the daemon
  # existed) and an operator runs `start` again, the daemon does not see that
  # process and will spawn a second copy. The normal flow — instances managed
  # through the daemon from creation — is unaffected, and `restart` is safe because
  # its stop half (above) tears the orphan down first before this start runs.
  if __watchdog_available; then
    __watchdog_dispatch_lifecycle start "$_instance_name"
    return $?
  fi

  # Get management file from config
  local management_file
  management_file=$(__get_config_value "$_instance_config_file" "management_file" 2> /dev/null)

  if [[ -z "$management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Start standalone process - suppress output since this is pure logic
  if ! "$management_file" start -d > /dev/null 2>&1; then
    return $EC_ERROR
  fi

  return $EC_SUCCESS_INSTANCE_STARTED
}

export -f __logic_start_standalone_instance

# Stops an instance using the appropriate lifecycle manager
# Args: $1 = _instance_name
# Returns: 212 on success (triggers instance-stopped event), error codes on failure
function __logic_instance_stop() {
  local _instance_name="$1"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Load instance configuration using centralized validation
  local _instance_config_file
  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Native instances only (watchdog, or the direct management script when absent).
  __logic_stop_standalone_instance "$_instance_name" "$_instance_config_file"
  local _stop_rc=$?

  # Release the ports the run held. Only on a stop that actually happened: a
  # refused or failed stop leaves the server running, and closing its ports would
  # strand a live instance behind a shut door. A crash never reaches here, which
  # is correct — the restart that follows still needs the ports.
  if [[ $_stop_rc -eq $EC_SUCCESS_INSTANCE_STOPPED ]]; then
    __logic_ensure_firewall_closed "$_instance_config_file"
  fi

  return $_stop_rc
}

export -f __logic_instance_stop

# Helper function to stop standalone instance
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 212 on success, error codes on failure
function __logic_stop_standalone_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

  # Route to the resident watchdog when present + ready AND it actually tracks this
  # instance: it records desired-state = stopped (so it will not crash-restart) and
  # performs the graceful drain -> cgroup.kill teardown. An instance the daemon does
  # NOT track (e.g. an orphan started via the direct path before the daemon existed)
  # falls through to the direct PID-file stop below — otherwise the daemon, which
  # only sees its own cgroups, would report success while the orphan kept running.
  if __watchdog_available && __watchdog_tracks "$_instance_name"; then
    __watchdog_dispatch_lifecycle stop "$_instance_name"
    return $?
  fi

  # Get management file from config
  local management_file
  management_file=$(__get_config_value "$_instance_config_file" "management_file" 2> /dev/null)
  local result=$?

  if [[ -z "$management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Stop standalone process - suppress output since this is pure logic
  if ! "$management_file" stop > /dev/null 2>&1; then
    return $EC_ERROR
  fi

  return $EC_SUCCESS_INSTANCE_STOPPED
}

export -f __logic_stop_standalone_instance
# Restarts an instance by stopping then starting it
# Args: $1 = _instance_name
# Returns: 213 on success (triggers instance-restarted event), error codes on failure
function __logic_instance_restart() {
  local _instance_name="$1"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Stop the instance first
  __logic_instance_stop "$_instance_name"
  local stop_result=$?

  # If stop failed, return the error
  if [[ $stop_result -ne $EC_SUCCESS_INSTANCE_STOPPED ]]; then
    return $stop_result
  fi

  # Start the instance
  __logic_instance_start "$_instance_name"
  local start_result=$?

  # If start failed, return the error
  if [[ $start_result -ne $EC_SUCCESS_INSTANCE_STARTED ]]; then
    return $start_result
  fi

  # Return restart success event code
  return $EC_SUCCESS_INSTANCE_RESTARTED
}

export -f __logic_instance_restart

# Checks if an instance is active (simple running check)
# Args: $1 = _instance_name
# Returns: 0 if active, 1 if inactive, error codes on failure
function __logic_instance_is_active() {
  local _instance_name="$1"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Load instance configuration using centralized validation
  local _instance_config_file
  local exit_code

  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  __logic_is_active_standalone_instance "$_instance_name" "$_instance_config_file"
  return $?
}

export -f __logic_instance_is_active

# Helper function to check if standalone instance is active
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 0 if active, 1 if inactive, error codes on failure
function __logic_is_active_standalone_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

  # When the watchdog supervises this instance it is the source of truth for
  # liveness: the daemon spawns the process itself and writes no PID file, so the
  # management script's PID check would be stale. A "not tracked" result (the
  # instance was started before the daemon existed) falls through to the direct
  # check below.
  if __watchdog_available; then
    __watchdog_is_active "$_instance_name"
    case $? in
      0) return 0 ;;
      1) return 1 ;;
      *) ;; # unknown / not tracked -> direct check below
    esac
  fi

  # Get management file from config
  local management_file
  management_file=$(__get_config_value "$_instance_config_file" "management_file" 2> /dev/null)
  local result=$?

  if [[ $result -ne 0 ]]; then
    return $result
  fi

  if [[ -z "$management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Check standalone process status - suppress stderr since this is pure logic
  "$management_file" is-active > /dev/null 2>&1
  return $?
}

export -f __logic_is_active_standalone_instance

# Gets comprehensive status information for an instance
# Args: $1 = _instance_name, $2 = json_format (optional), $3 = fast_mode (optional)
# Returns: 0 on success, error codes on failure
# Outputs: status information to stdout
function __logic_instance_status() {
  local _instance_name="$1"
  local json_format="${2:-}"
  local fast_mode="${3:-}"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Load instance configuration using centralized validation
  local _instance_config_file
  local exit_code

  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Get management file from config
  local management_file
  management_file=$(__get_config_value "$_instance_config_file" "management_file" 2> /dev/null)
  local result=$?
  if [[ -z "$management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Call the management script's status function, then reconcile its run-state
  # with the watchdog — the authority for the native instances it cgroup-spawns
  # (which carry no PID file, so the management script's own check reads them as
  # inactive). This keeps `status` consistent with is-active; see
  # __overlay_status_active. A no-op for orphans, containers, and a daemon-down
  # host (empty active value -> output passed through unchanged).
  local _raw _rc _active _pid
  _raw=$("$management_file" status ${json_format:+--json} ${fast_mode:+--fast})
  _rc=$?
  _active=$(__watchdog_active_value "$_instance_name")
  _pid=$(__watchdog_pid_value "$_instance_name")
  _raw=$(__overlay_status_active "$json_format" "$_active" "$_raw")
  __overlay_process_pid "$json_format" "$_pid" "$_raw"

  return $_rc
}

export -f __logic_instance_status

# Displays logs for an instance
# Args: $1 = _instance_name, $2 = follow_flag (true/false), $3 = line_count (optional, default 10)
# Returns: 0 on success, error codes on failure
# Outputs: log content to stdout
function __logic_instance_logs() {
  local _instance_name="$1"
  local follow_flag="${2:-false}"
  local line_count="${3:-10}"

  # Validate required parameters
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local _instance_config_file
  local exit_code

  # Load instance configuration using centralized validation
  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  __logic_logs_standalone_instance "$_instance_name" "$_instance_config_file" "$follow_flag" "$line_count"
  return $?
}

export -f __logic_instance_logs

# Helper function to display standalone instance logs
# Args: $1 = _instance_name, $2 = _instance_config_file, $3 = follow_flag, $4 = line_count
# Returns: 0 on success, error codes on failure
function __logic_logs_standalone_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"
  local follow_flag="$3"
  local line_count="$4"

  # Get management file from config
  local management_file
  management_file=$(__get_config_value "$_instance_config_file" "management_file" 2> /dev/null)
  local result=$?

  if [[ $result -ne 0 ]]; then
    return $EC_INVALID_CONFIG
  fi

  if [[ -z "$management_file" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Display logs using management script with appropriate parameters
  if [[ "$follow_flag" == "true" ]]; then
    "$management_file" logs --follow --tail "$line_count"
  else
    "$management_file" logs --tail "$line_count"
  fi

  return $?
}

export -f __logic_logs_standalone_instance

# Mark module as loaded
declare -g KGSM_LOGIC_LIFECYCLE_LOADED=1
export KGSM_LOGIC_LIFECYCLE_LOADED
