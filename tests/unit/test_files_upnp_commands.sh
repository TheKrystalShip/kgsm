#!/usr/bin/env bash

# KGSM Files UPnP Command CLI Tests
#
# Test Type: UNIT
# Target: commands/files.upnp.sh - CLI interface and argument handling
#
# Tests the CLI interface of files.upnp.sh including help system,
# error handling for missing/invalid args, and behavior on valid instances.
#
# Note: UPnP integration is config-only - no external tools or router
# communication occurs during enable/disable. Both commands should succeed
# on valid instances without any external dependencies.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_upnp_commands"
readonly MODULE="$KGSM_ROOT/commands/files.upnp.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up files.upnp commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "files.upnp.sh module should exist"
  assert_file_executable "$MODULE" "files.upnp.sh should be executable"

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
  assert_contains "$output" "UPnP" "Help should mention UPnP"
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

function test_enable_on_valid_instance() {
  log_test_step "Testing enable on valid instance succeeds (config-only operation)"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # UPnP enable is config-only and should succeed without any external deps
  local output
  output=$("$MODULE" enable "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "enable on valid instance should succeed (config-only)"
  assert_contains "$output" "enabled successfully" "Should show success message"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_disable_on_valid_instance() {
  log_test_step "Testing disable on valid instance succeeds (config-only operation)"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # UPnP disable is config-only and should succeed without any external deps
  local output
  output=$("$MODULE" disable "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "disable on valid instance should succeed (config-only)"
  assert_contains "$output" "disabled successfully" "Should show success message"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_enable_then_disable_on_valid_instance() {
  log_test_step "Testing enable followed by disable on valid instance"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Enable
  "$MODULE" enable "$instance_name" 2>/dev/null
  local enable_exit=$?
  assert_equals 0 "$enable_exit" "enable should succeed"

  # Disable
  "$MODULE" disable "$instance_name" 2>/dev/null
  local disable_exit=$?
  assert_equals 0 "$disable_exit" "disable after enable should succeed"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

