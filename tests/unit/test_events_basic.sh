#!/usr/bin/env bash

# =============================================================================
# KGSM Events Module - Basic Test Suite
# =============================================================================
#
# This test provides basic coverage of the events.sh module to verify
# the testing framework works correctly with the events module.
#
# Test Coverage:
# ✓ Module existence and basic functionality
# ✓ Help command works
# ✓ Status command works
# ✓ Basic error handling
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="events_basic"
readonly EVENTS_MODULE="$KGSM_ROOT/commands/events.sh"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function setup_test() {
  log_test "Setting up basic events module test environment"

  # Basic module existence checks
  assert_file_exists "$EVENTS_MODULE" "Events module should exist"
  assert_file_executable "$EVENTS_MODULE" "Events module should be executable"

  log_test "Test environment setup complete"
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function test_module_basics() {
  log_step "Testing basic module functionality"

  # Test help command
  assert_command_succeeds "$EVENTS_MODULE --help" "events.sh --help should work"

  # Test status command
  assert_command_succeeds "$EVENTS_MODULE --status" "events.sh --status should work"

  # Test that module fails without arguments
  assert_command_fails "$EVENTS_MODULE" "events.sh without arguments should fail"

  log_test "Basic module functionality validated"
}

function test_help_content() {
  log_step "Testing help content"

  local help_output
  help_output=$("$EVENTS_MODULE" --help 2>&1)

  assert_contains "$help_output" "Event System Management" "Help should contain module description"
  assert_contains "$help_output" "--status" "Help should document --status command"
  assert_contains "$help_output" "--socket" "Help should document --socket subcommand"
  assert_contains "$help_output" "--webhook" "Help should document --webhook subcommand"

  log_test "Help content validated"
}

function test_status_content() {
  log_step "Testing status content"

  local status_output
  status_output=$("$EVENTS_MODULE" --status 2>&1)

  assert_contains "$status_output" "KGSM Event System Status" "Status should show system status header"
  assert_contains "$status_output" "Unix Domain Socket Transport" "Status should show socket transport section"
  assert_contains "$status_output" "HTTP Webhook Transport" "Status should show webhook transport section"

  log_test "Status content validated"
}

function test_error_handling() {
  log_step "Testing error handling"

  # Test invalid arguments
  assert_command_fails "$EVENTS_MODULE --invalid-argument" "Should reject invalid arguments"

  # Test missing subcommands
  assert_command_fails "$EVENTS_MODULE --socket" "Should reject --socket without subcommand"
  assert_command_fails "$EVENTS_MODULE --webhook" "Should reject --webhook without subcommand"

  log_test "Error handling validated"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting basic events module tests"

  # Initialize test environment
  setup_test

  # Run tests
  test_module_basics
  test_help_content
  test_status_content
  test_error_handling

  log_test "Basic events module tests completed successfully"

  # Print final results and determine exit code using framework
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All basic events module tests completed successfully"
  else
    fail_test "Some basic events module tests failed"
  fi
}

# Execute main function
main "$@"
