#!/usr/bin/env bash

# KGSM Container Blueprint Commands Unit Tests
#
# Test Type: UNIT
# Target: commands/blueprints.container.sh CLI interface

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprints_container_commands"
readonly MODULE="$KGSM_ROOT/commands/blueprints.container.sh"

# Standard test container blueprint (from testing_specification.md)
readonly TEST_BLUEPRINT_CONTAINER="vrising"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up container blueprint command tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "Container blueprint command module should exist"
  assert_file_executable "$MODULE" "Container blueprint command module should be executable"

  log_test_step "Container blueprint command test environment validated"
}

# =============================================================================
# help / usage TESTS
# =============================================================================

function test_help_no_args() {
  log_test_step "Testing: no arguments shows usage and exits non-zero"

  assert_command_fails "$MODULE" \
    "No arguments should fail"

  assert_command_output "$MODULE 2>&1 || true" "Usage" \
    "No arguments should show usage"
}

function test_help_flag() {
  log_test_step "Testing: --help flag"

  assert_command_succeeds "$MODULE --help" \
    "--help should succeed"

  assert_command_output "$MODULE --help" "Usage" \
    "--help output should contain Usage"
}

function test_help_command() {
  log_test_step "Testing: help command"

  assert_command_succeeds "$MODULE help" \
    "help command should succeed"

  assert_command_output "$MODULE help" "list" \
    "help output should mention list command"
}

function test_help_list_subcommand() {
  log_test_step "Testing: help list subcommand"

  assert_command_succeeds "$MODULE help list" \
    "help list should succeed"

  assert_command_output "$MODULE help list" "List Container Blueprints" \
    "help list output should contain List Container Blueprints"
}

function test_help_info_subcommand() {
  log_test_step "Testing: help info subcommand"

  assert_command_succeeds "$MODULE help info" \
    "help info should succeed"

  assert_command_output "$MODULE help info" "Container Blueprint Info" \
    "help info output should contain Container Blueprint Info"
}

function test_help_find_subcommand() {
  log_test_step "Testing: help find subcommand"

  assert_command_succeeds "$MODULE help find" \
    "help find should succeed"

  assert_command_output "$MODULE help find" "Find Container Blueprint" \
    "help find output should contain Find Container Blueprint"
}

function test_help_invalid_subcommand() {
  log_test_step "Testing: help with unknown subcommand fails"

  assert_command_fails "$MODULE help nonexistent_command_xyz" \
    "help with unknown subcommand should fail"
}

# =============================================================================
# list TESTS
# =============================================================================

function test_list_all() {
  log_test_step "Testing: list (all container blueprints)"

  assert_command_succeeds "$MODULE list" \
    "list should succeed"

  assert_command_output "$MODULE list" "vrising" \
    "list output should include vrising"
}

function test_list_default() {
  log_test_step "Testing: list default"

  assert_command_succeeds "$MODULE list default" \
    "list default should succeed"

  assert_command_output "$MODULE list default" "vrising" \
    "list default output should include vrising"
}

function test_list_custom() {
  log_test_step "Testing: list custom"

  assert_command_succeeds "$MODULE list custom" \
    "list custom should succeed (even if empty)"
}

function test_list_detailed() {
  log_test_step "Testing: list detailed"

  assert_command_succeeds "$MODULE list detailed" \
    "list detailed should succeed"

  assert_command_output "$MODULE list detailed" "vrising" \
    "list detailed output should include vrising"
}

function test_list_json() {
  log_test_step "Testing: list --json"

  assert_command_succeeds "$MODULE list --json" \
    "list --json should succeed"

  local output
  output=$("$MODULE" list --json 2>&1)
  assert_contains "$output" "vrising" \
    "list --json output should include vrising"
}

function test_list_default_json() {
  log_test_step "Testing: list default --json"

  assert_command_succeeds "$MODULE list default --json" \
    "list default --json should succeed"

  local output
  output=$("$MODULE" list default --json 2>&1)
  assert_contains "$output" "vrising" \
    "list default --json output should include vrising"
}

function test_list_custom_json() {
  log_test_step "Testing: list custom --json"

  assert_command_succeeds "$MODULE list custom --json" \
    "list custom --json should succeed"
}

function test_list_invalid_filter() {
  log_test_step "Testing: list with invalid filter fails"

  assert_command_fails "$MODULE list invalid_filter_xyz" \
    "list with invalid filter should fail"
}

function test_list_help() {
  log_test_step "Testing: list --help"

  assert_command_succeeds "$MODULE list --help" \
    "list --help should succeed"

  assert_command_output "$MODULE list --help" "List Container Blueprints" \
    "list --help output should contain List Container Blueprints"
}

# =============================================================================
# info TESTS
# =============================================================================

function test_info_container_blueprint() {
  log_test_step "Testing: info vrising (container blueprint)"

  assert_command_succeeds "$MODULE info $TEST_BLUEPRINT_CONTAINER" \
    "info vrising should succeed"

  assert_command_output "$MODULE info $TEST_BLUEPRINT_CONTAINER" "vrising" \
    "info vrising output should contain vrising"
}

function test_info_container_blueprint_json() {
  log_test_step "Testing: info vrising --json"

  assert_command_succeeds "$MODULE info $TEST_BLUEPRINT_CONTAINER --json" \
    "info vrising --json should succeed"

  local output
  output=$("$MODULE" info "$TEST_BLUEPRINT_CONTAINER" --json 2>&1)
  assert_contains "$output" "vrising" \
    "info vrising --json output should contain vrising"
}

function test_info_json_contains_blueprint_type() {
  log_test_step "Testing: info --json output contains BlueprintType: Container"

  local output
  output=$("$MODULE" info "$TEST_BLUEPRINT_CONTAINER" --json 2>&1)
  assert_contains "$output" "Container" \
    "info --json output should contain BlueprintType Container"
}

function test_info_missing_blueprint_arg() {
  log_test_step "Testing: info with no blueprint argument fails"

  assert_command_fails "$MODULE info" \
    "info with no argument should fail"
}

function test_info_invalid_blueprint() {
  log_test_step "Testing: info with non-existent blueprint fails"

  assert_command_fails "$MODULE info nonexistent_container_blueprint_xyz" \
    "info with non-existent container blueprint should fail"
}

function test_info_invalid_option() {
  log_test_step "Testing: info with invalid option fails"

  assert_command_fails "$MODULE info --invalid-option" \
    "info with invalid option should fail"
}

function test_info_help() {
  log_test_step "Testing: info --help"

  assert_command_succeeds "$MODULE info --help" \
    "info --help should succeed"

  assert_command_output "$MODULE info --help" "Container Blueprint Info" \
    "info --help output should contain Container Blueprint Info"
}

# =============================================================================
# find TESTS
# =============================================================================

function test_find_container_blueprint() {
  log_test_step "Testing: find vrising (container blueprint)"

  assert_command_succeeds "$MODULE find $TEST_BLUEPRINT_CONTAINER" \
    "find vrising should succeed"

  assert_command_output "$MODULE find $TEST_BLUEPRINT_CONTAINER" "vrising.docker-compose.yml" \
    "find vrising output should contain vrising.docker-compose.yml"
}

function test_find_path_is_valid_file() {
  log_test_step "Testing: find returns a valid existing file path"

  local path
  path=$("$MODULE" find "$TEST_BLUEPRINT_CONTAINER" 2>&1)

  assert_file_exists "$path" \
    "find should return a path to an existing file"
}

function test_find_path_contains_container_dir() {
  log_test_step "Testing: find returns path inside container blueprints directory"

  local path
  path=$("$MODULE" find "$TEST_BLUEPRINT_CONTAINER" 2>&1)

  assert_contains "$path" "container" \
    "find should return path inside container directory"
}

function test_find_missing_blueprint_arg() {
  log_test_step "Testing: find with no blueprint argument fails"

  assert_command_fails "$MODULE find" \
    "find with no argument should fail"
}

function test_find_invalid_blueprint() {
  log_test_step "Testing: find with non-existent blueprint fails"

  assert_command_fails "$MODULE find nonexistent_container_blueprint_xyz" \
    "find with non-existent container blueprint should fail"
}

function test_find_invalid_option() {
  log_test_step "Testing: find with invalid option fails"

  assert_command_fails "$MODULE find --invalid-option" \
    "find with invalid option should fail"
}

function test_find_help() {
  log_test_step "Testing: find --help"

  assert_command_succeeds "$MODULE find --help" \
    "find --help should succeed"

  assert_command_output "$MODULE find --help" "Find Container Blueprint" \
    "find --help output should contain Find Container Blueprint"
}

# =============================================================================
# additional container blueprints TESTS
# =============================================================================

function test_list_contains_all_default_container_blueprints() {
  log_test_step "Testing: list includes all expected default container blueprints"

  local output
  output=$("$MODULE" list 2>&1)

  assert_contains "$output" "abioticfactor" \
    "list output should include abioticfactor"

  assert_contains "$output" "enshrouded" \
    "list output should include enshrouded"
}

function test_find_another_container_blueprint() {
  log_test_step "Testing: find enshrouded (another container blueprint)"

  assert_command_succeeds "$MODULE find enshrouded" \
    "find enshrouded should succeed"

  assert_command_output "$MODULE find enshrouded" "enshrouded.docker-compose.yml" \
    "find enshrouded output should contain enshrouded.docker-compose.yml"
}

# =============================================================================
# unknown command TESTS
# =============================================================================

function test_unknown_command() {
  log_test_step "Testing: unknown command fails"

  assert_command_fails "$MODULE unknown_command_xyz" \
    "Unknown command should fail"
}

