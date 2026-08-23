#!/usr/bin/env bash

# KGSM Lifecycle Command CLI Tests
#
# Test Type: UNIT
# Target: commands/lifecycle.sh - CLI interface and argument handling
#
# Tests the CLI interface of lifecycle.sh including help system,
# error handling for missing/invalid args, and behavior on stopped instances.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="lifecycle_commands"
readonly MODULE="$KGSM_ROOT/commands/lifecycle.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up lifecycle commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "lifecycle.sh module should exist"
  assert_file_executable "$MODULE" "lifecycle.sh should be executable"

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
  assert_contains "$output" "stop" "Help should mention stop command"
  assert_contains "$output" "restart" "Help should mention restart command"
  assert_contains "$output" "status" "Help should mention status command"
  assert_contains "$output" "is-active" "Help should mention is-active command"
  assert_contains "$output" "logs" "Help should mention logs command"
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

function test_help_stop_command() {
  log_test_step "Testing help for stop command"

  local output
  output=$("$MODULE" help stop 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help stop should succeed"
  assert_contains "$output" "Stop" "Should show stop command help"
}

function test_help_restart_command() {
  log_test_step "Testing help for restart command"

  local output
  output=$("$MODULE" help restart 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help restart should succeed"
  assert_contains "$output" "Restart" "Should show restart command help"
}

function test_help_status_command() {
  log_test_step "Testing help for status command"

  local output
  output=$("$MODULE" help status 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help status should succeed"
  assert_contains "$output" "Status" "Should show status command help"
}

function test_help_is_active_command() {
  log_test_step "Testing help for is-active command"

  local output
  output=$("$MODULE" help is-active 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help is-active should succeed"
  assert_contains "$output" "Is-Active" "Should show is-active command help"
}

function test_help_logs_command() {
  log_test_step "Testing help for logs command"

  local output
  output=$("$MODULE" help logs 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help logs should succeed"
  assert_contains "$output" "Logs" "Should show logs command help"
}

function test_help_unknown_command() {
  log_test_step "Testing help for unknown command returns error"

  assert_command_fails "$MODULE help nonexistent_cmd_xyz" \
    "help for unknown command should fail"
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

function test_stop_missing_instance() {
  log_test_step "Testing stop with missing instance argument"

  assert_command_fails "$MODULE stop" \
    "stop with no instance should fail"

  local output
  output=$("$MODULE" stop 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_restart_missing_instance() {
  log_test_step "Testing restart with missing instance argument"

  assert_command_fails "$MODULE restart" \
    "restart with no instance should fail"

  local output
  output=$("$MODULE" restart 2>&1 || true)
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

function test_is_active_missing_instance() {
  log_test_step "Testing is-active with missing instance argument"

  assert_command_fails "$MODULE is-active" \
    "is-active with no instance should fail"

  local output
  output=$("$MODULE" is-active 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_logs_missing_instance() {
  log_test_step "Testing logs with missing instance argument"

  assert_command_fails "$MODULE logs" \
    "logs with no instance should fail"

  local output
  output=$("$MODULE" logs 2>&1 || true)
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

function test_stop_invalid_instance() {
  log_test_step "Testing stop with invalid instance name"

  assert_command_fails "$MODULE stop nonexistent_instance_xyz_12345" \
    "stop with invalid instance should fail"
}

function test_restart_invalid_instance() {
  log_test_step "Testing restart with invalid instance name"

  assert_command_fails "$MODULE restart nonexistent_instance_xyz_12345" \
    "restart with invalid instance should fail"
}

function test_status_invalid_instance() {
  log_test_step "Testing status with invalid instance name"

  assert_command_fails "$MODULE status nonexistent_instance_xyz_12345" \
    "status with invalid instance should fail"
}

function test_is_active_invalid_instance() {
  log_test_step "Testing is-active with invalid instance name"

  assert_command_fails "$MODULE is-active nonexistent_instance_xyz_12345" \
    "is-active with invalid instance should fail"
}

function test_logs_invalid_instance() {
  log_test_step "Testing logs with invalid instance name"

  assert_command_fails "$MODULE logs nonexistent_instance_xyz_12345" \
    "logs with invalid instance should fail"
}

# =============================================================================
# INVALID OPTIONS TESTS
# =============================================================================

function test_start_invalid_option() {
  log_test_step "Testing start with invalid option"

  assert_command_fails "$MODULE start --unknown-flag" \
    "start with unknown flag should fail"
}

function test_stop_invalid_option() {
  log_test_step "Testing stop with invalid option"

  assert_command_fails "$MODULE stop --unknown-flag" \
    "stop with unknown flag should fail"
}

function test_status_invalid_option() {
  log_test_step "Testing status with invalid option"

  assert_command_fails "$MODULE status --unknown-flag" \
    "status with unknown flag should fail"
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

  # Should produce usage output even though it exits non-zero
  assert_contains "$output" "start" "No-command output should mention start"
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

function test_stop_help_flag() {
  log_test_step "Testing stop --help flag"

  local output
  output=$("$MODULE" stop --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "stop --help should succeed"
  assert_contains "$output" "Stop" "Should show stop help"
}

function test_logs_tail_invalid_value() {
  log_test_step "Testing logs --tail with non-numeric value"

  assert_command_fails "$MODULE logs some_instance --tail notanumber" \
    "logs with non-numeric --tail value should fail"
}

# =============================================================================
# STOPPED INSTANCE BEHAVIOR TESTS
# =============================================================================

function test_is_active_on_stopped_instance() {
  log_test_step "Testing is-active on a stopped instance returns non-zero"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # A freshly created instance is not running, so is-active should fail
  "$MODULE" is-active "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" "is-active on stopped instance should return non-zero"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_status_on_stopped_instance() {
  log_test_step "Testing status on a stopped instance succeeds and shows info"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" 2>/dev/null)

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

function test_status_json_on_stopped_instance() {
  log_test_step "Testing status --json on a stopped instance produces JSON"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output
  output=$("$MODULE" status "$instance_name" --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "status --json on valid instance should succeed"
  assert_contains "$output" "{" "JSON output should contain opening brace"
  assert_contains "$output" "}" "JSON output should contain closing brace"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_status_json_carries_the_library_state() {
  log_test_step "Testing status --json carries library_state whichever verb asked"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # A consumer joins on this field without knowing which verb produced the
  # object, so an entrypoint that omits it hands back an absence that reads as
  # the unknown it is not.
  local shorthand detailed
  shorthand=$("$MODULE" status --json "$instance_name" 2>&1)
  detailed=$("$KGSM_ROOT/commands/instances.sh" --json status "$instance_name" 2>&1)

  assert_equals "online" "$(echo "$shorthand" | jq -r '.library_state')" \
    "status --json should report the library the instance is placed in"
  assert_equals \
    "$(echo "$detailed" | jq -r '.library_state')" \
    "$(echo "$shorthand" | jq -r '.library_state')" \
    "Both status verbs should report the same library state"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

