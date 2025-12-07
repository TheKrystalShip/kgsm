#!/usr/bin/env bash

# KGSM Blueprints Module Comprehensive Unit Tests
# Tests the complete functionality of the blueprints.sh module with maximum coverage
# Validates that behavioral uncertainty has been removed through proper validation

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="blueprints_module_comprehensive"
readonly BLUEPRINTS_MODULE="$KGSM_ROOT/commands/blueprints.sh"

# =============================================================================
# TEST UTILITY FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up comprehensive blueprints module tests"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$BLUEPRINTS_MODULE" "blueprints.sh module should exist"

  # Verify blueprints directory structure exists
  assert_dir_exists "$KGSM_ROOT/blueprints" "blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default" "default blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default/native" "native blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default/container" "container blueprints directory should exist"

  # Verify custom blueprints directory structure exists
  assert_dir_exists "$KGSM_ROOT/blueprints/custom" "custom blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/custom/native" "native blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/custom/container" "container blueprints directory should exist"

  # Verify default blueprints are present
  assert_file_exists "$KGSM_ROOT/blueprints/default/native/factorio.bp" "factorio.bp should exist"
  assert_file_exists "$KGSM_ROOT/blueprints/default/native/minecraft.bp" "minecraft.bp should exist"
  assert_file_exists "$KGSM_ROOT/blueprints/default/container/abioticfactor.docker-compose.yml" "abioticfactor.docker-compose.yml should exist"
  assert_file_exists "$KGSM_ROOT/blueprints/default/container/vrising.docker-compose.yml" "vrising.docker-compose.yml should exist"

  log_test "Test environment validated successfully"
}

function create_test_blueprint() {
  local blueprint_name="$1"
  local blueprint_type="${2:-native}" # native or container
  local blueprint_dir="$KGSM_ROOT/blueprints/custom/$blueprint_type"

  # Ensure custom blueprint directory exists
  mkdir -p "$blueprint_dir"

  if [[ "$blueprint_type" == "native" ]]; then
    local blueprint_file="$blueprint_dir/${blueprint_name}.bp"
    cat >"$blueprint_file" <<'EOF'
# Test Blueprint
name="Test Blueprint"
executable_file="test_server"
executable_arguments="-config test.cfg"
executable_working_directory="."
executable_subdirectory=""
EOF
  else
    local blueprint_file="$blueprint_dir/${blueprint_name}.docker-compose.yml"
    cat >"$blueprint_file" <<'EOF'
version: '3.8'
services:
  gameserver:
    image: test/gameserver:latest
    ports:
      - "25565:25565"
    environment:
      - SERVER_NAME=TestServer
EOF
  fi

  echo "$blueprint_file"
}

function cleanup_test_blueprint() {
  local blueprint_file="$1"
  [[ -f "$blueprint_file" ]] && rm -f "$blueprint_file"
}

# =============================================================================
# TEST FUNCTIONS - BASIC FUNCTIONALITY
# =============================================================================

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  assert_file_exists "$BLUEPRINTS_MODULE" "blueprints.sh module should exist"
  assert_file_executable "$BLUEPRINTS_MODULE" "blueprints.sh module should be executable"

  log_test "Module existence and permissions validated"
}

function test_help_functionality() {
  log_step "Testing help functionality"

  # Test --help flag
  assert_command_succeeds "$BLUEPRINTS_MODULE --help" "blueprints.sh --help should work"

  # Test -h flag
  assert_command_succeeds "$BLUEPRINTS_MODULE -h" "blueprints.sh -h should work"

  # Test help output contains expected sections
  local help_output
  help_output=$("$BLUEPRINTS_MODULE" --help 2>&1)

  assert_contains "$help_output" "Blueprint Management" "Help should contain title"
  assert_contains "$help_output" "--list" "Help should contain --list option"
  assert_contains "$help_output" "--info" "Help should contain --info option"
  assert_contains "$help_output" "--find" "Help should contain --find option"

  log_test "Help functionality validated"
}

function test_no_arguments_behavior() {
  log_step "Testing no arguments behavior"

  # Module should show usage when called without arguments
  assert_command_fails "$BLUEPRINTS_MODULE" "blueprints.sh with no arguments should fail"

  # Should show usage message
  local output
  output=$("$BLUEPRINTS_MODULE" 2>&1 || true)
  assert_contains "$output" "Blueprint Management" "Should show usage when no arguments provided"

  log_test "No arguments behavior validated"
}

# =============================================================================
# TEST FUNCTIONS - LISTING FUNCTIONALITY
# =============================================================================

function test_basic_listing() {
  log_step "Testing basic blueprint listing functionality"

  # Basic --list should work
  assert_command_succeeds "$BLUEPRINTS_MODULE --list" "blueprints.sh --list should work"

  # List output should contain blueprints
  local list_output
  list_output=$("$BLUEPRINTS_MODULE" --list 2>&1)

  # Should have some output (at least default blueprints)
  assert_not_null "$list_output" "Blueprint list should not be empty"

  log_test "Basic listing functionality validated"
}

function test_list_default_blueprints() {
  log_step "Testing default blueprints listing"

  # --list --default should work
  assert_command_succeeds "$BLUEPRINTS_MODULE --list --default" "blueprints.sh --list --default should work"

  # Should list default blueprints
  local default_output
  default_output=$("$BLUEPRINTS_MODULE" --list --default 2>&1)

  # Should contain known default blueprints
  if [[ -f "$KGSM_ROOT/blueprints/default/native/factorio.bp" ]]; then
    assert_contains "$default_output" "factorio" "Should list factorio blueprint if it exists"
  fi

  log_test "Default blueprints listing validated"
}

function test_list_custom_blueprints() {
  log_step "Testing custom blueprints listing"

  # --list --custom should work (even if empty)
  assert_command_succeeds "$BLUEPRINTS_MODULE --list --custom" "blueprints.sh --list --custom should work"

  log_test "Custom blueprints listing validated"
}

function test_list_detailed_blueprints() {
  log_step "Testing detailed blueprints listing"

  # --list --detailed should work
  assert_command_succeeds "$BLUEPRINTS_MODULE --list --detailed" "blueprints.sh --list --detailed should work"

  log_test "Detailed blueprints listing validated"
}

function test_json_listing_functionality() {
  log_step "Testing JSON listing functionality"

  # Basic JSON listing
  assert_command_succeeds "$BLUEPRINTS_MODULE --list --json" "blueprints.sh --list --json should work"

  # JSON output should be valid JSON
  local json_output
  json_output=$("$BLUEPRINTS_MODULE" --list --json 2>&1)

  # Validate JSON format
  if command -v jq >/dev/null 2>&1; then
    assert_command_succeeds "echo '$json_output' | jq ." "JSON output should be valid JSON"
  fi

  # Test detailed JSON
  assert_command_succeeds "$BLUEPRINTS_MODULE --list --detailed --json" "blueprints.sh --list --detailed --json should work"

  # Test default JSON
  assert_command_succeeds "$BLUEPRINTS_MODULE --list --default --json" "blueprints.sh --list --default --json should work"

  # Test custom JSON
  assert_command_succeeds "$BLUEPRINTS_MODULE --list --custom --json" "blueprints.sh --list --custom --json should work"

  log_test "JSON listing functionality validated"
}

# =============================================================================
# TEST FUNCTIONS - BLUEPRINT OPERATIONS
# =============================================================================

function test_blueprint_info_functionality() {
  log_step "Testing blueprint info functionality"

  # Find a valid blueprint to test with
  local test_blueprint=""
  if [[ -f "$KGSM_ROOT/blueprints/default/native/factorio.bp" ]]; then
    test_blueprint="factorio.bp"
  elif [[ -f "$KGSM_ROOT/blueprints/default/native/minecraft.bp" ]]; then
    test_blueprint="minecraft.bp"
  else
    # Find any .bp file
    test_blueprint=$(find "$KGSM_ROOT/blueprints" -name "*.bp" -type f | head -1 | xargs basename)
  fi

  # It should find a blueprint
  assert_not_null "$test_blueprint" "Test blueprint should not be null"

  # Test --info with valid blueprint
  assert_command_succeeds "$BLUEPRINTS_MODULE --info '$test_blueprint'" "blueprints.sh --info should work with valid blueprint"
  output=$("$BLUEPRINTS_MODULE" --info "$test_blueprint" 2>&1)
  exit_code=$?
  assert_equals "$exit_code" "0" "Blueprint info should exit with code 0"
  assert_not_null "$output" "Blueprint info should not be empty"

  # Test --info --json with valid blueprint
  assert_command_succeeds "$BLUEPRINTS_MODULE --info '$test_blueprint' --json" "blueprints.sh --info --json should work with valid blueprint"
  output=$("$BLUEPRINTS_MODULE" --info "$test_blueprint" --json 2>&1)
  exit_code=$?
  assert_equals "$exit_code" "0" "Blueprint info should exit with code 0"
  assert_not_null "$output" "Blueprint info should not be empty"

  # Test --info --detailed with valid blueprint
  assert_command_succeeds "$BLUEPRINTS_MODULE --info '$test_blueprint' --detailed" "blueprints.sh --info --detailed should work with valid blueprint"
  output=$("$BLUEPRINTS_MODULE" --info "$test_blueprint" --detailed 2>&1)
  exit_code=$?
  assert_equals "$exit_code" "0" "Blueprint info should exit with code 0"
  assert_not_null "$output" "Blueprint info should not be empty"

  # Test --info --json --detailed with valid blueprint
  assert_command_succeeds "$BLUEPRINTS_MODULE --info '$test_blueprint' --json --detailed" "blueprints.sh --info --json --detailed should work with valid blueprint"
  output=$("$BLUEPRINTS_MODULE" --info "$test_blueprint" --json --detailed 2>&1)
  exit_code=$?
  assert_equals "$exit_code" "0" "Blueprint info should exit with code 0"
  assert_not_null "$output" "Blueprint info should not be empty"

  log_test "Blueprint info functionality validated"
}

function test_blueprint_find_functionality() {
  log_step "Testing blueprint find functionality"

  # Find a valid blueprint to test with
  local test_blueprint=""
  if [[ -f "$KGSM_ROOT/blueprints/default/native/factorio.bp" ]]; then
    test_blueprint="factorio.bp"
  elif [[ -f "$KGSM_ROOT/blueprints/default/native/minecraft.bp" ]]; then
    test_blueprint="minecraft.bp"
  else
    # Find any .bp file
    test_blueprint=$(find "$KGSM_ROOT/blueprints" -name "*.bp" -type f | head -1 | xargs basename)
  fi

  if [[ -n "$test_blueprint" ]]; then
    # Test --find with valid blueprint
    assert_command_succeeds "$BLUEPRINTS_MODULE --find '$test_blueprint'" "blueprints.sh --find should work with valid blueprint"

    # Find output should be a valid path
    local find_output
    find_output=$("$BLUEPRINTS_MODULE" --find "$test_blueprint" 2>&1)
    assert_file_exists "$find_output" "Blueprint path returned by --find should exist"
  else
    log_test "No valid blueprints found for find testing - this is expected in minimal test environments"
  fi

  log_test "Blueprint find functionality validated"
}

# =============================================================================
# TEST FUNCTIONS - VALIDATION BEHAVIOR (BEHAVIORAL UNCERTAINTY REMOVAL)
# =============================================================================

function test_validation_with_invalid_blueprints() {
  log_step "Testing validation behavior with invalid blueprints"

  # Test --info with non-existent blueprint - should fail predictably
  assert_command_fails "$BLUEPRINTS_MODULE --info 'nonexistent_blueprint.bp'" "blueprints.sh --info should fail with non-existent blueprint"

  # Test --find with non-existent blueprint - should fail predictably
  assert_command_fails "$BLUEPRINTS_MODULE --find 'nonexistent_blueprint.bp'" "blueprints.sh --find should fail with non-existent blueprint"

  # Error messages should be helpful
  local error_output
  error_output=$("$BLUEPRINTS_MODULE" --info "nonexistent_blueprint.bp" 2>&1 || true)
  assert_contains "$error_output" "not found" "Error message should indicate blueprint not found"

  log_test "Invalid blueprint validation behavior confirmed"
}

function test_validation_with_empty_arguments() {
  log_step "Testing validation behavior with empty arguments"

  # Test --info without blueprint argument
  assert_command_fails "$BLUEPRINTS_MODULE --info" "blueprints.sh --info without argument should fail"

  # Test --find without blueprint argument
  assert_command_fails "$BLUEPRINTS_MODULE --find" "blueprints.sh --find without argument should fail"

  # Error messages should be clear
  local error_output
  error_output=$("$BLUEPRINTS_MODULE" --info 2>&1 || true)
  assert_contains "$error_output" "Missing argument" "Error message should indicate missing argument"

  log_test "Empty argument validation behavior confirmed"
}

function test_validation_with_corrupted_blueprints() {
  log_step "Testing validation behavior with corrupted blueprints"

  # Create a corrupted native blueprint
  local corrupted_bp
  corrupted_bp=$(create_test_blueprint "corrupted_test" "native")

  # Corrupt the blueprint by making it empty
  echo "" >"$corrupted_bp"

  # Test --info with corrupted blueprint - should fail predictably
  assert_command_fails "$BLUEPRINTS_MODULE --info 'corrupted_test.bp'" "blueprints.sh --info should fail with corrupted blueprint"

  # Test --find with corrupted blueprint - should fail predictably
  assert_command_fails "$BLUEPRINTS_MODULE --find 'corrupted_test.bp'" "blueprints.sh --find should fail with corrupted blueprint"

  # Cleanup
  cleanup_test_blueprint "$corrupted_bp"

  log_test "Corrupted blueprint validation behavior confirmed"
}

function test_validation_with_malformed_blueprints() {
  log_step "Testing validation behavior with malformed blueprints"

  # Create a malformed native blueprint
  local malformed_bp
  malformed_bp=$(create_test_blueprint "malformed_test" "native")

  # Make the blueprint malformed (missing required fields)
  cat >"$malformed_bp" <<'EOF'
# Malformed blueprint - missing required fields
description="This blueprint is missing required fields"
EOF

  # Test --info with malformed blueprint - should fail predictably
  assert_command_fails "$BLUEPRINTS_MODULE --info 'malformed_test.bp'" "blueprints.sh --info should fail with malformed blueprint"

  # Test --find with malformed blueprint - should fail predictably
  assert_command_fails "$BLUEPRINTS_MODULE --find 'malformed_test.bp'" "blueprints.sh --find should fail with malformed blueprint"

  # Cleanup
  cleanup_test_blueprint "$malformed_bp"

  log_test "Malformed blueprint validation behavior confirmed"
}

# =============================================================================
# TEST FUNCTIONS - ERROR HANDLING
# =============================================================================

function test_invalid_argument_handling() {
  log_step "Testing invalid argument handling"

  # Test invalid main arguments
  assert_command_fails "$BLUEPRINTS_MODULE --invalid-argument" "blueprints.sh should reject invalid arguments"

  # Test invalid list sub-arguments
  assert_command_fails "$BLUEPRINTS_MODULE --list --invalid-subarg" "blueprints.sh --list should reject invalid sub-arguments"

  # Error messages should be helpful
  local error_output
  error_output=$("$BLUEPRINTS_MODULE" --invalid-argument 2>&1 || true)
  assert_contains "$error_output" "Invalid argument" "Error message should indicate invalid argument"

  log_test "Invalid argument handling validated"
}

function test_permission_error_handling() {
  log_step "Testing permission error handling"

  # Create a test blueprint with restricted permissions
  local restricted_bp
  restricted_bp=$(create_test_blueprint "restricted_test" "native")

  # Remove read permissions
  chmod 000 "$restricted_bp"

  # Test --info with unreadable blueprint - should fail predictably
  assert_command_fails "$BLUEPRINTS_MODULE --info 'restricted_test.bp'" "blueprints.sh --info should fail with unreadable blueprint"

  # Restore permissions for cleanup
  chmod 644 "$restricted_bp"
  cleanup_test_blueprint "$restricted_bp"

  log_test "Permission error handling validated"
}

# =============================================================================
# TEST FUNCTIONS - COMPREHENSIVE COVERAGE
# =============================================================================

function test_all_command_combinations() {
  log_step "Testing all command combinations for comprehensive coverage"

  # Test all valid --list combinations
  local list_commands=(
    "--list"
    "--list --default"
    "--list --custom"
    "--list --detailed"
    "--list --json"
    "--list --default --json"
    "--list --custom --json"
    "--list --detailed --json"
  )

  for cmd in "${list_commands[@]}"; do
    assert_command_succeeds "$BLUEPRINTS_MODULE $cmd" "blueprints.sh $cmd should work"
  done

  log_test "All command combinations tested"
}

function test_debug_mode_functionality() {
  log_step "Testing debug mode functionality"

  # Test --debug flag with various commands
  assert_command_succeeds "$BLUEPRINTS_MODULE --debug --help" "blueprints.sh --debug --help should work"
  assert_command_succeeds "$BLUEPRINTS_MODULE --debug --list" "blueprints.sh --debug --list should work"

  log_test "Debug mode functionality validated"
}

function test_module_integration() {
  log_step "Testing module integration and dependencies"

  # Test that the module can find and load its dependencies
  assert_command_succeeds "bash -c 'KGSM_ROOT=\"$KGSM_ROOT\" \"$BLUEPRINTS_MODULE\" --help'" "Module should work with explicit KGSM_ROOT"

  log_test "Module integration validated"
}

# =============================================================================
# TEST FUNCTIONS - BEHAVIORAL CERTAINTY VALIDATION
# =============================================================================

function test_behavioral_certainty_consistency() {
  log_step "Testing behavioral certainty and consistency"

  # Run the same command multiple times - should always produce the same result
  local result1 result2 result3

  # Test --list consistency
  result1=$("$BLUEPRINTS_MODULE" --list 2>&1 || echo "FAILED")
  result2=$("$BLUEPRINTS_MODULE" --list 2>&1 || echo "FAILED")
  result3=$("$BLUEPRINTS_MODULE" --list 2>&1 || echo "FAILED")

  assert_equals "$result1" "$result2" "Multiple --list calls should produce identical results"
  assert_equals "$result2" "$result3" "All --list calls should be consistent"

  # Test --help consistency
  result1=$("$BLUEPRINTS_MODULE" --help 2>&1 || echo "FAILED")
  result2=$("$BLUEPRINTS_MODULE" --help 2>&1 || echo "FAILED")

  assert_equals "$result1" "$result2" "Multiple --help calls should produce identical results"

  log_test "Behavioral certainty and consistency validated"
}

function test_validation_error_consistency() {
  log_step "Testing validation error consistency"

  # Test that the same invalid input always produces the same error
  local error1 error2 error3

  error1=$("$BLUEPRINTS_MODULE" --info "nonexistent.bp" 2>&1 || true)
  error2=$("$BLUEPRINTS_MODULE" --info "nonexistent.bp" 2>&1 || true)
  error3=$("$BLUEPRINTS_MODULE" --info "nonexistent.bp" 2>&1 || true)

  assert_equals "$error1" "$error2" "Same invalid input should produce identical errors"
  assert_equals "$error2" "$error3" "Error messages should be consistent"

  log_test "Validation error consistency confirmed"
}

# =============================================================================
# TEST FUNCTIONS - EDGE CASES
# =============================================================================

function test_edge_cases() {
  log_step "Testing edge cases and boundary conditions"

  # Test with very long blueprint names
  assert_command_fails "$BLUEPRINTS_MODULE --info '$(printf 'a%.0s' {1..1000}).bp'" "Should handle very long blueprint names gracefully"

  # Test with special characters in blueprint names
  assert_command_fails "$BLUEPRINTS_MODULE --info 'blueprint with spaces.bp'" "Should handle spaces in blueprint names"
  assert_command_fails "$BLUEPRINTS_MODULE --info 'blueprint@#\$%.bp'" "Should handle special characters in blueprint names"

  # Test with empty string arguments
  assert_command_fails "$BLUEPRINTS_MODULE --info ''" "Should reject empty blueprint names"

  log_test "Edge cases handled appropriately"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting comprehensive blueprints module tests"

  # Initialize test environment
  setup_test

  # Basic functionality tests
  test_module_existence_and_permissions
  test_help_functionality
  test_no_arguments_behavior

  # Listing functionality tests
  test_basic_listing
  test_list_default_blueprints
  test_list_custom_blueprints
  test_list_detailed_blueprints
  test_json_listing_functionality

  # Blueprint operations tests
  test_blueprint_info_functionality
  test_blueprint_find_functionality

  # Validation behavior tests (behavioral uncertainty removal)
  test_validation_with_invalid_blueprints
  test_validation_with_empty_arguments
  test_validation_with_corrupted_blueprints
  test_validation_with_malformed_blueprints

  # Error handling tests
  test_invalid_argument_handling
  test_permission_error_handling

  # Comprehensive coverage tests
  test_all_command_combinations
  test_debug_mode_functionality
  test_module_integration

  # Behavioral certainty validation
  test_behavioral_certainty_consistency
  test_validation_error_consistency

  # Edge cases
  test_edge_cases

  log_test "Comprehensive blueprints module tests completed successfully"

  # Print final results and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All comprehensive blueprints module tests completed successfully"
  else
    fail_test "Some comprehensive blueprints module tests failed"
  fi
}

# Execute main function
main "$@"
