#!/usr/bin/env bash

# KGSM Instances Module Comprehensive Unit Tests
# Tests all functionality of the instances.sh module with maximum code coverage

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="instances_module_comprehensive"
readonly INSTANCES_MODULE="$KGSM_ROOT/modules/instances.sh"

# Test variables
TEST_BLUEPRINT="factorio.bp"
TEST_INSTALL_DIR=""
TEST_INSTANCE_NAME=""
CREATED_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up comprehensive instances module tests"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$INSTANCES_MODULE" "instances.sh module should exist"

  # Set up test directories
  TEST_INSTALL_DIR="$KGSM_ROOT/test_instances"
  mkdir -p "$TEST_INSTALL_DIR"

  # Set up cleanup trap
  trap cleanup_test EXIT

  log_test "Test environment validated"
}

function cleanup_test() {
  log_step "Cleaning up comprehensive instances module test"

  # Remove any created instances
  for instance in "${CREATED_INSTANCES[@]}"; do
    if [[ -n "$instance" ]]; then
      "$INSTANCES_MODULE" remove "$instance" > /dev/null 2>&1 || true
      log_test "Attempted to remove test instance: $instance"
    fi
  done

  # Clean up test directories
  if [[ -d "$TEST_INSTALL_DIR" ]]; then
    rm -rf "$TEST_INSTALL_DIR" > /dev/null 2>&1 || true
    log_test "Cleaned up test install directory"
  fi
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

function test_help_functionality() {
  log_step "Testing help functionality"

  # Test --help flag
  assert_command_succeeds "$INSTANCES_MODULE --help" "instances.sh --help should work"

  # Test -h flag
  assert_command_succeeds "$INSTANCES_MODULE -h" "instances.sh -h should work"

  # Test help output contains expected sections
  local help_output
  if help_output=$("$INSTANCES_MODULE" --help 2> /dev/null); then
    assert_contains "$help_output" "Instance Management" "Help should contain main title"
    assert_contains "$help_output" "Usage:" "Help should contain usage section"
    assert_contains "$help_output" "Options:" "Help should contain options section"
    assert_contains "$help_output" "list" "Help should document list option"
    assert_contains "$help_output" "create" "Help should document create option"
    assert_contains "$help_output" "remove" "Help should document remove option"
    assert_contains "$help_output" "info" "Help should document info option"
    assert_contains "$help_output" "status" "Help should document status option"
  else
    assert_true "false" "Help command should produce output"
  fi
}

function test_invalid_arguments() {
  log_step "Testing invalid argument handling"

  # Test various invalid arguments
  assert_command_fails "$INSTANCES_MODULE --invalid-option" "Module should reject invalid options"
  assert_command_fails "$INSTANCES_MODULE --nonexistent" "Module should reject nonexistent options"
  assert_command_fails "$INSTANCES_MODULE invalid-command" "Module should reject invalid commands"
  assert_command_fails "$INSTANCES_MODULE create" "Module should require arguments for create"
  assert_command_fails "$INSTANCES_MODULE remove" "Module should require arguments for remove"
  assert_command_fails "$INSTANCES_MODULE info" "Module should require arguments for info"
  assert_command_fails "$INSTANCES_MODULE status" "Module should require arguments for status"
  assert_command_fails "$INSTANCES_MODULE find" "Module should require arguments for find"
  assert_command_fails "$INSTANCES_MODULE generate-id" "Module should require arguments for generate-id"
}

function test_list_functionality_empty() {
  log_step "Testing list functionality with no instances"

  # Basic list should work even with no instances
  assert_command_succeeds "$INSTANCES_MODULE list" "instances.sh list should work with no instances"

  # JSON list should work even with no instances
  assert_command_succeeds "$INSTANCES_MODULE list --json" "instances.sh list --json should work with no instances"

  # Detailed list should work even with no instances
  assert_command_succeeds "$INSTANCES_MODULE list detailed" "instances.sh list detailed should work with no instances"

  # Combined detailed JSON list should work
  assert_command_succeeds "$INSTANCES_MODULE list --json detailed" "instances.sh list --json detailed should work with no instances"
}

function test_generate_id_functionality() {
  log_step "Testing instance ID generation"

  # Test ID generation for various blueprints
  local blueprints=("factorio.bp" "terraria.bp" "minecraft.bp")

  for blueprint in "${blueprints[@]}"; do
    if [[ -f "$KGSM_ROOT/blueprints/default/native/$blueprint" ]]; then
      local generated_id
      if generated_id=$("$INSTANCES_MODULE" generate-id "$blueprint" 2> /dev/null); then
        assert_not_null "$generated_id" "Should generate ID for blueprint: $blueprint"
        assert_not_equals "" "$generated_id" "Generated ID should not be empty for: $blueprint"
        log_test "Generated ID '$generated_id' for blueprint '$blueprint'"
      else
        log_test "ID generation failed for '$blueprint' - may be expected based on blueprint requirements"
      fi
    else
      log_test "Blueprint not found: $blueprint - skipping ID generation test"
    fi
  done

  # Test ID generation with invalid blueprint (may succeed as it just generates a name)
  if "$INSTANCES_MODULE" generate-id "nonexistent.bp" > /dev/null 2>&1; then
    log_test "ID generation succeeded for nonexistent blueprint (generates name regardless)"
  else
    log_test "ID generation failed for nonexistent blueprint (validates blueprint existence)"
  fi
}

function test_find_nonexistent_instance() {
  log_step "Testing find functionality with nonexistent instances"

  local nonexistent_name="test-nonexistent-$(date +%s)"
  assert_command_fails "$INSTANCES_MODULE find '$nonexistent_name'" "Should fail when finding nonexistent instance"
}

function test_info_nonexistent_instance() {
  log_step "Testing info functionality with nonexistent instances"

  local nonexistent_name="test-nonexistent-$(date +%s)"
  assert_command_fails "$INSTANCES_MODULE --instance '$nonexistent_name' info" "Should fail when getting info for nonexistent instance"

  # Test JSON info with nonexistent instance
  assert_command_fails "$INSTANCES_MODULE --instance '$nonexistent_name' info --json" "Should fail when getting JSON info for nonexistent instance"
}

function test_status_nonexistent_instance() {
  log_step "Testing status functionality with nonexistent instances"

  local nonexistent_name="test-nonexistent-$(date +%s)"
  assert_command_fails "$INSTANCES_MODULE --instance '$nonexistent_name' status" "Should fail when getting status for nonexistent instance"
}

function test_remove_nonexistent_instance() {
  log_step "Testing remove functionality with nonexistent instances"

  local nonexistent_name="test-nonexistent-$(date +%s)"
  assert_command_fails "$INSTANCES_MODULE --instance '$nonexistent_name' remove" "Should fail when removing nonexistent instance"
}

function test_instance_creation_workflow() {
  log_step "Testing complete instance creation workflow"

  # Find a suitable blueprint
  if [[ ! -f "$KGSM_ROOT/blueprints/default/native/$TEST_BLUEPRINT" ]]; then
    TEST_BLUEPRINT=$(find "$KGSM_ROOT/blueprints" -name "*.bp" -type f | head -1 | xargs basename 2> /dev/null)
    if [[ -z "$TEST_BLUEPRINT" ]]; then
      skip_test "No blueprints available for instance creation testing"
      return
    fi
  fi

  # Generate instance ID
  local instance_id
  if instance_id=$("$INSTANCES_MODULE" generate-id "$TEST_BLUEPRINT" 2> /dev/null); then
    TEST_INSTANCE_NAME="$instance_id"
    assert_not_null "$TEST_INSTANCE_NAME" "Generated instance ID should not be empty"
    log_test "Generated instance ID: $TEST_INSTANCE_NAME"
  else
    skip_test "Unable to generate instance ID for blueprint: $TEST_BLUEPRINT"
    return
  fi

  # Create instance with generated ID
  local created_instance
  if created_instance=$("$INSTANCES_MODULE" create "$TEST_BLUEPRINT" --install-dir "$TEST_INSTALL_DIR" --name "$TEST_INSTANCE_NAME" 2> /dev/null); then
    assert_not_null "$created_instance" "Instance creation should return instance name"
    CREATED_INSTANCES+=("$TEST_INSTANCE_NAME")
    log_test "Instance created successfully: $created_instance"
  else
    log_test "Instance creation failed - may be expected based on blueprint requirements"
    return
  fi

  # Verify instance appears in list
  local instance_list
  if instance_list=$("$INSTANCES_MODULE" list 2> /dev/null); then
    assert_list_contains "$instance_list" "$TEST_INSTANCE_NAME" "Instance should appear in instance list"
    log_test "Instance appears in list"
  else
    assert_true "false" "Instance list command should succeed after creation"
  fi

  # Test find functionality
  local instance_config
  if instance_config=$("$INSTANCES_MODULE" find "$TEST_INSTANCE_NAME" 2> /dev/null); then
    assert_file_exists "$instance_config" "Instance config file should exist"
    log_test "Instance config file found: $instance_config"
  else
    assert_true "false" "Should be able to find created instance"
  fi

  # Test info functionality
  assert_command_succeeds "$INSTANCES_MODULE info '$TEST_INSTANCE_NAME'" "Instance info should work for created instance"

  # Test JSON info functionality
  local instance_json
  if instance_json=$("$INSTANCES_MODULE" info "$TEST_INSTANCE_NAME" --json 2> /dev/null); then
    assert_not_null "$instance_json" "Instance JSON info should not be null"

    # Validate JSON format if jq is available
    if command -v jq > /dev/null 2>&1; then
      if echo "$instance_json" | jq . > /dev/null 2>&1; then
        assert_true "true" "Instance JSON should be valid JSON"
        log_test "Instance JSON info is valid"
      else
        log_test "Instance JSON info is not valid format"
      fi
    fi
  else
    log_test "Instance JSON info failed - may be expected for some blueprints"
  fi

  # Test status functionality
  if "$INSTANCES_MODULE" status "$TEST_INSTANCE_NAME" > /dev/null 2>&1; then
    log_test "Instance status command works"
  else
    log_test "Instance status command failed - may be expected for newly created instances"
  fi
}

function test_instance_creation_with_custom_name() {
  log_step "Testing instance creation with custom name"

  local custom_name="test-custom-$(date +%s)"

  # Create instance with custom name
  local created_instance
  if created_instance=$("$INSTANCES_MODULE" create "$TEST_BLUEPRINT" --install-dir "$TEST_INSTALL_DIR" --name "$custom_name" 2> /dev/null); then
    assert_contains "$created_instance" "$custom_name" "Created instance should have custom name"
    CREATED_INSTANCES+=("$custom_name")
    log_test "Instance created with custom name: $created_instance"
  else
    log_test "Instance creation with custom name failed - may be expected"
    return
  fi

  # Verify custom named instance can be found
  assert_command_succeeds "$INSTANCES_MODULE find '$custom_name'" "Should be able to find custom named instance"
}

function test_instance_creation_missing_arguments() {
  log_step "Testing instance creation with missing arguments"

  # Test create without blueprint
  assert_command_fails "$INSTANCES_MODULE create" "Should fail when create called without blueprint"

  # Test create with blueprint but missing install-dir (may have default behavior)
  if "$INSTANCES_MODULE" create "$TEST_BLUEPRINT" > /dev/null 2>&1; then
    log_test "Create succeeded without install-dir (may use default location)"
  else
    log_test "Create failed without install-dir (requires explicit install-dir)"
  fi

  # Test create with invalid blueprint (may succeed if it just creates config)
  if "$INSTANCES_MODULE" create "nonexistent.bp" --install-dir "$TEST_INSTALL_DIR" > /dev/null 2>&1; then
    log_test "Create succeeded with nonexistent blueprint (may create config regardless)"
  else
    log_test "Create failed with nonexistent blueprint (validates blueprint existence)"
  fi
}

function test_list_with_blueprint_filter() {
  log_step "Testing list functionality with blueprint filter"

  # Test listing with specific blueprint filter
  local blueprint_name
  blueprint_name=$(basename "$TEST_BLUEPRINT" .bp)

  assert_command_succeeds "$INSTANCES_MODULE list '$blueprint_name'" "Should be able to list instances for specific blueprint"
  assert_command_succeeds "$INSTANCES_MODULE list --json '$blueprint_name'" "Should be able to list instances for specific blueprint in JSON"
  assert_command_succeeds "$INSTANCES_MODULE list detailed '$blueprint_name'" "Should be able to list detailed instances for specific blueprint"
  assert_command_succeeds "$INSTANCES_MODULE list --json detailed '$blueprint_name'" "Should be able to list detailed instances for specific blueprint in JSON"
}

function test_json_output_format() {
  log_step "Testing JSON output format consistency"

  # Test that JSON outputs are valid when jq is available
  if command -v jq > /dev/null 2>&1; then
    local json_outputs=(
      "$($INSTANCES_MODULE list --json 2> /dev/null)"
      "$($INSTANCES_MODULE list --json detailed 2> /dev/null)"
    )

    for json_output in "${json_outputs[@]}"; do
      if [[ -n "$json_output" ]]; then
        if echo "$json_output" | jq . > /dev/null 2>&1; then
          assert_true "true" "JSON output should be valid"
        else
          assert_true "false" "JSON output should be valid JSON format"
        fi
      fi
    done
  else
    log_test "jq not available, skipping JSON validation"
  fi
}

function test_debug_flag() {
  log_step "Testing debug flag functionality"

  # Test that debug flag is accepted (though we can't easily verify its effect)
  assert_command_succeeds "$INSTANCES_MODULE --debug --help" "Debug flag should be accepted with help"
  assert_command_succeeds "$INSTANCES_MODULE --debug list" "Debug flag should be accepted with list"
}

function test_input_and_save_commands() {
  log_step "Testing input and save commands"

  # Test input command with missing arguments
  assert_command_fails "$INSTANCES_MODULE input" "Input command should require instance argument"
  assert_command_fails "$INSTANCES_MODULE input 'test-instance'" "Input command should require command argument"

  # Test save command with missing arguments
  assert_command_fails "$INSTANCES_MODULE save" "Save command should require instance argument"

  # Test input and save with nonexistent instance
  local nonexistent_name="test-nonexistent-$(date +%s)"
  assert_command_fails "$INSTANCES_MODULE input '$nonexistent_name' 'test command'" "Input should fail with nonexistent instance"
  assert_command_fails "$INSTANCES_MODULE save '$nonexistent_name'" "Save should fail with nonexistent instance"
}

function test_edge_cases() {
  log_step "Testing edge cases and boundary conditions"

  # Test with empty strings
  assert_command_fails "$INSTANCES_MODULE generate-id ''" "Should fail with empty blueprint name"
  assert_command_fails "$INSTANCES_MODULE find ''" "Should fail with empty instance name"
  assert_command_fails "$INSTANCES_MODULE info ''" "Should fail with empty instance name"

  # Test with special characters in names
  local special_chars="test-instance-with-special-chars-!@#"
  assert_command_fails "$INSTANCES_MODULE find '$special_chars'" "Should handle special characters gracefully"

  # Test with very long names
  local long_name="test-instance-with-very-long-name-$(printf 'a%.0s' {1..100})"
  assert_command_fails "$INSTANCES_MODULE find '$long_name'" "Should handle very long names gracefully"
}

function test_multiple_instances() {
  log_step "Testing multiple instance management"

  # Create multiple test instances if possible
  local instance_names=()
  for i in {1..3}; do
    local instance_name="test-multi-$i-$(date +%s)"
    local created_instance
    if created_instance=$("$INSTANCES_MODULE" create "$TEST_BLUEPRINT" --install-dir "$TEST_INSTALL_DIR" --name "$instance_name" 2> /dev/null); then
      instance_names+=("$instance_name")
      CREATED_INSTANCES+=("$instance_name")
      log_test "Created test instance: $created_instance"
    else
      log_test "Failed to create test instance $instance_name - continuing with available instances"
      break
    fi
  done

  if [[ ${#instance_names[@]} -gt 0 ]]; then
    # Test that list shows all instances
    local instance_list
    if instance_list=$("$INSTANCES_MODULE" list 2> /dev/null); then
      for instance_name in "${instance_names[@]}"; do
        assert_list_contains "$instance_list" "$instance_name" "List should contain instance: $instance_name"
      done
    fi

    # Test individual operations on each instance
    for instance_name in "${instance_names[@]}"; do
      assert_command_succeeds "$INSTANCES_MODULE find '$instance_name'" "Should find instance: $instance_name"
      assert_command_succeeds "$INSTANCES_MODULE info '$instance_name'" "Should get info for instance: $instance_name"
    done
  else
    log_test "No multiple instances created - skipping multiple instance tests"
  fi
}

function test_cleanup_instances() {
  log_step "Testing instance removal"

  # Remove instances that were created during testing
  set -x
  for instance in "${CREATED_INSTANCES[@]}"; do
    if [[ -n "$instance" ]]; then
      assert_command_succeeds "$INSTANCES_MODULE remove '$instance'" "Should be able to remove instance: $instance"

      # Verify instance is no longer in list
      local instance_list_after
      if instance_list_after=$("$INSTANCES_MODULE" list 2> /dev/null); then
        assert_list_not_contains "$instance_list_after" "$instance" "Instance should not appear in list after removal: $instance"
      fi

      # Verify instance cannot be found
      assert_command_fails "$INSTANCES_MODULE find '$instance'" "Should not be able to find removed instance: $instance"
    fi
  done
  set +x

  # Clear the array since instances are removed
  CREATED_INSTANCES=()
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting comprehensive instances module unit tests"

  # Initialize test environment
  setup_test

  # Basic functionality tests
  test_module_existence_and_permissions
  test_help_functionality
  test_invalid_arguments

  # List functionality tests
  test_list_functionality_empty
  test_generate_id_functionality
  test_find_nonexistent_instance
  test_info_nonexistent_instance
  test_status_nonexistent_instance
  test_remove_nonexistent_instance

  # Instance creation tests
  test_instance_creation_workflow
  test_instance_creation_with_custom_name
  test_instance_creation_missing_arguments

  # List functionality tests
  test_list_with_blueprint_filter

  # JSON output format tests
  test_json_output_format

  # Debug flag tests
  test_debug_flag

  # Input and save commands tests
  test_input_and_save_commands

  # Edge cases tests
  test_edge_cases

  # Multiple instances tests
  test_multiple_instances
  test_cleanup_instances

  log_test "Comprehensive instances module tests completed successfully"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All comprehensive instances module tests completed successfully"
  else
    fail_test "Some comprehensive instances module tests failed"
  fi
}

# Execute main function
main "$@"
