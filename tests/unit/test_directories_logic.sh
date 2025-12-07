#!/usr/bin/env bash

# =============================================================================
# KGSM Directories Logic Layer - Unit Test Suite
# =============================================================================
#
# This test provides comprehensive coverage of the pure logic functions in
# commands/handlers/directories.sh, testing all scenarios, error conditions, and
# exit code behaviors.
#
# The logic layer contains pure business logic functions that:
# - Have no user-facing I/O
# - Communicate results only via exit codes
# - Return 200+ for success events, standard error codes for failures
#
# Test Coverage:
# ✓ __logic_create_directories function
# ✓ __logic_remove_directories function
# ✓ Parameter validation
# ✓ Exit code verification
# ✓ Directory creation and removal
# ✓ Config file updates
# ✓ Error conditions and edge cases
# ✓ Path validation (absolute paths)
# ✓ Function isolation (no I/O side effects)
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="directories_logic"
readonly LOGIC_LIBRARY="$KGSM_ROOT/commands/handlers/directories.sh"
readonly TEST_INSTANCE="logic-test-$(date +%s)"
readonly TEST_WORKING_DIR="/tmp/kgsm-test-${TEST_INSTANCE}"
readonly TEST_CONFIG_FILE="/tmp/test-${TEST_INSTANCE}.ini"

# =============================================================================
# SETUP AND TEARDOWN
# =============================================================================

function setup_test() {
  log_test "Setting up directories logic test environment"

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

  # Load the logic library
  if [[ -f "$LOGIC_LIBRARY" ]]; then
    # shellcheck disable=SC1090
    source "$LOGIC_LIBRARY" || {
      log_error "Failed to load logic library: $LOGIC_LIBRARY"
      exit 1
    }
  else
    log_error "Logic library not found: $LOGIC_LIBRARY"
    exit 1
  fi

  # Create test config file
  cat > "$TEST_CONFIG_FILE" << EOF
# Test instance configuration
instance_name=$TEST_INSTANCE
working_dir=$TEST_WORKING_DIR
EOF

  log_test "Test environment setup complete"
}

function teardown_test() {
  log_test "Cleaning up directories logic test environment"

  # Remove test directories
  [[ -d "$TEST_WORKING_DIR" ]] && rm -rf "$TEST_WORKING_DIR" 2>/dev/null || true

  # Remove test config file
  [[ -f "$TEST_CONFIG_FILE" ]] && rm -f "$TEST_CONFIG_FILE" 2>/dev/null || true

  log_test "Test environment cleanup complete"
}

# =============================================================================
# TEST FUNCTIONS - LOGIC LIBRARY VALIDATION
# =============================================================================

function test_logic_library_existence() {
  log_step "Testing logic library existence and loading"

  # Basic file system checks
  assert_file_exists "$LOGIC_LIBRARY" "Logic library file should exist"
  assert_command_succeeds "test -r '$LOGIC_LIBRARY'" "Logic library should be readable"

  # Check file size (should not be empty)
  assert_command_succeeds "test -s '$LOGIC_LIBRARY'" "Logic library should not be empty"

  # Verify it's a bash script
  local first_line
  first_line=$(head -n1 "$LOGIC_LIBRARY")
  assert_contains "$first_line" "#!/usr/bin/env bash" "Logic library should be a bash script"

  log_test "Logic library existence validated"
}

function test_logic_functions_exist() {
  log_step "Testing that logic functions are defined"

  # Test that required functions exist
  assert_function_exists "__logic_create_directories" "Create directories function should exist"
  assert_function_exists "__logic_remove_directories" "Remove directories function should exist"

  log_test "Logic functions existence validated"
}

# =============================================================================
# TEST FUNCTIONS - __logic_create_directories
# =============================================================================

function test_create_directories_success() {
  log_step "Testing __logic_create_directories success case"

  # Ensure test directory doesn't exist
  [[ -d "$TEST_WORKING_DIR" ]] && rm -rf "$TEST_WORKING_DIR"

  # Call the logic function
  local exit_code
  __logic_create_directories "$TEST_INSTANCE" "$TEST_CONFIG_FILE" "$TEST_WORKING_DIR"
  exit_code=$?

  # Verify exit code is success event code
  assert_equals "$EC_SUCCESS_DIRECTORIES_CREATED" "$exit_code" "Should return directories created success code"

  # Verify directories were created
  assert_dir_exists "$TEST_WORKING_DIR" "Working directory should be created"
  assert_dir_exists "$TEST_WORKING_DIR/backups" "Backups directory should be created"
  assert_dir_exists "$TEST_WORKING_DIR/install" "Install directory should be created"
  assert_dir_exists "$TEST_WORKING_DIR/saves" "Saves directory should be created"
  assert_dir_exists "$TEST_WORKING_DIR/temp" "Temp directory should be created"
  assert_dir_exists "$TEST_WORKING_DIR/logs" "Logs directory should be created"

  # Verify config file was updated
  assert_file_contains "$TEST_CONFIG_FILE" "working_dir=\"$TEST_WORKING_DIR\"" "Config should contain working_dir"
  assert_file_contains "$TEST_CONFIG_FILE" "backups_dir=\"$TEST_WORKING_DIR/backups\"" "Config should contain backups_dir"
  assert_file_contains "$TEST_CONFIG_FILE" "install_dir=\"$TEST_WORKING_DIR/install\"" "Config should contain install_dir"
  assert_file_contains "$TEST_CONFIG_FILE" "saves_dir=\"$TEST_WORKING_DIR/saves\"" "Config should contain saves_dir"
  assert_file_contains "$TEST_CONFIG_FILE" "temp_dir=\"$TEST_WORKING_DIR/temp\"" "Config should contain temp_dir"
  assert_file_contains "$TEST_CONFIG_FILE" "logs_dir=\"$TEST_WORKING_DIR/logs\"" "Config should contain logs_dir"

  log_test "Create directories success case validated"
}

function test_create_directories_invalid_parameters() {
  log_step "Testing __logic_create_directories parameter validation"

  local exit_code

  # Test empty instance name
  __logic_create_directories "" "$TEST_CONFIG_FILE" "$TEST_WORKING_DIR"
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty instance name"

  # Test empty config file
  __logic_create_directories "$TEST_INSTANCE" "" "$TEST_WORKING_DIR"
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty config file"

  # Test empty working dir
  __logic_create_directories "$TEST_INSTANCE" "$TEST_CONFIG_FILE" ""
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty working dir"

  log_test "Create directories parameter validation completed"
}

function test_create_directories_relative_path() {
  log_step "Testing __logic_create_directories with relative path"

  local exit_code
  local relative_path="relative/path"

  # Test relative path (should fail)
  __logic_create_directories "$TEST_INSTANCE" "$TEST_CONFIG_FILE" "$relative_path"
  exit_code=$?
  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config for relative path"

  log_test "Create directories relative path validation completed"
}

function test_create_directories_permission_error() {
  log_step "Testing __logic_create_directories permission error"

  # Create a directory we can't write to (if running as non-root)
  local readonly_dir="/tmp/kgsm-readonly-test-$$"
  local readonly_subdir="$readonly_dir/subdir"

  assert_command_succeeds "mkdir -p $readonly_dir" "Should be able to create directory in test environment"
  assert_command_succeeds "chmod 444 $readonly_dir" "Should be able to assign 444 permissions to directory in test environment"

  local exit_code
  __logic_create_directories "$TEST_INSTANCE" "$TEST_CONFIG_FILE" "$readonly_subdir" 2>&1
  exit_code=$?

  # Should fail with mkdir error
  assert_equals "$EC_FAILED_MKDIR" "$exit_code" "Should return mkdir failed for permission error"

  log_test "Create directories permission error test completed"
}

# =============================================================================
# TEST FUNCTIONS - __logic_remove_directories
# =============================================================================

function test_remove_directories_success() {
  log_step "Testing __logic_remove_directories success case"

  # First create directories to remove
  mkdir -p "$TEST_WORKING_DIR"/{backups,install,saves,temp,logs}
  echo "test file" > "$TEST_WORKING_DIR/test.txt"

  # Verify directories exist before removal
  assert_dir_exists "$TEST_WORKING_DIR" "Working directory should exist before removal"

  # Call the logic function
  local exit_code
  __logic_remove_directories "$TEST_INSTANCE" "$TEST_WORKING_DIR"
  exit_code=$?

  # Verify exit code is success event code
  assert_equals "$EC_SUCCESS_DIRECTORIES_REMOVED" "$exit_code" "Should return directories removed success code"

  # Verify directory was removed
  assert_dir_not_exists "$TEST_WORKING_DIR" "Working directory should be removed"

  log_test "Remove directories success case validated"
}

function test_remove_directories_invalid_parameters() {
  log_step "Testing __logic_remove_directories parameter validation"

  local exit_code

  # Test empty instance name
  __logic_remove_directories "" "$TEST_WORKING_DIR"
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty instance name"

  # Test empty working dir
  __logic_remove_directories "$TEST_INSTANCE" ""
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty working dir"

  log_test "Remove directories parameter validation completed"
}

function test_remove_directories_relative_path() {
  log_step "Testing __logic_remove_directories with relative path"

  local exit_code
  local relative_path="relative/path"

  # Test relative path (should fail)
  __logic_remove_directories "$TEST_INSTANCE" "$relative_path"
  exit_code=$?
  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config for relative path"

  log_test "Remove directories relative path validation completed"
}

function test_remove_directories_nonexistent() {
  log_step "Testing __logic_remove_directories with nonexistent directory"

  local nonexistent_dir="/tmp/kgsm-nonexistent-$$"

  # Ensure directory doesn't exist
  [[ -d "$nonexistent_dir" ]] && rm -rf "$nonexistent_dir"

  local exit_code
  __logic_remove_directories "$TEST_INSTANCE" "$nonexistent_dir"
  exit_code=$?

  # Should succeed (rm -rf doesn't fail on nonexistent directories)
  assert_equals "$EC_SUCCESS_DIRECTORIES_REMOVED" "$exit_code" "Should succeed even if directory doesn't exist"

  log_test "Remove directories nonexistent directory test completed"
}

# =============================================================================
# TEST FUNCTIONS - FUNCTION ISOLATION
# =============================================================================

function test_functions_have_no_io() {
  log_step "Testing that logic functions produce no output"

  # Create test directory
  mkdir -p "$TEST_WORKING_DIR"

  # Capture any output from create function
  local create_output
  create_output=$(__logic_create_directories "$TEST_INSTANCE" "$TEST_CONFIG_FILE" "$TEST_WORKING_DIR" 2>&1)
  local create_exit=$?

  # Should have no output (pure function)
  assert_null "$create_output" "Create function should produce no output"
  assert_equals "$EC_SUCCESS_DIRECTORIES_CREATED" "$create_exit" "Create function should return success code"

  # Capture any output from remove function
  local remove_output
  remove_output=$(__logic_remove_directories "$TEST_INSTANCE" "$TEST_WORKING_DIR" 2>&1)
  local remove_exit=$?

  # Should have no output (pure function)
  assert_null "$remove_output" "Remove function should produce no output"
  assert_equals "$EC_SUCCESS_DIRECTORIES_REMOVED" "$remove_exit" "Remove function should return success code"

  log_test "Function isolation (no I/O) validated"
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

function run_all_tests() {
  log_test "Starting directories logic unit tests"

  # Setup
  setup_test

  # Basic validation tests
  test_logic_library_existence
  test_logic_functions_exist

  # Create directories tests
  test_create_directories_success
  test_create_directories_invalid_parameters
  test_create_directories_relative_path
  test_create_directories_permission_error

  # Remove directories tests
  test_remove_directories_success
  test_remove_directories_invalid_parameters
  test_remove_directories_relative_path
  test_remove_directories_nonexistent

  # Function isolation tests
  test_functions_have_no_io

  # Cleanup
  teardown_test

  # Print summary
  print_assert_summary "$TEST_NAME"
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all_tests
fi
