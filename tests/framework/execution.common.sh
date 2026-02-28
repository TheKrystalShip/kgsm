#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - Shared Execution Helpers Module
# ==============================================================================
# Version: 1.0
# Description: Provides common helper functions shared by both sequential and
#              parallel test executors, including environment management,
#              output capture, result parsing, and serialization.
# Dependencies: loader.sh, config.sh, logging.sh
# ==============================================================================

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

# Load guard to prevent multiple sourcing
if [[ -n "${TEST_EXECUTION_COMMON_LOADED:-}" ]]; then
  return 0
fi

# ==============================================================================
# ENVIRONMENT MANAGEMENT
# ==============================================================================

# ------------------------------------------------------------------------------
# Setup test environment for sandbox execution
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - sandbox_path: Absolute path to sandbox directory
#   $2 - test_log: Absolute path to test log file
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Exit code: EC_FAILURE (1) on error
# ------------------------------------------------------------------------------
function __setup_test_environment() {
  local sandbox_path="$1"
  local test_log="$2"

  # Save original KGSM_ROOT for restoration
  local original_kgsm_root="${KGSM_ROOT:-}"

  # Set sandbox context environment variables
  declare -g KGSM_ROOT="$sandbox_path"
  export KGSM_ROOT
  declare -g KGSM_TEST_MODE="true"
  export KGSM_TEST_MODE
  declare -g KGSM_TEST_LOG="$test_log"
  export KGSM_TEST_LOG
  declare -g KGSM_TEST_SANDBOX="$sandbox_path"
  export KGSM_TEST_SANDBOX
  declare -g KGSM_LOG_CONSOLE_ENABLED="false"
  export KGSM_LOG_CONSOLE_ENABLED
  declare -g TEST_SANDBOX_INSTANCES_INSTALL_DIR="${sandbox_path}/test_instances"
  export TEST_SANDBOX_INSTANCES_INSTALL_DIR

  # CRITICAL: Unset all module load flags to force fresh initialization in sandbox
  # The test framework loaded KGSM modules with HOST KGSM_ROOT, but tests need
  # modules loaded with SANDBOX KGSM_ROOT. By unsetting these flags, we force
  # modules to reload when the test sources them.
  unset KGSM_BOOTSTRAP_LOADED
  unset KGSM_COMMON_LOADED
  unset KGSM_LOADER_LOADED
  unset KGSM_CONFIG_LOADED
  unset KGSM_PARSER_LOADED
  unset KGSM_VALIDATION_LOADED
  unset KGSM_LOGGING_LOADED
  unset KGSM_EVENTS_LOADED
  unset KGSM_OVERRIDES_LOADED

  # Load KGSM bootstrap in sandbox context
  # This gives tests access to KGSM modules, error codes, and functions
  if [[ -f "${original_kgsm_root}/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${original_kgsm_root}/core/bootstrap.sh" || {
      log_error "Failed to load KGSM bootstrap: ${original_kgsm_root}/core/bootstrap.sh"
      return $EC_FAILURE
    }
  else
    log_error "KGSM bootstrap not found: ${original_kgsm_root}/core/bootstrap.sh"
    return $EC_FAILURE
  fi

  # Debug: verify environment is set
  log_debug "Environment setup complete: KGSM_TEST_SANDBOX=$KGSM_TEST_SANDBOX KGSM_ROOT=$original_kgsm_root"

  return $EC_SUCCESS
}
export -f __setup_test_environment

# ------------------------------------------------------------------------------
# Restore test environment to host context
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - original_kgsm_root: Original KGSM_ROOT value from setup
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function __restore_test_environment() {
  local original_kgsm_root="$1"

  # Restore original KGSM_ROOT
  if [[ -n "$original_kgsm_root" ]]; then
    export KGSM_ROOT="$original_kgsm_root"
  else
    unset KGSM_ROOT
  fi

  # Unset sandbox context variables
  unset KGSM_TEST_MODE
  unset KGSM_TEST_LOG
  unset KGSM_TEST_SANDBOX
  unset KGSM_LOG_CONSOLE_ENABLED

  # Re-export module load flags so subsequent code can see them
  # (they were unset to force sandbox reload)
  export KGSM_BOOTSTRAP_LOADED
  export KGSM_COMMON_LOADED
  export KGSM_LOADER_LOADED
  export KGSM_CONFIG_LOADED

  return $EC_SUCCESS
}
export -f __restore_test_environment

# ==============================================================================
# TEST EXECUTION HELPERS
# ==============================================================================

# ------------------------------------------------------------------------------
# Wait for a process to complete or timeout
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - pid: Process ID to wait for
#   $2 - timeout: Max wait time in seconds
# Returns:
#   0 if process completed, 1 if timeout reached
# ------------------------------------------------------------------------------
function wait_with_timeout() {
  local pid=$1
  local timeout=$2
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
      return 1
    fi
    sleep 1
    ((elapsed++))
  done
  return 0
}
export -f wait_with_timeout

# ------------------------------------------------------------------------------
# Execute test file with timeout and capture output
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - test_file: Absolute path to test file
#   $2 - timeout_seconds: Max execution time (default: TEST_DEFAULT_TIMEOUT)
# Returns:
#   Exit code: Test's exit code (or EC_TIMEOUT if timeout)
#   Stdout: Captured output (stderr + stdout combined)
# ------------------------------------------------------------------------------
function __capture_test_output() {
  local test_file="$1"
  local timeout_seconds="${2:-${TEST_DEFAULT_TIMEOUT}}"

  local output_file="/tmp/kgsm-test-output-$$.txt"
  local exit_code

  (
    # Source the test file — only defines functions (no main "$@" invocation)
    source "$test_file"

    # Run setup_test if defined
    if declare -f setup_test >/dev/null 2>&1; then
      setup_test
    fi

    if [[ -n "${KGSM_TEST_FUNCTION_FILTER:-}" ]]; then
      # Run only the specified function
      "${KGSM_TEST_FUNCTION_FILTER}"
    else
      # Auto-discover and run all test_* functions in file order
      local -a _test_functions
      mapfile -t _test_functions < <(grep -oP '^function \Ktest_\w+' "$test_file")
      for _fn in "${_test_functions[@]}"; do
        if declare -f "$_fn" >/dev/null 2>&1; then
          "$_fn"
        fi
      done
    fi

    # Framework calls print_assert_summary — capture its exit code
    local _test_exit=0
    if declare -f print_assert_summary >/dev/null 2>&1; then
      print_assert_summary "${TEST_NAME:-}" || _test_exit=$?
    fi

    # Run cleanup_test if defined (must not affect test result)
    if declare -f cleanup_test >/dev/null 2>&1; then
      cleanup_test
    fi

    exit $_test_exit
  ) >"$output_file" 2>&1 &

  local test_pid=$!

  # Wait for completion or timeout
  if ! wait_with_timeout "$test_pid" "$timeout_seconds"; then
    # Timeout - kill the test process
    kill -9 "$test_pid" 2>/dev/null
    wait "$test_pid" 2>/dev/null
    echo "TEST TIMEOUT: Test exceeded ${timeout_seconds}s limit" >> "$output_file"
    exit_code=$EC_TIMEOUT
  else
    wait "$test_pid"
    exit_code=$?
  fi

  local output
  if [[ -f "$output_file" ]]; then
    output=$(tr -d '\0' < "$output_file")
    rm -f "$output_file"
  else
    output="No output captured (output file missing)"
  fi

  echo "$output"
  return $exit_code
}
export -f __capture_test_output

# ------------------------------------------------------------------------------
# Execute test file inline (no subshell) for interactive debugging
# ------------------------------------------------------------------------------
# This function runs the same test lifecycle as __capture_test_output but
# without wrapping it in a subshell or background process. This allows
# debuggers like bashdb to step through the test code line by line.
#
# Arguments:
#   $1 - test_file: Absolute path to test file
# Returns:
#   Exit code: 0 if all assertions passed, 1 otherwise
# ------------------------------------------------------------------------------
function __execute_test_inline() {
  local test_file="$1"

  # Source the test file — defines functions
  # shellcheck disable=SC1090
  source "$test_file"

  # Run setup_test if defined
  if declare -f setup_test >/dev/null 2>&1; then
    setup_test
  fi

  # Run target function(s)
  if [[ -n "${KGSM_TEST_FUNCTION_FILTER:-}" ]]; then
    if declare -f "$KGSM_TEST_FUNCTION_FILTER" >/dev/null 2>&1; then
      "$KGSM_TEST_FUNCTION_FILTER"
    else
      echo "ERROR: Function not found: $KGSM_TEST_FUNCTION_FILTER" >&2
      echo "Available test functions in $(basename "$test_file"):" >&2
      grep -oP '^function \Ktest_\w+' "$test_file" >&2
      return 1
    fi
  else
    local -a _test_functions
    mapfile -t _test_functions < <(grep -oP '^function \Ktest_\w+' "$test_file")
    for _fn in "${_test_functions[@]}"; do
      if declare -f "$_fn" >/dev/null 2>&1; then
        "$_fn"
      fi
    done
  fi

  # Print assertion summary
  local _test_exit=0
  if declare -f print_assert_summary >/dev/null 2>&1; then
    print_assert_summary "${TEST_NAME:-}" || _test_exit=$?
  fi

  # Run cleanup_test if defined (must not affect test result)
  if declare -f cleanup_test >/dev/null 2>&1; then
    cleanup_test
  fi

  return $_test_exit
}
export -f __execute_test_inline

# ------------------------------------------------------------------------------
# Parse assertion statistics from test log
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - test_log: Absolute path to test log file
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Stdout: Three integers separated by spaces: "passed failed total"
# ------------------------------------------------------------------------------
function __parse_assertion_stats() {
  local test_log="$1"

  # Check if log file exists
  if [[ ! -f "$test_log" ]]; then
    echo "0 0 0 0"
    return $EC_SUCCESS
  fi

  # Primary method: Look for KGSM_ASSERT_STATS marker
  local stats_line
  stats_line=$(grep "^KGSM_ASSERT_STATS:" "$test_log" 2>/dev/null | tail -1 || echo "")

  if [[ -n "$stats_line" ]]; then
    # Extract "passed/failed/total/skipped" from marker
    local stats_value
    stats_value=$(echo "$stats_line" | sed 's/^KGSM_ASSERT_STATS: *//' | tr -d '[:space:]')

    # Parse format: 133/0/133/2 (passed/failed/total/skipped)
    local passed failed total skipped
    IFS='/' read -r passed failed total skipped <<< "$stats_value"

    # If skipped is not present, default to 0 (backward compatibility)
    [[ -z "$skipped" ]] && skipped=0

    # Validate extracted values are numbers
    if [[ "$passed" =~ ^[0-9]+$ ]] && [[ "$failed" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$skipped" =~ ^[0-9]+$ ]]; then
      echo "$passed $failed $total $skipped"
      return $EC_SUCCESS
    fi
  fi

  # Fallback method: Count PASS: and FAIL: markers
  local passed failed total skipped
  # Look for PASS: anywhere in the line (not just at beginning) to handle bash tracing output
  passed=$(grep -c "PASS:" "$test_log" 2>/dev/null || echo "0")
  failed=$(grep -c "FAIL:" "$test_log" 2>/dev/null || echo "0")
  skipped=$(grep -c "^\[SKIP\]" "$test_log" 2>/dev/null || echo "0")

  # Ensure we have clean numeric values (strip whitespace)
  passed=$(echo "$passed" | tr -d '[:space:]')
  failed=$(echo "$failed" | tr -d '[:space:]')
  skipped=$(echo "$skipped" | tr -d '[:space:]')

  # Validate they are numbers
  [[ ! "$passed" =~ ^[0-9]+$ ]] && passed=0
  [[ ! "$failed" =~ ^[0-9]+$ ]] && failed=0
  [[ ! "$skipped" =~ ^[0-9]+$ ]] && skipped=0

  total=$((passed + failed))

  echo "$passed $failed $total $skipped"
  return $EC_SUCCESS
}
export -f __parse_assertion_stats

# ------------------------------------------------------------------------------
# Calculate test duration in milliseconds
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - start_timestamp: Unix timestamp in milliseconds from 'date +%s%3N'
#   $2 - end_timestamp: Unix timestamp in milliseconds from 'date +%s%3N'
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Stdout: Duration in milliseconds (integer)
# ------------------------------------------------------------------------------
function __calculate_duration() {
  local start_time="$1"
  local end_time="$2"

  local duration=$((end_time - start_time))
  echo "$duration"
}
export -f __calculate_duration

# ==============================================================================
# RESULT SERIALIZATION (for parallel IPC)
# ==============================================================================

# ------------------------------------------------------------------------------
# Serialize result array to temp file for inter-process communication
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - result_array_name: Name of associative array (as string, not nameref)
#   $2 - result_file: Absolute path to result file
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
# File format:
#   key=value (one per line)
#   Newlines in values escaped as \n
# ------------------------------------------------------------------------------
function __write_result_to_file() {
  local result_array_name="$1"
  local result_file="$2"

  # Validate inputs
  if [[ -z "$result_array_name" ]]; then
    log_error "__write_result_to_file: result_array_name is required"
    return $EC_FAILURE
  fi

  if [[ -z "$result_file" ]]; then
    log_error "__write_result_to_file: result_file is required"
    return $EC_FAILURE
  fi

  # Ensure result directory exists
  local result_dir
  result_dir=$(dirname "$result_file")
  if [[ ! -d "$result_dir" ]]; then
    mkdir -p "$result_dir" || {
      log_error "Failed to create result directory: $result_dir"
      return $EC_FAILURE
    }
  fi

  # Get nameref to array (indirect reference)
  local -n result_array_ref="$result_array_name"

  # Write key=value pairs to file
  {
    for key in "${!result_array_ref[@]}"; do
      # Escape special characters in value (preserve newlines, etc.)
      local value="${result_array_ref[$key]}"
      # Simple escaping: replace newlines with literal \n
      value="${value//$'\n'/\\n}"
      echo "${key}=${value}"
    done
  } > "$result_file" || {
    log_error "Failed to write result file: $result_file"
    return $EC_FAILURE
  }

  log_debug "Wrote result to file: $result_file"
  return $EC_SUCCESS
}
export -f __write_result_to_file

# ------------------------------------------------------------------------------
# Deserialize result file into associative array
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - result_file: Absolute path to result file
#   $2 - result_array_name: Name of associative array to populate
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
# ------------------------------------------------------------------------------
function __read_result_from_file() {
  local result_file="$1"
  local result_array_name="$2"

  # Validate inputs
  if [[ -z "$result_file" ]]; then
    log_error "__read_result_from_file: result_file is required"
    return $EC_FAILURE
  fi

  if [[ ! -f "$result_file" ]]; then
    log_error "__read_result_from_file: result file not found: $result_file"
    return $EC_FAILURE
  fi

  if [[ -z "$result_array_name" ]]; then
    log_error "__read_result_from_file: result_array_name is required"
    return $EC_FAILURE
  fi

  # Get nameref to array
  local -n result_array_ref="$result_array_name"

  # Read key=value pairs from file
  local line key value
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Split on first = only (value may contain =)
    key="${line%%=*}"
    value="${line#*=}"

    # Skip if no key found
    [[ -z "$key" ]] && continue

    # Unescape newlines
    value="${value//\\n/$'\n'}"

    # Populate array
    result_array_ref["$key"]="$value"
  done < "$result_file"

  log_debug "Read result from file: $result_file (${#result_array_ref[@]} fields)"
  return $EC_SUCCESS
}
export -f __read_result_from_file

# ==============================================================================
# Core Execution Function (Used by both Sequential and Parallel executors)
# ==============================================================================

# ------------------------------------------------------------------------------
# Execute a single test in a sandbox environment
# ------------------------------------------------------------------------------
# This is the core test execution function used by both sequential and parallel
# executors. It sets up the environment, runs the test, captures output, and
# populates the result array.
#
# Arguments:
#   $1 - test_file: Absolute path to test file
#   $2 - test_type: "unit", "integration", or "e2e"
#   $3 - sandbox_path: Absolute path to sandbox directory
#   $4 - test_log: Absolute path to test log file
#   $5 - result_array: Name of associative array to populate with results
# Returns:
#   Exit code: EC_SUCCESS (always, test failure reflected in result data)
#   Side effect: Populates result_array with test results
# Result array fields:
#   test_name, test_type, exit_code, assertions_passed, assertions_failed,
#   assertions_total, duration_seconds, test_log_path, sandbox_path, timestamp
# ------------------------------------------------------------------------------
function execute_test_in_sandbox() {
  local test_file="$1"
  local test_type="$2"
  local sandbox_path="$3"
  local test_log="$4"
  local -n result_array="$5"

  # Extract test name from file path
  local test_name
  test_name=$(basename "$test_file" .sh)

  # Initialize result array
  result_array[test_name]="$test_name"
  result_array[test_type]="$test_type"
  result_array[exit_code]="$EC_FAILURE"
  result_array[assertions_passed]="0"
  result_array[assertions_failed]="0"
  result_array[assertions_total]="0"
  result_array[functions_skipped]="0"
  result_array[duration_seconds]="0"
  result_array[test_log_path]="$test_log"
  result_array[sandbox_path]="$sandbox_path"
  result_array[timestamp]="$(date +%Y-%m-%dT%H:%M:%S%z)"

  # Validate sandbox exists
  if ! validate_sandbox "$sandbox_path" >/dev/null 2>&1; then
    log_error "Sandbox validation failed: $sandbox_path"
    result_array[exit_code]="$EC_ERROR"
    return $EC_SUCCESS
  fi

  # Save original KGSM_ROOT before setup modifies it
  local original_kgsm_root="${KGSM_ROOT:-}"

  # Setup environment (exports KGSM_TEST_SANDBOX and other variables)
  __setup_test_environment "$sandbox_path" "$test_log"

  # Ensure environment restoration via trap
  trap '__restore_test_environment' EXIT INT TERM

  # Record start time (in milliseconds for accurate tracking)
  local start_time end_time duration
  start_time=$(date +%s%3N)

  # Execute test and capture output using the common function
  local test_exit_code captured_output timeout_seconds
  timeout_seconds="${TEST_DEFAULT_TIMEOUT:-300}"

  if captured_output=$(__capture_test_output "$test_file" "$timeout_seconds"); then
    test_exit_code=$EC_SUCCESS
  else
    test_exit_code=$?
  fi

  # Write captured output to log
  if [[ -n "$captured_output" ]]; then
    echo "$captured_output" >> "$test_log"
  fi

  # Record end time (in milliseconds)
  end_time=$(date +%s%3N)

  # Parse assertion statistics from log
  local stats
  stats=$(__parse_assertion_stats "$test_log")
  read -r passed failed total skipped <<< "$stats"

  # Calculate duration (in milliseconds)
  duration=$(__calculate_duration "$start_time" "$end_time")

  # Populate result array
  result_array[exit_code]="$test_exit_code"
  result_array[assertions_passed]="$passed"
  result_array[assertions_failed]="$failed"
  result_array[assertions_total]="$total"
  result_array[functions_skipped]="$skipped"
  result_array[duration_seconds]="$duration"

  # Restore environment (also happens via trap)
  __restore_test_environment "$original_kgsm_root"

  # Remove trap
  trap - EXIT INT TERM

  return $EC_SUCCESS
}
export -f execute_test_in_sandbox

# ==============================================================================
# Module Initialization
# ==============================================================================

# Mark module as loaded
declare -g TEST_EXECUTION_COMMON_LOADED=1
export TEST_EXECUTION_COMMON_LOADED
