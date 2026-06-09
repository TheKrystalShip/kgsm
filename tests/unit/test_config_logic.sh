#!/usr/bin/env bash

# KGSM Config Logic Unit Tests
#
# Test Type: UNIT
# Target: core/config.sh - Pure logic functions for get/set/validate/list/reset
#
# Covers functions NOT tested by test_config_merge_logic.sh (merge engine),
# test_config_migrations.sh (migration scripts), or test_config_commands.sh
# (CLI interface):
#   - __validate_config_key
#   - __validate_config_value
#   - __get_config_value
#   - __get_config_value_safe
#   - __set_config_value
#   - __get_all_config_keys
#   - __list_config_values
#   - __reset_config
#   - __validate_current_config

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="config_logic"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up config logic tests"

  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$KGSM_ROOT/core/config.sh" "core/config.sh should exist"

  # Source the config module (bootstrap is already loaded by the test runner)
  source "$KGSM_ROOT/core/config.sh"

  # Verify required error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_KEY_NOT_FOUND" "EC_KEY_NOT_FOUND should be defined"
  assert_not_null "$EC_SUCCESS_CONFIG_SET" "EC_SUCCESS_CONFIG_SET should be defined"
  assert_not_null "$EC_SUCCESS_CONFIG_RESET" "EC_SUCCESS_CONFIG_RESET should be defined"
  assert_not_null "$EC_SUCCESS_CONFIG_VALIDATED" "EC_SUCCESS_CONFIG_VALIDATED should be defined"

  # Verify all tested functions are exported
  assert_function_exists "__validate_config_key" "__validate_config_key should be exported"
  assert_function_exists "__validate_config_value" "__validate_config_value should be exported"
  assert_function_exists "__get_config_value" "__get_config_value should be exported"
  assert_function_exists "__get_config_value_safe" "__get_config_value_safe should be exported"
  assert_function_exists "__set_config_value" "__set_config_value should be exported"
  assert_function_exists "__get_all_config_keys" "__get_all_config_keys should be exported"
  assert_function_exists "__list_config_values" "__list_config_values should be exported"
  assert_function_exists "__reset_config" "__reset_config should be exported"
  assert_function_exists "__validate_current_config" "__validate_current_config should be exported"

  # Verify config files are accessible in sandbox
  assert_not_null "$CONFIG_FILE" "CONFIG_FILE should be set"
  assert_not_null "$DEFAULT_CONFIG_FILE" "DEFAULT_CONFIG_FILE should be set"
  assert_file_exists "$CONFIG_FILE" "CONFIG_FILE should exist in sandbox"
  assert_file_exists "$DEFAULT_CONFIG_FILE" "DEFAULT_CONFIG_FILE should exist in sandbox"

  log_test_step "Config logic test environment validated"
}

# =============================================================================
# __validate_config_key() TESTS
# =============================================================================

function test_validate_config_key_empty_arg() {
  log_test_step "Testing __validate_config_key with empty key"

  __validate_config_key "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty key"
}

function test_validate_config_key_unknown_key() {
  log_test_step "Testing __validate_config_key with unknown key"

  __validate_config_key "nonexistent_config_key_xyz" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code" "Should return EC_KEY_NOT_FOUND for unknown key"
}

function test_validate_config_key_valid_key() {
  log_test_step "Testing __validate_config_key with a known valid key"

  # enable_logging is a well-known boolean key in all KGSM configs
  __validate_config_key "enable_logging" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for a valid known key"
}

function test_validate_config_key_valid_integer_key() {
  log_test_step "Testing __validate_config_key with a known integer key"

  __validate_config_key "instance_suffix_length" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for instance_suffix_length key"
}

# =============================================================================
# __validate_config_value() TESTS
# =============================================================================

function test_validate_config_value_empty_key() {
  log_test_step "Testing __validate_config_value with empty key"

  __validate_config_value "" "true" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty key"
}

function test_validate_config_value_boolean_true() {
  log_test_step "Testing __validate_config_value with valid boolean true"

  __validate_config_value "enable_logging" "true" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should accept 'true' for boolean key"
}

function test_validate_config_value_boolean_false() {
  log_test_step "Testing __validate_config_value with valid boolean false"

  __validate_config_value "enable_logging" "false" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should accept 'false' for boolean key"
}

function test_validate_config_value_boolean_invalid() {
  log_test_step "Testing __validate_config_value with invalid boolean value"

  __validate_config_value "enable_logging" "yes" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should reject 'yes' for boolean key"
}

function test_validate_config_value_boolean_invalid_number() {
  log_test_step "Testing __validate_config_value with numeric value for boolean key"

  __validate_config_value "enable_logging" "1" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should reject '1' for boolean key"
}

function test_validate_config_value_integer_valid() {
  log_test_step "Testing __validate_config_value with valid integer"

  __validate_config_value "instance_suffix_length" "3" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should accept '3' for instance_suffix_length"
}

function test_validate_config_value_integer_zero_invalid() {
  log_test_step "Testing __validate_config_value with zero for non-retry integer key"

  __validate_config_value "instance_suffix_length" "0" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should reject 0 for instance_suffix_length"
}

function test_validate_config_value_integer_too_high() {
  log_test_step "Testing __validate_config_value with value exceeding max for integer key"

  # instance_suffix_length max is 10
  __validate_config_value "instance_suffix_length" "11" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should reject 11 for instance_suffix_length (max 10)"
}

function test_validate_config_value_integer_not_numeric() {
  log_test_step "Testing __validate_config_value with non-numeric value for integer key"

  __validate_config_value "instance_suffix_length" "abc" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should reject non-numeric value for integer key"
}

function test_validate_config_value_webhook_retry_zero_valid() {
  log_test_step "Testing __validate_config_value with zero for webhook_retry_count (allowed)"

  __validate_config_value "webhook_retry_count" "0" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should accept 0 for webhook_retry_count"
}

function test_validate_config_value_webhook_timeout_valid() {
  log_test_step "Testing __validate_config_value with valid webhook timeout"

  __validate_config_value "webhook_timeout_seconds" "30" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should accept 30 for webhook_timeout_seconds"
}

function test_validate_config_value_webhook_timeout_exceeds_max() {
  log_test_step "Testing __validate_config_value with webhook timeout exceeding max (300)"

  __validate_config_value "webhook_timeout_seconds" "301" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should reject 301 for webhook_timeout_seconds (max 300)"
}

# =============================================================================
# __get_config_value() TESTS
# =============================================================================

function test_get_config_value_empty_file() {
  log_test_step "Testing __get_config_value with empty config file path"

  __get_config_value "" "enable_logging" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty file path"
}

function test_get_config_value_empty_key() {
  log_test_step "Testing __get_config_value with empty key"

  __get_config_value "$CONFIG_FILE" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty key"
}

function test_get_config_value_nonexistent_file() {
  log_test_step "Testing __get_config_value with non-existent config file"

  __get_config_value "/tmp/nonexistent_kgsm_config_xyz.ini" "enable_logging" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing file"
}

function test_get_config_value_unknown_key() {
  log_test_step "Testing __get_config_value with unknown key"

  __get_config_value "$CONFIG_FILE" "unknown_key_xyz_999" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code" "Should return EC_KEY_NOT_FOUND for unknown key"
}

function test_get_config_value_known_key_returns_value() {
  log_test_step "Testing __get_config_value returns value for known key"

  local value
  value=$(__get_config_value "$CONFIG_FILE" "enable_logging" 2>/dev/null)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for known key"
  assert_not_null "$value" "Value should not be empty for enable_logging"
}

function test_get_config_value_from_temp_file() {
  log_test_step "Testing __get_config_value reads value from arbitrary config file"

  local temp_config
  temp_config=$(mktemp /tmp/kgsm_test_config_XXXXXX.ini)
  echo "my_test_key=my_test_value" >> "$temp_config"

  local value
  value=$(__get_config_value "$temp_config" "my_test_key" 2>/dev/null)
  local exit_code=$?

  rm -f "$temp_config"

  assert_equals "0" "$exit_code" "Should return 0 for key in temp file"
  assert_equals "my_test_value" "$value" "Should return correct value from temp file"
}

# =============================================================================
# __get_config_value_safe() TESTS
# =============================================================================

function test_get_config_value_safe_empty_key() {
  log_test_step "Testing __get_config_value_safe with empty key"

  __get_config_value_safe "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty key"
}

function test_get_config_value_safe_unknown_key() {
  log_test_step "Testing __get_config_value_safe with unknown key"

  __get_config_value_safe "nonexistent_key_abc_xyz" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code" "Should return EC_KEY_NOT_FOUND for unknown key"
}

function test_get_config_value_safe_known_key() {
  log_test_step "Testing __get_config_value_safe with valid known key"

  local value
  value=$(__get_config_value_safe "enable_logging" 2>/dev/null)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for valid key"
  assert_not_null "$value" "Should return non-empty value for enable_logging"
}

function test_get_config_value_safe_integer_key() {
  log_test_step "Testing __get_config_value_safe with integer key"

  local value
  value=$(__get_config_value_safe "instance_suffix_length" 2>/dev/null)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for instance_suffix_length"
  assert_matches "$value" "^[0-9]+$" "Value should be numeric for instance_suffix_length"
}

# =============================================================================
# __set_config_value() TESTS
# =============================================================================

function test_set_config_value_empty_key() {
  log_test_step "Testing __set_config_value with empty key"

  __set_config_value "" "true" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty key"
}

function test_set_config_value_unknown_key() {
  log_test_step "Testing __set_config_value with unknown key"

  __set_config_value "nonexistent_key_xyz_abc" "somevalue" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code" "Should return EC_KEY_NOT_FOUND for unknown key"
}

function test_set_config_value_invalid_value() {
  log_test_step "Testing __set_config_value with invalid value for boolean key"

  __set_config_value "enable_logging" "notabool" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for invalid boolean value"
}

function test_set_config_value_valid_boolean() {
  log_test_step "Testing __set_config_value with valid boolean value"

  # Read current value so we can restore it
  local original
  original=$(__get_config_value_safe "enable_logging" 2>/dev/null)

  __set_config_value "enable_logging" "false" 2>/dev/null
  local exit_code=$?

  # Restore original value
  __set_config_value "enable_logging" "${original:-true}" 2>/dev/null

  assert_equals "$EC_SUCCESS_CONFIG_SET" "$exit_code" "Should return EC_SUCCESS_CONFIG_SET for valid set"
}

function test_set_config_value_valid_integer() {
  log_test_step "Testing __set_config_value with valid integer value"

  # Read current value so we can restore it
  local original
  original=$(__get_config_value_safe "instance_suffix_length" 2>/dev/null)

  __set_config_value "instance_suffix_length" "4" 2>/dev/null
  local exit_code=$?

  # Restore original
  __set_config_value "instance_suffix_length" "${original:-3}" 2>/dev/null

  assert_equals "$EC_SUCCESS_CONFIG_SET" "$exit_code" "Should return EC_SUCCESS_CONFIG_SET for valid integer"
}

function test_set_config_value_persists_change() {
  log_test_step "Testing __set_config_value change is persisted to file"

  local original
  original=$(__get_config_value_safe "instance_suffix_length" 2>/dev/null)

  __set_config_value "instance_suffix_length" "7" 2>/dev/null

  local new_value
  new_value=$(__get_config_value_safe "instance_suffix_length" 2>/dev/null)

  # Restore original
  __set_config_value "instance_suffix_length" "${original:-3}" 2>/dev/null

  assert_equals "7" "$new_value" "Set value should be persisted and readable back"
}

# =============================================================================
# __get_all_config_keys() TESTS
# =============================================================================

function test_get_all_config_keys_returns_keys() {
  log_test_step "Testing __get_all_config_keys returns non-empty list"

  local output
  output=$(__get_all_config_keys 2>/dev/null)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 with valid config file"
  assert_not_null "$output" "Should return non-empty key list"
}

function test_get_all_config_keys_contains_known_key() {
  log_test_step "Testing __get_all_config_keys includes known key"

  local output
  output=$(__get_all_config_keys 2>/dev/null)

  assert_contains "$output" "enable_logging" "Key list should include enable_logging"
}

function test_get_all_config_keys_no_comments() {
  log_test_step "Testing __get_all_config_keys does not include commented lines"

  local output
  output=$(__get_all_config_keys 2>/dev/null)

  assert_not_contains "$output" "#" "Key list should not contain comment characters"
}

function test_get_all_config_keys_no_section_headers() {
  log_test_step "Testing __get_all_config_keys does not include section headers"

  local output
  output=$(__get_all_config_keys 2>/dev/null)

  assert_not_contains "$output" "[" "Key list should not contain section header brackets"
}

# =============================================================================
# __list_config_values() TESTS
# =============================================================================

function test_list_config_values_plain_output() {
  log_test_step "Testing __list_config_values produces human-readable output"

  local output
  output=$(__list_config_values "" 2>/dev/null)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for plain list"
  assert_not_null "$output" "List output should not be empty"
  assert_contains "$output" "=" "Plain list should contain key=value pairs"
}

function test_list_config_values_contains_known_key() {
  log_test_step "Testing __list_config_values output includes known key"

  local output
  output=$(__list_config_values "" 2>/dev/null)

  assert_contains "$output" "enable_logging" "List should include enable_logging key"
}

function test_list_config_values_json_requires_jq() {
  log_test_step "Testing __list_config_values JSON format (skips if jq unavailable)"

  if ! command -v jq >/dev/null 2>&1; then
    skip_test "jq not available - skipping JSON format test"
    return 0
  fi

  local output
  output=$(__list_config_values "1" 2>/dev/null)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for JSON list with jq available"
  assert_contains "$output" "{" "JSON output should start with opening brace"
  assert_contains "$output" "enable_logging" "JSON output should include enable_logging"
}

# =============================================================================
# __reset_config() TESTS
# =============================================================================

function test_reset_config_returns_success_code() {
  log_test_step "Testing __reset_config returns EC_SUCCESS_CONFIG_RESET"

  # Save current config content to restore after test
  local saved_config
  saved_config=$(cat "$CONFIG_FILE")

  __reset_config 2>/dev/null
  local exit_code=$?

  # Restore original config content
  echo "$saved_config" > "$CONFIG_FILE"

  assert_equals "$EC_SUCCESS_CONFIG_RESET" "$exit_code" \
    "Should return EC_SUCCESS_CONFIG_RESET after successful reset"
}

function test_reset_config_copies_default() {
  log_test_step "Testing __reset_config overwrites config with default content"

  # Set a distinctive value
  __set_config_value "instance_suffix_length" "9" 2>/dev/null

  # Save config before reset
  local before_reset
  before_reset=$(__get_config_value_safe "instance_suffix_length" 2>/dev/null)

  __reset_config 2>/dev/null

  # After reset, value should match default
  local after_reset
  after_reset=$(__get_config_value "$DEFAULT_CONFIG_FILE" "instance_suffix_length" 2>/dev/null)
  local current_after
  current_after=$(__get_config_value_safe "instance_suffix_length" 2>/dev/null)

  assert_equals "$after_reset" "$current_after" \
    "After reset, instance_suffix_length should match default"
}

function test_reset_config_creates_backup() {
  log_test_step "Testing __reset_config creates a timestamped backup"

  __reset_config 2>/dev/null

  # At least one timestamped .bak file should exist after reset
  local after_count
  after_count=$(find "$(dirname "$CONFIG_FILE")" -name "$(basename "$CONFIG_FILE").*.bak" 2>/dev/null | wc -l)

  local is_valid=false
  if [[ "$after_count" -ge 1 ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" "reset_config should leave at least one timestamped backup file"
}

# =============================================================================
# __validate_current_config() TESTS
# =============================================================================

function test_validate_current_config_clean_config() {
  log_test_step "Testing __validate_current_config on a clean/default config"

  __validate_current_config 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$exit_code" \
    "Should return EC_SUCCESS_CONFIG_VALIDATED for clean default config"
}

function test_validate_current_config_after_valid_set() {
  log_test_step "Testing __validate_current_config after setting a valid value"

  local original
  original=$(__get_config_value_safe "enable_logging" 2>/dev/null)

  __set_config_value "enable_logging" "true" 2>/dev/null

  __validate_current_config 2>/dev/null
  local exit_code=$?

  # Restore
  __set_config_value "enable_logging" "${original:-true}" 2>/dev/null

  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$exit_code" \
    "Should return EC_SUCCESS_CONFIG_VALIDATED after setting valid value"
}

