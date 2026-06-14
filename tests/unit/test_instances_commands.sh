#!/usr/bin/env bash

# KGSM Instances Command Tests
#
# Test Type: UNIT
# Target: commands/instances.sh - CLI interface

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instances_commands"
readonly MODULE="$KGSM_ROOT/commands/instances.sh"

# Test-specific paths
TEST_INSTALL_DIR=""

# Per-test cleanup tracking (used by teardown hook)
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instances commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "instances.sh command should exist"
  assert_file_executable "$MODULE" "instances.sh command should be executable"

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
    remove_test_instance "$bp" "$name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  done
}

# =============================================================================
# TEST: help - Shows Usage
# =============================================================================

function test_help_command() {
  log_test_step "Testing 'help' command"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should exit 0"
  assert_contains "$output" "create" "help should mention create"
  assert_contains "$output" "remove" "help should mention remove"
  assert_contains "$output" "list" "help should mention list"
  assert_contains "$output" "info" "help should mention info"
  assert_contains "$output" "find" "help should mention find"
  assert_contains "$output" "generate-id" "help should mention generate-id"
}

function test_help_subcommands() {
  log_test_step "Testing help sub-commands"

  local commands=("create" "remove" "list" "info" "status" "find" "generate-id")

  for cmd in "${commands[@]}"; do
    local output
    output=$("$MODULE" help "$cmd" 2>&1)
    assert_equals 0 "$?" "help $cmd should exit 0"
    assert_not_null "$output" "help $cmd should produce output"
  done
}

function test_no_args_shows_usage() {
  log_test_step "Testing that no arguments shows usage and fails"

  "$MODULE" 2>/dev/null
  assert_not_equals 0 "$?" "No arguments should exit non-zero"
}

# =============================================================================
# TEST: list - Lists Instances
# =============================================================================

function test_list_empty() {
  log_test_step "Testing 'list' with no instances"

  local output
  output=$("$MODULE" list 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list should succeed even with no instances"
}

function test_list_json_empty() {
  log_test_step "Testing 'list --json' with no instances"

  local output
  output=$("$MODULE" list --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list --json should succeed"
  # Should output valid JSON array
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "list --json output should be valid JSON"
}

# =============================================================================
# TEST: generate-id - Produces Instance ID
# =============================================================================

function test_generate_id_valid_blueprint() {
  log_test_step "Testing 'generate-id factorio' produces output"

  local output
  output=$("$MODULE" generate-id factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "generate-id should succeed with valid blueprint"
  assert_not_null "$output" "generate-id should produce output"
}

function test_generate_id_with_bp_extension() {
  log_test_step "Testing 'generate-id factorio.bp' with extension"

  local output
  output=$("$MODULE" generate-id factorio.bp 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "generate-id should succeed with .bp extension"
  assert_not_null "$output" "generate-id should produce output"
}

function test_generate_id_missing_blueprint() {
  log_test_step "Testing 'generate-id' without blueprint argument"

  "$MODULE" generate-id 2>/dev/null
  assert_not_equals 0 "$?" "generate-id without blueprint should fail"
}

function test_generate_id_invalid_blueprint() {
  log_test_step "Testing 'generate-id' with nonexistent blueprint"

  "$MODULE" generate-id totally_nonexistent_blueprint_xyz 2>/dev/null
  assert_not_equals 0 "$?" "generate-id with invalid blueprint should fail"
}

# =============================================================================
# TEST: create - Creates Instance
# =============================================================================

function test_create_instance() {
  log_test_step "Testing 'create' command creates instance"

  local instance_name
  instance_name="test-create-$$"

  # Setup prerequisites
  setup_instance_prereqs "factorio" "$instance_name" "$TEST_INSTALL_DIR"

  local output
  output=$("$MODULE" create factorio \
    --install-dir "$TEST_INSTALL_DIR" \
    --name "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "create should succeed"
  assert_not_null "$output" "create should output the instance name"
  assert_contains "$output" "$instance_name" "create should echo back instance name"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")
}

function test_create_missing_blueprint() {
  log_test_step "Testing 'create' without blueprint argument fails"

  "$MODULE" create --install-dir "$TEST_INSTALL_DIR" 2>/dev/null
  assert_not_equals 0 "$?" "create without blueprint should fail"
}

function test_create_invalid_blueprint() {
  log_test_step "Testing 'create' with invalid blueprint fails"

  "$MODULE" create nonexistent_xyz_blueprint --install-dir "$TEST_INSTALL_DIR" 2>/dev/null
  assert_not_equals 0 "$?" "create with invalid blueprint should fail"
}

# =============================================================================
# TEST: info - Shows Instance Info
# =============================================================================

function test_info_instance() {
  log_test_step "Testing 'info' command shows instance configuration"

  local instance_name="test-info-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for info test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" info "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info should succeed"
  assert_not_null "$output" "info should produce output"
  assert_contains "$output" "name=" "info output should contain name key"
}

function test_info_json_instance() {
  log_test_step "Testing 'info --json' outputs valid JSON"

  local instance_name="test-info-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for info --json test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" info "$instance_name" --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info --json should succeed"
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "info --json output should be valid JSON"
}

function test_info_missing_instance() {
  log_test_step "Testing 'info' with missing instance argument fails"

  "$MODULE" info 2>/dev/null
  assert_not_equals 0 "$?" "info without instance should fail"
}

function test_info_invalid_instance() {
  log_test_step "Testing 'info' with nonexistent instance fails"

  "$MODULE" info totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "info with nonexistent instance should fail"
}

# =============================================================================
# TEST: find - Returns Instance Config Path
# =============================================================================

function test_find_instance() {
  log_test_step "Testing 'find' command returns instance config path"

  local instance_name="test-find-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for find test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" find "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "find should succeed"
  assert_not_null "$output" "find should return a path"
  assert_file_exists "$output" "find should return path to existing file"
}

function test_find_missing_instance_arg() {
  log_test_step "Testing 'find' without instance argument fails"

  "$MODULE" find 2>/dev/null
  assert_not_equals 0 "$?" "find without instance should fail"
}

function test_find_nonexistent_instance() {
  log_test_step "Testing 'find' with nonexistent instance fails"

  "$MODULE" find totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "find with nonexistent instance should fail"
}

# =============================================================================
# TEST: list - Lists Instances After Creation
# =============================================================================

function test_list_after_creation() {
  log_test_step "Testing 'list' shows created instance"

  local instance_name="test-list-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" list 2>&1)

  assert_contains "$output" "$instance_name" "list should include the created instance"
}

function test_list_json_after_creation() {
  log_test_step "Testing 'list --json' includes created instance"

  local instance_name="test-list-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" list --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list --json should succeed"
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "list --json output should be valid JSON"
  assert_contains "$output" "$instance_name" "list --json should include the created instance"
}

function test_list_filter_by_blueprint() {
  log_test_step "Testing 'list factorio' filters by blueprint"

  local instance_name="test-list-filter-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" list factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list factorio should succeed"
  assert_contains "$output" "$instance_name" "list factorio should include factorio instance"
}

# =============================================================================
# TEST: remove - Removes Instance
# =============================================================================

function test_remove_instance() {
  log_test_step "Testing 'remove' command removes instance"

  local instance_name="test_remove_instance"
  create_test_instance "factorio" "$instance_name" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for remove test"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" remove "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "remove should succeed"

  # Instance should no longer be findable
  "$MODULE" find "$instance_name" 2>/dev/null
  assert_not_equals 0 "$?" "find should fail after remove"
}

function test_remove_missing_instance_arg() {
  log_test_step "Testing 'remove' without instance argument fails"

  "$MODULE" remove 2>/dev/null
  assert_not_equals 0 "$?" "remove without instance should fail"
}

function test_remove_nonexistent_instance() {
  log_test_step "Testing 'remove' with nonexistent instance fails"

  "$MODULE" remove totally_nonexistent_instance_xyz 2>/dev/null
  assert_not_equals 0 "$?" "remove with nonexistent instance should fail"
}

# =============================================================================
# TEST: config-set / config-get
# =============================================================================

function test_config_set_get_roundtrip() {
  log_test_step "Testing config-set then config-get round-trips a simple value"

  local instance_name="test-cfg-roundtrip-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" config-set "$instance_name" "auto_update=true" 2>&1)
  assert_equals 0 "$?" "config-set should succeed"
  assert_contains "$output" "Set" "config-set should report success"

  output=$("$MODULE" config-get "$instance_name" "auto_update" 2>&1)
  assert_equals 0 "$?" "config-get should succeed"
  assert_equals "true" "$output" "config-get should return the value just set"
}

function test_config_set_complex_value_roundtrip() {
  log_test_step "Testing config-set preserves spaces, '=', and backslashes via the CLI"

  local instance_name="test-cfg-complex-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  # The whole key=value rides as a single argv element; the value contains
  # spaces, an embedded '=', and a backslash.
  local value='--start-server saves/my=world.zip --regex \d+'
  "$MODULE" config-set "$instance_name" "executable_arguments=$value" >/dev/null 2>&1
  assert_equals 0 "$?" "config-set should succeed with a complex value"

  local output
  output=$("$MODULE" config-get "$instance_name" "executable_arguments" 2>&1)
  assert_equals 0 "$?" "config-get should succeed"
  assert_equals "$value" "$output" \
    "Complex value must round-trip verbatim through the CLI"
}

function test_config_set_value_with_dashdash_flag() {
  log_test_step "Testing config-set value containing '--json' is not consumed as a flag"

  local instance_name="test-cfg-flagval-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local value='--json --verbose'
  "$MODULE" config-set "$instance_name" "executable_arguments=$value" >/dev/null 2>&1
  assert_equals 0 "$?" "config-set should succeed even when the value contains --json"

  local output
  output=$("$MODULE" config-get "$instance_name" "executable_arguments" 2>&1)
  assert_equals "$value" "$output" \
    "A value containing --json must not be stripped by global flag parsing"
}

function test_config_set_refuses_protected_key() {
  log_test_step "Testing config-set refuses an identity key and leaves it unchanged"

  local instance_name="test-cfg-protected-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  "$MODULE" config-set "$instance_name" "name=hacked" 2>/dev/null
  assert_not_equals 0 "$?" "config-set should refuse the identity key 'name'"

  local output
  output=$("$MODULE" config-get "$instance_name" "name" 2>&1)
  assert_equals "$instance_name" "$output" "'name' must be unchanged after refusal"
}

function test_config_set_toggle_key_hints_dedicated_flow() {
  log_test_step "Testing config-set refuses a toggle and points to the files flow"

  local instance_name="test-cfg-toggle-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  local output
  output=$("$MODULE" config-set "$instance_name" "enable_firewall_management=true" 2>&1)
  assert_not_equals 0 "$?" "config-set should refuse the integration toggle"
  assert_contains "$output" "files ufw" \
    "Refusal should point to the dedicated 'files ufw' flow"
}

function test_config_set_rejects_missing_assignment() {
  log_test_step "Testing config-set with a non-assignment argument fails"

  local instance_name="test-cfg-noassign-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")

  "$MODULE" config-set "$instance_name" "auto_update" 2>/dev/null
  assert_not_equals 0 "$?" "config-set without '=' should fail"
}

function test_config_set_missing_args() {
  log_test_step "Testing config-set with missing arguments fails"

  "$MODULE" config-set 2>/dev/null
  assert_not_equals 0 "$?" "config-set with no arguments should fail"
}

function test_config_get_missing_args() {
  log_test_step "Testing config-get with missing arguments fails"

  "$MODULE" config-get 2>/dev/null
  assert_not_equals 0 "$?" "config-get with no arguments should fail"
}

function test_config_get_unknown_instance() {
  log_test_step "Testing config-get on an unknown instance fails"

  "$MODULE" config-get totally_nonexistent_instance_xyz auto_update 2>/dev/null
  assert_not_equals 0 "$?" "config-get on a missing instance should fail"
}

function test_help_config_subcommands() {
  log_test_step "Testing help output covers config-get and config-set"

  local output
  output=$("$MODULE" help 2>&1)
  assert_contains "$output" "config-get" "main help should mention config-get"
  assert_contains "$output" "config-set" "main help should mention config-set"

  output=$("$MODULE" help config-set 2>&1)
  assert_equals 0 "$?" "help config-set should exit 0"
  assert_contains "$output" "config-set" "help config-set should describe the command"

  output=$("$MODULE" help config-get 2>&1)
  assert_equals 0 "$?" "help config-get should exit 0"
  assert_contains "$output" "config-get" "help config-get should describe the command"
}

