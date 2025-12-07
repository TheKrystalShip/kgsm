#!/usr/bin/env bash

# KGSM Test Suite - Common Library Comprehensive Tests
#
# Tests the core/common.sh library to ensure it properly sources all dependent
# libraries and makes their functions available.
#
# Author: The Krystal Ship Team
# Version: 1.0

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="Common Library Comprehensive Tests"
readonly COMMON_LIBRARY="$KGSM_ROOT/core/common.sh"
readonly LIB_DIR="$KGSM_ROOT/lib"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function test_common_library_existence() {
  log_step "Testing common library file existence and structure"

  assert_file_exists "$COMMON_LIBRARY" "Common library file should exist"
  assert_file_contains "$COMMON_LIBRARY" "#!/usr/bin/env bash" "Common library should be a bash script"
}

function test_common_library_sourcing() {
  log_step "Testing common library can be sourced without errors"

  # Source the common library for all subsequent tests
  source "$COMMON_LIBRARY"

  # Test that KGSM_COMMON_LOADED is set
  assert_contains "$KGSM_COMMON_LOADED" "1" "KGSM_COMMON_LOADED should be set to 1 after sourcing"
}

function test_kgsm_root_detection() {
  log_step "Testing KGSM_ROOT detection and setup"

  # Test that KGSM_ROOT is set correctly
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$KGSM_ROOT/kgsm.sh" "KGSM_ROOT should point to directory containing kgsm.sh"

  # Test that KGSM_ROOT is exported
  assert_command_succeeds "env | grep -q '^KGSM_ROOT='" "KGSM_ROOT should be exported"
}

function test_library_files_existence() {
  log_step "Testing all required library files exist"

  local required_libs=(
    "errors.sh"
    "config.sh"
    "logging.sh"
    "parser.sh"
    "validation.sh"
    "system.sh"
    "loader.sh"
  )

  for lib in "${required_libs[@]}"; do
    assert_file_exists "$LIB_DIR/$lib" "Library file $lib should exist"
    # Check for either shebang format
    if grep -q "#!/usr/bin/env bash" "$LIB_DIR/$lib" || grep -q "#!/bin/bash" "$LIB_DIR/$lib"; then
      print_assert_result "PASS" "Library file $lib should be a bash script: $lib contains bash shebang" "$(get_caller_info)"
    else
      print_assert_result "FAIL" "Library file $lib should be a bash script: $lib does not contain bash shebang" "$(get_caller_info)"
      return $ASSERT_FAILURE
    fi
  done
}

function test_errors_library_functions() {
  log_step "Testing errors library functions are available"

  # Test that error code variables are defined (only those that actually exist)
  assert_not_null "$EC_OKAY" "EC_OKAY should be defined"
  assert_not_null "$EC_GENERAL" "EC_GENERAL should be defined"
  assert_not_null "$EC_KGSM_ROOT" "EC_KGSM_ROOT should be defined"
  assert_not_null "$EC_FAILED_CONFIG" "EC_FAILED_CONFIG should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_FAILED_SOURCE" "EC_FAILED_SOURCE should be defined"
  assert_not_null "$EC_MISSING_ARG" "EC_MISSING_ARG should be defined"
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FAILED_CD" "EC_FAILED_CD should be defined"
  assert_not_null "$EC_FAILED_CP" "EC_FAILED_CP should be defined"
  assert_not_null "$EC_FAILED_RM" "EC_FAILED_RM should be defined"
  assert_not_null "$EC_FAILED_TEMPLATE" "EC_FAILED_TEMPLATE should be defined"
  assert_not_null "$EC_FAILED_DOWNLOAD" "EC_FAILED_DOWNLOAD should be defined"
  assert_not_null "$EC_FAILED_DEPLOY" "EC_FAILED_DEPLOY should be defined"
  assert_not_null "$EC_FAILED_MKDIR" "EC_FAILED_MKDIR should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_FAILED_SED" "EC_FAILED_SED should be defined"
  assert_not_null "$EC_SYSTEMD" "EC_SYSTEMD should be defined"
  assert_not_null "$EC_UFW" "EC_UFW should be defined"
  assert_not_null "$EC_MALFORMED_INSTANCE" "EC_MALFORMED_INSTANCE should be defined"
  assert_not_null "$EC_MISSING_DEPENDENCY" "EC_MISSING_DEPENDENCY should be defined"
  assert_not_null "$EC_FAILED_LN" "EC_FAILED_LN should be defined"
  assert_not_null "$EC_FAILED_UPDATE_CONFIG" "EC_FAILED_UPDATE_CONFIG should be defined"

  # Test that error code variables are numeric
  assert_matches "$EC_OKAY" "^[0-9]+$" "EC_OKAY should be numeric"
  assert_matches "$EC_GENERAL" "^[0-9]+$" "EC_GENERAL should be numeric"
}

function test_config_library_functions() {
  log_step "Testing config library functions are available"

  # Test core config functions
  assert_function_exists "__get_config_value" "Config function __get_config_value should be available"
  assert_function_exists "__add_or_update_config" "Config function __add_or_update_config should be available"
  assert_function_exists "__remove_config" "Config function __remove_config should be available"
  assert_function_exists "__validate_config_key" "Config function __validate_config_key should be available"
  assert_function_exists "__validate_config_value" "Config function __validate_config_value should be available"
  assert_function_exists "__get_all_config_keys" "Config function __get_all_config_keys should be available"
  assert_function_exists "__list_config_values" "Config function __list_config_values should be available"
  assert_function_exists "__set_config_value" "Config function __set_config_value should be available"
  assert_function_exists "__get_config_value_safe" "Config function __get_config_value_safe should be available"
  assert_function_exists "__reset_config" "Config function __reset_config should be available"
  assert_function_exists "__validate_current_config" "Config function __validate_current_config should be available"
  assert_function_exists "__merge_user_config_with_default" "Config function __merge_user_config_with_default should be available"

  # Test that config variables are set
  assert_not_null "$CONFIG_FILE" "CONFIG_FILE should be defined"
  assert_not_null "$DEFAULT_CONFIG_FILE" "DEFAULT_CONFIG_FILE should be defined"
  assert_not_null "$MERGED_CONFIG_FILE" "MERGED_CONFIG_FILE should be defined"

  # Test that config files exist
  assert_file_exists "$CONFIG_FILE" "CONFIG_FILE should exist"
  assert_file_exists "$DEFAULT_CONFIG_FILE" "DEFAULT_CONFIG_FILE should exist"
}

function test_logging_library_functions() {
  log_step "Testing logging library functions are available"

  # Test logging functions (only those that actually exist)
  assert_function_exists "__print_info" "Logging function __print_info should be available"
  assert_function_exists "__print_success" "Logging function __print_success should be available"
  assert_function_exists "__print_warning" "Logging function __print_warning should be available"
  assert_function_exists "__print_error" "Logging function __print_error should be available"
  assert_function_exists "__log_message" "Logging function __log_message should be available"
}

function test_parser_library_functions() {
  log_step "Testing parser library functions are available"

  # Test parser functions (only those that actually exist)
  assert_function_exists "__parse_ufw_to_upnp_ports" "Parser function __parse_ufw_to_upnp_ports should be available"
  assert_function_exists "__parse_docker_compose_to_ufw_ports" "Parser function __parse_docker_compose_to_ufw_ports should be available"
  assert_function_exists "__extract_blueprint_name" "Parser function __extract_blueprint_name should be available"
}

function test_validation_library_functions() {
  log_step "Testing validation library functions are available"

  # Test validation functions (only those that actually exist)
  assert_function_exists "validate_blueprint" "Validation function validate_blueprint should be available"
  assert_function_exists "validate_blueprint_exists" "Validation function validate_blueprint_exists should be available"
  assert_function_exists "validate_blueprint_readable" "Validation function validate_blueprint_readable should be available"
  assert_function_exists "validate_blueprint_format" "Validation function validate_blueprint_format should be available"
  assert_function_exists "validate_native_blueprint_format" "Validation function validate_native_blueprint_format should be available"
  assert_function_exists "validate_container_blueprint_format" "Validation function validate_container_blueprint_format should be available"
  assert_function_exists "validate_not_empty" "Validation function validate_not_empty should be available"
  assert_function_exists "validate_directory_exists" "Validation function validate_directory_exists should be available"
  assert_function_exists "validate_directory_writable" "Validation function validate_directory_writable should be available"
}

function test_system_library_functions() {
  log_step "Testing system library functions are available"

  # Test system functions (only those that actually exist)
  assert_function_exists "__create_dir" "System function __create_dir should be available"
  assert_function_exists "__create_file" "System function __create_file should be available"
  assert_function_exists "__source" "System function __source should be available"
}

function test_loader_library_functions() {
  log_step "Testing loader library functions are available"

  # Test loader functions (only those that actually exist)
  assert_function_exists "__find_or_fail" "Loader function __find_or_fail should be available"
  assert_function_exists "__find_native_default_blueprint" "Loader function __find_native_default_blueprint should be available"
  assert_function_exists "__find_default_container_blueprint" "Loader function __find_default_container_blueprint should be available"
  assert_function_exists "__find_default_blueprint" "Loader function __find_default_blueprint should be available"
  assert_function_exists "__find_custom_native_blueprint" "Loader function __find_custom_native_blueprint should be available"
  assert_function_exists "__find_custom_container_blueprint" "Loader function __find_custom_container_blueprint should be available"
  assert_function_exists "__find_custom_blueprint" "Loader function __find_custom_blueprint should be available"
  assert_function_exists "__find_blueprint" "Loader function __find_blueprint should be available"
  assert_function_exists "__find_core_module" "Loader function __find_core_module should be available"
  assert_function_exists "__find_command" "Loader function __find_command should be available"
  assert_function_exists "__find_instance_config" "Loader function __find_instance_config should be available"
  assert_function_exists "__find_template" "Loader function __find_template should be available"
  assert_function_exists "__find_override" "Loader function __find_override should be available"
  assert_function_exists "__source_blueprint" "Loader function __source_blueprint should be available"
  assert_function_exists "__source_instance" "Loader function __source_instance should be available"
  assert_function_exists "__get_instance_config_value" "Loader function __get_instance_config_value should be available"
}

function test_common_library_reload_protection() {
  log_step "Testing common library reload protection"

  # Test that common.sh doesn't reload if already loaded
  local original_loaded="$KGSM_COMMON_LOADED"

  # Source common.sh again
  source "$COMMON_LIBRARY"

  # Should still be set to the same value
  assert_equals "$original_loaded" "$KGSM_COMMON_LOADED" "KGSM_COMMON_LOADED should not change on reload"
}

function test_common_library_environment_variables() {
  log_step "Testing common library environment variables"

  # Test that all expected environment variables are set
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_not_null "$KGSM_COMMON_LOADED" "KGSM_COMMON_LOADED should be set"
  assert_not_null "$KGSM_LOADER_LOADED" "KGSM_LOADER_LOADED should be set"
  assert_not_null "$KGSM_SYSTEM_LOADED" "KGSM_SYSTEM_LOADED should be set"
  assert_not_null "$KGSM_ERRORS_LOADED" "KGSM_ERRORS_LOADED should be set"
  assert_not_null "$KGSM_CONFIG_LOADED" "KGSM_CONFIG_LOADED should be set"
  assert_not_null "$KGSM_LOGGING_LOADED" "KGSM_LOGGING_LOADED should be set"
  assert_not_null "$KGSM_PARSER_LOADED" "KGSM_PARSER_LOADED should be set"
  assert_not_null "$KGSM_VALIDATION_LOADED" "KGSM_VALIDATION_LOADED should be set"

  # Test that all loaded flags are set to 1
  assert_equals "$KGSM_COMMON_LOADED" "1" "KGSM_COMMON_LOADED should be 1"
  assert_equals "$KGSM_LOADER_LOADED" "1" "KGSM_LOADER_LOADED should be 1"
  assert_equals "$KGSM_SYSTEM_LOADED" "1" "KGSM_SYSTEM_LOADED should be 1"
  assert_equals "$KGSM_ERRORS_LOADED" "1" "KGSM_ERRORS_LOADED should be 1"
  assert_equals "$KGSM_CONFIG_LOADED" "1" "KGSM_CONFIG_LOADED should be 1"
  assert_equals "$KGSM_LOGGING_LOADED" "1" "KGSM_LOGGING_LOADED should be 1"
  assert_equals "$KGSM_PARSER_LOADED" "1" "KGSM_PARSER_LOADED should be 1"
  assert_equals "$KGSM_VALIDATION_LOADED" "1" "KGSM_VALIDATION_LOADED should be 1"
}

function test_common_library_function_availability() {
  log_step "Testing that all expected functions are available after sourcing"

  # Test a few key functions from each library to ensure they're available
  assert_function_exists "__print_error" "Error printing function should be available"
  assert_function_exists "__get_config_value" "Config function should be available"
  assert_function_exists "__print_info" "Logging function should be available"
  assert_function_exists "validate_blueprint" "Validation function should be available"
  assert_function_exists "__create_dir" "System function should be available"
  assert_function_exists "__find_core_module" "Loader function should be available"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting comprehensive common library tests"

  # Initialize test environment
  setup_test

  # Basic functionality tests
  test_common_library_existence
  test_library_files_existence
  test_common_library_sourcing # This sources the library for all subsequent tests
  test_kgsm_root_detection

  # Run function availability tests (after library is sourced)
  test_errors_library_functions
  test_config_library_functions
  test_logging_library_functions
  test_parser_library_functions
  test_validation_library_functions
  test_system_library_functions
  test_loader_library_functions

  # Behavioral consistency tests
  test_common_library_reload_protection
  test_common_library_environment_variables
  test_common_library_function_availability

  log_test "Comprehensive common library tests completed successfully"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All comprehensive common library tests completed successfully"
  else
    fail_test "Some comprehensive common library tests failed"
  fi
}

main "$@"
