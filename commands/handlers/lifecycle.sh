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
# - Standard error codes: EC_INVALID_ARG, EC_INVALID_CONFIG, EC_SYSTEMD, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_LIFECYCLE_LOADED}" ]]; then
  return 0
fi

# Success event exit codes are now centralized in core/errors.sh
# They are automatically available through the bootstrap process

# Helper function to extract lifecycle manager from instance config
# Args: $1 = _instance_config_file
# Returns: lifecycle_manager value to stdout, 0 on success, error code on failure
function __get_lifecycle_manager() {
  local _instance_config_file="$1"

  if [[ -z "$_instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  local lifecycle_manager
  lifecycle_manager=$(__get_config_value "$_instance_config_file" "lifecycle_manager" 2> /dev/null)

  if [[ -z "$lifecycle_manager" ]]; then
    return $EC_INVALID_CONFIG
  fi

  echo "$lifecycle_manager"
  return 0
}

export -f __get_lifecycle_manager

# Starts an instance using the appropriate lifecycle manager
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

  # Extract lifecycle manager from config
  local lifecycle_manager
  lifecycle_manager=$(__get_lifecycle_manager "$_instance_config_file" 2> /dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Execute type-specific logic
  case "$lifecycle_manager" in
    systemd)
      __logic_start_systemd_instance "$_instance_name" "$_instance_config_file"
      return $?
      ;;
    standalone)
      __logic_start_standalone_instance "$_instance_name" "$_instance_config_file"
      return $?
      ;;
    *)
      return $EC_INVALID_CONFIG
      ;;
  esac
}

export -f __logic_instance_start
# Helper function to start systemd instance
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 211 on success, error codes on failure
function __logic_start_systemd_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

  # Determine if sudo is needed
  local sudo_cmd=""
  [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo -E"

  # Start systemd service - suppress output since this is pure logic
  if ! $sudo_cmd systemctl start "${_instance_name%.ini}" --no-pager > /dev/null 2>&1; then
    return $EC_SYSTEMD
  fi

  return $EC_SUCCESS_INSTANCE_STARTED
}

export -f __logic_start_systemd_instance

# Helper function to start standalone instance
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 211 on success, error codes on failure
function __logic_start_standalone_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

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

  # Extract lifecycle manager from config
  local lifecycle_manager
  lifecycle_manager=$(__get_lifecycle_manager "$_instance_config_file")
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Execute type-specific logic
  case "$lifecycle_manager" in
    systemd)
      __logic_stop_systemd_instance "$_instance_name" "$_instance_config_file"
      return $?
      ;;
    standalone)
      __logic_stop_standalone_instance "$_instance_name" "$_instance_config_file"
      return $?
      ;;
    *)
      return $EC_INVALID_CONFIG
      ;;
  esac
}

export -f __logic_instance_stop

# Helper function to stop systemd instance
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 212 on success, error codes on failure
function __logic_stop_systemd_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

  # Determine if sudo is needed
  local sudo_cmd=""
  [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo -E"

  # Stop systemd service - suppress output since this is pure logic
  if ! $sudo_cmd systemctl stop "${_instance_name%.ini}" --no-pager > /dev/null 2>&1; then
    return $EC_SYSTEMD
  fi

  return $EC_SUCCESS_INSTANCE_STOPPED
}

export -f __logic_stop_systemd_instance

# Helper function to stop standalone instance
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 212 on success, error codes on failure
function __logic_stop_standalone_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

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
  local lifecycle_manager
  local exit_code

  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Extract lifecycle manager from config
  lifecycle_manager=$(__get_lifecycle_manager "$_instance_config_file")
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Execute type-specific logic
  case "$lifecycle_manager" in
    systemd)
      __logic_is_active_systemd_instance "$_instance_name" "$_instance_config_file"
      return $?
      ;;
    standalone)
      __logic_is_active_standalone_instance "$_instance_name" "$_instance_config_file"
      return $?
      ;;
    *)
      return $EC_INVALID_CONFIG
      ;;
  esac
}

export -f __logic_instance_is_active

# Helper function to check if systemd instance is active
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 0 if active, 1 if inactive
function __logic_is_active_systemd_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

  # Check systemd service status - suppress output since this is pure logic
  local is_active
  is_active=$(systemctl is-active "${_instance_name%.ini}" --no-pager 2> /dev/null)

  [[ "$is_active" == "active" ]] && return 0
  return 1
}

export -f __logic_is_active_systemd_instance

# Helper function to check if standalone instance is active
# Args: $1 = _instance_name, $2 = _instance_config_file
# Returns: 0 if active, 1 if inactive, error codes on failure
function __logic_is_active_standalone_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"

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
  "$management_file" --is-active > /dev/null 2>&1
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
  local lifecycle_manager
  local exit_code

  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Extract lifecycle manager from config
  lifecycle_manager=$(__get_lifecycle_manager "$_instance_config_file")
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

  # Call the management script's status function with appropriate flags
  if [[ -n "$json_format" && -n "$fast_mode" ]]; then
    "$management_file" --status --json --fast
  elif [[ -n "$json_format" ]]; then
    "$management_file" --status --json
  elif [[ -n "$fast_mode" ]]; then
    "$management_file" --status --fast
  else
    "$management_file" --status
  fi

  return $?
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
  local lifecycle_manager
  local exit_code

  # Load instance configuration using centralized validation
  _instance_config_file=$(validate_instance_name "$_instance_name" 2> /dev/null)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Extract lifecycle manager from config
  lifecycle_manager=$(__get_lifecycle_manager "$_instance_config_file")
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Execute type-specific logic
  case "$lifecycle_manager" in
    systemd)
      __logic_logs_systemd_instance "$_instance_name" "$_instance_config_file" "$follow_flag" "$line_count"
      return $?
      ;;
    standalone)
      __logic_logs_standalone_instance "$_instance_name" "$_instance_config_file" "$follow_flag" "$line_count"
      return $?
      ;;
    *)
      return $EC_INVALID_CONFIG
      ;;
  esac
}

export -f __logic_instance_logs

# Helper function to display systemd instance logs
# Args: $1 = _instance_name, $2 = _instance_config_file, $3 = follow_flag, $4 = line_count
# Returns: 0 on success, error codes on failure
function __logic_logs_systemd_instance() {
  local _instance_name="$1"
  local _instance_config_file="$2"
  local follow_flag="$3"
  local line_count="$4"

  # Display logs using journalctl
  if [[ "$follow_flag" == "true" ]]; then
    journalctl -n "$line_count" -fu "${_instance_name%.ini}"
  else
    journalctl -n "$line_count" -u "${_instance_name%.ini}" --no-pager
  fi

  return $?
}

export -f __logic_logs_systemd_instance

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
    "$management_file" --logs --follow --tail "$line_count"
  else
    "$management_file" --logs --tail "$line_count"
  fi

  return $?
}

export -f __logic_logs_standalone_instance

# Mark module as loaded
declare -g KGSM_LOGIC_LIFECYCLE_LOADED=1
export KGSM_LOGIC_LIFECYCLE_LOADED
