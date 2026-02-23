#!/usr/bin/env bash

# KGSM File Management Command CLI Tests
#
# Test Type: UNIT
# Target: commands/files.management.sh - CLI interface and argument handling
#
# Tests the CLI interface of files.management.sh including help system,
# error handling for missing/invalid args, and create/remove behavior.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_management_commands"
readonly MODULE="$KGSM_ROOT/commands/files.management.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up files.management commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "files.management.sh module should exist"
  assert_file_executable "$MODULE" "files.management.sh should be executable"

  log_test_step "Test environment validated"
}

# =============================================================================
# HELP SYSTEM TESTS
# =============================================================================

function test_help_top_level() {
  log_test_step "Testing top-level help output"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should succeed"
  assert_contains "$output" "create" "Help should mention create command"
  assert_contains "$output" "remove" "Help should mention remove command"
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "create" "Help output should contain create"
  assert_contains "$output" "remove" "Help output should contain remove"
}

function test_help_create_command() {
  log_test_step "Testing help for create command"

  local output
  output=$("$MODULE" help create 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help create should succeed"
  assert_contains "$output" "Create" "Should show create command help"
}

function test_help_remove_command() {
  log_test_step "Testing help for remove command"

  local output
  output=$("$MODULE" help remove 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help remove should succeed"
  assert_contains "$output" "Remove" "Should show remove command help"
}

function test_help_unknown_command() {
  log_test_step "Testing help for unknown command returns error"

  assert_command_fails "$MODULE help nonexistent_cmd_xyz" \
    "help for unknown command should fail"
}

# =============================================================================
# MISSING ARGUMENT TESTS
# =============================================================================

function test_create_missing_instance() {
  log_test_step "Testing create with missing instance argument"

  assert_command_fails "$MODULE create" \
    "create with no instance should fail"

  local output
  output=$("$MODULE" create 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_remove_missing_instance() {
  log_test_step "Testing remove with missing instance argument"

  assert_command_fails "$MODULE remove" \
    "remove with no instance should fail"

  local output
  output=$("$MODULE" remove 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

# =============================================================================
# INVALID INSTANCE TESTS
# =============================================================================

function test_create_invalid_instance() {
  log_test_step "Testing create with invalid instance name"

  assert_command_fails "$MODULE create nonexistent_instance_xyz_12345" \
    "create with invalid instance should fail"

  local output
  output=$("$MODULE" create nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" "Should show instance not found error"
}

function test_remove_invalid_instance() {
  log_test_step "Testing remove with invalid instance name"

  assert_command_fails "$MODULE remove nonexistent_instance_xyz_12345" \
    "remove with invalid instance should fail"

  local output
  output=$("$MODULE" remove nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" "Should show instance not found error"
}

# =============================================================================
# INVALID OPTIONS TESTS
# =============================================================================

function test_create_invalid_option() {
  log_test_step "Testing create with invalid option"

  assert_command_fails "$MODULE create --unknown-flag" \
    "create with unknown flag should fail"

  local output
  output=$("$MODULE" create --unknown-flag 2>&1 || true)
  assert_contains "$output" "Unknown option" "Should show unknown option error"
}

function test_remove_invalid_option() {
  log_test_step "Testing remove with invalid option"

  assert_command_fails "$MODULE remove --unknown-flag" \
    "remove with unknown flag should fail"

  local output
  output=$("$MODULE" remove --unknown-flag 2>&1 || true)
  assert_contains "$output" "Unknown option" "Should show unknown option error"
}

function test_unknown_command() {
  log_test_step "Testing unknown top-level command"

  assert_command_fails "$MODULE notacommand" \
    "unknown command should fail"

  local output
  output=$("$MODULE" notacommand 2>&1 || true)
  assert_contains "$output" "Unknown command" "Should show unknown command error"
}

function test_no_command() {
  log_test_step "Testing module with no command shows usage"

  local output
  output=$("$MODULE" 2>&1 || true)

  assert_contains "$output" "create" "No-command output should mention create"
}

# =============================================================================
# COMMAND-SPECIFIC HELP FLAGS
# =============================================================================

function test_create_help_flag() {
  log_test_step "Testing create --help flag"

  local output
  output=$("$MODULE" create --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "create --help should succeed"
  assert_contains "$output" "Create" "Should show create help"
}

function test_remove_help_flag() {
  log_test_step "Testing remove --help flag"

  local output
  output=$("$MODULE" remove --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "remove --help should succeed"
  assert_contains "$output" "Remove" "Should show remove help"
}

# =============================================================================
# COMMAND BEHAVIOR WITH VALID INSTANCE
# =============================================================================

function test_create_management_file_with_valid_instance() {
  log_test_step "Testing create command creates management file for valid instance"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output
  output=$("$MODULE" create "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "create on valid instance should succeed"
  assert_contains "$output" "created successfully" "Should show success message"

  # Verify the management file was created
  local instance_config
  instance_config=$("$KGSM_ROOT/commands/instances.sh" info "$instance_name" --field management_file 2>/dev/null || true)
  if [[ -n "$instance_config" ]]; then
    assert_file_exists "$instance_config" "Management file should exist after create"
  fi

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_remove_management_file_with_valid_instance() {
  log_test_step "Testing remove command removes management file for valid instance"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # First create the management file
  "$MODULE" create "$instance_name" 2>/dev/null

  # Now remove it
  local output
  output=$("$MODULE" remove "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "remove on valid instance should succeed"
  assert_contains "$output" "removed successfully" "Should show success message"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_remove_idempotent_when_no_management_file() {
  log_test_step "Testing remove succeeds even when management file does not exist"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Remove without creating the management file first
  local output
  output=$("$MODULE" remove "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "remove should succeed even when no management file exists"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_create_then_remove_management_file() {
  log_test_step "Testing create followed by remove produces clean state"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Create
  "$MODULE" create "$instance_name" 2>/dev/null
  local create_exit=$?
  assert_equals 0 "$create_exit" "create should succeed"

  # Remove
  "$MODULE" remove "$instance_name" 2>/dev/null
  local remove_exit=$?
  assert_equals 0 "$remove_exit" "remove should succeed after create"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting files.management commands tests"

  setup_test

  # Help system
  test_help_top_level
  test_help_flag
  test_help_create_command
  test_help_remove_command
  test_help_unknown_command

  # Missing arguments
  test_create_missing_instance
  test_remove_missing_instance

  # Invalid instances
  test_create_invalid_instance
  test_remove_invalid_instance

  # Invalid options
  test_create_invalid_option
  test_remove_invalid_option
  test_unknown_command
  test_no_command

  # Command-specific help flags
  test_create_help_flag
  test_remove_help_flag

  # Command behavior with valid instance
  test_create_management_file_with_valid_instance
  test_remove_management_file_with_valid_instance
  test_remove_idempotent_when_no_management_file
  test_create_then_remove_management_file

  log_test_step "files.management commands tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All files.management commands tests passed"
  else
    fail_test "Some files.management commands tests failed"
  fi
}

main "$@"
