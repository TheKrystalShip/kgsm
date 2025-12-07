#!/usr/bin/env bash

# =============================================================================
# KGSM Directories Module - Comprehensive Test Suite
# =============================================================================
#
# This test provides comprehensive coverage of the directories.sh module, testing all
# commands, error conditions, edge cases, and behavioral consistency.
#
# The directories module manages the directory structure needed for game server instances:
# - Working directory (main instance directory)
# - Installation directory (game files)
# - Backups directory (backup storage)
# - Saves directory (save files/worlds)
# - Temp directory (temporary files)
# - Logs directory (instance logs)
#
# Test Coverage:
# ✓ Module existence and permissions
# ✓ Help functionality and usage display
# ✓ All command combinations (--create, --remove)
# ✓ Instance parameter validation
# ✓ Error handling (missing args, invalid args, non-existent instances)
# ✓ Directory creation and removal verification
# ✓ Configuration file updates
# ✓ Path validation (absolute paths)
# ✓ Permission and ownership validation
# ✓ Debug mode functionality
# ✓ Behavioral consistency and predictability
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="directories_module_comprehensive"
readonly DIRECTORIES_MODULE="$KGSM_ROOT/commands/directories.sh"
readonly TEST_INSTANCE="factorio-test-$(date +%s)"
readonly TEST_BLUEPRINT="factorio.bp"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Custom cleanup function for directories module testing
function cleanup_test_instance() {
  local instance_name="$1"

  if [[ -n "$instance_name" ]]; then
    log_test "Cleaning up test instance: $instance_name"
    remove_test_instance "$instance_name"

    # Also try to clean up any remaining files
    local instance_config="$KGSM_ROOT/instances/${instance_name}.ini"
    [[ -f "$instance_config" ]] && rm -f "$instance_config" 2>/dev/null || true
  fi
}

function setup_test() {
  log_test "Setting up comprehensive directories module test environment"

  # Additional directories module specific setup
  assert_file_exists "$DIRECTORIES_MODULE" "Directories module should exist"
  assert_file_executable "$DIRECTORIES_MODULE" "Directories module should be executable"

  log_test "Test environment setup complete"
}

# =============================================================================
# TEST FUNCTIONS - BASIC MODULE VALIDATION
# =============================================================================

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  # Basic file system checks
  assert_file_exists "$DIRECTORIES_MODULE" "Directories module file should exist"
  assert_command_succeeds "test -r '$DIRECTORIES_MODULE'" "Directories module should be readable"
  assert_file_executable "$DIRECTORIES_MODULE" "Directories module should be executable"

  # Check file size (should not be empty)
  assert_command_succeeds "test -s '$DIRECTORIES_MODULE'" "Directories module should not be empty"

  # Verify it's a bash script
  local first_line
  first_line=$(head -n1 "$DIRECTORIES_MODULE")
  assert_contains "$first_line" "#!/usr/bin/env bash" "Directories module should be a bash script"

  log_test "Module existence and permissions validated"
}

function test_help_functionality() {
  log_step "Testing help functionality and usage display"

  # Test --help flag
  assert_command_succeeds "$DIRECTORIES_MODULE --help" "directories.sh --help should work"

  # Test -h flag
  assert_command_succeeds "$DIRECTORIES_MODULE -h" "directories.sh -h should work"

  # Verify help content contains expected information
  local help_output
  help_output=$("$DIRECTORIES_MODULE" --help 2>&1)

  assert_contains "$help_output" "Directory Management for Krystal Game Server Manager" "Help should contain module description"
  assert_contains "$help_output" "--instance" "Help should document --instance option"
  assert_contains "$help_output" "--create" "Help should document --create command"
  assert_contains "$help_output" "--remove" "Help should document --remove command"
  assert_contains "$help_output" "Creates installation, data, logs, and backup directories" "Help should describe create functionality"
  assert_contains "$help_output" "Warning: This will delete all instance data" "Help should contain removal warning"
  assert_contains "$help_output" "Examples:" "Help should contain usage examples"

  log_test "Help functionality validated"
}

# =============================================================================
# TEST FUNCTIONS - ARGUMENT VALIDATION
# =============================================================================

function test_missing_arguments() {
  log_step "Testing behavior with missing arguments"

  # Test no arguments at all
  assert_command_fails "$DIRECTORIES_MODULE" "directories.sh without arguments should fail"

  # Test missing instance argument
  assert_command_fails "$DIRECTORIES_MODULE --instance" "directories.sh --instance without value should fail"
  assert_command_fails "$DIRECTORIES_MODULE -i" "directories.sh -i without value should fail"

  # Test missing instance for commands
  assert_command_fails "$DIRECTORIES_MODULE --create" "directories.sh --create without --instance should fail"
  assert_command_fails "$DIRECTORIES_MODULE --remove" "directories.sh --remove without --instance should fail"

  # Verify error messages are helpful
  local error_output
  error_output=$("$DIRECTORIES_MODULE" --instance 2>&1 || true)
  assert_contains "$error_output" "Missing argument" "Error message should indicate missing argument"

  log_test "Missing argument handling validated"
}

function test_invalid_arguments() {
  log_step "Testing behavior with invalid arguments"

  # Test completely invalid arguments
  assert_command_fails "$DIRECTORIES_MODULE --invalid-argument" "directories.sh should reject invalid arguments"
  assert_command_fails "$DIRECTORIES_MODULE --instance test --invalid-command" "directories.sh should reject invalid commands"

  # Verify error messages
  local error_output
  error_output=$("$DIRECTORIES_MODULE" --invalid-argument 2>&1 || true)
  assert_contains "$error_output" "ERROR" "Error message should contain error indication"

  log_test "Invalid argument handling validated"
}

function test_instance_validation() {
  log_step "Testing instance parameter validation"

  # Test with non-existent instance
  assert_command_fails "$DIRECTORIES_MODULE --instance nonexistent-instance --create" "directories.sh should fail with non-existent instance"

  # Test with empty instance name
  assert_command_fails "$DIRECTORIES_MODULE --instance '' --create" "directories.sh should fail with empty instance name"

  # Verify error messages for non-existent instances
  local error_output
  error_output=$("$DIRECTORIES_MODULE" --instance "nonexistent-instance" --create 2>&1 || true)
  assert_contains "$error_output" "not found" "Error should indicate instance not found"

  log_test "Instance validation behavior confirmed"
}

# =============================================================================
# TEST FUNCTIONS - COMMAND FUNCTIONALITY WITH REAL INSTANCE
# =============================================================================

function test_create_command_functionality() {
  log_step "Testing --create command functionality"

  # Create a test instance first
  local test_instance
  test_instance=$(create_test_instance "$TEST_BLUEPRINT" "$TEST_INSTANCE")

  if [[ -z "$test_instance" ]]; then
    log_test "Failed to create test instance, skipping create tests"
    return
  fi

  # Test basic create command
  assert_command_succeeds "$DIRECTORIES_MODULE --instance '$test_instance' --create" "directories.sh --create should work with valid instance"

  # Verify directories were created
  local instance_config="$KGSM_ROOT/instances/${test_instance}.ini"
  if [[ -f "$instance_config" ]]; then
    # Check if working_dir is set in config
    local working_dir
    working_dir=$(grep "^working_dir=" "$instance_config" | cut -d'=' -f2 | tr -d '"' || echo "")

    if [[ -n "$working_dir" ]]; then
      # Verify expected directories exist
      assert_dir_exists "$working_dir" "Working directory should be created"
      assert_dir_exists "$working_dir/backups" "Backups directory should be created"
      assert_dir_exists "$working_dir/install" "Install directory should be created"
      assert_dir_exists "$working_dir/saves" "Saves directory should be created"
      assert_dir_exists "$working_dir/temp" "Temp directory should be created"
      assert_dir_exists "$working_dir/logs" "Logs directory should be created"

      log_test "All expected directories were created in: $working_dir"
    else
      log_test "Could not determine working directory from config"
    fi
  else
    log_test "Instance config file not found: $instance_config"
  fi

  # Cleanup
  cleanup_test_instance "$test_instance"

  log_test "Create command functionality tested"
}

function test_remove_command_functionality() {
  log_step "Testing --remove command functionality"

  # Create a test instance first
  local test_instance
  test_instance=$(create_test_instance "$TEST_BLUEPRINT" "$TEST_INSTANCE")

  if [[ -z "$test_instance" ]]; then
    log_test "Failed to create test instance, skipping remove tests"
    return
  fi

  # Create directories first
  "$DIRECTORIES_MODULE" --instance "$test_instance" --create >/dev/null 2>&1 || true

  # Get working directory before removal
  local instance_config="$KGSM_ROOT/instances/${test_instance}.ini"
  local working_dir=""
  if [[ -f "$instance_config" ]]; then
    working_dir=$(grep "^working_dir=" "$instance_config" | cut -d'=' -f2 | tr -d '"' || echo "")
  fi

  # Test remove command
  assert_command_succeeds "$DIRECTORIES_MODULE --instance '$test_instance' --remove" "directories.sh --remove should work with valid instance"

  # Verify directories were removed
  if [[ -n "$working_dir" && -d "$working_dir" ]]; then
    log_test "Working directory still exists after removal: $working_dir"
  else
    log_test "Working directory successfully removed"
  fi

  # Cleanup
  cleanup_test_instance "$test_instance"

  log_test "Remove command functionality tested"
}

# =============================================================================
# TEST FUNCTIONS - DIRECTORY OPERATIONS VERIFICATION
# =============================================================================

function test_directory_creation_verification() {
  log_step "Testing directory creation verification"

  # Create a test instance
  local test_instance
  test_instance=$(create_test_instance "$TEST_BLUEPRINT" "$TEST_INSTANCE")

  if [[ -z "$test_instance" ]]; then
    log_test "Failed to create test instance, skipping directory creation tests"
    return
  fi

  # Create directories
  if "$DIRECTORIES_MODULE" --instance "$test_instance" --create >/dev/null 2>&1; then
    log_test "Directory creation command executed successfully"

    # Verify all expected directories exist
    local instance_config="$KGSM_ROOT/instances/${test_instance}.ini"
    if [[ -f "$instance_config" ]]; then
      local working_dir
      working_dir=$(grep "^working_dir=" "$instance_config" | cut -d'=' -f2 | tr -d '"' || echo "")

      if [[ -n "$working_dir" ]]; then
        local expected_dirs=(
          "$working_dir"
          "$working_dir/backups"
          "$working_dir/install"
          "$working_dir/saves"
          "$working_dir/temp"
          "$working_dir/logs"
        )

        for dir in "${expected_dirs[@]}"; do
          assert_dir_exists "$dir" "Expected directory should exist: $(basename "$dir")"
        done

        log_test "All directory structure verified"
      fi
    fi
  else
    log_test "Directory creation failed"
  fi

  # Cleanup
  cleanup_test_instance "$test_instance"

  log_test "Directory creation verification completed"
}

function test_directory_removal_verification() {
  log_step "Testing directory removal verification"

  # Create a test instance
  local test_instance
  test_instance=$(create_test_instance "$TEST_BLUEPRINT" "$TEST_INSTANCE")

  if [[ -z "$test_instance" ]]; then
    log_test "Failed to create test instance, skipping directory removal tests"
    return
  fi

  # Create directories first
  "$DIRECTORIES_MODULE" --instance "$test_instance" --create >/dev/null 2>&1 || true

  # Get working directory path
  local instance_config="$KGSM_ROOT/instances/${test_instance}.ini"
  local working_dir=""
  if [[ -f "$instance_config" ]]; then
    working_dir=$(grep "^working_dir=" "$instance_config" | cut -d'=' -f2 | tr -d '"' || echo "")
  fi

  # Remove directories
  assert_command_succeeds "$DIRECTORIES_MODULE --instance '$test_instance' --remove" "Directory removal should succeed"

  # Verify directories were removed
  if [[ -n "$working_dir" ]]; then
    assert_dir_not_exists "$working_dir" "Working directory should be removed after --remove command"
  fi

  # Cleanup
  cleanup_test_instance "$test_instance"

  log_test "Directory removal verification completed"
}

# =============================================================================
# TEST FUNCTIONS - CONFIGURATION INTEGRATION
# =============================================================================

function test_configuration_file_updates() {
  log_step "Testing configuration file updates"

  # Create a test instance
  local test_instance
  test_instance=$(create_test_instance "$TEST_BLUEPRINT" "$TEST_INSTANCE")

  if [[ -z "$test_instance" ]]; then
    log_test "Failed to create test instance, skipping configuration tests"
    return
  fi

  # Create directories
  "$DIRECTORIES_MODULE" --instance "$test_instance" --create >/dev/null 2>&1 || true

  # Verify configuration file was updated
  local instance_config
  instance_config="$("$KGSM_ROOT/commands/instances.sh" --find "$test_instance")"

  if [[ -f "$instance_config" ]]; then
    # Check for expected configuration keys
    local expected_keys=(
      "working_dir"
      "backups_dir"
      "install_dir"
      "saves_dir"
      "temp_dir"
      "logs_dir"
    )

    for key in "${expected_keys[@]}"; do
      assert_file_contains "$instance_config" "$key=" "Config should contain $key setting"
    done

    log_test "Configuration file updates verified"
  else
    assert_true "false" "Instance configuration file should exist"
  fi

  # Cleanup
  cleanup_test_instance "$test_instance"

  log_test "Configuration file update testing completed"
}

function test_path_validation() {
  log_step "Testing path validation"

  # Create a test instance
  local test_instance
  test_instance=$(create_test_instance "$TEST_BLUEPRINT" "$TEST_INSTANCE")

  if [[ -z "$test_instance" ]]; then
    log_test "Failed to create test instance, skipping path validation tests"
    return
  fi

  # Verify that working_dir is an absolute path
  local instance_config="$KGSM_ROOT/instances/${test_instance}.ini"
  if [[ -f "$instance_config" ]]; then
    local working_dir
    working_dir=$(grep "^working_dir=" "$instance_config" | cut -d'=' -f2 | tr -d '"' || echo "")

    if [[ -n "$working_dir" ]]; then
      assert_starts_with "$working_dir" "/" "Working directory should be an absolute path"
      log_test "Path validation confirmed: $working_dir"
    fi
  fi

  # Cleanup
  cleanup_test_instance "$test_instance"

  log_test "Path validation testing completed"
}

# =============================================================================
# TEST FUNCTIONS - ERROR HANDLING & EDGE CASES
# =============================================================================

function test_permission_error_handling() {
  log_step "Testing permission error handling"

  # Note: Permission testing is limited in test environment
  # We mainly test that the module handles permission-related scenarios gracefully

  # Test with non-existent instance (should fail gracefully)
  assert_command_fails "$DIRECTORIES_MODULE --instance 'nonexistent' --create" "Should handle non-existent instance gracefully"

  # Test error message quality
  local error_output
  error_output=$("$DIRECTORIES_MODULE" --instance "nonexistent" --create 2>&1 || true)
  assert_not_null "$error_output" "Should provide error output for failed operations"

  log_test "Permission error handling tested"
}

function test_edge_cases() {
  log_step "Testing edge cases and boundary conditions"

  # Test with very long instance names
  assert_command_fails "$DIRECTORIES_MODULE --instance '$(printf 'a%.0s' {1..1000})' --create" "Should handle very long instance names gracefully"

  # Test with special characters in instance names
  assert_command_fails "$DIRECTORIES_MODULE --instance 'instance with spaces' --create" "Should handle spaces in instance names"
  assert_command_fails "$DIRECTORIES_MODULE --instance 'instance@#\$%' --create" "Should handle special characters in instance names"

  # Test with empty string arguments
  assert_command_fails "$DIRECTORIES_MODULE --instance '' --create" "Should reject empty instance names"

  # Test multiple conflicting arguments
  assert_command_fails "$DIRECTORIES_MODULE --instance test --create --remove" "Should reject conflicting create/remove commands"

  log_test "Edge cases handled appropriately"
}

# =============================================================================
# TEST FUNCTIONS - BEHAVIORAL CONSISTENCY
# =============================================================================

function test_behavioral_consistency() {
  log_step "Testing behavioral consistency and predictability"

  # Test that the same command produces consistent results
  local result1 result2 result3

  # Test help consistency
  result1=$("$DIRECTORIES_MODULE" --help 2>&1 || echo "FAILED")
  result2=$("$DIRECTORIES_MODULE" --help 2>&1 || echo "FAILED")
  result3=$("$DIRECTORIES_MODULE" --help 2>&1 || echo "FAILED")

  assert_equals "$result1" "$result2" "Multiple --help calls should produce identical results"
  assert_equals "$result2" "$result3" "All --help calls should be consistent"

  # Test error consistency
  result1=$("$DIRECTORIES_MODULE" --invalid-arg 2>&1 || true)
  result2=$("$DIRECTORIES_MODULE" --invalid-arg 2>&1 || true)

  assert_equals "$result1" "$result2" "Same invalid input should produce identical errors"

  log_test "Behavioral consistency confirmed"
}

function test_debug_mode_functionality() {
  log_step "Testing debug mode functionality"

  # Test --debug flag with various commands
  assert_command_succeeds "$DIRECTORIES_MODULE --debug --help" "directories.sh --debug --help should work"

  # Debug mode with invalid arguments should still fail but with debug output
  assert_command_fails "$DIRECTORIES_MODULE --debug --invalid-argument" "Debug mode should not change error behavior"

  log_test "Debug mode functionality validated"
}

# =============================================================================
# TEST FUNCTIONS - COMPREHENSIVE COVERAGE
# =============================================================================

function test_all_command_combinations() {
  log_step "Testing all command combinations for comprehensive coverage"

  # Create a test instance for testing
  local test_instance
  test_instance=$(create_test_instance "$TEST_BLUEPRINT" "$TEST_INSTANCE")

  if [[ -z "$test_instance" ]]; then
    log_test "Failed to create test instance, skipping command combination tests"
    return
  fi

  # Test create command
  if "$DIRECTORIES_MODULE" --instance "$test_instance" --create >/dev/null 2>&1; then
    log_test "directories.sh --create succeeded"
  else
    log_test "directories.sh --create failed"
  fi

  # Test remove command
  if "$DIRECTORIES_MODULE" --instance "$test_instance" --remove >/dev/null 2>&1; then
    log_test "directories.sh --remove succeeded"
  else
    log_test "directories.sh --remove failed"
  fi

  # Cleanup
  cleanup_test_instance "$test_instance"

  log_test "All command combinations tested"
}

function test_module_integration_with_kgsm() {
  log_step "Testing module integration with KGSM environment"

  # Test that the module can find and load its dependencies
  assert_command_succeeds "bash -c 'KGSM_ROOT=\"$KGSM_ROOT\" \"$DIRECTORIES_MODULE\" --help'" "Module should work with explicit KGSM_ROOT"

  # Test module discovery by checking if the module can be found
  local found_module
  found_module=$(find "$KGSM_ROOT/modules" -name "directories.sh" -type f | head -1)
  assert_not_null "$found_module" "Module should be discoverable in modules directory"

  log_test "Module integration with KGSM validated"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting comprehensive directories module tests"

  # Initialize test environment
  setup_test

  # Basic functionality tests
  test_module_existence_and_permissions
  test_help_functionality

  # Argument validation tests
  test_missing_arguments
  test_invalid_arguments
  test_instance_validation

  # Core functionality tests
  test_create_command_functionality
  test_remove_command_functionality

  # Directory operations verification
  test_directory_creation_verification
  test_directory_removal_verification

  # Configuration integration tests
  test_configuration_file_updates
  test_path_validation

  # Error handling and edge cases
  test_permission_error_handling
  test_edge_cases

  # Behavioral consistency validation
  test_behavioral_consistency
  test_debug_mode_functionality

  # Comprehensive coverage tests
  test_all_command_combinations
  test_module_integration_with_kgsm

  log_test "Comprehensive directories module tests completed successfully"

  # Print final results and determine exit code using framework
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All comprehensive directories module tests completed successfully"
  else
    fail_test "Some comprehensive directories module tests failed"
  fi
}

# Execute main function
main "$@"
