#!/usr/bin/env bash

# KGSM Blueprints Files Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/blueprints.native.sh,
#         commands/blueprints.container.sh, and commands/instances.sh
#
# Integration points tested:
# - blueprints.native.sh list/find/info return consistent data with instances
# - blueprints.container.sh list/find/info work independently of native
# - Native blueprint path from find can be used to create an instance
# - blueprints.native.sh and blueprints.container.sh scope is isolated
#   (native module only finds .bp files; container module only finds docker-compose.yml)
# - JSON output from both modules is valid
# - Error handling for nonexistent blueprints

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprints_files_integration"
readonly NATIVE_MODULE="$KGSM_ROOT/commands/blueprints.native.sh"
readonly CONTAINER_MODULE="$KGSM_ROOT/commands/blueprints.container.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"
readonly BLUEPRINTS_MODULE="$KGSM_ROOT/commands/blueprints.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up blueprints files integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$NATIVE_MODULE" "blueprints.native.sh should exist"
  assert_file_executable "$NATIVE_MODULE" "blueprints.native.sh should be executable"
  assert_file_exists "$CONTAINER_MODULE" "blueprints.container.sh should exist"
  assert_file_executable "$CONTAINER_MODULE" "blueprints.container.sh should be executable"
  assert_file_exists "$INSTANCES_MODULE" "instances.sh should exist"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"

  log_test_step "Integration test environment validated"
}

# =============================================================================
# NATIVE BLUEPRINT TESTS
# =============================================================================

# TEST 1: blueprints.native.sh list returns known blueprints
function test_native_list_contains_known_blueprints() {
  log_test_step "Testing: blueprints.native.sh list contains known blueprints"

  local list_output
  list_output=$("$NATIVE_MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh list should succeed"
  assert_not_empty "$list_output" "blueprints.native.sh list should produce output"
  assert_contains "$list_output" "factorio" "native list should contain factorio"
  assert_contains "$list_output" "terraria" "native list should contain terraria"
  assert_contains "$list_output" "necesse" "native list should contain necesse"
}

# TEST 2: blueprints.native.sh list default returns only .bp files
function test_native_list_default_filter() {
  log_test_step "Testing: blueprints.native.sh list default shows official blueprints"

  local output
  output=$("$NATIVE_MODULE" list default 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh list default should succeed"
  assert_not_empty "$output" "blueprints.native.sh list default should produce output"
  assert_contains "$output" "factorio" "default native list should contain factorio"
}

# TEST 3: blueprints.native.sh list custom succeeds (may be empty)
function test_native_list_custom_filter() {
  log_test_step "Testing: blueprints.native.sh list custom succeeds"

  # Custom list may be empty but should not error
  "$NATIVE_MODULE" list custom 2>/dev/null
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh list custom should succeed"
}

# TEST 4: blueprints.native.sh find returns path ending in .bp
function test_native_find_returns_bp_extension() {
  log_test_step "Testing: blueprints.native.sh find factorio returns a .bp file path"

  local blueprint_path
  blueprint_path=$("$NATIVE_MODULE" find factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh find factorio should succeed"
  assert_not_empty "$blueprint_path" "find should return a path"
  assert_file_exists "$blueprint_path" "blueprint path should point to existing file"
  assert_ends_with "$blueprint_path" ".bp" "native blueprint path should end with .bp"
}

# TEST 5: blueprints.native.sh info contains required fields
function test_native_info_contains_required_fields() {
  log_test_step "Testing: blueprints.native.sh info factorio contains required blueprint fields"

  local info_output
  info_output=$("$NATIVE_MODULE" info factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh info factorio should succeed"
  assert_not_empty "$info_output" "info output should not be empty"
  assert_contains "$info_output" "name=" "info should contain name field"
  assert_contains "$info_output" "executable_file=" "info should contain executable_file"
  assert_contains "$info_output" "level_name=" "info should contain level_name"
}

# TEST 6: blueprints.native.sh --json output is valid JSON
function test_native_info_json_format() {
  log_test_step "Testing: blueprints.native.sh info factorio --json returns valid JSON"

  local json_output
  json_output=$("$NATIVE_MODULE" info factorio --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh info factorio --json should succeed"
  assert_not_empty "$json_output" "JSON output should not be empty"

  echo "$json_output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "Output should be valid JSON"

  # JSON should have the BlueprintType field indicating native
  assert_contains "$json_output" "\"BlueprintType\"" "JSON should have BlueprintType key"
  assert_contains "$json_output" "\"Native\"" "JSON BlueprintType should be Native"
}

# TEST 7: blueprints.native.sh list --json returns valid JSON array
function test_native_list_json_format() {
  log_test_step "Testing: blueprints.native.sh list --json returns valid JSON array"

  local json_output
  json_output=$("$NATIVE_MODULE" list --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.native.sh list --json should succeed"
  assert_not_empty "$json_output" "JSON list output should not be empty"

  echo "$json_output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "List --json output should be valid JSON"
}

# TEST 8: blueprints.native.sh find nonexistent blueprint fails
function test_native_find_invalid_blueprint_fails() {
  log_test_step "Testing: blueprints.native.sh find nonexistent blueprint returns error"

  "$NATIVE_MODULE" find nonexistent_blueprint_xyz_abc 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "blueprints.native.sh find with nonexistent blueprint should fail"
}

# TEST 9: blueprints.native.sh info nonexistent blueprint fails
function test_native_info_invalid_blueprint_fails() {
  log_test_step "Testing: blueprints.native.sh info nonexistent blueprint returns error"

  "$NATIVE_MODULE" info nonexistent_blueprint_xyz_abc 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "blueprints.native.sh info with nonexistent blueprint should fail"
}

# TEST 10: blueprints.native.sh find path is consistent with blueprints.sh find
function test_native_find_consistent_with_blueprints_sh() {
  log_test_step "Testing: blueprints.native.sh find returns same path as blueprints.sh find"

  local native_path
  native_path=$("$NATIVE_MODULE" find factorio 2>&1)
  assert_equals 0 "$?" "blueprints.native.sh find factorio should succeed"

  local generic_path
  generic_path=$("$BLUEPRINTS_MODULE" find factorio 2>&1)
  assert_equals 0 "$?" "blueprints.sh find factorio should succeed"

  assert_equals "$native_path" "$generic_path" \
    "blueprints.native.sh and blueprints.sh should return the same path for factorio"
}

# TEST 11: blueprints.native.sh find path can be used to create an instance
function test_native_find_path_enables_instance_creation() {
  log_test_step "Testing: blueprint path from blueprints.native.sh find can create an instance"

  local blueprint_path
  blueprint_path=$("$NATIVE_MODULE" find factorio 2>&1)
  assert_equals 0 "$?" "blueprints.native.sh find factorio should succeed"
  assert_file_exists "$blueprint_path" "blueprint path should point to real file"

  # Create an instance from this blueprint
  local instance_name="test-native-path-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  assert_equals 0 "$create_exit" \
    "Instance creation with blueprint found via native module should succeed"

  # Instance should be findable
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed for created instance"
  assert_file_exists "$instance_config" "Instance config should exist"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# TEST 12: Multiple native blueprints can coexist with different find results
function test_native_find_different_blueprints_different_paths() {
  log_test_step "Testing: blueprints.native.sh find returns different paths for different blueprints"

  local factorio_path
  factorio_path=$("$NATIVE_MODULE" find factorio 2>&1)
  assert_equals 0 "$?" "blueprints.native.sh find factorio should succeed"

  local terraria_path
  terraria_path=$("$NATIVE_MODULE" find terraria 2>&1)
  assert_equals 0 "$?" "blueprints.native.sh find terraria should succeed"

  assert_not_equals "$factorio_path" "$terraria_path" \
    "Different blueprints should have different file paths"

  assert_ends_with "$factorio_path" ".bp" "factorio path should end with .bp"
  assert_ends_with "$terraria_path" ".bp" "terraria path should end with .bp"
}

# =============================================================================
# CONTAINER BLUEPRINT TESTS
# =============================================================================

# TEST 13: blueprints.container.sh list returns known container blueprints
function test_container_list_contains_vrising() {
  log_test_step "Testing: blueprints.container.sh list contains vrising"

  local list_output
  list_output=$("$CONTAINER_MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.container.sh list should succeed"
  assert_not_empty "$list_output" "container list should produce output"
  assert_contains "$list_output" "vrising" "container list should contain vrising"
}

# TEST 14: blueprints.container.sh list default returns blueprints
function test_container_list_default_filter() {
  log_test_step "Testing: blueprints.container.sh list default shows official container blueprints"

  local output
  output=$("$CONTAINER_MODULE" list default 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.container.sh list default should succeed"
  assert_not_empty "$output" "container default list should produce output"
  assert_contains "$output" "vrising" "default container list should contain vrising"
}

# TEST 15: blueprints.container.sh find vrising returns docker-compose path
function test_container_find_returns_docker_compose_path() {
  log_test_step "Testing: blueprints.container.sh find vrising returns docker-compose.yml path"

  local blueprint_path
  blueprint_path=$("$CONTAINER_MODULE" find vrising 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.container.sh find vrising should succeed"
  assert_not_empty "$blueprint_path" "container find should return a path"
  assert_file_exists "$blueprint_path" "container blueprint path should point to existing file"
  assert_contains "$blueprint_path" "docker-compose.yml" \
    "container blueprint path should contain docker-compose.yml"
}

# TEST 16: blueprints.container.sh info contains name field
function test_container_info_contains_name() {
  log_test_step "Testing: blueprints.container.sh info vrising contains name and ports"

  local info_output
  info_output=$("$CONTAINER_MODULE" info vrising 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.container.sh info vrising should succeed"
  assert_not_empty "$info_output" "container info output should not be empty"
  # Container blueprint is a docker-compose.yml - output is the file content
  assert_contains "$info_output" "vrising" \
    "container info should reference vrising"
}

# TEST 17: blueprints.container.sh --json returns valid JSON
function test_container_info_json_format() {
  log_test_step "Testing: blueprints.container.sh info vrising --json returns valid JSON"

  local json_output
  json_output=$("$CONTAINER_MODULE" info vrising --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "blueprints.container.sh info vrising --json should succeed"
  assert_not_empty "$json_output" "container JSON output should not be empty"

  echo "$json_output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "Container info --json should produce valid JSON"

  assert_contains "$json_output" "\"BlueprintType\"" "JSON should have BlueprintType key"
  assert_contains "$json_output" "\"Container\"" "JSON BlueprintType should be Container"
}

# TEST 18: blueprints.container.sh find nonexistent blueprint fails
function test_container_find_invalid_blueprint_fails() {
  log_test_step "Testing: blueprints.container.sh find nonexistent blueprint returns error"

  "$CONTAINER_MODULE" find nonexistent_container_xyz_abc 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "blueprints.container.sh find with nonexistent blueprint should fail"
}

# =============================================================================
# ISOLATION TESTS (native vs container scope)
# =============================================================================

# TEST 19: blueprints.native.sh cannot find container blueprints
function test_native_module_cannot_find_container_blueprint() {
  log_test_step "Testing: blueprints.native.sh cannot find container-only blueprint (vrising)"

  # vrising only exists as a container blueprint, not a native .bp file
  "$NATIVE_MODULE" find vrising 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "blueprints.native.sh should not find vrising (container-only blueprint)"
}

# TEST 20: blueprints.container.sh cannot find native blueprints
function test_container_module_cannot_find_native_blueprint() {
  log_test_step "Testing: blueprints.container.sh cannot find native-only blueprint (factorio)"

  # factorio only exists as a native blueprint, not a docker-compose.yml
  "$CONTAINER_MODULE" find factorio 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "blueprints.container.sh should not find factorio (native-only blueprint)"
}

# TEST 21: Instance created from native blueprint has runtime=native in config
function test_native_blueprint_instance_has_native_runtime() {
  log_test_step "Testing: instance created from native blueprint has runtime=native in config"

  local instance_name="test-native-runtime-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed"
  assert_file_exists "$instance_config" "Instance config should exist"

  # Verify runtime is native
  assert_file_contains "$instance_config" 'runtime=' \
    "Instance config should have runtime key"
  local runtime_val
  runtime_val=$(grep '^runtime=' "$instance_config" | cut -d= -f2 | tr -d '"')
  assert_equals "native" "$runtime_val" \
    "Instance from native blueprint should have runtime=native"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

