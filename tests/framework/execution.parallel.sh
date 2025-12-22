#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - Parallel Test Executor
# ==============================================================================
# Version: 1.0
# Description: Executes tests concurrently using job pool management and
#              inter-process communication via result serialization.
#              Uses a configurable number of concurrent jobs (TEST_PARALLEL).
# Dependencies: execution.common.sh, sandbox.sh
# ==============================================================================

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

# Load guard to prevent multiple sourcing
if [[ -n "${TEST_EXECUTION_PARALLEL_LOADED:-}" ]]; then
  return 0
fi

# ==============================================================================
# Private Job Management Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Spawn a single test as a background job
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - test_file: Absolute path to test file
#   $2 - test_type: "unit", "integration", or "e2e"
#   $3 - results_dir: Directory for result files
#   $4 - pid_var_name: Name of variable to store PID (nameref)
#   $5 - result_file_var_name: Name of variable to store result file path (nameref)
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Sets pid_var_name and result_file_var_name via nameref
# ------------------------------------------------------------------------------
function __spawn_test_job() {
  local test_file="$1"
  local test_type="$2"
  local results_dir="$3"
  local -n _pid_out="$4"
  local -n _result_file_out="$5"

  local test_name
  test_name=$(basename "$test_file" .sh)

  # Generate result file path before spawning (test_name is unique per run)
  # Use distinct name to avoid nameref collision with caller's variable
  local _rf_path="${results_dir}/${test_name}.result"
  _result_file_out="$_rf_path"

  # Launch job in subshell (isolated environment)
  # CRITICAL: Redirect stdout/stderr to test log file to prevent blocking
  # and to capture any output from the test execution.
  local test_log="${TEST_LOG_DIR}/${test_name}.log"
  (
    # Trap for cleanup on exit/error
    # shellcheck disable=SC2064
    trap "cleanup_sandbox \"\${sandbox_path:-}\" 2>/dev/null || true" EXIT INT TERM

    # Create sandbox (no 'local' - we're not in a function context inside subshell)
    # Use unique sandbox ID: "type_testname" to avoid conflicts between parallel jobs
    sandbox_path=""
    if ! sandbox_path=$(create_sandbox "${test_type}_${test_name}"); then
      log_error "Failed to create sandbox for test: $test_name"

      # Write error result
      declare -A error_result=(
        [test_name]="$test_name"
        [test_type]="$test_type"
        [exit_code]="$EC_ERROR"
        [assertions_passed]="0"
        [assertions_failed]="0"
        [assertions_total]="0"
        [duration_seconds]="0"
        [test_log_path]=""
        [sandbox_path]=""
        [timestamp]="$(date +%Y-%m-%dT%H:%M:%S%z)"
      )
      __write_result_to_file error_result "$_rf_path"
      exit $EC_ERROR
    fi

    # Execute test in sandbox (uses execute_test_in_sandbox from common module)
    declare -A test_result
    execute_test_in_sandbox "$test_file" "$test_type" "$sandbox_path" "$test_log" test_result

    # Serialize result for parent process
    __write_result_to_file test_result "$_rf_path"

    # Cleanup sandbox (unless keeping for failed tests)
    if [[ "${TEST_CLEANUP_SANDBOXES:-true}" == "true" ]]; then
      test_exit_code="${test_result[exit_code]:-1}"
      if [[ "$test_exit_code" -eq $EC_SUCCESS ]]; then
        cleanup_sandbox "$sandbox_path" >/dev/null 2>&1 || true
      else
        log_debug "Keeping sandbox for failed test: $sandbox_path"
      fi
    fi

    # Exit with test result code
    exit "${test_result[exit_code]:-1}"
  ) >>"$test_log" 2>&1 &

  # Store job PID via nameref (NOT in a subshell, so parent can wait for it)
  _pid_out=$!
  return $EC_SUCCESS
}
export -f __spawn_test_job

# ------------------------------------------------------------------------------
# Wait for a job slot to become available
# ------------------------------------------------------------------------------
# Blocks until the number of running background jobs is below TEST_PARALLEL.
# Uses `wait -n` (Bash 4.3+) for efficient waiting.
#
# Arguments: None (reads TEST_PARALLEL from environment)
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function __wait_for_job_slot() {
  local max_jobs="${TEST_PARALLEL:-4}"

  # Count running background jobs
  local running_jobs
  running_jobs=$(jobs -rp | wc -l)

  # If at capacity, wait for any one job to complete
  if [[ $running_jobs -ge $max_jobs ]]; then
    # wait -n: Wait for next job completion (Bash 4.3+)
    # This is more efficient than polling
    wait -n 2>/dev/null || true
  fi

  return $EC_SUCCESS
}
export -f __wait_for_job_slot

# ------------------------------------------------------------------------------
# Collect results from all completed jobs
# ------------------------------------------------------------------------------
# Reads result files written by job subshells and populates the main
# results array using compound keys.
#
# Arguments:
#   $1 - result_files_name: Name of associative array (test_name -> result_file)
#   $2 - results_name: Name of main results associative array
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Side effect: Populates results array with test results
# ------------------------------------------------------------------------------
function __collect_completed_jobs() {
  local result_files_name="$1"
  local results_name="$2"

  # Get namerefs
  local -n result_files_ref="$result_files_name"
  local -n results_ref="$results_name"

  local collected_count=0

  # Iterate through expected result files
  for test_name in "${!result_files_ref[@]}"; do
    local result_file="${result_files_ref[$test_name]}"

    # Check if result file exists
    if [[ ! -f "$result_file" ]]; then
      log_warning "Result file not found for test: $test_name (job may have crashed)"

      # Create missing result (treat as error)
      results_ref["${test_name}__test_name"]="$test_name"
      results_ref["${test_name}__test_type"]="unknown"
      results_ref["${test_name}__exit_code"]="$EC_ERROR"
      results_ref["${test_name}__assertions_passed"]="0"
      results_ref["${test_name}__assertions_failed"]="0"
      results_ref["${test_name}__assertions_total"]="0"
      results_ref["${test_name}__duration_seconds"]="0"
      results_ref["${test_name}__test_log_path"]=""
      results_ref["${test_name}__sandbox_path"]=""
      results_ref["${test_name}__timestamp"]="$(date +%Y-%m-%dT%H:%M:%S%z)"

      collected_count=$((collected_count + 1))
      continue
    fi

    # Read result file into temporary array
    declare -A test_result
    if ! __read_result_from_file "$result_file" test_result; then
      log_error "Failed to read result file: $result_file"

      # Create error result
      results_ref["${test_name}__test_name"]="$test_name"
      results_ref["${test_name}__exit_code"]="$EC_ERROR"
      collected_count=$((collected_count + 1))
      continue
    fi

    # Flatten to compound keys using helper from execution.common.sh
    __flatten_result_to_compound_keys "$test_name" test_result results_ref

    collected_count=$((collected_count + 1))

    log_debug "Collected result for test: $test_name (${collected_count} total)"
  done

  return $EC_SUCCESS
}
export -f __collect_completed_jobs

# ------------------------------------------------------------------------------
# Cleanup temporary result files directory
# ------------------------------------------------------------------------------
# Removes the .results directory containing serialized job results.
# Preserves files in debug mode for inspection.
#
# Arguments:
#   $1 - results_dir: Directory to remove
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function __cleanup_result_files() {
  local results_dir="$1"

  if [[ -z "$results_dir" ]]; then
    log_warning "__cleanup_result_files: results_dir is empty"
    return $EC_SUCCESS
  fi

  # Safety check: Only remove .results directories
  if [[ ! "$results_dir" =~ \.results$ ]]; then
    log_error "__cleanup_result_files: refusing to remove non-.results directory: $results_dir"
    return $EC_FAILURE
  fi

  # Preserve in debug mode
  if [[ "${TEST_DEBUG:-false}" == "true" ]]; then
    log_info "Preserving result files for inspection: $results_dir"
    return $EC_SUCCESS
  fi

  # Remove directory
  if [[ -d "$results_dir" ]]; then
    rm -rf "$results_dir" || {
      log_warning "Failed to remove results directory: $results_dir"
      return $EC_FAILURE
    }
    log_debug "Cleaned up result files: $results_dir"
  fi

  return $EC_SUCCESS
}
export -f __cleanup_result_files

# ==============================================================================
# Public API Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Execute tests in parallel with configurable concurrency
# ------------------------------------------------------------------------------
# Spawns multiple test jobs concurrently, up to TEST_PARALLEL limit.
# Results are collected via IPC (serialized result files).
#
# Arguments:
#   $1 - test_type: "unit", "integration", or "e2e"
#   $2 - test_files_array: Name of array containing test file paths
#   $3 - results_array: Name of associative array to populate with results
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Side effect: Populates results_array with compound keys
# Result array structure:
#   Identical to execute_tests_sequential() - uses compound keys:
#   results_array[test_name__field]="value"
# ------------------------------------------------------------------------------
function execute_tests_parallel() {
  local test_type="$1"
  local test_files_name="$2"
  local results_name="$3"
  local -n test_files_ref="$test_files_name"
  local -n results_ref="$results_name"

  # Validate test type
  if [[ ! "$test_type" =~ ^(unit|integration|e2e)$ ]]; then
    log_error "Invalid test type: $test_type (expected: unit, integration, or e2e)"
    return $EC_FAILURE
  fi

  # Check if test files array is empty
  if [[ ${#test_files_ref[@]} -eq 0 ]]; then
    log_warning "No test files provided for parallel execution"
    return $EC_SUCCESS
  fi

  # Get concurrency limit
  local max_parallel="${TEST_PARALLEL:-4}"
  local total_tests=${#test_files_ref[@]}

  # Create results directory for IPC
  local results_dir="${TEST_LOG_DIR}/.results"
  mkdir -p "$results_dir" || {
    log_error "Failed to create results directory: $results_dir"
    return $EC_FAILURE
  }

  # Initialize job tracking
  declare -A active_jobs      # pid -> test_name
  declare -A result_files     # test_name -> result_file_path
  local spawned_count=0

  # Spawn jobs with concurrency limit
  for test_file in "${test_files_ref[@]}"; do
    local test_name
    test_name=$(basename "$test_file" .sh)

    # Wait for job slot if at capacity
    __wait_for_job_slot

    # Spawn job - uses namerefs to return PID and result file path
    # This avoids command substitution which would orphan the background jobs
    local job_pid=""
    local result_file=""
    __spawn_test_job "$test_file" "$test_type" "$results_dir" job_pid result_file

    # Track job
    active_jobs[$job_pid]="$test_name"
    result_files["$test_name"]="$result_file"
    spawned_count=$((spawned_count + 1))

    log_debug "Spawned job ${spawned_count}/${total_tests}: $test_name (PID: $job_pid)"
  done

  # Wait for all remaining jobs to complete
  wait

  # Collect all results from files (pass original name to avoid circular ref)
  __collect_completed_jobs result_files "$results_name"

  # Cleanup result files directory
  __cleanup_result_files "$results_dir"

  return $EC_SUCCESS
}
export -f execute_tests_parallel

# ==============================================================================
# Module Initialization
# ==============================================================================

# Mark module as loaded
declare -g TEST_EXECUTION_PARALLEL_LOADED=1
export TEST_EXECUTION_PARALLEL_LOADED
