#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - Execution Orchestrator Module
# ==============================================================================
# Version: 1.0
# Description: Orchestrates test execution by delegating to the appropriate
#              executor (sequential or parallel) based on configuration.
#              This is the main entry point for all test execution - callers
#              should only source this module, not the underlying executors.
# Dependencies: execution.common.sh, config.sh
# Conditionally loads: execution.sequential.sh OR execution.parallel.sh
# ==============================================================================

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

# Load guard to prevent multiple sourcing
if [[ -n "${TEST_EXECUTION_LOADED:-}" ]]; then
  return 0
fi

# Get the framework directory
_EXECUTION_FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Load Common Execution Module (always required)
# ==============================================================================

# shellcheck disable=SC1091
source "${_EXECUTION_FRAMEWORK_DIR}/execution.common.sh" || {
  echo "ERROR: Failed to load execution.common.sh" >&2
  return 1
}

# ==============================================================================
# Load Executor Based on Configuration
# ==============================================================================

# Determine which executor to use based on TEST_PARALLEL config
# TEST_PARALLEL is now an integer: 1 = sequential, 2+ = parallel
# The config.sh module normalizes boolean/auto values to integers
_parallel_count="${TEST_PARALLEL:-1}"

# Use parallel executor if TEST_PARALLEL > 1
if [[ "$_parallel_count" -gt 1 ]]; then
  # Load parallel executor
  # shellcheck disable=SC1091
  if [[ -f "${_EXECUTION_FRAMEWORK_DIR}/execution.parallel.sh" ]]; then
    if [[ -z "${TEST_EXECUTION_PARALLEL_LOADED:-}" ]]; then
      source "${_EXECUTION_FRAMEWORK_DIR}/execution.parallel.sh" || {
        echo "ERROR: Failed to load execution.parallel.sh" >&2
        return 1
      }
    fi
    _active_executor="parallel"
    log_debug "Parallel executor loaded (concurrency: $_parallel_count)"
  else
    # Parallel executor not found, fall back to sequential
    log_warning "Parallel execution requested (TEST_PARALLEL=$_parallel_count) but execution.parallel.sh not found. Falling back to sequential."
    _parallel_count=1
  fi
fi

# Load sequential executor (either as primary or as fallback)
if [[ "$_parallel_count" -le 1 ]]; then
  # shellcheck disable=SC1091
  if [[ -z "${TEST_EXECUTION_SEQUENTIAL_LOADED:-}" ]]; then
    source "${_EXECUTION_FRAMEWORK_DIR}/execution.sequential.sh" || {
      echo "ERROR: Failed to load execution.sequential.sh" >&2
      return 1
    }
  fi
  _active_executor="sequential"
fi

# ==============================================================================
# Public API Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Execute tests using the configured executor
# ------------------------------------------------------------------------------
# This is the main entry point for test execution. It delegates to either
# execute_tests_sequential() or execute_tests_parallel() based on config.
#
# Arguments:
#   $1 - test_type: "unit", "integration", or "e2e"
#   $2 - test_files_array: Name of array containing test file paths
#   $3 - results_array: Name of associative array to populate with results
# Returns:
#   Exit code from the underlying executor
# ------------------------------------------------------------------------------
function execute_tests() {
  local test_type="$1"
  local test_files_array_name="$2"
  local results_array_name="$3"

  if [[ "$_active_executor" == "parallel" ]]; then
    log_debug "Executing tests using parallel executor"
    execute_tests_parallel "$test_type" "$test_files_array_name" "$results_array_name"
  else
    log_debug "Executing tests using sequential executor"
    execute_tests_sequential "$test_type" "$test_files_array_name" "$results_array_name"
  fi
}
export -f execute_tests

# ------------------------------------------------------------------------------
# Get the currently active executor type
# ------------------------------------------------------------------------------
# Returns:
#   Stdout: "sequential" or "parallel"
# ------------------------------------------------------------------------------
function get_active_executor() {
  echo "$_active_executor"
}
export -f get_active_executor

# ------------------------------------------------------------------------------
# Check if parallel execution is available
# ------------------------------------------------------------------------------
# Returns:
#   Exit code: 0 if parallel executor is available, 1 otherwise
# ------------------------------------------------------------------------------
function is_parallel_available() {
  [[ -f "${_EXECUTION_FRAMEWORK_DIR}/execution.parallel.sh" ]]
}
export -f is_parallel_available

# ==============================================================================
# Module Initialization
# ==============================================================================

# Export active executor for debugging/logging
export _active_executor

# Log which executor is active (only in debug mode)
log_debug "Execution module loaded. Active executor: $_active_executor"

# Mark module as loaded
declare -g TEST_EXECUTION_LOADED=1
export TEST_EXECUTION_LOADED
