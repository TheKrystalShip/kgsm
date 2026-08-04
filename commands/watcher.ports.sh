#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

# Load logic library
logic_library=$(__find_command_handler watchers.ports.sh)
# shellcheck source=handlers/watchers.ports.sh
source "$logic_library" || {
  __print_error "Failed to load port watcher logic library"
  exit $EC_FAILED_SOURCE
}

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Port Monitor Watcher for Krystal Game Server Manager${END}

Monitors network ports to detect when game server instances become ready for players.
Checks for port availability using netstat/ss to determine server readiness.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance> [options]

${UNDERLINE}Commands:${END}
  watch <instance>            Start watching ports for readiness
  test <instance>             Test port monitoring configuration
  status <instance>           Show port watcher configuration status
  help [command]              Display help information

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --detach                    Run watcher in detached background process

${UNDERLINE}Configuration:${END}
  • ports                     UFW-style port definitions (pipe-separated)
  • Supports ranges (27015:27020/udp) and single ports (7777/tcp)
  • Monitors first port in the list for readiness detection
  • Check interval: ${config_watcher_ports_check_interval_seconds:-5} seconds

${UNDERLINE}Examples:${END}
  ${self} watch valheim-server-01
  ${self} watch factorio-space-age --detach
  ${self} test minecraft-survival
  ${self} status terraria-modded
  ${self} help watch

${UNDERLINE}Notes:${END}
  • Uses 'ss' command for efficient port monitoring
  • Monitors TCP and UDP ports simultaneously
  • Automatically stops when server process terminates
  • Exits with success when port becomes active
  • Supports multiple ports but monitors first one for readiness
  • Emits instance-ready event when port becomes available
"
}

function usage_watch() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Watch Ports for Readiness${END}

Monitors network ports for the instance to detect when the server becomes ready.

${UNDERLINE}Usage:${END}
  ${self} watch <instance> [--detach]

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Options:${END}
  --detach                    Run in detached background process
  --help                      Display this help information

${UNDERLINE}Description:${END}
  Monitors the first configured port using 'ss' command and waits for it to
  become active. When the port is bound by the server process, emits an
  instance-ready event and exits successfully.

  The watcher automatically stops if:
    • The port becomes active (success)
    • The server process terminates
    • The global timeout is reached (default: 600 seconds)

  Port availability is checked every ${config_watcher_ports_check_interval_seconds:-5} seconds.

  When run with --detach, the watcher runs as a background process and outputs
  to logs/watcher-<instance>.log instead of the terminal.

${UNDERLINE}Examples:${END}
  ${self} watch factorio-server
  ${self} watch valheim-server --detach

${UNDERLINE}Requirements:${END}
  • Instance must have ports configured
  • 'ss' command must be available (iproute2 package)
  • Server process must be running
"
}

function usage_test() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Test Port Monitoring Configuration${END}

Tests if the configured ports are currently active.

${UNDERLINE}Usage:${END}
  ${self} test <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Checks all configured ports to see if they are currently active (bound).
  Useful for validating port configuration and debugging watcher behavior.

  This is a one-time check of the current port status, not a continuous monitor.

${UNDERLINE}Examples:${END}
  ${self} test factorio-server
  ${self} test minecraft-survival

${UNDERLINE}Requirements:${END}
  • Instance must have ports configured
  • 'ss' command must be available
"
}

function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Show Port Watcher Status${END}

Displays configuration and current state of port monitor watcher for an instance.

${UNDERLINE}Usage:${END}
  ${self} status <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Shows detailed information about the port watcher configuration including:
    • Configured ports
    • Primary port being monitored
    • Current port activity status
    • Check interval and timeout configuration
    • Dependency availability (ss command)

${UNDERLINE}Examples:${END}
  ${self} status factorio-server
  ${self} status valheim-server
"
}

# Command: watch <instance> [--detach]
function _cmd_watch() {
  local instance_name=""
  local detach=false

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_watch
        return 0
        ;;
      --detach)
        detach=true
        shift
        ;;
      *)
        if [[ -z "$instance_name" ]]; then
          instance_name="$1"
          shift
        else
          __print_error "Unknown argument: $1"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
  done

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    usage_watch
    return $EC_MISSING_ARG
  fi

  # Find instance config file using standard finder
  local instance_config_file
  if ! instance_config_file=$(__find_instance_config "$instance_name" 2>/dev/null); then
    __print_error "Instance '$instance_name' not found"
    return $EC_NOT_FOUND
  fi

  # If detached, spawn background process
  if [[ "$detach" == true ]]; then
    (
      _cmd_watch "$instance_name"
    ) &
    disown
    __print_success "Detached port watcher for '$instance_name' has been launched"
    return 0
  fi

  # Source the instance configuration
  __source_instance "$instance"

  # Create watcher log file path
  local watcher_log_file="$LOGS_SOURCE_DIR/watcher-${instance%.ini}.log"

  # Validate ports are configured
  local all_ports="$instance_ports"
  if [[ -z "$all_ports" ]]; then
    __print_error_file_only "$watcher_log_file" "No ports configured for '$instance_name'"
    __print_error_file_only "$watcher_log_file" "Set 'ports' in the instance configuration"
    return $EC_WATCHER_PORT_NOT_ACTIVE
  fi

  # Get the first port for monitoring
  local first_port
  first_port=$(__logic_extract_first_port "$all_ports")
  local extract_result=$?

  if [[ $extract_result -ne $EC_SUCCESS || -z "$first_port" ]]; then
    __print_error_file_only "$watcher_log_file" "Failed to extract first port from configuration: '$all_ports'"
    return $EC_INVALID_ARG
  fi

  # Wait for PID file to be created (server startup)
  local server_pid
  local pid_file="$instance_pid_file"
  local pid_wait_timeout=10

  __print_info_file_only "$watcher_log_file" "Waiting for PID file: $pid_file"
  while [[ ! -f "$pid_file" && $pid_wait_timeout -gt 0 ]]; do
    sleep 1
    ((pid_wait_timeout--))
  done

  if [[ ! -f "$pid_file" ]]; then
    __print_error_file_only "$watcher_log_file" "PID file '$pid_file' was not created within timeout"
    return $EC_FILE_NOT_FOUND
  fi

  if ! server_pid=$(< "$pid_file" 2> /dev/null); then
    __print_error_file_only "$watcher_log_file" "Failed to read server PID from '$pid_file'"
    return $EC_FILE_NOT_FOUND
  fi

  if [[ -z "$server_pid" ]]; then
    __print_error_file_only "$watcher_log_file" "Server PID is empty"
    return $EC_ERROR
  fi

  __print_info_file_only "$watcher_log_file" "Server PID: $server_pid"
  __print_info_file_only "$watcher_log_file" "Monitoring port: $first_port"

  # Execute the port watch
  local timeout_seconds="${config_watcher_global_timeout_seconds:-600}"
  local check_interval="${config_watcher_ports_check_interval_seconds:-5}"
  __logic_execute_port_watch "$instance" "$server_pid" "$first_port" "$timeout_seconds" "$watcher_log_file" "$check_interval"
  local exit_code=$?

  # Handle exit codes
  case $exit_code in
    $EC_SUCCESS_INSTANCE_READY)
      # Emit event
      __emit_event instance-ready "${instance%.ini}"
      return 0
      ;;
    $EC_WATCHER_TIMEOUT)
      return $exit_code
      ;;
    $EC_ERROR)
      return $exit_code
      ;;
    *)
      __print_error_file_only "$watcher_log_file" "Unexpected error during port watch"
      return $exit_code
      ;;
  esac
}

# Command: test <instance>
function _cmd_test() {
  local instance_name=""

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_test
        return 0
        ;;
      *)
        if [[ -z "$instance_name" ]]; then
          instance_name="$1"
          shift
        else
          __print_error "Unknown argument: $1"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
  done

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    usage_test
    return $EC_MISSING_ARG
  fi

  # Find instance config file using standard finder
  local instance_config_file
  if ! instance_config_file=$(__find_instance_config "$instance_name" 2>/dev/null); then
    __print_error "Instance '$instance_name' not found"
    return $EC_NOT_FOUND
  fi

  # Source instance for display purposes
  __source_instance "$instance_config_file"

  __print_info "Testing port monitoring for '$instance_name'"
  __print_info "Configured ports: $instance_ports"

  # Call logic function
  local status_data
  status_data=$(__logic_test_port_status "$instance_config_file")
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      # Parse status data
      IFS='|' read -r port_count active_count <<< "$status_data"

      # Display individual port status
      IFS='|' read -ra port_defs <<< "$instance_ports"
      for port_def in "${port_defs[@]}"; do
        # Extract port number from this definition
        local port_num
        if [[ "$port_def" =~ ^([0-9]+):([0-9]+)(/[a-z]+)?$ ]]; then
          port_num="${BASH_REMATCH[1]}"
        elif [[ "$port_def" =~ ^([0-9]+)(/[a-z]+)?$ ]]; then
          port_num="${BASH_REMATCH[1]}"
        else
          __print_warning "Invalid port definition: $port_def"
          continue
        fi

        if ss -lntu 2> /dev/null | grep -q ":${port_num}\b"; then
          __print_success "Port $port_num ($port_def): Active"
        else
          __print_warning "Port $port_num ($port_def): Inactive"
        fi
      done

      echo ""
      if [[ $active_count -eq $port_count ]]; then
        __print_success "All $port_count ports are active!"
        return 0
      elif [[ $active_count -gt 0 ]]; then
        __print_warning "$active_count of $port_count ports are active"
        return 1
      else
        __print_warning "No ports are currently active"
        __print_info "This may be normal if the server isn't running"
        return 1
      fi
      ;;
    $EC_WATCHER_PORT_NOT_ACTIVE)
      __print_error "No ports configured for '$instance_name'"
      __print_error "Set 'ports' in the instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to test port status"
      return $exit_code
      ;;
  esac
}

# Command: status <instance>
function _cmd_status() {
  local instance_name=""

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_status
        return 0
        ;;
      *)
        if [[ -z "$instance_name" ]]; then
          instance_name="$1"
          shift
        else
          __print_error "Unknown argument: $1"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
  done

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    usage_status
    return $EC_MISSING_ARG
  fi

  # Find instance config file using standard finder
  local instance_config_file
  if ! instance_config_file=$(__find_instance_config "$instance_name" 2>/dev/null); then
    __print_error "Instance '$instance_name' not found"
    return $EC_NOT_FOUND
  fi

  # Source the instance configuration so instance_* variables are available to logic functions
  __source_instance "$instance_config_file"

  # Get status data from logic layer
  local status_data
  status_data=$(__logic_get_port_status_data "$instance_config_file")
  local exit_code=$?

  if [[ $exit_code -ne $EC_SUCCESS ]]; then
    __print_error "Failed to retrieve port watcher status"
    return $exit_code
  fi

  # Parse status data
  IFS='|' read -r all_ports first_port port_count active_count <<< "$status_data"

  local BOLD="\e[1m"
  local END="\e[0m"
  local GREEN="\e[32m"
  local RED="\e[31m"
  local YELLOW="\e[33m"

  echo -e "${BOLD}Port Monitor Watcher Status for '$instance_name'${END}"
  echo "============================================"
  echo ""

  # Configuration status
  echo -e "${BOLD}Configuration:${END}"
  if [[ -n "$all_ports" ]]; then
    echo -e "  Ports: ${GREEN}$all_ports${END}"
    if [[ -n "$first_port" ]]; then
      echo "  Primary port (monitored): $first_port"
    else
      echo "  Primary port (monitored): Invalid format"
    fi
  else
    echo -e "  Ports: ${RED}Not configured${END}"
    echo "    Configure 'ports' in instance configuration"
  fi

  echo "  Check interval: ${config_watcher_ports_check_interval_seconds:-5} seconds"
  echo "  Timeout: ${config_watcher_global_timeout_seconds:-600} seconds"
  echo ""

  # Dependencies
  echo -e "${BOLD}Dependencies:${END}"
  if command -v ss > /dev/null 2>&1; then
    echo -e "  ss command: ${GREEN}Available${END}"
  else
    echo -e "  ss command: ${RED}Missing${END}"
    echo "    Install with: sudo apt-get install iproute2"
  fi
  echo ""

  # Test current state
  if [[ -n "$all_ports" ]]; then
    echo -e "${BOLD}Current Port Status:${END}"
    # Split by | and process each port definition
    IFS='|' read -ra port_defs <<< "$all_ports"
    for port_def in "${port_defs[@]}"; do
      # Extract port number from this definition
      local port_num
      if [[ "$port_def" =~ ^([0-9]+):([0-9]+)(/[a-z]+)?$ ]]; then
        port_num="${BASH_REMATCH[1]}"
      elif [[ "$port_def" =~ ^([0-9]+)(/[a-z]+)?$ ]]; then
        port_num="${BASH_REMATCH[1]}"
      else
        echo -e "  $port_def: ${RED}Invalid format${END}"
        continue
      fi

      if ss -lntu 2> /dev/null | grep -q ":${port_num}\b"; then
        echo -e "  Port $port_num ($port_def): ${GREEN}Active${END}"
      else
        echo -e "  Port $port_num ($port_def): ${YELLOW}Inactive${END}"
      fi
    done
  fi

  return 0
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return 0
  fi

  case "$command" in
    watch)
      usage_watch
      ;;
    test)
      usage_test
      ;;
    status)
      usage_status
      ;;
    *)
      __print_error "Unknown command: $command"
      echo ""
      show_usage
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
  watch)
    _cmd_watch "$@"
    exit $?
    ;;
  test)
    _cmd_test "$@"
    exit $?
    ;;
  status)
    _cmd_status "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    echo ""
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
