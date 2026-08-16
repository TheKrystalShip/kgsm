#!/usr/bin/env bash

# KGSM Instances Handler Logic Tests
#
# Test Type: UNIT
# Target: commands/handlers/instances.sh - Pure __logic_* functions
#
# Tests all logic functions for instance management including creation,
# removal, listing, and name generation. Uses manual minimal setup instead
# of kgsm.wrapper.sh to avoid complex installation dependencies.

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="instances_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/instances.sh"

# Test-specific paths
TEST_INSTALL_DIR=""

# Per-test cleanup tracking (used by teardown hook)
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# NOTE: Previously, this test file defined local helper functions:
#   - _setup_instance_prereqs(): Setup working dir + symlink
#   - remove_test_instance(): Remove symlink + dirs
#   - create_test_instance(): Combine prereqs + config creation
#
# These have been moved to tests/framework/kgsm.wrapper.sh as:
#   - setup_instance_prereqs(): Public function for manual control
#   - create_test_instance(): Automatic creation (prereqs + config)
#   - remove_test_instance(): Enhanced cleanup
#
# This makes the pattern reusable across all tests. See:
# tests/framework/kgsm.wrapper.example.sh for usage examples.

# Setup instance prerequisites using the enhanced wrapper
# Args: $1 = blueprint, $2 = instance_name
# Returns: 0 on success, non-zero on failure
function _setup_instance_prereqs() {
  local blueprint="$1"
  local instance_name="$2"

  setup_instance_prereqs "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
  return $?
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instances logic tests"

  # Set test install directory within sandbox
  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_not_null "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should be set"

  # Verify handler exists
  assert_file_exists "$HANDLER" "Handler should exist"

  # Source the handler
  # shellcheck disable=SC1090
  source "$HANDLER"

  # Verify error codes defined
  assert_not_null "$EC_SUCCESS_INSTANCE_CREATED" "EC_SUCCESS_INSTANCE_CREATED should be defined"
  assert_not_null "$EC_SUCCESS_INSTANCE_REMOVED" "EC_SUCCESS_INSTANCE_REMOVED should be defined"
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_BLUEPRINT_NOT_FOUND" "EC_BLUEPRINT_NOT_FOUND should be defined"
  assert_not_null "$EC_DIRECTORY_NOT_FOUND" "EC_DIRECTORY_NOT_FOUND should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_NOT_FOUND" "EC_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_INSTANCE" "EC_INVALID_INSTANCE should be defined"
  assert_not_null "$EC_FAILED_TOUCH" "EC_FAILED_TOUCH should be defined"
  assert_not_null "$EC_FAILED_RM" "EC_FAILED_RM should be defined"

  # Verify all logic functions are exported
  assert_function_exists "__logic_generate_unique_instance_name" "__logic_generate_unique_instance_name should be exported"
  assert_function_exists "__logic_instance_config_exists" "__logic_instance_config_exists should be exported"
  assert_function_exists "__logic_create_instance_config_file" "__logic_create_instance_config_file should be exported"
  assert_function_exists "__logic_create_base_instance" "__logic_create_base_instance should be exported"
  assert_function_exists "__logic_create_instance" "__logic_create_instance should be exported"
  assert_function_exists "__logic_remove_instance" "__logic_remove_instance should be exported"
  assert_function_exists "__logic_get_instances" "__logic_get_instances should be exported"
  assert_function_exists "__logic_get_instance_paths" "__logic_get_instance_paths should be exported"
  assert_function_exists "__set_instance_config_value" "__set_instance_config_value should be exported"
  assert_function_exists "__is_protected_instance_config_key" "__is_protected_instance_config_key should be exported"
  assert_function_exists "__get_instance_config_value" "__get_instance_config_value should be available"

  # Error codes used by the config setter
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_FAILED_SED" "EC_FAILED_SED should be defined"
  assert_not_null "$EC_FAILED_MV" "EC_FAILED_MV should be defined"

  log_test_step "Test environment validated"
}

function setup() {
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" 2>/dev/null || true
  done
}

# =============================================================================
# __logic_generate_unique_instance_name() TESTS
# =============================================================================

function test_generate_name_first_instance() {
  log_test_step "Testing __logic_generate_unique_instance_name for first instance"

  local blueprint="factorio"

  # Generate name for first instance (should return blueprint name)
  local generated_name
  generated_name=$(__logic_generate_unique_instance_name "$blueprint")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_equals "$blueprint" "$generated_name" "First instance should use blueprint name"
}

function test_generate_name_second_instance() {
  log_test_step "Testing __logic_generate_unique_instance_name when blueprint instance exists"

  local blueprint="factorio"
  local instance_name="$blueprint"

  # Create first instance with blueprint name
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Generate name for second instance (should return blueprint-XX format)
  local generated_name
  generated_name=$(__logic_generate_unique_instance_name "$blueprint")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_matches "$generated_name" "^${instance_name}-[0-9]+$" \
    "Second instance should use blueprint-suffix format"
}

function test_generate_name_empty_parameter() {
  log_test_step "Testing __logic_generate_unique_instance_name with empty parameter"

  __logic_generate_unique_instance_name "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty parameter"
}

function test_generate_name_container_blueprint() {
  log_test_step "Testing __logic_generate_unique_instance_name with container blueprint"

  local blueprint="vrising"

  # Generate name for container blueprint
  local generated_name
  generated_name=$(__logic_generate_unique_instance_name "$blueprint")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_equals "$blueprint" "$generated_name" \
    "First container instance should use blueprint name"
}

function test_generate_name_suffix_length() {
  log_test_step "Testing __logic_generate_unique_instance_name suffix length"

  local blueprint="necesse"

  # Create first instance
  create_test_instance "$blueprint" "$blueprint"
  _TEARDOWN_INSTANCES+=("$blueprint:$blueprint")

  # Generate second instance name
  local generated_name
  generated_name=$(__logic_generate_unique_instance_name "$blueprint")

  # Extract suffix (everything after blueprint-)
  local suffix="${generated_name#${blueprint}-}"
  local suffix_length="${#suffix}"

  # The suffix is as long as the configured value, whatever the sandbox seeds.
  # Asserting a literal here couples the test to the fixture instead of to the
  # behaviour it is checking.
  local expected_length="${config_instance_suffix_length:-2}"
  assert_equals "$expected_length" "$suffix_length" \
    "Suffix length should match config_instance_suffix_length"
}

# =============================================================================
# __logic_instance_config_exists() TESTS
# =============================================================================

function test_config_exists_true() {
  log_test_step "Testing __logic_instance_config_exists when config exists"

  local blueprint="factorio"
  local instance_name="test-exists"

  # Create minimal instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Check if config exists
  __logic_instance_config_exists "$instance_name" "$blueprint"
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should return 0 when config exists"
}

function test_config_exists_false() {
  log_test_step "Testing __logic_instance_config_exists when config does not exist"

  local blueprint="factorio"
  local instance_name="nonexistent"

  # Check if config exists (it doesn't)
  __logic_instance_config_exists "$instance_name" "$blueprint"
  local exit_code=$?

  assert_equals 1 "$exit_code" "Should return 1 when config does not exist"
}

function test_config_exists_empty_instance_name() {
  log_test_step "Testing __logic_instance_config_exists with empty instance name"

  __logic_instance_config_exists "" "factorio" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance name"
}

function test_config_exists_empty_blueprint_name() {
  log_test_step "Testing __logic_instance_config_exists with empty blueprint name"

  __logic_instance_config_exists "test" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty blueprint name"
}

function test_config_exists_both_empty() {
  log_test_step "Testing __logic_instance_config_exists with both parameters empty"

  __logic_instance_config_exists "" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for both empty parameters"
}

# =============================================================================
# __logic_create_instance_config_file() TESTS
# =============================================================================

function test_create_config_file_success() {
  log_test_step "Testing __logic_create_instance_config_file with valid symlink"

  local blueprint="factorio"
  local instance_name="test-config"

  # Setup prerequisites (symlink must exist)
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create config file
  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_not_null "$config_path" "Should return config file path"
  assert_file_exists "$config_path" "Config file should exist"

  # Verify path format
  local expected_config="${instance_name}.config.ini"
  assert_contains "$config_path" "$expected_config" \
    "Path should contain correct config filename"
}

function test_create_config_file_empty_instance_name() {
  log_test_step "Testing __logic_create_instance_config_file with empty instance name"

  __logic_create_instance_config_file "" "factorio" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance name"
}

function test_create_config_file_empty_blueprint() {
  log_test_step "Testing __logic_create_instance_config_file with empty blueprint"

  __logic_create_instance_config_file "test" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty blueprint"
}

function test_create_config_file_no_symlink() {
  log_test_step "Testing __logic_create_instance_config_file without existing symlink"

  local blueprint="factorio"
  local instance_name="no-symlink"

  # Don't create symlink - call function directly
  __logic_create_instance_config_file "$instance_name" "$blueprint" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_DIRECTORY_NOT_FOUND" "$exit_code" \
    "Should return EC_DIRECTORY_NOT_FOUND when symlink doesn't exist"
}

function test_create_config_file_container_blueprint() {
  log_test_step "Testing __logic_create_instance_config_file with container blueprint"

  local blueprint="vrising"
  local instance_name="test-container-config"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create config file
  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed for container blueprint"
  assert_file_exists "$config_path" "Config file should exist"
}

# =============================================================================
# __logic_create_base_instance() TESTS
# =============================================================================

function test_create_base_instance_native_blueprint() {
  log_test_step "Testing __logic_create_base_instance with native blueprint"

  local blueprint="factorio"
  local instance_name="test-base-native"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create config file first
  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")

  # Get blueprint path
  local blueprint_path="$KGSM_ROOT/blueprints/$blueprint.bp.yaml"

  # Create base instance
  __logic_create_base_instance "$config_path" "$instance_name" "$blueprint_path" "$TEST_INSTALL_DIR"
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_file_exists "$config_path" "Config file should still exist"

  # Verify config contains expected values
  assert_file_contains "$config_path" "runtime=\"native\"" \
    "Config should contain runtime=native"
  assert_file_contains "$config_path" "name=\"$instance_name\"" \
    "Config should contain instance name"
}

function test_create_base_instance_materializes_player_patterns() {
  log_test_step "Testing __logic_create_base_instance materializes blueprint player-presence patterns into the config"

  local blueprint="factorio"
  local instance_name="test-base-player-patterns"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Set player-presence patterns on the sandboxed blueprint (yq is a kgsm hard
  # dep). These flow blueprint -> blueprint_player_*_regex (loader) ->
  # instance_player_*_regex (export) -> instance.tp -> config, so the watchdog
  # can read them off `instances info --json` for native detection. Plain literal
  # tokens (no regex metacharacters) so the grep-based assertion below matches
  # the value verbatim — real-pattern matching is covered by the watchdog tests.
  local blueprint_path="$KGSM_ROOT/blueprints/$blueprint.bp.yaml"
  yq -i '.player_joined_regex = "JOINMARK"' "$blueprint_path"
  yq -i '.player_left_regex = "LEAVEMARK"' "$blueprint_path"

  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")

  __logic_create_base_instance "$config_path" "$instance_name" "$blueprint_path" "$TEST_INSTALL_DIR"
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"

  # The raw (un-encoded) patterns must land in the instance config verbatim.
  assert_file_contains "$config_path" 'player_joined_regex="JOINMARK"' \
    "Config should materialize player_joined_regex from the blueprint"
  assert_file_contains "$config_path" 'player_left_regex="LEAVEMARK"' \
    "Config should materialize player_left_regex from the blueprint"
}

function test_create_base_instance_player_patterns_empty_when_unset() {
  log_test_step "Testing player-presence pattern keys are present-but-empty when the blueprint sets none"

  local blueprint="factorio"
  local instance_name="test-base-no-player-patterns"

  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local blueprint_path="$KGSM_ROOT/blueprints/$blueprint.bp.yaml"
  # Order-independent: ensure the shared-sandbox blueprint has NO patterns (another
  # test may have set them). __bp_yaml_field maps an absent key -> "" (loader.sh).
  yq -i 'del(.player_joined_regex, .player_left_regex)' "$blueprint_path"

  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")

  __logic_create_base_instance "$config_path" "$instance_name" "$blueprint_path" "$TEST_INSTALL_DIR"

  # Keys always present (so `instances info --json` carries them) but empty -> the
  # watchdog reads "" and disables native detection (honest unknown, no event).
  assert_file_contains "$config_path" 'player_joined_regex=""' \
    "Unset blueprint pattern should yield an empty player_joined_regex key"
  assert_file_contains "$config_path" 'player_left_regex=""' \
    "Unset blueprint pattern should yield an empty player_left_regex key"
}

function test_create_base_instance_materializes_upnp_gate_default_false() {
  log_test_step "Testing __logic_create_base_instance materializes the UPnP gate (default false)"

  local blueprint="factorio"
  local instance_name="test-base-upnp-default"

  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local blueprint_path="$KGSM_ROOT/blueprints/$blueprint.bp.yaml"
  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")

  __logic_create_base_instance "$config_path" "$instance_name" "$blueprint_path" "$TEST_INSTALL_DIR"
  local exit_code=$?
  assert_equals 0 "$exit_code" "Should succeed"

  # The gate key is always present (so the watchdog reads it off `instances info
  # --json`) and defaults false = inert (no UPnP op until explicitly enabled).
  assert_file_contains "$config_path" 'enable_port_forwarding="false"' \
    "Config should materialize the UPnP gate defaulting to false"
}

function test_create_base_instance_upnp_gate_seeds_from_config() {
  log_test_step "Testing the UPnP gate seeds from config_enable_port_forwarding"

  local blueprint="factorio"
  local instance_name="test-base-upnp-seeded"

  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local blueprint_path="$KGSM_ROOT/blueprints/$blueprint.bp.yaml"
  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")

  # The host default (config_enable_port_forwarding) seeds each new instance; flip
  # it true for this create and confirm it flows config -> instance var -> config
  # file. Save/restore so it never leaks to a sibling test in the shared shell.
  local _saved="${config_enable_port_forwarding:-}"
  export config_enable_port_forwarding="true"
  __logic_create_base_instance "$config_path" "$instance_name" "$blueprint_path" "$TEST_INSTALL_DIR"
  local exit_code=$?
  if [[ -n "$_saved" ]]; then
    export config_enable_port_forwarding="$_saved"
  else
    unset config_enable_port_forwarding
  fi

  assert_equals 0 "$exit_code" "Should succeed"
  assert_file_contains "$config_path" 'enable_port_forwarding="true"' \
    "A true host default should materialize enable_port_forwarding=\"true\""
}

function test_create_base_instance_container_blueprint() {
  log_test_step "Testing __logic_create_base_instance with container blueprint"

  local blueprint="vrising"
  local instance_name="test-base-container"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create config file
  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")

  # Get blueprint path
  local blueprint_path="$KGSM_ROOT/blueprints/$blueprint.bp.yaml"

  # Create base instance
  __logic_create_base_instance "$config_path" "$instance_name" "$blueprint_path" "$TEST_INSTALL_DIR"
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"

  # Verify config contains container runtime
  assert_file_contains "$config_path" "runtime=\"container\"" \
    "Config should contain runtime=container"
}

function test_create_base_instance_empty_config_path() {
  log_test_step "Testing __logic_create_base_instance with empty config path"

  __logic_create_base_instance "" "test" "$KGSM_ROOT/blueprints/factorio.bp.yaml" "$TEST_INSTALL_DIR" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty config path"
}

function test_create_base_instance_empty_instance_name() {
  log_test_step "Testing __logic_create_base_instance with empty instance name"

  __logic_create_base_instance "/tmp/config" "" "$KGSM_ROOT/blueprints/factorio.bp.yaml" "$TEST_INSTALL_DIR" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance name"
}

function test_create_base_instance_empty_blueprint_path() {
  log_test_step "Testing __logic_create_base_instance with empty blueprint path"

  __logic_create_base_instance "/tmp/config" "test" "" "$TEST_INSTALL_DIR" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty blueprint path"
}

function test_create_base_instance_empty_install_dir() {
  log_test_step "Testing __logic_create_base_instance with empty install directory"

  __logic_create_base_instance "/tmp/config" "test" "$KGSM_ROOT/blueprints/factorio.bp.yaml" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty install directory"
}

function test_create_base_instance_invalid_blueprint() {
  log_test_step "Testing __logic_create_base_instance with invalid blueprint file"

  local blueprint="factorio"
  local instance_name="test-invalid-bp"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create config file
  local config_path
  config_path=$(__logic_create_instance_config_file "$instance_name" "$blueprint")

  # Use non-existent blueprint path - this will fail parameter validation first
  __logic_create_base_instance "" "$instance_name" "/nonexistent.bp.yaml" "$TEST_INSTALL_DIR" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG when config path is empty"
}

# =============================================================================
# __logic_create_instance() TESTS
# =============================================================================

function test_create_instance_native_blueprint() {
  log_test_step "Testing __logic_create_instance with native blueprint"

  local blueprint="factorio"
  local instance_name="test-create-native"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create instance
  local result
  result=$(__logic_create_instance "$blueprint" "$TEST_INSTALL_DIR" "$instance_name")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_CREATED"
  assert_equals "$instance_name" "$result" "Should echo instance name"

  # Verify config file exists
  local config_path="$KGSM_INSTANCES_DIR/$blueprint/$instance_name/$instance_name.config.ini"
  assert_file_exists "$config_path" "Config file should exist"
}

function test_create_instance_container_blueprint() {
  log_test_step "Testing __logic_create_instance with container blueprint"

  local blueprint="vrising"
  local instance_name="test-create-container"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create instance
  local result
  result=$(__logic_create_instance "$blueprint" "$TEST_INSTALL_DIR" "$instance_name")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_CREATED"
  assert_equals "$instance_name" "$result" "Should echo instance name"
}

function test_create_instance_auto_generate_name() {
  log_test_step "Testing __logic_create_instance with auto-generated name"

  local blueprint="necesse"

  # Don't setup prereqs - but we need to create the instance with auto name
  # Since the function generates the name, we need to setup after knowing the name
  # Actually, the symlink MUST exist before __logic_create_instance is called
  # So we need to generate the name first, then setup prereqs

  local generated_name
  generated_name=$(__logic_generate_unique_instance_name "$blueprint")

  # Setup prerequisites with generated name
  _setup_instance_prereqs "$blueprint" "$generated_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$generated_name")

  # Create instance without identifier (auto-generate)
  local result
  result=$(__logic_create_instance "$blueprint" "$TEST_INSTALL_DIR" "")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_CREATED"
  assert_not_null "$result" "Should echo generated instance name"
}

function test_create_instance_custom_identifier() {
  log_test_step "Testing __logic_create_instance with custom identifier"

  local blueprint="factorio"
  local custom_name="my-custom-server"

  # Setup prerequisites
  _setup_instance_prereqs "$blueprint" "$custom_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$custom_name")

  # Create instance with custom identifier
  local result
  result=$(__logic_create_instance "$blueprint" "$TEST_INSTALL_DIR" "$custom_name")
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_CREATED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_CREATED"
  assert_equals "$custom_name" "$result" "Should use custom identifier"
}

function test_create_instance_invalid_blueprint() {
  log_test_step "Testing __logic_create_instance with invalid blueprint"

  __logic_create_instance "nonexistent-blueprint" "$TEST_INSTALL_DIR" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" \
    "Should return EC_BLUEPRINT_NOT_FOUND for invalid blueprint"
}

function test_create_instance_nonexistent_install_dir() {
  log_test_step "Testing __logic_create_instance with non-existent install directory"

  local blueprint="factorio"
  local nonexistent_dir="/nonexistent/path/to/nowhere"

  __logic_create_instance "$blueprint" "$nonexistent_dir" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_DIRECTORY_NOT_FOUND" "$exit_code" \
    "Should return EC_DIRECTORY_NOT_FOUND for non-existent install directory"
}

function test_create_instance_unwritable_install_dir() {
  log_test_step "Testing __logic_create_instance with unwritable install directory"

  local blueprint="factorio"
  local readonly_dir="$TEST_INSTALL_DIR/readonly"

  # Create directory and make it unwritable
  mkdir -p "$readonly_dir"
  local original_perms
  original_perms=$(stat -c "%a" "$readonly_dir")
  chmod 000 "$readonly_dir"

  # Test with unwritable directory
  __logic_create_instance "$blueprint" "$readonly_dir" "" 2>/dev/null
  local exit_code=$?

  # Restore permissions immediately
  chmod "$original_perms" "$readonly_dir"
  rmdir "$readonly_dir"

  assert_equals "$EC_PERMISSION" "$exit_code" \
    "Should return EC_PERMISSION for unwritable install directory"
}

function test_create_instance_duplicate_name() {
  log_test_step "Testing __logic_create_instance with duplicate instance name"

  local blueprint="factorio"
  local instance_name="duplicate-test"

  # Create first instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Try to create second instance with same name
  # Setup prereqs again would fail, so we just call the logic directly
  __logic_create_instance "$blueprint" "$TEST_INSTALL_DIR" "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_INSTANCE" "$exit_code" \
    "Should return EC_INVALID_INSTANCE for duplicate instance name"
}

# =============================================================================
# __logic_remove_instance() TESTS
# =============================================================================

function test_remove_instance_success() {
  log_test_step "Testing __logic_remove_instance with valid instance"

  local blueprint="factorio"
  local instance_name="test-remove"

  # Create minimal instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Verify symlink exists before removal
  local symlink_path="$KGSM_INSTANCES_DIR/$blueprint/$instance_name"
  if [[ -L "$symlink_path" ]]; then
    assert_true "true" "Symlink should exist before removal"
  else
    assert_true "false" "Symlink should exist before removal"
  fi

  # Remove instance
  __logic_remove_instance "$instance_name"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_REMOVED" "$exit_code" \
    "Should return EC_SUCCESS_INSTANCE_REMOVED"

  # Verify symlink removed
  if [[ -L "$symlink_path" ]]; then
    assert_false "true" "Symlink should be removed"
  else
    assert_false "false" "Symlink should be removed"
  fi
}

function test_remove_instance_empty_blueprint_dir() {
  log_test_step "Testing __logic_remove_instance removes empty blueprint directory"

  local blueprint="factorio"
  local instance_name="test-remove-dir"

  # Create minimal instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Remove instance
  __logic_remove_instance "$instance_name"

  # Verify instance directory removed (was empty after instance removal)
  local instance_dir="${KGSM_INSTANCES_DIR}/${blueprint}/${instance_name}"
  if [[ -d "$instance_dir" ]]; then
    assert_false "true" "Empty instance directory should be removed"
  else
    assert_false "false" "Empty instance directory should be removed"
  fi
}

function test_remove_instance_empty_parameter() {
  log_test_step "Testing __logic_remove_instance with empty parameter"

  __logic_remove_instance "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty parameter"
}

function test_remove_instance_nonexistent() {
  log_test_step "Testing __logic_remove_instance with non-existent instance"

  __logic_remove_instance "nonexistent-instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_NOT_FOUND" "$exit_code" \
    "Should return EC_NOT_FOUND for non-existent instance"
}

function test_remove_instance_not_symlink() {
  log_test_step "Testing __logic_remove_instance when instance dir is not a symlink"

  local blueprint="factorio"
  local instance_name="test-not-symlink"

  # Create instance directory structure but not as symlink
  local instance_dir="$KGSM_INSTANCES_DIR/$blueprint/$instance_name"
  mkdir -p "$instance_dir"
  touch "$instance_dir/$instance_name.config.ini"

  # Try to remove (should fail because it's not a symlink)
  __logic_remove_instance "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_INSTANCE" "$exit_code" \
    "Should return EC_INVALID_INSTANCE when instance dir is not a symlink"

  # Cleanup
  rm -rf "$KGSM_INSTANCES_DIR/$blueprint"
}

function test_remove_instance_container_blueprint() {
  log_test_step "Testing __logic_remove_instance with container blueprint instance"

  local blueprint="vrising"
  local instance_name="test-remove-container"

  # Create minimal container instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Remove instance
  __logic_remove_instance "$instance_name"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_REMOVED" "$exit_code" \
    "Should succeed for container blueprint instance"
}

# =============================================================================
# __logic_get_instances() TESTS
# =============================================================================

function test_get_instances_all() {
  log_test_step "Testing __logic_get_instances without filter"

  local blueprint1="factorio"
  local blueprint2="necesse"
  local instance1="test-all-1"
  local instance2="test-all-2"
  local instance3="test-all-3"

  # Create multiple instances
  create_test_instance "$blueprint1" "$instance1"
  _TEARDOWN_INSTANCES+=("$blueprint1:$instance1")
  create_test_instance "$blueprint1" "$instance2"
  _TEARDOWN_INSTANCES+=("$blueprint1:$instance2")
  create_test_instance "$blueprint2" "$instance3"
  _TEARDOWN_INSTANCES+=("$blueprint2:$instance3")

  # Get all instances
  local instances
  instances=$(__logic_get_instances "")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_contains "$instances" "$instance1" "Should contain instance1"
  assert_contains "$instances" "$instance2" "Should contain instance2"
  assert_contains "$instances" "$instance3" "Should contain instance3"
}

function test_get_instances_filtered_by_blueprint() {
  log_test_step "Testing __logic_get_instances filtered by blueprint"

  local blueprint1="factorio"
  local blueprint2="necesse"
  local instance1="test-filter-1"
  local instance2="test-filter-2"
  local instance3="test-filter-3"

  # Create instances for different blueprints
  create_test_instance "$blueprint1" "$instance1"
  _TEARDOWN_INSTANCES+=("$blueprint1:$instance1")
  create_test_instance "$blueprint1" "$instance2"
  _TEARDOWN_INSTANCES+=("$blueprint1:$instance2")
  create_test_instance "$blueprint2" "$instance3"
  _TEARDOWN_INSTANCES+=("$blueprint2:$instance3")

  # Get only factorio instances
  local instances
  instances=$(__logic_get_instances "$blueprint1")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_contains "$instances" "$instance1" "Should contain factorio instance1"
  assert_contains "$instances" "$instance2" "Should contain factorio instance2"
  assert_not_contains "$instances" "$instance3" \
    "Should not contain necesse instance"
}

function test_get_instances_empty_result() {
  log_test_step "Testing __logic_get_instances with no instances"

  # Get instances when none exist
  local instances
  instances=$(__logic_get_instances "")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed even with no instances"

  if [[ -n "$instances" ]]; then
    skip_test "Instances exist in environment, cannot test empty result"
    return
  fi

  assert_null "$instances" "Should return empty result"
}

function test_get_instances_single_instance() {
  log_test_step "Testing __logic_get_instances with single instance"

  local blueprint="factorio"
  local instance_name="test-single"

  # Create single instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Get instances
  local instances
  instances=$(__logic_get_instances "")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"

  if [[ -n "$instances" ]]; then
    skip_test "Multiple instances exist in environment, cannot test single instance result"
    return
  fi

  assert_equals "$instance_name" "$instances" \
    "Should return single instance name"
}

function test_get_instances_container_blueprint() {
  log_test_step "Testing __logic_get_instances with container blueprint"

  local blueprint="vrising"
  local instance_name="test-container-list"

  # Create container instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Get instances filtered by container blueprint
  local instances
  instances=$(__logic_get_instances "$blueprint")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_contains "$instances" "$instance_name" \
    "Should contain container instance"
}

# =============================================================================
# __logic_get_instance_paths() TESTS
# =============================================================================

function test_get_instance_paths_all() {
  log_test_step "Testing __logic_get_instance_paths without filter"

  local blueprint1="factorio"
  local blueprint2="necesse"
  local instance1="test-paths-1"
  local instance2="test-paths-2"

  # Create instances
  create_test_instance "$blueprint1" "$instance1"
  _TEARDOWN_INSTANCES+=("$blueprint1:$instance1")
  create_test_instance "$blueprint2" "$instance2"
  _TEARDOWN_INSTANCES+=("$blueprint2:$instance2")

  # Get all instance paths
  local paths
  paths=$(__logic_get_instance_paths "")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_contains "$paths" "$instance1.config.ini" \
    "Should contain config path for instance1"
  assert_contains "$paths" "$instance2.config.ini" \
    "Should contain config path for instance2"
}

function test_get_instance_paths_filtered() {
  log_test_step "Testing __logic_get_instance_paths filtered by blueprint"

  local blueprint1="factorio"
  local blueprint2="necesse"
  local instance1="test-path-filter-1"
  local instance2="test-path-filter-2"

  # Create instances
  create_test_instance "$blueprint1" "$instance1"
  _TEARDOWN_INSTANCES+=("$blueprint1:$instance1")
  create_test_instance "$blueprint2" "$instance2"
  _TEARDOWN_INSTANCES+=("$blueprint2:$instance2")

  # Get paths filtered by blueprint1
  local paths
  paths=$(__logic_get_instance_paths "$blueprint1")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_contains "$paths" "$instance1.config.ini" \
    "Should contain factorio instance path"
  assert_not_contains "$paths" "$instance2.config.ini" \
    "Should not contain necesse instance path"
}

function test_get_instance_paths_empty_result() {
  log_test_step "Testing __logic_get_instance_paths with no instances"

  # Get paths when none exist
  local paths
  paths=$(__logic_get_instance_paths "")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed even with no instances"

  if [[ -n "$paths" ]]; then
    skip_test "Instances exist in environment, cannot test empty result"
    return
  fi

  assert_null "$paths" "Should return empty result"
}

function test_get_instance_paths_absolute() {
  log_test_step "Testing __logic_get_instance_paths returns absolute paths"

  local blueprint="factorio"
  local instance_name="test-absolute-path"

  # Create instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Get paths
  local paths
  paths=$(__logic_get_instance_paths "")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_matches "$paths" "^/" "Path should be absolute (start with /)"
}

function test_get_instance_paths_container_blueprint() {
  log_test_step "Testing __logic_get_instance_paths with container blueprint"

  local blueprint="vrising"
  local instance_name="test-container-paths"

  # Create container instance
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Get paths
  local paths
  paths=$(__logic_get_instance_paths "$blueprint")
  local exit_code=$?

  assert_equals 0 "$exit_code" "Should succeed"
  assert_contains "$paths" "$instance_name.config.ini" \
    "Should contain container instance config path"
}

# =============================================================================
# __is_protected_instance_config_key() TESTS
# =============================================================================

function test_protected_key_classification() {
  log_test_step "Testing __is_protected_instance_config_key classifies keys correctly"

  # Keys that must be refused (identity/structural, managed paths, toggles)
  local protected=(
    name blueprint_file runtime platform install_datetime
    is_steam_account_required steam_app_id client_steam_app_id ports
    install_dir working_dir logs_dir saves_dir backups_dir temp_dir launch_dir
    management_file pid_file log_file socket_file version_file
    executable_file compose_file firewall_rule_file command_shortcut_file
    executable_subdirectory
    enable_firewall_management enable_command_shortcuts
  )
  local key
  for key in "${protected[@]}"; do
    __is_protected_instance_config_key "$key"
    assert_equals 0 "$?" "'$key' should be classified as protected"
  done

  # Plain runtime values that must remain settable
  local settable=(
    auto_update executable_arguments level_name compress_backups
    save_command stop_command save_command_timeout_seconds
    stop_command_timeout_seconds startup_success_regex steamcmd_arguments
    wget_timeout_seconds
  )
  for key in "${settable[@]}"; do
    __is_protected_instance_config_key "$key"
    assert_equals 1 "$?" "'$key' should be classified as settable"
  done
}

# =============================================================================
# __set_instance_config_value() TESTS
# =============================================================================

function test_set_config_updates_existing_key() {
  log_test_step "Testing __set_instance_config_value updates an existing key (quoted)"

  local blueprint="factorio"
  local instance_name="test-set-existing"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  __set_instance_config_value "$instance_name" "auto_update" "true"
  local exit_code=$?
  assert_equals 0 "$exit_code" "Should succeed with no event (return 0)"

  local config_path="$KGSM_INSTANCES_DIR/$blueprint/$instance_name/$instance_name.config.ini"
  assert_file_contains "$config_path" 'auto_update="true"' \
    "Value should be written in quoted key=\"value\" form"

  local got
  got=$(__get_instance_config_value "$instance_name" "auto_update")
  assert_equals "true" "$got" "Round-trip should return the new value"
}

function test_set_config_value_with_spaces_equals_backslash() {
  log_test_step "Testing __set_instance_config_value preserves spaces, '=', and backslashes"

  local blueprint="factorio"
  local instance_name="test-set-complex"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # The headline use case: executable_arguments with spaces, an embedded '='
  # and a backslash (as in a regex). Must round-trip byte-for-byte.
  local value='--start-server saves/my=world.zip --regex \d+'
  __set_instance_config_value "$instance_name" "executable_arguments" "$value"
  assert_equals 0 "$?" "Should succeed"

  local got
  got=$(__get_instance_config_value "$instance_name" "executable_arguments")
  assert_equals "$value" "$got" \
    "Complex value (spaces + '=' + backslash) must round-trip verbatim"
}

function test_set_config_value_with_quotes_stays_sourceable() {
  log_test_step "Testing __set_instance_config_value keeps a quoted value sourceable"

  local blueprint="factorio"
  local instance_name="test-set-quoted"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # A presence regex matching a quoted player name — the shape Necesse's
  # disconnect line needs. Written unescaped, the embedded quotes close the
  # assignment early and the rest of the line is parsed as code, which makes the
  # whole config unsourceable and bricks the instance.
  local value='Player (?<id>\d+) \("(?<name>[^"]*)"\) disconnected: `x` \\'
  __set_instance_config_value "$instance_name" "player_left_regex" "$value"
  assert_equals 0 "$?" "Should succeed"

  local config_file
  config_file=$(__find_instance_config "$instance_name")

  # The file must still source, and both readers must return what went in:
  # sourcing is what the management script does, __get_instance_config_value is
  # what everything else does, and the two agreeing is the actual contract.
  local sourced
  sourced=$(bash -c "source '$config_file' && printf '%s' \"\$player_left_regex\"")
  assert_equals 0 "$?" "Config with a quoted value must still be sourceable"
  assert_equals "$value" "$sourced" "Sourcing must yield the value verbatim"

  local got
  got=$(__get_instance_config_value "$instance_name" "player_left_regex")
  assert_equals "$value" "$got" "Text reader must agree with sourcing"
}

function test_set_config_adds_absent_key() {
  log_test_step "Testing __set_instance_config_value adds a key that is absent"

  local blueprint="factorio"
  local instance_name="test-set-absent"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local config_path="$KGSM_INSTANCES_DIR/$blueprint/$instance_name/$instance_name.config.ini"
  # A settable (non-protected) key that the template does not define
  if grep -q "^custom_runtime_flag=" "$config_path"; then
    assert_false "true" "custom_runtime_flag should be absent before the test"
  fi

  __set_instance_config_value "$instance_name" "custom_runtime_flag" "on"
  assert_equals 0 "$?" "Should succeed adding an absent key"

  local got
  got=$(__get_instance_config_value "$instance_name" "custom_runtime_flag")
  assert_equals "on" "$got" "Added key should be readable"
}

function test_set_config_preserves_other_keys() {
  log_test_step "Testing __set_instance_config_value leaves other keys untouched"

  local blueprint="factorio"
  local instance_name="test-set-preserve"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local name_before runtime_before
  name_before=$(__get_instance_config_value "$instance_name" "name")
  runtime_before=$(__get_instance_config_value "$instance_name" "runtime")

  __set_instance_config_value "$instance_name" "level_name" "my-world"
  assert_equals 0 "$?" "Should succeed"

  assert_equals "$name_before" "$(__get_instance_config_value "$instance_name" name)" \
    "name should be unchanged"
  assert_equals "$runtime_before" "$(__get_instance_config_value "$instance_name" runtime)" \
    "runtime should be unchanged"
}

function test_set_config_refuses_identity_key() {
  log_test_step "Testing __set_instance_config_value refuses an identity key"

  local blueprint="factorio"
  local instance_name="test-refuse-identity"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local before
  before=$(__get_instance_config_value "$instance_name" "name")

  __set_instance_config_value "$instance_name" "name" "hacked" 2>/dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should refuse identity key 'name'"

  assert_equals "$before" "$(__get_instance_config_value "$instance_name" name)" \
    "'name' must be unchanged after a refused set"
}

function test_set_config_refuses_path_keys() {
  log_test_step "Testing __set_instance_config_value refuses managed path keys"

  local blueprint="factorio"
  local instance_name="test-refuse-paths"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local key
  for key in install_dir working_dir management_file pid_file executable_subdirectory; do
    local before
    before=$(__get_instance_config_value "$instance_name" "$key")
    __set_instance_config_value "$instance_name" "$key" "/tmp/evil" 2>/dev/null
    assert_equals "$EC_INVALID_ARG" "$?" "Should refuse managed path key '$key'"
    assert_equals "$before" "$(__get_instance_config_value "$instance_name" "$key")" \
      "'$key' must be unchanged after a refused set"
  done
}

function test_set_config_refuses_toggle_keys() {
  log_test_step "Testing __set_instance_config_value refuses integration toggles"

  local blueprint="factorio"
  local instance_name="test-refuse-toggles"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local key
  for key in enable_firewall_management enable_command_shortcuts; do
    __set_instance_config_value "$instance_name" "$key" "true" 2>/dev/null
    assert_equals "$EC_INVALID_ARG" "$?" "Should refuse integration toggle '$key'"
  done
}

function test_set_config_rejects_invalid_key_format() {
  log_test_step "Testing __set_instance_config_value rejects malformed keys"

  # These return before any instance lookup, so no instance is required.
  local badkey
  for badkey in "bad key" "1leading" "has-dash" "has.dot" "with\$dollar" ""; do
    __set_instance_config_value "any-instance" "$badkey" "x" 2>/dev/null
    assert_equals "$EC_INVALID_ARG" "$?" "Should reject malformed key '$badkey'"
  done
}

function test_set_config_empty_instance() {
  log_test_step "Testing __set_instance_config_value with empty instance name"

  __set_instance_config_value "" "auto_update" "true" 2>/dev/null
  assert_equals "$EC_INVALID_ARG" "$?" \
    "Should return EC_INVALID_ARG for empty instance name"
}

function test_set_config_unknown_instance() {
  log_test_step "Testing __set_instance_config_value with unknown instance"

  __set_instance_config_value "nonexistent-instance-xyz" "auto_update" "true" 2>/dev/null
  assert_equals "$EC_FILE_NOT_FOUND" "$?" \
    "Should return EC_FILE_NOT_FOUND for unknown instance"
}

# =============================================================================
# __get_instance_config_value() REGRESSION TEST
# =============================================================================

function test_get_config_value_preserves_embedded_equals() {
  log_test_step "Testing __get_instance_config_value preserves '=' in values"

  local blueprint="factorio"
  local instance_name="test-get-equals"
  create_test_instance "$blueprint" "$instance_name"
  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local config_path="$KGSM_INSTANCES_DIR/$blueprint/$instance_name/$instance_name.config.ini"
  # Write a raw line directly (bypassing the setter) to isolate the getter.
  printf 'getter_probe="a=b=c"\n' >> "$config_path"

  local got
  got=$(__get_instance_config_value "$instance_name" "getter_probe")
  assert_equals "a=b=c" "$got" \
    "Getter must not truncate at the second '=' (split on first '=' only)"
}

