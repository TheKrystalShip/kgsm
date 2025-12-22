#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - Sequential Execution Module
# ==============================================================================
# Version: 2.0
# Description: Provides sequential test execution capabilities for the KGSM
#              testing framework. Handles test execution in sandboxed
#              environments, output capture, and result collection.
#              Executes tests one at a time in series.
# Dependencies: execution.common.sh, sandbox.sh
# ==============================================================================

# Load guard to prevent multiple sourcing
if [[ -n "${TEST_EXECUTION_SEQUENTIAL_LOADED:-}" ]]; then
  return 0
fi

# ==============================================================================
# Core Execution Functions
# ==============================================================================
# Note: Helper functions and execute_test_in_sandbox() are provided by
#       execution.common.sh - this module only provides execute_tests_sequential()
# ==============================================================================

# ------------------------------------------------------------------------------
# Execute tests sequentially (one at a time)
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - test_type: "unit", "integration", or "e2e"
#   $2 - test_files_array: Name of array containing test file paths
#   $3 - results_array: Name of associative array to populate with results
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Side effect: Populates results_array with test results
# Result array structure:
#   Flattened associative array with compound keys:
#   results_array[test_name_1__test_name]="test_config_merge_logic"
#   results_array[test_name_1__test_type]="unit"
#   results_array[test_name_1__exit_code]="0"
#   ... (all fields for each test)
# ------------------------------------------------------------------------------
function execute_tests_sequential() {
  local test_type="$1"
  local -n test_files_array="$2"
  local -n results_array="$3"

  # Validate test type
  if [[ ! "$test_type" =~ ^(unit|integration|e2e)$ ]]; then
    log_error "Invalid test type: $test_type (expected: unit, integration, or e2e)"
    return $EC_FAILURE
  fi

  # Check if test files array is empty
  if [[ ${#test_files_array[@]} -eq 0 ]]; then
    log_warning "No test files provided for sequential execution"
    return $EC_SUCCESS
  fi

  log_info "Executing ${#test_files_array[@]} ${test_type} tests sequentially..."

  # Execute each test in order
  local test_count=0
  for test_file in "${test_files_array[@]}"; do
    test_count=$((test_count + 1))

    # Extract test name
    local test_name
    test_name=$(basename "$test_file" .sh)

    log_info "Starting test ${test_count}/${#test_files_array[@]}: $test_name"

    # Create sandbox for this test
    local sandbox_path
    if ! sandbox_path=$(create_sandbox "$test_type" "$test_name" 2>&1); then
      log_error "Failed to create sandbox for test: $test_name"

      # Store error result
      results_array["${test_name}__test_name"]="$test_name"
      results_array["${test_name}__test_type"]="$test_type"
      results_array["${test_name}__exit_code"]="$EC_ERROR"
      results_array["${test_name}__assertions_passed"]="0"
      results_array["${test_name}__assertions_failed"]="0"
      results_array["${test_name}__assertions_total"]="0"
      results_array["${test_name}__duration_seconds"]="0"
      results_array["${test_name}__test_log_path"]=""
      results_array["${test_name}__sandbox_path"]=""
      results_array["${test_name}__timestamp"]="$(date +%Y-%m-%dT%H:%M:%S%z)"

      continue
    fi

    # Generate log file path
    local test_log="${TEST_LOG_DIR}/${test_name}.log"

    # Execute test in sandbox
    declare -A test_result
    execute_test_in_sandbox "$test_file" "$test_type" "$sandbox_path" "$test_log" test_result

    # Copy results to main results array with compound keys
    for key in "${!test_result[@]}"; do
      results_array["${test_name}__${key}"]="${test_result[$key]}"
    done

    # Cleanup sandbox (optional, based on TEST_CLEANUP_SANDBOXES config)
    if [[ "${TEST_CLEANUP_SANDBOXES:-true}" == "true" ]]; then
      local test_exit_code="${test_result[exit_code]:-1}"
      # shellcheck disable=SC2086
      if [[ "$test_exit_code" -eq $EC_SUCCESS ]]; then
        cleanup_sandbox "$sandbox_path" >/dev/null 2>&1 || true
      else
        log_debug "Keeping sandbox for failed test: $sandbox_path"
      fi
    fi

    log_info "Completed test ${test_count}/${#test_files_array[@]}: $test_name (exit: ${test_result[exit_code]})"
  done

  log_info "Sequential execution completed for ${test_count} ${test_type} tests"

  return $EC_SUCCESS
}
export -f execute_tests_sequential

# ==============================================================================
# Module Initialization
# ==============================================================================

# Mark module as loaded
declare -g TEST_EXECUTION_SEQUENTIAL_LOADED=1
export TEST_EXECUTION_SEQUENTIAL_LOADED

