#!/usr/bin/env bash

# KGSM Module Discovery Integration Test
# Tests the discovery and loading of KGSM modules

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="module_discovery"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up module discovery integration test"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "Test environment validated"
}

function test_modules_directory_existence() {
  log_step "Testing modules directory existence"

  assert_dir_exists "$KGSM_ROOT/modules" "modules directory should exist"
}

function test_core_modules_existence() {
  log_step "Testing core module existence"

  local core_modules=("instances.sh" "blueprints.sh" "lifecycle.sh" "files.sh")

  for module in "${core_modules[@]}"; do
    local module_path="$KGSM_ROOT/commands/$module"
    assert_file_exists "$module_path" "Core module should exist: $module"

    # Check if module is executable
    if [[ -x "$module_path" ]]; then
      assert_true "true" "Core module should be executable: $module"
    else
      assert_true "false" "Core module should be executable: $module"
    fi
  done
}

function test_include_modules_existence() {
  log_step "Testing include module existence"

  assert_dir_exists "$KGSM_ROOT/lib" "$KGSM_ROOT/lib directory should exist"

  local include_modules=("common.sh" "config.sh" "errors.sh" "logging.sh")

  for module in "${include_modules[@]}"; do
    local module_path="$KGSM_ROOT/core/$module"
    assert_file_exists "$module_path" "Include module should exist: $module"
  done
}

function test_module_count() {
  log_step "Testing module count"

  local total_modules
  total_modules=$(find "$KGSM_ROOT/modules" -name "*.sh" -type f 2>/dev/null | wc -l)

  assert_greater_than "$total_modules" 10 "Should have more than 10 modules total"
  log_test "Found $total_modules modules total"
}

function test_module_help_functionality() {
  log_step "Testing module help functionality"

  local testable_modules=("instances.sh" "blueprints.sh" "lifecycle.sh")

  for module in "${testable_modules[@]}"; do
    local module_path="$KGSM_ROOT/commands/$module"
    assert_command_succeeds "$module_path --help" "$module --help should work"
  done
}

function test_module_dependencies() {
  log_step "Testing module dependencies"

  # Test that common dependencies are available
  assert_file_exists "$KGSM_ROOT/core/common.sh" "Common module should be available for dependencies"
  assert_file_exists "$KGSM_ROOT/core/config.sh" "Config module should be available for dependencies"
  assert_file_exists "$KGSM_ROOT/core/logging.sh" "Logging module should be available for dependencies"
  assert_file_exists "$KGSM_ROOT/core/errors.sh" "Errors module should be available for dependencies"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting module discovery integration test"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_modules_directory_existence
  test_core_modules_existence
  test_include_modules_existence
  test_module_count
  test_module_help_functionality
  test_module_dependencies

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All module discovery integration tests completed successfully"
  else
    fail_test "Some module discovery integration tests failed"
  fi
}

# Execute main function
main "$@"
