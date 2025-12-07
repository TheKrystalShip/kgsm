#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Unix Domain Socket Event Transport for Krystal Game Server Manager${END}

Manages Unix Domain Socket event broadcasting for local inter-process communication.

${UNDERLINE}Usage:${END}
  ${self} <command> [options]

${UNDERLINE}Commands:${END}
  enable                      Enable Unix Domain Socket event transport
  disable                     Disable Unix Domain Socket event transport
  test                        Test socket functionality
  status                      Show socket transport status
  emit <payload>              Emit event to socket (internal use)
  help [command]              Show help information

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  --debug                     Enable debug output

${UNDERLINE}Examples:${END}
  ${self} enable
  ${self} test
  ${self} status
  ${self} disable

${UNDERLINE}Notes:${END}
  • Socket transport requires 'socat' for message transmission
  • Socket file is created in \$KGSM_ROOT directory
  • Multiple processes can listen to the same socket
  • Sockets are created automatically when first event is emitted
"
}

function usage_enable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Enable Socket Transport${END}

Enables Unix Domain Socket event transport and validates dependencies.

${UNDERLINE}Usage:${END}
  ${self} enable

${UNDERLINE}Description:${END}
Activates socket-based event broadcasting by:
  • Checking for required 'socat' dependency
  • Updating KGSM configuration to enable socket transport
  • Displaying socket file location(s)

Socket files are created automatically when the first event is emitted.

${UNDERLINE}Examples:${END}
  ${self} enable
"
}

function usage_disable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Disable Socket Transport${END}

Disables Unix Domain Socket event transport and cleans up socket files.

${UNDERLINE}Usage:${END}
  ${self} disable

${UNDERLINE}Description:${END}
Deactivates socket-based event broadcasting by:
  • Updating KGSM configuration to disable socket transport
  • Removing any existing socket files

${UNDERLINE}Examples:${END}
  ${self} disable
"
}

function usage_test() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Test Socket Transport${END}

Tests socket functionality by sending a test event and verifying reception.

${UNDERLINE}Usage:${END}
  ${self} test

${UNDERLINE}Description:${END}
Validates socket transport by:
  • Creating temporary socket listener(s)
  • Sending test event through the socket emission function
  • Verifying the event was received correctly
  • Cleaning up test resources

Requires socket transport to be enabled.

${UNDERLINE}Examples:${END}
  ${self} test
"
}

function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Show Socket Status${END}

Displays detailed socket transport status information.

${UNDERLINE}Usage:${END}
  ${self} status

${UNDERLINE}Description:${END}
Shows socket transport information including:
  • Configuration state (enabled/disabled)
  • Socket file location(s)
  • Dependency status (socat availability)
  • Runtime status (socket file existence)

${UNDERLINE}Examples:${END}
  ${self} status
"
}

# Core function: Send event to socket (used by core/events.sh)
function __socket_emit_event() {
  local payload="$1"

  if [[ -z "$payload" ]]; then
    __print_error "Event payload is required"
    return 1
  fi

  # Check if socat is available
  if ! command -v socat > /dev/null 2>&1; then
    __print_error "socat is required for socket events but is not installed"
    return 1
  fi

  # Get socket filenames (with backward compatibility)
  local socket_filenames
  if [[ -n "$config_event_socket_filenames" ]]; then
    socket_filenames="$config_event_socket_filenames"
  elif [[ -n "$config_event_socket_filename" ]]; then
    # Backward compatibility
    socket_filenames="$config_event_socket_filename"
  else
    socket_filenames="kgsm.sock"
  fi

  # Convert comma-separated list to array
  IFS=',' read -ra socket_list <<< "$socket_filenames"

  local overall_result=0
  local sent_to_any=false

  # Send to each socket
  for socket_name in "${socket_list[@]}"; do
    # Trim whitespace
    socket_name=$(echo "$socket_name" | xargs)
    local socket_file="$KGSM_ROOT/$socket_name"

    if [[ ! -e "$socket_file" ]]; then
      continue
    fi

    # Send event to socket
    echo "$payload" | socat - UNIX-CONNECT:"$socket_file",reuseaddr
    local result=$?

    if [[ $result -eq 0 ]]; then
      sent_to_any=true
    else
      overall_result=$result
    fi
  done

  # Return success if we sent to at least one socket, or if no sockets exist
  if [[ "$sent_to_any" == "true" ]]; then
    return 0
  else
    return $overall_result
  fi
}

export -f __socket_emit_event

# Enable socket transport
function _cmd_enable() {
  if [[ "$1" == "--help" ]]; then
    usage_enable
    return $EC_OKAY
  fi

  __print_info "Enabling Unix Domain Socket event transport..."

  # Check dependencies
  if ! command -v socat > /dev/null 2>&1; then
    __print_error "socat is required but not installed"
    __print_error "Install socat: sudo apt-get install socat (Ubuntu/Debian) or sudo yum install socat (RHEL/CentOS)"
    return $EC_MISSING_DEPENDENCY
  fi

  # Enable in configuration
  __set_config_value "enable_event_broadcasting" "true"
  local result=$?
  if [[ $result -eq 0 ]]; then
    __print_success "Unix Domain Socket event transport enabled"

    # Get socket filenames (with backward compatibility)
    local socket_filenames
    if [[ -n "$config_event_socket_filenames" ]]; then
      socket_filenames="$config_event_socket_filenames"
    elif [[ -n "$config_event_socket_filename" ]]; then
      socket_filenames="$config_event_socket_filename"
    else
      socket_filenames="kgsm.sock"
    fi

    # Convert comma-separated list to array
    IFS=',' read -ra socket_list <<< "$socket_filenames"

    if [[ ${#socket_list[@]} -eq 1 ]]; then
      __print_info "Socket file will be created at: $KGSM_ROOT/${socket_list[0]// /}"
    else
      __print_info "Socket files will be created at:"
      for socket_name in "${socket_list[@]}"; do
        socket_name=$(echo "$socket_name" | xargs)
        __print_info "  - $KGSM_ROOT/$socket_name"
      done
    fi

    __print_info "Use '${self} test' to verify functionality"
  fi

  return $result
}

# Disable socket transport
function _cmd_disable() {
  if [[ "$1" == "--help" ]]; then
    usage_disable
    return $EC_OKAY
  fi

  __print_info "Disabling Unix Domain Socket event transport..."

  # Disable in configuration
  __set_config_value "enable_event_broadcasting" "false"
  local result=$?
  if [[ $result -eq 0 ]]; then
    __print_success "Unix Domain Socket event transport disabled"

    # Get socket filenames (with backward compatibility)
    local socket_filenames
    if [[ -n "$config_event_socket_filenames" ]]; then
      socket_filenames="$config_event_socket_filenames"
    elif [[ -n "$config_event_socket_filename" ]]; then
      socket_filenames="$config_event_socket_filename"
    else
      socket_filenames="kgsm.sock"
    fi

    # Convert comma-separated list to array
    IFS=',' read -ra socket_list <<< "$socket_filenames"

    # Clean up socket files if they exist
    for socket_name in "${socket_list[@]}"; do
      socket_name=$(echo "$socket_name" | xargs)
      local socket_file="$KGSM_ROOT/$socket_name"
      if [[ -e "$socket_file" ]]; then
        rm -f "$socket_file"
        __print_info "Removed socket file: $socket_file"
      fi
    done
  fi

  return $result
}

# Test socket functionality
function _cmd_test() {
  if [[ "$1" == "--help" ]]; then
    usage_test
    return $EC_OKAY
  fi

  __print_info "Testing Unix Domain Socket event transport..."

  # Check if enabled
  if [[ "$config_enable_event_broadcasting" != "true" ]]; then
    __print_error "Socket transport is not enabled"
    __print_error "Use '${self} enable' to activate socket transport first"
    return 1
  fi

  # Check dependencies
  if ! command -v socat > /dev/null 2>&1; then
    __print_error "socat is required but not installed"
    return $EC_MISSING_DEPENDENCY
  fi

  # Get socket filenames (with backward compatibility)
  local socket_filenames
  if [[ -n "$config_event_socket_filenames" ]]; then
    socket_filenames="$config_event_socket_filenames"
  elif [[ -n "$config_event_socket_filename" ]]; then
    socket_filenames="$config_event_socket_filename"
  else
    socket_filenames="kgsm.sock"
  fi

  # Convert comma-separated list to array
  IFS=',' read -ra socket_list <<< "$socket_filenames"

  if [[ ${#socket_list[@]} -eq 1 ]]; then
    __print_info "Socket file: $KGSM_ROOT/${socket_list[0]// /}"
  else
    __print_info "Socket files:"
    for socket_name in "${socket_list[@]}"; do
      socket_name=$(echo "$socket_name" | xargs)
      __print_info "  - $KGSM_ROOT/$socket_name"
    done
  fi

  # Clean up any existing socket files
  for socket_name in "${socket_list[@]}"; do
    socket_name=$(echo "$socket_name" | xargs)
    local socket_file="$KGSM_ROOT/$socket_name"
    if [[ -e "$socket_file" ]]; then
      rm -f "$socket_file"
    fi
  done

  # Create a simple test by using the actual emit function
  local test_payload
  test_payload=$(
    jq -n \
      --arg event_type "test_event" \
      --arg test_data "Socket transport test" \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg hostname "$(hostname 2>/dev/null || echo 'localhost')" \
      '{
        EventType: $event_type,
        Data: { Test: $test_data },
        Timestamp: $timestamp,
        Hostname: $hostname,
        KGSMVersion: "test"
      }'
  )

  # Test each socket
  local overall_success=true
  local listeners=()
  local test_outputs=()

  # Start listeners for each socket
  for i in "${!socket_list[@]}"; do
    local socket_name=$(echo "${socket_list[$i]}" | xargs)
    local socket_file="$KGSM_ROOT/$socket_name"
    local test_output="/tmp/kgsm-socket-test-$$-$i"

    # Start listener that will capture one message and exit
    timeout 5 socat UNIX-LISTEN:"$socket_file",fork - > "$test_output" &
    local listener_pid=$!

    listeners+=("$listener_pid")
    test_outputs+=("$test_output")

    __print_info "Started listener for socket: $socket_name (PID: $listener_pid)"
  done

  # Give listeners time to start
  sleep 1

  # Send test event using the actual emit function
  if __socket_emit_event "$test_payload"; then
    __print_success "Test event sent to socket(s)"

    # Wait a moment for delivery
    sleep 1

    # Check each output
    for i in "${!test_outputs[@]}"; do
      local test_output="${test_outputs[$i]}"
      local socket_name=$(echo "${socket_list[$i]}" | xargs)

      if [[ -s "$test_output" ]]; then
        local received_data
        received_data=$(cat "$test_output")
        if echo "$received_data" | jq -e '.EventType == "test_event"' > /dev/null 2>&1; then
          __print_success "Socket '$socket_name': Event received and validated"
        else
          __print_error "Socket '$socket_name': Received data is invalid"
          overall_success=false
        fi
      else
        __print_error "Socket '$socket_name': No data received"
        overall_success=false
      fi
    done
  else
    __print_error "Failed to send test event"
    overall_success=false
  fi

  # Clean up
  for listener_pid in "${listeners[@]}"; do
    kill "$listener_pid" 2> /dev/null || true
    wait "$listener_pid" 2> /dev/null || true
  done

  for test_output in "${test_outputs[@]}"; do
    rm -f "$test_output"
  done

  for socket_name in "${socket_list[@]}"; do
    socket_name=$(echo "$socket_name" | xargs)
    local socket_file="$KGSM_ROOT/$socket_name"
    rm -f "$socket_file"
  done

  if [[ "$overall_success" == "true" ]]; then
    __print_success "Socket transport test PASSED"
    return 0
  else
    __print_error "Socket transport test FAILED"
    return 1
  fi
}

# Show socket status
function _cmd_status() {
  if [[ "$1" == "--help" ]]; then
    usage_status
    return $EC_OKAY
  fi

  local BOLD="\e[1m"
  local END="\e[0m"
  local GREEN="\e[32m"
  local RED="\e[31m"

  echo -e "${BOLD}Unix Domain Socket Transport Status${END}"
  echo "===================================="
  echo ""

  # Configuration status
  echo -e "${BOLD}Configuration:${END}"
  if [[ "$config_enable_event_broadcasting" == "true" ]]; then
    echo -e "  Status: ${GREEN}Enabled${END}"
  else
    echo -e "  Status: ${RED}Disabled${END}"
  fi

  # Get socket filenames (with backward compatibility)
  local socket_filenames
  if [[ -n "$config_event_socket_filenames" ]]; then
    socket_filenames="$config_event_socket_filenames"
  elif [[ -n "$config_event_socket_filename" ]]; then
    socket_filenames="$config_event_socket_filename"
  else
    socket_filenames="kgsm.sock"
  fi

  # Convert comma-separated list to array
  IFS=',' read -ra socket_list <<< "$socket_filenames"

  if [[ ${#socket_list[@]} -eq 1 ]]; then
    echo "  Socket file: $KGSM_ROOT/${socket_list[0]// /}"
  else
    echo "  Socket files:"
    for socket_name in "${socket_list[@]}"; do
      socket_name=$(echo "$socket_name" | xargs)
      echo "    - $KGSM_ROOT/$socket_name"
    done
  fi
  echo ""

  # Dependencies
  echo -e "${BOLD}Dependencies:${END}"
  if command -v socat > /dev/null 2>&1; then
    echo -e "  socat: ${GREEN}Available${END} ($(socat -V 2> /dev/null | head -1 || echo 'version unknown'))"
  else
    echo -e "  socat: ${RED}Not installed${END}"
    echo "                 Install with: sudo apt-get install socat (Ubuntu/Debian)"
    echo "                 sudo yum install socat (RHEL/CentOS)"
  fi
  echo ""

  # Runtime status
  echo -e "${BOLD}Runtime Status:${END}"
  local any_exist=false
  for socket_name in "${socket_list[@]}"; do
    socket_name=$(echo "$socket_name" | xargs)
    local socket_file="$KGSM_ROOT/$socket_name"
    if [[ -e "$socket_file" ]]; then
      echo -e "  $socket_name: ${GREEN}Exists${END}"
      any_exist=true
    else
      echo "  $socket_name: Not yet created"
    fi
  done

  if [[ "$any_exist" == "false" ]]; then
    echo "    Sockets will be created when first event is emitted"
  fi

  return $EC_OKAY
}

# Handle emit command (called by commands/events.sh)
function _cmd_emit() {
  local payload="$1"
  __socket_emit_event "$payload"
  return $?
}

# Help command
function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return $EC_OKAY
  fi

  case "$command" in
    enable)
      usage_enable
      ;;
    disable)
      usage_disable
      ;;
    test)
      usage_test
      ;;
    status)
      usage_status
      ;;
    *)
      __print_error "Unknown command: $command"
      show_usage
      return $EC_INVALID_ARG
      ;;
  esac

  return $EC_OKAY
}

# Main entry point
if [[ $# -eq 0 ]]; then
  show_usage
  exit $EC_GENERAL
fi

# Parse global options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help | help)
      shift
      _cmd_help "$@"
      exit $?
      ;;
    --debug)
      export KGSM_DEBUG=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

# Parse command
command="${1:-}"
shift 2> /dev/null || true

# Route to command handlers
case "$command" in
  "")
    show_usage
    exit $EC_GENERAL
    ;;
  enable)
    _cmd_enable "$@"
    exit $?
    ;;
  disable)
    _cmd_disable "$@"
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
  emit)
    _cmd_emit "$@"
    exit $?
    ;;
  help)
    _cmd_help "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
