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

function setup_file() {
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

function test_status_output_format() {
  log_test_step "Testing __logic_instance_status output format"

  local blueprint="factorio"
  local instance_name="factorio_test_instance_$$"
  instance_name=$(create_test_instance "$blueprint" "$instance_name" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  status_output=$(__logic_instance_status "$instance_name" 2>&1)
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
  instance_name=$(create_test_instance "$blueprint" "$instance_name" 2>/dev/null)

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

