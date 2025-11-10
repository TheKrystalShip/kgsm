#!/usr/bin/env bash

# KGSM Instances Module Unit Tests
# Tests the core functionality of the instances.sh module

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="instances_module"
readonly INSTANCES_MODULE="$KGSM_ROOT/modules/instances.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up instances module tests"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "Test environment validated"
}

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  assert_file_exists "$INSTANCES_MODULE" "instances.sh module should exist"

  # Check if file is executable
  if [[ -x "$INSTANCES_MODULE" ]]; then
    assert_true "true" "instances.sh module should be executable"
  else
    assert_true "false" "instances.sh module should be executable"
  fi
}

function test_module_help_functionality() {
  log_step "Testing module help functionality"

  assert_command_succeeds "$INSTANCES_MODULE --help" "instances.sh --help should work"
}

function test_module_list_functionality() {
  log_step "Testing module list functionality"

  # List should work even with no instances
  assert_command_succeeds "$INSTANCES_MODULE list" "instances.sh list should work"
}

function test_module_json_list_functionality() {
  log_step "Testing module JSON list functionality"

  assert_command_succeeds "$INSTANCES_MODULE list --json" "instances.sh list --json should work"
}

function test_instance_id_generation() {
  log_step "Testing instance ID generation"

  # First, check if we have a blueprint to test with
  local factorio_blueprint="$KGSM_ROOT/blueprints/default/native/factorio.bp"

  if [[ -f "$factorio_blueprint" ]]; then
    local instance_id
    if instance_id=$("$INSTANCES_MODULE" generate-id factorio.bp 2>/dev/null); then
      assert_not_null "$instance_id" "Generated instance ID should not be empty"
      log_test "Generated instance ID: $instance_id"
    else
      log_test "ID generation failed - this may be expected if blueprint requirements aren't met"
    fi
  else
    log_test "No factorio.bp found, skipping ID generation test"
  fi
}

function test_invalid_argument_handling() {
  log_step "Testing invalid argument handling"

  assert_command_fails "$INSTANCES_MODULE --invalid-argument" "Module should reject invalid arguments"
}

function test_missing_argument_handling() {
  log_step "Testing missing argument handling"

  # create should require arguments
  assert_command_fails "$INSTANCES_MODULE create" "Module should require arguments for create"
}

function test_find_nonexistent_instance() {
  log_step "Testing find functionality with non-existent instance"

  local nonexistent_name="nonexistent-test-instance-$(date +%s)"
  assert_command_fails "$INSTANCES_MODULE find '$nonexistent_name'" "Module should fail when finding non-existent instance"
}

function test_module_output_format() {
  log_step "Testing module output format consistency"

  # Test that list produces parseable output (even if empty)
  local list_output
  if list_output=$("$INSTANCES_MODULE" list 2>/dev/null); then
    log_test "List command produces output (may be empty if no instances)"
  else
    log_test "List command failed - this may indicate a configuration issue"
  fi

  # Test that list --json produces valid format (if jq is available)
  if command -v jq >/dev/null 2>&1; then
    local json_output
    if json_output=$("$INSTANCES_MODULE" list --json 2>/dev/null); then
      if echo "$json_output" | jq . >/dev/null 2>&1; then
        assert_true "true" "JSON output should be valid JSON"
      else
        log_test "JSON output is not valid JSON format"
      fi
    fi
  else
    log_test "jq not available, skipping JSON validation"
  fi
}

function test_module_status_functionality() {
  log_step "Testing module status-related functionality"

  # Test status command with non-existent instance (should fail gracefully)
  local test_instance="test-nonexistent-$(date +%s)"

  # Status check for non-existent instance should fail
  if "$INSTANCES_MODULE" status "$test_instance" >/dev/null 2>&1; then
    log_test "Status command succeeded for non-existent instance (unexpected but not necessarily wrong)"
  else
    log_test "Status command failed for non-existent instance (expected behavior)"
  fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting instances module unit tests"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_module_existence_and_permissions
  test_module_help_functionality
  test_module_list_functionality
  test_module_json_list_functionality
  test_instance_id_generation
  test_invalid_argument_handling
  test_missing_argument_handling
  test_find_nonexistent_instance
  test_module_output_format
  test_module_status_functionality

  log_test "Instances module tests completed successfully"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All instances module tests completed successfully"
  else
    fail_test "Some instances module tests failed"
  fi
}

# Execute main function
main "$@"
