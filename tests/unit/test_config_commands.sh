#!/usr/bin/env bash

# KGSM Configuration Commands Unit Tests
#
# Test Type: UNIT
# Target: commands/config.sh CLI interface
#
# Tests the individual CLI commands exposed by commands/config.sh,
# complementing the integration tests in tests/integration/test_config_commands.sh.
# Integration tests cover: merge, rollback, diff, validate via kgsm.sh.
# These unit tests cover: set, get, list, help, error handling via commands/config.sh.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="config_commands"
readonly MODULE="$KGSM_ROOT/commands/config.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up config commands unit tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "commands/config.sh should exist"
  assert_file_executable "$MODULE" "commands/config.sh should be executable"

  # Ensure a valid config file exists in the sandbox
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
  fi

  log_test_step "Config commands unit test environment validated"
}

# =============================================================================
# TEST: help - No Arguments Shows General Usage
# =============================================================================

function test_help_no_args() {
  log_test_step "Testing 'help' with no arguments shows usage"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help should exit 0"
  assert_contains "$output" "Usage" "help output should contain 'Usage'"
  assert_contains "$output" "set" "help output should list 'set' command"
  assert_contains "$output" "get" "help output should list 'get' command"
  assert_contains "$output" "list" "help output should list 'list' command"
  assert_contains "$output" "validate" "help output should list 'validate' command"
}

# =============================================================================
# TEST: help - Per-Command Help
# =============================================================================

function test_help_set_command() {
  log_test_step "Testing 'help set' shows set usage"

  local output
  output=$("$MODULE" help set 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help set should exit 0"
  assert_contains "$output" "set" "help set output should describe 'set'"
}

function test_help_get_command() {
  log_test_step "Testing 'help get' shows get usage"

  local output
  output=$("$MODULE" help get 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help get should exit 0"
  assert_contains "$output" "get" "help get output should describe 'get'"
}

function test_help_list_command() {
  log_test_step "Testing 'help list' shows list usage"

  local output
  output=$("$MODULE" help list 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help list should exit 0"
  assert_contains "$output" "list" "help list output should describe 'list'"
}

function test_help_reset_command() {
  log_test_step "Testing 'help reset' shows reset usage"

  local output
  output=$("$MODULE" help reset 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help reset should exit 0"
  assert_contains "$output" "reset" "help reset output should describe 'reset'"
}

function test_help_validate_command() {
  log_test_step "Testing 'help validate' shows validate usage"

  local output
  output=$("$MODULE" help validate 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help validate should exit 0"
  assert_contains "$output" "validate" "help validate output should describe 'validate'"
}

function test_help_edit_command() {
  log_test_step "Testing 'help edit' shows edit usage"

  local output
  output=$("$MODULE" help edit 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help edit should exit 0"
  assert_contains "$output" "edit" "help edit output should describe 'edit'"
}

function test_help_unknown_command() {
  log_test_step "Testing 'help unknown_xyz' fails with invalid arg"

  local exit_code
  "$MODULE" help unknown_xyz_cmd 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "help with unknown command should return EC_INVALID_ARG"
}

# =============================================================================
# TEST: list - Outputs Configuration Values
# =============================================================================

function test_list_outputs_config() {
  log_test_step "Testing 'list' outputs configuration key=value pairs"

  local output
  output=$("$MODULE" list 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "list should exit 0"
  assert_not_null "$output" "list should produce output"
  # At minimum the output should contain some key=value pairs
  assert_contains "$output" "=" "list output should contain key=value pairs"
}

# =============================================================================
# TEST: list --json - Outputs JSON Format
# =============================================================================

function test_list_json_format() {
  log_test_step "Testing 'list --json' outputs JSON format"

  if ! command -v jq &>/dev/null; then
    log_test_step "jq not available, skipping JSON list test"
    return 0
  fi

  local output
  output=$("$MODULE" list --json 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "list --json should exit 0"
  assert_not_null "$output" "list --json should produce output"
  # Valid JSON should contain braces or brackets
  assert_contains "$output" "{" "list --json output should contain JSON object"
}

# =============================================================================
# TEST: get - Returns Value for Valid Key
# =============================================================================

function test_get_valid_key() {
  log_test_step "Testing 'get enable_logging' returns a value"

  local output
  output=$("$MODULE" get enable_logging 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "get with valid key should exit 0"
  assert_not_null "$output" "get should return a non-empty value"
}

# =============================================================================
# TEST: get - Fails for Nonexistent Key
# =============================================================================

function test_get_nonexistent_key() {
  log_test_step "Testing 'get nonexistent_key_xyz' fails"

  local exit_code
  "$MODULE" get nonexistent_key_xyz 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_KEY_NOT_FOUND" "get with unknown key should return EC_KEY_NOT_FOUND"
}

# =============================================================================
# TEST: get - Fails Without Arguments
# =============================================================================

function test_get_missing_arg() {
  log_test_step "Testing 'get' with no key argument fails"

  local exit_code
  "$MODULE" get 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_MISSING_ARG" "get with no args should return EC_MISSING_ARG"
}

# =============================================================================
# TEST: set - Succeeds for Valid Key/Value
# =============================================================================

function test_set_valid_key_value() {
  log_test_step "Testing 'set enable_logging=true' succeeds"

  local exit_code
  "$MODULE" set enable_logging=true 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_CONFIG_SET" "set with valid key=value should return EC_SUCCESS_CONFIG_SET"

  # Verify value was written to config file
  assert_command_succeeds "grep -q 'enable_logging=true' '$CONFIG_FILE'" \
    "Config file should contain updated value"
}

# =============================================================================
# TEST: set - Fails for Invalid/Unknown Key
# =============================================================================

function test_set_invalid_key() {
  log_test_step "Testing 'set nonexistent_key_xyz=value' fails"

  local exit_code
  "$MODULE" set nonexistent_key_xyz=somevalue 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_KEY_NOT_FOUND" "set with unknown key should return EC_KEY_NOT_FOUND"
}

# =============================================================================
# TEST: set - Fails Without Arguments
# =============================================================================

function test_set_missing_arg() {
  log_test_step "Testing 'set' with no key=value argument fails"

  local exit_code
  "$MODULE" set 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_MISSING_ARG" "set with no args should return EC_MISSING_ARG"
}

# =============================================================================
# TEST: set - Fails With Invalid Format (no = sign)
# =============================================================================

function test_set_invalid_format() {
  log_test_step "Testing 'set invalidformat' (no = sign) fails"

  local exit_code
  "$MODULE" set invalidformatnoequals 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "set with invalid format should return EC_INVALID_ARG"
}

# =============================================================================
# TEST: validate - Passes on Clean Config
# =============================================================================

function test_validate_clean_config() {
  log_test_step "Testing 'validate' passes on default config"

  # Reset to default config so validation has a known-good state
  cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"

  local exit_code
  "$MODULE" validate 2>/dev/null
  exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_CONFIG_VALIDATED" "validate should return EC_SUCCESS_CONFIG_VALIDATED on clean config"
}

# =============================================================================
# TEST: Error Handling - Invalid Command
# =============================================================================

function test_invalid_command() {
  log_test_step "Testing invalid command returns EC_INVALID_ARG"

  local output exit_code
  output=$("$MODULE" totally_invalid_cmd 2>&1)
  exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "invalid command should return EC_INVALID_ARG"
  assert_contains "$output" "Invalid command" "output should mention invalid command"
}

# =============================================================================
# TEST: Error Handling - No Command
# =============================================================================

function test_no_command() {
  log_test_step "Testing invocation with no command fails"

  local exit_code
  "$MODULE" 2>/dev/null
  exit_code=$?

  assert_not_equals "$exit_code" "0" "no command should not exit 0"
}

