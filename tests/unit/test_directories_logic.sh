#!/usr/bin/env bash

# KGSM Directory Logic Handler Unit Tests
#
# Tests all __logic_* and utility functions from commands/handlers/directories.sh
# Covers directory creation, removal, permission handling, and config updates.

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="directories_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/directories.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up directory logic tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Directory handler should exist"

  # Source the handler
  source "$HANDLER"

  # Verify required error codes are defined
  assert_not_null "$EC_SUCCESS" "EC_SUCCESS should be defined"
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FAILED_MKDIR" "EC_FAILED_MKDIR should be defined"
  assert_not_null "$EC_FAILED_RM" "EC_FAILED_RM should be defined"
  assert_not_null "$EC_FAILED_TOUCH" "EC_FAILED_TOUCH should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_FAILED_UPDATE_CONFIG" "EC_FAILED_UPDATE_CONFIG should be defined"
  assert_not_null "$EC_SUCCESS_DIRECTORIES_CREATED" "EC_SUCCESS_DIRECTORIES_CREATED should be defined"
  assert_not_null "$EC_SUCCESS_DIRECTORIES_REMOVED" "EC_SUCCESS_DIRECTORIES_REMOVED should be defined"

  # Verify functions are exported
  assert_function_exists "__create_dir" "__create_dir should be exported"
  assert_function_exists "__create_file" "__create_file should be exported"
  assert_function_exists "__logic_create_directories" "__logic_create_directories should be exported"
  assert_function_exists "__logic_remove_directories" "__logic_remove_directories should be exported"

  # Verify module loaded guard
  assert_not_null "$KGSM_LOGIC_DIRECTORIES_LOADED" "Module should be loaded"

  log_test_step "Directory logic test environment validated"
}

# =============================================================================
# __create_dir() TESTS
# =============================================================================

function test_create_dir_with_default_permissions() {
  log_test_step "Testing __create_dir with default permissions"

  local test_dir="$KGSM_TEST_SANDBOX/test_dir_default_$$"

  __create_dir "$test_dir"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "Should return EC_SUCCESS"
  assert_dir_exists "$test_dir" "Directory should be created"

  # Check permissions (755)
  local perms
  perms=$(stat -c "%a" "$test_dir")
  assert_equals "$perms" "755" "Should have 755 permissions"

  # Cleanup
  rm -rf "$test_dir"
}

function test_create_dir_with_custom_permissions() {
  log_test_step "Testing __create_dir with custom permissions"

  local test_dir="$KGSM_TEST_SANDBOX/test_dir_custom_$$"

  __create_dir "$test_dir" "700"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "Should return EC_SUCCESS"
  assert_dir_exists "$test_dir" "Directory should be created"

  # Check permissions (700)
  local perms
  perms=$(stat -c "%a" "$test_dir")
  assert_equals "$perms" "700" "Should have 700 permissions"

  # Cleanup
  rm -rf "$test_dir"
}

function test_create_dir_idempotent() {
  log_test_step "Testing __create_dir idempotency"

  local test_dir="$KGSM_TEST_SANDBOX/test_dir_idempotent_$$"

  # Create first time
  __create_dir "$test_dir"
  assert_equals "$?" "$EC_SUCCESS" "First call should succeed"

  # Create second time (should also succeed)
  __create_dir "$test_dir"
  assert_equals "$?" "$EC_SUCCESS" "Second call should succeed (idempotent)"

  assert_dir_exists "$test_dir" "Directory should still exist"

  # Cleanup
  rm -rf "$test_dir"
}

function test_create_dir_empty_parameter() {
  log_test_step "Testing __create_dir with empty parameter"

  __create_dir "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
}

function test_create_dir_permission_denied() {
  log_test_step "Testing __create_dir with unwritable parent directory"

  local test_parent="$KGSM_TEST_SANDBOX/test_parent_$$"
  local test_dir="$test_parent/subdir"

  # Create parent and make it unwritable
  mkdir -p "$test_parent"
  chmod 000 "$test_parent"

  __create_dir "$test_dir" 2>/dev/null
  local exit_code=$?

  # Restore permissions immediately
  chmod 755 "$test_parent"

  assert_equals "$exit_code" "$EC_FAILED_MKDIR" "Should return EC_FAILED_MKDIR"
  assert_dir_not_exists "$test_dir" "Directory should not be created"

  # Cleanup
  rm -rf "$test_parent"
}

# =============================================================================
# __create_file() TESTS
# =============================================================================

function test_create_file_with_default_permissions() {
  log_test_step "Testing __create_file with default permissions"

  local test_file="$KGSM_TEST_SANDBOX/test_file_default_$$"

  __create_file "$test_file"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "Should return EC_SUCCESS"
  assert_file_exists "$test_file" "File should be created"

  # Check permissions (644)
  local perms
  perms=$(stat -c "%a" "$test_file")
  assert_equals "$perms" "644" "Should have 644 permissions"

  # Cleanup
  rm -f "$test_file"
}

function test_create_file_with_custom_permissions() {
  log_test_step "Testing __create_file with custom permissions"

  local test_file="$KGSM_TEST_SANDBOX/test_file_custom_$$"

  __create_file "$test_file" "600"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "Should return EC_SUCCESS"
  assert_file_exists "$test_file" "File should be created"

  # Check permissions (600)
  local perms
  perms=$(stat -c "%a" "$test_file")
  assert_equals "$perms" "600" "Should have 600 permissions"

  # Cleanup
  rm -f "$test_file"
}

function test_create_file_idempotent() {
  log_test_step "Testing __create_file idempotency"

  local test_file="$KGSM_TEST_SANDBOX/test_file_idempotent_$$"

  # Create first time
  __create_file "$test_file"
  assert_equals "$?" "$EC_SUCCESS" "First call should succeed"

  # Create second time (should also succeed)
  __create_file "$test_file"
  assert_equals "$?" "$EC_SUCCESS" "Second call should succeed (idempotent)"

  assert_file_exists "$test_file" "File should still exist"

  # Cleanup
  rm -f "$test_file"
}

function test_create_file_empty_parameter() {
  log_test_step "Testing __create_file with empty parameter"

  __create_file "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
}

function test_create_file_permission_denied() {
  log_test_step "Testing __create_file with unwritable parent directory"

  local test_parent="$KGSM_TEST_SANDBOX/test_parent_file_$$"
  local test_file="$test_parent/testfile"

  # Create parent and make it unwritable
  mkdir -p "$test_parent"
  chmod 000 "$test_parent"

  __create_file "$test_file" 2>/dev/null
  local exit_code=$?

  # Restore permissions immediately
  chmod 755 "$test_parent"

  assert_equals "$exit_code" "$EC_FAILED_TOUCH" "Should return EC_FAILED_TOUCH"
  assert_file_not_exists "$test_file" "File should not be created"

  # Cleanup
  rm -rf "$test_parent"
}

# =============================================================================
# __logic_create_directories() TESTS
# =============================================================================

function test_create_directories_success() {
  log_test_step "Testing __logic_create_directories with valid parameters"

  local instance_name="test-instance-$$"
  local working_dir="$KGSM_TEST_SANDBOX/test_instance_$$"
  local config_file="$KGSM_TEST_SANDBOX/test_config_$$.ini"

  # Create config file
  touch "$config_file"

  __logic_create_directories "$instance_name" "$config_file" "$working_dir"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_DIRECTORIES_CREATED" \
    "Should return EC_SUCCESS_DIRECTORIES_CREATED"

  # Verify all 7 directories were created (working_dir + 6 subdirs, incl. the
  # player-presence events dir bind-mounted into container instances).
  assert_dir_exists "$working_dir" "working_dir should be created"
  assert_dir_exists "$working_dir/backups" "backups_dir should be created"
  assert_dir_exists "$working_dir/install" "install_dir should be created"
  assert_dir_exists "$working_dir/saves" "saves_dir should be created"
  assert_dir_exists "$working_dir/temp" "temp_dir should be created"
  assert_dir_exists "$working_dir/logs" "logs_dir should be created"
  assert_dir_exists "$working_dir/events" "events_dir should be created"

  # Verify config file was updated
  assert_file_contains "$config_file" "working_dir" "Config should contain working_dir"
  assert_file_contains "$config_file" "backups_dir" "Config should contain backups_dir"
  assert_file_contains "$config_file" "install_dir" "Config should contain install_dir"
  assert_file_contains "$config_file" "saves_dir" "Config should contain saves_dir"
  assert_file_contains "$config_file" "temp_dir" "Config should contain temp_dir"
  assert_file_contains "$config_file" "logs_dir" "Config should contain logs_dir"
  assert_file_contains "$config_file" "events_dir" "Config should contain events_dir"

  # Cleanup
  rm -rf "$working_dir" "$config_file"
}

function test_create_directories_idempotent() {
  log_test_step "Testing __logic_create_directories idempotency"

  local instance_name="test-instance-idempotent-$$"
  local working_dir="$KGSM_TEST_SANDBOX/test_instance_idempotent_$$"
  local config_file="$KGSM_TEST_SANDBOX/test_config_idempotent_$$.ini"

  # Create config file
  touch "$config_file"

  # Create first time
  __logic_create_directories "$instance_name" "$config_file" "$working_dir"
  assert_equals "$?" "$EC_SUCCESS_DIRECTORIES_CREATED" "First call should succeed"

  # Create second time (should also succeed)
  __logic_create_directories "$instance_name" "$config_file" "$working_dir"
  assert_equals "$?" "$EC_SUCCESS_DIRECTORIES_CREATED" "Second call should succeed (idempotent)"

  # Verify directories still exist
  assert_dir_exists "$working_dir" "working_dir should still exist"
  assert_dir_exists "$working_dir/backups" "backups_dir should still exist"

  # Cleanup
  rm -rf "$working_dir" "$config_file"
}

function test_create_directories_missing_instance_name() {
  log_test_step "Testing __logic_create_directories with missing instance_name"

  local config_file="$KGSM_TEST_SANDBOX/test_config_missing_$$.ini"
  local working_dir="$KGSM_TEST_SANDBOX/test_working_missing_$$"

  touch "$config_file"

  __logic_create_directories "" "$config_file" "$working_dir" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"

  # Cleanup
  rm -f "$config_file"
}

function test_create_directories_missing_config_file() {
  log_test_step "Testing __logic_create_directories with missing config_file"

  local instance_name="test-instance-$$"
  local working_dir="$KGSM_TEST_SANDBOX/test_working_$$"

  __logic_create_directories "$instance_name" "" "$working_dir" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
}

function test_create_directories_missing_working_dir() {
  log_test_step "Testing __logic_create_directories with missing working_dir"

  local instance_name="test-instance-$$"
  local config_file="$KGSM_TEST_SANDBOX/test_config_$$.ini"

  touch "$config_file"

  __logic_create_directories "$instance_name" "$config_file" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"

  # Cleanup
  rm -f "$config_file"
}

function test_create_directories_relative_path() {
  log_test_step "Testing __logic_create_directories with relative path"

  local instance_name="test-instance-$$"
  local config_file="$KGSM_TEST_SANDBOX/test_config_relative_$$.ini"
  local working_dir="relative/path/test"

  touch "$config_file"

  __logic_create_directories "$instance_name" "$config_file" "$working_dir" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_CONFIG" "Should return EC_INVALID_CONFIG for relative path"

  # Cleanup
  rm -f "$config_file"
}

function test_create_directories_nonexistent_config() {
  log_test_step "Testing __logic_create_directories with non-existent config file"

  local instance_name="test-instance-$$"
  local config_file="$KGSM_TEST_SANDBOX/nonexistent_config_$$.ini"
  local working_dir="$KGSM_TEST_SANDBOX/test_working_$$"

  # Do NOT create the config file

  __logic_create_directories "$instance_name" "$config_file" "$working_dir" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_FAILED_UPDATE_CONFIG" \
    "Should return EC_FAILED_UPDATE_CONFIG for non-existent config"

  # Cleanup (working_dir might have been created)
  rm -rf "$working_dir"
}

function test_create_directories_unwritable_config() {
  log_test_step "Testing __logic_create_directories with unwritable config file"

  local instance_name="test-instance-$$"
  local config_file="$KGSM_TEST_SANDBOX/test_config_readonly_$$.ini"
  local working_dir="$KGSM_TEST_SANDBOX/test_working_readonly_$$"

  # Create config and make it read-only
  touch "$config_file"
  chmod 444 "$config_file"

  __logic_create_directories "$instance_name" "$config_file" "$working_dir" 2>/dev/null
  local exit_code=$?

  # Restore permissions immediately
  chmod 644 "$config_file"

  assert_equals "$exit_code" "$EC_FAILED_UPDATE_CONFIG" \
    "Should return EC_FAILED_UPDATE_CONFIG for read-only config"

  # Cleanup
  rm -rf "$working_dir" "$config_file"
}

function test_create_directories_unwritable_parent() {
  log_test_step "Testing __logic_create_directories with unwritable parent directory"

  local instance_name="test-instance-$$"
  local config_file="$KGSM_TEST_SANDBOX/test_config_unwritable_$$.ini"
  local parent_dir="$KGSM_TEST_SANDBOX/unwritable_parent_$$"
  local working_dir="$parent_dir/test_working"

  touch "$config_file"

  # Create parent and make it unwritable
  mkdir -p "$parent_dir"
  chmod 000 "$parent_dir"

  __logic_create_directories "$instance_name" "$config_file" "$working_dir" 2>/dev/null
  local exit_code=$?

  # Restore permissions immediately
  chmod 755 "$parent_dir"

  assert_equals "$exit_code" "$EC_FAILED_MKDIR" \
    "Should return EC_FAILED_MKDIR for unwritable parent"

  # Cleanup
  rm -rf "$parent_dir" "$config_file"
}

# =============================================================================
# __logic_remove_directories() TESTS
# =============================================================================

function test_remove_directories_success() {
  log_test_step "Testing __logic_remove_directories with valid parameters"

  local instance_name="test-instance-$$"
  local working_dir="$KGSM_TEST_SANDBOX/test_instance_remove_$$"

  # Create directory structure
  mkdir -p "$working_dir"/{backups,install,saves,temp,logs}
  echo "test data" > "$working_dir/testfile"

  __logic_remove_directories "$instance_name" "$working_dir"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_DIRECTORIES_REMOVED" \
    "Should return EC_SUCCESS_DIRECTORIES_REMOVED"
  assert_dir_not_exists "$working_dir" "working_dir should be removed"
}

function test_remove_directories_with_nested_content() {
  log_test_step "Testing __logic_remove_directories with nested content"

  local instance_name="test-instance-nested-$$"
  local working_dir="$KGSM_TEST_SANDBOX/test_instance_nested_$$"

  # Create complex directory structure
  mkdir -p "$working_dir"/{backups/{daily,weekly},install/{bin,lib},saves/world1}
  echo "data" > "$working_dir/backups/daily/backup1.tar.gz"
  echo "binary" > "$working_dir/install/bin/server"

  __logic_remove_directories "$instance_name" "$working_dir"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_DIRECTORIES_REMOVED" \
    "Should return EC_SUCCESS_DIRECTORIES_REMOVED"
  assert_dir_not_exists "$working_dir" "All nested content should be removed"
}

function test_remove_directories_missing_instance_name() {
  log_test_step "Testing __logic_remove_directories with missing instance_name"

  local working_dir="$KGSM_TEST_SANDBOX/test_working_$$"

  __logic_remove_directories "" "$working_dir" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
}

function test_remove_directories_missing_working_dir() {
  log_test_step "Testing __logic_remove_directories with missing working_dir"

  local instance_name="test-instance-$$"

  __logic_remove_directories "$instance_name" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
}

function test_remove_directories_relative_path() {
  log_test_step "Testing __logic_remove_directories with relative path"

  local instance_name="test-instance-$$"
  local working_dir="relative/path"

  __logic_remove_directories "$instance_name" "$working_dir" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_CONFIG" \
    "Should return EC_INVALID_CONFIG for relative path (safety check)"
}

function test_remove_directories_nonexistent_directory() {
  log_test_step "Testing __logic_remove_directories with non-existent directory"

  local instance_name="test-instance-$$"
  local working_dir="$KGSM_TEST_SANDBOX/nonexistent_dir_$$"

  __logic_remove_directories "$instance_name" "$working_dir" 2>/dev/null
  local exit_code=$?

  # rm -rf on non-existent directory succeeds, so this should return success
  assert_equals "$exit_code" "$EC_SUCCESS_DIRECTORIES_REMOVED" \
    "Should return EC_SUCCESS_DIRECTORIES_REMOVED (rm -rf succeeds on non-existent)"
}
