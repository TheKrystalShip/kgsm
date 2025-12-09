#!/usr/bin/env bash

# KGSM Test Framework - Common Test Utilities
#
# Author: The Krystal Ship Team
# Version: 3.0
#
# Common functions and utilities shared across all test files

# =============================================================================
# CONSTANTS
# =============================================================================

# Exit codes (only define if not already defined)
if [[ -z "${EC_SUCCESS:-}" ]]; then
  readonly EC_SUCCESS=0
  readonly EC_FAILURE=1
  readonly EC_SKIP=77
  readonly EC_ERROR=2
fi

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Test games for E2E testing (small download size)
readonly TEST_GAMES=("factorio" "necesse" "vrising")

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

# Initialize test environment
function setup_test_environment() {
  # Ensure required environment variables are set
  if [[ -z "${KGSM_ROOT:-}" ]]; then
    echo "ERROR: KGSM_ROOT not set" >&2
    exit $EC_ERROR
  fi

  if [[ -z "${KGSM_TEST_SANDBOX:-}" ]]; then
    echo "ERROR: KGSM_TEST_SANDBOX not set" >&2
    exit $EC_ERROR
  fi

  # Source assertion framework
  local assert_lib="$(dirname "${BASH_SOURCE[0]}")/assert.sh"
  if [[ -f "$assert_lib" ]]; then
    # shellcheck disable=SC1090
    source "$assert_lib"
  else
    echo "ERROR: Could not find assertion library: $assert_lib" >&2
    exit $EC_ERROR
  fi

  # Source fixtures framework
  local fixtures_lib="$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"
  if [[ -f "$fixtures_lib" ]]; then
    # shellcheck disable=SC1090
    source "$fixtures_lib"
  else
    echo "ERROR: Could not find fixtures library: $fixtures_lib" >&2
    exit $EC_ERROR
  fi

  # Set up paths
  export KGSM_CONFIG_FILE="$KGSM_ROOT/config.ini"
  export KGSM_INSTANCES_DIR="$KGSM_ROOT/instances"
  export KGSM_LOGS_DIR="$KGSM_ROOT/logs"
  export KGSM_VERSION_FILE="$KGSM_ROOT/.kgsm.version"

  # Ensure test directories exist
  mkdir -p "$KGSM_INSTANCES_DIR"
  mkdir -p "$KGSM_LOGS_DIR"

  # Ensure the version file exists
  if [[ ! -f "$KGSM_VERSION_FILE" ]]; then
    echo "1.0.0" >"$KGSM_VERSION_FILE"
  fi

  log_test "Test environment initialized"
  log_test "KGSM_ROOT: $KGSM_ROOT"
  log_test "KGSM_TEST_SANDBOX: $KGSM_TEST_SANDBOX"
}

# =============================================================================
# LOGGING UTILITIES
# =============================================================================

# Log test message
function log_test() {
  local message="$1"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
    echo "[$timestamp] [TEST] $message" >>"$KGSM_TEST_LOG"
  fi

  if [[ "${KGSM_DEBUG:-false}" == "true" ]]; then
    printf "${PURPLE}[DEBUG]${NC} %s\n" "$message" >&2
  fi
}

# Log test step
function log_step() {
  local step_name="$1"
  printf "${CYAN}[STEP]${NC} %s\n" "$step_name" >&2
  log_test "STEP: $step_name"
}

# Log test info
function log_info() {
  local message="$1"
  printf "${BLUE}[INFO]${NC} %s\n" "$message" >&2
  log_test "INFO: $message"
}

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Wait for condition with timeout
function wait_for_condition() {
  local condition="$1"
  local timeout="${2:-30}"
  local interval="${3:-1}"
  local description="${4:-condition}"

  log_test "Waiting for $description (timeout: ${timeout}s)"

  local elapsed=0
  while ((elapsed < timeout)); do
    if eval "$condition"; then
      log_test "$description met after ${elapsed}s"
      return $EC_SUCCESS
    fi

    sleep "$interval"
    ((elapsed += interval))
  done

  log_test "$description not met within ${timeout}s"
  return $EC_FAILURE
}

# Generate random test ID
function generate_test_id() {
  local prefix="${1:-test}"
  echo "${prefix}_$(date +%s)_$$"
}

# Clean up test resources
function cleanup_test_resources() {
  local test_id="${1:-}"

  if [[ -n "$test_id" ]]; then
    log_test "Cleaning up resources for test: $test_id"

    # Clean up any instances created during test
    if [[ -d "$KGSM_INSTANCES_DIR" ]]; then
      find "$KGSM_INSTANCES_DIR" -name "*${test_id}*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi

    # Clean up any temporary files
    find /tmp -name "*kgsm*${test_id}*" -type f -delete 2>/dev/null || true
  fi
}

# =============================================================================
# KGSM-SPECIFIC UTILITIES
# =============================================================================

# Run KGSM command with error handling
function run_kgsm() {
  local args="$1"
  local expected_exit_code="${2:-0}"

  log_test "Running KGSM command: kgsm.sh $args"

  local output
  local exit_code

  if output=$("$KGSM_ROOT/kgsm.sh" $args 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  log_test "KGSM command exited with code: $exit_code"

  if [[ -n "$output" ]]; then
    log_test "KGSM output: $output"
  fi

  if [[ $exit_code -eq $expected_exit_code ]]; then
    return $EC_SUCCESS
  else
    return $EC_FAILURE
  fi
}

# Create test instance
function create_test_instance() {
  local blueprint="$1"
  local test_id="$2"
  local install_dir="${3:-$KGSM_INSTANCES_DIR}"

  log_step "Creating test instance: $test_id using blueprint $blueprint"

  local instance_name
  if instance_name=$("$KGSM_ROOT/commands/instances.sh" create "$blueprint" --install-dir "$install_dir" --name "$test_id"); then
    log_test "Instance created successfully: $instance_name"

    # Create the complete directory structure for the instance
    # This follows the same pattern as the main kgsm.sh script
    log_test "Creating directory structure for instance: $instance_name"
    if "$KGSM_ROOT/commands/directories.sh" create "$instance_name" >/dev/null 2>&1; then
      log_test "Directory structure created successfully for: $instance_name"
    else
      log_test "Warning: Failed to create directory structure for: $instance_name (may be expected in test environment)"
    fi

    echo "$instance_name"
    return $EC_SUCCESS
  else
    log_test "Failed to create instance"
    return $EC_FAILURE
  fi
}

# Remove test instance
function remove_test_instance() {
  local instance_name="$1"

  log_step "Removing test instance: $instance_name"

  # First remove the directory structure (if it exists)
  log_test "Removing directory structure for instance: $instance_name"
  "$KGSM_ROOT/commands/directories.sh" remove "$instance_name" >/dev/null 2>&1 || true

  # Then remove the instance configuration
  if "$KGSM_ROOT/commands/instances.sh" remove "$instance_name" >/dev/null 2>&1; then
    log_test "Instance removed successfully: $instance_name"
    return $EC_SUCCESS
  else
    log_test "Failed to remove instance: $instance_name"
    return $EC_FAILURE
  fi
}

# Check if instance exists
function instance_exists() {
  local instance_name="$1"

  if "$KGSM_ROOT/commands/instances.sh" find "$instance_name" >/dev/null 2>&1; then
    return $EC_SUCCESS
  else
    return $EC_FAILURE
  fi
}

# Get instance status
function get_instance_status() {
  local instance_name="$1"

  "$KGSM_ROOT/commands/instances.sh" status "$instance_name" 2>/dev/null || echo "unknown"
}

# =============================================================================
# FILE AND DIRECTORY UTILITIES
# =============================================================================

# Create temporary test directory
function create_temp_dir() {
  local prefix="${1:-kgsm-test}"
  local temp_dir

  temp_dir=$(mktemp -d -t "${prefix}-XXXXXX")
  log_test "Created temporary directory: $temp_dir"
  echo "$temp_dir"
}

# Create temporary test file
function create_temp_file() {
  local prefix="${1:-kgsm-test}"
  local temp_file

  temp_file=$(mktemp -t "${prefix}-XXXXXX")
  log_test "Created temporary file: $temp_file"
  echo "$temp_file"
}

# Wait for file to exist
function wait_for_file() {
  local file_path="$1"
  local timeout="${2:-30}"

  wait_for_condition "[[ -f '$file_path' ]]" "$timeout" 1 "file $file_path to exist"
}

# Wait for directory to exist
function wait_for_dir() {
  local dir_path="$1"
  local timeout="${2:-30}"

  wait_for_condition "[[ -d '$dir_path' ]]" "$timeout" 1 "directory $dir_path to exist"
}

# =============================================================================
# NETWORK UTILITIES
# =============================================================================

# Check if port is open
function is_port_open() {
  local host="${1:-localhost}"
  local port="$2"
  local timeout="${3:-5}"

  if command -v nc >/dev/null 2>&1; then
    nc -z -w "$timeout" "$host" "$port" >/dev/null 2>&1
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/$host/$port" >/dev/null 2>&1
  else
    # Fallback method
    exec 6<>/dev/tcp/"$host"/"$port" 2>/dev/null && exec 6<&- && exec 6>&-
  fi
}

# Wait for port to be open
function wait_for_port() {
  local host="${1:-localhost}"
  local port="$2"
  local timeout="${3:-60}"

  wait_for_condition "is_port_open '$host' '$port'" "$timeout" 2 "port $port to be open on $host"
}

# =============================================================================
# PROCESS UTILITIES
# =============================================================================

# Check if process is running by PID
function is_process_running() {
  local pid="$1"

  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    return $EC_SUCCESS
  else
    return $EC_FAILURE
  fi
}

# Wait for process to start
function wait_for_process() {
  local pid_file="$1"
  local timeout="${2:-30}"

  wait_for_condition "[[ -f '$pid_file' ]] && is_process_running \"\$(cat '$pid_file')\"" "$timeout" 1 "process to start"
}

# Wait for process to stop
function wait_for_process_stop() {
  local pid_file="$1"
  local timeout="${2:-30}"

  wait_for_condition "[[ ! -f '$pid_file' ]] || ! is_process_running \"\$(cat '$pid_file' 2>/dev/null)\"" "$timeout" 1 "process to stop"
}

# =============================================================================
# STEAM/GAME UTILITIES
# =============================================================================

# Check if SteamCMD is available
function is_steamcmd_available() {
  command -v steamcmd >/dev/null 2>&1
}

# Skip test if SteamCMD is not available
function require_steamcmd() {
  if ! is_steamcmd_available; then
    skip_test "SteamCMD not available"
  fi
}

# Check if Docker is available
function is_docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

# Skip test if Docker is not available
function require_docker() {
  if ! is_docker_available; then
    skip_test "Docker not available"
  fi
}

# =============================================================================
# TEST RESULT UTILITIES
# =============================================================================

# Mark test as passed
function pass_test() {
  local message="${1:-Test passed}"
  log_test "PASS: $message"
  exit $EC_SUCCESS
}

# Mark test as failed
function fail_test() {
  local message="${1:-Test failed}"
  log_test "FAIL: $message"
  printf "${RED}[FAIL]${NC} %s\n" "$message" >&2
  exit $EC_FAILURE
}

# Mark test as skipped
function skip_test() {
  local reason="${1:-Test skipped}"
  log_test "SKIP: $reason"
  printf "${YELLOW}[SKIP]${NC} %s\n" "$reason" >&2
  exit $EC_SKIP
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-setup when sourced (if not in main script)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # Only setup if we're in a test environment
  if [[ "${KGSM_TEST_MODE:-false}" == "true" ]]; then
    setup_test_environment
  fi
fi
