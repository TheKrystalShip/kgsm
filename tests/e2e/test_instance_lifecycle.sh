#!/usr/bin/env bash

# KGSM Instance Lifecycle End-to-End Test
# Tests the complete lifecycle of creating and managing an instance

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="instance_lifecycle"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

# Test variables
TEST_INSTALL_DIR="$KGSM_ROOT/test_instances"
TEST_BLUEPRINT="factorio"
TEST_INSTANCE_NAME="factorio-test"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up instance lifecycle e2e test"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$INSTANCES_MODULE" "instances module should exist"

  # Set up cleanup trap
  trap cleanup_test EXIT

  log_test "Test environment validated"
}

function cleanup_test() {
  log_step "Cleaning up test instance"

  if [[ -n "$TEST_INSTANCE_NAME" ]]; then
    "$INSTANCES_MODULE" --remove "$TEST_INSTANCE_NAME" >/dev/null 2>&1 || true
    log_test "Attempted to remove test instance: $TEST_INSTANCE_NAME"
  fi

  if [[ -d "$TEST_INSTALL_DIR" ]]; then
    rm -rf "$TEST_INSTALL_DIR" >/dev/null 2>&1 || true
    log_test "Cleaned up test install directory"
  fi
}

function test_find_suitable_blueprint() {
  log_step "Finding suitable blueprint for testing"

  # Try to find a suitable blueprint for testing
  if [[ -f "$KGSM_ROOT/blueprints/default/native/factorio.bp" ]]; then
    TEST_BLUEPRINT="factorio.bp"
  elif [[ -f "$KGSM_ROOT/blueprints/default/native/terraria.bp" ]]; then
    TEST_BLUEPRINT="terraria.bp"
  elif [[ -f "$KGSM_ROOT/blueprints/default/native/minecraft.bp" ]]; then
    TEST_BLUEPRINT="minecraft.bp"
  else
    # Find any .bp file
    TEST_BLUEPRINT=$(find "$KGSM_ROOT/blueprints" -name "*.bp" -type f | head -1 | xargs basename 2>/dev/null)
  fi

  assert_not_null "$TEST_BLUEPRINT" "Should find at least one suitable blueprint for testing"
  log_test "Using blueprint: $TEST_BLUEPRINT"
}

function test_create_install_directory() {
  log_step "Creating test install directory"

  assert_command_succeeds "mkdir -p '$TEST_INSTALL_DIR'" "Should be able to create test install directory"
  assert_dir_exists "$TEST_INSTALL_DIR" "Test install directory should exist after creation"

  log_test "Test install directory created: $TEST_INSTALL_DIR"
}

function test_generate_instance_id() {
  log_step "Generating instance ID"

  local generated_id
  if generated_id=$("$INSTANCES_MODULE" --generate-id "$TEST_BLUEPRINT" 2>/dev/null); then
    TEST_INSTANCE_NAME="$generated_id"
    assert_not_null "$TEST_INSTANCE_NAME" "Generated instance ID should not be empty"
    log_test "Generated instance ID: $TEST_INSTANCE_NAME"
  else
    skip_test "Unable to generate instance ID for blueprint: $TEST_BLUEPRINT"
  fi
}

function test_create_instance() {
  log_step "Creating instance"

  local created_instance
  if created_instance=$("$INSTANCES_MODULE" --create "$TEST_BLUEPRINT" --install-dir "$TEST_INSTALL_DIR" --name "$TEST_INSTANCE_NAME" 2>/dev/null); then
    assert_equals "$TEST_INSTANCE_NAME" "$created_instance" "Created instance name should match requested name"
    log_test "Instance created successfully: $created_instance"
  else
    assert_true "false" "Instance creation should succeed, got $created_instance"
  fi
}

function test_instance_appears_in_list() {
  log_step "Verifying instance appears in list"

  local instance_list
  if instance_list=$("$INSTANCES_MODULE" --list 2>/dev/null); then
    assert_list_contains "$instance_list" "$TEST_INSTANCE_NAME" "Instance should appear in instance list"
    log_test "Instance appears in instance list"
  else
    assert_true "false" "Instance list command should succeed"
  fi
}

function test_find_instance_config() {
  log_step "Finding instance configuration file"

  local instance_config
  if instance_config=$("$INSTANCES_MODULE" --find "$TEST_INSTANCE_NAME" 2>/dev/null); then
    assert_file_exists "$instance_config" "Instance config file should exist"
    log_test "Instance config file found: $instance_config"
  else
    assert_true "false" "Should be able to find instance config file"
  fi
}

function test_instance_info() {
  log_step "Getting instance information"

  assert_command_succeeds "$INSTANCES_MODULE --info '$TEST_INSTANCE_NAME'" "Instance info command should work"
}

function test_instance_info_json() {
  log_step "Getting instance information in JSON format"

  local instance_json
  if instance_json=$("$INSTANCES_MODULE" --info "$TEST_INSTANCE_NAME" --json 2>/dev/null); then
    assert_not_null "$instance_json" "Instance JSON info should not be null"
    assert_not_equals "null" "$instance_json" "Instance JSON should contain actual data"

    # Validate JSON format if jq is available
    if command -v jq >/dev/null 2>&1; then
      if echo "$instance_json" | jq . >/dev/null 2>&1; then
        assert_true "true" "Instance JSON should be valid JSON"
      else
        log_test "Instance JSON is not valid format"
      fi
    fi

    log_test "Instance JSON info command works"
  else
    log_test "Instance JSON info command failed - this may be expected for some blueprints"
  fi
}

function test_instance_status() {
  log_step "Getting instance status"

  # Status command should work, though the result may vary
  if "$INSTANCES_MODULE" --status "$TEST_INSTANCE_NAME" >/dev/null 2>&1; then
    log_test "Instance status command works"
  else
    log_test "Instance status command failed - this may be expected for newly created instances"
  fi
}

function test_verify_instance_configuration() {
  log_step "Verifying instance configuration"

  local instance_config
  if instance_config=$("$INSTANCES_MODULE" --find "$TEST_INSTANCE_NAME" 2>/dev/null); then
    assert_file_exists "$instance_config" "Instance configuration file should exist"
    log_test "Instance configuration verified: $instance_config"
  else
    assert_true "false" "Instance configuration should be findable"
  fi
}

function test_remove_instance() {
  log_step "Removing instance"

  local instance_name_to_remove="$TEST_INSTANCE_NAME"

  assert_command_succeeds "$INSTANCES_MODULE --remove '$TEST_INSTANCE_NAME'" "Instance removal should succeed"

  log_test "Instance removed successfully: $instance_name_to_remove"
}

function test_verify_instance_removal() {
  log_step "Verifying instance removal"

  local instance_name_to_check="$TEST_INSTANCE_NAME"
  local instance_list_after

  if instance_list_after=$("$INSTANCES_MODULE" --list 2>/dev/null); then
    assert_list_not_contains "$instance_list_after" "$instance_name_to_check" "Instance should not appear in list after removal"
    log_test "Instance successfully removed from list"
  else
    log_test "Unable to verify instance removal due to list command failure"
  fi
}

function test_complete_lifecycle() {
  log_step "Testing complete instance lifecycle"

  # Run through the complete lifecycle
  test_find_suitable_blueprint
  test_create_install_directory
  test_generate_instance_id
  test_create_instance
  test_instance_appears_in_list
  test_find_instance_config
  test_instance_info
  test_instance_info_json
  test_instance_status
  test_verify_instance_configuration
  test_remove_instance
  test_verify_instance_removal

  log_test "Complete instance lifecycle test completed"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting instance lifecycle e2e test"

  # Initialize test environment
  setup_test

  # Check if we should skip this test due to missing dependencies
  if [[ -z "$(find "$KGSM_ROOT/blueprints" -name "*.bp" -type f | head -1)" ]]; then
    skip_test "No blueprints available for instance lifecycle testing"
  fi

  # Execute complete lifecycle test
  test_complete_lifecycle

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All instance lifecycle e2e tests completed successfully"
  else
    fail_test "Some instance lifecycle e2e tests failed"
  fi
}

# Execute main function
main "$@"
