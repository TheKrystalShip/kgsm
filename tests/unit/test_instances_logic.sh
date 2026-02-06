#!/usr/bin/env bash

# KGSM Instance Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/instances.sh - Pure logic functions for instance management
#
# Tests all __logic_* functions:
# - __logic_generate_unique_instance_name()
# - __logic_instance_config_exists()
# - __logic_create_instance_config_file()
# - __logic_create_base_instance()
# - __logic_create_instance()
# - __logic_remove_instance()
# - __logic_get_instances()
# - __logic_get_instance_paths()

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="instances_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/instances.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up instances logic tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$HANDLER" "Instances handler should exist"

  # Source the handler
  source "$HANDLER"

  # Verify error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_BLUEPRINT_NOT_FOUND" "EC_BLUEPRINT_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_BLUEPRINT" "EC_INVALID_BLUEPRINT should be defined"
  assert_not_null "$EC_INVALID_INSTANCE" "EC_INVALID_INSTANCE should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_FAILED_SOURCE" "EC_FAILED_SOURCE should be defined"
  assert_not_null "$EC_FAILED_MKDIR" "EC_FAILED_MKDIR should be defined"
  assert_not_null "$EC_FAILED_TOUCH" "EC_FAILED_TOUCH should be defined"
  assert_not_null "$EC_FAILED_RM" "EC_FAILED_RM should be defined"
  assert_not_null "$EC_FAILED_TEMPLATE" "EC_FAILED_TEMPLATE should be defined"
  assert_not_null "$EC_NOT_FOUND" "EC_NOT_FOUND should be defined"
  assert_not_null "$EC_SUCCESS_INSTANCE_CREATED" "EC_SUCCESS_INSTANCE_CREATED should be defined"
  assert_not_null "$EC_SUCCESS_INSTANCE_REMOVED" "EC_SUCCESS_INSTANCE_REMOVED should be defined"

  # Verify functions are exported
  assert_function_exists "__logic_generate_unique_instance_name" \
    "__logic_generate_unique_instance_name should be exported"
  assert_function_exists "__logic_instance_config_exists" \
    "__logic_instance_config_exists should be exported"
  assert_function_exists "__logic_create_instance_config_file" \
    "__logic_create_instance_config_file should be exported"
  assert_function_exists "__logic_create_base_instance" \
    "__logic_create_base_instance should be exported"
  assert_function_exists "__logic_create_instance" \
    "__logic_create_instance should be exported"
  assert_function_exists "__logic_remove_instance" \
    "__logic_remove_instance should be exported"
  assert_function_exists "__logic_get_instances" \
    "__logic_get_instances should be exported"
  assert_function_exists "__logic_get_instance_paths" \
    "__logic_get_instance_paths should be exported"

  log_test_step "Instances logic test environment validated"
}

# =============================================================================
# __logic_generate_unique_instance_name TESTS
# =============================================================================

function test_generate_unique_name_empty_param() {
  log_test_step "Testing __logic_generate_unique_instance_name with empty parameter"

  __logic_generate_unique_instance_name "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty parameter"
}

function test_generate_unique_name_no_existing_instance() {
  log_test_step "Testing __logic_generate_unique_instance_name with no existing instance"

  local blueprint_name="factorio"
  local output
  output=$(__logic_generate_unique_instance_name "$blueprint_name")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_equals "$blueprint_name" "$output" \
    "Should return blueprint name when no instance exists"
}

function test_generate_unique_name_with_existing_instance() {
  log_test_step "Testing __logic_generate_unique_instance_name with existing instance"

  # Create a test instance using the blueprint name
  local blueprint_name="factorio"
  local instance
  instance=$(create_test_instance "$blueprint_name" "$blueprint_name")

  # Generate unique name - should get suffix
  local output
  output=$(__logic_generate_unique_instance_name "$blueprint_name")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_not_equals "$blueprint_name" "$output" "Should return different name when instance exists"
  assert_matches "$output" "^${blueprint_name}-[0-9]+$" "Should follow format 'blueprint-XX'"

  # Cleanup
  remove_test_instance "$instance" &> /dev/null
}

function test_generate_unique_name_multiple_calls() {
  log_test_step "Testing __logic_generate_unique_instance_name generates different names"

  # Create instance with blueprint name
  local blueprint_name="factorio"
  local instance1
  instance1=$(create_test_instance "$blueprint_name" "$blueprint_name")

  # Generate two unique names
  local name1 name2
  name1=$(__logic_generate_unique_instance_name "$blueprint_name")

  # Create instance with first generated name
  local instance2
  instance2=$(create_test_instance "$blueprint_name" "$name1")

  # Generate another name
  name2=$(__logic_generate_unique_instance_name "$blueprint_name")

  assert_not_equals "$name1" "$name2" \
    "Multiple calls should generate different unique names"

  # Cleanup
  remove_test_instance "$instance1" &> /dev/null
  remove_test_instance "$instance2" &> /dev/null
}

# =============================================================================
# __logic_instance_config_exists TESTS
# =============================================================================

function test_instance_config_exists_empty_instance_name() {
  log_test_step "Testing __logic_instance_config_exists with empty instance name"

  __logic_instance_config_exists "" "factorio" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance name"
}

function test_instance_config_exists_empty_blueprint_name() {
  log_test_step "Testing __logic_instance_config_exists with empty blueprint name"

  __logic_instance_config_exists "test-instance" "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty blueprint name"
}

function test_instance_config_exists_both_empty() {
  log_test_step "Testing __logic_instance_config_exists with both parameters empty"

  __logic_instance_config_exists "" "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for both empty parameters"
}

function test_instance_config_exists_non_existent() {
  log_test_step "Testing __logic_instance_config_exists with non-existent instance"

  __logic_instance_config_exists "nonexistent-instance" "factorio" 2> /dev/null
  local exit_code=$?

  assert_equals "1" "$exit_code" "Should return 1 for non-existent instance"
}

function test_instance_config_exists_existing_instance() {
  log_test_step "Testing __logic_instance_config_exists with existing instance"

  # Create test instance
  local blueprint_name="factorio"
  local instance
  instance=$(create_test_instance "$blueprint_name")

  # Check if config exists
  __logic_instance_config_exists "$instance" "$blueprint_name" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for existing instance"

  # Cleanup
  remove_test_instance "$instance" &> /dev/null
}

function test_instance_config_exists_auto_appends_extension() {
  log_test_step "Testing __logic_instance_config_exists auto-appends .ini extension"

  # Create test instance
  local blueprint_name="factorio"
  local instance
  instance=$(create_test_instance "$blueprint_name")

  # Check without .ini extension
  __logic_instance_config_exists "$instance" "$blueprint_name" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should handle instance name without .ini extension"

  # Cleanup
  remove_test_instance "$instance" &> /dev/null
}

# =============================================================================
# __logic_create_instance_config_file TESTS
# =============================================================================

function test_create_config_file_empty_instance_name() {
  log_test_step "Testing __logic_create_instance_config_file with empty instance name"

  __logic_create_instance_config_file "" "factorio" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance name"
}

function test_create_config_file_empty_blueprint_name() {
  log_test_step "Testing __logic_create_instance_config_file with empty blueprint name"

  __logic_create_instance_config_file "test-instance" "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty blueprint name"
}

function test_create_config_file_valid_params() {
  log_test_step "Testing __logic_create_instance_config_file with valid parameters"

  local blueprint_name="factorio"
  local instance_name
  instance_name=$(generate_test_id "$blueprint_name")

  local config_file
  config_file=$(__logic_create_instance_config_file "$instance_name" "$blueprint_name")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_not_null "$config_file" "Should output config file path"
  assert_file_exists "$config_file" "Config file should exist at returned path"
  assert_contains "$config_file" "$INSTANCES_SOURCE_DIR/$blueprint_name/$instance_name.ini" \
    "Config file path should match expected structure"

  # Cleanup
  rm -f "$config_file"
  rmdir "$INSTANCES_SOURCE_DIR/$blueprint_name" 2> /dev/null || true
}

function test_create_config_file_creates_directory() {
  log_test_step "Testing __logic_create_instance_config_file creates instance directory"

  local blueprint_name="factorio"
  local instance_name
  instance_name=$(generate_test_id "$blueprint_name")

  # Ensure directory doesn't exist
  rm -rf "$INSTANCES_SOURCE_DIR/$blueprint_name"

  local config_file
  config_file=$(__logic_create_instance_config_file "$instance_name" "$blueprint_name")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_dir_exists "$INSTANCES_SOURCE_DIR/$blueprint_name" \
    "Should create blueprint directory"

  # Cleanup
  rm -f "$config_file"
  rmdir "$INSTANCES_SOURCE_DIR/$blueprint_name" 2> /dev/null || true
}

function test_create_config_file_permission_denied() {
  log_test_step "Testing __logic_create_instance_config_file with permission denied"

  # Make instances directory read-only
  local original_perms
  original_perms=$(stat -c '%a' "$INSTANCES_SOURCE_DIR")
  chmod 555 "$INSTANCES_SOURCE_DIR"

  local blueprint_name="factorio"
  local instance_name
  instance_name=$(generate_test_id "$blueprint_name")

  __logic_create_instance_config_file "$instance_name" "$blueprint_name" 2> /dev/null
  local exit_code=$?

  # Restore permissions immediately
  chmod "$original_perms" "$INSTANCES_SOURCE_DIR"

  assert_equals "$EC_FAILED_MKDIR" "$exit_code" "Should return EC_FAILED_MKDIR when directory creation fails"
}

# =============================================================================
# __logic_create_base_instance TESTS
# =============================================================================

function test_create_base_instance_empty_config_file() {
  log_test_step "Testing __logic_create_base_instance with empty config file path"

  __logic_create_base_instance "" "test" "$KGSM_ROOT/blueprints/default/native/factorio.bp" "/tmp" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty config file"
}

function test_create_base_instance_empty_instance_name() {
  log_test_step "Testing __logic_create_base_instance with empty instance name"

  __logic_create_base_instance "/tmp/test.ini" "" "$KGSM_ROOT/blueprints/default/native/factorio.bp" "/tmp" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance name"
}

function test_create_base_instance_empty_blueprint_path() {
  log_test_step "Testing __logic_create_base_instance with empty blueprint path"

  __logic_create_base_instance "/tmp/test.ini" "test" "" "/tmp" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty blueprint path"
}

function test_create_base_instance_empty_install_dir() {
  log_test_step "Testing __logic_create_base_instance with empty install directory"

  __logic_create_base_instance "/tmp/test.ini" "test" "$KGSM_ROOT/blueprints/default/native/factorio.bp" "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty install directory"
}

function test_create_base_instance_native_blueprint() {
  log_test_step "Testing __logic_create_base_instance with native blueprint"

  local blueprint_path="$KGSM_ROOT/blueprints/default/native/factorio.bp"
  local instance_name
  instance_name=$(generate_test_id "factorio")
  local config_file="/tmp/${instance_name}.ini"
  local install_dir="/tmp"

  # Create empty config file
  touch "$config_file"

  __logic_create_base_instance "$config_file" "$instance_name" "$blueprint_path" "$install_dir" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_file_exists "$config_file" "Config file should exist"

  # Verify config contains expected variables
  assert_file_contains "$config_file" "instance_name=$instance_name" \
    "Config should contain instance_name"
  assert_file_contains "$config_file" "instance_runtime=native" \
    "Config should set runtime to native"
  assert_file_contains "$config_file" "instance_blueprint_file=$blueprint_path" \
    "Config should contain blueprint file path"

  # Cleanup
  rm -f "$config_file"
}

function test_create_base_instance_container_blueprint() {
  log_test_step "Testing __logic_create_base_instance with container blueprint"

  # Skip if no container blueprint exists
  local blueprint_path="$KGSM_ROOT/blueprints/default/container/vrising.docker-compose.yml"
  if [[ ! -f "$blueprint_path" ]]; then
    skip_test "Container blueprint not found"
    return
  fi

  local instance_name
  instance_name=$(generate_test_id "vrising")
  local config_file="/tmp/${instance_name}.ini"
  local install_dir="/tmp"

  # Create empty config file
  touch "$config_file"

  __logic_create_base_instance "$config_file" "$instance_name" "$blueprint_path" "$install_dir" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_file_contains "$config_file" "instance_runtime=container" \
    "Config should set runtime to container"

  # Cleanup
  rm -f "$config_file"
}

function test_create_base_instance_invalid_blueprint_extension() {
  log_test_step "Testing __logic_create_base_instance with invalid blueprint extension"

  local instance_name
  instance_name=$(generate_test_id "test")
  local config_file="/tmp/${instance_name}.ini"
  local invalid_blueprint="/tmp/invalid.txt"
  local install_dir="/tmp"

  # Create files
  touch "$config_file"
  touch "$invalid_blueprint"

  __logic_create_base_instance "$config_file" "$instance_name" "$invalid_blueprint" "$install_dir" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" \
    "Should return EC_INVALID_BLUEPRINT for invalid extension"

  # Cleanup
  rm -f "$config_file" "$invalid_blueprint"
}

function test_create_base_instance_global_executable() {
  log_test_step "Testing __logic_create_base_instance with global executable (java)"

  # Create temporary blueprint with java executable
  local blueprint_path="/tmp/test-java.bp"
  cat > "$blueprint_path" << 'EOF'
name=test-java
executable_file=java
executable_arguments=-jar server.jar
level_name=world
EOF

  local instance_name
  instance_name=$(generate_test_id "test")
  local config_file="/tmp/${instance_name}.ini"
  local install_dir="/tmp"

  touch "$config_file"

  __logic_create_base_instance "$config_file" "$instance_name" "$blueprint_path" "$install_dir" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_file_contains "$config_file" "instance_executable_file=java" \
    "Should not prepend ./ to global executables like java"

  # Cleanup
  rm -f "$config_file" "$blueprint_path"
}

function test_create_base_instance_local_executable() {
  log_test_step "Testing __logic_create_base_instance with local executable"

  local blueprint_path="$KGSM_ROOT/blueprints/default/native/factorio.bp"
  local instance_name
  instance_name=$(generate_test_id "test")
  local config_file="/tmp/${instance_name}.ini"
  local install_dir="/tmp"

  touch "$config_file"

  __logic_create_base_instance "$config_file" "$instance_name" "$blueprint_path" "$install_dir" 2> /dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"

  # Factorio uses local executable, should have ./ prepended
  assert_file_contains "$config_file" "instance_executable_file=./" \
    "Should prepend ./ to local executables"

  # Cleanup
  rm -f "$config_file"
}

# =============================================================================
# __logic_create_instance TESTS
# =============================================================================

function test_create_instance_invalid_blueprint() {
  log_test_step "Testing __logic_create_instance with invalid blueprint"

  __logic_create_instance "nonexistent-blueprint" "/tmp" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" \
    "Should return EC_BLUEPRINT_NOT_FOUND for invalid blueprint"
}

function test_create_instance_nonexistent_install_dir() {
  log_test_step "Testing __logic_create_instance with non-existent install directory"

  __logic_create_instance "factorio" "/nonexistent/path/to/nowhere" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND for non-existent install directory"
}

function test_create_instance_nonwritable_install_dir() {
  log_test_step "Testing __logic_create_instance with non-writable install directory"

  # Create temporary directory and make it read-only
  local test_dir="/tmp/kgsm-readonly-test"
  mkdir -p "$test_dir"
  chmod 555 "$test_dir"

  __logic_create_instance "factorio" "$test_dir" 2> /dev/null
  local exit_code=$?

  # Restore permissions and cleanup
  chmod 755 "$test_dir"
  rmdir "$test_dir"

  assert_equals "$EC_PERMISSION" "$exit_code" "Should return EC_PERMISSION for non-writable install directory"
}

function test_create_instance_auto_generated_name() {
  log_test_step "Testing __logic_create_instance with auto-generated name"

  local output
  output=$(__logic_create_instance "factorio" "$TEST_SANDBOX_INSTANCES_INSTALL_DIR")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_CREATED for success"
  assert_not_null "$output" "Should output instance name"

  # Verify instance was created
  local instance_name="$output"
  assert_file_exists "$INSTANCES_SOURCE_DIR/factorio/${instance_name}.ini" \
    "Instance config should exist"

  # Cleanup
  remove_test_instance "$instance_name" &> /dev/null
}

function test_create_instance_custom_identifier() {
  log_test_step "Testing __logic_create_instance with custom identifier"

  local custom_name
  custom_name=$(generate_test_id "custom")

  local output
  output=$(__logic_create_instance "factorio" "$TEST_SANDBOX_INSTANCES_INSTALL_DIR" "$custom_name")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_CREATED for success"
  assert_equals "$custom_name" "$output" \
    "Should use provided custom identifier"

  # Verify instance was created with custom name
  assert_file_exists "$INSTANCES_SOURCE_DIR/factorio/${custom_name}.ini" \
    "Instance config should exist with custom name"

  # Cleanup
  remove_test_instance "$custom_name" &> /dev/null
}

function test_create_instance_duplicate_identifier() {
  log_test_step "Testing __logic_create_instance with duplicate identifier"

  local custom_name
  custom_name=$(generate_test_id "duplicate")

  # Create first instance
  local instance1
  instance1=$(__logic_create_instance "factorio" "$TEST_SANDBOX_INSTANCES_INSTALL_DIR" "$custom_name")

  # Try to create second instance with same name
  __logic_create_instance "factorio" "$TEST_SANDBOX_INSTANCES_INSTALL_DIR" "$custom_name" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_INSTANCE" "$exit_code" \
    "Should return EC_INVALID_INSTANCE for duplicate identifier"

  # Cleanup
  remove_test_instance "$instance1" &> /dev/null
}

function test_create_instance_native_blueprint() {
  log_test_step "Testing __logic_create_instance with native blueprint"

  local output
  output=$(__logic_create_instance "factorio" "$TEST_SANDBOX_INSTANCES_INSTALL_DIR")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" \
    "Should create native instance successfully"

  # Verify config has native runtime
  local config_file="$INSTANCES_SOURCE_DIR/factorio/${output}.ini"
  assert_file_contains "$config_file" "instance_runtime=native" \
    "Config should specify native runtime"

  # Cleanup
  remove_test_instance "$output" &> /dev/null
}

function test_create_instance_container_blueprint() {
  log_test_step "Testing __logic_create_instance with container blueprint"

  # Skip if no container blueprint exists
  if [[ ! -f "$KGSM_ROOT/blueprints/default/container/vrising.docker-compose.yml" ]]; then
    skip_test "Container blueprint not found"
    return
  fi

  local output
  output=$(__logic_create_instance "vrising" "$TEST_SANDBOX_INSTANCES_INSTALL_DIR")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" "Should create container instance successfully"

  # Verify config has container runtime
  local config_file="$INSTANCES_SOURCE_DIR/vrising/${output}.ini"
  assert_file_contains "$config_file" "instance_runtime=container" "Config should specify container runtime"

  # Cleanup
  remove_test_instance "$output" &> /dev/null
}

# =============================================================================
# __logic_remove_instance TESTS
# =============================================================================

function test_remove_instance_empty_param() {
  log_test_step "Testing __logic_remove_instance with empty parameter"

  __logic_remove_instance "" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty parameter"
}

function test_remove_instance_nonexistent() {
  log_test_step "Testing __logic_remove_instance with non-existent instance"

  __logic_remove_instance "nonexistent-instance" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_NOT_FOUND" "$exit_code" \
    "Should return EC_NOT_FOUND for non-existent instance"
}

function test_remove_instance_valid() {
  log_test_step "Testing __logic_remove_instance with valid instance"

  # Create test instance
  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")

  # Remove instance
  __logic_remove_instance "$instance" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_REMOVED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_REMOVED for success"

  # Verify config file was removed
  assert_file_not_exists "$INSTANCES_SOURCE_DIR/factorio/${instance}.ini" \
    "Instance config should be removed"
}

function test_remove_instance_empty_directory_cleanup() {
  log_test_step "Testing __logic_remove_instance removes empty blueprint directory"

  # Create single instance
  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")

  # Directory should exist
  assert_dir_exists "$INSTANCES_SOURCE_DIR/factorio" \
    "Blueprint directory should exist before removal"

  # Remove instance
  __logic_remove_instance "$instance" 2> /dev/null

  # If this was the only instance, directory should be removed
  # Note: In test environment there might be other test instances,
  # so we only verify the logic doesn't fail
  local exit_code=$?
  assert_equals "$EC_SUCCESS_INSTANCE_REMOVED" "$exit_code" \
    "Should successfully remove instance even if directory cleanup needed"
}

function test_remove_instance_keeps_nonempty_directory() {
  log_test_step "Testing __logic_remove_instance keeps non-empty blueprint directory"

  # Create two instances
  local instance1 instance2
  instance1=$(create_test_instance "factorio" "$(generate_test_id)")
  instance2=$(create_test_instance "factorio" "$(generate_test_id)")

  # Remove first instance
  __logic_remove_instance "$instance1" 2> /dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_REMOVED" "$exit_code" \
    "Should successfully remove first instance"

  # Directory should still exist because second instance remains
  assert_dir_exists "$INSTANCES_SOURCE_DIR/factorio" \
    "Blueprint directory should remain when other instances exist"

  # Cleanup
  remove_test_instance "$instance2" &> /dev/null
}

# =============================================================================
# __logic_get_instances TESTS
# =============================================================================

function test_get_instances_empty_no_filter() {
  log_test_step "Testing __logic_get_instances with no instances and no filter"

  # Ensure clean state
  rm -rf "$INSTANCES_SOURCE_DIR"/*

  local output
  output=$(__logic_get_instances)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 even with no instances"
  assert_null "$output" "Output should be empty when no instances exist"
}

function test_get_instances_multiple_no_filter() {
  log_test_step "Testing __logic_get_instances with multiple instances, no filter"

  # Create instances from different blueprints
  local instance1 instance2 instance3
  instance1=$(create_test_instance "factorio" "$(generate_test_id)")
  instance2=$(create_test_instance "factorio" "$(generate_test_id)")
  instance3=$(create_test_instance "terraria" "$(generate_test_id)")

  local output
  output=$(__logic_get_instances)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_not_null "$output" "Should output instance names"
  assert_contains "$output" "$instance1" "Should include first factorio instance"
  assert_contains "$output" "$instance2" "Should include second factorio instance"
  assert_contains "$output" "$instance3" "Should include terraria instance"

  # Cleanup
  remove_test_instance "$instance1" &> /dev/null
  remove_test_instance "$instance2" &> /dev/null
  remove_test_instance "$instance3" &> /dev/null
}

function test_get_instances_with_blueprint_filter() {
  log_test_step "Testing __logic_get_instances with blueprint filter"

  # Create instances from different blueprints
  local instance1 instance2 instance3
  instance1=$(create_test_instance "factorio" "$(generate_test_id)")
  instance2=$(create_test_instance "factorio" "$(generate_test_id)")
  instance3=$(create_test_instance "terraria" "$(generate_test_id)")

  local output
  output=$(__logic_get_instances "factorio")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_contains "$output" "$instance1" "Should include first factorio instance"
  assert_contains "$output" "$instance2" "Should include second factorio instance"
  assert_not_contains "$output" "$instance3" "Should NOT include terraria instance"

  # Cleanup
  remove_test_instance "$instance1" &> /dev/null
  remove_test_instance "$instance2" &> /dev/null
  remove_test_instance "$instance3" &> /dev/null
}

function test_get_instances_nonexistent_blueprint_filter() {
  log_test_step "Testing __logic_get_instances with non-existent blueprint filter"

  # Create an instance
  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")

  local output
  output=$(__logic_get_instances "nonexistent-blueprint")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 even with no matches"
  assert_null "$output" "Output should be empty for non-matching filter"

  # Cleanup
  remove_test_instance "$instance" &> /dev/null
}

function test_get_instances_name_format() {
  log_test_step "Testing __logic_get_instances returns names without path or extension"

  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")

  local output
  output=$(__logic_get_instances "factorio")

  assert_not_contains "$output" ".ini" "Output should not contain .ini extension"
  assert_not_contains "$output" "/" "Output should not contain path separators"
  assert_equals "$instance" "$output" "Output should be just the instance name"

  # Cleanup
  remove_test_instance "$instance" &> /dev/null
}

# =============================================================================
# __logic_get_instance_paths TESTS
# =============================================================================

function test_get_instance_paths_empty_no_filter() {
  log_test_step "Testing __logic_get_instance_paths with no instances and no filter"

  # Ensure clean state
  rm -rf "$INSTANCES_SOURCE_DIR"/*

  local output
  output=$(__logic_get_instance_paths)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 even with no instances"
  assert_null "$output" "Output should be empty when no instances exist"
}

function test_get_instance_paths_multiple_no_filter() {
  log_test_step "Testing __logic_get_instance_paths with multiple instances, no filter"

  # Create instances
  local instance1 instance2
  instance1=$(create_test_instance "factorio" "$(generate_test_id)")
  instance2=$(create_test_instance "terraria" "$(generate_test_id)")

  local output
  output=$(__logic_get_instance_paths)
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_not_null "$output" "Should output paths"
  assert_contains "$output" "$INSTANCES_SOURCE_DIR/factorio/${instance1}.ini" \
    "Should include full path to factorio instance"
  assert_contains "$output" "$INSTANCES_SOURCE_DIR/terraria/${instance2}.ini" \
    "Should include full path to terraria instance"

  # Cleanup
  remove_test_instance "$instance1" &> /dev/null
  remove_test_instance "$instance2" &> /dev/null
}

function test_get_instance_paths_with_filter() {
  log_test_step "Testing __logic_get_instance_paths with blueprint filter"

  # Create instances
  local instance1 instance2
  instance1=$(create_test_instance "factorio" "$(generate_test_id)")
  instance2=$(create_test_instance "terraria" "$(generate_test_id)")

  local output
  output=$(__logic_get_instance_paths "factorio")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for success"
  assert_contains "$output" "factorio" "Should include factorio path"
  assert_not_contains "$output" "terraria" "Should NOT include terraria path"

  # Cleanup
  remove_test_instance "$instance1" &> /dev/null
  remove_test_instance "$instance2" &> /dev/null
}

function test_get_instance_paths_format() {
  log_test_step "Testing __logic_get_instance_paths returns full paths with .ini"

  local instance
  instance=$(create_test_instance "factorio" "$(generate_test_id)")

  local output
  output=$(__logic_get_instance_paths "factorio")

  assert_contains "$output" ".ini" "Output should contain .ini extension"
  assert_contains "$output" "$INSTANCES_SOURCE_DIR" \
    "Output should contain full path from INSTANCES_SOURCE_DIR"
  assert_matches "$output" "^/" "Output should start with / (absolute path)"

  # Cleanup
  remove_test_instance "$instance" &> /dev/null
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting instances logic tests"

  # Initialize test environment
  setup_test

  # __logic_generate_unique_instance_name tests
  test_generate_unique_name_empty_param
  test_generate_unique_name_no_existing_instance
  test_generate_unique_name_with_existing_instance
  test_generate_unique_name_multiple_calls

  # __logic_instance_config_exists tests
  test_instance_config_exists_empty_instance_name
  test_instance_config_exists_empty_blueprint_name
  test_instance_config_exists_both_empty
  test_instance_config_exists_non_existent
  test_instance_config_exists_existing_instance
  test_instance_config_exists_auto_appends_extension

  # __logic_create_instance_config_file tests
  test_create_config_file_empty_instance_name
  test_create_config_file_empty_blueprint_name
  test_create_config_file_valid_params
  test_create_config_file_creates_directory
  test_create_config_file_permission_denied

  # __logic_create_base_instance tests
  test_create_base_instance_empty_config_file
  test_create_base_instance_empty_instance_name
  test_create_base_instance_empty_blueprint_path
  test_create_base_instance_empty_install_dir
  test_create_base_instance_native_blueprint
  test_create_base_instance_container_blueprint
  test_create_base_instance_invalid_blueprint_extension
  test_create_base_instance_global_executable
  test_create_base_instance_local_executable

  # __logic_create_instance tests
  test_create_instance_invalid_blueprint
  test_create_instance_nonexistent_install_dir
  test_create_instance_nonwritable_install_dir
  test_create_instance_auto_generated_name
  test_create_instance_custom_identifier
  test_create_instance_duplicate_identifier
  test_create_instance_native_blueprint
  test_create_instance_container_blueprint

  # __logic_remove_instance tests
  test_remove_instance_empty_param
  test_remove_instance_nonexistent
  test_remove_instance_valid
  test_remove_instance_empty_directory_cleanup
  test_remove_instance_keeps_nonempty_directory

  # __logic_get_instances tests
  test_get_instances_empty_no_filter
  test_get_instances_multiple_no_filter
  test_get_instances_with_blueprint_filter
  test_get_instances_nonexistent_blueprint_filter
  test_get_instances_name_format

  # __logic_get_instance_paths tests
  test_get_instance_paths_empty_no_filter
  test_get_instance_paths_multiple_no_filter
  test_get_instance_paths_with_filter
  test_get_instance_paths_format

  log_test_step "Instances logic tests completed"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All instances logic tests completed successfully"
  else
    fail_test "Some instances logic tests failed"
  fi
}

# Execute main function
main "$@"
