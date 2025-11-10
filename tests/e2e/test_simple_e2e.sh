#!/usr/bin/env bash

# Simple KGSM End-to-End Test
# Tests complete KGSM workflow without requiring external dependencies

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="simple_e2e"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up simple e2e test"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "Test environment validated"
}

function test_main_script() {
  log_step "Testing main KGSM script"

  local kgsm_script="$KGSM_ROOT/kgsm.sh"
  assert_file_exists "$kgsm_script" "kgsm.sh should exist"

  # Check if script is executable
  if [[ -x "$kgsm_script" ]]; then
    assert_true "true" "kgsm.sh should be executable"
  else
    assert_true "false" "kgsm.sh should be executable"
  fi
}

function test_configuration() {
  log_step "Testing configuration setup"

  assert_file_exists "$KGSM_ROOT/config.ini" "config.ini should exist"
  assert_file_exists "$KGSM_ROOT/config.default.ini" "config.default.ini should exist"

  # Test configuration readability
  if [[ -r "$KGSM_ROOT/config.ini" ]]; then
    assert_true "true" "config.ini should be readable"
  else
    assert_true "false" "config.ini should be readable"
  fi
}

function test_modules_infrastructure() {
  log_step "Testing modules infrastructure"

  assert_dir_exists "$KGSM_ROOT/modules" "modules directory should exist"

  # Count and validate modules
  local module_count
  module_count=$(find "$KGSM_ROOT/modules" -name "*.sh" -type f 2>/dev/null | wc -l)

  assert_greater_than "$module_count" 0 "Should have at least one module file"
  log_test "Found $module_count module files"
}

function test_blueprints_infrastructure() {
  log_step "Testing blueprints infrastructure"

  assert_dir_exists "$KGSM_ROOT/blueprints" "blueprints directory should exist"

  # Count blueprints
  local blueprint_count
  blueprint_count=$(find "$KGSM_ROOT/blueprints" -name "*.bp" -o -name "*.yml" 2>/dev/null | wc -l)

  assert_greater_than "$blueprint_count" 0 "Should have at least one blueprint"
  log_test "Found $blueprint_count blueprint files"
}

function test_instances_directory() {
  log_step "Testing instances directory setup"

  # Instances directory should exist or be creatable
  local instances_dir="$KGSM_ROOT/instances"

  if [[ -d "$instances_dir" ]]; then
    assert_dir_exists "$instances_dir" "instances directory should exist"
    log_test "instances directory already exists"
  else
    log_test "instances directory will be created when needed"

    # Test that we can create it
    if mkdir -p "$instances_dir" 2>/dev/null; then
      assert_dir_exists "$instances_dir" "should be able to create instances directory"
      log_test "instances directory created successfully"
    else
      assert_true "false" "should be able to create instances directory"
    fi
  fi
}

function test_core_modules_functionality() {
  log_step "Testing core modules functionality"

  # Test that core modules can be executed and respond to help
  local core_modules=("blueprints.sh" "instances.sh" "lifecycle.sh")

  for module in "${core_modules[@]}"; do
    local module_path="$KGSM_ROOT/modules/$module"

    if [[ -f "$module_path" ]]; then
      assert_command_succeeds "$module_path --help" "$module should respond to --help"
    else
      log_test "Core module not found: $module (may not be required)"
    fi
  done
}

function test_blueprints_listing() {
  log_step "Testing blueprints listing functionality"

  local blueprints_module="$KGSM_ROOT/modules/blueprints.sh"

  if [[ -f "$blueprints_module" ]]; then
    assert_command_succeeds "$blueprints_module list" "blueprints list should work"

    # Test JSON output if module supports it
    if "$blueprints_module" list --json >/dev/null 2>&1; then
      log_test "blueprints module supports JSON output"
    else
      log_test "blueprints module may not support JSON output"
    fi
  else
    assert_true "false" "blueprints module should exist"
  fi
}

function test_instances_listing() {
  log_step "Testing instances listing functionality"

  local instances_module="$KGSM_ROOT/modules/instances.sh"

  if [[ -f "$instances_module" ]]; then
    assert_command_succeeds "$instances_module list" "instances list should work"

    # Test JSON output if module supports it
    if "$instances_module" list --json >/dev/null 2>&1; then
      log_test "instances module supports JSON output"
    else
      log_test "instances module may not support JSON output"
    fi
  else
    assert_true "false" "instances module should exist"
  fi
}

function test_e2e_workflow_readiness() {
  log_step "Testing e2e workflow readiness"

  # Test that all components needed for a basic workflow are present
  assert_file_exists "$KGSM_ROOT/kgsm.sh" "Main script should be ready"
  assert_dir_exists "$KGSM_ROOT/blueprints" "Blueprints should be available"
  assert_dir_exists "$KGSM_ROOT/modules" "Modules should be available"
  assert_file_exists "$KGSM_ROOT/config.ini" "Configuration should be ready"

  log_test "All components for e2e workflow are present"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting simple e2e test"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_main_script
  test_configuration
  test_modules_infrastructure
  test_blueprints_infrastructure
  test_instances_directory
  test_core_modules_functionality
  test_blueprints_listing
  test_instances_listing
  test_e2e_workflow_readiness

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All simple e2e tests completed successfully"
  else
    fail_test "Some simple e2e tests failed"
  fi
}

# Execute main function
main "$@"
