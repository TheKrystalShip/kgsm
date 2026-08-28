#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# =============================================================================
# HELP SYSTEM
# =============================================================================

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "${UNDERLINE}Network Management for Krystal Game Server Manager${END}

Manages network ports and connectivity for game server hosting.

${UNDERLINE}Usage:${END}
  $self <command> [arguments] [options]

${UNDERLINE}Commands:${END}
  ${BOLD}Port Management:${END}
  ports check <port> [protocol]    Check if a port is in use
  ports list-used                  List all ports currently in use
  ports conflicts                  Find port conflicts across instances
  ports kill <port> [protocol]     Kill process using a port

  ${BOLD}Connectivity Testing:${END}
  test-port <port> [protocol]      Test if port is externally accessible
  test-all                         Test all KGSM instance ports

  ${BOLD}Network Information:${END}
  ip                               Show external and local IP addresses
  dns                              Show DNS server configuration

  help [command]                   Show help information

${UNDERLINE}Options:${END}
  -h, --help                       Show help and exit
  --debug                          Enable debug output

${UNDERLINE}Examples:${END}
  ${BOLD}Port Management:${END}
  $self ports check 27015          Check if TCP port 27015 is in use
  $self ports check 27015 udp      Check if UDP port 27015 is in use
  $self ports list-used            Show all ports in use on system
  $self ports conflicts            Find KGSM instance port conflicts
  $self ports kill 27015           Kill process using port 27015

  ${BOLD}Connectivity Testing:${END}
  $self test-port 27015            Test if port 27015 is externally accessible
  $self test-all                   Test all KGSM instance ports

  ${BOLD}Network Information:${END}
  $self ip                         Show external and local IP addresses
  $self dns                        Show DNS servers

${UNDERLINE}Notes:${END}
  • Port protocol defaults to 'tcp' if not specified
  • Port range: 1-65535
  • Killing ports may require sudo privileges
  • Connectivity tests require the port to be listening
  • External accessibility testing has limitations
"
}

function show_usage_ports_check() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Check Port Usage${END}

Checks if a specific port is currently in use on the system.

${UNDERLINE}Usage:${END}
  $self ports check <port> [protocol]

${UNDERLINE}Arguments:${END}
  port                             Port number to check (1-65535)
  protocol                         Protocol: tcp or udp (default: tcp)

${UNDERLINE}Options:${END}
  --help                           Display this help information

${UNDERLINE}Description:${END}
Checks if the specified port is currently being used by any process.
If the port is in use, shows which process is using it.

${UNDERLINE}Examples:${END}
  $self ports check 27015          Check TCP port 27015
  $self ports check 27015 tcp      Check TCP port 27015 (explicit)
  $self ports check 27015 udp      Check UDP port 27015
"
}

function show_usage_ports_kill() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Kill Process Using Port${END}

Terminates the process using a specific port.

${UNDERLINE}Usage:${END}
  $self ports kill <port> [protocol]

${UNDERLINE}Arguments:${END}
  port                             Port number (1-65535)
  protocol                         Protocol: tcp or udp (default: tcp)

${UNDERLINE}Options:${END}
  --help                           Display this help information

${UNDERLINE}Warning:${END}
This will forcefully terminate the process using the specified port.
Use with caution. May require sudo privileges.

${UNDERLINE}Description:${END}
Finds and terminates the process currently using the specified port.
Attempts graceful shutdown (SIGTERM) first, then forces (SIGKILL) if needed.

${UNDERLINE}Examples:${END}
  $self ports kill 27015           Kill process using TCP port 27015
  $self ports kill 27015 udp       Kill process using UDP port 27015
"
}

function show_usage_test_port() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Test Port Accessibility${END}

Tests if a port is accessible from outside the network.

${UNDERLINE}Usage:${END}
  $self test-port <port> [protocol]

${UNDERLINE}Arguments:${END}
  port                             Port number to test (1-65535)
  protocol                         Protocol: tcp or udp (default: tcp)

${UNDERLINE}Options:${END}
  --help                           Display this help information

${UNDERLINE}Description:${END}
Tests if the specified port is accessible from external networks.
The port must be listening locally for the test to be meaningful.

Note: Full external testing has limitations without remote test servers.
Results indicate probable accessibility based on local checks and
basic connectivity tests.

${UNDERLINE}Examples:${END}
  $self test-port 27015            Test TCP port 27015 accessibility
  $self test-port 27015 udp        Test UDP port 27015 accessibility
"
}

function show_usage_ip() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Display IP Address Information${END}

Shows the server's external and local IP addresses.

${UNDERLINE}Usage:${END}
  $self ip

${UNDERLINE}Options:${END}
  --help                           Display this help information

${UNDERLINE}Description:${END}
Displays both external (public) and local (private) IP addresses for this server.

External IP is retrieved from https://icanhazip.com using curl or wget.
Local IPs are retrieved from the system's network configuration.

${UNDERLINE}Examples:${END}
  $self ip
"
}

# =============================================================================
# LOAD REQUIRED LIBRARIES
# =============================================================================

logic_library=$(__find_command_handler network.sh)
# shellcheck source=handlers/network.sh
source "$logic_library" || {
  __print_error "Failed to load network logic library"
  exit $EC_FAILED_SOURCE
}

function _cmd_ports_check() {
  local port=""
  local protocol="tcp"

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_ports_check
        return 0
        ;;
      -p | --protocol)
        shift
        protocol="$1"
        ;;
      -t | --tcp)
        protocol="tcp"
        ;;
      -u | --udp)
        protocol="udp"
        ;;
      *)
        port="$1"
        break
        ;;
    esac
    shift
  done

  # Validate port
  if [[ -z "$port" ]]; then
    __print_error "Missing required argument: <port>"
    __print_error "Use '$self ports check --help' for usage"
    return $EC_MISSING_ARG
  fi

  # Call logic function
  local result
  result=$(__logic_check_port "$port" "$protocol")
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_FREE)
      __print_success "Port $port/$protocol is FREE"
      ;;
    $EC_SUCCESS_NETWORK_PORT_IN_USE)
      local process_info="${result#in_use:}"
      __print_warning "Port $port/$protocol is IN USE"
      __print_info "Process: $process_info"
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid argument"
      __print_error "Port must be between 1-65535, protocol must be tcp or udp"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "Port checking requires ss, netstat, or lsof"
      ;;
    *)
      __print_error "Failed to check port"
      ;;
  esac

  return $exit_code
}

# Render the marker-delimited port list as a JSON array of
# {port, protocol, process} objects. A socket nobody could attribute carries a
# null process — never a placeholder name.
function _ports_used_to_json() {
  local _result="$1"

  local _protocol="" _first=true
  echo "["
  while IFS=$'\t' read -r _port _process; do
    case "$_port" in
      "TCP_PORTS:") _protocol="tcp"; continue ;;
      "UDP_PORTS:") _protocol="udp"; continue ;;
      "") continue ;;
    esac

    [[ "$_first" == false ]] && echo ","
    _first=false

    if [[ -n "$_process" ]]; then
      printf '  {"port": %s, "protocol": "%s", "process": %s}' \
        "$_port" "$_protocol" "$(jq -Rn --arg v "$_process" '$v')"
    else
      printf '  {"port": %s, "protocol": "%s", "process": null}' \
        "$_port" "$_protocol"
    fi
  done <<<"$_result"
  echo ""
  echo "]"
}

function _cmd_ports_list_used() {
  local json_format=0

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --json)
        json_format=1
        ;;
      --help)
        echo "List all ports currently in use on the system"
        echo "Usage: $self ports list-used [--json]"
        echo ""
        echo "Each entry is a listening port, the protocol it listens on, and"
        echo "the process holding it when the socket could be attributed."
        echo ""
        echo "Options:"
        echo "  --json                      Emit the entries as a JSON array"
        return 0
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  [[ "$json_format" -eq 0 ]] && __print_info "Scanning for ports in use..."

  local result
  result=$(__logic_list_used_ports)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_CHECKED)
      if [[ "$json_format" -eq 1 ]]; then
        _ports_used_to_json "$result"
        return 0
      fi

      echo ""
      local protocol=""
      while IFS=$'\t' read -r port process; do
        if [[ "$port" == "TCP_PORTS:" ]]; then
          protocol="tcp"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "TCP PORTS:"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        elif [[ "$port" == "UDP_PORTS:" ]]; then
          protocol="udp"
          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "UDP PORTS:"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        elif [[ -n "$port" ]]; then
          if [[ -n "$process" ]]; then
            echo "  ${port}/${protocol} — ${process}"
          else
            echo "  ${port}/${protocol}"
          fi
        fi
      done <<<"$result"
      echo ""
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "Port listing requires ss or netstat"
      ;;
    *)
      __print_error "Failed to list ports"
      ;;
  esac

  return $exit_code
}

# Render the conflict lines as a JSON array. An empty array is the honest
# encoding of "no conflicts" — the shape is the same either way, so a consumer
# never has to recognise a sentinel word to learn there were none.
function _ports_conflicts_to_json() {
  local _result="$1"

  echo "["
  if [[ "$_result" != "no_conflicts" ]]; then
    local _first=true
    while IFS= read -r _line; do
      local _kind _port_proto _port _protocol
      case "$_line" in
        conflict:*) _kind="instance" ;;
        external_conflict:*) _kind="external" ;;
        *) continue ;;
      esac

      _port_proto=$(echo "$_line" | cut -d: -f2)
      _port="${_port_proto%%/*}"
      _protocol="${_port_proto##*/}"

      [[ "$_first" == false ]] && echo ","
      _first=false

      if [[ "$_kind" == "instance" ]]; then
        printf '  {"kind": "instance", "port": %s, "protocol": "%s", "instance": %s, "other": %s}' \
          "$_port" "$_protocol" \
          "$(jq -Rn --arg v "$(echo "$_line" | cut -d: -f3)" '$v')" \
          "$(jq -Rn --arg v "$(echo "$_line" | cut -d: -f4)" '$v')"
      else
        printf '  {"kind": "external", "port": %s, "protocol": "%s", "instance": %s, "other": %s}' \
          "$_port" "$_protocol" \
          "$(jq -Rn --arg v "$(echo "$_line" | cut -d: -f3)" '$v')" \
          "$(jq -Rn --arg v "$(echo "$_line" | cut -d: -f4-)" '$v')"
      fi
    done <<<"$_result"
    echo ""
  fi
  echo "]"
}

function _cmd_ports_conflicts() {
  local json_format=0

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --json)
        json_format=1
        ;;
      --help)
        echo "Find port conflicts across KGSM instances"
        echo "Usage: $self ports conflicts [--json]"
        echo ""
        echo "Checks all KGSM instances for:"
        echo "  • Duplicate port assignments between instances"
        echo "  • Ports in use by external processes"
        echo ""
        echo "Options:"
        echo "  --json                      Emit the conflicts as a JSON array"
        echo "                              (empty when there are none)"
        return 0
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  [[ "$json_format" -eq 0 ]] &&
    __print_info "Scanning KGSM instances for port conflicts..."

  local result
  result=$(__logic_find_port_conflicts)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_CHECKED)
      if [[ "$json_format" -eq 1 ]]; then
        _ports_conflicts_to_json "$result"
        return 0
      fi

      if [[ "$result" == "no_conflicts" ]]; then
        __print_success "No port conflicts found!"
      else
        echo ""
        __print_warning "Port conflicts detected:"
        echo ""
        echo "$result" | while IFS= read -r line; do
          if [[ "$line" == conflict:* ]]; then
            # Format: conflict:port/protocol:instance1:instance2
            local port_proto instance1 instance2
            port_proto=$(echo "$line" | cut -d: -f2)
            instance1=$(echo "$line" | cut -d: -f3)
            instance2=$(echo "$line" | cut -d: -f4)
            echo "  Port $port_proto: '$instance1' ↔ '$instance2'"
          elif [[ "$line" == external_conflict:* ]]; then
            # Format: external_conflict:port/protocol:instance:process
            local port_proto instance process
            port_proto=$(echo "$line" | cut -d: -f2)
            instance=$(echo "$line" | cut -d: -f3)
            process=$(echo "$line" | cut -d: -f4-)
            echo "  Port $port_proto: '$instance' conflicts with external process: $process"
          fi
        done
        echo ""
      fi
      ;;
    *)
      __print_error "Failed to check for conflicts"
      ;;
  esac

  return $exit_code
}

function _cmd_ports_kill() {
  local port=""
  local protocol="tcp"

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        show_usage_ports_kill
        return 0
        ;;
      *)
        if [[ -z "$port" ]]; then
          port="$1"
        elif [[ "$protocol" == "tcp" ]]; then
          protocol="$1"
        else
          __print_error "Too many arguments"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  # Validate port
  if [[ -z "$port" ]]; then
    __print_error "Missing required argument: <port>"
    __print_error "Use '$self ports kill --help' for usage"
    return $EC_MISSING_ARG
  fi

  __print_warning "Attempting to kill process using port $port/$protocol..."

  __logic_kill_port_process "$port" "$protocol"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      __print_success "Process using port $port/$protocol has been terminated"
      ;;
    $EC_NOT_FOUND)
      __print_info "No process found using port $port/$protocol"
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid argument"
      __print_error "Port must be between 1-65535, protocol must be tcp or udp"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied"
      __print_error "Killing process requires sufficient privileges (try sudo)"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "Port operations require lsof, ss, or netstat"
      ;;
    *)
      __print_error "Failed to kill process"
      ;;
  esac

  return $exit_code
}

function _cmd_ports() {
  local subcommand="$1"
  shift

  case "$subcommand" in
    check)
      _cmd_ports_check "$@"
      return $?
      ;;
    list-used)
      _cmd_ports_list_used "$@"
      return $?
      ;;
    conflicts)
      _cmd_ports_conflicts "$@"
      return $?
      ;;
    kill)
      _cmd_ports_kill "$@"
      return $?
      ;;
    --help)
      _cmd_help ports
      return 0
      ;;
    "")
      __print_error "Missing subcommand for 'ports'"
      __print_error "Use '$self ports --help' for available subcommands"
      return $EC_MISSING_ARG
      ;;
    *)
      __print_error "Unknown subcommand: $subcommand"
      __print_error "Use '$self ports --help' for available subcommands"
      return $EC_INVALID_ARG
      ;;
  esac
}

function _cmd_test_port() {
  local port=""
  local protocol="tcp"

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        show_usage_test_port
        return 0
        ;;
      *)
        if [[ -z "$port" ]]; then
          port="$1"
        elif [[ "$protocol" == "tcp" ]]; then
          protocol="$1"
        else
          __print_error "Too many arguments"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  # Validate port
  if [[ -z "$port" ]]; then
    __print_error "Missing required argument: <port>"
    __print_error "Use '$self test-port --help' for usage"
    return $EC_MISSING_ARG
  fi

  __print_info "Testing port $port/$protocol accessibility..."

  local result
  result=$(__logic_test_port_accessibility "$port" "$protocol")
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_CHECKED)
      if [[ "$result" == "accessible" ]]; then
        __print_success "Port $port/$protocol appears to be ACCESSIBLE"
      elif [[ "$result" == not_accessible:* ]]; then
        local reason="${result#not_accessible:}"
        __print_warning "Port $port/$protocol is NOT ACCESSIBLE"
        case "$reason" in
          port_not_listening)
            __print_info "Reason: Port is not listening locally"
            __print_info "Start a service on this port before testing accessibility"
            ;;
          cannot_determine_external_ip)
            __print_info "Reason: Cannot determine external IP address"
            __print_info "Check internet connectivity"
            ;;
          cannot_test_externally)
            __print_info "Reason: External testing tools unavailable"
            __print_info "Port is listening locally but external test inconclusive"
            __print_info "Try connecting from another machine to verify"
            ;;
          *)
            __print_info "Reason: $reason"
            ;;
        esac
      fi
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid argument"
      __print_error "Port must be between 1-65535, protocol must be tcp or udp"
      ;;
    *)
      __print_error "Failed to test port accessibility"
      ;;
  esac

  return $exit_code
}

function _cmd_test_all() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        echo "Test all KGSM instance ports for accessibility"
        echo "Usage: $self test-all"
        return 0
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  __print_info "Testing all KGSM instance ports..."

  local result
  result=$(__logic_test_all_instance_ports)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_CHECKED)
      if [[ "$result" == "no_instances" ]]; then
        __print_info "No KGSM instances found"
      elif [[ "$result" == "no_ports_to_test" ]]; then
        __print_info "No ports configured in KGSM instances"
      else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "PORT ACCESSIBILITY TEST RESULTS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "$result" | while IFS= read -r line; do
          if [[ "$line" == test:* ]]; then
            # Format: test:instance:port/protocol:result
            local instance port_proto test_result
            instance=$(echo "$line" | cut -d: -f2)
            port_proto=$(echo "$line" | cut -d: -f3)
            test_result=$(echo "$line" | cut -d: -f4-)

            if [[ "$test_result" == "accessible" ]]; then
              echo "  ✓ [$instance] $port_proto - ACCESSIBLE"
            else
              local reason="${test_result#not_accessible:}"
              echo "  ✗ [$instance] $port_proto - NOT ACCESSIBLE ($reason)"
            fi
          fi
        done
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
      fi
      ;;
    *)
      __print_error "Failed to test instance ports"
      ;;
  esac

  return $exit_code
}

function _cmd_ip() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        show_usage_ip
        return 0
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local overall_exit_code=0

  # Get external IP
  __print_info "Retrieving external IP address..."
  local external_ip
  external_ip=$(__logic_get_external_ip)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_CHECKED)
      __print_success "External IP: $external_ip"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_warning "Cannot retrieve external IP: curl or wget not available"
      overall_exit_code=$EC_MISSING_DEPENDENCY
      ;;
    *)
      __print_warning "Failed to retrieve external IP address"
      overall_exit_code=$EC_ERROR
      ;;
  esac

  # Get local IP(s)
  __print_info "Retrieving local IP address(es)..."
  local local_ips
  local_ips=$(__logic_get_local_ip)
  exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_CHECKED)
      echo ""
      __print_success "Local IP address(es):"
      echo "$local_ips" | while read -r ip; do
        echo "  $ip"
      done
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_warning "Cannot retrieve local IPs: required commands not available"
      if [[ $overall_exit_code -eq 0 ]]; then
        overall_exit_code=$EC_MISSING_DEPENDENCY
      fi
      ;;
    *)
      __print_warning "Failed to retrieve local IP addresses"
      if [[ $overall_exit_code -eq 0 ]]; then
        overall_exit_code=$EC_ERROR
      fi
      ;;
  esac

  return $overall_exit_code
}

function _cmd_dns() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        echo "Display DNS server configuration"
        echo "Usage: $self dns"
        return 0
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local result
  result=$(__logic_get_dns_info)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_NETWORK_PORT_CHECKED)
      __print_success "DNS Servers:"
      echo "$result" | tr ' ' '\n' | while read -r dns; do
        [[ -n "$dns" ]] && echo "  $dns"
      done
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Cannot retrieve DNS information"
      __print_error "Required tools or files not available"
      ;;
    *)
      __print_error "Failed to retrieve DNS information"
      ;;
  esac

  return $exit_code
}

function _cmd_help() {
  local command="$1"
  local subcommand="$2"

  if [[ -z "$command" ]]; then
    show_usage
  else
    case "$command" in
      ports)
        case "$subcommand" in
          check)
            show_usage_ports_check
            ;;
          kill)
            show_usage_ports_kill
            ;;
          *)
            echo "Help for 'ports' command"
            echo ""
            echo "Available subcommands:"
            echo "  check <port> [protocol]     Check if port is in use"
            echo "  list-used                   List all used ports"
            echo "  conflicts                   Find port conflicts"
            echo "  kill <port> [protocol]      Kill process using port"
            echo ""
            echo "Use '$self help ports <subcommand>' for detailed help"
            ;;
        esac
        ;;
      test-port)
        show_usage_test_port
        ;;
      ip)
        show_usage_ip
        ;;
      *)
        __print_error "Unknown command: $command"
        __print_error "Use '$self help' for available commands"
        return $EC_INVALID_ARG
        ;;
    esac
  fi
  return 0
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

# Command routing
case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  -h | --help | help)
    _cmd_help "$@"
    exit $?
    ;;
  ports)
    _cmd_ports "$@"
    exit $?
    ;;
  test-port)
    _cmd_test_port "$@"
    exit $?
    ;;
  test-all)
    _cmd_test_all "$@"
    exit $?
    ;;
  ip)
    _cmd_ip "$@"
    exit $?
    ;;
  dns)
    _cmd_dns "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$self --help' for usage information"
    exit $EC_INVALID_ARG
    ;;
esac
