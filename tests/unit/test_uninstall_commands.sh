#!/usr/bin/env bash

# KGSM Uninstall Commands Tests
#
# Test Type: UNIT
# Target: commands/uninstall.sh - CLI interface and argument handling
#
# Tests the CLI interface of uninstall.sh including help system,
# argument validation, and error handling. Does NOT test actual
# uninstallation workflows to avoid destructive operations.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="uninstall_commands"
readonly MODULE="$KGSM_ROOT/commands/uninstall.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up uninstall commands tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "uninstall.sh module should exist"
  assert_file_executable "$MODULE" "uninstall.sh should be executable"

  log_test_step "Test environment validated"
}

# =============================================================================
# HELP SYSTEM TESTS
# =============================================================================

function test_help_flag() {
  log_test_step "Testing --help flag shows usage"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help should exit 0"
  assert_contains "$output" "instance" "Help should mention instance argument"
  assert_contains "$output" "irreversible" "Help should warn about irreversible operation"
}

function test_help_short_flag() {
  log_test_step "Testing -h flag shows usage"

  local output
  output=$("$MODULE" -h 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "-h should exit 0"
  assert_contains "$output" "Uninstall" "Help should describe the uninstall module"
}

function test_help_command() {
  log_test_step "Testing 'help' command passed to _uninstall shows usage"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should exit 0"
  assert_contains "$output" "instance" "Help should mention instance argument"
}

# =============================================================================
# MISSING ARGUMENT TESTS
# =============================================================================

function test_missing_instance_arg() {
  log_test_step "Testing that missing instance argument returns error"

  assert_command_fails "$MODULE" \
    "Running uninstall.sh with no arguments should fail"

  local output
  output=$("$MODULE" 2>&1 || true)
  assert_contains "$output" "Missing required argument" \
    "Should show missing argument error when no instance provided"
}

# =============================================================================
# INVALID OPTION TESTS
# =============================================================================

function test_unknown_option() {
  log_test_step "Testing that an unknown option flag returns error"

  assert_command_fails "$MODULE --unknown-flag-xyz" \
    "Unknown option flag should cause failure"

  local output
  output=$("$MODULE" --unknown-flag-xyz 2>&1 || true)
  assert_contains "$output" "Unknown option" \
    "Should show unknown option error for unrecognized flag"
}

function test_unknown_dash_option() {
  log_test_step "Testing that a single-dash unknown option returns error"

  assert_command_fails "$MODULE -z" \
    "Unknown single-dash option should cause failure"

  local output
  output=$("$MODULE" -z 2>&1 || true)
  assert_contains "$output" "Unknown option" \
    "Should show unknown option error for unrecognized single-dash flag"
}

# =============================================================================
# INVALID INSTANCE TESTS
# =============================================================================

function test_invalid_instance() {
  log_test_step "Testing that nonexistent instance shows not found error"

  # Note: uninstall.sh validates the instance before the interactive prompt,
  # so this test is safe and will not attempt destructive operations.
  local output
  output=$("$MODULE" nonexistent_instance_xyz_12345 2>&1 || true)

  assert_contains "$output" "not found" \
    "Should report that instance was not found"
}

# =============================================================================
# HELP OUTPUT STRUCTURE TESTS
# =============================================================================

function test_help_contains_warning() {
  log_test_step "Testing help output contains destructive operation warning"

  local output
  output=$("$MODULE" --help 2>&1)

  assert_contains "$output" "Warning" "Help should contain a Warning section"
}

function test_help_contains_examples() {
  log_test_step "Testing help output contains usage examples"

  local output
  output=$("$MODULE" --help 2>&1)

  assert_contains "$output" "Examples" "Help should contain an Examples section"
}

function test_help_contains_usage() {
  log_test_step "Testing help output contains usage line"

  local output
  output=$("$MODULE" --help 2>&1)

  assert_contains "$output" "Usage" "Help should contain a Usage section"
}

