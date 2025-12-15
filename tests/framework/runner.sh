#!/usr/bin/env bash

# KGSM Test Framework - Main Test Runner
#
# Author: The Krystal Ship Team
# Version: 3.0
#
# This is a comprehensive testing framework for KGSM that provides:
# - Sandboxed environments for each test suite
# - Real code testing (no mocking)
# - Detailed logging and reporting
# - Colored console output
# - Debug capabilities
# - Test skip functionality
# - Modular design following SOLID principles

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export KGSM_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"

# Source centralized logging module for runner
if [[ -f "$SCRIPT_DIR/logging.sh" ]]; then
  source "$SCRIPT_DIR/logging.sh"
fi

# Test configuration file
readonly TEST_CONFIG="${TESTS_ROOT}/config/test.conf"

# Exit codes
readonly EC_SUCCESS=0
readonly EC_FAILURE=1
readonly EC_SKIP=77
readonly EC_ERROR=2

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Test types
readonly TEST_TYPE_UNIT="unit"
readonly TEST_TYPE_INTEGRATION="integration"
readonly TEST_TYPE_E2E="e2e"

# Default test games (small download size)
readonly DEFAULT_TEST_GAMES=("factorio" "necesse" "vrising")

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

declare -g TEST_DEBUG=false
declare -g TEST_VERBOSE=false
declare -g TEST_QUIET=false
declare -g TEST_PARALLEL=false
declare -g TEST_SANDBOX_ROOT=""
declare -g TEST_LOG_DIR=""
declare -g TEST_RESULTS_FILE=""

# Test counters
declare -g TESTS_TOTAL=0
declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g TESTS_SKIPPED=0
declare -g TESTS_ERRORS=0

# Test filters
declare -ga TEST_TYPES=()
declare -ga TEST_PATTERNS=()
declare -ga TEST_EXCLUDE=()

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Print colored output
function print_color() {
  local color="$1"
  shift
  if [[ "$TEST_QUIET" != "true" ]]; then
    printf "${color}%s${NC}\n" "$*"
  fi
}

function print_info() { print_color "$BLUE" "[INFO] $*"; }
function print_success() { print_color "$GREEN" "[SUCCESS] $*"; }
function print_warning() { print_color "$YELLOW" "[WARNING] $*"; }
function print_error() { print_color "$RED" "[ERROR] $*"; }
function print_debug() {
  if [[ "$TEST_DEBUG" == "true" ]]; then
    print_color "$CYAN" "[DEBUG] $*"
  fi
}

# Logging function (runner-specific, writes to runner.log)
function log_message() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date -Iseconds)

  # Write to runner log in standardized format
  if [[ -n "$TEST_LOG_DIR" ]]; then
    echo "[$timestamp] [$level] [runner.sh] $message" >>"$TEST_LOG_DIR/runner.log"
  fi

  # Console output
  case "$level" in
  "INFO") print_info "$message" ;;
  "SUCCESS") print_success "$message" ;;
  "WARNING") print_warning "$message" ;;
  "ERROR") print_error "$message" ;;
  "DEBUG") print_debug "$message" ;;
  esac
}

# Strip ANSI escape codes from text
function strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================

function load_test_config() {
  if [[ -f "$TEST_CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$TEST_CONFIG"
    log_message "DEBUG" "Loaded test configuration from $TEST_CONFIG"
  else
    log_message "WARNING" "Test configuration file not found: $TEST_CONFIG"
    log_message "INFO" "Using default configuration"
  fi
}

# =============================================================================
# SANDBOX ENVIRONMENT MANAGEMENT
# =============================================================================

function create_sandbox() {
  local sandbox_id="$1"
  local sandbox_path="$TEST_SANDBOX_ROOT/$sandbox_id"

  log_message "DEBUG" "Creating sandbox: $sandbox_path"

  # Remove existing sandbox if it exists
  if [[ -d "$sandbox_path" ]]; then
    rm -rf "$sandbox_path"
  fi

  # Create sandbox directory
  mkdir -p "$sandbox_path"

  # Copy KGSM to sandbox
  cp -r "$KGSM_ROOT"/* "$sandbox_path/"

  # Create test-specific config
  create_test_config "$sandbox_path"

  # Set permissions
  chmod +x "$sandbox_path/kgsm.sh"
  find "$sandbox_path/commands" -name "*.sh" -exec chmod +x {} \;

  echo "$sandbox_path"
}

function create_test_config() {
  local sandbox_path="$1"
  local config_file="$sandbox_path/config.ini"

  # Copy default config
  cp "$sandbox_path/config.default.ini" "$config_file"

  # Modify for test environment
  cat >>"$config_file" <<EOF

# =============================================================================
# TEST ENVIRONMENT OVERRIDES
# =============================================================================

# Disable features that require system integration for testing
enable_systemd=false
enable_firewall_management=false
enable_port_forwarding=false
enable_event_broadcasting=false
enable_command_shortcuts=false

# Set test-specific paths
default_install_directory=$sandbox_path/instances
log_max_size_kb=1024

# Enable logging for tests
enable_logging=true

# Test-specific settings
instance_suffix_length=3
enable_backup_compression=false
instance_save_command_timeout_seconds=2
instance_stop_command_timeout_seconds=5
instance_auto_update_before_start=false

EOF
}

function cleanup_sandbox() {
  local sandbox_path="$1"

  if [[ -d "$sandbox_path" ]]; then
    log_message "DEBUG" "Cleaning up sandbox: $sandbox_path"
    rm -rf "$sandbox_path"
  fi
}

# =============================================================================
# TEST DISCOVERY AND EXECUTION
# =============================================================================

function discover_tests() {
  local test_type="$1"
  local test_dir="$TESTS_ROOT/$test_type"

  if [[ ! -d "$test_dir" ]]; then
    log_message "WARNING" "Test directory not found: $test_dir"
    return 0
  fi

  find "$test_dir" -name "test_*.sh" -type f | sort
}

function should_run_test() {
  local test_file="$1"
  local test_name="$(basename "$test_file" .sh)"

  # Check if test should be skipped based on configuration
  local skip_var="SKIP_${test_name^^}"
  if [[ "${!skip_var:-false}" == "true" ]]; then
    return 1
  fi

  # Check test patterns
  if [[ ${#TEST_PATTERNS[@]} -gt 0 ]]; then
    local match=false
    for pattern in "${TEST_PATTERNS[@]}"; do
      if [[ "$test_name" =~ $pattern ]]; then
        match=true
        break
      fi
    done
    if [[ "$match" != "true" ]]; then
      return 1
    fi
  fi

  # Check exclude patterns
  for exclude in "${TEST_EXCLUDE[@]}"; do
    if [[ "$test_name" =~ $exclude ]]; then
      return 1
    fi
  done

  return 0
}

function execute_test() {
  local test_file="$1"
  local test_type="$2"
  local test_name="$(basename "$test_file" .sh)"
  local sandbox_id="${test_type}_${test_name}_$$"
  local sandbox_path=""

  log_message "INFO" "Running $test_type test: $test_name"

  # Create test log file
  local test_log="$TEST_LOG_DIR/${test_name}.log"
  echo "=== Test: $test_name ===" >"$test_log"
  echo "Type: $test_type" >>"$test_log"
  echo "Started: $(date)" >>"$test_log"
  echo "" >>"$test_log"

  # Create sandbox environment first
  sandbox_path="$(create_sandbox "$sandbox_id")"

  # Set all test environment variables before running test
  local original_kgsm_root="$KGSM_ROOT"
  export KGSM_ROOT="$sandbox_path"
  export KGSM_TEST_MODE="true"
  export KGSM_TEST_LOG="$test_log"
  export KGSM_TEST_SANDBOX="$sandbox_path"
  export KGSM_LOG_CONSOLE_ENABLED="false"  # Disable console output during test execution

  # Set log level from environment or default to INFO
  export KGSM_TEST_LOG_LEVEL="${KGSM_TEST_LOG_LEVEL:-INFO}"

  if [[ "$TEST_DEBUG" == "true" ]]; then
    export KGSM_DEBUG="true"
    export KGSM_TEST_LOG_LEVEL="DEBUG"
    set -x
  fi

  local start_time="$(date +%s)"
  local exit_code=0

  # Execute the test and capture output
  # Instead of redirecting everything, let the logging module handle file writes
  # Capture stderr/stdout only for unexpected output (errors, debug info from code under test)
  local captured_output
  if captured_output=$(bash "$test_file" 2>&1); then
    exit_code=$EC_SUCCESS
  else
    exit_code=$?
  fi

  # If there was any captured output (from code under test, not framework), log it
  if [[ -n "$captured_output" ]]; then
    # Strip ANSI codes and append to test log
    echo "$captured_output" | strip_ansi >> "$test_log"
  fi

  local end_time="$(date +%s)"
  local duration=$((end_time - start_time))

  # Log test completion
  {
    echo ""
    echo "Completed: $(date)"
    echo "Duration: ${duration}s"
    echo "Exit code: $exit_code"
  } >> "$test_log"

  # Parse assertion stats from test log
  local assert_passed=0
  local assert_failed=0
  local assert_total=0
  if [[ -f "$test_log" ]]; then
    local stats_line
    stats_line=$(grep "^KGSM_ASSERT_STATS:" "$test_log" 2>/dev/null | tail -1 || true)
    if [[ -n "$stats_line" ]]; then
      # Extract passed/failed/total from "KGSM_ASSERT_STATS: 133/0/133"
      local stats_value
      stats_value=$(echo "$stats_line" | sed 's/^KGSM_ASSERT_STATS: //')
      assert_passed=$(echo "$stats_value" | cut -d'/' -f1)
      assert_failed=$(echo "$stats_value" | cut -d'/' -f2)
      assert_total=$(echo "$stats_value" | cut -d'/' -f3)
    fi
  fi

  # Update counters and report result
  case $exit_code in
  $EC_SUCCESS)
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_message "SUCCESS" "(P:${assert_passed}/F:${assert_failed}/T:${assert_total}) ✓ $test_name (${duration}s)"
    ;;
  $EC_SKIP)
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    log_message "WARNING" "⊘ $test_name (skipped)"
    ;;
  *)
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_message "ERROR" "(P:${assert_passed}/F:${assert_failed}/T:${assert_total}) ✗ $test_name (${duration}s)"
    if [[ "$TEST_VERBOSE" == "true" ]]; then
      print_error "Last 10 lines of test log:"
      tail -10 "$test_log" | while IFS= read -r line; do
        print_error "  $line"
      done
    fi
    ;;
  esac

  # Record result
  echo "$test_name,$test_type,$exit_code,$duration,$(date -Iseconds),$assert_passed,$assert_failed,$assert_total" >>"$TEST_RESULTS_FILE"

  # Restore original KGSM_ROOT
  export KGSM_ROOT="$original_kgsm_root"

  # Cleanup
  if [[ "$TEST_DEBUG" != "true" ]]; then
    cleanup_sandbox "$sandbox_path"
    set +x 2>/dev/null || true
  else
    log_message "DEBUG" "Sandbox preserved for debugging: $sandbox_path"
  fi

  return $exit_code
}

function run_test_suite() {
  local test_type="$1"

  printf "\n"
  print_color "$CYAN" "=== Running $test_type tests ==="

  local tests
  mapfile -t tests < <(discover_tests "$test_type")

  if [[ ${#tests[@]} -eq 0 ]]; then
    log_message "WARNING" "No $test_type tests found"
    return 0
  fi

  for test_file in "${tests[@]}"; do
    if should_run_test "$test_file"; then
      TESTS_TOTAL=$((TESTS_TOTAL + 1))
      execute_test "$test_file" "$test_type"
    else
      log_message "INFO" "Skipping test: $(basename "$test_file" .sh)"
    fi
  done
}

# =============================================================================
# REPORTING
# =============================================================================

function generate_summary() {
  local total_runtime=$(($(date +%s) - ${START_TIME:-$(date +%s)}))

  printf "\n"
  print_color "$WHITE" "$(printf '=%.0s' {1..60})"
  print_color "$WHITE" "TEST SUMMARY"
  print_color "$WHITE" "$(printf '=%.0s' {1..60})"

  printf "%-20s %s\n" "Total tests:" "$TESTS_TOTAL"
  printf "${GREEN}%-20s %s${NC}\n" "Passed:" "$TESTS_PASSED"
  printf "${RED}%-20s %s${NC}\n" "Failed:" "$TESTS_FAILED"
  printf "${YELLOW}%-20s %s${NC}\n" "Skipped:" "$TESTS_SKIPPED"
  printf "%-20s %s\n" "Runtime:" "${total_runtime}s"

  if [[ -f "$TEST_RESULTS_FILE" ]]; then
    printf "%-20s %s\n" "Results file:" "$TEST_RESULTS_FILE"
  fi

  if [[ -d "$TEST_LOG_DIR" ]]; then
    printf "%-20s %s\n" "Logs directory:" "$TEST_LOG_DIR"
  fi

  print_color "$WHITE" "$(printf '=%.0s' {1..60})"

  # Determine exit code
  if [[ $TESTS_FAILED -gt 0 ]]; then
    return $EC_FAILURE
  else
    return $EC_SUCCESS
  fi
}

# =============================================================================
# LOG MANAGEMENT
# =============================================================================

function clean_old_logs() {
  local logs_dir="$TESTS_ROOT/logs"

  if [[ ! -d "$logs_dir" ]]; then
    print_info "No logs directory found"
    return 0
  fi

  print_info "Cleaning old test logs..."

  # Count current log directories (match new timestamp format YYYY-MM-DD_HH-MM-SS)
  local log_count=$(find "$logs_dir" -maxdepth 1 -type d -name "20*-*-*_*-*-*" | wc -l)

  if [[ $log_count -le 10 ]]; then
    print_info "Found $log_count log directories (keeping all, threshold is 10)"
    return 0
  fi

  # Remove all but the 10 most recent log directories
  find "$logs_dir" -maxdepth 1 -type d -name "20*-*-*_*-*-*" -printf '%T@ %p\n' |
    sort -n | head -n -10 | cut -d' ' -f2- |
    while IFS= read -r dir; do
      print_info "Removing old log directory: $(basename "$dir")"
      rm -rf "$dir"
    done

  local remaining=$(find "$logs_dir" -maxdepth 1 -type d -name "20*-*-*_*-*-*" | wc -l)
  print_success "Log cleanup complete. $remaining directories remaining."
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function show_usage() {
  cat <<EOF
KGSM Test Framework Runner

Usage: $(basename "$0") [OPTIONS] [TEST_TYPES...]

OPTIONS:
    -h, --help          Show this help message
    -d, --debug         Enable debug mode (preserves sandboxes)
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress non-essential output
    -p, --parallel      Run tests in parallel (where possible)
    --clean-logs        Remove old test logs (keeps last 10)

FILTERING:
    --pattern REGEX     Only run tests matching pattern
    --exclude REGEX     Exclude tests matching pattern

TEST TYPES:
    unit                Run unit tests
    integration         Run integration tests
    e2e                 Run end-to-end tests
    all                 Run all test types (default)

EXAMPLES:
    $(basename "$0")                    # Run all tests
    $(basename "$0") unit               # Run only unit tests
    $(basename "$0") --debug e2e        # Run e2e tests with debug
    $(basename "$0") --pattern "instance"  # Run tests matching "instance"
    $(basename "$0") --clean-logs       # Clean up old test logs

LOGS:
    Test logs are saved in tests/logs/ with timestamped directories.
    Use --clean-logs to remove old logs (keeps most recent 10).

EOF
}

function main() {
  export START_TIME="$(date +%s)"

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
      show_usage
      exit $EC_SUCCESS
      ;;
    -d | --debug)
      TEST_DEBUG=true
      ;;
    -v | --verbose)
      TEST_VERBOSE=true
      ;;
    -q | --quiet)
      TEST_QUIET=true
      ;;
    -p | --parallel)
      TEST_PARALLEL=true
      ;;
    --clean-logs)
      clean_old_logs
      exit $EC_SUCCESS
      ;;
    --pattern)
      shift
      TEST_PATTERNS+=("$1")
      ;;
    --exclude)
      shift
      TEST_EXCLUDE+=("$1")
      ;;
    unit | integration | e2e)
      TEST_TYPES+=("$1")
      ;;
    all)
      TEST_TYPES=("unit" "integration" "e2e")
      ;;
    *)
      print_error "Unknown option: $1"
      show_usage
      exit $EC_ERROR
      ;;
    esac
    shift
  done

  # Default to all tests if none specified
  if [[ ${#TEST_TYPES[@]} -eq 0 ]]; then
    TEST_TYPES=("unit" "integration" "e2e")
  fi

  # Initialize testing environment
  TEST_SANDBOX_ROOT="$(mktemp -d -t kgsm-test-sandbox-XXXXXX)"

  # Create timestamped log directory in project
  local timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  TEST_LOG_DIR="$TESTS_ROOT/logs/$timestamp"
  mkdir -p "$TEST_LOG_DIR"
  TEST_RESULTS_FILE="$TEST_LOG_DIR/results.csv"

  # Create results header
  echo "test_name,test_type,exit_code,duration_seconds,timestamp,assertions_passed,assertions_failed,assertions_total" >"$TEST_RESULTS_FILE"

  print_color "$BOLD$CYAN" "KGSM Test Framework Runner"
  print_color "$GRAY" "Sandbox: $TEST_SANDBOX_ROOT"
  print_color "$GREEN" "Logs: $TEST_LOG_DIR"
  print_color "$GRAY" "Logs will be preserved in the project directory for easy access"

  # Load configuration
  load_test_config

  # Set up signal handlers for cleanup
  trap 'cleanup_all' EXIT INT TERM

  # Run test suites
  for test_type in "${TEST_TYPES[@]}"; do
    run_test_suite "$test_type"
  done

  # Generate final summary
  generate_summary
}

function cleanup_all() {
  if [[ "$TEST_DEBUG" != "true" && -n "$TEST_SANDBOX_ROOT" ]]; then
    rm -rf "$TEST_SANDBOX_ROOT"
  fi
  # Note: TEST_LOG_DIR is kept in project directory for easy access
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
