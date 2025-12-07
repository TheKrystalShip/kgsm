#!/usr/bin/env bash

# Disabling SC2086 globally
# shellcheck disable=SC2086

## Colored output
# Check if stdout is tty
if test -t 1; then
  ncolors=0

  # Check for availability of tput
  if command -v tput >/dev/null 2>&1; then
    ncolors="$(tput colors 2>/dev/null || echo 0)"
  fi

  # More than 8 means it supports colors
  if [[ $ncolors ]] && [[ "$ncolors" -gt 8 ]]; then
    export COLOR_RED="\033[0;31m"
    export COLOR_GREEN="\033[0;32m"
    export COLOR_ORANGE="\033[0;33m"
    export COLOR_BLUE="\033[0;34m"
    export COLOR_END="\033[0m"
  else
    # Fallback: no colors
    export COLOR_RED=""
    export COLOR_GREEN=""
    export COLOR_ORANGE=""
    export COLOR_BLUE=""
    export COLOR_END=""
  fi
fi

export LOG_LEVEL_SUCCESS="SUCCESS"
export LOG_LEVEL_INFO="INFO"
export LOG_LEVEL_WARNING="WARNING"
export LOG_LEVEL_ERROR="ERROR"

# Initialize logging variables (will be set properly when KGSM_ROOT is available)
export LOGS_SOURCE_DIR=""
export LOG_FILE=""

# Don't call directly, use the __print_* functions instead
function __log_message() {
  local log_level="$1"
  local message="$2"

  # Input validation
  if [[ -z "$log_level" ]]; then
    echo "ERROR: Log level is required" >&2
    return $EC_INVALID_ARG
  fi

  if [[ -z "$message" ]]; then
    echo "ERROR: Log message is required" >&2
    return $EC_INVALID_ARG
  fi

  # Validate log level
  case "$log_level" in
    "$LOG_LEVEL_SUCCESS"|"$LOG_LEVEL_INFO"|"$LOG_LEVEL_WARNING"|"$LOG_LEVEL_ERROR")
      ;;
    *)
      echo "ERROR: Invalid log level: $log_level" >&2
      return $EC_INVALID_ARG
      ;;
  esac

  # Initialize logging paths if not set
  if [[ -z "$LOGS_SOURCE_DIR" ]] || [[ -z "$LOG_FILE" ]]; then
    # KGSM_ROOT is guaranteed to be set by common.sh before this module loads
    export LOGS_SOURCE_DIR="$KGSM_ROOT/logs"
    export LOG_FILE="$LOGS_SOURCE_DIR/kgsm.log"
  fi

  # Sanitize message to prevent injection
  message=$(printf '%s' "$message" | sed 's/[[:cntrl:]]//g')

  # $message should contain as much information about the caller as possible,
  # so we can trace back the error or log entry.
  # BASH_SOURCE[-1] gives us the name of the script that called this function,
  # BASH_LINENO[1] gives us the line number in that script where this function was called.
  local caller_info=""
  if [[ ${#BASH_SOURCE[@]} -gt 1 ]]; then
    local caller_file="${BASH_SOURCE[-1]##*/}"
    local caller_line="${BASH_LINENO[1]}"
    caller_info="${caller_file}:${caller_line}"
  else
    caller_info="unknown:0"
  fi

  local full_message="${caller_info} $message"

  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown-time')"

  # This works if declared in here but not if declared outside
  # of the function... why?
  declare -A LOG_LEVEL_COLOR_MAP=(
    ["$LOG_LEVEL_SUCCESS"]="$COLOR_GREEN"
    ["$LOG_LEVEL_INFO"]="$COLOR_BLUE"
    ["$LOG_LEVEL_WARNING"]="$COLOR_ORANGE"
    ["$LOG_LEVEL_ERROR"]="$COLOR_RED"
  )

  # Get the color for the log level (with fallback)
  local colored_log_level="${LOG_LEVEL_COLOR_MAP[$log_level]:-$COLOR_END}"

  local printable_log_entry="[${colored_log_level}${log_level}${COLOR_END}] $full_message"
  local log_entry="[$timestamp] [$log_level] $full_message"

  # Ensure log directory exists (__create_dir is provided by system.sh)
  if ! __create_dir "$LOGS_SOURCE_DIR" 2>/dev/null; then
    echo "ERROR: Failed to create log directory: $LOGS_SOURCE_DIR" >&2
    # Continue without file logging, but still output to console
  else
    # Rotate log file if it reaches the size limit
    # config_log_max_size_kb is guaranteed to be set by config.sh
    local max_size_kb="${config_log_max_size_kb:-1024}"  # Default 1MB
    if [[ -f "$LOG_FILE" ]]; then
      local file_size
      if file_size=$(stat --format=%s "$LOG_FILE" 2>/dev/null); then
        if [[ "$file_size" -ge $((max_size_kb * 1024)) ]]; then
          local backup_file; backup_file="$LOG_FILE.$(date '+%Y%m%d%H%M%S' 2>/dev/null || echo 'backup')"
          if ! mv "$LOG_FILE" "$backup_file" 2>/dev/null; then
            echo "WARNING: Failed to rotate log file" >&2
          fi
        fi
      fi
    fi

    # Write to log file if enabled
    # config_enable_logging is guaranteed to be set by config.sh
    if [[ "${config_enable_logging:-true}" == "true" ]]; then
      if ! echo "$log_entry" >>"$LOG_FILE" 2>/dev/null; then
        echo "WARNING: Failed to write to log file: $LOG_FILE" >&2
      fi
    fi
  fi

  # Output to console with error handling
  if [[ "$log_level" = "$LOG_LEVEL_ERROR" ]]; then
    if ! echo -e "$printable_log_entry" >&2; then
      # Fallback without colors if echo -e fails
      echo "[$log_level] $full_message" >&2
    fi
  else
    if ! echo -e "$printable_log_entry"; then
      # Fallback without colors if echo -e fails
      echo "[$log_level] $full_message"
    fi
  fi
}

# File-only logging function that writes to a custom log file without terminal output
function __log_message_file_only() {
  local log_level="$1"
  local message="$2"
  local custom_log_file="$3"

  # Input validation
  if [[ -z "$log_level" ]]; then
    echo "ERROR: Log level is required" >&2
    return $EC_INVALID_ARG
  fi

  if [[ -z "$message" ]]; then
    echo "ERROR: Log message is required" >&2
    return $EC_INVALID_ARG
  fi

  if [[ -z "$custom_log_file" ]]; then
    echo "ERROR: Custom log file path is required" >&2
    return $EC_INVALID_ARG
  fi

  # Validate log level
  case "$log_level" in
    "$LOG_LEVEL_SUCCESS"|"$LOG_LEVEL_INFO"|"$LOG_LEVEL_WARNING"|"$LOG_LEVEL_ERROR")
      ;;
    *)
      echo "ERROR: Invalid log level: $log_level" >&2
      return $EC_INVALID_ARG
      ;;
  esac

  # Initialize logging paths if not set
  if [[ -z "$LOGS_SOURCE_DIR" ]]; then
    # KGSM_ROOT is guaranteed to be set by common.sh before this module loads
    export LOGS_SOURCE_DIR="$KGSM_ROOT/logs"
  fi

  # Sanitize message to prevent injection
  message=$(printf '%s' "$message" | sed 's/[[:cntrl:]]//g')

  # Get caller information
  local caller_info=""
  if [[ ${#BASH_SOURCE[@]} -gt 1 ]]; then
    local caller_file="${BASH_SOURCE[-1]##*/}"
    local caller_line="${BASH_LINENO[1]}"
    caller_info="${caller_file}:${caller_line}"
  else
    caller_info="unknown:0"
  fi

  local full_message="${caller_info} $message"

  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown-time')"

  local log_entry="[$timestamp] [$log_level] $full_message"

  # Ensure log directory exists (__create_dir is provided by system.sh)
  if ! __create_dir "$LOGS_SOURCE_DIR" 2>/dev/null; then
    echo "ERROR: Failed to create log directory: $LOGS_SOURCE_DIR" >&2
    return 1
  fi

  # Rotate log file if it reaches the size limit
  local max_size_kb="${config_log_max_size_kb:-1024}"  # Default 1MB
  if [[ -f "$custom_log_file" ]]; then
    local file_size
    if file_size=$(stat --format=%s "$custom_log_file" 2>/dev/null); then
      if [[ "$file_size" -ge $((max_size_kb * 1024)) ]]; then
        local backup_file; backup_file="$custom_log_file.$(date '+%Y%m%d%H%M%S' 2>/dev/null || echo 'backup')"
        if ! mv "$custom_log_file" "$backup_file" 2>/dev/null; then
          echo "WARNING: Failed to rotate log file" >&2
        fi
      fi
    fi
  fi

  # Write to custom log file if enabled
  if [[ "${config_enable_logging:-true}" == "true" ]]; then
    if ! echo "$log_entry" >>"$custom_log_file" 2>/dev/null; then
      echo "WARNING: Failed to write to log file: $custom_log_file" >&2
      return 1
    fi
  fi

  return 0
}

export -f __log_message
export -f __log_message_file_only

function __print_error() {
  if [[ $# -eq 0 ]]; then
    echo "ERROR: __print_error requires a message argument" >&2
    return $EC_INVALID_ARG
  fi
  __log_message "$LOG_LEVEL_ERROR" "$*"
}

export -f __print_error

function __print_success() {
  if [[ $# -eq 0 ]]; then
    echo "ERROR: __print_success requires a message argument" >&2
    return $EC_INVALID_ARG
  fi
  __log_message "$LOG_LEVEL_SUCCESS" "$*"
}

export -f __print_success

function __print_warning() {
  if [[ $# -eq 0 ]]; then
    echo "ERROR: __print_warning requires a message argument" >&2
    return $EC_INVALID_ARG
  fi
  __log_message "$LOG_LEVEL_WARNING" "$*"
}

export -f __print_warning

function __print_info() {
  if [[ $# -eq 0 ]]; then
    echo "ERROR: __print_info requires a message argument" >&2
    return $EC_INVALID_ARG
  fi
  __log_message "$LOG_LEVEL_INFO" "$*"
}

export -f __print_info

# File-only logging functions that write to custom log files without terminal output
function __print_error_file_only() {
  local custom_log_file="$1"
  shift
  if [[ -z "$custom_log_file" ]] || [[ $# -eq 0 ]]; then
    echo "ERROR: __print_error_file_only requires log file path and message arguments" >&2
    return $EC_INVALID_ARG
  fi
  __log_message_file_only "$LOG_LEVEL_ERROR" "$*" "$custom_log_file"
}

export -f __print_error_file_only

function __print_success_file_only() {
  local custom_log_file="$1"
  shift
  if [[ -z "$custom_log_file" ]] || [[ $# -eq 0 ]]; then
    echo "ERROR: __print_success_file_only requires log file path and message arguments" >&2
    return $EC_INVALID_ARG
  fi
  __log_message_file_only "$LOG_LEVEL_SUCCESS" "$*" "$custom_log_file"
}

export -f __print_success_file_only

function __print_warning_file_only() {
  local custom_log_file="$1"
  shift
  if [[ -z "$custom_log_file" ]] || [[ $# -eq 0 ]]; then
    echo "ERROR: __print_warning_file_only requires log file path and message arguments" >&2
    return $EC_INVALID_ARG
  fi
  __log_message_file_only "$LOG_LEVEL_WARNING" "$*" "$custom_log_file"
}

export -f __print_warning_file_only

function __print_info_file_only() {
  local custom_log_file="$1"
  shift
  if [[ -z "$custom_log_file" ]] || [[ $# -eq 0 ]]; then
    echo "ERROR: __print_info_file_only requires log file path and message arguments" >&2
    return $EC_INVALID_ARG
  fi
  __log_message_file_only "$LOG_LEVEL_INFO" "$*" "$custom_log_file"
}

export -f __print_info_file_only

export KGSM_LOGGING_LOADED=1
