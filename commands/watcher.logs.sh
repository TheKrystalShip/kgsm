#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

# Load logic library
logic_library=$(__find_command_handler watchers.logs.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load log watcher logic library"
  exit $EC_FAILED_SOURCE
}

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Log Pattern Watcher for Krystal Game Server Manager${END}

Monitors game server log files to detect when instances become ready for players.
Uses configurable regex patterns to match server startup completion messages.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance> [options]

${UNDERLINE}Commands:${END}
  watch <instance>            Start watching log file for readiness pattern
  test <instance>             Test log pattern matching configuration
  status <instance>           Show log watcher configuration status
  help [command]              Display help information

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --detach                    Run watcher in detached background process

${UNDERLINE}Configuration:${END}
  • startup_success_regex     Regex pattern to match in log file
  • logs_dir                  Directory containing instance log files
  • Log file expected: {logs_dir}/latest.log

${UNDERLINE}Examples:${END}
  ${self} watch valheim-server-01
  ${self} watch factorio-space-age --detach
  ${self} test minecraft-survival
  ${self} status terraria-modded
  ${self} help watch

${UNDERLINE}Notes:${END}
  • Monitors latest.log file in the instance logs directory
  • Uses 'tail -f' to follow log file in real-time
  • Automatically stops when server process terminates
  • Exits with success when pattern is found
  • Supports regex patterns for flexible matching
  • Emits instance-ready event when pattern matches
"
}

function usage_watch() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Watch Log File for Readiness${END}

Monitors the instance log file in real-time for the configured startup success pattern.

${UNDERLINE}Usage:${END}
  ${self} watch <instance> [--detach]

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Options:${END}
  --detach                    Run in detached background process
  --help                      Display this help information

${UNDERLINE}Description:${END}
  Watches the instance log file using 'tail -f' and waits for the configured
  startup_success_regex pattern to appear. When the pattern matches, emits an
  instance-ready event and exits successfully.

  The watcher automatically stops if:
    • The pattern is matched (success)
    • The server process terminates
    • The global timeout is reached (default: 600 seconds)

  When run with --detach, the watcher runs as a background process and outputs
  to logs/watcher-<instance>.log instead of the terminal.

${UNDERLINE}Examples:${END}
  ${self} watch factorio-server
  ${self} watch valheim-server --detach

${UNDERLINE}Requirements:${END}
  • Instance must have startup_success_regex configured
  • Log file must exist (typically created when server starts)
  • Server process must be running
"
}

function usage_test() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Test Log Pattern Configuration${END}

Tests if the configured startup success pattern exists in the current log file.

${UNDERLINE}Usage:${END}
  ${self} test <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Checks the current log file for the configured startup_success_regex pattern.
  Useful for validating pattern configuration and debugging watcher behavior.

  This is a one-time check of the existing log content, not a real-time monitor.

${UNDERLINE}Examples:${END}
  ${self} test factorio-server
  ${self} test minecraft-survival

${UNDERLINE}Requirements:${END}
  • Instance must have startup_success_regex configured
  • Log file must exist
"
}

function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Show Log Watcher Status${END}

Displays configuration and current state of log pattern watcher for an instance.

${UNDERLINE}Usage:${END}
  ${self} status <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Shows detailed information about the log watcher configuration including:
    • Configured startup success pattern
    • Log file path and existence
    • Current pattern match status
    • Timeout configuration

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

  # Ensure .ini extension
  local instance="${instance_name%.ini}.ini"
  local instance_config_file="$INSTANCES_SOURCE_DIR/$instance"

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_NOT_FOUND
  fi

  # If detached, spawn background process
  if [[ "$detach" == true ]]; then
    (
      _cmd_watch "$instance_name"
    ) &
    disown
    __print_success "Detached log watcher for '$instance_name' has been launched"
    return 0
  fi

  # Source the instance configuration
  __source_instance "$instance"

  # Create watcher log file path
  local watcher_log_file="$LOGS_SOURCE_DIR/watcher-${instance%.ini}.log"

  # Validate log pattern is configured
  local ready_pattern="$instance_startup_success_regex"
  if [[ -z "$ready_pattern" ]]; then
    __print_error_file_only "$watcher_log_file" "No log pattern configured for '$instance_name'"
    __print_error_file_only "$watcher_log_file" "Set 'startup_success_regex' in the instance configuration"
    return $EC_WATCHER_PATTERN_NOT_FOUND
  fi

  # Validate log file exists
  if [[ ! -f "$instance_log_file" ]]; then
    __print_error_file_only "$watcher_log_file" "Log file not found: $instance_log_file"
    __print_error_file_only "$watcher_log_file" "Instance may not be running or logs directory not configured"
    return $EC_WATCHER_LOG_FILE_MISSING
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

  # Wait a couple of seconds to make sure the server stores the PID
  sleep 2

  if ! server_pid=$(cat "$pid_file" 2>/dev/null); then
    __print_error_file_only "$watcher_log_file" "Failed to read server PID from '$pid_file'"
    return $EC_FILE_NOT_FOUND
  fi

  if [[ -z "$server_pid" ]]; then
    __print_error_file_only "$watcher_log_file" "Server PID is empty"
    return $EC_ERROR
  fi

  __print_info_file_only "$watcher_log_file" "Server PID: $server_pid"

  # Execute the log watch
  local timeout_seconds="${config_watcher_global_timeout_seconds:-600}"
  __logic_execute_log_watch "$instance" "$server_pid" "$ready_pattern" "$instance_log_file" "$timeout_seconds" "$watcher_log_file"
  local exit_code=$?

  # Handle exit codes
  case $exit_code in
    $EC_SUCCESS_INSTANCE_READY)
      # Event already emitted by logic layer
      events.sh emit instance-ready "${instance%.ini}"
      return 0
      ;;
    $EC_WATCHER_TIMEOUT)
      return $exit_code
      ;;
    $EC_ERROR)
      return $exit_code
      ;;
    *)
      __print_error_file_only "$watcher_log_file" "Unexpected error during log watch"
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

  # Ensure .ini extension
  local instance="${instance_name%.ini}.ini"
  local instance_config_file="$INSTANCES_SOURCE_DIR/$instance"

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_NOT_FOUND
  fi

  # Source instance for display purposes
  __source_instance "$instance"

  __print_info "Testing log pattern matching for '$instance_name'"
  __print_info "Pattern: '$instance_startup_success_regex'"
  __print_info "Log file: '$instance_log_file'"

  # Call logic function
  __logic_test_log_pattern "$instance_config_file"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      __print_success "Pattern found in log file!"
      return 0
      ;;
    $EC_WATCHER_PATTERN_NOT_FOUND)
      __print_warning "Pattern not found in current log file"
      __print_info "This may be normal if the server hasn't started yet"
      return 1
      ;;
    $EC_WATCHER_LOG_FILE_MISSING)
      __print_error "Log file not found: $instance_log_file"
      return $exit_code
      ;;
    *)
      __print_error "Failed to test log pattern"
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

  # Ensure .ini extension
  local instance="${instance_name%.ini}.ini"
  local instance_config_file="$INSTANCES_SOURCE_DIR/$instance"

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_NOT_FOUND
  fi

  # Get status data from logic layer
  local status_data
  status_data=$(__logic_get_log_status_data "$instance_config_file")
  local exit_code=$?

  if [[ $exit_code -ne $EC_SUCCESS ]]; then
    __print_error "Failed to retrieve log watcher status"
    return $exit_code
  fi

  # Parse status data
  IFS='|' read -r ready_pattern log_file log_exists pattern_found <<< "$status_data"

  local BOLD="\e[1m"
  local END="\e[0m"
  local GREEN="\e[32m"
  local RED="\e[31m"
  local YELLOW="\e[33m"

  echo -e "${BOLD}Log Pattern Watcher Status for '$instance_name'${END}"
  echo "========================================"
  echo ""

  # Configuration status
  echo -e "${BOLD}Configuration:${END}"
  if [[ -n "$ready_pattern" ]]; then
    echo -e "  Pattern: ${GREEN}$ready_pattern${END}"
  else
    echo -e "  Pattern: ${RED}Not configured${END}"
    echo "    Configure 'startup_success_regex' in instance configuration"
  fi

  echo "  Log file: $log_file"
  if [[ "$log_exists" == "true" ]]; then
    echo -e "  Log file status: ${GREEN}Exists${END}"
    if [[ -f "$log_file" ]]; then
      echo "  Log file size: $(du -h "$log_file" 2>/dev/null | cut -f1)"
    fi
  else
    echo -e "  Log file status: ${RED}Missing${END}"
  fi

  echo "  Timeout: ${config_watcher_global_timeout_seconds:-600} seconds"
  echo ""

  # Test current state
  if [[ -n "$ready_pattern" && "$log_exists" == "true" ]]; then
    echo -e "${BOLD}Current State:${END}"
    if [[ "$pattern_found" == "true" ]]; then
      echo -e "  Pattern in log: ${GREEN}Found${END}"
    else
      echo -e "  Pattern in log: ${YELLOW}Not found${END}"
    fi
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

