#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# =============================================================================
# Port Monitor Watcher Logic Library
# =============================================================================
# Pure logic functions for port monitoring readiness detection.
# No user-facing I/O - returns only exit codes.

if [[ -n "${KGSM_LOGIC_WATCHERS_PORTS_LOADED:-}" ]]; then
  return 0
fi

# Extract the first port from UFW-style port format
# Args: $1 = ufw_ports (UFW-style port definitions, pipe-separated)
# Returns: Echoes the first port number, returns EC_SUCCESS on success
#          Returns EC_INVALID_ARG on invalid format
function __logic_extract_first_port() {
  local ufw_ports="$1"

  if [[ -z "$ufw_ports" ]]; then
    return $EC_MISSING_ARG
  fi

  # Split by | and get the first port definition
  local first_def
  first_def=$(echo "$ufw_ports" | cut -d'|' -f1)

  # Handle different formats:
  # Port range with protocol: 26900:26903/tcp -> 26900
  # Single port with protocol: 7777/udp -> 7777
  # Port range without protocol: 26900:26903 -> 26900
  # Single port without protocol: 22420 -> 22420

  if [[ "$first_def" =~ ^([0-9]+):([0-9]+)(/[a-z]+)?$ ]]; then
    # Port range - return start port
    echo "${BASH_REMATCH[1]}"
    return $EC_SUCCESS
  elif [[ "$first_def" =~ ^([0-9]+)(/[a-z]+)?$ ]]; then
    # Single port - return the port
    echo "${BASH_REMATCH[1]}"
    return $EC_SUCCESS
  else
    return $EC_INVALID_ARG
  fi
}

export -f __logic_extract_first_port

# Execute port monitoring
# Args: $1 = instance (instance name with .ini)
#       $2 = server_pid (PID of server process or container ID)
#       $3 = port_to_check (port number to monitor)
#       $4 = timeout_seconds (timeout in seconds)
#       $5 = watcher_log_file (path to watcher log file)
#       $6 = check_interval (interval between checks in seconds)
# Returns: EC_SUCCESS_INSTANCE_READY on port active
#          EC_WATCHER_TIMEOUT on timeout
#          EC_ERROR if server process stopped
#          Other error codes on failure
function __logic_execute_port_watch() {
  local instance="$1"
  local server_pid="$2"
  local port_to_check="$3"
  local timeout_seconds="${4:-600}"
  local watcher_log_file="$5"
  local check_interval="${6:-5}"

  __print_info_file_only "$watcher_log_file" "Watching for port '$port_to_check' to become active"
  __print_info_file_only "$watcher_log_file" "Instance: '$instance', PID: $server_pid, Timeout: ${timeout_seconds}s"

  # Use timeout to enforce global timeout with port checking loop
  if timeout "${timeout_seconds}s" bash -c '
    instance="$1"
    server_pid="$2"
    port_to_check="$3"
    check_interval="$4"

    while true; do
      # Check if server process/container is still running
      if [[ "$server_pid" =~ ^[0-9]+$ ]]; then
        # Regular PID - check if process is running
        if ! kill -0 "$server_pid" 2>/dev/null; then
          echo "Server process stopped"
          exit 1
        fi
      else
        # Docker container ID - check container status
        if ! docker inspect "$server_pid" --format="{{.State.Status}}" 2>/dev/null | grep -q "running"; then
          echo "Server container stopped"
          exit 1
        fi
      fi

      # Check if port is active
      if ss -lntu | grep -q ":${port_to_check}\b"; then
        echo "Port is active"
        exit 0
      fi

      sleep "$check_interval"
    done
  ' -- "$instance" "$server_pid" "$port_to_check" "$check_interval"; then
    __print_success_file_only "$watcher_log_file" "Instance '$instance' is ready. Port '$port_to_check' is active."
    return $EC_SUCCESS_INSTANCE_READY
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      __print_warning_file_only "$watcher_log_file" "Port watch for '$instance' timed out after ${timeout_seconds}s"
      return $EC_WATCHER_TIMEOUT
    elif [[ $exit_code -eq 1 ]]; then
      __print_info_file_only "$watcher_log_file" "Server process for '$instance' stopped. Aborting port watch."
      return $EC_ERROR
    else
      __print_error_file_only "$watcher_log_file" "Port watch for '$instance' failed with exit code $exit_code"
      return $exit_code
    fi
  fi
}

export -f __logic_execute_port_watch

# Test port monitoring configuration
# Args: $1 = instance_config_file (path to instance .ini file)
# Returns: Echoes "port_count|active_count", returns EC_SUCCESS
#          Returns error codes on failure
function __logic_test_port_status() {
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

  local all_ports="$instance_ports"
  if [[ -z "$all_ports" ]]; then
    return $EC_WATCHER_PORT_NOT_ACTIVE
  fi

  local port_count=0
  local active_count=0

  # Split by | and process each port definition
  IFS='|' read -ra port_defs <<< "$all_ports"
  for port_def in "${port_defs[@]}"; do
    # Extract port number from this definition
    local port_num
    if [[ "$port_def" =~ ^([0-9]+):([0-9]+)(/[a-z]+)?$ ]]; then
      # Port range - check start port for simplicity
      port_num="${BASH_REMATCH[1]}"
      ((port_count++))
    elif [[ "$port_def" =~ ^([0-9]+)(/[a-z]+)?$ ]]; then
      # Single port
      port_num="${BASH_REMATCH[1]}"
      ((port_count++))
    else
      continue
    fi

    if ss -lntu 2>/dev/null | grep -q ":${port_num}\b"; then
      ((active_count++))
    fi
  done

  echo "${port_count}|${active_count}"
  return $EC_SUCCESS
}

export -f __logic_test_port_status

# Get port watcher status data
# Args: $1 = instance_config_file (path to instance .ini file)
# Returns: Echoes status data in format: ports|first_port|port_count|active_count
#          Returns EC_SUCCESS on success, error codes on failure
function __logic_get_port_status_data() {
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

  local all_ports="$instance_ports"
  local first_port=""
  local port_count=0
  local active_count=0

  if [[ -n "$all_ports" ]]; then
    first_port=$(__logic_extract_first_port "$all_ports" 2>/dev/null) || first_port=""

    # Get port status
    local status_data
    status_data=$(__logic_test_port_status "$instance_config_file" 2>/dev/null) || status_data="0|0"
    port_count=$(echo "$status_data" | cut -d'|' -f1)
    active_count=$(echo "$status_data" | cut -d'|' -f2)
  fi

  echo "${all_ports}|${first_port}|${port_count}|${active_count}"
  return $EC_SUCCESS
}

export -f __logic_get_port_status_data

# Mark module as loaded
declare -g KGSM_LOGIC_WATCHERS_PORTS_LOADED=1
export KGSM_LOGIC_WATCHERS_PORTS_LOADED
