#!/usr/bin/env bash

# Integration tests for commands/events.sh

# shellcheck disable=SC1091
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="events_module"

function test_events_help() {
  log_step "Testing events help command"

  local module
  module=$(__find_command events.sh)

  # Test main help
  assert_command_succeeds "$module help" "Events help should succeed"

  # Test command-specific help
  assert_command_succeeds "$module help status" "Status help should succeed"
  assert_command_succeeds "$module help test" "Test help should succeed"
  assert_command_succeeds "$module help emit" "Emit help should succeed"
}

function test_events_emit_validation() {
  log_step "Testing events emit validation"

  local module
  module=$(__find_command events.sh)

  # Test invalid event type
  assert_command_fails "$module emit invalid-event-type myserver" "Should reject invalid event type"

  # Test missing parameters
  assert_command_fails "$module emit instance-version-updated myserver" "Should reject insufficient params"

  # Test missing event type
  assert_command_fails "$module emit" "Should require event type"
}

function test_events_status() {
  log_step "Testing events status command"

  local module
  module=$(__find_command events.sh)

  # Status should always work (just shows current state)
  assert_command_succeeds "$module status" "Status command should succeed"
}

function test_events_socket_commands() {
  log_step "Testing events socket delegation"

  local module
  module=$(__find_command events.sh)

  # Test delegation to socket module
  assert_command_succeeds "$module socket help" "Socket help should work"
  assert_command_succeeds "$module socket status" "Socket status should work"
}

function test_events_webhook_commands() {
  log_step "Testing events webhook delegation"

  local module
  module=$(__find_command events.sh)

  # Test delegation to webhook module
  assert_command_succeeds "$module webhook help" "Webhook help should work"
  assert_command_succeeds "$module webhook status" "Webhook status should work"
}

function test_events_test_command() {
  log_step "Testing events test command"

  local module
  module=$(__find_command events.sh)

  # Test with no transports enabled (should fail gracefully)
  export config_enable_event_broadcasting=false
  export config_enable_webhook_events=false

  assert_command_fails "$module test all" "Test should fail when no transports enabled"
}

function test_socket_module_commands() {
  log_step "Testing socket module commands"

  local module
  module=$(__find_command events.socket.sh)

  # Test command structure
  assert_command_succeeds "$module help" "Socket module help should work"
  assert_command_succeeds "$module status" "Socket module status should work"
  assert_command_succeeds "$module help enable" "Socket enable help should work"
  assert_command_succeeds "$module help disable" "Socket disable help should work"
  assert_command_succeeds "$module help test" "Socket test help should work"
}

function test_webhook_module_commands() {
  log_step "Testing webhook module commands"

  local module
  module=$(__find_command events.webhook.sh)

  # Test command structure
  assert_command_succeeds "$module help" "Webhook module help should work"
  assert_command_succeeds "$module status" "Webhook module status should work"
  assert_command_succeeds "$module help enable" "Webhook enable help should work"
  assert_command_succeeds "$module help configure" "Webhook configure help should work"
}

function main() {
  log_test "Starting events module integration tests"

  # Run all tests
  test_events_help
  test_events_emit_validation
  test_events_status
  test_events_socket_commands
  test_events_webhook_commands
  test_events_test_command
  test_socket_module_commands
  test_webhook_module_commands

  log_test "Events module integration tests completed"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All events module integration tests passed"
  else
    fail_test "Some events module integration tests failed"
  fi
}

# Execute main function
main "$@"
