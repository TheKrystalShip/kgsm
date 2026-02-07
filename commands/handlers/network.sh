#!/usr/bin/env bash

# =============================================================================
# KGSM Network Logic Library
# =============================================================================
#
# Pure business logic for network-level operations including:
# - Port checking and conflict detection
# - Network connectivity testing
# - DNS information retrieval
#
# All functions are pure logic - no user-facing I/O.
# Return values are standardized exit codes from core/errors.sh
#
# =============================================================================

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_NETWORK_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# PORT MANAGEMENT
# =============================================================================

# Check if a specific port is in use
# Args:
#   $1 - Port number to check
#   $2 - Protocol (tcp/udp, optional, defaults to "tcp")
# Returns:
#   EC_SUCCESS_NETWORK_PORT_FREE - Port is free (echoes "free")
#   EC_SUCCESS_NETWORK_PORT_IN_USE - Port is in use (echoes process info)
#   EC_INVALID_ARG - Invalid port number
#   EC_MISSING_DEPENDENCY - Required tools not available
function __logic_check_port() {
  local port="$1"
  local protocol="${2:-tcp}"

  # Validate port number
  if [[ -z "$port" ]]; then
    return $EC_INVALID_ARG
  fi

  if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate protocol
  if [[ "$protocol" != "tcp" ]] && [[ "$protocol" != "udp" ]]; then
    return $EC_INVALID_ARG
  fi

  # Try ss first (modern, preferred)
  if command -v ss >/dev/null 2>&1; then
    local output
    if [[ "$protocol" == "tcp" ]]; then
      output=$(ss -tlnp 2>/dev/null | grep -E ":${port}\s")
    else
      output=$(ss -ulnp 2>/dev/null | grep -E ":${port}\s")
    fi

    if [[ -n "$output" ]]; then
      # Extract process info
      local process_info
      process_info=$(echo "$output" | awk '{print $NF}' | head -1)
      echo "in_use:$process_info"
      return $EC_SUCCESS_NETWORK_PORT_IN_USE
    else
      echo "free"
      return $EC_SUCCESS_NETWORK_PORT_FREE
    fi
  fi

  # Fallback to netstat
  if command -v netstat >/dev/null 2>&1; then
    local output
    if [[ "$protocol" == "tcp" ]]; then
      output=$(netstat -tlnp 2>/dev/null | grep -E ":${port}\s")
    else
      output=$(netstat -ulnp 2>/dev/null | grep -E ":${port}\s")
    fi

    if [[ -n "$output" ]]; then
      local process_info
      process_info=$(echo "$output" | awk '{print $NF}' | head -1)
      echo "in_use:$process_info"
      return $EC_SUCCESS_NETWORK_PORT_IN_USE
    else
      echo "free"
      return $EC_SUCCESS_NETWORK_PORT_FREE
    fi
  fi

  # Fallback to lsof
  if command -v lsof >/dev/null 2>&1; then
    local output
    if [[ "$protocol" == "tcp" ]]; then
      output=$(lsof -iTCP:"$port" -sTCP:LISTEN -n -P 2>/dev/null)
    else
      output=$(lsof -iUDP:"$port" -n -P 2>/dev/null)
    fi

    if [[ -n "$output" ]]; then
      local process_info
      process_info=$(echo "$output" | tail -1 | awk '{print $1":"$2}')
      echo "in_use:$process_info"
      return $EC_SUCCESS_NETWORK_PORT_IN_USE
    else
      echo "free"
      return $EC_SUCCESS_NETWORK_PORT_FREE
    fi
  fi

  # No suitable tool available
  return $EC_MISSING_DEPENDENCY
}

export -f __logic_check_port

# List all ports currently in use on the system
# Returns:
#   EC_SUCCESS_NETWORK_PORT_CHECKED - Port list retrieved (echoes port info)
#   EC_MISSING_DEPENDENCY - Required tools not available
function __logic_list_used_ports() {
  # Try ss first (modern, preferred)
  if command -v ss >/dev/null 2>&1; then
    local tcp_ports udp_ports
    tcp_ports=$(ss -tlnp 2>/dev/null | tail -n +2 | awk '{print $4":"$NF}' | sed 's/.*://g' | sort -u)
    udp_ports=$(ss -ulnp 2>/dev/null | tail -n +2 | awk '{print $4":"$NF}' | sed 's/.*://g' | sort -u)

    if [[ -n "$tcp_ports" ]] || [[ -n "$udp_ports" ]]; then
      echo "TCP_PORTS:"
      echo "$tcp_ports"
      echo "UDP_PORTS:"
      echo "$udp_ports"
      return $EC_SUCCESS_NETWORK_PORT_CHECKED
    fi
  fi

  # Fallback to netstat
  if command -v netstat >/dev/null 2>&1; then
    local tcp_ports udp_ports
    tcp_ports=$(netstat -tlnp 2>/dev/null | tail -n +3 | awk '{print $4":"$NF}' | sed 's/.*://g' | sort -u)
    udp_ports=$(netstat -ulnp 2>/dev/null | tail -n +3 | awk '{print $4":"$NF}' | sed 's/.*://g' | sort -u)

    if [[ -n "$tcp_ports" ]] || [[ -n "$udp_ports" ]]; then
      echo "TCP_PORTS:"
      echo "$tcp_ports"
      echo "UDP_PORTS:"
      echo "$udp_ports"
      return $EC_SUCCESS_NETWORK_PORT_CHECKED
    fi
  fi

  return $EC_MISSING_DEPENDENCY
}

export -f __logic_list_used_ports

# Find port conflicts across KGSM instances
# Returns:
#   EC_SUCCESS_NETWORK_PORT_CHECKED - Conflicts checked (echoes conflict info or "no_conflicts")
#   EC_MISSING_DEPENDENCY - Required tools not available
function __logic_find_port_conflicts() {
  local instances_dir="$KGSM_INSTANCES_DIR"

  if [[ ! -d "$instances_dir" ]]; then
    echo "no_conflicts"
    return $EC_SUCCESS_NETWORK_PORT_CHECKED
  fi

  # Collect all instance ports
  declare -A port_map
  local conflicts_found=false

  # Iterate over directory symlinks
  for instance_dir in "$instances_dir"/*/*/; do
    # Remove trailing slash
    instance_dir="${instance_dir%/}"

    # Skip if not a symlink
    [[ ! -L "$instance_dir" ]] && continue

    local _instance_name
    _instance_name=$(basename "$instance_dir")

    # Find config file inside symlinked directory
    local instance_config="${instance_dir}/${_instance_name}.config.ini"
    [[ ! -f "$instance_config" ]] && continue

    # Extract ports from config
    local ports
    ports=$(grep "^instance_ports=" "$instance_config" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [[ -z "$ports" ]]; then
      continue
    fi

    # Parse ports (format: "port1:port2/tcp|port3/udp")
    IFS='|' read -ra port_entries <<< "$ports"
    for entry in "${port_entries[@]}"; do
      # Extract port and protocol
      local port protocol
      if [[ "$entry" =~ ([0-9]+)/([a-z]+) ]]; then
        port="${BASH_REMATCH[1]}"
        protocol="${BASH_REMATCH[2]}"
      elif [[ "$entry" =~ ^[0-9]+$ ]]; then
        port="$entry"
        protocol="tcp"
      else
        continue
      fi

      local key="${port}/${protocol}"

      # Check if port is already mapped to another instance
      if [[ -n "${port_map[$key]}" ]]; then
        conflicts_found=true
        echo "conflict:$port/$protocol:${port_map[$key]}:$_instance_name"
      else
        port_map[$key]="$_instance_name"
      fi

      # Also check if port is in use by non-KGSM process
      local status
      status=$(__logic_check_port "$port" "$protocol" 2>/dev/null)
      if [[ "$status" == in_use:* ]]; then
        local process_info="${status#in_use:}"
        # Check if it's not a known KGSM instance process
        if [[ "$process_info" != *"$_instance_name"* ]]; then
          conflicts_found=true
          echo "external_conflict:$port/$protocol:$_instance_name:$process_info"
        fi
      fi
    done
  done

  if [[ "$conflicts_found" == false ]]; then
    echo "no_conflicts"
  fi

  return $EC_SUCCESS_NETWORK_PORT_CHECKED
}

export -f __logic_find_port_conflicts

# Kill process using a specific port
# Args:
#   $1 - Port number
#   $2 - Protocol (tcp/udp, optional, defaults to "tcp")
# Returns:
#   EC_SUCCESS - Process killed successfully
#   EC_NOT_FOUND - No process using port
#   EC_INVALID_ARG - Invalid arguments
#   EC_PERMISSION - Insufficient permissions
#   EC_MISSING_DEPENDENCY - Required tools not available
function __logic_kill_port_process() {
  local port="$1"
  local protocol="${2:-tcp}"

  # Validate arguments
  if [[ -z "$port" ]]; then
    return $EC_INVALID_ARG
  fi

  if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    return $EC_INVALID_ARG
  fi

  # Find PID using the port
  local pid=""

  # Try lsof first (most reliable for getting PID)
  if command -v lsof >/dev/null 2>&1; then
    if [[ "$protocol" == "tcp" ]]; then
      pid=$(lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)
    else
      pid=$(lsof -iUDP:"$port" -t 2>/dev/null | head -1)
    fi
  fi

  # Fallback to ss
  if [[ -z "$pid" ]] && command -v ss >/dev/null 2>&1; then
    local output
    if [[ "$protocol" == "tcp" ]]; then
      output=$(ss -tlnp 2>/dev/null | grep -E ":${port}\s")
    else
      output=$(ss -ulnp 2>/dev/null | grep -E ":${port}\s")
    fi

    if [[ -n "$output" ]]; then
      # Extract PID from ss output (format: "users:(("process",pid=123,...))")
      pid=$(echo "$output" | grep -oP 'pid=\K[0-9]+' | head -1)
    fi
  fi

  # Fallback to netstat
  if [[ -z "$pid" ]] && command -v netstat >/dev/null 2>&1; then
    local output
    if [[ "$protocol" == "tcp" ]]; then
      output=$(netstat -tlnp 2>/dev/null | grep -E ":${port}\s")
    else
      output=$(netstat -ulnp 2>/dev/null | grep -E ":${port}\s")
    fi

    if [[ -n "$output" ]]; then
      # Extract PID (format: "pid/program_name")
      pid=$(echo "$output" | awk '{print $NF}' | grep -oP '^\d+' | head -1)
    fi
  fi

  # Check if we found a PID
  if [[ -z "$pid" ]]; then
    # No suitable tool available or port not in use
    if ! command -v lsof >/dev/null 2>&1 && ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1; then
      return $EC_MISSING_DEPENDENCY
    fi
    return $EC_NOT_FOUND
  fi

  # Try to kill the process
  if ! kill -15 "$pid" >/dev/null 2>&1; then
    return $EC_PERMISSION
  fi

  # Wait a moment for graceful shutdown
  sleep 1

  # Check if process is still running, force kill if needed
  if kill -0 "$pid" >/dev/null 2>&1; then
    if ! kill -9 "$pid" >/dev/null 2>&1; then
      return $EC_PERMISSION
    fi
  fi

  return $EC_SUCCESS
}

export -f __logic_kill_port_process

# =============================================================================
# NETWORK CONNECTIVITY TESTING
# =============================================================================

# Test if a port is externally accessible
# Args:
#   $1 - Port number to test
#   $2 - Protocol (tcp/udp, optional, defaults to "tcp")
# Returns:
#   EC_SUCCESS_NETWORK_PORT_CHECKED - Test completed (echoes "accessible" or "not_accessible:reason")
#   EC_INVALID_ARG - Invalid arguments
#   EC_MISSING_DEPENDENCY - Required tools not available
function __logic_test_port_accessibility() {
  local port="$1"
  local protocol="${2:-tcp}"

  # Validate port
  if [[ -z "$port" ]]; then
    return $EC_INVALID_ARG
  fi

  if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    return $EC_INVALID_ARG
  fi

  # First check if port is actually listening locally
  local local_status
  local_status=$(__logic_check_port "$port" "$protocol" 2>/dev/null)

  if [[ "$local_status" != in_use:* ]]; then
    echo "not_accessible:port_not_listening"
    return $EC_SUCCESS_NETWORK_PORT_CHECKED
  fi

  # Get external IP
  local external_ip
  if command -v curl >/dev/null 2>&1; then
    external_ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null | tr -d '\n')
  elif command -v wget >/dev/null 2>&1; then
    local timeout="${config_wget_timeout_seconds:-60}"
    external_ip=$(wget -qO- --timeout="$timeout" https://icanhazip.com 2>/dev/null | tr -d '\n')
  fi

  if [[ -z "$external_ip" ]]; then
    echo "not_accessible:cannot_determine_external_ip"
    return $EC_SUCCESS_NETWORK_PORT_CHECKED
  fi

  # For TCP, try to connect to ourselves from external perspective
  # Note: This is a simplified check - full external testing would require a remote service
  if [[ "$protocol" == "tcp" ]]; then
    # Check if nc (netcat) is available
    if command -v nc >/dev/null 2>&1; then
      # Try to connect with a timeout
      if timeout 3 nc -zv "$external_ip" "$port" >/dev/null 2>&1; then
        echo "accessible"
        return $EC_SUCCESS_NETWORK_PORT_CHECKED
      fi
    elif command -v telnet >/dev/null 2>&1; then
      # Fallback to telnet
      if timeout 3 bash -c "echo | telnet $external_ip $port" >/dev/null 2>&1; then
        echo "accessible"
        return $EC_SUCCESS_NETWORK_PORT_CHECKED
      fi
    fi
  fi

  # If we can't definitively test, provide a "probable" status
  echo "not_accessible:cannot_test_externally"
  return $EC_SUCCESS_NETWORK_PORT_CHECKED
}

export -f __logic_test_port_accessibility

# Test all KGSM instance ports for accessibility
# Returns:
#   EC_SUCCESS_NETWORK_PORT_CHECKED - Tests completed (echoes results)
#   EC_MISSING_DEPENDENCY - Required tools not available
function __logic_test_all_instance_ports() {
  local instances_dir="$KGSM_INSTANCES_DIR"

  if [[ ! -d "$instances_dir" ]]; then
    echo "no_instances"
    return $EC_SUCCESS_NETWORK_PORT_CHECKED
  fi

  local tests_run=false

  # Iterate over directory symlinks
  for instance_dir in "$instances_dir"/*/*/; do
    # Remove trailing slash
    instance_dir="${instance_dir%/}"

    # Skip if not a symlink
    [[ ! -L "$instance_dir" ]] && continue

    local _instance_name
    _instance_name=$(basename "$instance_dir")

    # Find config file inside symlinked directory
    local instance_config="${instance_dir}/${_instance_name}.config.ini"
    [[ ! -f "$instance_config" ]] && continue

    # Extract ports
    local ports
    ports=$(grep "^instance_ports=" "$instance_config" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [[ -z "$ports" ]]; then
      continue
    fi

    # Parse and test each port
    IFS='|' read -ra port_entries <<< "$ports"
    for entry in "${port_entries[@]}"; do
      local port protocol
      if [[ "$entry" =~ ([0-9]+)/([a-z]+) ]]; then
        port="${BASH_REMATCH[1]}"
        protocol="${BASH_REMATCH[2]}"
      elif [[ "$entry" =~ ^[0-9]+$ ]]; then
        port="$entry"
        protocol="tcp"
      else
        continue
      fi

      tests_run=true
      local result
      result=$(__logic_test_port_accessibility "$port" "$protocol" 2>/dev/null)
      echo "test:$_instance_name:$port/$protocol:$result"
    done
  done

  if [[ "$tests_run" == false ]]; then
    echo "no_ports_to_test"
  fi

  return $EC_SUCCESS_NETWORK_PORT_CHECKED
}

export -f __logic_test_all_instance_ports

# =============================================================================
# IP ADDRESS INFORMATION
# =============================================================================

# Get the server's external IP address
# Returns:
#   EC_SUCCESS_NETWORK_PORT_CHECKED - IP retrieved successfully (echoes IP)
#   EC_MISSING_DEPENDENCY - Required tool not available
#   EC_ERROR - Failed to retrieve IP
function __logic_get_external_ip() {
  # Try curl first (preferred)
  if command -v curl >/dev/null 2>&1; then
    local ip
    ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null)
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return $EC_SUCCESS_NETWORK_PORT_CHECKED
    fi
  fi

  # Fallback to wget
  if command -v wget >/dev/null 2>&1; then
    local ip
    local timeout="${config_wget_timeout_seconds:-60}"
    ip=$(wget -qO- --timeout="$timeout" https://icanhazip.com 2>/dev/null)
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return $EC_SUCCESS_NETWORK_PORT_CHECKED
    fi
  fi

  # Neither tool available or both failed
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  return $EC_ERROR
}

export -f __logic_get_external_ip

# Get the server's local IP address(es)
# Returns:
#   EC_SUCCESS_NETWORK_PORT_CHECKED - IP(s) retrieved successfully (echoes IPs)
#   EC_MISSING_DEPENDENCY - Required tool not available
#   EC_ERROR - Failed to retrieve IP
function __logic_get_local_ip() {
  # Check if hostname command exists
  if ! command -v hostname >/dev/null 2>&1; then
    # Try ip command as fallback
    if command -v ip >/dev/null 2>&1; then
      local ips
      ips=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 2>/dev/null)
      if [[ -n "$ips" ]]; then
        echo "$ips"
        return $EC_SUCCESS_NETWORK_PORT_CHECKED
      fi
    fi
    return $EC_MISSING_DEPENDENCY
  fi

  # Get local IP addresses
  local ips
  ips=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$')
  if [[ -n "$ips" ]]; then
    echo "$ips"
    return $EC_SUCCESS_NETWORK_PORT_CHECKED
  fi

  return $EC_ERROR
}

export -f __logic_get_local_ip

# =============================================================================
# DNS INFORMATION
# =============================================================================

# Get DNS server information
# Returns:
#   EC_SUCCESS_NETWORK_PORT_CHECKED - DNS info retrieved (echoes DNS servers)
#   EC_MISSING_DEPENDENCY - Required tools not available
function __logic_get_dns_info() {
  # Try systemd-resolve first (modern systems)
  if command -v systemd-resolve >/dev/null 2>&1; then
    local dns_servers
    dns_servers=$(systemd-resolve --status 2>/dev/null | grep "DNS Servers:" | awk '{$1=$2=""; print $0}' | xargs)
    if [[ -n "$dns_servers" ]]; then
      echo "$dns_servers"
      return $EC_SUCCESS_NETWORK_PORT_CHECKED
    fi
  fi

  # Fallback to resolvectl (newer systemd)
  if command -v resolvectl >/dev/null 2>&1; then
    local dns_servers
    dns_servers=$(resolvectl status 2>/dev/null | grep "DNS Servers:" | awk '{$1=$2=""; print $0}' | xargs)
    if [[ -n "$dns_servers" ]]; then
      echo "$dns_servers"
      return $EC_SUCCESS_NETWORK_PORT_CHECKED
    fi
  fi

  # Fallback to /etc/resolv.conf
  if [[ -f /etc/resolv.conf ]]; then
    local dns_servers
    dns_servers=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
    if [[ -n "$dns_servers" ]]; then
      echo "$dns_servers" | xargs
      return $EC_SUCCESS_NETWORK_PORT_CHECKED
    fi
  fi

  return $EC_MISSING_DEPENDENCY
}

export -f __logic_get_dns_info

# =============================================================================
# MODULE LOADED FLAG
# =============================================================================

declare -g KGSM_LOGIC_NETWORK_LOADED=1
export KGSM_LOGIC_NETWORK_LOADED
