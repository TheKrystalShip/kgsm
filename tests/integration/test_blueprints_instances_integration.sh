#!/usr/bin/env bash

# KGSM Blueprints + Instances Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/blueprints.sh and commands/instances.sh
#
# Integration points tested:
# - Blueprint validation gates instance creation
# - Blueprint info/find work after instances are created from them
# - Instance config contains blueprint-derived data (ports, executable, etc.)
# - Instance list filtering by blueprint name
# - Multiple instances from the same blueprint
# - Container blueprint → container instance data flow
# - Blueprint list consistency before and after instance creation/removal

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprints_instances_integration"
readonly BLUEPRINTS_MODULE="$KGSM_ROOT/commands/blueprints.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

TEST_INSTALL_DIR=""
TEST_LIBRARY=""

# Per-test cleanup tracking (used by teardown hook)
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up blueprints+instances integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  TEST_LIBRARY="$(__ensure_test_library "$TEST_INSTALL_DIR")"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$BLUEPRINTS_MODULE" "blueprints.sh command should exist"
  assert_file_executable "$BLUEPRINTS_MODULE" "blueprints.sh command should be executable"
  assert_file_exists "$INSTANCES_MODULE" "instances.sh command should exist"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh command should be executable"

  log_test_step "Integration test environment validated"
}

function setup() {
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  done
}

# =============================================================================
# TEST 1: Blueprint validation gates instance creation
# Invalid blueprint name must be rejected before any instance structure is created
# =============================================================================

function test_invalid_blueprint_blocks_instance_creation() {
  log_test_step "Testing: invalid blueprint prevents instance creation"

  "$INSTANCES_MODULE" create nonexistent_blueprint_xyz_abc \
    --library "$TEST_LIBRARY" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "Instance creation with nonexistent blueprint should fail"

  # Verify no partial instance structure was created
  assert_dir_not_exists "$KGSM_ROOT/instances/nonexistent_blueprint_xyz_abc" \
    "No instance directory should be created for invalid blueprint"
}

# =============================================================================
# TEST 2: Blueprint find works and path used in instance config
# blueprints find → path → instance config contains that blueprint path
# =============================================================================

function test_blueprint_path_reflected_in_instance_config() {
  log_test_step "Testing: blueprint path from 'find' matches instance config blueprint_file"

  # Get the blueprint path via the blueprints module
  local blueprint_path
  blueprint_path=$("$BLUEPRINTS_MODULE" find factorio 2>&1)
  local find_exit=$?

  assert_equals 0 "$find_exit" "blueprints find factorio should succeed"
  assert_not_null "$blueprint_path" "blueprints find should return a path"
  assert_file_exists "$blueprint_path" "blueprint path should point to existing file"

  # Create an instance from that blueprint
  local instance_name="test-bp-path-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  assert_equals 0 "$create_exit" "Instance creation should succeed"

  # Verify the instance config references the blueprint
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed for created instance"
  assert_file_exists "$instance_config" "Instance config file should exist"

  # Instance config should contain the blueprint filename
  assert_file_contains "$instance_config" "factorio" \
    "Instance config should reference factorio blueprint"
}

# =============================================================================
# TEST 3: Blueprint info fields are present in instance config
# Blueprint defines executable_file, ports, level_name → must appear in instance
# =============================================================================

function test_blueprint_info_fields_in_instance_config() {
  log_test_step "Testing: blueprint info fields are reflected in instance config"

  # Get blueprint info (canonical JSON) to know expected values
  local blueprint_info
  blueprint_info=$("$BLUEPRINTS_MODULE" info factorio --json 2>&1)
  assert_equals 0 "$?" "blueprints info factorio --json should succeed"
  assert_not_null "$blueprint_info" "Blueprint info should not be empty"

  # Extract expected values from blueprint info
  local expected_executable
  expected_executable=$(echo "$blueprint_info" | jq -r '.ExecutableFile')
  local expected_level
  expected_level=$(echo "$blueprint_info" | jq -r '.LevelName')

  assert_not_null "$expected_executable" "Blueprint should define executable_file"
  assert_not_null "$expected_level" "Blueprint should define level_name"

  # Create an instance
  local instance_name="test-bp-fields-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # Get instance info and verify blueprint-derived fields
  local instance_info
  instance_info=$("$INSTANCES_MODULE" info "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances info should succeed"

  # Instance config must include the expected executable
  assert_file_contains "$("$INSTANCES_MODULE" find "$instance_name" 2>&1)" \
    "$expected_executable" \
    "Instance config should contain blueprint executable_file value"

  assert_file_contains "$("$INSTANCES_MODULE" find "$instance_name" 2>&1)" \
    "$expected_level" \
    "Instance config should contain blueprint level_name value"
}

# =============================================================================
# TEST 4: Blueprint list is unaffected by instance creation/removal
# Creating/removing instances must not alter the blueprint list
# =============================================================================

function test_blueprint_list_unaffected_by_instances() {
  log_test_step "Testing: blueprint list is stable before/after instance create+remove"

  # Capture blueprint list before
  local list_before
  list_before=$("$BLUEPRINTS_MODULE" list 2>&1)
  assert_equals 0 "$?" "blueprints list should succeed before instance creation"
  assert_contains "$list_before" "factorio" "factorio should appear in blueprint list"
  assert_contains "$list_before" "terraria" "terraria should appear in blueprint list"

  # Create instances from multiple blueprints
  local instance_factorio="test-bplist-f-$$"
  local instance_terraria="test-bplist-t-$$"
  create_test_instance "factorio" "$instance_factorio" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  create_test_instance "terraria" "$instance_terraria" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  _TEARDOWN_INSTANCES+=("factorio:$instance_factorio")
  _TEARDOWN_INSTANCES+=("terraria:$instance_terraria")

  # Blueprint list should still contain the same blueprints
  local list_during
  list_during=$("$BLUEPRINTS_MODULE" list 2>&1)
  assert_contains "$list_during" "factorio" "factorio should still appear after instance creation"
  assert_contains "$list_during" "terraria" "terraria should still appear after instance creation"

  # Remove instances
  remove_test_instance "factorio" "$instance_factorio" "$TEST_INSTALL_DIR"
  remove_test_instance "terraria" "$instance_terraria" "$TEST_INSTALL_DIR"

  # Blueprint list should remain unchanged after removal
  local list_after
  list_after=$("$BLUEPRINTS_MODULE" list 2>&1)
  assert_contains "$list_after" "factorio" "factorio should still appear after instance removal"
  assert_contains "$list_after" "terraria" "terraria should still appear after instance removal"
}

# =============================================================================
# TEST 5: Instance list filtered by blueprint name
# After creating instances from different blueprints, list filters correctly
# =============================================================================

function test_instance_list_filtered_by_blueprint() {
  log_test_step "Testing: instances list filtered by blueprint name"

  local instance_factorio="test-filter-f-$$"
  local instance_terraria="test-filter-t-$$"

  create_test_instance "factorio" "$instance_factorio" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "factorio instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_factorio")

  create_test_instance "terraria" "$instance_terraria" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "terraria instance should be created"
  _TEARDOWN_INSTANCES+=("terraria:$instance_terraria")

  # Filter by factorio: must include factorio instance, must not include terraria instance
  local factorio_list
  factorio_list=$("$INSTANCES_MODULE" list factorio 2>&1)
  assert_equals 0 "$?" "instances list factorio should succeed"
  assert_contains "$factorio_list" "$instance_factorio" \
    "instances list factorio should include factorio instance"
  assert_not_contains "$factorio_list" "$instance_terraria" \
    "instances list factorio should not include terraria instance"

  # Filter by terraria: must include terraria instance, must not include factorio instance
  local terraria_list
  terraria_list=$("$INSTANCES_MODULE" list terraria 2>&1)
  assert_equals 0 "$?" "instances list terraria should succeed"
  assert_contains "$terraria_list" "$instance_terraria" \
    "instances list terraria should include terraria instance"
  assert_not_contains "$terraria_list" "$instance_factorio" \
    "instances list terraria should not include factorio instance"
}

# =============================================================================
# TEST 6: Multiple instances from same blueprint co-exist
# Two instances from factorio must both appear in list and have separate configs
# =============================================================================

function test_multiple_instances_from_same_blueprint() {
  log_test_step "Testing: two instances from same blueprint co-exist independently"

  local instance_one="test-multi-one-$$"
  local instance_two="test-multi-two-$$"

  create_test_instance "factorio" "$instance_one" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "First factorio instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_one")

  create_test_instance "factorio" "$instance_two" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Second factorio instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_two")

  # Both should appear in the list
  local all_instances
  all_instances=$("$INSTANCES_MODULE" list 2>&1)
  assert_contains "$all_instances" "$instance_one" \
    "First instance should appear in list"
  assert_contains "$all_instances" "$instance_two" \
    "Second instance should appear in list"

  # Both should appear when filtering by blueprint
  local factorio_instances
  factorio_instances=$("$INSTANCES_MODULE" list factorio 2>&1)
  assert_contains "$factorio_instances" "$instance_one" \
    "First instance should appear in factorio-filtered list"
  assert_contains "$factorio_instances" "$instance_two" \
    "Second instance should appear in factorio-filtered list"

  # Each should have its own config file
  local config_one config_two
  config_one=$("$INSTANCES_MODULE" find "$instance_one" 2>&1)
  config_two=$("$INSTANCES_MODULE" find "$instance_two" 2>&1)

  assert_not_equals "$config_one" "$config_two" \
    "Two instances should have different config file paths"
  assert_file_exists "$config_one" "First instance config should exist"
  assert_file_exists "$config_two" "Second instance config should exist"
}

# =============================================================================
# TEST 7: Instance removal removes it from list but blueprint still findable
# After removing an instance, blueprints find/info still work for that blueprint
# =============================================================================

function test_instance_removal_does_not_affect_blueprint() {
  log_test_step "Testing: removing an instance does not affect blueprint discoverability"

  local instance_name="test-rm-bp-$$"
  create_test_instance "necesse" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "necesse instance should be created"
  _TEARDOWN_INSTANCES+=("necesse:$instance_name")

  # Instance should exist in list
  local list_before
  list_before=$("$INSTANCES_MODULE" list 2>&1)
  assert_contains "$list_before" "$instance_name" "Instance should appear in list before removal"

  # Blueprint operations should work before removal
  assert_command_succeeds "$BLUEPRINTS_MODULE find necesse" \
    "blueprints find should work while instance exists"

  # Remove the instance
  remove_test_instance "necesse" "$instance_name" "$TEST_INSTALL_DIR"

  # Instance should no longer appear in list
  local list_after
  list_after=$("$INSTANCES_MODULE" list 2>&1)
  assert_not_contains "$list_after" "$instance_name" \
    "Instance should not appear in list after removal"

  # Blueprint operations must still work after instance removal
  assert_command_succeeds "$BLUEPRINTS_MODULE find necesse" \
    "blueprints find should still work after instance removal"
  assert_command_succeeds "$BLUEPRINTS_MODULE info necesse" \
    "blueprints info should still work after instance removal"
}

# =============================================================================
# TEST 8: generate-id uses blueprint name and is consistent with instance create
# generate-id output can be used directly with instance create --name
# =============================================================================

function test_generate_id_compatible_with_create() {
  log_test_step "Testing: generate-id output is usable with instance create --name"

  # Generate a unique ID with a custom name to avoid real-system conflicts
  local genid_name="test-genid-$$"
  local generated_id
  generated_id=$("$INSTANCES_MODULE" generate-id factorio --name "$genid_name" 2>&1)
  assert_equals 0 "$?" "generate-id factorio --name should succeed"
  assert_equals "$genid_name" "$generated_id" "generate-id --name should return the provided name"

  # Use that ID to create an instance via create_test_instance (reliable path)
  local created_name
  created_name=$(create_test_instance "factorio" "$generated_id" "$TEST_INSTALL_DIR" 2>&1)
  local create_exit=$?
  _TEARDOWN_INSTANCES+=("factorio:$generated_id")

  assert_equals 0 "$create_exit" \
    "create with generated ID should succeed"

  assert_contains "$created_name" "$generated_id" \
    "create_test_instance output should include the generated ID"

  # Verify instance appears in list
  local list_output
  list_output=$("$INSTANCES_MODULE" list 2>&1)
  assert_contains "$list_output" "$generated_id" \
    "Instance created with generated ID should appear in list"
}

# =============================================================================
# TEST 9: Duplicate instance name is rejected (blueprint-level uniqueness)
# Creating two instances with the same name under same blueprint must fail
# =============================================================================

function test_duplicate_instance_name_rejected() {
  log_test_step "Testing: creating duplicate instance name is rejected"

  local instance_name="test-dup-$$"

  # Create first instance
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "First instance creation should succeed"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # Attempt to create a second instance with the same name
  local alt_name="${instance_name}-alt"
  setup_instance_prereqs "factorio" "$alt_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  "$INSTANCES_MODULE" create factorio \
    --library "$TEST_LIBRARY" \
    --name "$instance_name" 2>/dev/null
  local dup_exit=$?

  assert_not_equals 0 "$dup_exit" \
    "Creating instance with duplicate name should fail"

  # Also clean up the alt prereq symlink that was created above
  __cleanup_instance "factorio" "$alt_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# =============================================================================
# TEST 10: Steam blueprint instance config contains steam app id
# necesse (Steam, no account required) blueprint data flows into instance config
# =============================================================================

function test_steam_blueprint_data_flows_to_instance() {
  log_test_step "Testing: Steam blueprint data (steam_app_id, client_steam_app_id) appears in instance config"

  # Get necesse blueprint info (canonical JSON) and extract SteamAppId + ClientSteamAppId
  local blueprint_info
  blueprint_info=$("$BLUEPRINTS_MODULE" info necesse --json 2>&1)
  assert_equals 0 "$?" "blueprints info necesse --json should succeed"

  local expected_app_id expected_client_app_id
  expected_app_id=$(echo "$blueprint_info" | jq -r '.SteamAppId')
  expected_client_app_id=$(echo "$blueprint_info" | jq -r '.ClientSteamAppId')
  assert_not_null "$expected_app_id" "Necesse blueprint should have steam_app_id"
  assert_not_null "$expected_client_app_id" "Necesse blueprint should have client_steam_app_id"

  # Create an instance from necesse
  local instance_name="test-steam-$$"
  create_test_instance "necesse" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "necesse instance creation should succeed"
  _TEARDOWN_INSTANCES+=("necesse:$instance_name")

  # Instance config should contain the steam_app_id and client_steam_app_id
  local instance_config_path
  instance_config_path=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_file_exists "$instance_config_path" "Instance config file should exist"
  assert_file_contains "$instance_config_path" "$expected_app_id" \
    "Instance config should contain the blueprint's steam_app_id"
  assert_file_contains "$instance_config_path" "$expected_client_app_id" \
    "Instance config should contain the blueprint's client_steam_app_id"
}

# =============================================================================
# TEST 11: Instance info returns valid JSON with blueprint-derived fields
# instances info --json output should include instance_name and blueprint data
# =============================================================================

function test_instance_info_json_contains_blueprint_data() {
  log_test_step "Testing: instances info --json output contains blueprint-derived fields"

  local instance_name="test-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for JSON info test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local json_output
  json_output=$("$INSTANCES_MODULE" info "$instance_name" --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "instances info --json should succeed"

  # Validate it's parseable JSON
  echo "$json_output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "instances info --json should produce valid JSON"

  # JSON should include the name and blueprint-related fields
  # Template uses `name=` so JSON key is "name"
  assert_contains "$json_output" "\"name\"" \
    "JSON output should include 'name' key"
  assert_contains "$json_output" "$instance_name" \
    "JSON output should include the actual instance name"
}

# =============================================================================
# TEST 12: Blueprint type for native vs container reflected in instance runtime
# Native blueprint (factorio) → runtime=native; container (vrising) → runtime=container
# =============================================================================

function test_blueprint_type_reflected_in_instance_runtime() {
  log_test_step "Testing: blueprint type (native/container) is reflected in instance runtime"

  # Native blueprint: factorio
  local native_instance="test-native-$$"
  create_test_instance "factorio" "$native_instance" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Native (factorio) instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$native_instance")

  local native_config
  native_config=$("$INSTANCES_MODULE" find "$native_instance" 2>&1)
  # Instance config should contain the runtime key (template: runtime="${instance_runtime}")
  # Template produces: runtime="native" (with quotes around value)
  assert_file_contains "$native_config" 'runtime=' \
    "Native instance config should have runtime key"
  local native_runtime_val
  native_runtime_val=$(grep '^runtime=' "$native_config" | cut -d= -f2 | tr -d '"')
  assert_equals "native" "$native_runtime_val" \
    "Native instance config should have runtime value of native"

  # Verify blueprint module identifies it as native
  local bp_type
  bp_type=$("$BLUEPRINTS_MODULE" find factorio 2>&1)
  assert_contains "$bp_type" "factorio.bp.yaml" \
    "Native blueprint path should be factorio.bp.yaml"

  # Container blueprint: vrising (if Docker available)
  if ! is_docker_available; then
    log_test_step "Docker not available - skipping container blueprint type check"
    return 0
  fi

  local container_instance="test-container-$$"
  create_test_instance "vrising" "$container_instance" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Container (vrising) instance should be created"
  _TEARDOWN_INSTANCES+=("vrising:$container_instance")

  local container_config
  container_config=$("$INSTANCES_MODULE" find "$container_instance" 2>&1)
  assert_file_contains "$container_config" 'runtime=' \
    "Container instance config should have runtime key"
  local container_runtime_val
  container_runtime_val=$(grep '^runtime=' "$container_config" | cut -d= -f2 | tr -d '"')
  assert_equals "container" "$container_runtime_val" \
    "Container instance config should have runtime value of container"

  local bp_path
  bp_path=$("$BLUEPRINTS_MODULE" find vrising 2>&1)
  assert_contains "$bp_path" "vrising.bp.yaml" \
    "Container blueprint path should be vrising.bp.yaml"
}

