#!/usr/bin/env bash

# KGSM Files UFW Command CLI Tests
#
# Test Type: UNIT
# Target: commands/files.ufw.sh - CLI interface and argument handling
#
# Tests the CLI interface of files.ufw.sh including help system,
# error handling for missing/invalid args, and behavior on valid instances.
#
# Note: Tests that require UFW installed or root access are either
# skipped or test only up to the point of the external dependency.
# The disable path on an unconfigured instance succeeds without UFW.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_ufw_commands"
readonly MODULE="$KGSM_ROOT/commands/files.ufw.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up files.ufw commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "files.ufw.sh module should exist"
  assert_file_executable "$MODULE" "files.ufw.sh should be executable"

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
  assert_contains "$output" "enable" "Help should mention enable command"
  assert_contains "$output" "disable" "Help should mention disable command"
  assert_contains "$output" "UFW" "Help should mention UFW"
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "enable" "Help output should contain enable"
}

function test_help_enable_command() {
  log_test_step "Testing help for enable command"

  local output
  output=$("$MODULE" help enable 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help enable should succeed"
  assert_contains "$output" "Enable" "Should show enable command help"
}

function test_help_disable_command() {
  log_test_step "Testing help for disable command"

  local output
  output=$("$MODULE" help disable 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help disable should succeed"
  assert_contains "$output" "Disable" "Should show disable command help"
}

function test_help_unknown_command() {
  log_test_step "Testing help for unknown command returns error"

  assert_command_fails "$MODULE help nonexistent_cmd_xyz" \
    "help for unknown command should fail"
}

# =============================================================================
# MISSING ARGUMENT TESTS
# =============================================================================

function test_enable_missing_instance() {
  log_test_step "Testing enable with missing instance argument"

  assert_command_fails "$MODULE enable" \
    "enable with no instance should fail"

  local output
  output=$("$MODULE" enable 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_disable_missing_instance() {
  log_test_step "Testing disable with missing instance argument"

  assert_command_fails "$MODULE disable" \
    "disable with no instance should fail"

  local output
  output=$("$MODULE" disable 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

# =============================================================================
# INVALID INSTANCE TESTS
# =============================================================================

function test_enable_invalid_instance() {
  log_test_step "Testing enable with invalid instance name"

  assert_command_fails "$MODULE enable nonexistent_instance_xyz_12345" \
    "enable with invalid instance should fail"

  local output
  output=$("$MODULE" enable nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" "Should show instance not found error"
}

function test_disable_invalid_instance() {
  log_test_step "Testing disable with invalid instance name"

  assert_command_fails "$MODULE disable nonexistent_instance_xyz_12345" \
    "disable with invalid instance should fail"

  local output
  output=$("$MODULE" disable nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" "Should show instance not found error"
}

# =============================================================================
# INVALID OPTIONS TESTS
# =============================================================================

function test_enable_invalid_option() {
  log_test_step "Testing enable with invalid option"

  assert_command_fails "$MODULE enable --unknown-flag" \
    "enable with unknown flag should fail"

  local output
  output=$("$MODULE" enable --unknown-flag 2>&1 || true)
  assert_contains "$output" "Unknown option" "Should show unknown option error"
}

function test_disable_invalid_option() {
  log_test_step "Testing disable with invalid option"

  assert_command_fails "$MODULE disable --unknown-flag" \
    "disable with unknown flag should fail"

  local output
  output=$("$MODULE" disable --unknown-flag 2>&1 || true)
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

  assert_contains "$output" "enable" "No-command output should mention enable"
}

# =============================================================================
# COMMAND-SPECIFIC HELP FLAGS
# =============================================================================

function test_enable_help_flag() {
  log_test_step "Testing enable --help flag"

  local output
  output=$("$MODULE" enable --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "enable --help should succeed"
  assert_contains "$output" "Enable" "Should show enable help"
}

function test_disable_help_flag() {
  log_test_step "Testing disable --help flag"

  local output
  output=$("$MODULE" disable --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "disable --help should succeed"
  assert_contains "$output" "Disable" "Should show disable help"
}

# =============================================================================
# VALID INSTANCE BEHAVIOR TESTS
# =============================================================================

function test_disable_on_fresh_instance() {
  log_test_step "Testing disable on fresh instance with no UFW rule configured"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # A fresh instance has no firewall_rule_file configured,
  # so disable should succeed (no-op path, no UFW interaction needed)
  local output
  output=$("$MODULE" disable "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "disable on fresh instance (no UFW rule configured) should succeed"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_enable_on_instance_fails_without_ufw() {
  log_test_step "Testing enable on valid instance fails when UFW not available"

  # Skip if UFW is installed and available (test environment has UFW)
  if command -v ufw &>/dev/null; then
    skip_test "UFW is available in this environment - skipping unavailability test"
    return
  fi

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Enable requires UFW - should fail when UFW is unavailable
  "$MODULE" enable "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" "enable should fail when UFW is not available"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting files.ufw commands tests"

  setup_test

  # Help system
  test_help_top_level
  test_help_flag
  test_help_enable_command
  test_help_disable_command
  test_help_unknown_command

  # Missing arguments
  test_enable_missing_instance
  test_disable_missing_instance

  # Invalid instances
  test_enable_invalid_instance
  test_disable_invalid_instance

  # Invalid options
  test_enable_invalid_option
  test_disable_invalid_option
  test_unknown_command
  test_no_command

  # Command-specific help flags
  test_enable_help_flag
  test_disable_help_flag

  # Valid instance behavior
  test_disable_on_fresh_instance
  test_enable_on_instance_fails_without_ufw

  log_test_step "Files.ufw commands tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All files.ufw commands tests passed"
  else
    fail_test "Some files.ufw commands tests failed"
  fi
}

main "$@"
