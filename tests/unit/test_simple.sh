#!/usr/bin/env bash

# Simple KGSM Test - Unit Test Example
# This test demonstrates the framework working with basic KGSM functionality

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="simple"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up simple unit test"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "Test environment validated"
}

function test_kgsm_main_script() {
  log_step "Testing main KGSM script existence"

  local kgsm_script="$KGSM_ROOT/kgsm.sh"
  assert_file_exists "$kgsm_script" "kgsm.sh should exist"

  # Check if file is executable
  if [[ -x "$kgsm_script" ]]; then
    assert_true "true" "kgsm.sh should be executable"
  else
    assert_true "false" "kgsm.sh should be executable"
  fi
}

function test_instances_module_existence() {
  log_step "Testing instances module existence"

  local instances_module="$KGSM_ROOT/commands/instances.sh"
  assert_file_exists "$instances_module" "instances.sh module should exist"

  # Check if file is executable
  if [[ -x "$instances_module" ]]; then
    assert_true "true" "instances.sh module should be executable"
  else
    assert_true "false" "instances.sh module should be executable"
  fi
}

function test_instances_module_help() {
  log_step "Testing instances module help functionality"

  local instances_module="$KGSM_ROOT/commands/instances.sh"
  assert_command_succeeds "$instances_module --help" "instances.sh --help should work"
}

function test_instances_module_list() {
  log_step "Testing instances module list functionality"

  local instances_module="$KGSM_ROOT/commands/instances.sh"
  assert_command_succeeds "$instances_module --list" "instances.sh --list should work"
}

function test_basic_directory_structure() {
  log_step "Testing basic KGSM directory structure"

  assert_dir_exists "$KGSM_ROOT/modules" "modules directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints" "blueprints directory should exist"

  # Check if instances directory exists or can be created
  if [[ -d "$KGSM_ROOT/instances" ]]; then
    log_test "instances directory already exists"
  else
    log_test "instances directory will be created when needed"
  fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting simple unit test"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_kgsm_main_script
  test_instances_module_existence
  test_instances_module_help
  test_instances_module_list
  test_basic_directory_structure

  log_test "Simple unit tests completed successfully"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All simple unit tests completed successfully"
  else
    fail_test "Some simple unit tests failed"
  fi
}

# Execute main function
main "$@"
