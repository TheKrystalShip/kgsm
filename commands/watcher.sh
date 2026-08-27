#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

# Load logic library
logic_library=$(__find_command_handler watchers.sh)
# shellcheck source=handlers/watchers.sh
source "$logic_library" || {
  __print_error "Failed to load watcher logic library"
  exit $EC_FAILED_SOURCE
}

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Instance Readiness Watcher for Krystal Game Server Manager${END}

Monitors game server instances to detect when they become ready for players.
Supports multiple detection strategies including log pattern matching and port monitoring.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance> [options]
  ${self} logs <subcommand> <instance> [options]
  ${self} ports <subcommand> <instance> [options]

${UNDERLINE}Quick Commands:${END}
  start <instance>            Launch watcher with auto-selected strategy
  test <instance>             Test watcher configuration (auto-selects strategy)
  status <instance>           Show watcher configuration for all strategies
  help [command]              Display help information

${UNDERLINE}Component Commands:${END}
  logs watch <instance>       Watch log file for readiness pattern
  logs test <instance>        Test log pattern configuration
  logs status <instance>      Show log watcher status
  ports watch <instance>      Watch ports for readiness
  ports test <instance>       Test port monitoring configuration
  ports status <instance>     Show port watcher status

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --detach                    Run watcher in detached background process

${UNDERLINE}Detection Strategies:${END}
  ${UNDERLINE}Log Pattern Matching (Primary):${END}
    • Monitors the instance log file for a specific success pattern
    • Uses startup_success_regex configuration value
    • Provides immediate feedback when the server reports readiness
    • Recommended for most game servers that log startup completion

  ${UNDERLINE}Port Monitoring (Fallback):${END}
    • Monitors network ports for availability
    • Uses first port from ports configuration
    • Checks port binding every ${config_watcher_ports_check_interval_seconds:-5} seconds
    • Used when no log pattern is configured

${UNDERLINE}Timeout and Monitoring:${END}
  • Global timeout: ${config_watcher_global_timeout_seconds:-600} seconds (configurable)
  • Runs as detached background process when --detach is used
  • Automatically cleans up if server process terminates
  • Emits server.ready event when detection succeeds

${UNDERLINE}Examples:${END}
  ${self} start valheim-server-01
  ${self} start factorio-space-age --detach
  ${self} test minecraft-survival
  ${self} status terraria-modded
  ${self} logs watch valheim-server-01 --detach
  ${self} ports test minecraft-survival
  ${self} help start

${UNDERLINE}Notes:${END}
  • Strategy auto-selection: log pattern takes precedence over port monitoring
  • Only one strategy is used per instance
  • Timeout values are configurable via KGSM configuration
  • Failed detection attempts are logged with appropriate warnings
  • Events are emitted to the KGSM event system upon successful detection
  • Component commands allow manual control of specific strategies
"
}

function usage_start() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Start Instance Readiness Watcher${END}

Launches a watcher for the specified instance using auto-selected strategy.

${UNDERLINE}Usage:${END}
  ${self} start <instance> [--detach]

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Options:${END}
  --detach                    Run in detached background process
  --help                      Display this help information

${UNDERLINE}Description:${END}
  Automatically selects the appropriate watcher strategy based on instance
  configuration and launches the watcher. Strategy selection priority:
    1. Log pattern matching (if startup_success_regex is configured)
    2. Port monitoring (if ports are configured)

  When run with --detach, the watcher runs as a background process and outputs
  to logs/watcher-<instance>.log instead of the terminal.

${UNDERLINE}Examples:${END}
  ${self} start factorio-server
  ${self} start valheim-server --detach

${UNDERLINE}Requirements:${END}
  • Instance must have either startup_success_regex or ports configured
  • Server process must be running or starting
"
}

function usage_test() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Test Watcher Configuration${END}

Tests the watcher configuration for the specified instance using auto-selected strategy.

${UNDERLINE}Usage:${END}
  ${self} test <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Automatically selects the appropriate watcher strategy and tests its configuration.
  For log pattern matching, checks if the pattern exists in the current log.
  For port monitoring, checks if configured ports are currently active.

${UNDERLINE}Examples:${END}
  ${self} test factorio-server
  ${self} test minecraft-survival

${UNDERLINE}Requirements:${END}
  • Instance must have either startup_success_regex or ports configured
"
}

function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Show Watcher Status${END}

Displays comprehensive watcher configuration and status for both strategies.

${UNDERLINE}Usage:${END}
  ${self} status <instance>

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Description:${END}
  Shows detailed information about all watcher strategies including:
    • Which strategy would be auto-selected
    • Log pattern configuration and current state
    • Port monitoring configuration and current state
    • Timeout and check interval settings

${UNDERLINE}Examples:${END}
  ${self} status factorio-server
  ${self} status valheim-server
"
}

# Command: start <instance> [--detach]
function _cmd_start() {
  local instance_name=""
  local detach=false

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        usage_start
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
    usage_start
    return $EC_MISSING_ARG
  fi

  # Find instance config file using standard finder
  local instance_config_file
  if ! instance_config_file=$(__find_instance_config "$instance_name" 2>/dev/null); then
    __print_error "Instance '$instance_name' not found"
    return $EC_NOT_FOUND
  fi

  # Determine which strategy to use
  local strategy
  strategy=$(__logic_determine_strategy "$instance_config_file")
  local result=$?

  if [[ $result -ne $EC_SUCCESS ]]; then
    __print_error "No readiness detection strategy configured for '$instance_name'"
    __print_error "Configure either 'startup_success_regex' or 'ports'"
    return $EC_WATCHER_NO_STRATEGY
  fi

  if [[ "$detach" == false ]]; then
    __print_info "Starting readiness watcher for '$instance_name' using $strategy strategy"
  fi

  # Delegate to appropriate submodule
  case "$strategy" in
    logs)
      if [[ "$detach" == true ]]; then
        watcher.logs.sh watch "$instance_name" --detach
      else
        watcher.logs.sh watch "$instance_name"
      fi
      ;;
    ports)
      if [[ "$detach" == true ]]; then
        watcher.ports.sh watch "$instance_name" --detach
      else
        watcher.ports.sh watch "$instance_name"
      fi
      ;;
    *)
      __print_error "Unknown strategy: $strategy"
      return $EC_ERROR
      ;;
  esac

  return $?
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

  # Determine which strategy to use
  local strategy
  strategy=$(__logic_determine_strategy "$instance_config_file")
  local result=$?

  if [[ $result -ne $EC_SUCCESS ]]; then
    __print_error "No readiness detection strategy configured for '$instance_name'"
    __print_error "Configure either 'startup_success_regex' or 'ports'"
    return $EC_WATCHER_NO_STRATEGY
  fi

  # Delegate to appropriate submodule
  case "$strategy" in
    logs)
      watcher.logs.sh test "$instance_name"
      ;;
    ports)
      watcher.ports.sh test "$instance_name"
      ;;
    *)
      __print_error "Unknown strategy: $strategy"
      return $EC_ERROR
      ;;
  esac

  return $?
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

  # Source the instance configuration for display
  __source_instance "$instance_config_file"

  local BOLD="\e[1m"
  local END="\e[0m"
  local GREEN="\e[32m"
  local RED="\e[31m"

  echo -e "${BOLD}Instance Readiness Watcher Status for '$instance_name'${END}"
  echo "=================================================="
  echo ""

  # Show which strategy would be used
  echo -e "${BOLD}Strategy Selection:${END}"
  local strategy
  strategy=$(__logic_determine_strategy "$instance_config_file" 2> /dev/null)
  local result=$?

  if [[ $result -eq $EC_SUCCESS ]]; then
    echo -e "  Selected strategy: ${GREEN}$strategy${END}"
  else
    echo -e "  Selected strategy: ${RED}None configured${END}"
  fi

  echo ""

  # Show configuration for both strategies
  echo -e "${BOLD}Log Pattern Strategy:${END}"
  local ready_pattern="$instance_startup_success_regex"
  if [[ -n "$ready_pattern" ]]; then
    echo -e "  Status: ${GREEN}Configured${END}"
    echo "  Pattern: $ready_pattern"
  else
    echo -e "  Status: ${RED}Not configured${END}"
  fi

  echo ""

  echo -e "${BOLD}Port Monitoring Strategy:${END}"
  local all_ports="$instance_ports"
  if [[ -n "$all_ports" ]]; then
    echo -e "  Status: ${GREEN}Configured${END}"
    echo "  Ports: $all_ports"
  else
    echo -e "  Status: ${RED}Not configured${END}"
  fi

  echo ""

  # Global configuration
  echo -e "${BOLD}Global Configuration:${END}"
  echo "  Timeout: ${config_watcher_global_timeout_seconds:-600} seconds"
  echo "  Port check interval: ${config_watcher_ports_check_interval_seconds:-5} seconds"

  echo ""

  # Show detailed status for the selected strategy
  if [[ $result -eq $EC_SUCCESS ]]; then
    echo -e "${BOLD}Selected Strategy Details:${END}"
    case "$strategy" in
      logs)
        watcher.logs.sh status "$instance_name"
        ;;
      ports)
        watcher.ports.sh status "$instance_name"
        ;;
    esac
  else
    echo -e "${BOLD}Configuration Required:${END}"
    echo "  Configure either 'startup_success_regex' or 'ports' in the instance configuration"
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
    start)
      usage_start
      ;;
    test)
      usage_test
      ;;
    status)
      usage_status
      ;;
    logs | ports)
      __print_info "Component-specific help:"
      echo ""
      if [[ "$command" == "logs" ]]; then
        watcher.logs.sh --help
      else
        watcher.ports.sh --help
      fi
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

# Every verb here operates on an instance named first, and accepts its display
# name as well as its id, resolved once so nothing inward sees anything but an
# id. An id resolves to itself; an unmatched argument is left for the handler.
case "$command" in
  start | test | status | logs | ports)
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
  test)
    _cmd_test "$@"
    exit $?
    ;;
  status)
    _cmd_status "$@"
    exit $?
    ;;
  logs)
    watcher.logs.sh "$@"
    exit $?
    ;;
  ports)
    watcher.ports.sh "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    echo ""
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
