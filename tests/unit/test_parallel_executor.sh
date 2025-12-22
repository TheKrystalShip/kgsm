#!/usr/bin/env bash

# KGSM Parallel Executor Tests
#
# Test Type: UNIT
# Target: tests/framework/execution.parallel.sh
#
# Tests the parallel test execution module including:
# - Job spawning and management
# - Concurrency limiting
# - Result collection via serialization
# - Integration with execution.common.sh helpers

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="parallel_executor"

# Temp directory for test artifacts
TEST_TEMP_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up parallel executor tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_not_null "${TEST_EXECUTION_COMMON_LOADED:-}" "execution.common.sh should be loaded"

  # Create temp directory for test files
  TEST_TEMP_DIR=$(mktemp -d -t "kgsm-parallel-test-XXXXXX")
  assert_dir_exists "$TEST_TEMP_DIR" "Temp directory should be created"

  # Verify parallel module functions exist
  assert_function_exists "execute_tests_parallel" "execute_tests_parallel should be available"
  assert_function_exists "__spawn_test_job" "__spawn_test_job should be available"
  assert_function_exists "__wait_for_job_slot" "__wait_for_job_slot should be available"
  assert_function_exists "__collect_completed_jobs" "__collect_completed_jobs should be available"
  assert_function_exists "__cleanup_result_files" "__cleanup_result_files should be available"

  log_test_step "Test environment validated"
}

function cleanup_test() {
  log_test_step "Cleaning up parallel executor test resources"

  # Remove temp directory
  if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

function test_parallel_config_normalization() {
  log_test_step "Testing TEST_PARALLEL configuration normalization"

  # The config module should normalize TEST_PARALLEL to an integer
  assert_not_null "$TEST_PARALLEL" "TEST_PARALLEL should be set"

  # Should be a positive integer
  if [[ "$TEST_PARALLEL" =~ ^[0-9]+$ ]]; then
    assert_true "[[ $TEST_PARALLEL -ge 1 ]]" "TEST_PARALLEL should be >= 1"
    assert_true "[[ $TEST_PARALLEL -le 32 ]]" "TEST_PARALLEL should be <= 32"
  else
    fail_test "TEST_PARALLEL should be an integer, got: $TEST_PARALLEL"
  fi
}

function test_executor_selection() {
  log_test_step "Testing executor selection based on TEST_PARALLEL"

  # Check which executor is active
  local active
  active=$(get_active_executor)

  assert_not_null "$active" "Active executor should be set"

  if [[ "$TEST_PARALLEL" -le 1 ]]; then
    assert_equals "$active" "sequential" "Should use sequential when TEST_PARALLEL <= 1"
  else
    assert_equals "$active" "parallel" "Should use parallel when TEST_PARALLEL > 1"
  fi
}

# =============================================================================
# JOB SLOT MANAGEMENT TESTS
# =============================================================================

function test_wait_for_job_slot_no_jobs() {
  log_test_step "Testing __wait_for_job_slot with no running jobs"

  # With no background jobs, should return immediately
  local start_time end_time duration
  start_time=$(date +%s)

  __wait_for_job_slot
  local exit_code=$?

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  assert_equals "$exit_code" "0" "Should return success"
  assert_true "[[ $duration -lt 2 ]]" "Should return quickly (< 2s)"
}

function test_wait_for_job_slot_under_limit() {
  log_test_step "Testing __wait_for_job_slot under concurrency limit"

  # Save original TEST_PARALLEL
  local original_parallel="$TEST_PARALLEL"
  TEST_PARALLEL=4

  # Start one background job (sleep)
  sleep 10 &
  local job_pid=$!

  # Should return immediately since we're under limit
  local start_time end_time duration
  start_time=$(date +%s)

  __wait_for_job_slot
  local exit_code=$?

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  # Cleanup
  kill $job_pid 2>/dev/null || true
  wait $job_pid 2>/dev/null || true
  TEST_PARALLEL="$original_parallel"

  assert_equals "$exit_code" "0" "Should return success"
  assert_true "[[ $duration -lt 2 ]]" "Should return quickly when under limit"
}

# =============================================================================
# RESULT COLLECTION TESTS
# =============================================================================

function test_collect_completed_jobs_basic() {
  log_test_step "Testing __collect_completed_jobs with valid result files"

  # Create a mock results directory
  local results_dir="$TEST_TEMP_DIR/results"
  mkdir -p "$results_dir"

  # Create mock result files
  cat > "$results_dir/test_one_123.result" << 'EOF'
test_name=test_one
test_type=unit
exit_code=0
assertions_passed=5
assertions_failed=0
assertions_total=5
duration_seconds=2
test_log_path=/tmp/test_one.log
sandbox_path=/tmp/sandbox_one
timestamp=2024-12-21T20:00:00+0000
EOF

  cat > "$results_dir/test_two_456.result" << 'EOF'
test_name=test_two
test_type=unit
exit_code=1
assertions_passed=3
assertions_failed=2
assertions_total=5
duration_seconds=3
test_log_path=/tmp/test_two.log
sandbox_path=/tmp/sandbox_two
timestamp=2024-12-21T20:01:00+0000
EOF

  # Setup result_files tracking array
  declare -A result_files=(
    [test_one]="$results_dir/test_one_123.result"
    [test_two]="$results_dir/test_two_456.result"
  )

  # Collect results
  declare -A collected_results
  __collect_completed_jobs result_files collected_results
  local exit_code=$?

  assert_equals "$exit_code" "0" "Collection should succeed"

  # Verify test_one results
  assert_equals "${collected_results[test_one__test_name]}" "test_one" "test_one name"
  assert_equals "${collected_results[test_one__exit_code]}" "0" "test_one exit_code"
  assert_equals "${collected_results[test_one__assertions_passed]}" "5" "test_one assertions_passed"

  # Verify test_two results
  assert_equals "${collected_results[test_two__test_name]}" "test_two" "test_two name"
  assert_equals "${collected_results[test_two__exit_code]}" "1" "test_two exit_code"
  assert_equals "${collected_results[test_two__assertions_failed]}" "2" "test_two assertions_failed"
}

function test_collect_completed_jobs_missing_file() {
  log_test_step "Testing __collect_completed_jobs with missing result file"

  # Setup result_files with non-existent file
  declare -A result_files=(
    [missing_test]="$TEST_TEMP_DIR/nonexistent.result"
  )

  # Collect results (should create error entry)
  declare -A collected_results
  __collect_completed_jobs result_files collected_results
  local exit_code=$?

  assert_equals "$exit_code" "0" "Collection should succeed (handles missing files)"
  assert_equals "${collected_results[missing_test__exit_code]}" "$EC_ERROR" "Missing file should create error result"
}

# =============================================================================
# CLEANUP TESTS
# =============================================================================

function test_cleanup_result_files_safety() {
  log_test_step "Testing __cleanup_result_files safety checks"

  # Should refuse to remove non-.results directories
  local unsafe_dir="$TEST_TEMP_DIR/unsafe"
  mkdir -p "$unsafe_dir"

  __cleanup_result_files "$unsafe_dir"
  local exit_code=$?

  assert_not_equals "$exit_code" "0" "Should fail for non-.results directory"
  assert_dir_exists "$unsafe_dir" "Unsafe directory should NOT be removed"

  # Cleanup
  rmdir "$unsafe_dir"
}

function test_cleanup_result_files_valid() {
  log_test_step "Testing __cleanup_result_files with valid .results directory"

  # Create a .results directory
  local results_dir="$TEST_TEMP_DIR/test.results"
  mkdir -p "$results_dir"
  touch "$results_dir/test.result"

  # Ensure we're not in debug mode for this test
  local original_debug="${TEST_DEBUG:-false}"
  TEST_DEBUG=false

  __cleanup_result_files "$results_dir"
  local exit_code=$?

  TEST_DEBUG="$original_debug"

  assert_equals "$exit_code" "0" "Cleanup should succeed"
  assert_dir_not_exists "$results_dir" ".results directory should be removed"
}

function test_cleanup_result_files_debug_preserve() {
  log_test_step "Testing __cleanup_result_files preserves in debug mode"

  # Create a .results directory
  local results_dir="$TEST_TEMP_DIR/debug.results"
  mkdir -p "$results_dir"
  touch "$results_dir/test.result"

  # Enable debug mode
  local original_debug="${TEST_DEBUG:-false}"
  TEST_DEBUG=true

  __cleanup_result_files "$results_dir"
  local exit_code=$?

  TEST_DEBUG="$original_debug"

  assert_equals "$exit_code" "0" "Cleanup should succeed"
  assert_dir_exists "$results_dir" ".results directory should be preserved in debug mode"

  # Manual cleanup
  rm -rf "$results_dir"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

function test_parallel_executor_available() {
  log_test_step "Testing parallel executor availability"

  local available
  if is_parallel_available; then
    available="yes"
  else
    available="no"
  fi

  assert_equals "$available" "yes" "Parallel executor should be available"
}

function test_execute_tests_parallel_empty_array() {
  log_test_step "Testing execute_tests_parallel with empty test array"

  # Create empty test files array
  declare -a empty_tests=()
  declare -A results

  # Should handle empty array gracefully
  execute_tests_parallel "unit" empty_tests results
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed with empty array"
}

function test_execute_tests_parallel_invalid_type() {
  log_test_step "Testing execute_tests_parallel with invalid test type"

  declare -a test_files=("/tmp/test.sh")
  declare -A results

  execute_tests_parallel "invalid_type" test_files results
  local exit_code=$?

  assert_not_equals "$exit_code" "0" "Should fail with invalid test type"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting parallel executor tests"

  # Initialize test environment
  setup_test

  # Configuration tests
  test_parallel_config_normalization
  test_executor_selection

  # Job slot management tests
  test_wait_for_job_slot_no_jobs
  test_wait_for_job_slot_under_limit

  # Result collection tests
  test_collect_completed_jobs_basic
  test_collect_completed_jobs_missing_file

  # Cleanup tests
  test_cleanup_result_files_safety
  test_cleanup_result_files_valid
  test_cleanup_result_files_debug_preserve

  # Integration tests
  test_parallel_executor_available
  test_execute_tests_parallel_empty_array
  test_execute_tests_parallel_invalid_type

  # Cleanup
  cleanup_test

  log_test_step "Parallel executor tests completed"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All parallel executor tests completed successfully"
  else
    fail_test "Some parallel executor tests failed"
  fi
}

# Execute main function
main "$@"
