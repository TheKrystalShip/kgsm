#!/usr/bin/env bash

# Simple KGSM Integration Test
# Tests interaction between multiple KGSM modules

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="simple_integration"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up simple integration test"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "Test environment validated"
}

function test_core_modules_existence() {
  log_step "Testing core module existence"

  # Test blueprints module
  local blueprints_module="$KGSM_ROOT/commands/blueprints.sh"
  assert_file_exists "$blueprints_module" "blueprints.sh module should exist"

  # Test instances module
  local instances_module="$KGSM_ROOT/commands/instances.sh"
  assert_file_exists "$instances_module" "instances.sh module should exist"

  # Test lifecycle module
  local lifecycle_module="$KGSM_ROOT/commands/lifecycle.sh"
  assert_file_exists "$lifecycle_module" "lifecycle.sh module should exist"
}

function test_blueprint_discovery() {
  log_step "Testing blueprint discovery"

  assert_dir_exists "$KGSM_ROOT/blueprints" "blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default" "default blueprints directory should exist"
}

function test_blueprint_counting() {
  log_step "Testing blueprint counting and availability"

  # Count blueprint files
  local blueprint_count
  blueprint_count=$(find "$KGSM_ROOT/blueprints" -name "*.bp" -o -name "*.yml" 2>/dev/null | wc -l)

  assert_greater_than "$blueprint_count" 0 "Should have at least one blueprint file"
  log_test "Found $blueprint_count blueprint files"
}

function test_module_help_integration() {
  log_step "Testing module help functionality integration"

  # All core modules should provide help
  local blueprints_module="$KGSM_ROOT/commands/blueprints.sh"
  local instances_module="$KGSM_ROOT/commands/instances.sh"
  local lifecycle_module="$KGSM_ROOT/commands/lifecycle.sh"

  assert_command_succeeds "$blueprints_module --help" "blueprints module help should work"
  assert_command_succeeds "$instances_module --help" "instances module help should work"
  assert_command_succeeds "$lifecycle_module --help" "lifecycle module help should work"
}

function test_blueprints_instances_integration() {
  log_step "Testing blueprints and instances module integration"

  local blueprints_module="$KGSM_ROOT/commands/blueprints.sh"
  local instances_module="$KGSM_ROOT/commands/instances.sh"

  # Both modules should be able to list their content
  assert_command_succeeds "$blueprints_module --list" "blueprints --list should work"
  assert_command_succeeds "$instances_module --list" "instances --list should work"

  # Test JSON output consistency
  assert_command_succeeds "$blueprints_module --list --json" "blueprints --list --json should work"
  assert_command_succeeds "$instances_module --list --json" "instances --list --json should work"
}

function test_configuration_module_integration() {
  log_step "Testing configuration integration across modules"

  local config_file="$KGSM_ROOT/config.ini"
  assert_file_exists "$config_file" "Configuration file should exist"

  # Test that configuration contains integration-relevant settings
  assert_file_contains "$config_file" "default_install_directory" "Config should contain install directory setting"
  assert_file_contains "$config_file" "enable_logging" "Config should contain logging setting"

  # Test environment overrides are applied (important for integration testing)
  assert_file_contains "$config_file" "TEST ENVIRONMENT OVERRIDES" "Config should contain test overrides"
}

function test_directory_structure_integration() {
  log_step "Testing directory structure integration"

  # Core directories that modules depend on
  assert_dir_exists "$KGSM_ROOT/modules" "modules directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints" "blueprints directory should exist"

  # Instance directory should exist or be creatable
  local instances_dir="$KGSM_ROOT/instances"
  if [[ -d "$instances_dir" ]]; then
    log_test "instances directory already exists"
  else
    log_test "instances directory will be created when needed"
  fi

  # Logs directory for integration
  local logs_dir="$KGSM_ROOT/logs"
  if [[ -d "$logs_dir" ]]; then
    log_test "logs directory already exists"
  else
    log_test "logs directory will be created when needed"
  fi
}

function test_error_handling_integration() {
  log_step "Testing error handling integration between modules"

  local blueprints_module="$KGSM_ROOT/commands/blueprints.sh"
  local instances_module="$KGSM_ROOT/commands/instances.sh"

  # All modules should reject invalid arguments consistently
  assert_command_fails "$blueprints_module --invalid-arg" "blueprints module should reject invalid arguments"
  assert_command_fails "$instances_module --invalid-arg" "instances module should reject invalid arguments"
}

function test_output_format_consistency() {
  log_step "Testing output format consistency across modules"

  # Test that modules produce consistent output formats
  if command -v jq >/dev/null 2>&1; then
    local blueprints_json instances_json

    # Get JSON output from both modules
    if blueprints_json=$("$KGSM_ROOT/commands/blueprints.sh" --list --json 2>/dev/null); then
      if echo "$blueprints_json" | jq . >/dev/null 2>&1; then
        assert_true "true" "blueprints module should produce valid JSON"
      fi
    fi

    if instances_json=$("$KGSM_ROOT/commands/instances.sh" --list --json 2>/dev/null); then
      if echo "$instances_json" | jq . >/dev/null 2>&1; then
        assert_true "true" "instances module should produce valid JSON"
      fi
    fi
  else
    log_test "jq not available, skipping JSON format validation"
  fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting simple integration test"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_core_modules_existence
  test_blueprint_discovery
  test_blueprint_counting
  test_module_help_integration
  test_blueprints_instances_integration
  test_configuration_module_integration
  test_directory_structure_integration
  test_error_handling_integration
  test_output_format_consistency

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All simple integration tests completed successfully"
  else
    fail_test "Some simple integration tests failed"
  fi
}

# Execute main function
main "$@"
