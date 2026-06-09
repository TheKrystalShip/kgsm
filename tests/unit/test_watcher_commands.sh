#!/usr/bin/env bash

# KGSM Watcher Command CLI Tests
#
# Test Type: UNIT
# Target: commands/watcher.sh - CLI interface and argument handling
#
# Tests the CLI interface of watcher.sh including help system,
# error handling for missing/invalid args, and non-blocking command behavior.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="watcher_commands"
readonly MODULE="$KGSM_ROOT/commands/watcher.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up watcher commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "watcher.sh module should exist"
  assert_file_executable "$MODULE" "watcher.sh should be executable"

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
  assert_contains "$output" "start" "Help should mention start command"
  assert_contains "$output" "test" "Help should mention test command"
  assert_contains "$output" "status" "Help should mention status command"
  assert_contains "$output" "logs" "Help should mention logs component"
  assert_contains "$output" "ports" "Help should mention ports component"
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "start" "Help output should contain start"
}

function test_help_start_command() {
  log_test_step "Testing help for start command"

  local output
  output=$("$MODULE" help start 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help start should succeed"
  assert_contains "$output" "Start" "Should show start command help"
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

function test_help_logs_component() {
  log_test_step "Testing help for logs component"

  local output
  output=$("$MODULE" help logs 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help logs should succeed"
  assert_contains "$output" "watch" "Logs help should mention watch command"
}

function test_help_ports_component() {
  log_test_step "Testing help for ports component"

  local output
  output=$("$MODULE" help ports 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help ports should succeed"
  assert_contains "$output" "watch" "Ports help should mention watch command"
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

  assert_contains "$output" "start" "No-command output should mention start"
}

# =============================================================================
# MISSING ARGUMENT TESTS
# =============================================================================

function test_start_missing_instance() {
  log_test_step "Testing start with missing instance argument"

  assert_command_fails "$MODULE start" \
    "start with no instance should fail"

  local output
  output=$("$MODULE" start 2>&1 || true)
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

function test_start_invalid_instance() {
  log_test_step "Testing start with invalid instance name"

  assert_command_fails "$MODULE start nonexistent_instance_xyz_12345" \
    "start with invalid instance should fail"
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

function test_start_invalid_option() {
  log_test_step "Testing start with invalid option"

  assert_command_fails "$MODULE start --unknown-flag" \
    "start with unknown flag should fail"
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

function test_start_help_flag() {
  log_test_step "Testing start --help flag"

  local output
  output=$("$MODULE" start --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "start --help should succeed"
  assert_contains "$output" "Start" "Should show start help"
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

function test_status_shows_strategy_info() {
  log_test_step "Testing status shows strategy selection info"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output
  output=$("$MODULE" status "$instance_name" 2>&1)

  assert_contains "$output" "Strategy" "status should mention Strategy"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST COMMAND WITH VALID INSTANCE (NO STRATEGY CONFIGURED)
# =============================================================================

function test_test_on_instance_with_no_strategy() {
  log_test_step "Testing 'test' on instance with no watcher strategy configured"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # factorio has no startup_success_regex or ports in default config
  # so test should fail with no-strategy error
  "$MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" "test on instance with no strategy should fail"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# LOGS/PORTS PASSTHROUGH TESTS
# =============================================================================

function test_logs_passthrough_missing_instance() {
  log_test_step "Testing logs passthrough with missing instance argument"

  assert_command_fails "$MODULE logs watch" \
    "logs watch with no instance should fail"
}

function test_ports_passthrough_missing_instance() {
  log_test_step "Testing ports passthrough with missing instance argument"

  assert_command_fails "$MODULE ports watch" \
    "ports watch with no instance should fail"
}

function test_logs_passthrough_invalid_instance() {
  log_test_step "Testing logs passthrough with invalid instance"

  assert_command_fails "$MODULE logs status nonexistent_xyz_12345" \
    "logs status with invalid instance should fail"
}

function test_ports_passthrough_invalid_instance() {
  log_test_step "Testing ports passthrough with invalid instance"

  assert_command_fails "$MODULE ports status nonexistent_xyz_12345" \
    "ports status with invalid instance should fail"
}

