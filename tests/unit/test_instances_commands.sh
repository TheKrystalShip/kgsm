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

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up instances commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "instances.sh command should exist"
  assert_file_executable "$MODULE" "instances.sh command should be executable"

  log_test_step "Test environment validated"
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

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
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

  local output
  output=$("$MODULE" info "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info should succeed"
  assert_not_null "$output" "info should produce output"
  assert_contains "$output" "instance_name" "info output should contain instance_name key"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_info_json_instance() {
  log_test_step "Testing 'info --json' outputs valid JSON"

  local instance_name="test-info-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for info --json test"

  local output
  output=$("$MODULE" info "$instance_name" --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info --json should succeed"
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "info --json output should be valid JSON"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
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

  local output
  output=$("$MODULE" find "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "find should succeed"
  assert_not_null "$output" "find should return a path"
  assert_file_exists "$output" "find should return path to existing file"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
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

  local output
  output=$("$MODULE" list 2>&1)

  assert_contains "$output" "$instance_name" "list should include the created instance"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_list_json_after_creation() {
  log_test_step "Testing 'list --json' includes created instance"

  local instance_name="test-list-json-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"

  local output
  output=$("$MODULE" list --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list --json should succeed"
  echo "$output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "list --json output should be valid JSON"
  assert_contains "$output" "$instance_name" "list --json should include the created instance"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_list_filter_by_blueprint() {
  log_test_step "Testing 'list factorio' filters by blueprint"

  local instance_name="test-list-filter-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created"

  local output
  output=$("$MODULE" list factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "list factorio should succeed"
  assert_contains "$output" "$instance_name" "list factorio should include factorio instance"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST: remove - Removes Instance
# =============================================================================

function test_remove_instance() {
  log_test_step "Testing 'remove' command removes instance"

  local instance_name="test-remove-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for remove test"

  local output
  output=$("$MODULE" remove "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "remove should succeed"

  # Instance should no longer be findable
  "$MODULE" find "$instance_name" 2>/dev/null
  assert_not_equals 0 "$?" "find should fail after remove"

  # Cleanup remaining directory structures
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
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
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting instances commands tests"

  setup_test

  # Help tests
  test_help_command
  test_help_subcommands
  test_no_args_shows_usage

  # List (empty) tests
  test_list_empty
  test_list_json_empty

  # generate-id tests
  test_generate_id_valid_blueprint
  test_generate_id_with_bp_extension
  test_generate_id_missing_blueprint
  test_generate_id_invalid_blueprint

  # create tests
  test_create_instance
  test_create_missing_blueprint
  test_create_invalid_blueprint

  # info tests
  test_info_instance
  test_info_json_instance
  test_info_missing_instance
  test_info_invalid_instance

  # find tests
  test_find_instance
  test_find_missing_instance_arg
  test_find_nonexistent_instance

  # list after creation tests
  test_list_after_creation
  test_list_json_after_creation
  test_list_filter_by_blueprint

  # remove tests
  test_remove_instance
  test_remove_missing_instance_arg
  test_remove_nonexistent_instance

  log_test_step "Instances commands tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All instances commands tests completed successfully"
  else
    fail_test "Some instances commands tests failed"
  fi
}

main "$@"
