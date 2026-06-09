#!/usr/bin/env bash

# KGSM <TEST_DESCRIPTION> Tests
#
# Test Type: <UNIT|INTEGRATION|E2E>
# Target: <what this tests - module, workflow, or interaction>
#
# Template Usage:
# 1. Copy to appropriate directory:
#    - Unit tests:        tests/unit/test_<module>_<logic|commands>.sh
#    - Integration tests: tests/integration/test_<module1>_<module2>_integration.sh
#    - E2E tests:         tests/e2e/test_<workflow>_e2e.sh
# 2. Replace <PLACEHOLDERS> with actual values
# 3. Implement test functions (each starting with log_test_step)
# 4. Run: ./tests/run.sh --pattern <test_name>
#
# NOTE: Do NOT add a main() function or "main "$@"" invocation.
# The framework auto-discovers test_* functions and calls them automatically.
# The framework also calls setup_test() before tests and print_assert_summary() after.
# Per-test hooks: setup() runs before EACH test_*() function, teardown() runs after each.

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="<test_name>"

# Optional: Module/file references for unit/integration tests
# readonly MODULE="$KGSM_ROOT/commands/<module>.sh"
# readonly HANDLER="$KGSM_ROOT/commands/handlers/<module>.sh"

# Optional: Test configuration for E2E tests
# readonly WAIT_TIMEOUT=120
# readonly PORT_CHECK_INTERVAL=5

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up <test_name> tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Unit test setup: Source handler modules
  # local handler="$KGSM_ROOT/commands/handlers/<module>.sh"
  # assert_file_exists "$handler" "Handler should exist"
  # source "$handler"

  # Command test setup: Verify module exists
  # assert_file_exists "$MODULE" "Module should exist"
  # assert_file_executable "$MODULE" "Module should be executable"

  # Integration/E2E setup: Check dependencies
  # require_steamcmd  # Uncomment if needed
  # require_docker    # Uncomment if needed

  log_test_step "Test environment validated"
}

# Optional: setup() is called by the framework BEFORE EACH test_*() function.
# Use for per-test resource creation, state reset, creating temp directories, etc.
# function setup() {
#   log_test_step "Per-test setup"
#   # Create test-specific resources here
# }

# Optional: teardown() is called by the framework AFTER EACH test_*() function.
# Runs even if the test fails. Failures here do not affect the test result.
# Use for per-test cleanup: removing temp files, restoring config, etc.
# function teardown() {
#   log_test_step "Per-test cleanup"
#   # Clean up test-specific resources here
# }

# =============================================================================
# EXAMPLE TEST PATTERNS
# =============================================================================

# Pattern: Logic layer test (tests pure __logic_* functions)
function test_logic_operation_success() {
  log_test_step "Testing __logic_<operation> with valid parameters"

  # Setup
  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")

  # Execute logic function
  __logic_<operation> "$instance"
  local exit_code=$?

  # Assert exit code
  assert_equals "$EC_SUCCESS_<EVENT>" "$exit_code" "Should return success event code"

  # Cleanup
  remove_test_instance "$instance"
}

# Pattern: Command layer test (tests CLI interface)
function test_command_execution() {
  log_test_step "Testing '<command>' command"

  # Setup
  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")

  # Execute command
  assert_command_succeeds "$MODULE <command> $instance" \
    "Command should succeed"

  # Verify output
  local output
  output=$("$MODULE" "<command>" "$instance" 2>&1)
  assert_contains "$output" "success" \
    "Output should contain success message"

  # Cleanup
  remove_test_instance "$instance"
}

# Pattern: Error handling test
function test_error_handling() {
  log_test_step "Testing error handling for invalid input"

  # Execute with invalid input
  assert_command_fails "$MODULE <command> invalid_xyz" \
    "Should fail with invalid input"

  # Verify error message
  local output
  output=$("$MODULE" "<command>" "invalid_xyz" 2>&1 || true)
  assert_contains "$output" "error\|invalid\|failed" \
    "Should show error message"
}

# Pattern: Integration workflow test
function test_workflow_integration() {
  log_test_step "Testing workflow: <module1> → <module2>"

  # Step 1: Execute first operation
  local result1
  result1=$("$MODULE1" "<command>" "<args>" 2>&1)
  assert_not_null "$result1" "First operation should produce result"

  # Step 2: Execute second operation using first result
  assert_command_succeeds "$MODULE2 <command> $result1" \
    "Second operation should succeed with first result"

  # Verify final state
  assert_file_exists "$KGSM_ROOT/expected/result" \
    "Expected result should exist"
}

# Pattern: Complete E2E workflow test
function test_complete_workflow() {
  log_test_step "Testing complete workflow: create → configure → start → stop → remove"

  local instance
  instance=$(generate_test_id)

  # Create
  local created
  created=$("$KGSM_ROOT/commands/instances.sh" create factorio --name "$instance" 2>&1)
  assert_not_null "$created" "Instance should be created"

  # Configure (directories, files, etc.)
  assert_command_succeeds "$KGSM_ROOT/commands/directories.sh create --instance $created" \
    "Directories should be created"
  assert_command_succeeds "$KGSM_ROOT/commands/files.sh create --instance $created" \
    "Files should be created"

  # Start
  assert_command_succeeds "$KGSM_ROOT/commands/lifecycle.sh start $created" \
    "Instance should start"

  # Verify running
  sleep 2
  assert_command_succeeds "$KGSM_ROOT/commands/lifecycle.sh is-active $created" \
    "Instance should be active"

  # Stop
  assert_command_succeeds "$KGSM_ROOT/commands/lifecycle.sh stop $created" \
    "Instance should stop"

  # Remove
  assert_command_succeeds "$KGSM_ROOT/commands/files.sh remove --instance $created" \
    "Files should be removed"
  assert_command_succeeds "$KGSM_ROOT/commands/directories.sh remove --instance $created" \
    "Directories should be removed"
  assert_command_succeeds "$KGSM_ROOT/commands/instances.sh remove $created" \
    "Instance should be removed"
}

# Optional: cleanup_test() is called by the framework after all tests complete
# function teardown_file() {
#   # Clean up any resources created during testing
# }

# Hook execution order:
# 1. setup_test()    - once per file (environment validation)
# 2. setup()         - before EACH test_*() function
# 3. test_*()        - the test function
# 4. teardown()      - after EACH test_*() function
# 5. cleanup_test()  - once per file (final cleanup)
