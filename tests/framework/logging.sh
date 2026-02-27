#!/usr/bin/env bash

# KGSM Test Framework - Centralized Logging Module
#
# Author: The Krystal Ship Team
# Version: 1.0
#
# Provides unified, structured logging for the test framework with:
# - Log levels (ERROR, WARN, INFO, DEBUG)
# - Dual output paths (console with colors, file without)
# - Automatic ANSI code stripping for file output
# - Standardized format: [TIMESTAMP] [LEVEL] [SOURCE] message
# - Frequent flushing for reliability

# =============================================================================
# CONSTANTS
# =============================================================================

if [[ -n "${TEST_LOGGING_LOADED:-}" ]]; then
  return 0
fi

# Log levels (numeric values for comparison)
[[ -z "${LOG_LEVEL_DEBUG:-}" ]] && declare -g LOG_LEVEL_DEBUG=0
[[ -z "${LOG_LEVEL_INFO:-}" ]] && declare -g LOG_LEVEL_INFO=1
[[ -z "${LOG_LEVEL_WARN:-}" ]] && declare -g LOG_LEVEL_WARN=2
[[ -z "${LOG_LEVEL_ERROR:-}" ]] && declare -g LOG_LEVEL_ERROR=3
[[ -z "${LOG_LEVEL_SUCCESS:-}" ]] && declare -g LOG_LEVEL_SUCCESS=4

# Log level names
[[ -z "${LOG_LEVEL_NAME_DEBUG:-}" ]] && declare -g LOG_LEVEL_NAME_DEBUG="DEBUG"
[[ -z "${LOG_LEVEL_NAME_INFO:-}" ]] && declare -g LOG_LEVEL_NAME_INFO="INFO"
[[ -z "${LOG_LEVEL_NAME_WARN:-}" ]] && declare -g LOG_LEVEL_NAME_WARN="WARN"
[[ -z "${LOG_LEVEL_NAME_ERROR:-}" ]] && declare -g LOG_LEVEL_NAME_ERROR="ERROR"
[[ -z "${LOG_LEVEL_NAME_SUCCESS:-}" ]] && declare -g LOG_LEVEL_NAME_SUCCESS="SUCCESS"

# Use existing color codes if available
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${PURPLE:=\033[0;35m}"
: "${CYAN:=\033[0;36m}"
: "${NC:=\033[0m}"

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Current log level threshold (default: INFO)
declare -g KGSM_LOG_LEVEL="${KGSM_TEST_LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Convert log level name to numeric value if needed
case "${KGSM_TEST_LOG_LEVEL:-INFO}" in
  DEBUG) KGSM_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
  INFO)  KGSM_LOG_LEVEL=$LOG_LEVEL_INFO ;;
  WARN)  KGSM_LOG_LEVEL=$LOG_LEVEL_WARN ;;
  ERROR) KGSM_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
  SUCCESS) KGSM_LOG_LEVEL=$LOG_LEVEL_SUCCESS ;;
  *)     KGSM_LOG_LEVEL=$LOG_LEVEL_INFO ;;
esac

# =============================================================================
# CORE LOGGING FUNCTIONS
# =============================================================================

# Get ISO 8601 timestamp with timezone
function __log_get_timestamp() {
  date -Iseconds
}

export -f __log_get_timestamp

# Get caller information for source tracking
# Args: $1 = stack frame offset (default: 3)
function __log_get_caller() {
  local frame="${1:-3}"
  local func="${FUNCNAME[$frame]:-main}"
  local line="${BASH_LINENO[$((frame - 1))]:-0}"
  local file="${BASH_SOURCE[$frame]:-unknown}"

  echo "$(basename "$file"):$line in $func()"
}

export -f __log_get_caller

# Strip ANSI escape codes from text
# Args: $1 = text to strip
function __log_strip_ansi() {
  local text="$1"
  echo "$text" | sed 's/\x1b\[[0-9;]*m//g'
}

export -f __log_strip_ansi

# Write log entry to file (plain text, no colors)
# Args: $1 = timestamp, $2 = level, $3 = source, $4 = message
function __log_write_to_file() {
  local timestamp="$1"
  local level="$2"
  local source="$3"
  local message="$4"

  if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
    # Strip any ANSI codes from message
    local clean_message
    clean_message=$(__log_strip_ansi "$message")

    # Write to file with immediate flush
    echo "[$timestamp] [$level] [$source] $clean_message" >> "$KGSM_TEST_LOG"
  fi
}

export -f __log_write_to_file

# Write log entry to console (colored, to stderr)
# Args: $1 = level, $2 = color, $3 = message
function __log_write_to_console() {
  local level="$1"
  local color="$2"
  local message="$3"

  # Only write to console if not being captured by test runner
  # (runner will handle console output separately)
  if [[ "${KGSM_LOG_CONSOLE_ENABLED:-true}" == "true" ]]; then
    printf "${color}[%s]${NC} %s\n" "$level" "$message" >&2
  fi
}

export -f __log_write_to_console

# Main logging function
# Args: $1 = level_num, $2 = level_name, $3 = color, $4 = message, $5 = caller_frame_offset
function __log() {
  local level_num="$1"
  local level_name="$2"
  local color="$3"
  local message="$4"
  local caller_frame="${5:-3}"

  # Check if this log level should be output
  if [[ $level_num -lt $KGSM_LOG_LEVEL ]]; then
    return 0
  fi

  local timestamp
  timestamp=$(__log_get_timestamp)

  local source
  source=$(__log_get_caller "$caller_frame")

  # Write to file (always, regardless of level, for complete audit trail)
  __log_write_to_file "$timestamp" "$level_name" "$source" "$message"

  # Write to console (with colors)
  __log_write_to_console "$level_name" "$color" "$message"
}

export -f __log

# =============================================================================
# PUBLIC API - Log Level Functions
# =============================================================================

# Log debug message
# Args: $1 = message, $2 = caller_frame_offset (optional)
function log_debug() {
  local message="$1"
  local frame="${2:-3}"
  __log $LOG_LEVEL_DEBUG "$LOG_LEVEL_NAME_DEBUG" "$PURPLE" "$message" "$frame"
}

export -f log_debug

# Log info message
# Args: $1 = message, $2 = caller_frame_offset (optional)
function log_info() {
  local message="$1"
  local frame="${2:-3}"
  __log $LOG_LEVEL_INFO "$LOG_LEVEL_NAME_INFO" "$BLUE" "$message" "$frame"
}

export -f log_info

# Log warning message
# Args: $1 = message, $2 = caller_frame_offset (optional)
function log_warning() {
  local message="$1"
  local frame="${2:-3}"
  __log $LOG_LEVEL_WARN "$LOG_LEVEL_NAME_WARN" "$YELLOW" "$message" "$frame"
}

export -f log_warning

# Log error message
# Args: $1 = message, $2 = caller_frame_offset (optional)
function log_error() {
  local message="$1"
  local frame="${2:-3}"
  __log $LOG_LEVEL_ERROR "$LOG_LEVEL_NAME_ERROR" "$RED" "$message" "$frame"
}

export -f log_error

function log_success() {
  local message="$1"
  local frame="${2:-3}"
  __log $LOG_LEVEL_SUCCESS "$LOG_LEVEL_NAME_SUCCESS" "$GREEN" "$message" "$frame"
}

export -f log_success

# =============================================================================
# SPECIALIZED LOGGING FUNCTIONS
# =============================================================================

# Log test step (INFO level with STEP marker)
# Args: $1 = step description
function log_test_step() {
  local step="$1"
  __log $LOG_LEVEL_INFO "$LOG_LEVEL_NAME_INFO" "$CYAN" "[STEP] $step" 3
}

export -f log_test_step

# Log assertion result
# Args: $1 = result (PASS|FAIL), $2 = message, $3 = caller_info
function log_assertion() {
  local result="$1"
  local message="$2"
  local caller_info="$3"

  local timestamp
  timestamp=$(__log_get_timestamp)

  if [[ "$result" == "PASS" ]]; then
    local level="$LOG_LEVEL_NAME_SUCCESS"
    local color="$GREEN"
    local symbol="✓"
  else
    local level="$LOG_LEVEL_NAME_ERROR"
    local color="$RED"
    local symbol="✗"
  fi

  # Write to file in standardized format
  __log_write_to_file "$timestamp" "$level" "$caller_info" "$result: $message"

  # Write structured expected/actual detail line on failure
  if [[ "$result" == "FAIL" && -n "${ASSERT_EXPECTED+x}" && -n "${ASSERT_ACTUAL+x}" ]]; then
    if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
      echo "ASSERT_DETAIL: expected=${ASSERT_EXPECTED} actual=${ASSERT_ACTUAL}" >> "$KGSM_TEST_LOG"
    fi
    unset ASSERT_EXPECTED ASSERT_ACTUAL
  fi

  # Write to console with visual symbol
  if [[ "${KGSM_LOG_CONSOLE_ENABLED:-true}" == "true" ]]; then
    printf "${color}%s %s:${NC} %s\n" "$symbol" "$result" "$message" >&2
  fi
}

export -f log_assertion

# Log raw output from code under test (stderr/stdout capture)
# Args: $1 = output text
function log_captured_output() {
  local output="$1"

  if [[ -n "$output" && -n "${KGSM_TEST_LOG:-}" ]]; then
    # Strip ANSI codes and write to file
    local clean_output
    clean_output=$(__log_strip_ansi "$output")
    echo "$clean_output" >> "$KGSM_TEST_LOG"
  fi
}

export -f log_captured_output

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Set log level dynamically
# Args: $1 = level name (DEBUG|INFO|WARN|ERROR)
function log_set_level() {
  local level_name="$1"

  case "$level_name" in
    DEBUG) KGSM_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
    INFO)  KGSM_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    WARN)  KGSM_LOG_LEVEL=$LOG_LEVEL_WARN ;;
    ERROR) KGSM_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
    SUCCESS) KGSM_LOG_LEVEL=$LOG_LEVEL_SUCCESS ;;
    *)
      log_warning "Invalid log level: $level_name, keeping current level"
      return 1
      ;;
  esac

  return 0
}

export -f log_set_level

# Get current log level name
function log_get_level() {
  case $KGSM_LOG_LEVEL in
    $LOG_LEVEL_DEBUG) echo "$LOG_LEVEL_NAME_DEBUG" ;;
    $LOG_LEVEL_INFO)  echo "$LOG_LEVEL_NAME_INFO" ;;
    $LOG_LEVEL_WARN)  echo "$LOG_LEVEL_NAME_WARN" ;;
    $LOG_LEVEL_ERROR) echo "$LOG_LEVEL_NAME_ERROR" ;;
    $LOG_LEVEL_SUCCESS) echo "$LOG_LEVEL_NAME_SUCCESS" ;;
    *) echo "UNKNOWN" ;;
  esac
}

export -f log_get_level

# Flush log buffer (noop since we flush on every write)
function log_flush() {
  # Logs are flushed immediately, but this function exists
  # for API compatibility if buffering is added later
  return 0
}

export -f log_flush

# =============================================================================
# INITIALIZATION
# =============================================================================

declare -g TEST_LOGGING_LOADED=1
export TEST_LOGGING_LOADED
