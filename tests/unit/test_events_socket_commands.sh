#!/usr/bin/env bash

# KGSM Events Socket Commands Tests
#
# Test Type: UNIT
# Target: commands/events.socket.sh CLI interface
#
# Tests the command-level interface for the events.socket.sh module:
# - Help system (--help, -h, help command, subcommand help)
# - No arguments behavior
# - status command (always succeeds)
# - enable command (socat available in test environment)
# - disable command
# - test command when socket transport is disabled
# - emit command argument validation
# - Invalid/unknown command handling

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="events_socket_commands"
readonly MODULE="$KGSM_ROOT/commands/events.socket.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up events.socket.sh command tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "events.socket.sh command module should exist"
  assert_file_executable "$MODULE" "events.socket.sh command module should be executable"

  log_test_step "Events socket command test environment validated"
}

# =============================================================================
# help / usage TESTS
# =============================================================================

function test_help_no_args() {
  log_test_step "Testing: no arguments shows usage and exits non-zero"

  assert_command_fails "$MODULE" \
    "No arguments should fail"

  assert_command_output "$MODULE 2>&1 || true" "Usage" \
    "No arguments should show Usage"
}

function test_help_flag() {
  log_test_step "Testing: --help flag shows usage and succeeds"

  assert_command_succeeds "$MODULE --help" \
    "--help should succeed"

  assert_command_output "$MODULE --help" "Usage" \
    "--help output should contain Usage"
}

function test_help_h_flag() {
  log_test_step "Testing: -h flag shows usage and succeeds"

  assert_command_succeeds "$MODULE -h" \
    "-h should succeed"

  assert_command_output "$MODULE -h" "Usage" \
    "-h output should contain Usage"
}

function test_help_command() {
  log_test_step "Testing: help command shows usage and succeeds"

  assert_command_succeeds "$MODULE help" \
    "help command should succeed"

  assert_command_output "$MODULE help" "Commands" \
    "help output should contain Commands section"
}

function test_help_lists_commands() {
  log_test_step "Testing: help output lists all socket transport commands"

  local output
  output=$("$MODULE" help 2>&1)

  assert_contains "$output" "enable" \
    "help output should mention enable command"
  assert_contains "$output" "disable" \
    "help output should mention disable command"
  assert_contains "$output" "test" \
    "help output should mention test command"
  assert_contains "$output" "status" \
    "help output should mention status command"
  assert_contains "$output" "emit" \
    "help output should mention emit command"
}

function test_help_mentions_socat() {
  log_test_step "Testing: help output mentions socat dependency"

  local output
  output=$("$MODULE" help 2>&1)

  assert_contains "$output" "socat" \
    "help output should mention socat as required dependency"
}

function test_help_enable_subcommand() {
  log_test_step "Testing: help enable shows enable-specific help"

  assert_command_succeeds "$MODULE help enable" \
    "help enable should succeed"

  assert_command_output "$MODULE help enable" "Enable" \
    "help enable output should contain Enable"
}

function test_help_disable_subcommand() {
  log_test_step "Testing: help disable shows disable-specific help"

  assert_command_succeeds "$MODULE help disable" \
    "help disable should succeed"

  assert_command_output "$MODULE help disable" "Disable" \
    "help disable output should contain Disable"
}

function test_help_test_subcommand() {
  log_test_step "Testing: help test shows test-specific help"

  assert_command_succeeds "$MODULE help test" \
    "help test should succeed"

  assert_command_output "$MODULE help test" "Test" \
    "help test output should contain Test"
}

function test_help_status_subcommand() {
  log_test_step "Testing: help status shows status-specific help"

  assert_command_succeeds "$MODULE help status" \
    "help status should succeed"

  assert_command_output "$MODULE help status" "Status" \
    "help status output should contain Status"
}

function test_help_unknown_subcommand_fails() {
  log_test_step "Testing: help with unknown subcommand fails"

  assert_command_fails "$MODULE help nonexistent_command_xyz" \
    "help with unknown subcommand should fail"
}

function test_help_unknown_subcommand_error_message() {
  log_test_step "Testing: help with unknown subcommand shows error"

  assert_command_output "$MODULE help nonexistent_command_xyz 2>&1 || true" "Unknown command" \
    "help with unknown subcommand should show 'Unknown command' error"
}

# =============================================================================
# status TESTS
# =============================================================================

function test_status_succeeds() {
  log_test_step "Testing: status command always succeeds"

  assert_command_succeeds "$MODULE status" \
    "status should succeed regardless of configuration"
}

function test_status_shows_transport_header() {
  log_test_step "Testing: status output shows transport status header"

  assert_command_output "$MODULE status" "Unix Domain Socket" \
    "status output should contain 'Unix Domain Socket' header"
}

function test_status_shows_configuration_section() {
  log_test_step "Testing: status output shows Configuration section"

  assert_command_output "$MODULE status" "Configuration" \
    "status output should contain Configuration section"
}

function test_status_shows_dependencies_section() {
  log_test_step "Testing: status output shows Dependencies section"

  assert_command_output "$MODULE status" "Dependencies" \
    "status output should contain Dependencies section"
}

function test_status_shows_socket_file_info() {
  log_test_step "Testing: status output shows socket file location"

  assert_command_output "$MODULE status" "Socket file" \
    "status output should show socket file location"
}

function test_status_help_flag() {
  log_test_step "Testing: status --help shows status help and succeeds"

  assert_command_succeeds "$MODULE help status" \
    "help status should succeed"

  assert_command_output "$MODULE help status" "Displays" \
    "status help should describe what it displays"
}

# =============================================================================
# enable TESTS
# =============================================================================

function test_enable_help_flag() {
  log_test_step "Testing: enable --help shows enable help and succeeds"

  assert_command_succeeds "$MODULE enable --help" \
    "enable --help should succeed"

  assert_command_output "$MODULE enable --help" "Enable" \
    "enable --help output should contain Enable"
}

function test_enable_with_socat_succeeds() {
  log_test_step "Testing: enable shows enabling message when socat is available"

  # socat is available in the test environment
  if ! command -v socat >/dev/null 2>&1; then
    skip_test "socat not available - skipping enable output test"
    return
  fi

  # enable shows the enabling message then returns EC_SUCCESS_CONFIG_SET (240)
  assert_command_output "$MODULE enable 2>&1 || true" "Enabling Unix Domain Socket" \
    "enable output should show 'Enabling Unix Domain Socket' message"
}

function test_enable_output_mentions_socket_file() {
  log_test_step "Testing: enable mentions the socket transport type"

  if ! command -v socat >/dev/null 2>&1; then
    skip_test "socat not available - skipping enable output test"
    return
  fi

  assert_command_output "$MODULE enable 2>&1 || true" "event transport" \
    "enable output should mention 'event transport'"
}

# =============================================================================
# disable TESTS
# =============================================================================

function test_disable_help_flag() {
  log_test_step "Testing: disable --help shows disable help and succeeds"

  assert_command_succeeds "$MODULE disable --help" \
    "disable --help should succeed"

  assert_command_output "$MODULE disable --help" "Disable" \
    "disable --help output should contain Disable"
}

function test_disable_succeeds() {
  log_test_step "Testing: disable command shows disabling message"

  # disable returns EC_SUCCESS_CONFIG_SET (240), not 0.
  # Verify by checking output contains the disabling message.
  assert_command_output "$MODULE disable 2>&1 || true" "Disabling Unix Domain Socket" \
    "disable output should show 'Disabling Unix Domain Socket' message"
}

function test_disable_shows_success_message() {
  log_test_step "Testing: disable command shows transport type in output"

  assert_command_output "$MODULE disable 2>&1 || true" "event transport" \
    "disable output should mention 'event transport'"
}

# =============================================================================
# test SUBCOMMAND TESTS
# =============================================================================

function test_test_help_flag() {
  log_test_step "Testing: test --help shows test help and succeeds"

  assert_command_succeeds "$MODULE test --help" \
    "test --help should succeed"

  assert_command_output "$MODULE test --help" "Test" \
    "test --help output should contain Test"
}

function test_test_when_disabled_fails() {
  log_test_step "Testing: test command fails when socket transport is disabled"

  # Ensure socket transport is disabled first (default state in sandbox)
  "$MODULE" disable >/dev/null 2>&1 || true

  assert_command_fails "$MODULE test" \
    "test should fail when socket transport is disabled"
}

function test_test_when_disabled_shows_error() {
  log_test_step "Testing: test command shows error message when disabled"

  "$MODULE" disable >/dev/null 2>&1 || true

  assert_command_output "$MODULE test 2>&1 || true" "not enabled" \
    "test should show 'not enabled' error when socket transport is disabled"
}

# =============================================================================
# emit TESTS
# =============================================================================

function test_emit_no_payload_fails() {
  log_test_step "Testing: emit with no payload fails"

  assert_command_fails "$MODULE emit" \
    "emit with no payload should fail"
}

function test_emit_no_payload_error_message() {
  log_test_step "Testing: emit with no payload shows error message"

  assert_command_output "$MODULE emit 2>&1 || true" "payload" \
    "emit with no payload should mention payload in error"
}

# =============================================================================
# UNKNOWN COMMAND TESTS
# =============================================================================

function test_unknown_command_fails() {
  log_test_step "Testing: unknown command fails with non-zero exit code"

  assert_command_fails "$MODULE unknown_command_xyz" \
    "Unknown command should fail"
}

function test_unknown_command_error_message() {
  log_test_step "Testing: unknown command shows error message"

  assert_command_output "$MODULE unknown_command_xyz 2>&1 || true" "Unknown command" \
    "Unknown command should show 'Unknown command' error"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting events.socket.sh command tests"

  setup_test

  # Help / usage tests
  test_help_no_args
  test_help_flag
  test_help_h_flag
  test_help_command
  test_help_lists_commands
  test_help_mentions_socat
  test_help_enable_subcommand
  test_help_disable_subcommand
  test_help_test_subcommand
  test_help_status_subcommand
  test_help_unknown_subcommand_fails
  test_help_unknown_subcommand_error_message

  # status tests
  test_status_succeeds
  test_status_shows_transport_header
  test_status_shows_configuration_section
  test_status_shows_dependencies_section
  test_status_shows_socket_file_info
  test_status_help_flag

  # enable tests
  test_enable_help_flag
  test_enable_with_socat_succeeds
  test_enable_output_mentions_socket_file

  # disable tests
  test_disable_help_flag
  test_disable_succeeds
  test_disable_shows_success_message

  # test subcommand tests
  test_test_help_flag
  test_test_when_disabled_fails
  test_test_when_disabled_shows_error

  # emit tests
  test_emit_no_payload_fails
  test_emit_no_payload_error_message

  # unknown command tests
  test_unknown_command_fails
  test_unknown_command_error_message

  log_test_step "Events socket command tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All events.socket.sh command tests passed"
  else
    fail_test "Some events.socket.sh command tests failed"
  fi
}

main "$@"
