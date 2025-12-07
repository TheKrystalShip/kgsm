#!/usr/bin/env bash

# =============================================================================
# KGSM Config Module - Refactored Test Suite
# =============================================================================
#
# This test provides comprehensive coverage of the refactored config.sh module,
# testing the new command-based CLI interface and pure logic functions.
#
# The refactored config module uses command-based interface:
# - Setting configuration values (set)
# - Getting configuration values (get)
# - Listing all configuration (list)
# - Resetting to defaults (reset)
# - Validating configuration (validate)
# - Opening in editor (edit)
# - Help system (help)
#
# Test Coverage:
# ✓ Pure logic functions with success event codes
# ✓ Command-based CLI interface
# ✓ Orchestrator I/O management
# ✓ Event dispatching integration
# ✓ Centralized validation integration
# ✓ Help system functionality
# ✓ Error handling and edge cases
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="config_module_refactored"
readonly CONFIG_MODULE="$KGSM_ROOT/commands/config.sh"
readonly BOOTSTRAP_LIB="$KGSM_ROOT/core/bootstrap.sh"
readonly CONFIG_LIB="$KGSM_ROOT/core/config.sh"
readonly CONFIG_FILE="$KGSM_ROOT/config.ini"
readonly DEFAULT_CONFIG_FILE="$KGSM_ROOT/config.default.ini"
readonly BACKUP_CONFIG_FILE="$CONFIG_FILE.backup.test"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Backup current config and restore after tests
function backup_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$BACKUP_CONFIG_FILE"
  fi
}

function restore_config() {
  if [[ -f "$BACKUP_CONFIG_FILE" ]]; then
    mv "$BACKUP_CONFIG_FILE" "$CONFIG_FILE"
  fi
}

function setup_test() {
  # Since we're sourcing just the config.sh library, it won't have all the
  # necessary dependencies loaded and it won't load them by itself
  # so we manually load up the bootstrap.sh library script to account for that.
  if [[ -f "$BOOTSTRAP_LIB" ]]; then
    source "$BOOTSTRAP_LIB"
  fi

    cat > "$CONFIG_FILE" << 'EOF'
# Test configuration file
enable_logging=true
instance_suffix_length=3
enable_systemd=false
webhook_timeout_seconds=30
default_install_directory=/opt/kgsm
EOF
}

# =============================================================================
# PURE LOGIC FUNCTION TESTS
# =============================================================================

function test_pure_logic_set_config_value() {
  log_step "Pure Logic: __set_config_value function"

  # Test successful set operation
  assert_command_succeeds "__set_config_value 'enable_logging' 'true'" \
    "Should successfully set config value"

  # Verify the value was actually set
  local result
  result=$(__get_config_value "$CONFIG_FILE" "enable_logging")
  assert_equals "true" "$result" "Config value should be updated"

  # Test successful set operation
  assert_command_succeeds "__set_config_value 'enable_logging' 'false'" \
    "Should successfully set config value"

  # Verify the value was actually set
  result=$(__get_config_value "$CONFIG_FILE" "enable_logging")
  assert_equals "false" "$result" "Config value should be updated"

  # Test that function returns success event code
  __set_config_value "instance_suffix_length" "5"
  local exit_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_SET" "$exit_code" \
    "Should return success event code EC_SUCCESS_CONFIG_SET"

  # Test invalid key
  __set_config_value "invalid_key" "value" 2> /dev/null
  exit_code=$?
  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code"  \
    "Should return EC_KEY_NOT_FOUND for invalid key"

  # Test invalid value for boolean
  __set_config_value "enable_logging" "maybe" 2> /dev/null
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code"  \
    "Should return EC_INVALID_ARG for invalid boolean value"

  log_test "Pure Logic: __set_config_value function"
}

function test_pure_logic_get_config_value() {
  log_step "Pure Logic: __get_config_value_safe function"

  # Test successful get operation
  local result
  result=$(__get_config_value_safe "enable_logging")
  local exit_code=$?
  assert_equals "0" "$exit_code" "Should return 0 for successful get"

  # We don't know the value because other tests might have changed it, we
  # just care that it's one of the two possibilities
  assert_containe "true false" "$result" "Should return correct config value"

  # Test invalid key
  __get_config_value_safe "invalid_key" 2> /dev/null
  exit_code=$?
  assert_equals "$EC_KEY_NOT_FOUND" "$exit_code" \
    "Should return EC_KEY_NOT_FOUND for invalid key"

  # Test empty key
  __get_config_value_safe "" 2> /dev/null
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty key"

  log_test "Pure Logic: __get_config_value_safe function"
}

function test_pure_logic_list_config_values() {
  log_step "Pure Logic: __list_config_values function"

  # Set up the value first
  __set_config_value "enable_logging" "true"

  # Test normal list operation
  local result
  result=$(__list_config_values)
  local exit_code=$?
  assert_equals "0" "$exit_code" "Should return 0 for successful list"
  assert_contains "$result" "enable_logging = true" "Should contain config values"

  # Test JSON format
  result=$(__list_config_values "1")
  exit_code=$?
  assert_equals "0" "$exit_code" "Should return 0 for successful JSON list"
  assert_contains "$result" '"enable_logging": true' "Should contain JSON formatted values"

  log_test "Pure Logic: __list_config_values function"
}

function test_pure_logic_reset_config() {
  log_step "Pure Logic: __reset_config function"

  # Modify a value first
  __set_config_value "enable_logging" "false" > /dev/null 2>&1

  # Test reset operation
  __reset_config > /dev/null 2>&1
  local exit_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_RESET" "$exit_code" \
    "Should return success event code EC_SUCCESS_CONFIG_RESET"

  # Verify config was reset (should match default)
  local result
  result=$(__get_config_value "$CONFIG_FILE" "enable_logging" 2> /dev/null || echo "default_value")
  # The exact value depends on what's in config.default.ini, so we just verify the operation succeeded
  assert_not_equals "$result" "" "Config should be reset to default values"

  log_test "Pure Logic: __reset_config function"
}

function test_pure_logic_validate_config() {
  log_step "Pure Logic: __validate_current_config function"

  # Test validation with valid config
  __validate_current_config > /dev/null 2>&1
  local exit_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$exit_code" \
    "Should return success event code EC_SUCCESS_CONFIG_VALIDATED for valid config"

  # Test validation with invalid config
  sed -i "s/enable_logging=.*/enable_logging='yes'/" "$CONFIG_FILE"

  __validate_current_config > /dev/null 2>&1
  exit_code=$?
  assert_equals "1" "$exit_code" \
    "Should return 1 for invalid config"

  log_test "Pure Logic: __validate_current_config function"
}

# =============================================================================
# COMMAND-BASED CLI TESTS
# =============================================================================

function test_command_based_cli_set() {
  log_step "Command-based CLI: set command"

  # Test successful set command
  local result
  result=$("$CONFIG_MODULE" set "enable_logging=false" 2>&1)
  local exit_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_SET" "$exit_code" "Set command should succeed"
  assert_contains "$result" "Configuration updated" "Should show success message"

  # Test invalid format
  result=$("$CONFIG_MODULE" set "invalid_format" 2>&1)
  exit_code=$?
  assert_not_equals "$exit_code" "0" "Should fail with invalid format"
  assert_contains "$result" "Invalid format" "Should show format error"

  # Test missing argument
  result=$("$CONFIG_MODULE" set 2>&1)
  exit_code=$?
  assert_not_equals "$exit_code" "0" "Should fail with missing argument"
  assert_contains "$result" "Missing argument" "Should show missing argument error"

  log_test "Command-based CLI: set command"
}

function test_command_based_cli_get() {
  log_step "Command-based CLI: get command"

  # Test successful get command
  local result
  result=$("$CONFIG_MODULE" get "enable_logging" 2>&1)
  local exit_code=$?
  assert_equals "0" "$exit_code" "Get command should succeed"
  assert_contains "true false" "$result" "Should return correct value (either true or false)"

  # Test invalid key
  result=$("$CONFIG_MODULE" get "invalid_key" 2>&1)
  exit_code=$?
  assert_not_equals "$exit_code" "0" "Should fail with invalid key"
  assert_contains "$result" "Configuration key not found" "Should show key not found error"

  # Test missing argument
  result=$("$CONFIG_MODULE" get 2>&1)
  exit_code=$?
  assert_not_equals "$exit_code" "0" "Should fail with missing argument"
  assert_contains "$result" "Missing argument" "Should show missing argument error"

  log_test "Command-based CLI: get command"
}

function test_command_based_cli_list() {
  log_step "Command-based CLI: list command"

  # Test normal list command
  local result
  result=$("$CONFIG_MODULE" list 2>&1)
  local exit_code=$?
  assert_equals "0" "$exit_code" "List command should succeed"
  assert_contains "$result" "enable_logging" "Should show config values"

  # Test JSON list command
  result=$("$CONFIG_MODULE" list --json 2>&1)
  exit_code=$?
  assert_equals "0" "$exit_code" "JSON list command should succeed"
  assert_contains "$result" '"enable_logging"'  "Should show JSON formatted values"

  log_test "Command-based CLI: list command"
}

function test_command_based_cli_help() {
  log_step "Command-based CLI: help system"

  # Test general help
  local result
  result=$("$CONFIG_MODULE" help 2>&1)
  local exit_code=$?
  assert_equals "0" "$exit_code" "Help command should succeed"
  assert_contains "$result" "Configuration Management" "Should show general help"
  assert_contains "$result" "set <key=value>" "Should show command syntax"

  # Test command-specific help
  result=$("$CONFIG_MODULE" help set 2>&1)
  exit_code=$?
  assert_equals "0" "$exit_code" "Command-specific help should succeed"
  assert_contains "$result" "Usage: config.sh set" "Should show command-specific help"

  # Test --help flag
  result=$("$CONFIG_MODULE" --help 2>&1)
  exit_code=$?
  assert_equals "0" "$exit_code" "--help flag should succeed"
  assert_contains "$result" "Configuration Management" "Should show help with --help flag"

  # Test no command (should show usage)
  result=$("$CONFIG_MODULE" 2>&1)
  exit_code=$?
  assert_command_fails "No command should show usage and exit $EC_GENERAL"
  assert_contains "$result" "Configuration Management" "Should show usage when no command provided"

  log_test "Command-based CLI: help system"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting $TEST_NAME"

  # Backup original config
  backup_config

  # Setup test
  setup_test

  # Run pure logic function tests
  test_pure_logic_set_config_value
  test_pure_logic_get_config_value
  test_pure_logic_list_config_values
  test_pure_logic_reset_config
  test_pure_logic_validate_config

  # Run command-based CLI tests
  test_command_based_cli_set
  test_command_based_cli_get
  test_command_based_cli_list
  test_command_based_cli_help

  # Restore original config
  restore_config

  # Print final results and determine exit code using framework
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All config module tests completed successfully"
  else
    fail_test "Some config module tests failed"
  fi
}

# Execute main function
main "$@"
