#!/usr/bin/env bash

# KGSM Blueprint Logic Handler Unit Tests
#
# Tests all __logic_* functions from [blueprints.sh](http://_vscodecontentref_/0)
# Uses real blueprints: factorio, terraria, starbound, necesse (native)
# and vrising (container) to cover all blueprint variations.

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="blueprints_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/blueprints.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up blueprint logic tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Blueprint handler should exist"

  # Source the handler
  source "$HANDLER"

  # Verify required error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_BLUEPRINT_NOT_FOUND" "EC_BLUEPRINT_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_BLUEPRINT" "EC_INVALID_BLUEPRINT should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_SUCCESS_BLUEPRINT_FOUND" "EC_SUCCESS_BLUEPRINT_FOUND should be defined"
  assert_not_null "$EC_SUCCESS_BLUEPRINT_LISTED" "EC_SUCCESS_BLUEPRINT_LISTED should be defined"
  assert_not_null "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED should be defined"

  # Verify blueprint directories exist
  assert_dir_exists "$BLUEPRINTS_NATIVE_DEFAULT_DIR" "Native default blueprints should exist"
  assert_dir_exists "$BLUEPRINTS_CONTAINER_DEFAULT_DIR" "Container default blueprints should exist"

  # Verify test blueprints exist
  assert_file_exists "$BLUEPRINTS_NATIVE_DEFAULT_DIR/factorio.bp" "Factorio blueprint should exist"
  assert_file_exists "$BLUEPRINTS_NATIVE_DEFAULT_DIR/terraria.bp" "Terraria blueprint should exist"
  assert_file_exists "$BLUEPRINTS_NATIVE_DEFAULT_DIR/starbound.bp" "Starbound blueprint should exist"
  assert_file_exists "$BLUEPRINTS_NATIVE_DEFAULT_DIR/necesse.bp" "Necesse blueprint should exist"
  assert_file_exists "$BLUEPRINTS_CONTAINER_DEFAULT_DIR/vrising.docker-compose.yml" "VRising blueprint should exist"

  # Verify logic functions are exported
  assert_function_exists "__logic_get_blueprint_type" "get_blueprint_type should be exported"
  assert_function_exists "__logic_validate_blueprint" "validate_blueprint should be exported"
  assert_function_exists "__logic_get_blueprint_path" "get_blueprint_path should be exported"
  assert_function_exists "__logic_list_blueprints" "list_blueprints should be exported"
  assert_function_exists "__logic_find_native_blueprint" "find_native_blueprint should be exported"
  assert_function_exists "__logic_list_native_blueprints" "list_native_blueprints should be exported"
  assert_function_exists "__logic_get_native_blueprint_info" "get_native_blueprint_info should be exported"
  assert_function_exists "__logic_find_container_blueprint" "find_container_blueprint should be exported"
  assert_function_exists "__logic_list_container_blueprints" "list_container_blueprints should be exported"
  assert_function_exists "__logic_get_container_blueprint_info" "get_container_blueprint_info should be exported"

  log_test_step "Blueprint logic test environment validated"
}

# =============================================================================
# __logic_get_blueprint_type() TESTS
# =============================================================================

function test_get_blueprint_type_native() {
  log_test_step "Testing __logic_get_blueprint_type with native blueprint"

  local output
  output=$(__logic_get_blueprint_type "factorio")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return success for native blueprint"
  assert_equals "native" "$output" "Should identify factorio as native type"
}

function test_get_blueprint_type_container() {
  log_test_step "Testing __logic_get_blueprint_type with container blueprint"

  local output
  output=$(__logic_get_blueprint_type "vrising")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return success for container blueprint"
  assert_equals "container" "$output" "Should identify vrising as container type"
}

function test_get_blueprint_type_not_found() {
  log_test_step "Testing __logic_get_blueprint_type with non-existent blueprint"

  __logic_get_blueprint_type "nonexistent-blueprint-xyz" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return blueprint not found error"
}

function test_get_blueprint_type_empty_param() {
  log_test_step "Testing __logic_get_blueprint_type with empty parameter"

  __logic_get_blueprint_type "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

# =============================================================================
# __logic_validate_blueprint() TESTS
# =============================================================================

function test_validate_blueprint_valid_native() {
  log_test_step "Testing __logic_validate_blueprint with valid native blueprint"

  __logic_validate_blueprint "terraria" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should validate terraria blueprint successfully"
}

function test_validate_blueprint_valid_container() {
  log_test_step "Testing __logic_validate_blueprint with valid container blueprint"

  __logic_validate_blueprint "vrising" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should validate vrising blueprint successfully"
}

function test_validate_blueprint_not_found() {
  log_test_step "Testing __logic_validate_blueprint with non-existent blueprint"

  __logic_validate_blueprint "does-not-exist" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return blueprint not found error"
}

function test_validate_blueprint_empty_param() {
  log_test_step "Testing __logic_validate_blueprint with empty parameter"

  __logic_validate_blueprint "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

# =============================================================================
# __logic_get_blueprint_path() TESTS
# =============================================================================

function test_get_blueprint_path_native() {
  log_test_step "Testing __logic_get_blueprint_path with native blueprint"

  local output
  output=$(__logic_get_blueprint_path "starbound")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return success for starbound"
  assert_contains "$output" "starbound.bp" "Path should contain blueprint filename"
  assert_file_exists "$output" "Returned path should exist"
}

function test_get_blueprint_path_container() {
  log_test_step "Testing __logic_get_blueprint_path with container blueprint"

  local output
  output=$(__logic_get_blueprint_path "vrising")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return success for vrising"
  assert_contains "$output" "vrising.docker-compose.yml" "Path should contain docker-compose filename"
  assert_file_exists "$output" "Returned path should exist"
}

function test_get_blueprint_path_not_found() {
  log_test_step "Testing __logic_get_blueprint_path with non-existent blueprint"

  __logic_get_blueprint_path "missing-blueprint" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return blueprint not found error"
}

function test_get_blueprint_path_empty_param() {
  log_test_step "Testing __logic_get_blueprint_path with empty parameter"

  __logic_get_blueprint_path "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

function test_get_blueprint_path_permission_denied() {
  log_test_step "Testing __logic_get_blueprint_path with unreadable blueprint"

  local blueprint_path="$BLUEPRINTS_NATIVE_DEFAULT_DIR/necesse.bp"
  local original_perms=$(stat -c "%a" "$blueprint_path")

  # Make unreadable
  chmod 000 "$blueprint_path"

  # Test
  __logic_get_blueprint_path "necesse" 2> /dev/null
  local exit_code=$?

  # Restore immediately
  chmod "$original_perms" "$blueprint_path"

  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" "Should return invalid blueprint error for unreadable file"
}

# =============================================================================
# __logic_list_blueprints() TESTS
# =============================================================================

function test_list_blueprints_all() {
  log_test_step "Testing __logic_list_blueprints with 'all' source"

  local output
  output=$(__logic_list_blueprints "all")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
  assert_contains "$output" "factorio" "Should list factorio"
  assert_contains "$output" "terraria" "Should list terraria"
  assert_contains "$output" "starbound" "Should list starbound"
  assert_contains "$output" "necesse" "Should list necesse"
  assert_contains "$output" "vrising" "Should list vrising"
}

function test_list_blueprints_default_source() {
  log_test_step "Testing __logic_list_blueprints with default source parameter"

  local output
  output=$(__logic_list_blueprints)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
  assert_not_null "$output" "Should return blueprint list"
}

function test_list_blueprints_sorted() {
  log_test_step "Testing __logic_list_blueprints output is sorted"

  local output
  output=$(__logic_list_blueprints "all")

  # Check if output is sorted (compare with sorted version)
  local sorted_output
  sorted_output=$(echo "$output" | sort)

  assert_equals "$sorted_output" "$output" "Output should be sorted alphabetically"
}

# =============================================================================
# __logic_find_native_blueprint() TESTS
# =============================================================================

function test_find_native_blueprint_exists() {
  log_test_step "Testing __logic_find_native_blueprint with existing blueprint"

  local output
  output=$(__logic_find_native_blueprint "factorio")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should return success code"
  assert_contains "$output" "factorio.bp" "Path should contain factorio.bp"
  assert_file_exists "$output" "Returned path should exist"
}

function test_find_native_blueprint_with_extension() {
  log_test_step "Testing __logic_find_native_blueprint with .bp extension"

  local output
  output=$(__logic_find_native_blueprint "terraria.bp")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should return success code"
  assert_contains "$output" "terraria.bp" "Path should contain terraria.bp"
}

function test_find_native_blueprint_not_found() {
  log_test_step "Testing __logic_find_native_blueprint with non-existent blueprint"

  __logic_find_native_blueprint "nonexistent" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return blueprint not found error"
}

function test_find_native_blueprint_empty_param() {
  log_test_step "Testing __logic_find_native_blueprint with empty parameter"

  __logic_find_native_blueprint "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

function test_find_native_blueprint_priority() {
  log_test_step "Testing __logic_find_native_blueprint custom > default priority"

  # Create custom blueprint
  local custom_blueprint="$BLUEPRINTS_NATIVE_CUSTOM_DIR/test-priority.bp"
  cat > "$custom_blueprint" << EOF
name=test-priority
executable_file=test.sh
executable_arguments=""
EOF

  # Find it
  local output
  output=$(__logic_find_native_blueprint "test-priority")
  local exit_code=$?

  # Clean up
  rm -f "$custom_blueprint"

  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should find custom blueprint"
  assert_contains "$output" "custom" "Should return custom directory path"
}

# =============================================================================
# __logic_list_native_blueprints() TESTS
# =============================================================================

function test_list_native_blueprints_all() {
  log_test_step "Testing __logic_list_native_blueprints with 'all' source"

  local output
  output=$(__logic_list_native_blueprints "all")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
  assert_contains "$output" "factorio" "Should list factorio"
  assert_contains "$output" "terraria" "Should list terraria"
  assert_contains "$output" "starbound" "Should list starbound"
  assert_contains "$output" "necesse" "Should list necesse"
}

function test_list_native_blueprints_default() {
  log_test_step "Testing __logic_list_native_blueprints with 'default' source"

  local output
  output=$(__logic_list_native_blueprints "default")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
  assert_contains "$output" "factorio" "Should list default factorio"
}

function test_list_native_blueprints_custom() {
  log_test_step "Testing __logic_list_native_blueprints with 'custom' source"

  # Create a custom blueprint
  local custom_bp="$BLUEPRINTS_NATIVE_CUSTOM_DIR/test-custom.bp"
  cat > "$custom_bp" << EOF
name=test-custom
executable_file=test.sh
executable_arguments=""
EOF

  local output
  output=$(__logic_list_native_blueprints "custom")
  local exit_code=$?

  # Clean up
  rm -f "$custom_bp"

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
  assert_contains "$output" "test-custom" "Should list custom blueprint"
}

function test_list_native_blueprints_invalid_source() {
  log_test_step "Testing __logic_list_native_blueprints with invalid source"

  __logic_list_native_blueprints "invalid" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

function test_list_native_blueprints_empty_source() {
  log_test_step "Testing __logic_list_native_blueprints with empty source"

  __logic_list_native_blueprints "" 2> /dev/null
  local exit_code=$?

  # When no argument is passed, it defaults to "all", so output is still expected
  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
}

function test_list_native_blueprints_sorted() {
  log_test_step "Testing __logic_list_native_blueprints output is sorted"

  local output
  output=$(__logic_list_native_blueprints "all")

  local sorted_output
  sorted_output=$(echo "$output" | sort)

  assert_equals "$sorted_output" "$output" "Output should be sorted alphabetically"
}

# =============================================================================
# __logic_get_native_blueprint_info() TESTS
# =============================================================================

function test_get_native_blueprint_info_factorio() {
  log_test_step "Testing __logic_get_native_blueprint_info with factorio (non-Steam)"

  local output
  output=$(__logic_get_native_blueprint_info "factorio")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "$exit_code" "Should return success code"
  assert_contains "$output" "name=factorio" "Should contain blueprint name"
  assert_contains "$output" "blueprint_type=native" "Should identify as native type"
  assert_contains "$output" "executable_file=" "Should contain executable_file field"
  assert_contains "$output" "blueprint_path=" "Should contain blueprint_path field"
}

function test_get_native_blueprint_info_starbound() {
  log_test_step "Testing __logic_get_native_blueprint_info with starbound (Steam with account)"

  local output
  output=$(__logic_get_native_blueprint_info "starbound")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "$exit_code" "Should return success code"
  assert_contains "$output" "name=starbound" "Should contain blueprint name"
  assert_contains "$output" "steam_app_id=" "Should contain steam_app_id field"
  assert_contains "$output" "is_steam_account_required=" "Should contain account requirement field"
}

function test_get_native_blueprint_info_necesse() {
  log_test_step "Testing __logic_get_native_blueprint_info with necesse (Steam no account)"

  local output
  output=$(__logic_get_native_blueprint_info "necesse")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "$exit_code" "Should return success code"
  assert_contains "$output" "name=necesse" "Should contain blueprint name"
  assert_contains "$output" "steam_app_id=" "Should contain steam_app_id field"
}

function test_get_native_blueprint_info_not_found() {
  log_test_step "Testing __logic_get_native_blueprint_info with non-existent blueprint"

  __logic_get_native_blueprint_info "nonexistent" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return blueprint not found error"
}

function test_get_native_blueprint_info_empty_param() {
  log_test_step "Testing __logic_get_native_blueprint_info with empty parameter"

  __logic_get_native_blueprint_info "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

function test_get_native_blueprint_info_permission_denied() {
  log_test_step "Testing __logic_get_native_blueprint_info with unreadable blueprint"

  local blueprint_path="$BLUEPRINTS_NATIVE_DEFAULT_DIR/terraria.bp"
  local original_perms=$(stat -c "%a" "$blueprint_path")

  # Make unreadable
  chmod 000 "$blueprint_path"

  # Test
  __logic_get_native_blueprint_info "terraria" 2> /dev/null
  local exit_code=$?

  # Restore immediately
  chmod "$original_perms" "$blueprint_path"

  assert_equals "$EC_PERMISSION" "$exit_code" "Should return permission error"
}

function test_get_native_blueprint_info_output_format() {
  log_test_step "Testing __logic_get_native_blueprint_info output format"

  local output
  output=$(__logic_get_native_blueprint_info "factorio")

  # Verify all required fields are present
  assert_contains "$output" "name=" "Should contain name field"
  assert_contains "$output" "ports=" "Should contain ports field"
  assert_contains "$output" "steam_app_id=" "Should contain steam_app_id field"
  assert_contains "$output" "is_steam_account_required=" "Should contain is_steam_account_required field"
  assert_contains "$output" "executable_file=" "Should contain executable_file field"
  assert_contains "$output" "level_name=" "Should contain level_name field"
  assert_contains "$output" "executable_subdirectory=" "Should contain executable_subdirectory field"
  assert_contains "$output" "executable_arguments=" "Should contain executable_arguments field"
  assert_contains "$output" "stop_command=" "Should contain stop_command field"
  assert_contains "$output" "save_command=" "Should contain save_command field"
  assert_contains "$output" "blueprint_type=native" "Should contain blueprint_type field"
  assert_contains "$output" "blueprint_path=" "Should contain blueprint_path field"
}

# =============================================================================
# __logic_find_container_blueprint() TESTS
# =============================================================================

function test_find_container_blueprint_exists() {
  log_test_step "Testing __logic_find_container_blueprint with existing blueprint"

  local output
  output=$(__logic_find_container_blueprint "vrising")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should return success code"
  assert_contains "$output" "vrising.docker-compose.yml" "Path should contain docker-compose file"
  assert_file_exists "$output" "Returned path should exist"
}

function test_find_container_blueprint_with_extension() {
  log_test_step "Testing __logic_find_container_blueprint with .docker-compose.yml extension"

  local output
  output=$(__logic_find_container_blueprint "vrising.docker-compose.yml")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should return success code"
  assert_contains "$output" "vrising.docker-compose.yml" "Path should contain docker-compose file"
}

function test_find_container_blueprint_not_found() {
  log_test_step "Testing __logic_find_container_blueprint with non-existent blueprint"

  __logic_find_container_blueprint "nonexistent" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return blueprint not found error"
}

function test_find_container_blueprint_empty_param() {
  log_test_step "Testing __logic_find_container_blueprint with empty parameter"

  __logic_find_container_blueprint "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

# =============================================================================
# __logic_list_container_blueprints() TESTS
# =============================================================================

function test_list_container_blueprints_all() {
  log_test_step "Testing __logic_list_container_blueprints with 'all' source"

  local output
  output=$(__logic_list_container_blueprints "all")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
  assert_contains "$output" "vrising" "Should list vrising"
}

function test_list_container_blueprints_default() {
  log_test_step "Testing __logic_list_container_blueprints with 'default' source"

  local output
  output=$(__logic_list_container_blueprints "default")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
}

function test_list_container_blueprints_custom() {
  log_test_step "Testing __logic_list_container_blueprints with 'custom' source"

  local output
  output=$(__logic_list_container_blueprints "custom")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code (even if empty)"
}

function test_list_container_blueprints_invalid_source() {
  log_test_step "Testing __logic_list_container_blueprints with invalid source"

  __logic_list_container_blueprints "invalid" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

# =============================================================================
# __logic_get_container_blueprint_info() TESTS
# =============================================================================

function test_get_container_blueprint_info_vrising() {
  log_test_step "Testing __logic_get_container_blueprint_info with vrising"

  local output
  output=$(__logic_get_container_blueprint_info "vrising")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "$exit_code" "Should return success code"
  assert_contains "$output" "name=vrising" "Should contain blueprint name"
  assert_contains "$output" "blueprint_type=container" "Should identify as container type"
  assert_contains "$output" "blueprint_path=" "Should contain blueprint_path field"
}

function test_get_container_blueprint_info_not_found() {
  log_test_step "Testing __logic_get_container_blueprint_info with non-existent blueprint"

  __logic_get_container_blueprint_info "nonexistent" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return blueprint not found error"
}

function test_get_container_blueprint_info_empty_param() {
  log_test_step "Testing __logic_get_container_blueprint_info with empty parameter"

  __logic_get_container_blueprint_info "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid argument error"
}

function test_get_container_blueprint_info_output_format() {
  log_test_step "Testing __logic_get_container_blueprint_info output format"

  local output
  output=$(__logic_get_container_blueprint_info "vrising")

  # Verify all required fields are present (even if empty)
  assert_contains "$output" "name=" "Should contain name field"
  assert_contains "$output" "ports=" "Should contain ports field"
  assert_contains "$output" "steam_app_id=" "Should contain steam_app_id field (empty)"
  assert_contains "$output" "is_steam_account_required=" "Should contain is_steam_account_required field (empty)"
  assert_contains "$output" "executable_file=" "Should contain executable_file field (empty)"
  assert_contains "$output" "level_name=" "Should contain level_name field (empty)"
  assert_contains "$output" "executable_subdirectory=" "Should contain executable_subdirectory field (empty)"
  assert_contains "$output" "executable_arguments=" "Should contain executable_arguments field (empty)"
  assert_contains "$output" "stop_command=" "Should contain stop_command field (empty)"
  assert_contains "$output" "save_command=" "Should contain save_command field (empty)"
  assert_contains "$output" "blueprint_type=container" "Should contain blueprint_type field"
  assert_contains "$output" "blueprint_path=" "Should contain blueprint_path field"
}

function test_get_container_blueprint_info_permission_denied() {
  log_test_step "Testing __logic_get_container_blueprint_info with unreadable blueprint"

  local blueprint_path="$BLUEPRINTS_CONTAINER_DEFAULT_DIR/vrising.docker-compose.yml"
  local original_perms=$(stat -c "%a" "$blueprint_path")

  # Make unreadable
  chmod 000 "$blueprint_path"

  # Test
  __logic_get_container_blueprint_info "vrising" 2> /dev/null
  local exit_code=$?

  # Restore immediately
  chmod "$original_perms" "$blueprint_path"

  assert_equals "$EC_PERMISSION" "$exit_code" "Should return permission error"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting blueprint logic handler tests"

  setup_test

  # __logic_get_blueprint_type tests
  test_get_blueprint_type_native
  test_get_blueprint_type_container
  test_get_blueprint_type_not_found
  test_get_blueprint_type_empty_param

  # __logic_validate_blueprint tests
  test_validate_blueprint_valid_native
  test_validate_blueprint_valid_container
  test_validate_blueprint_not_found
  test_validate_blueprint_empty_param

  # __logic_get_blueprint_path tests
  test_get_blueprint_path_native
  test_get_blueprint_path_container
  test_get_blueprint_path_not_found
  test_get_blueprint_path_empty_param
  test_get_blueprint_path_permission_denied

  # __logic_list_blueprints tests
  test_list_blueprints_all
  test_list_blueprints_default_source
  test_list_blueprints_sorted

  # __logic_find_native_blueprint tests
  test_find_native_blueprint_exists
  test_find_native_blueprint_with_extension
  test_find_native_blueprint_not_found
  test_find_native_blueprint_empty_param
  test_find_native_blueprint_priority

  # __logic_list_native_blueprints tests
  test_list_native_blueprints_all
  test_list_native_blueprints_default
  test_list_native_blueprints_custom
  test_list_native_blueprints_invalid_source
  test_list_native_blueprints_empty_source
  test_list_native_blueprints_sorted

  # __logic_get_native_blueprint_info tests
  test_get_native_blueprint_info_factorio
  test_get_native_blueprint_info_starbound
  test_get_native_blueprint_info_necesse
  test_get_native_blueprint_info_not_found
  test_get_native_blueprint_info_empty_param
  test_get_native_blueprint_info_permission_denied
  test_get_native_blueprint_info_output_format

  # __logic_find_container_blueprint tests
  test_find_container_blueprint_exists
  test_find_container_blueprint_with_extension
  test_find_container_blueprint_not_found
  test_find_container_blueprint_empty_param

  # __logic_list_container_blueprints tests
  test_list_container_blueprints_all
  test_list_container_blueprints_default
  test_list_container_blueprints_custom
  test_list_container_blueprints_invalid_source

  # __logic_get_container_blueprint_info tests
  test_get_container_blueprint_info_vrising
  test_get_container_blueprint_info_not_found
  test_get_container_blueprint_info_empty_param
  test_get_container_blueprint_info_output_format
  test_get_container_blueprint_info_permission_denied

  log_test_step "Blueprint logic handler tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All blueprint logic tests passed"
  else
    fail_test "Some blueprint logic tests failed"
  fi
}

main "$@"
