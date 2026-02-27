#!/usr/bin/env bash

# KGSM Systemd Command CLI Tests
#
# Test Type: UNIT
# Target: commands/files.systemd.sh - CLI interface and argument handling
#
# Tests the CLI interface of files.systemd.sh including help system,
# error handling for missing/invalid args.
#
# Notes:
# - enable/disable operations require systemd (daemon-reload) and root/sudo
# - Success path tests are skipped unless root or passwordless sudo is available

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_systemd_commands"
readonly MODULE="$KGSM_ROOT/commands/files.systemd.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up files.systemd commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "files.systemd.sh module should exist"
  assert_file_executable "$MODULE" "files.systemd.sh should be executable"

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
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "enable" "Help output should contain enable"
  assert_contains "$output" "disable" "Help output should contain disable"
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
# VALID INSTANCE - SYSTEMD OPERATIONS (require systemd/root, may be skipped)
# =============================================================================

function test_enable_on_valid_instance_requires_systemd() {
  log_test_step "Testing enable command fails gracefully without systemd access"

  # Skip if we have root or passwordless sudo (success path not tested here)
  if [[ "$EUID" -eq 0 ]] || sudo -n systemctl daemon-reload 2>/dev/null; then
    skip_test "Skipping - system has systemd access; this test validates non-privileged failure"
    return
  fi

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # enable should fail due to systemd access requirement
  "$MODULE" enable "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" "enable without systemd access should fail"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_disable_on_valid_instance_no_systemd_files() {
  log_test_step "Testing disable on instance with no systemd files configured"

  # disable with no systemd files configured should succeed early
  # (logic returns EC_SUCCESS_SYSTEMD_DISABLED when no files configured)
  # Skip if we can't guarantee daemon-reload behavior
  if [[ "$EUID" -ne 0 ]] && ! sudo -n systemctl daemon-reload 2>/dev/null; then
    skip_test "Skipping - requires root or passwordless sudo for this code path"
    return
  fi

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # A freshly created instance has no systemd files configured; disable should succeed
  local output
  output=$("$MODULE" disable "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "disable on instance with no systemd files should succeed"
  assert_contains "$output" "disabled successfully" "Should show success message"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

