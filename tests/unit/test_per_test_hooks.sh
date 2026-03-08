#!/usr/bin/env bash

# KGSM Per-Test Hooks Tests
#
# Test Type: UNIT
# Target: execution.common.sh per-test setup() and teardown() hook behavior
#
# Validates that setup() runs before each test_* function and teardown() runs
# after each test_* function, using counter files to track invocation counts.
#
# NOTE: Do NOT add a main() function or "main "$@"" invocation.
# The framework auto-discovers test_* functions and calls them automatically.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="per_test_hooks"

# Counter files initialized by setup_test(), incremented by setup()/teardown()
SETUP_COUNTER_FILE=""
TEARDOWN_COUNTER_FILE=""

# =============================================================================
# PER-TEST HOOKS
# =============================================================================

function setup() {
  local count
  count=$(<"$SETUP_COUNTER_FILE")
  echo "$(( count + 1 ))" > "$SETUP_COUNTER_FILE"
}

function teardown() {
  local count
  count=$(<"$TEARDOWN_COUNTER_FILE")
  echo "$(( count + 1 ))" > "$TEARDOWN_COUNTER_FILE"
}

# =============================================================================
# TEST LIFECYCLE
# =============================================================================

function setup_test() {
  log_test_step "Setting up per-test hooks tests"

  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  SETUP_COUNTER_FILE="${KGSM_TEST_SANDBOX}/test_setup_counter_$$"
  TEARDOWN_COUNTER_FILE="${KGSM_TEST_SANDBOX}/test_teardown_counter_$$"

  echo "0" > "$SETUP_COUNTER_FILE"
  echo "0" > "$TEARDOWN_COUNTER_FILE"

  assert_file_exists "$SETUP_COUNTER_FILE" "Setup counter file should be created"
  assert_file_exists "$TEARDOWN_COUNTER_FILE" "Teardown counter file should be created"

  log_test_step "Per-test hooks test environment validated"
}

function cleanup_test() {
  rm -f "$SETUP_COUNTER_FILE" "$TEARDOWN_COUNTER_FILE"
}

# =============================================================================
# TEST: setup() called before first test, teardown() not yet called
# =============================================================================

function test_first_setup_called_teardown_not_yet() {
  log_test_step "Verifying setup() called before first test, teardown() not yet called"

  local setup_count
  setup_count=$(<"$SETUP_COUNTER_FILE")
  assert_equals "1" "$setup_count" \
    "setup() should have been called exactly once before the first test"

  local teardown_count
  teardown_count=$(<"$TEARDOWN_COUNTER_FILE")
  assert_equals "0" "$teardown_count" \
    "teardown() should not have been called before the first test completes"
}

# =============================================================================
# TEST: setup() called again for second test, teardown() called once after first
# =============================================================================

function test_second_setup_and_first_teardown_called() {
  log_test_step "Verifying setup()/teardown() state before second test"

  local setup_count
  setup_count=$(<"$SETUP_COUNTER_FILE")
  assert_equals "2" "$setup_count" \
    "setup() should have been called twice (once before each of the first two tests)"

  local teardown_count
  teardown_count=$(<"$TEARDOWN_COUNTER_FILE")
  assert_equals "1" "$teardown_count" \
    "teardown() should have been called once (after the first test completed)"
}

# =============================================================================
# TEST: cumulative counts are correct for third test
# =============================================================================

function test_third_verifies_cumulative_hook_counts() {
  log_test_step "Verifying cumulative hook execution counts for third test"

  local setup_count
  setup_count=$(<"$SETUP_COUNTER_FILE")
  assert_equals "3" "$setup_count" \
    "setup() should have been called three times total (once before each test)"

  local teardown_count
  teardown_count=$(<"$TEARDOWN_COUNTER_FILE")
  assert_equals "2" "$teardown_count" \
    "teardown() should have been called twice (after first and second test)"
}

# =============================================================================
# TEST: setup() and teardown() are optional (design verification)
# =============================================================================

function test_hooks_are_optional() {
  log_test_step "Verifying setup() and teardown() are optional hooks"

  # The framework checks 'declare -f setup' and 'declare -f teardown' before
  # calling them. A test file that does not define these functions runs without
  # error. Since both hooks ARE defined in this file, we verify the framework
  # correctly invoked them by confirming the counters are non-zero.
  local setup_count
  setup_count=$(<"$SETUP_COUNTER_FILE")
  assert_greater_than "$setup_count" "0" \
    "setup() should have been called at least once, confirming hooks are recognised"

  local teardown_count
  teardown_count=$(<"$TEARDOWN_COUNTER_FILE")
  assert_greater_than "$teardown_count" "0" \
    "teardown() should have been called at least once, confirming hooks are recognised"
}

# =============================================================================
# TEST: setup_test() ran exactly once and counter files are still present
# =============================================================================

function test_file_level_setup_test_ran_once() {
  log_test_step "Verifying setup_test() ran once and created the counter files"

  # Counter files must exist — they are only created in setup_test().
  # If setup_test() had not run (or run more than once and clobbered state),
  # earlier tests would have failed. Presence of both files confirms a single
  # successful setup_test() invocation.
  assert_file_exists "$SETUP_COUNTER_FILE" \
    "Setup counter file must exist (created by setup_test)"
  assert_file_exists "$TEARDOWN_COUNTER_FILE" \
    "Teardown counter file must exist (created by setup_test)"

  # By this point (5th test) setup() should have been called 5 times.
  local setup_count
  setup_count=$(<"$SETUP_COUNTER_FILE")
  assert_equals "5" "$setup_count" \
    "setup() should have been called five times — once before each test function"
}
