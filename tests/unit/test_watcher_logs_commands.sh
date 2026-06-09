#!/usr/bin/env bash

# KGSM Watcher Logs Command CLI Tests
#
# Test Type: UNIT
# Target: commands/watcher.logs.sh - CLI interface and argument handling
#
# Tests the CLI interface of watcher.logs.sh including help system,
# error handling for missing/invalid args, and non-blocking status commands.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="watcher_logs_commands"
readonly MODULE="$KGSM_ROOT/commands/watcher.logs.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up watcher logs commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "watcher.logs.sh module should exist"
  assert_file_executable "$MODULE" "watcher.logs.sh should be executable"

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
  assert_contains "$output" "watch" "Help should mention watch command"
  assert_contains "$output" "test" "Help should mention test command"
  assert_contains "$output" "status" "Help should mention status command"
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "watch" "Help output should contain watch"
}

function test_help_watch_command() {
  log_test_step "Testing help for watch command"

  local output
  output=$("$MODULE" help watch 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help watch should succeed"
  assert_contains "$output" "Watch" "Should show watch command help"
}

function test_help_test_command() {
  log_test_step "Testing help for test command"

  local output
  output=$("$MODULE" help test 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help test should succeed"
  assert_contains "$output" "Test" "Should show test command help"
}

function test_help_status_command() {
  log_test_step "Testing help for status command"

  local output
  output=$("$MODULE" help status 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help status should succeed"
  assert_contains "$output" "Status" "Should show status command help"
}

function test_help_unknown_command() {
  log_test_step "Testing help for unknown command returns error"

  assert_command_fails "$MODULE help nonexistent_cmd_xyz" \
    "help for unknown command should fail"
}

# =============================================================================
# NO-COMMAND TESTS
# =============================================================================

function test_no_command() {
  log_test_step "Testing module with no command shows usage"

  local output
  output=$("$MODULE" 2>&1 || true)

  assert_contains "$output" "watch" "No-command output should mention watch"
}

# =============================================================================
# MISSING ARGUMENT TESTS
# =============================================================================

function test_watch_missing_instance() {
  log_test_step "Testing watch with missing instance argument"

  assert_command_fails "$MODULE watch" \
    "watch with no instance should fail"

  local output
  output=$("$MODULE" watch 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_test_missing_instance() {
  log_test_step "Testing test with missing instance argument"

  assert_command_fails "$MODULE test" \
    "test with no instance should fail"

  local output
  output=$("$MODULE" test 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_status_missing_instance() {
  log_test_step "Testing status with missing instance argument"

  assert_command_fails "$MODULE status" \
    "status with no instance should fail"

  local output
  output=$("$MODULE" status 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

# =============================================================================
# INVALID INSTANCE TESTS
# =============================================================================

function test_watch_invalid_instance() {
  log_test_step "Testing watch with invalid instance name"

  assert_command_fails "$MODULE watch nonexistent_instance_xyz_12345" \
    "watch with invalid instance should fail"
}

function test_test_invalid_instance() {
  log_test_step "Testing test with invalid instance name"

  assert_command_fails "$MODULE test nonexistent_instance_xyz_12345" \
    "test with invalid instance should fail"
}

function test_status_invalid_instance() {
  log_test_step "Testing status with invalid instance name"

  assert_command_fails "$MODULE status nonexistent_instance_xyz_12345" \
    "status with invalid instance should fail"
}

# =============================================================================
# INVALID OPTIONS / UNKNOWN COMMANDS
# =============================================================================

function test_watch_extra_argument() {
  log_test_step "Testing watch with extra unknown argument"

  assert_command_fails "$MODULE watch someinstance --unknown-flag" \
    "watch with unknown flag should fail"
}

function test_unknown_command() {
  log_test_step "Testing unknown top-level command"

  assert_command_fails "$MODULE notacommand" \
    "unknown command should fail"

  local output
  output=$("$MODULE" notacommand 2>&1 || true)
  assert_contains "$output" "Unknown command" "Should show unknown command error"
}

# =============================================================================
# COMMAND-SPECIFIC HELP FLAGS
# =============================================================================

function test_watch_help_flag() {
  log_test_step "Testing watch --help flag"

  local output
  output=$("$MODULE" watch --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "watch --help should succeed"
  assert_contains "$output" "Watch" "Should show watch help"
}

function test_test_help_flag() {
  log_test_step "Testing test --help flag"

  local output
  output=$("$MODULE" test --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "test --help should succeed"
  assert_contains "$output" "Test" "Should show test help"
}

function test_status_help_flag() {
  log_test_step "Testing status --help flag"

  local output
  output=$("$MODULE" status --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "status --help should succeed"
  assert_contains "$output" "Status" "Should show status help"
}

# =============================================================================
# STATUS COMMAND WITH VALID INSTANCE
# =============================================================================

function test_status_on_valid_instance() {
  log_test_step "Testing status on a valid instance succeeds and shows info"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output
  output=$("$MODULE" status "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "status on valid instance should succeed"
  assert_not_null "$output" "status should produce output"
  assert_contains "$output" "$instance_name" "status output should mention instance name"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_status_shows_pattern_info() {
  log_test_step "Testing status shows log pattern configuration info"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output
  output=$("$MODULE" status "$instance_name" 2>&1)

  assert_contains "$output" "Pattern" "status should mention Pattern"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST COMMAND WITH VALID INSTANCE (NO PATTERN CONFIGURED)
# =============================================================================

function test_test_on_instance_without_log_pattern() {
  log_test_step "Testing 'test' on instance without startup_success_regex configured"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # factorio has no startup_success_regex configured in default blueprint
  # The test command should fail because the pattern would not be found or log doesn't exist
  "$MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" "test on instance without log pattern should fail"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

