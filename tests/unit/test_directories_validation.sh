#!/usr/bin/env bash

# =============================================================================
# KGSM Directories Validation Functions - Unit Test Suite
# =============================================================================
#
# This test provides comprehensive coverage of the validation functions in
# core/validation.sh that are used by the directories module.
#
# The validation functions tested:
# - validate_instance_name: Validates instance name and returns config file path
# - validate_working_directory: Validates working directory configuration
#
# Test Coverage:
# ✓ validate_instance_name function
# ✓ validate_working_directory function
# ✓ Parameter validation
# ✓ Error code verification
# ✓ Valid and invalid inputs
# ✓ File existence and readability checks
# ✓ Path validation (absolute paths)
# ✓ Error message consistency
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="directories_validation"
readonly VALIDATION_LIBRARY="$KGSM_ROOT/core/validation.sh"
readonly TEST_INSTANCE="validation-test-$(date +%s)"
readonly TEST_WORKING_DIR="/tmp/kgsm-validation-test-${TEST_INSTANCE}"
readonly TEST_CONFIG_FILE="/tmp/test-validation-${TEST_INSTANCE}.ini"
readonly TEST_INSTANCES_DIR="/tmp/kgsm-test-instances-$$"

# =============================================================================
# SETUP AND TEARDOWN
# =============================================================================

function setup_test() {
  log_test "Setting up directories validation test environment"

  # Use KGSM bootstrap to load all required libraries
  local bootstrap_lib="$KGSM_ROOT/core/bootstrap.sh"
  if [[ -f "$bootstrap_lib" ]]; then
    # shellcheck disable=SC1090
    source "$bootstrap_lib" || {
      log_error "Failed to load KGSM bootstrap: $bootstrap_lib"
      exit 1
    }
  else
    log_error "KGSM bootstrap not found: $bootstrap_lib"
    exit 1
  fi

  # Create test instances directory
  mkdir -p "$TEST_INSTANCES_DIR"

  # Create test config file with valid working_dir
  cat > "$TEST_CONFIG_FILE" << EOF
# Test instance configuration
instance_name=$TEST_INSTANCE
working_dir=$TEST_WORKING_DIR
blueprint_file=factorio.bp
EOF

  # Create test instance config in instances directory
  cat > "$TEST_INSTANCES_DIR/${TEST_INSTANCE}.ini" << EOF
# Test instance configuration
instance_name=$TEST_INSTANCE
working_dir=$TEST_WORKING_DIR
blueprint_file=factorio.bp
EOF

  # Temporarily override INSTANCES_SOURCE_DIR for testing
  export INSTANCES_SOURCE_DIR_BACKUP="$INSTANCES_SOURCE_DIR"
  export INSTANCES_SOURCE_DIR="$TEST_INSTANCES_DIR"

  log_test "Test environment setup complete"
}

function teardown_test() {
  log_test "Cleaning up directories validation test environment"

  # Restore original INSTANCES_SOURCE_DIR
  if [[ -n "${INSTANCES_SOURCE_DIR_BACKUP:-}" ]]; then
    export INSTANCES_SOURCE_DIR="$INSTANCES_SOURCE_DIR_BACKUP"
    unset INSTANCES_SOURCE_DIR_BACKUP
  fi

  # Remove test directories and files
  [[ -d "$TEST_WORKING_DIR" ]] && rm -rf "$TEST_WORKING_DIR" 2>/dev/null || true
  [[ -f "$TEST_CONFIG_FILE" ]] && rm -f "$TEST_CONFIG_FILE" 2>/dev/null || true
  [[ -d "$TEST_INSTANCES_DIR" ]] && rm -rf "$TEST_INSTANCES_DIR" 2>/dev/null || true

  log_test "Test environment cleanup complete"
}

# =============================================================================
# TEST FUNCTIONS - VALIDATION LIBRARY
# =============================================================================

function test_validation_library_existence() {
  log_step "Testing validation library existence and loading"

  # Basic file system checks
  assert_file_exists "$VALIDATION_LIBRARY" "Validation library file should exist"
  assert_command_succeeds "test -r '$VALIDATION_LIBRARY'" "Validation library should be readable"

  # Check file size (should not be empty)
  assert_command_succeeds "test -s '$VALIDATION_LIBRARY'" "Validation library should not be empty"

  log_test "Validation library existence validated"
}

function test_validation_functions_exist() {
  log_step "Testing that validation functions are defined"

  # Test that required functions exist
  assert_function_exists "validate_instance_name" "validate_instance_name function should exist"
  assert_function_exists "validate_working_directory" "validate_working_directory function should exist"

  log_test "Validation functions existence validated"
}

# =============================================================================
# TEST FUNCTIONS - validate_instance_name
# =============================================================================

function test_validate_instance_name_success() {
  log_step "Testing validate_instance_name success case"

  # Test with valid instance name
  local result
  local exit_code
  result=$(validate_instance_name "$TEST_INSTANCE" 2>/dev/null)
  exit_code=$?

  # Should succeed and return config file path
  assert_equals "0" "$exit_code" "Should return success for valid instance"
  assert_not_null "$result" "Should return config file path"
  assert_contains "$result" "${TEST_INSTANCE}.ini" "Should return correct config file path"
  assert_file_exists "$result" "Returned config file should exist"

  log_test "validate_instance_name success case validated"
}

function test_validate_instance_name_empty() {
  log_step "Testing validate_instance_name with empty parameter"

  local result
  local exit_code
  result=$(validate_instance_name "" 2>/dev/null)
  exit_code=$?

  # Should fail with invalid argument error
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty instance name"
  assert_null "$result" "Should return no output for invalid input"

  log_test "validate_instance_name empty parameter test completed"
}

function test_validate_instance_name_nonexistent() {
  log_step "Testing validate_instance_name with nonexistent instance"

  local nonexistent_instance="nonexistent-instance-$$"
  local result
  local exit_code
  result=$(validate_instance_name "$nonexistent_instance" 2>/dev/null)
  exit_code=$?

  # Should fail with file not found error
  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return file not found for nonexistent instance"
  assert_null "$result" "Should return no output for nonexistent instance"

  log_test "validate_instance_name nonexistent instance test completed"
}

function test_validate_instance_name_unreadable() {
  log_step "Testing validate_instance_name with unreadable config file"

  # Create unreadable config file (if not running as root)
  if [[ $EUID -ne 0 ]]; then
    local unreadable_instance="unreadable-test-$$"
    local unreadable_config="$TEST_INSTANCES_DIR/${unreadable_instance}.ini"

    echo "test config" > "$unreadable_config"
    chmod 000 "$unreadable_config"

    local result
    local exit_code
    result=$(validate_instance_name "$unreadable_instance" 2>/dev/null)
    exit_code=$?

    # Should fail with permission error
    assert_equals "$EC_PERMISSION" "$exit_code" "Should return permission error for unreadable config"
    assert_null "$result" "Should return no output for unreadable config"

    # Cleanup
    chmod 644 "$unreadable_config" 2>/dev/null || true
    rm -f "$unreadable_config" 2>/dev/null || true
  else
    skip_test "Skipping unreadable file test when running as root"
  fi

  log_test "validate_instance_name unreadable config test completed"
}

# =============================================================================
# TEST FUNCTIONS - validate_working_directory
# =============================================================================

function test_validate_working_directory_success() {
  log_step "Testing validate_working_directory success case"

  # Test with valid config file
  local result
  local exit_code
  result=$(validate_working_directory "$TEST_CONFIG_FILE" 2>/dev/null)
  exit_code=$?

  # Should succeed and return working directory path
  assert_equals "0" "$exit_code" "Should return success for valid config"
  assert_not_null "$result" "Should return working directory path"
  assert_equals "$TEST_WORKING_DIR" "$result" "Should return correct working directory path"

  log_test "validate_working_directory success case validated"
}

function test_validate_working_directory_empty_parameter() {
  log_step "Testing validate_working_directory with empty parameter"

  local result
  local exit_code
  result=$(validate_working_directory "" 2>/dev/null)
  exit_code=$?

  # Should fail with invalid argument error
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty config file"
  assert_null "$result" "Should return no output for invalid input"

  log_test "validate_working_directory empty parameter test completed"
}

function test_validate_working_directory_nonexistent_file() {
  log_step "Testing validate_working_directory with nonexistent config file"

  local nonexistent_config="/tmp/nonexistent-config-$$.ini"
  local result
  local exit_code
  result=$(validate_working_directory "$nonexistent_config" 2>/dev/null)
  exit_code=$?

  # Should fail with file not found error
  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return file not found for nonexistent config"
  assert_null "$result" "Should return no output for nonexistent config"

  log_test "validate_working_directory nonexistent file test completed"
}

function test_validate_working_directory_missing_working_dir() {
  log_step "Testing validate_working_directory with missing working_dir"

  # Create config file without working_dir
  local config_without_working_dir="/tmp/test-no-working-dir-$$.ini"
  cat > "$config_without_working_dir" << EOF
# Test config without working_dir
instance_name=test
blueprint_file=factorio.bp
EOF

  local result
  local exit_code
  result=$(validate_working_directory "$config_without_working_dir" 2>/dev/null)
  exit_code=$?

  # Should fail with key not found error (more accurate than invalid config)
  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code" "Should return key not found for missing working_dir"
  assert_null "$result" "Should return no output for missing working_dir"

  # Cleanup
  rm -f "$config_without_working_dir" 2>/dev/null || true

  log_test "validate_working_directory missing working_dir test completed"
}

function test_validate_working_directory_relative_path() {
  log_step "Testing validate_working_directory with relative path"

  # Create config file with relative working_dir
  local config_with_relative_path="/tmp/test-relative-path-$$.ini"
  cat > "$config_with_relative_path" << EOF
# Test config with relative working_dir
instance_name=test
working_dir=relative/path
blueprint_file=factorio.bp
EOF

  local result
  local exit_code
  result=$(validate_working_directory "$config_with_relative_path" 2>/dev/null)
  exit_code=$?

  # Should fail with invalid config error
  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config for relative path"
  assert_null "$result" "Should return no output for relative path"

  # Cleanup
  rm -f "$config_with_relative_path" 2>/dev/null || true

  log_test "validate_working_directory relative path test completed"
}

function test_validate_working_directory_empty_working_dir() {
  log_step "Testing validate_working_directory with empty working_dir"

  # Create config file with empty working_dir
  local config_with_empty_working_dir="/tmp/test-empty-working-dir-$$.ini"
  cat > "$config_with_empty_working_dir" << EOF
# Test config with empty working_dir
instance_name=test
working_dir=
blueprint_file=factorio.bp
EOF

  local result
  local exit_code
  result=$(validate_working_directory "$config_with_empty_working_dir" 2>/dev/null)
  exit_code=$?

  # Should fail with invalid config error
  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code" "Should return \$EC_KEY_NOT_FOUND($EC_KEY_NOT_FOUND) for missing 'working_dir'"
  assert_null "$result" "Should return no output for empty working_dir"

  # Cleanup
  rm -f "$config_with_empty_working_dir" 2>/dev/null || true

  log_test "validate_working_directory empty working_dir test completed"
}

# =============================================================================
# TEST FUNCTIONS - INTEGRATION TESTS
# =============================================================================

function test_validation_functions_integration() {
  log_step "Testing validation functions working together"

  # Test the complete validation flow
  local instance_config
  local working_dir
  local exit_code

  # Step 1: Validate instance name
  instance_config=$(validate_instance_name "$TEST_INSTANCE" 2>/dev/null)
  exit_code=$?
  assert_equals "0" "$exit_code" "Instance validation should succeed"
  assert_not_null "$instance_config" "Should return config file path"

  # Step 2: Validate working directory using returned config
  working_dir=$(validate_working_directory "$instance_config" 2>/dev/null)
  exit_code=$?
  assert_equals "0" "$exit_code" "Working directory validation should succeed"
  assert_not_null "$working_dir" "Should return working directory path"
  assert_equals "$TEST_WORKING_DIR" "$working_dir" "Should return correct working directory"

  log_test "Validation functions integration test completed"
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

function run_all_tests() {
  log_test "Starting directories validation unit tests"

  # Setup
  setup_test

  # Basic validation tests
  test_validation_library_existence
  test_validation_functions_exist

  # validate_instance_name tests
  test_validate_instance_name_success
  test_validate_instance_name_empty
  test_validate_instance_name_nonexistent
  test_validate_instance_name_unreadable

  # validate_working_directory tests
  test_validate_working_directory_success
  test_validate_working_directory_empty_parameter
  test_validate_working_directory_nonexistent_file
  test_validate_working_directory_missing_working_dir
  test_validate_working_directory_relative_path
  test_validate_working_directory_empty_working_dir

  # Integration tests
  test_validation_functions_integration

  # Cleanup
  teardown_test

  # Print summary
  print_assert_summary "$TEST_NAME"
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all_tests
fi
