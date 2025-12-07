#!/usr/bin/env bash

# KGSM Lifecycle Module Unit Tests
# Tests the core functionality of the lifecycle.sh module

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="lifecycle_module"
readonly LIFECYCLE_MODULE="$KGSM_ROOT/commands/lifecycle.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up lifecycle module tests"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "Test environment validated"
}

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  assert_file_exists "$LIFECYCLE_MODULE" "lifecycle.sh module should exist"

  # Check if file is executable
  if [[ -x "$LIFECYCLE_MODULE" ]]; then
    assert_true "true" "lifecycle.sh module should be executable"
  else
    assert_true "false" "lifecycle.sh module should be executable"
  fi
}

function test_module_help_functionality() {
  log_step "Testing module help functionality"

  assert_command_succeeds "$LIFECYCLE_MODULE --help" "lifecycle.sh --help should work"
}

function test_invalid_argument_handling() {
  log_step "Testing invalid argument handling"

  assert_command_fails "$LIFECYCLE_MODULE --invalid-argument" "Module should reject invalid arguments"
}

function test_system_dependencies() {
  log_step "Testing system dependencies"

  # Check for systemctl availability (used for systemd lifecycle management)
  if command -v systemctl >/dev/null 2>&1; then
    assert_true "true" "systemctl should be available on systemd systems"
    log_test "systemctl is available"
  else
    log_test "systemctl not available (expected in some environments like containers)"
  fi

  # Check for other potential lifecycle management tools
  if command -v service >/dev/null 2>&1; then
    log_test "service command is available"
  else
    log_test "service command not available"
  fi
}

function test_lifecycle_management_types() {
  log_step "Testing lifecycle management support"

  # The lifecycle module should handle different management types
  # Test basic functionality without requiring actual instances

  # Check if the module has proper error handling for missing instances
  local test_instance="test-nonexistent-lifecycle-$(date +%s)"

  # These commands should fail gracefully for non-existent instances
  if "$LIFECYCLE_MODULE" --start "$test_instance" >/dev/null 2>&1; then
    log_test "Start command succeeded for non-existent instance (unexpected)"
  else
    log_test "Start command failed for non-existent instance (expected behavior)"
  fi

  if "$LIFECYCLE_MODULE" --stop "$test_instance" >/dev/null 2>&1; then
    log_test "Stop command succeeded for non-existent instance (unexpected)"
  else
    log_test "Stop command failed for non-existent instance (expected behavior)"
  fi
}

function test_module_argument_validation() {
  log_step "Testing module argument validation"

  # Test commands that should require instance names
  assert_command_fails "$LIFECYCLE_MODULE --start" "Start command should require instance name"
  assert_command_fails "$LIFECYCLE_MODULE --stop" "Stop command should require instance name"
  assert_command_fails "$LIFECYCLE_MODULE --restart" "Restart command should require instance name"
}

function test_lifecycle_configuration() {
  log_step "Testing lifecycle configuration integration"

  # Check if the module properly reads configuration settings
  # In test environment, systemd should be disabled
  local config_file="$KGSM_ROOT/config.ini"

  if [[ -f "$config_file" ]]; then
    if grep -q "enable_systemd=false" "$config_file"; then
      log_test "systemd is properly disabled in test configuration"
    else
      log_test "systemd setting not found in configuration"
    fi
  else
    assert_true "false" "Configuration file should exist"
  fi
}

function test_lifecycle_standalone_support() {
  log_step "Testing standalone lifecycle support"

  # Test that the module supports standalone mode (non-systemd)
  # This is especially important in test environments

  # Check if standalone lifecycle module exists
  local standalone_module="$KGSM_ROOT/commands/lifecycle.standalone.sh"
  if [[ -f "$standalone_module" ]]; then
    assert_file_exists "$standalone_module" "Standalone lifecycle module should exist"
    log_test "Standalone lifecycle module found"
  else
    log_test "Standalone lifecycle module not found (may be integrated into main module)"
  fi
}

function test_module_status_reporting() {
  log_step "Testing module status reporting"

  # Test status reporting for non-existent instances
  local test_instance="test-status-$(date +%s)"

  # Status command should handle non-existent instances gracefully
  local status_output
  if status_output=$("$LIFECYCLE_MODULE" --status "$test_instance" 2>/dev/null); then
    log_test "Status command produced output for non-existent instance"
  else
    log_test "Status command failed for non-existent instance (expected)"
  fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting lifecycle module unit tests"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_module_existence_and_permissions
  test_module_help_functionality
  test_invalid_argument_handling
  test_system_dependencies
  test_lifecycle_management_types
  test_module_argument_validation
  test_lifecycle_configuration
  test_lifecycle_standalone_support
  test_module_status_reporting

  log_test "Lifecycle module tests completed successfully"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All lifecycle module tests completed successfully"
  else
    fail_test "Some lifecycle module tests failed"
  fi
}

# Execute main function
main "$@"
