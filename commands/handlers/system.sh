#!/usr/bin/env bash

# =============================================================================
# KGSM System Logic Library
# =============================================================================
#
# Pure business logic for system-level operations including:
# - System shutdown and restart
# - Network information retrieval
# - System status checks
#
# All functions are pure logic - no user-facing I/O.
# Return values are standardized exit codes from core/errors.sh
#
# =============================================================================

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# =============================================================================
# SYSTEM POWER MANAGEMENT
# =============================================================================

# Schedule a system shutdown
# Args:
#   $1 - Time delay in minutes (0 for immediate, positive integer for delay)
# Returns:
#   EC_SUCCESS_SYSTEM_SHUTDOWN - Shutdown scheduled successfully
#   EC_INVALID_ARG - Invalid time argument
#   EC_PERMISSION - Insufficient permissions
#   EC_MISSING_DEPENDENCY - shutdown command not available
function __logic_schedule_shutdown() {
  local time_minutes="$1"

  # Validate argument
  if [[ -z "$time_minutes" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate numeric value
  if ! [[ "$time_minutes" =~ ^[0-9]+$ ]]; then
    return $EC_INVALID_ARG
  fi

  # Check if shutdown command exists
  if ! command -v shutdown >/dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  # Schedule shutdown
  if [[ "$time_minutes" -eq 0 ]]; then
    # Immediate shutdown
    if ! sudo shutdown -h now >/dev/null 2>&1; then
      return $EC_PERMISSION
    fi
  else
    # Delayed shutdown
    if ! sudo shutdown -h "+$time_minutes" >/dev/null 2>&1; then
      return $EC_PERMISSION
    fi
  fi

  return $EC_SUCCESS_SYSTEM_SHUTDOWN
}

export -f __logic_schedule_shutdown

# Cancel a scheduled shutdown
# Returns:
#   EC_OKAY - Shutdown cancelled successfully
#   EC_PERMISSION - Insufficient permissions
#   EC_MISSING_DEPENDENCY - shutdown command not available
function __logic_cancel_shutdown() {
  # Check if shutdown command exists
  if ! command -v shutdown >/dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  # Cancel shutdown
  if ! sudo shutdown -c >/dev/null 2>&1; then
    return $EC_PERMISSION
  fi

  return $EC_OKAY
}

export -f __logic_cancel_shutdown

# Schedule a system restart
# Args:
#   $1 - Time delay in minutes (0 for immediate, positive integer for delay)
# Returns:
#   EC_SUCCESS_SYSTEM_RESTART - Restart scheduled successfully
#   EC_INVALID_ARG - Invalid time argument
#   EC_PERMISSION - Insufficient permissions
#   EC_MISSING_DEPENDENCY - shutdown command not available
function __logic_schedule_restart() {
  local time_minutes="$1"

  # Validate argument
  if [[ -z "$time_minutes" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate numeric value
  if ! [[ "$time_minutes" =~ ^[0-9]+$ ]]; then
    return $EC_INVALID_ARG
  fi

  # Check if shutdown command exists
  if ! command -v shutdown >/dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  # Schedule restart
  if [[ "$time_minutes" -eq 0 ]]; then
    # Immediate restart
    if ! sudo shutdown -r now >/dev/null 2>&1; then
      return $EC_PERMISSION
    fi
  else
    # Delayed restart
    if ! sudo shutdown -r "+$time_minutes" >/dev/null 2>&1; then
      return $EC_PERMISSION
    fi
  fi

  return $EC_SUCCESS_SYSTEM_RESTART
}

export -f __logic_schedule_restart

# =============================================================================
# SYSTEM STATUS CHECKS
# =============================================================================

# Get system uptime information
# Returns:
#   EC_SUCCESS_SYSTEM_INFO_RETRIEVED - Uptime retrieved successfully (echoes uptime)
#   EC_MISSING_DEPENDENCY - uptime command not available
function __logic_get_uptime() {
  # Check if uptime command exists
  if ! command -v uptime >/dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  # Get uptime
  local uptime_info
  uptime_info=$(uptime -p 2>/dev/null)

  # Fallback for systems without -p flag
  if [[ -z "$uptime_info" ]]; then
    uptime_info=$(uptime 2>/dev/null)
  fi

  if [[ -n "$uptime_info" ]]; then
    echo "$uptime_info"
    return $EC_SUCCESS_SYSTEM_INFO_RETRIEVED
  fi

  return $EC_GENERAL
}

export -f __logic_get_uptime

# Check if system reboot is required
# Returns:
#   EC_OKAY - Reboot required status checked (echoes "true" or "false")
#   EC_GENERAL - Could not determine reboot status
function __logic_check_reboot_required() {
  # Check for /var/run/reboot-required (Debian/Ubuntu)
  if [[ -f /var/run/reboot-required ]]; then
    echo "true"
    return $EC_OKAY
  fi

  # Check for other indicators
  # RHEL/CentOS - check if needs-restarting exists
  if command -v needs-restarting >/dev/null 2>&1; then
    if needs-restarting -r >/dev/null 2>&1; then
      echo "false"
      return $EC_OKAY
    else
      echo "true"
      return $EC_OKAY
    fi
  fi

  # No indicators found - assume no reboot required
  echo "false"
  return $EC_OKAY
}

export -f __logic_check_reboot_required

# Get system load averages
# Returns:
#   EC_SUCCESS_SYSTEM_INFO_RETRIEVED - Load retrieved successfully (echoes load averages)
#   EC_GENERAL - Failed to retrieve load
function __logic_get_load_average() {
  # Check if uptime command exists (most reliable)
  if command -v uptime >/dev/null 2>&1; then
    local load
    load=$(uptime | awk -F'load average:' '{print $2}' | xargs 2>/dev/null)
    if [[ -n "$load" ]]; then
      echo "$load"
      return $EC_SUCCESS_SYSTEM_INFO_RETRIEVED
    fi
  fi

  # Fallback to /proc/loadavg
  if [[ -f /proc/loadavg ]]; then
    local load
    load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
    if [[ -n "$load" ]]; then
      echo "$load"
      return $EC_SUCCESS_SYSTEM_INFO_RETRIEVED
    fi
  fi

  return $EC_GENERAL
}

export -f __logic_get_load_average

# Get memory usage information
# Returns:
#   EC_SUCCESS_SYSTEM_INFO_RETRIEVED - Memory info retrieved successfully (echoes JSON)
#   EC_MISSING_DEPENDENCY - Required command not available
function __logic_get_memory_info() {
  # Check if free command exists
  if ! command -v free >/dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  # Get memory info
  local mem_info
  mem_info=$(free -h | grep '^Mem:' 2>/dev/null)

  if [[ -n "$mem_info" ]]; then
    echo "$mem_info"
    return $EC_SUCCESS_SYSTEM_INFO_RETRIEVED
  fi

  return $EC_GENERAL
}

export -f __logic_get_memory_info

# Get disk usage information
# Returns:
#   EC_SUCCESS_SYSTEM_INFO_RETRIEVED - Disk info retrieved successfully (echoes info)
#   EC_MISSING_DEPENDENCY - df command not available
function __logic_get_disk_usage() {
  # Check if df command exists
  if ! command -v df >/dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  # Get disk usage for root filesystem
  local disk_info
  disk_info=$(df -h / | tail -1 2>/dev/null)

  if [[ -n "$disk_info" ]]; then
    echo "$disk_info"
    return $EC_SUCCESS_SYSTEM_INFO_RETRIEVED
  fi

  return $EC_GENERAL
}

export -f __logic_get_disk_usage

# =============================================================================
# MODULE LOADED FLAG
# =============================================================================

export KGSM_LOGIC_SYSTEM_LOADED=1
