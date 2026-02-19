#!/usr/bin/env bash

# KGSM Lifecycle Handler Logic Tests
#
# Test Type: UNIT
# Target: commands/handlers/lifecycle.sh - Pure __logic_* functions
#
# Tests all logic functions for lifecycle management including start, stop,
# restart, is-active checks, status retrieval, and logs. Focuses on standalone
# mode since systemd requires real service infrastructure.

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="lifecycle_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/lifecycle.sh"

# Test-specific paths
TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up lifecycle logic tests"

  # Set test install directory within sandbox
  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Verify handler exists
  assert_file_exists "$HANDLER" "Handler should exist"

  # Source the handler
  # shellcheck disable=SC1090
  source "$HANDLER"

  # Verify success event codes
  assert_not_null "$EC_SUCCESS_INSTANCE_STARTED" "EC_SUCCESS_INSTANCE_STARTED should be defined"
  assert_equals 211 "$EC_SUCCESS_INSTANCE_STARTED" "EC_SUCCESS_INSTANCE_STARTED should be 211"

  assert_not_null "$EC_SUCCESS_INSTANCE_STOPPED" "EC_SUCCESS_INSTANCE_STOPPED should be defined"
  assert_equals 212 "$EC_SUCCESS_INSTANCE_STOPPED" "EC_SUCCESS_INSTANCE_STOPPED should be 212"

  assert_not_null "$EC_SUCCESS_INSTANCE_RESTARTED" "EC_SUCCESS_INSTANCE_RESTARTED should be defined"
  assert_equals 213 "$EC_SUCCESS_INSTANCE_RESTARTED" "EC_SUCCESS_INSTANCE_RESTARTED should be 213"

  # Verify error codes
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"

  # Verify main logic functions are exported
  assert_function_exists "__logic_instance_start" "__logic_instance_start should be exported"
  assert_function_exists "__logic_instance_stop" "__logic_instance_stop should be exported"
  assert_function_exists "__logic_instance_restart" "__logic_instance_restart should be exported"
  assert_function_exists "__logic_instance_is_active" "__logic_instance_is_active should be exported"
  assert_function_exists "__logic_instance_status" "__logic_instance_status should be exported"
  assert_function_exists "__logic_instance_logs" "__logic_instance_logs should be exported"

  # Verify helper functions
  assert_function_exists "__get_lifecycle_manager" "__get_lifecycle_manager should be exported"
  assert_function_exists "__logic_start_standalone_instance" "__logic_start_standalone_instance should be exported"
  assert_function_exists "__logic_stop_standalone_instance" "__logic_stop_standalone_instance should be exported"
  assert_function_exists "__logic_is_active_standalone_instance" "__logic_is_active_standalone_instance should be exported"
  assert_function_exists "__logic_logs_standalone_instance" "__logic_logs_standalone_instance should be exported"

  log_test_step "Test environment validated"
}

# =============================================================================
# __logic_instance_start() ERROR HANDLING TESTS
# =============================================================================

function test_start_empty_instance_name() {
  log_test_step "Testing __logic_instance_start with empty instance name"

  # Execute with empty name
  __logic_instance_start "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty instance name"
}

function test_start_nonexistent_instance() {
  log_test_step "Testing __logic_instance_start with nonexistent instance"

  local fake_instance="nonexistent_instance_xyz_12345"

  # Execute with nonexistent instance
  __logic_instance_start "$fake_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for nonexistent instance"
}

# =============================================================================
# __logic_instance_stop() ERROR HANDLING TESTS
# =============================================================================

function test_stop_empty_instance_name() {
  log_test_step "Testing __logic_instance_stop with empty instance name"

  # Execute with empty name
  __logic_instance_stop "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty instance name"
}

function test_stop_nonexistent_instance() {
  log_test_step "Testing __logic_instance_stop with nonexistent instance"

  local fake_instance="nonexistent_instance_xyz_12345"

  # Execute with nonexistent instance
  __logic_instance_stop "$fake_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for nonexistent instance"
}

# =============================================================================
# __logic_instance_restart() ERROR HANDLING TESTS
# =============================================================================

function test_restart_empty_instance_name() {
  log_test_step "Testing __logic_instance_restart with empty instance name"

  # Execute with empty name
  __logic_instance_restart "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty instance name"
}

function test_restart_nonexistent_instance() {
  log_test_step "Testing __logic_instance_restart with nonexistent instance"

  local fake_instance="nonexistent_instance_xyz_12345"

  # Execute with nonexistent instance
  __logic_instance_restart "$fake_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for nonexistent instance"
}

# =============================================================================
# __logic_instance_is_active() ERROR HANDLING TESTS
# =============================================================================

function test_is_active_empty_instance_name() {
  log_test_step "Testing __logic_instance_is_active with empty instance name"

  # Execute with empty name
  __logic_instance_is_active "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty instance name"
}

function test_is_active_nonexistent_instance() {
  log_test_step "Testing __logic_instance_is_active with nonexistent instance"

  local fake_instance="nonexistent_instance_xyz_12345"

  # Execute with nonexistent instance
  __logic_instance_is_active "$fake_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for nonexistent instance"
}

# =============================================================================
# __logic_instance_status() ERROR HANDLING TESTS
# =============================================================================

function test_status_empty_instance_name() {
  log_test_step "Testing __logic_instance_status with empty instance name"

  # Execute with empty name
  __logic_instance_status "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty instance name"
}

function test_status_nonexistent_instance() {
  log_test_step "Testing __logic_instance_status with nonexistent instance"

  local fake_instance="nonexistent_instance_xyz_12345"

  # Execute with nonexistent instance
  __logic_instance_status "$fake_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for nonexistent instance"
}

# =============================================================================
# __logic_instance_logs() ERROR HANDLING TESTS
# =============================================================================

function test_logs_empty_instance_name() {
  log_test_step "Testing __logic_instance_logs with empty instance name"

  # Execute with empty name
  __logic_instance_logs "" "" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty instance name"
}

function test_logs_nonexistent_instance() {
  log_test_step "Testing __logic_instance_logs with nonexistent instance"

  local fake_instance="nonexistent_instance_xyz_12345"

  # Execute with nonexistent instance
  __logic_instance_logs "$fake_instance" "" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for nonexistent instance"
}

# =============================================================================
# __get_lifecycle_manager() HELPER TESTS
# =============================================================================

function test_get_lifecycle_manager_empty_config_path() {
  log_test_step "Testing __get_lifecycle_manager with empty config path"

  # Execute with empty path
  __get_lifecycle_manager "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty config path"
}

function test_get_lifecycle_manager_nonexistent_config() {
  log_test_step "Testing __get_lifecycle_manager with nonexistent config file"

  local fake_config="/tmp/nonexistent_config_xyz_12345.conf"

  # Execute with nonexistent config
  __get_lifecycle_manager "$fake_config" 2>/dev/null
  local exit_code=$?

  # Should return non-zero exit code (any error is acceptable)
  assert_not_equals 0 "$exit_code" "Should return non-zero exit code for nonexistent config"
}

# =============================================================================
# STANDALONE INSTANCE TESTS (WITH REAL INSTANCE)
# =============================================================================
# NOTE: These tests create actual instances and attempt lifecycle operations.
# They are skipped if the management script cannot actually start/stop the server
# (which is expected in sandbox environment without full game server installation).

function test_lifecycle_with_valid_instance() {
  log_test_step "Testing lifecycle operations with valid instance"

  local blueprint="factorio"
  local instance_name="factorio_test_instance_$$"
  instance_name=$(create_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Test: Get lifecycle manager from config
  local config_file="$KGSM_INSTANCES_DIR/$instance_name.config.ini"
  assert_file_exists "$config_file" "Instance config should exist"

  local lifecycle_manager
  lifecycle_manager=$(__get_lifecycle_manager "$config_file" 2>/dev/null)
  local get_manager_exit=$?

  assert_equals 0 "$get_manager_exit" "Should successfully get lifecycle manager from valid config"
  assert_not_null "$lifecycle_manager" "Lifecycle manager should not be empty"

  # Test: is-active on stopped instance (should return 1 = not active)
  __logic_instance_is_active "$instance_name" 2>/dev/null
  local is_active_exit=$?

  # Exit code should be 0 (active) or 1 (inactive), not an error code
  if [[ $is_active_exit -eq 0 ]] || [[ $is_active_exit -eq 1 ]]; then
    local is_active_result="true"
  else
    local is_active_result="false"
  fi
  assert_true "$is_active_result" \
    "is-active should return 0 (active) or 1 (inactive), got $is_active_exit"

  # Test: status command (should succeed even when stopped)
  local status_output
  status_output=$(__logic_instance_status "$instance_name" false false 2>&1)
  local status_exit=$?

  assert_equals 0 "$status_exit" "Status should succeed for valid instance"
  assert_not_null "$status_output" "Status should produce output"

  # Test: logs command (may fail if no logs exist yet, which is acceptable)
  __logic_instance_logs "$instance_name" false 10 2>/dev/null
  local logs_exit=$?

  # Logs can return 0 (success) or various errors if logs don't exist yet
  # We just verify it doesn't crash with INVALID_ARG
  assert_not_equals "$EC_INVALID_ARG" "$logs_exit" \
    "Logs should not return INVALID_ARG for valid instance"

  # Note: We skip actual start/stop/restart tests because:
  # 1. Management script may not exist or be fully functional in test sandbox
  # 2. Game server binaries are not installed
  # 3. These operations are better tested in E2E tests with real servers
  #
  # The error handling tests above already verify parameter validation,
  # which is the primary responsibility of the logic layer.

  # Cleanup
  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_get_lifecycle_manager_with_valid_config() {
  log_test_step "Testing __get_lifecycle_manager with valid instance config"

  local blueprint="factorio"
  local instance_name="factorio_test_instance_$$"
  instance_name=$(create_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Get lifecycle manager
  local config_file="$KGSM_INSTANCES_DIR/$instance_name.config.ini"
  local lifecycle_manager
  lifecycle_manager=$(__get_lifecycle_manager "$config_file" 2>/dev/null)
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should successfully extract lifecycle_manager from config"
  assert_not_null "$lifecycle_manager" "Lifecycle manager value should not be empty"

  # Verify it's a valid value (either "systemd" or "standalone")
  if [[ "$lifecycle_manager" == "systemd" ]] || [[ "$lifecycle_manager" == "standalone" ]]; then
    local is_valid="true"
  else
    local is_valid="false"
  fi
  assert_true "$is_valid" "Lifecycle manager should be 'systemd' or 'standalone', got '$lifecycle_manager'"
}

function test_status_output_format() {
  log_test_step "Testing __logic_instance_status output format"

  local blueprint="factorio"
  local instance_name="factorio_test_instance_$$"
  instance_name=$(create_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  status_output=$(__logic_instance_status "$instance_name" false false 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "Status should succeed"
  assert_not_null "$status_output" "Status should produce output"

  # Verify output contains basic instance information
  assert_contains "$status_output" "$instance_name" \
    "Status output should contain instance name"

  # Cleanup
  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_status_json_format() {
  log_test_step "Testing __logic_instance_status with JSON format flag"

  local blueprint="factorio"
  local instance_name="factorio_test_instance_$$"
  instance_name=$(create_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  status_output=$(__logic_instance_status "$instance_name" true false 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "Status with JSON should succeed"
  assert_not_null "$status_output" "Status should produce output"

  # Basic JSON format validation (should contain braces)
  # Note: Full JSON validation would require jq, which may not be available
  assert_contains "$status_output" "{" "JSON output should contain opening brace"
  assert_contains "$status_output" "}" "JSON output should contain closing brace"

  # Cleanup
  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting lifecycle logic tests"

  # Setup
  setup_test

  # Error handling tests (no instance required)
  test_start_empty_instance_name
  test_start_nonexistent_instance
  test_stop_empty_instance_name
  test_stop_nonexistent_instance
  test_restart_empty_instance_name
  test_restart_nonexistent_instance
  test_is_active_empty_instance_name
  test_is_active_nonexistent_instance
  test_status_empty_instance_name
  test_status_nonexistent_instance
  test_logs_empty_instance_name
  test_logs_nonexistent_instance

  # Helper function tests
  test_get_lifecycle_manager_empty_config_path
  test_get_lifecycle_manager_nonexistent_config

  # Tests with real instances
  test_lifecycle_with_valid_instance
  test_get_lifecycle_manager_with_valid_config
  test_status_output_format
  test_status_json_format

  log_test_step "Lifecycle logic tests completed"

  # Print summary and exit
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All lifecycle logic tests passed"
  else
    fail_test "Some lifecycle logic tests failed"
  fi
}

main "$@"
