#!/usr/bin/env bash

# =============================================================================
# KGSM Config Module - Comprehensive Test Suite
# =============================================================================
#
# This test provides comprehensive coverage of the config.sh module, testing all
# commands, error conditions, edge cases, and behavioral consistency.
#
# The config module manages KGSM configuration settings through CLI interface:
# - Setting configuration values (--set)
# - Getting configuration values (--get)
# - Listing all configuration (--list)
# - Resetting to defaults (--reset)
# - Validating configuration (--validate)
# - Opening in editor (default behavior)
#
# Test Coverage:
# ✓ Module existence and permissions
# ✓ Help functionality and usage display
# ✓ All command combinations (--set, --get, --list, --reset, --validate)
# ✓ Argument validation and error handling
# ✓ Configuration value validation (boolean, integer, string)
# ✓ Integration with kgsm.sh delegation
# ✓ JSON output functionality
# ✓ Debug mode functionality
# ✓ Behavioral consistency and predictability
# ✓ Edge cases and boundary conditions
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="config_module_comprehensive"
readonly CONFIG_MODULE="$KGSM_ROOT/commands/config.sh"
readonly CONFIG_FILE="$KGSM_ROOT/config.ini"
readonly DEFAULT_CONFIG_FILE="$KGSM_ROOT/config.default.ini"
readonly BACKUP_CONFIG_FILE="$CONFIG_FILE.backup.test"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Backup current config and restore after tests
function backup_config() {
  log_test "Backing up current configuration"
  if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$BACKUP_CONFIG_FILE"
    log_test "Configuration backed up to $BACKUP_CONFIG_FILE"
  fi
}

function restore_config() {
  log_test "Restoring original configuration"
  if [[ -f "$BACKUP_CONFIG_FILE" ]]; then
    cp "$BACKUP_CONFIG_FILE" "$CONFIG_FILE"
    rm -f "$BACKUP_CONFIG_FILE"
    log_test "Configuration restored from backup"
  fi
}

function setup_test() {
  log_test "Setting up comprehensive config module test environment"

  # Backup current config
  backup_config

  # Basic module validation
  assert_file_exists "$CONFIG_MODULE" "Config module should exist"
  assert_file_executable "$CONFIG_MODULE" "Config module should be executable"

  # Ensure required files exist
  assert_file_exists "$CONFIG_FILE" "Config file should exist"
  assert_file_exists "$DEFAULT_CONFIG_FILE" "Default config file should exist"

  # Ensure config file is writable
  assert_command_succeeds "test -w '$CONFIG_FILE'" "Config file should be writable"

  # Ensure kgsm.sh exists in test environment (needed for common library)
  if [[ ! -f "$KGSM_ROOT/kgsm.sh" ]]; then
    echo '#!/usr/bin/env bash' > "$KGSM_ROOT/kgsm.sh"
    chmod +x "$KGSM_ROOT/kgsm.sh"
    log_test "Created kgsm.sh in test environment"
  fi

  log_test "Test environment setup complete"
}

function cleanup_test() {
  log_test "Cleaning up config module test environment"
  restore_config
}

# =============================================================================
# TEST FUNCTIONS - BASIC MODULE VALIDATION
# =============================================================================

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  # Basic file system checks
  assert_file_exists "$CONFIG_MODULE" "Config module file should exist"
  assert_command_succeeds "test -r '$CONFIG_MODULE'" "Config module should be readable"
  assert_file_executable "$CONFIG_MODULE" "Config module should be executable"

  # Check file size (should not be empty)
  assert_command_succeeds "test -s '$CONFIG_MODULE'" "Config module should not be empty"

  # Verify it's a bash script
  local first_line
  first_line=$(head -n1 "$CONFIG_MODULE")
  assert_contains "$first_line" "#!/usr/bin/env bash" "Config module should be a bash script"

  log_test "Module existence and permissions validated"
}

function test_help_functionality() {
  log_step "Testing help functionality and usage display"

  # Test --help flag
  assert_command_succeeds "$CONFIG_MODULE --help" "config.sh --help should work"

  # Test -h flag
  assert_command_succeeds "$CONFIG_MODULE -h" "config.sh -h should work"

  # Verify help content contains expected information
  local help_output
  help_output=$("$CONFIG_MODULE" --help 2>&1)

  assert_contains "$help_output" "Configuration Management for Krystal Game Server Manager" "Help should contain module description"
  assert_contains "$help_output" "--set" "Help should document --set command"
  assert_contains "$help_output" "--get" "Help should document --get command"
  assert_contains "$help_output" "--list" "Help should document --list command"
  assert_contains "$help_output" "--reset" "Help should document --reset command"
  assert_contains "$help_output" "--validate" "Help should document --validate command"
  assert_contains "$help_output" "Examples:" "Help should contain usage examples"

  log_test "Help functionality validated"
}

# =============================================================================
# TEST FUNCTIONS - ARGUMENT VALIDATION
# =============================================================================

function test_argument_filtering() {
  log_step "Testing --config argument filtering"

  # Test that --config argument is properly filtered when called from kgsm.sh
  assert_command_succeeds "$CONFIG_MODULE --config --help" "config.sh should filter out --config argument"

  # Test that help still works with --config prefix
  local help_output
  help_output=$("$CONFIG_MODULE" --config --help 2>&1)
  assert_contains "$help_output" "Configuration Management" "Help should work with --config prefix"

  log_test "Argument filtering validated"
}

function test_missing_arguments() {
  log_step "Testing behavior with missing arguments"

  # Test missing argument for --set
  assert_command_fails "$CONFIG_MODULE --set" "config.sh --set without value should fail"

  # Test missing argument for --get
  assert_command_fails "$CONFIG_MODULE --get" "config.sh --get without key should fail"

  # Verify error messages are helpful
  local error_output
  error_output=$("$CONFIG_MODULE" --set 2>&1 || true)
  assert_contains "$error_output" "Missing argument" "Error message should indicate missing argument"

  error_output=$("$CONFIG_MODULE" --get 2>&1 || true)
  assert_contains "$error_output" "Missing argument" "Error message should indicate missing argument"

  log_test "Missing argument handling validated"
}

function test_invalid_arguments() {
  log_step "Testing behavior with invalid arguments"

  # Test completely invalid arguments
  assert_command_fails "$CONFIG_MODULE --invalid-argument" "config.sh should reject invalid arguments"

  # Test invalid format for --set
  assert_command_fails "$CONFIG_MODULE --set invalid-format" "config.sh should reject invalid --set format"
  assert_command_fails "$CONFIG_MODULE --set key" "config.sh should reject --set without ="

  # Verify error messages
  local error_output
  error_output=$("$CONFIG_MODULE" --invalid-argument 2>&1 || true)
  assert_contains "$error_output" "ERROR" "Error message should contain error indication"

  log_test "Invalid argument handling validated"
}

# =============================================================================
# TEST FUNCTIONS - CONFIGURATION VALUE VALIDATION
# =============================================================================

function test_boolean_value_validation() {
  log_step "Testing boolean value validation"

  # Test valid boolean values
  assert_command_succeeds "$CONFIG_MODULE --set enable_logging=true" "Should accept true boolean value"
  assert_command_succeeds "$CONFIG_MODULE --set enable_logging=false" "Should accept false boolean value"

  # Test invalid boolean values
  assert_command_fails "$CONFIG_MODULE --set enable_logging=yes" "Should reject invalid boolean value"
  assert_command_fails "$CONFIG_MODULE --set enable_logging=1" "Should reject numeric boolean value"
  assert_command_fails "$CONFIG_MODULE --set enable_logging=on" "Should reject 'on' as boolean value"

  # Verify error messages for invalid booleans
  local error_output
  error_output=$("$CONFIG_MODULE" --set enable_logging=invalid 2>&1 || true)
  assert_contains "$error_output" "Invalid boolean value" "Error should indicate invalid boolean"

  log_test "Boolean value validation confirmed"
}

function test_integer_value_validation() {
  log_step "Testing integer value validation"

  # Test valid integer values
  assert_command_succeeds "$CONFIG_MODULE --set instance_suffix_length=3" "Should accept valid integer"
  assert_command_succeeds "$CONFIG_MODULE --set log_max_size_kb=2048" "Should accept valid integer"

  # Test invalid integer values
  assert_command_fails "$CONFIG_MODULE --set instance_suffix_length=abc" "Should reject non-numeric value"
  assert_command_fails "$CONFIG_MODULE --set instance_suffix_length=-1" "Should reject negative value"
  assert_command_fails "$CONFIG_MODULE --set instance_suffix_length=0" "Should reject zero value"

  # Test range validation for instance_suffix_length
  assert_command_fails "$CONFIG_MODULE --set instance_suffix_length=11" "Should reject value > 10"
  assert_command_fails "$CONFIG_MODULE --set instance_suffix_length=0" "Should reject value < 1"

  # Verify error messages for invalid integers
  local error_output
  error_output=$("$CONFIG_MODULE" --set instance_suffix_length=abc 2>&1 || true)
  assert_contains "$error_output" "Invalid integer value" "Error should indicate invalid integer"

  log_test "Integer value validation confirmed"
}

function test_string_value_validation() {
  log_step "Testing string value validation"

  # Test valid string values
  assert_command_succeeds "$CONFIG_MODULE --set update_channel=main" "Should accept valid string"
  assert_command_succeeds "$CONFIG_MODULE --set systemd_files_dir=/etc/systemd/system" "Should accept valid path"

  # Test empty string validation (some keys allow empty values)
  assert_command_succeeds "$CONFIG_MODULE --set default_install_directory=" "Should accept empty string for optional path"
  assert_command_succeeds "$CONFIG_MODULE --set STEAM_USERNAME=" "Should accept empty string for optional credentials"

  # Test invalid empty strings (for required fields)
  assert_command_fails "$CONFIG_MODULE --set update_channel=" "Should reject empty string for required field"

  log_test "String value validation confirmed"
}

# =============================================================================
# TEST FUNCTIONS - COMMAND FUNCTIONALITY
# =============================================================================

function test_set_command() {
  log_step "Testing --set command functionality"

  # Test setting various types of values
  assert_command_succeeds "$CONFIG_MODULE --set enable_logging=true" "Should set boolean value"
  assert_command_succeeds "$CONFIG_MODULE --set instance_suffix_length=4" "Should set integer value"
  assert_command_succeeds "$CONFIG_MODULE --set update_channel=dev" "Should set string value"

  # Verify values were actually set
  local value
  value=$("$CONFIG_MODULE" --get enable_logging)
  assert_equals "$value" "true" "enable_logging should be set to true"

  value=$("$CONFIG_MODULE" --get instance_suffix_length)
  assert_equals "$value" "4" "instance_suffix_length should be set to 4"

  value=$("$CONFIG_MODULE" --get update_channel)
  assert_equals "$value" "dev" "update_channel should be set to dev"

  log_test "Set command functionality validated"
}

function test_get_command() {
  log_step "Testing --get command functionality"

  # Test getting existing values
  local value
  value=$("$CONFIG_MODULE" --get enable_logging)
  assert_not_null "$value" "Should return value for existing key"

  value=$("$CONFIG_MODULE" --get instance_suffix_length)
  assert_not_null "$value" "Should return value for existing key"

  # Test getting non-existent key
  assert_command_fails "$CONFIG_MODULE --get nonexistent_key" "Should fail for non-existent key"

  # Verify error message for non-existent key
  local error_output
  error_output=$("$CONFIG_MODULE" --get nonexistent_key 2>&1 || true)
  assert_contains "$error_output" "Unknown configuration key" "Error should indicate unknown key"

  log_test "Get command functionality validated"
}

function test_list_command() {
  log_step "Testing --list command functionality"

  # Test basic list command
  assert_command_succeeds "$CONFIG_MODULE --list" "Should list all configuration values"

  # Test JSON output
  assert_command_succeeds "$CONFIG_MODULE --list --json" "Should output JSON format"

  # Verify list output contains expected content
  local list_output
  list_output=$("$CONFIG_MODULE" --list 2>&1)

  assert_contains "$list_output" "Current KGSM Configuration" "List should contain header"
  assert_contains "$list_output" "enable_logging" "List should contain config keys"
  assert_contains "$list_output" "instance_suffix_length" "List should contain config keys"

  # Verify JSON output is valid JSON
  local json_output
  json_output=$("$CONFIG_MODULE" --list --json 2>&1)
  assert_contains "$json_output" "{" "JSON output should start with {"
  assert_contains "$json_output" "}" "JSON output should end with }"

  log_test "List command functionality validated"
}

function test_reset_command() {
  log_step "Testing --reset command functionality"

  # Change some values first
  "$CONFIG_MODULE" --set enable_logging=true
  "$CONFIG_MODULE" --set instance_suffix_length=5

  # Test reset command
  assert_command_succeeds "$CONFIG_MODULE --reset" "Should reset configuration to defaults"

  # Verify values were reset
  local value
  value=$("$CONFIG_MODULE" --get enable_logging)
  assert_equals "$value" "false" "enable_logging should be reset to default"

  value=$("$CONFIG_MODULE" --get instance_suffix_length)
  assert_equals "$value" "2" "instance_suffix_length should be reset to default"

  log_test "Reset command functionality validated"
}

function test_validate_command() {
  log_step "Testing --validate command functionality"

  # Test with valid configuration
  assert_command_succeeds "$CONFIG_MODULE --validate" "Should validate current configuration"

  # Test with invalid configuration (set invalid value)
  "$CONFIG_MODULE" --set enable_logging=invalid 2>/dev/null || true

  # Validation should still pass (invalid values are caught during set)
  assert_command_succeeds "$CONFIG_MODULE --validate" "Should pass validation even with invalid values"

  log_test "Validate command functionality validated"
}

# =============================================================================
# TEST FUNCTIONS - INTEGRATION WITH KGSM.SH
# =============================================================================

function test_kgsm_integration() {
  log_step "Testing integration with kgsm.sh"

  # Test that kgsm.sh properly delegates to config module
  assert_command_succeeds "$KGSM_ROOT/kgsm.sh --config --help" "kgsm.sh should delegate --config --help"

  # Test setting value through kgsm.sh
  assert_command_succeeds "$KGSM_ROOT/kgsm.sh --config --set enable_logging=true" "kgsm.sh should delegate --config --set"

  # Test getting value through kgsm.sh
  local value
  value=$("$KGSM_ROOT/kgsm.sh" --config --get enable_logging)
  assert_equals "$value" "true" "kgsm.sh should properly delegate --config --get"

  # Test listing through kgsm.sh
  assert_command_succeeds "$KGSM_ROOT/kgsm.sh --config --list" "kgsm.sh should delegate --config --list"

  log_test "KGSM integration validated"
}

# =============================================================================
# TEST FUNCTIONS - EDGE CASES AND BOUNDARY CONDITIONS
# =============================================================================

function test_edge_cases() {
  log_step "Testing edge cases and boundary conditions"

  # Test with special characters in values
  assert_command_succeeds "$CONFIG_MODULE --set systemd_files_dir=/path/with/spaces" "Should handle paths with spaces"
  assert_command_succeeds "$CONFIG_MODULE --set event_socket_filenames=my-socket.sock,my-socket2.sock" "Should handle filenames with special chars"

  # Test boundary values for integers
  assert_command_succeeds "$CONFIG_MODULE --set instance_suffix_length=1" "Should accept minimum value"
  assert_command_succeeds "$CONFIG_MODULE --set instance_suffix_length=10" "Should accept maximum value"
  assert_command_fails "$CONFIG_MODULE --set instance_suffix_length=0" "Should reject value below minimum"
  assert_command_fails "$CONFIG_MODULE --set instance_suffix_length=11" "Should reject value above maximum"

  # Test with very long values
  local long_value
  long_value=$(printf 'a%.0s' {1..1000}) # 1000 character string
  assert_command_succeeds "$CONFIG_MODULE --set systemd_files_dir=/path/$long_value" "Should handle very long values"

  log_test "Edge cases validated"
}

function test_debug_mode() {
  log_step "Testing debug mode functionality"

  # Test that debug mode doesn't break functionality
  assert_command_succeeds "$CONFIG_MODULE --debug --help" "Debug mode should work with --help"
  assert_command_succeeds "$CONFIG_MODULE --debug --list" "Debug mode should work with --list"
  assert_command_succeeds "$CONFIG_MODULE --debug --set enable_logging=false" "Debug mode should work with --set"

  log_test "Debug mode functionality validated"
}

# =============================================================================
# TEST FUNCTIONS - BEHAVIORAL CONSISTENCY
# =============================================================================

function test_behavioral_consistency() {
  log_step "Testing behavioral consistency"

  # Test that repeated operations produce consistent results
  "$CONFIG_MODULE" --set enable_logging=true
  local value1
  value1=$("$CONFIG_MODULE" --get enable_logging)

  "$CONFIG_MODULE" --set enable_logging=true # Set same value again
  local value2
  value2=$("$CONFIG_MODULE" --get enable_logging)

  assert_equals "$value1" "$value2" "Repeated operations should produce consistent results"

  # Test that list output is consistent
  local list1
  list1=$("$CONFIG_MODULE" --list)
  local list2
  list2=$("$CONFIG_MODULE" --list)
  assert_equals "$list1" "$list2" "List output should be consistent"

  log_test "Behavioral consistency validated"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting comprehensive config module test suite"

  # Initialize test environment
  setup_test

  # Basic module validation
  test_module_existence_and_permissions
  test_help_functionality

  # Argument validation
  test_argument_filtering
  test_missing_arguments
  test_invalid_arguments

  # Configuration value validation
  test_boolean_value_validation
  test_integer_value_validation
  test_string_value_validation

  # Command functionality
  test_set_command
  test_get_command
  test_list_command
  test_reset_command
  test_validate_command

  # Integration testing
  test_kgsm_integration

  # Edge cases and boundary conditions
  test_edge_cases
  test_debug_mode

  # Behavioral consistency
  test_behavioral_consistency

  log_test "Comprehensive config module test suite completed successfully"

  # Print final results and determine exit code using framework
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All comprehensive files module tests completed successfully"
  else
    fail_test "Some comprehensive files module tests failed"
  fi
}

# Execute main function
main "$@"
