#!/usr/bin/env bash

# KGSM Autostart Commands Tests
#
# Test Type: UNIT
# Target: commands/autostart.sh - CLI interface for boot auto-start
#
# Tests the command surface: help, usage, unknown-command and missing-argument
# handling, and the "requires the watchdog daemon" guard. The success path (which
# needs a live daemon) is covered by the routing unit test (test_autostart_routing)
# and the live deploy validation; here the watchdog is forced to look absent (via a
# bogus socket path) so behavior is deterministic even on a host where a real
# kgsm-watchdog is running.

readonly TEST_NAME="autostart_commands"
readonly MODULE="$KGSM_ROOT/commands/autostart.sh"

function setup_file() {
  log_test_step "Setting up autostart commands tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "autostart.sh module should exist"
  assert_file_executable "$MODULE" "autostart.sh should be executable"

  log_test_step "Test environment validated"
}

# Point every invocation at a socket that cannot exist, so __watchdog_available is
# deterministically false regardless of any real daemon on the host.
function setup() {
  export KGSM_WATCHDOG_SOCKET="/tmp/kgsm-autostart-test-absent-$$-${RANDOM}.sock"
}

function teardown() {
  unset KGSM_WATCHDOG_SOCKET
}

# =============================================================================
# HELP / USAGE
# =============================================================================

function test_help_renders() {
  log_test_step "help renders the autostart usage"

  local output
  output=$("$MODULE" help 2>&1)
  assert_equals 0 "$?" "help should exit 0"
  assert_contains "$output" "Boot Auto-start" "help should describe the feature"
  assert_contains "$output" "enable" "help should list the enable command"
  assert_contains "$output" "disable" "help should list the disable command"
}

function test_no_command_shows_usage_and_errors() {
  log_test_step "no command shows usage and exits non-zero"

  local output exit_code
  output=$("$MODULE" 2>&1)
  exit_code=$?
  assert_not_equals 0 "$exit_code" "no command should be an error"
  assert_contains "$output" "Usage" "should show usage text"
}

function test_unknown_command_errors() {
  log_test_step "unknown command is rejected"

  "$MODULE" bogus-command > /dev/null 2>&1
  assert_not_equals 0 "$?" "an unknown command should exit non-zero"
}

# =============================================================================
# ARGUMENT VALIDATION
# =============================================================================

function test_enable_missing_instance_errors() {
  log_test_step "enable without an instance errors"

  "$MODULE" enable > /dev/null 2>&1
  assert_not_equals 0 "$?" "enable with no instance should exit non-zero"
}

function test_disable_missing_instance_errors() {
  log_test_step "disable without an instance errors"

  "$MODULE" disable > /dev/null 2>&1
  assert_not_equals 0 "$?" "disable with no instance should exit non-zero"
}

function test_status_missing_instance_errors() {
  log_test_step "status without an instance errors"

  "$MODULE" status > /dev/null 2>&1
  assert_not_equals 0 "$?" "status with no instance should exit non-zero"
}

# =============================================================================
# WATCHDOG-REQUIRED GUARD (daemon absent)
# =============================================================================

function test_enable_requires_daemon() {
  log_test_step "enable without a reachable daemon fails with a clear message"

  local output exit_code
  output=$("$MODULE" enable 7dtd 2>&1)
  exit_code=$?
  assert_not_equals 0 "$exit_code" "enable should fail when the daemon is absent"
  assert_contains "$output" "watchdog" "should explain that the watchdog is required"
}

function test_disable_requires_daemon() {
  log_test_step "disable without a reachable daemon fails with a clear message"

  local output exit_code
  output=$("$MODULE" disable 7dtd 2>&1)
  exit_code=$?
  assert_not_equals 0 "$exit_code" "disable should fail when the daemon is absent"
  assert_contains "$output" "watchdog" "should explain that the watchdog is required"
}

function test_list_requires_daemon() {
  log_test_step "list without a reachable daemon fails with a clear message"

  local output exit_code
  output=$("$MODULE" list 2>&1)
  exit_code=$?
  assert_not_equals 0 "$exit_code" "list should fail when the daemon is absent"
  assert_contains "$output" "watchdog" "should explain that the watchdog is required"
}
