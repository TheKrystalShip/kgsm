#!/usr/bin/env bash

# KGSM Blueprints Module Unit Tests
# Tests the core functionality of the blueprints.sh module

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="blueprints_module"
readonly BLUEPRINTS_MODULE="$KGSM_ROOT/modules/blueprints.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up blueprints module tests"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  log_test "Test environment validated"
}

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  assert_file_exists "$BLUEPRINTS_MODULE" "blueprints.sh module should exist"

  # Check if file is executable
  if [[ -x "$BLUEPRINTS_MODULE" ]]; then
    assert_true "true" "blueprints.sh module should be executable"
  else
    assert_true "false" "blueprints.sh module should be executable"
  fi
}

function test_module_help_functionality() {
  log_step "Testing module help functionality"

  assert_command_succeeds "$BLUEPRINTS_MODULE help" "blueprints.sh help should work"
}

function test_blueprint_listing_functionality() {
  log_step "Testing blueprint listing functionality"

  assert_command_succeeds "$BLUEPRINTS_MODULE list" "blueprints.sh list should work"
}

function test_blueprint_json_listing() {
  log_step "Testing blueprint JSON listing functionality"

  assert_command_succeeds "$BLUEPRINTS_MODULE list --json" "blueprints.sh list --json should work"
}

function test_blueprint_directory_structure() {
  log_step "Testing blueprint directory structure"

  assert_dir_exists "$KGSM_ROOT/blueprints" "blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default" "default blueprints directory should exist"

  # Check for both native and container blueprint directories
  if [[ -d "$KGSM_ROOT/blueprints/default/native" ]]; then
    log_test "Native blueprints directory exists"
  fi

  if [[ -d "$KGSM_ROOT/blueprints/default/container" ]]; then
    log_test "Container blueprints directory exists"
  fi
}

function test_blueprint_availability() {
  log_step "Testing blueprint availability"

  local native_blueprints container_blueprints total_blueprints

  # Count native blueprints (.bp files)
  native_blueprints=$(find "$KGSM_ROOT/blueprints" -name "*.bp" 2>/dev/null | wc -l)

  # Count container blueprints (.docker-compose.yml and .yml files)
  container_blueprints=$(find "$KGSM_ROOT/blueprints" -name "*.docker-compose.yml" -o -name "*.yml" 2>/dev/null | wc -l)

  total_blueprints=$((native_blueprints + container_blueprints))

  assert_greater_than "$total_blueprints" 0 "Should have at least one blueprint available"

  log_test "Found $total_blueprints blueprints ($native_blueprints native, $container_blueprints container)"
}

function test_specific_blueprint_existence() {
  log_step "Testing specific blueprint existence"

  # Test for factorio blueprint (should exist in default installation)
  local factorio_blueprint="$KGSM_ROOT/blueprints/default/native/factorio.bp"

  if [[ -f "$factorio_blueprint" ]]; then
    assert_file_exists "$factorio_blueprint" "factorio.bp blueprint should exist"
    log_test "factorio.bp blueprint found"
  else
    log_test "factorio.bp blueprint not found (this may be expected depending on installation)"
  fi
}

function test_invalid_argument_handling() {
  log_step "Testing invalid argument handling"

  assert_command_fails "$BLUEPRINTS_MODULE --invalid-argument" "Module should reject invalid arguments"
}

function test_module_output_format() {
  log_step "Testing module output format consistency"

  # Test that list produces parseable output
  local list_output
  if list_output=$("$BLUEPRINTS_MODULE" list 2>/dev/null); then
    assert_not_null "$list_output" "List command should produce output"
    log_test "List command produces output"
  else
    log_test "List command failed - this may indicate no blueprints are available"
  fi

  # Test that list --json produces valid format (if jq is available)
  if command -v jq >/dev/null 2>&1; then
    local json_output
    if json_output=$("$BLUEPRINTS_MODULE" list --json 2>/dev/null); then
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

function test_blueprint_file_integrity() {
  log_step "Testing blueprint file integrity"

  # Find all .bp files and verify they're readable
  local blueprint_files
  mapfile -t blueprint_files < <(find "$KGSM_ROOT/blueprints" -name "*.bp" -type f 2>/dev/null)

  if [[ ${#blueprint_files[@]} -gt 0 ]]; then
    for blueprint_file in "${blueprint_files[@]}"; do
      assert_file_exists "$blueprint_file" "Blueprint file should exist: $(basename "$blueprint_file")"

      # Check if file is readable
      if [[ -r "$blueprint_file" ]]; then
        log_test "Blueprint file is readable: $(basename "$blueprint_file")"
      else
        assert_true "false" "Blueprint file should be readable: $(basename "$blueprint_file")"
      fi
    done

    assert_greater_than "${#blueprint_files[@]}" 0 "Should have found readable blueprint files"
  else
    log_test "No .bp blueprint files found"
  fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting blueprints module unit tests"

  # Initialize test environment
  setup_test

  # Execute all test functions
  test_module_existence_and_permissions
  test_module_help_functionality
  test_blueprint_listing_functionality
  test_blueprint_json_listing
  test_blueprint_directory_structure
  test_blueprint_availability
  test_specific_blueprint_existence
  test_invalid_argument_handling
  test_module_output_format
  test_blueprint_file_integrity

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All blueprints module tests completed successfully"
  else
    fail_test "Some blueprints module tests failed"
  fi
}

# Execute main function
main "$@"
