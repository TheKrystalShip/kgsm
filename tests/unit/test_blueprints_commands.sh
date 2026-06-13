#!/usr/bin/env bash

# KGSM Blueprint Commands Unit Tests
#
# Test Type: UNIT
# Target: commands/blueprints.sh CLI interface

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprints_commands"
readonly MODULE="$KGSM_ROOT/commands/blueprints.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up blueprint command tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "Blueprint command module should exist"
  assert_file_executable "$MODULE" "Blueprint command module should be executable"

  log_test_step "Blueprint command test environment validated"
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

  assert_command_output "$MODULE help list" "List Blueprints" \
    "help list output should contain List Blueprints"
}

function test_help_info_subcommand() {
  log_test_step "Testing: help info subcommand"

  assert_command_succeeds "$MODULE help info" \
    "help info should succeed"

  assert_command_output "$MODULE help info" "Blueprint Info" \
    "help info output should contain Blueprint Info"
}

function test_help_find_subcommand() {
  log_test_step "Testing: help find subcommand"

  assert_command_succeeds "$MODULE help find" \
    "help find should succeed"

  assert_command_output "$MODULE help find" "Find Blueprint" \
    "help find output should contain Find Blueprint"
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
  log_test_step "Testing: list (all blueprints)"

  assert_command_succeeds "$MODULE list" \
    "list should succeed"

  assert_command_output "$MODULE list" "factorio" \
    "list output should include factorio"

  assert_command_output "$MODULE list" "terraria" \
    "list output should include terraria"

  assert_command_output "$MODULE list" "vrising" \
    "list output should include vrising"
}

function test_list_default() {
  log_test_step "Testing: list default"

  assert_command_succeeds "$MODULE list default" \
    "list default should succeed"

  assert_command_output "$MODULE list default" "factorio" \
    "list default output should include factorio"
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

  # Regression: the detailed loop must not discard entries. The info handler
  # returns a 200-range success-with-event code, so a naive `|| continue`
  # treated every blueprint as a failure and produced empty output.
  assert_command_output "$MODULE list detailed" "factorio" \
    "list detailed should include factorio"

  assert_command_output "$MODULE list detailed" "Native" \
    "list detailed should include the runtime column"
}

function test_list_detailed_json() {
  log_test_step "Testing: list detailed --json"

  assert_command_succeeds "$MODULE list detailed --json" \
    "list detailed --json should succeed"

  local output
  output=$("$MODULE" list detailed --json 2>&1)
  # Regression: must be a populated object keyed by blueprint name, not "{}".
  assert_contains "$output" "factorio" \
    "list detailed --json should include factorio"

  assert_contains "$output" "BlueprintType" \
    "list detailed --json entries should carry full info objects"
}

function test_list_json() {
  log_test_step "Testing: list --json"

  assert_command_succeeds "$MODULE list --json" \
    "list --json should succeed"

  local output
  output=$("$MODULE" list --json 2>&1)
  # JSON output should start with [ or {
  assert_contains "$output" "factorio" \
    "list --json output should include factorio"
}

function test_list_default_json() {
  log_test_step "Testing: list default --json"

  assert_command_succeeds "$MODULE list default --json" \
    "list default --json should succeed"
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

  assert_command_output "$MODULE list --help" "List Blueprints" \
    "list --help output should contain List Blueprints"
}

# =============================================================================
# info TESTS
# =============================================================================

function test_info_native_blueprint() {
  log_test_step "Testing: info factorio (native blueprint)"

  assert_command_succeeds "$MODULE info factorio" \
    "info factorio should succeed"

  assert_command_output "$MODULE info factorio" "name: factorio" \
    "info factorio output should contain name: factorio"

  assert_command_output "$MODULE info factorio" "executable_file:" \
    "info factorio output should contain executable_file"
}

function test_info_container_blueprint() {
  log_test_step "Testing: info vrising (container blueprint)"

  assert_command_succeeds "$MODULE info vrising" \
    "info vrising should succeed"

  assert_command_output "$MODULE info vrising" "vrising" \
    "info vrising output should contain vrising"
}

function test_info_json() {
  log_test_step "Testing: info factorio --json"

  assert_command_succeeds "$MODULE info factorio --json" \
    "info factorio --json should succeed"

  assert_command_output "$MODULE info factorio --json" "factorio" \
    "info factorio --json output should include factorio"
}

function test_info_missing_blueprint_arg() {
  log_test_step "Testing: info with no blueprint argument fails"

  assert_command_fails "$MODULE info" \
    "info with no argument should fail"
}

function test_info_invalid_blueprint() {
  log_test_step "Testing: info with non-existent blueprint fails"

  assert_command_fails "$MODULE info nonexistent_blueprint_xyz" \
    "info with non-existent blueprint should fail"
}

function test_info_invalid_option() {
  log_test_step "Testing: info with invalid option fails"

  assert_command_fails "$MODULE info --invalid-option factorio" \
    "info with invalid option should fail"
}

function test_info_help() {
  log_test_step "Testing: info --help"

  assert_command_succeeds "$MODULE info --help" \
    "info --help should succeed"

  assert_command_output "$MODULE info --help" "Blueprint Info" \
    "info --help output should contain Blueprint Info"
}

# =============================================================================
# find TESTS
# =============================================================================

function test_find_native_blueprint() {
  log_test_step "Testing: find factorio (native blueprint)"

  assert_command_succeeds "$MODULE find factorio" \
    "find factorio should succeed"

  assert_command_output "$MODULE find factorio" "factorio.bp.yaml" \
    "find factorio output should contain factorio.bp.yaml"
}

function test_find_container_blueprint() {
  log_test_step "Testing: find vrising (container blueprint)"

  assert_command_succeeds "$MODULE find vrising" \
    "find vrising should succeed"

  assert_command_output "$MODULE find vrising" "vrising.bp.yaml" \
    "find vrising output should contain vrising.bp.yaml"
}

function test_find_path_is_valid_file() {
  log_test_step "Testing: find returns a valid file path"

  local path
  path=$("$MODULE" find terraria 2>&1)

  assert_file_exists "$path" \
    "find should return a path to an existing file"
}

function test_find_missing_blueprint_arg() {
  log_test_step "Testing: find with no blueprint argument fails"

  assert_command_fails "$MODULE find" \
    "find with no argument should fail"
}

function test_find_invalid_blueprint() {
  log_test_step "Testing: find with non-existent blueprint fails"

  assert_command_fails "$MODULE find nonexistent_blueprint_xyz" \
    "find with non-existent blueprint should fail"
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

  assert_command_output "$MODULE find --help" "Find Blueprint" \
    "find --help output should contain Find Blueprint"
}

# =============================================================================
# unknown command TESTS
# =============================================================================

function test_unknown_command() {
  log_test_step "Testing: unknown command fails"

  assert_command_fails "$MODULE unknown_command_xyz" \
    "Unknown command should fail"
}

