#!/usr/bin/env bash

# KGSM Blueprints Logic Unit Tests
#
# This test suite provides comprehensive unit testing for the pure logic functions
# in commands/handlers/blueprints.sh. These tests focus on testing the business logic
# in isolation without external dependencies or user-facing I/O.

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="blueprints_logic"

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# Create a test blueprint file
function create_test_native_blueprint() {
  local blueprint_name="$1"
  local blueprint_dir="${2:-$KGSM_ROOT/blueprints/custom/native}"

  # Ensure custom blueprint directory exists
  mkdir -p "$blueprint_dir"

  local blueprint_file="$blueprint_dir/${blueprint_name}.bp"
  cat >"$blueprint_file" <<'EOF'
# Test Native Blueprint
blueprint_name="testgame"
blueprint_ports="7777:7777/tcp|7778:7778/udp"
blueprint_steam_app_id="123456"
blueprint_is_steam_account_required="true"
blueprint_executable_file="gameserver"
blueprint_level_name="World1"
blueprint_executable_subdirectory="bin"
blueprint_executable_arguments="-config server.cfg"
blueprint_stop_command="/quit"
blueprint_save_command="/save"
EOF

  echo "$blueprint_file"
}

# Create a test container blueprint file
function create_test_container_blueprint() {
  local blueprint_name="$1"
  local blueprint_dir="${2:-$KGSM_ROOT/blueprints/custom/container}"

  # Ensure custom blueprint directory exists
  mkdir -p "$blueprint_dir"

  local blueprint_file="$blueprint_dir/${blueprint_name}.docker-compose.yml"
  cat >"$blueprint_file" <<'EOF'
version: '3.8'
services:
  gameserver:
    image: test/gameserver:latest
    ports:
      - "25565:25565/tcp"
      - "25566:25566/udp"
    environment:
      - SERVER_NAME=TestServer
EOF

  echo "$blueprint_file"
}

# Cleanup test blueprint
function cleanup_test_blueprint() {
  local blueprint_file="$1"
  [[ -f "$blueprint_file" ]] && rm -f "$blueprint_file"
}

# =============================================================================
# TEST FUNCTIONS - SETUP
# =============================================================================

function setup_test() {
  log_step "Setting up blueprints logic tests"

  # Verify test environment is properly initialized
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Verify blueprint directories exist
  assert_dir_exists "$KGSM_ROOT/blueprints" "blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default" "default blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default/native" "default native blueprints directory should exist"
  assert_dir_exists "$KGSM_ROOT/blueprints/default/container" "default container blueprints directory should exist"

  # Ensure custom directories exist
  mkdir -p "$KGSM_ROOT/blueprints/custom/native"
  mkdir -p "$KGSM_ROOT/blueprints/custom/container"

  # Source the blueprints logic library
  local logic_lib="$KGSM_ROOT/commands/handlers/blueprints.sh"
  assert_file_exists "$logic_lib" "blueprints logic library should exist"

  # shellcheck disable=SC1090
  source "$logic_lib" || {
    log_error "Failed to source blueprints logic library"
    exit 1
  }

  log_test "Test environment validated successfully"
}

# =============================================================================
# TEST FUNCTIONS - BLUEPRINT TYPE DETECTION
# =============================================================================

function test_get_blueprint_type_native() {
  log_step "Testing __logic_get_blueprint_type with native blueprints"

  # Test with an existing native blueprint (factorio should exist in defaults)
  local blueprint_type
  blueprint_type=$(__logic_get_blueprint_type "factorio")
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed for existing native blueprint"
  assert_equals "$blueprint_type" "native" "Should return 'native' for .bp blueprint"

  log_test "Native blueprint type detection successful"
}

function test_get_blueprint_type_container() {
  log_step "Testing __logic_get_blueprint_type with container blueprints"

  # Create a test container blueprint
  local test_blueprint
  test_blueprint=$(create_test_container_blueprint "test_container")

  local blueprint_type
  blueprint_type=$(__logic_get_blueprint_type "test_container")
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed for existing container blueprint"
  assert_equals "$blueprint_type" "container" "Should return 'container' for docker-compose.yml blueprint"

  # Cleanup
  cleanup_test_blueprint "$test_blueprint"

  log_test "Container blueprint type detection successful"
}

function test_get_blueprint_type_invalid() {
  log_step "Testing __logic_get_blueprint_type with invalid blueprint"

  local blueprint_type
  blueprint_type=$(__logic_get_blueprint_type "nonexistent_blueprint_12345" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_BLUEPRINT_NOT_FOUND" "Should return EC_BLUEPRINT_NOT_FOUND for non-existent blueprint"
  assert_equals "$blueprint_type" "" "Should not output anything for non-existent blueprint"

  log_test "Invalid blueprint type detection successful"
}

function test_get_blueprint_type_empty() {
  log_step "Testing __logic_get_blueprint_type with empty parameter"

  local blueprint_type
  blueprint_type=$(__logic_get_blueprint_type "" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG for empty parameter"
  assert_equals "$blueprint_type" "" "Should not output anything for empty parameter"

  log_test "Empty parameter handling successful"
}

# =============================================================================
# TEST FUNCTIONS - BLUEPRINT VALIDATION
# =============================================================================

function test_validate_blueprint_valid() {
  log_step "Testing __logic_validate_blueprint with valid blueprint"

  __logic_validate_blueprint "factorio" >/dev/null 2>&1
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed for valid blueprint"

  log_test "Valid blueprint validation successful"
}

function test_validate_blueprint_invalid() {
  log_step "Testing __logic_validate_blueprint with invalid blueprint"

  __logic_validate_blueprint "nonexistent_blueprint_12345" >/dev/null 2>&1
  local exit_code=$?

  assert_not_equals "$exit_code" "0" "Should fail for non-existent blueprint"

  log_test "Invalid blueprint validation successful"
}

function test_validate_blueprint_empty() {
  log_step "Testing __logic_validate_blueprint with empty parameter"

  __logic_validate_blueprint "" >/dev/null 2>&1
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG for empty parameter"

  log_test "Empty parameter validation successful"
}

# =============================================================================
# TEST FUNCTIONS - BLUEPRINT PATH RETRIEVAL
# =============================================================================

function test_get_blueprint_path_native() {
  log_step "Testing __logic_get_blueprint_path with native blueprint"

  local blueprint_path
  blueprint_path=$(__logic_get_blueprint_path "factorio")
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed for existing native blueprint"
  assert_not_equals "$blueprint_path" "" "Should return non-empty path"
  assert_file_exists "$blueprint_path" "Returned path should exist"
  assert_contains "$blueprint_path" "factorio.bp" "Path should contain blueprint filename"

  log_test "Native blueprint path retrieval successful"
}

function test_get_blueprint_path_container() {
  log_step "Testing __logic_get_blueprint_path with container blueprint"

  # Create a test container blueprint
  local test_blueprint
  test_blueprint=$(create_test_container_blueprint "test_path_container")

  local blueprint_path
  blueprint_path=$(__logic_get_blueprint_path "test_path_container")
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed for existing container blueprint"
  assert_not_equals "$blueprint_path" "" "Should return non-empty path"
  assert_file_exists "$blueprint_path" "Returned path should exist"
  assert_contains "$blueprint_path" "test_path_container.docker-compose.yml" "Path should contain blueprint filename"

  # Cleanup
  cleanup_test_blueprint "$test_blueprint"

  log_test "Container blueprint path retrieval successful"
}

function test_get_blueprint_path_invalid() {
  log_step "Testing __logic_get_blueprint_path with invalid blueprint"

  local blueprint_path
  blueprint_path=$(__logic_get_blueprint_path "nonexistent_blueprint_12345" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_BLUEPRINT_NOT_FOUND" "Should return EC_BLUEPRINT_NOT_FOUND for non-existent blueprint"
  assert_equals "$blueprint_path" "" "Should not output anything for non-existent blueprint"

  log_test "Invalid blueprint path retrieval successful"
}

# =============================================================================
# TEST FUNCTIONS - NATIVE BLUEPRINT OPERATIONS
# =============================================================================

function test_find_native_blueprint_existing() {
  log_step "Testing __logic_find_native_blueprint with existing blueprint"

  local blueprint_path
  blueprint_path=$(__logic_find_native_blueprint "factorio")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_FOUND" "Should return EC_SUCCESS_BLUEPRINT_FOUND"
  assert_not_equals "$blueprint_path" "" "Should return non-empty path"
  assert_file_exists "$blueprint_path" "Returned path should exist"
  assert_contains "$blueprint_path" "factorio.bp" "Path should contain blueprint filename"

  log_test "Native blueprint found successfully"
}

function test_find_native_blueprint_custom_priority() {
  log_step "Testing __logic_find_native_blueprint custom blueprint priority"

  # Create a custom blueprint with the same name as a default blueprint
  local custom_blueprint
  custom_blueprint=$(create_test_native_blueprint "factorio")

  local blueprint_path
  blueprint_path=$(__logic_find_native_blueprint "factorio")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_FOUND" "Should find blueprint"
  assert_contains "$blueprint_path" "custom" "Should prioritize custom blueprint over default"

  # Cleanup
  cleanup_test_blueprint "$custom_blueprint"

  log_test "Custom blueprint priority verified"
}

function test_find_native_blueprint_strip_extension() {
  log_step "Testing __logic_find_native_blueprint extension stripping"

  local blueprint_path1 blueprint_path2
  blueprint_path1=$(__logic_find_native_blueprint "factorio")
  blueprint_path2=$(__logic_find_native_blueprint "factorio.bp")
  local exit_code1=$? exit_code2=$?

  assert_equals "$exit_code1" "$EC_SUCCESS_BLUEPRINT_FOUND" "Should find blueprint without extension"
  assert_equals "$exit_code2" "$EC_SUCCESS_BLUEPRINT_FOUND" "Should find blueprint with extension"
  assert_equals "$blueprint_path1" "$blueprint_path2" "Both should return the same path"

  log_test "Extension stripping verified"
}

function test_find_native_blueprint_nonexistent() {
  log_step "Testing __logic_find_native_blueprint with non-existent blueprint"

  local blueprint_path
  blueprint_path=$(__logic_find_native_blueprint "nonexistent_blueprint_12345" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_BLUEPRINT_NOT_FOUND" "Should return EC_BLUEPRINT_NOT_FOUND"
  assert_equals "$blueprint_path" "" "Should not output anything"

  log_test "Non-existent blueprint handled correctly"
}

function test_find_native_blueprint_empty() {
  log_step "Testing __logic_find_native_blueprint with empty parameter"

  local blueprint_path
  blueprint_path=$(__logic_find_native_blueprint "" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
  assert_equals "$blueprint_path" "" "Should not output anything"

  log_test "Empty parameter handled correctly"
}

# =============================================================================
# TEST FUNCTIONS - NATIVE BLUEPRINT LISTING
# =============================================================================

function test_list_native_blueprints_all() {
  log_step "Testing __logic_list_native_blueprints with 'all' source"

  local blueprint_list
  blueprint_list=$(__logic_list_native_blueprints "all")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_LISTED" "Should return EC_SUCCESS_BLUEPRINT_LISTED"
  assert_not_equals "$blueprint_list" "" "Should return non-empty list"
  assert_contains "$blueprint_list" "factorio" "Should include factorio blueprint"

  log_test "All native blueprints listed successfully"
}

function test_list_native_blueprints_default() {
  log_step "Testing __logic_list_native_blueprints with 'default' source"

  local blueprint_list
  blueprint_list=$(__logic_list_native_blueprints "default")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_LISTED" "Should return EC_SUCCESS_BLUEPRINT_LISTED"
  assert_not_equals "$blueprint_list" "" "Should return non-empty list (default blueprints exist)"
  assert_contains "$blueprint_list" "factorio" "Should include factorio blueprint from defaults"

  log_test "Default native blueprints listed successfully"
}

function test_list_native_blueprints_custom() {
  log_step "Testing __logic_list_native_blueprints with 'custom' source"

  # Create a custom blueprint first
  local custom_blueprint
  custom_blueprint=$(create_test_native_blueprint "test_custom_list")

  local blueprint_list
  blueprint_list=$(__logic_list_native_blueprints "custom")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_LISTED" "Should return EC_SUCCESS_BLUEPRINT_LISTED"
  assert_contains "$blueprint_list" "test_custom_list" "Should include custom blueprint"

  # Cleanup
  cleanup_test_blueprint "$custom_blueprint"

  log_test "Custom native blueprints listed successfully"
}

function test_list_native_blueprints_deduplication() {
  log_step "Testing __logic_list_native_blueprints deduplication"

  # Create a custom blueprint with same name as default
  local custom_blueprint
  custom_blueprint=$(create_test_native_blueprint "factorio")

  local blueprint_list
  blueprint_list=$(__logic_list_native_blueprints "all")
  local exit_code=$?

  # Count occurrences of "factorio" in the list
  local factorio_count
  factorio_count=$(echo "$blueprint_list" | grep -c "^factorio$")

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_LISTED" "Should return EC_SUCCESS_BLUEPRINT_LISTED"
  assert_equals "$factorio_count" "1" "Should list 'factorio' only once (deduplicated)"

  # Cleanup
  cleanup_test_blueprint "$custom_blueprint"

  log_test "Blueprint deduplication verified"
}

function test_list_native_blueprints_invalid_source() {
  log_step "Testing __logic_list_native_blueprints with invalid source"

  local blueprint_list
  blueprint_list=$(__logic_list_native_blueprints "invalid_source" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG for invalid source"

  log_test "Invalid source handled correctly"
}

function test_list_native_blueprints_empty_source() {
  log_step "Testing __logic_list_native_blueprints with empty source"

  local blueprint_list
  blueprint_list=$(__logic_list_native_blueprints "" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG for empty source"

  log_test "Empty source handled correctly"
}

# =============================================================================
# TEST FUNCTIONS - NATIVE BLUEPRINT INFO
# =============================================================================

function test_get_native_blueprint_info_valid() {
  log_step "Testing __logic_get_native_blueprint_info with valid blueprint"

  local info_data
  info_data=$(__logic_get_native_blueprint_info "factorio")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "Should return EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED"
  assert_not_equals "$info_data" "" "Should return non-empty data"
  assert_contains "$info_data" "name=" "Should include name field"
  assert_contains "$info_data" "blueprint_type=native" "Should include blueprint_type field"

  log_test "Native blueprint info retrieved successfully"
}

function test_get_native_blueprint_info_invalid() {
  log_step "Testing __logic_get_native_blueprint_info with invalid blueprint"

  local info_data
  info_data=$(__logic_get_native_blueprint_info "nonexistent_blueprint_12345" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_BLUEPRINT_NOT_FOUND" "Should return EC_BLUEPRINT_NOT_FOUND"
  assert_equals "$info_data" "" "Should not output anything"

  log_test "Invalid blueprint info handled correctly"
}

function test_get_native_blueprint_info_empty() {
  log_step "Testing __logic_get_native_blueprint_info with empty parameter"

  local info_data
  info_data=$(__logic_get_native_blueprint_info "" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
  assert_equals "$info_data" "" "Should not output anything"

  log_test "Empty parameter handled correctly"
}

# =============================================================================
# TEST FUNCTIONS - CONTAINER BLUEPRINT OPERATIONS
# =============================================================================

function test_find_container_blueprint_existing() {
  log_step "Testing __logic_find_container_blueprint with existing blueprint"

  # Create a test container blueprint
  local test_blueprint
  test_blueprint=$(create_test_container_blueprint "test_find_container")

  local blueprint_path
  blueprint_path=$(__logic_find_container_blueprint "test_find_container")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_FOUND" "Should return EC_SUCCESS_BLUEPRINT_FOUND"
  assert_not_equals "$blueprint_path" "" "Should return non-empty path"
  assert_file_exists "$blueprint_path" "Returned path should exist"
  assert_contains "$blueprint_path" "test_find_container.docker-compose.yml" "Path should contain blueprint filename"

  # Cleanup
  cleanup_test_blueprint "$test_blueprint"

  log_test "Container blueprint found successfully"
}

function test_find_container_blueprint_custom_priority() {
  log_step "Testing __logic_find_container_blueprint custom blueprint priority"

  # Create default and custom container blueprints
  local default_blueprint custom_blueprint
  default_blueprint=$(create_test_container_blueprint "test_priority" "$KGSM_ROOT/blueprints/default/container")
  custom_blueprint=$(create_test_container_blueprint "test_priority" "$KGSM_ROOT/blueprints/custom/container")

  local blueprint_path
  blueprint_path=$(__logic_find_container_blueprint "test_priority")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_FOUND" "Should find blueprint"
  assert_contains "$blueprint_path" "custom" "Should prioritize custom blueprint over default"

  # Cleanup
  cleanup_test_blueprint "$custom_blueprint"
  cleanup_test_blueprint "$default_blueprint"

  log_test "Custom container blueprint priority verified"
}

function test_find_container_blueprint_nonexistent() {
  log_step "Testing __logic_find_container_blueprint with non-existent blueprint"

  local blueprint_path
  blueprint_path=$(__logic_find_container_blueprint "nonexistent_container_12345" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_BLUEPRINT_NOT_FOUND" "Should return EC_BLUEPRINT_NOT_FOUND"
  assert_equals "$blueprint_path" "" "Should not output anything"

  log_test "Non-existent container blueprint handled correctly"
}

function test_find_container_blueprint_empty() {
  log_step "Testing __logic_find_container_blueprint with empty parameter"

  local blueprint_path
  blueprint_path=$(__logic_find_container_blueprint "" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
  assert_equals "$blueprint_path" "" "Should not output anything"

  log_test "Empty parameter handled correctly"
}

# =============================================================================
# TEST FUNCTIONS - CONTAINER BLUEPRINT LISTING
# =============================================================================

function test_list_container_blueprints_all() {
  log_step "Testing __logic_list_container_blueprints with 'all' source"

  # Create a test container blueprint
  local test_blueprint
  test_blueprint=$(create_test_container_blueprint "test_list_all")

  local blueprint_list
  blueprint_list=$(__logic_list_container_blueprints "all")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_LISTED" "Should return EC_SUCCESS_BLUEPRINT_LISTED"
  assert_contains "$blueprint_list" "test_list_all" "Should include test container blueprint"

  # Cleanup
  cleanup_test_blueprint "$test_blueprint"

  log_test "All container blueprints listed successfully"
}

function test_list_container_blueprints_custom() {
  log_step "Testing __logic_list_container_blueprints with 'custom' source"

  # Create a custom container blueprint
  local custom_blueprint
  custom_blueprint=$(create_test_container_blueprint "test_custom_container")

  local blueprint_list
  blueprint_list=$(__logic_list_container_blueprints "custom")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_LISTED" "Should return EC_SUCCESS_BLUEPRINT_LISTED"
  assert_contains "$blueprint_list" "test_custom_container" "Should include custom container blueprint"

  # Cleanup
  cleanup_test_blueprint "$custom_blueprint"

  log_test "Custom container blueprints listed successfully"
}

function test_list_container_blueprints_deduplication() {
  log_step "Testing __logic_list_container_blueprints deduplication"

  # Create blueprints with same name in both locations
  local default_blueprint custom_blueprint
  default_blueprint=$(create_test_container_blueprint "test_dedup" "$KGSM_ROOT/blueprints/default/container")
  custom_blueprint=$(create_test_container_blueprint "test_dedup" "$KGSM_ROOT/blueprints/custom/container")

  local blueprint_list
  blueprint_list=$(__logic_list_container_blueprints "all")
  local exit_code=$?

  # Count occurrences of "test_dedup" in the list
  local dedup_count
  dedup_count=$(echo "$blueprint_list" | grep -c "^test_dedup$")

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_LISTED" "Should return EC_SUCCESS_BLUEPRINT_LISTED"
  assert_equals "$dedup_count" "1" "Should list 'test_dedup' only once (deduplicated)"

  # Cleanup
  cleanup_test_blueprint "$custom_blueprint"
  cleanup_test_blueprint "$default_blueprint"

  log_test "Container blueprint deduplication verified"
}

function test_list_container_blueprints_invalid_source() {
  log_step "Testing __logic_list_container_blueprints with invalid source"

  local blueprint_list
  blueprint_list=$(__logic_list_container_blueprints "invalid_source" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG for invalid source"

  log_test "Invalid source handled correctly"
}

# =============================================================================
# TEST FUNCTIONS - CONTAINER BLUEPRINT INFO
# =============================================================================

function test_get_container_blueprint_info_valid() {
  log_step "Testing __logic_get_container_blueprint_info with valid blueprint"

  # Create a test container blueprint
  local test_blueprint
  test_blueprint=$(create_test_container_blueprint "test_info_container")

  local info_data
  info_data=$(__logic_get_container_blueprint_info "test_info_container")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "Should return EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED"
  assert_not_equals "$info_data" "" "Should return non-empty data"
  assert_contains "$info_data" "name=" "Should include name field"
  assert_contains "$info_data" "blueprint_type=container" "Should include blueprint_type field"

  # Cleanup
  cleanup_test_blueprint "$test_blueprint"

  log_test "Container blueprint info retrieved successfully"
}

function test_get_container_blueprint_info_invalid() {
  log_step "Testing __logic_get_container_blueprint_info with invalid blueprint"

  local info_data
  info_data=$(__logic_get_container_blueprint_info "nonexistent_container_12345" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_BLUEPRINT_NOT_FOUND" "Should return EC_BLUEPRINT_NOT_FOUND"
  assert_equals "$info_data" "" "Should not output anything"

  log_test "Invalid container blueprint info handled correctly"
}

function test_get_container_blueprint_info_empty() {
  log_step "Testing __logic_get_container_blueprint_info with empty parameter"

  local info_data
  info_data=$(__logic_get_container_blueprint_info "" 2>/dev/null)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
  assert_equals "$info_data" "" "Should not output anything"

  log_test "Empty parameter handled correctly"
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

function run_all_tests() {
  log_step "Running all blueprints logic tests"

  # Setup
  setup_test

  # Blueprint type detection tests
  test_get_blueprint_type_native
  test_get_blueprint_type_container
  test_get_blueprint_type_invalid
  test_get_blueprint_type_empty

  # Blueprint validation tests
  test_validate_blueprint_valid
  test_validate_blueprint_invalid
  test_validate_blueprint_empty

  # Blueprint path retrieval tests
  test_get_blueprint_path_native
  test_get_blueprint_path_container
  test_get_blueprint_path_invalid

  # Native blueprint operations
  test_find_native_blueprint_existing
  test_find_native_blueprint_custom_priority
  test_find_native_blueprint_strip_extension
  test_find_native_blueprint_nonexistent
  test_find_native_blueprint_empty

  # Native blueprint listing
  test_list_native_blueprints_all
  test_list_native_blueprints_default
  test_list_native_blueprints_custom
  test_list_native_blueprints_deduplication
  test_list_native_blueprints_invalid_source
  test_list_native_blueprints_empty_source

  # Native blueprint info
  test_get_native_blueprint_info_valid
  test_get_native_blueprint_info_invalid
  test_get_native_blueprint_info_empty

  # Container blueprint operations
  test_find_container_blueprint_existing
  test_find_container_blueprint_custom_priority
  test_find_container_blueprint_nonexistent
  test_find_container_blueprint_empty

  # Container blueprint listing
  test_list_container_blueprints_all
  test_list_container_blueprints_custom
  test_list_container_blueprints_deduplication
  test_list_container_blueprints_invalid_source

  # Container blueprint info
  test_get_container_blueprint_info_valid
  test_get_container_blueprint_info_invalid
  test_get_container_blueprint_info_empty

  log_step "All blueprints logic tests completed"
}

# Execute tests
run_all_tests
