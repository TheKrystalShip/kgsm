#!/usr/bin/env bash

# KGSM Native Blueprint Commands Unit Tests
#
# Test Type: UNIT
# Target: commands/blueprints.native.sh CLI interface

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprints_native_commands"
readonly MODULE="$KGSM_ROOT/commands/blueprints.native.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up native blueprint command tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "Native blueprint command module should exist"
  assert_file_executable "$MODULE" "Native blueprint command module should be executable"

  log_test_step "Native blueprint command test environment validated"
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

  assert_command_output "$MODULE --help" "Native Blueprint" \
    "--help output should mention Native Blueprint"
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

  assert_command_output "$MODULE help list" "List Native" \
    "help list output should contain 'List Native'"
}

function test_help_info_subcommand() {
  log_test_step "Testing: help info subcommand"

  assert_command_succeeds "$MODULE help info" \
    "help info should succeed"

  assert_command_output "$MODULE help info" "Native Blueprint Info" \
    "help info output should contain 'Native Blueprint Info'"
}

function test_help_find_subcommand() {
  log_test_step "Testing: help find subcommand"

  assert_command_succeeds "$MODULE help find" \
    "help find should succeed"

  assert_command_output "$MODULE help find" "Find Native Blueprint" \
    "help find output should contain 'Find Native Blueprint'"
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
  log_test_step "Testing: list (all native blueprints)"

  assert_command_succeeds "$MODULE list" \
    "list should succeed"

  assert_command_output "$MODULE list" "factorio" \
    "list output should include factorio"

  assert_command_output "$MODULE list" "terraria" \
    "list output should include terraria"

  assert_command_output "$MODULE list" "necesse" \
    "list output should include necesse"
}

function test_list_default() {
  log_test_step "Testing: list default"

  assert_command_succeeds "$MODULE list default" \
    "list default should succeed"

  assert_command_output "$MODULE list default" "factorio" \
    "list default output should include factorio"

  assert_command_output "$MODULE list default" "terraria" \
    "list default output should include terraria"
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
}

function test_list_json() {
  log_test_step "Testing: list --json"

  assert_command_succeeds "$MODULE list --json" \
    "list --json should succeed"

  local output
  output=$("$MODULE" list --json 2>&1)
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

  assert_command_output "$MODULE list --help" "List Native" \
    "list --help output should contain 'List Native'"
}

function test_list_excludes_container_blueprints() {
  log_test_step "Testing: list only returns native blueprints (no container names)"

  local output
  output=$("$MODULE" list 2>&1)

  # vrising is container-only, should not appear in native list
  assert_not_contains "$output" "vrising" \
    "native list should not include container blueprint vrising"
}

# =============================================================================
# info TESTS
# =============================================================================

function test_info_factorio() {
  log_test_step "Testing: info factorio"

  assert_command_succeeds "$MODULE info factorio" \
    "info factorio should succeed"

  assert_command_output "$MODULE info factorio" "name=factorio" \
    "info factorio output should contain name=factorio"

  assert_command_output "$MODULE info factorio" "executable_file=" \
    "info factorio output should contain executable_file field"
}

function test_info_terraria() {
  log_test_step "Testing: info terraria"

  assert_command_succeeds "$MODULE info terraria" \
    "info terraria should succeed"

  assert_command_output "$MODULE info terraria" "terraria" \
    "info terraria output should contain terraria"
}

function test_info_necesse() {
  log_test_step "Testing: info necesse (Steam game without account requirement)"

  assert_command_succeeds "$MODULE info necesse" \
    "info necesse should succeed"

  assert_command_output "$MODULE info necesse" "necesse" \
    "info necesse output should contain necesse"
}

function test_info_starbound() {
  log_test_step "Testing: info starbound (Steam game with account requirement)"

  assert_command_succeeds "$MODULE info starbound" \
    "info starbound should succeed"

  assert_command_output "$MODULE info starbound" "starbound" \
    "info starbound output should contain starbound"
}

function test_info_json() {
  log_test_step "Testing: info factorio --json"

  assert_command_succeeds "$MODULE info factorio --json" \
    "info factorio --json should succeed"

  local output
  output=$("$MODULE" info factorio --json 2>&1)

  assert_contains "$output" "factorio" \
    "info factorio --json output should include factorio"

  assert_contains "$output" "Native" \
    "info factorio --json output should contain BlueprintType Native"
}

function test_info_json_valid_json() {
  log_test_step "Testing: info --json produces valid JSON"

  local output
  output=$("$MODULE" info factorio --json 2>&1)

  echo "$output" | jq . > /dev/null 2>&1
  assert_equals 0 $? \
    "info factorio --json should produce valid JSON"
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

  assert_command_fails "$MODULE info --invalid-option" \
    "info with invalid option should fail"
}

function test_info_help() {
  log_test_step "Testing: info --help"

  assert_command_succeeds "$MODULE info --help" \
    "info --help should succeed"

  assert_command_output "$MODULE info --help" "Native Blueprint Info" \
    "info --help output should contain 'Native Blueprint Info'"
}

# =============================================================================
# find TESTS
# =============================================================================

function test_find_factorio() {
  log_test_step "Testing: find factorio"

  assert_command_succeeds "$MODULE find factorio" \
    "find factorio should succeed"

  assert_command_output "$MODULE find factorio" "factorio.bp" \
    "find factorio output should contain factorio.bp"
}

function test_find_terraria() {
  log_test_step "Testing: find terraria"

  assert_command_succeeds "$MODULE find terraria" \
    "find terraria should succeed"

  assert_command_output "$MODULE find terraria" "terraria.bp" \
    "find terraria output should contain terraria.bp"
}

function test_find_path_is_valid_file() {
  log_test_step "Testing: find returns a valid file path"

  local path
  path=$("$MODULE" find factorio 2>&1)

  assert_file_exists "$path" \
    "find factorio should return a path to an existing file"
}

function test_find_necesse_path_is_file() {
  log_test_step "Testing: find necesse returns existing file"

  local path
  path=$("$MODULE" find necesse 2>&1)

  assert_file_exists "$path" \
    "find necesse should return a path to an existing file"
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

  assert_command_output "$MODULE find --help" "Find Native Blueprint" \
    "find --help output should contain 'Find Native Blueprint'"
}

# =============================================================================
# unknown command TESTS
# =============================================================================

function test_unknown_command() {
  log_test_step "Testing: unknown command fails"

  assert_command_fails "$MODULE unknown_command_xyz" \
    "Unknown command should fail"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting native blueprint commands tests"

  setup_test

  # help/usage tests
  test_help_no_args
  test_help_flag
  test_help_command
  test_help_list_subcommand
  test_help_info_subcommand
  test_help_find_subcommand
  test_help_invalid_subcommand

  # list tests
  test_list_all
  test_list_default
  test_list_custom
  test_list_detailed
  test_list_json
  test_list_default_json
  test_list_custom_json
  test_list_invalid_filter
  test_list_help
  test_list_excludes_container_blueprints

  # info tests
  test_info_factorio
  test_info_terraria
  test_info_necesse
  test_info_starbound
  test_info_json
  test_info_json_valid_json
  test_info_missing_blueprint_arg
  test_info_invalid_blueprint
  test_info_invalid_option
  test_info_help

  # find tests
  test_find_factorio
  test_find_terraria
  test_find_path_is_valid_file
  test_find_necesse_path_is_file
  test_find_missing_blueprint_arg
  test_find_invalid_blueprint
  test_find_invalid_option
  test_find_help

  # unknown command test
  test_unknown_command

  log_test_step "Native blueprint commands tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All native blueprint command tests passed"
  else
    fail_test "Some native blueprint command tests failed"
  fi
}

main "$@"
