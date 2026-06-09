#!/usr/bin/env bash

# KGSM Install Commands Tests
#
# Test Type: UNIT
# Target: commands/install.sh - CLI interface and argument handling
#
# Tests the CLI interface of install.sh including help system,
# argument validation, and option parsing. Does NOT test actual
# installation (which would download game servers).

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="install_commands"
readonly MODULE="$KGSM_ROOT/commands/install.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up install commands tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "install.sh module should exist"
  assert_file_executable "$MODULE" "install.sh should be executable"

  log_test_step "Test environment validated"
}

# =============================================================================
# HELP SYSTEM TESTS
# =============================================================================

function test_help_flag() {
  log_test_step "Testing --help flag shows usage"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help should exit 0"
  assert_contains "$output" "blueprint" "Help should mention blueprint argument"
  assert_contains "$output" "--install-dir" "Help should mention --install-dir option"
  assert_contains "$output" "--version" "Help should mention --version option"
  assert_contains "$output" "--name" "Help should mention --name option"
}

function test_help_short_flag() {
  log_test_step "Testing -h flag shows usage"

  local output
  output=$("$MODULE" -h 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "-h should exit 0"
  assert_contains "$output" "blueprint" "Help should mention blueprint argument"
}

function test_help_command() {
  log_test_step "Testing 'help' command shows usage"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should exit 0"
  assert_contains "$output" "Install" "Help should describe the install module"
}

# =============================================================================
# MISSING ARGUMENT TESTS
# =============================================================================

function test_missing_blueprint_arg() {
  log_test_step "Testing that missing blueprint argument returns error"

  assert_command_fails "$MODULE" \
    "Running install.sh with no arguments should fail"

  local output
  output=$("$MODULE" 2>&1 || true)
  assert_contains "$output" "Missing required argument" \
    "Should show missing argument error when no blueprint provided"
}

function test_install_dir_missing_value() {
  log_test_step "Testing --install-dir flag with no value returns error"

  assert_command_fails "$MODULE factorio --install-dir" \
    "--install-dir without value should fail"

  local output
  output=$("$MODULE" factorio --install-dir 2>&1 || true)
  assert_contains "$output" "Missing argument" \
    "Should show missing argument error for --install-dir"
}

function test_version_missing_value() {
  log_test_step "Testing --version flag with no value returns error"

  assert_command_fails "$MODULE factorio --version" \
    "--version without value should fail"

  local output
  output=$("$MODULE" factorio --version 2>&1 || true)
  assert_contains "$output" "Missing argument" \
    "Should show missing argument error for --version"
}

function test_name_missing_value() {
  log_test_step "Testing --name flag with no value returns error"

  assert_command_fails "$MODULE factorio --name" \
    "--name without value should fail"

  local output
  output=$("$MODULE" factorio --name 2>&1 || true)
  assert_contains "$output" "Missing argument" \
    "Should show missing argument error for --name"
}

# =============================================================================
# INVALID OPTION TESTS
# =============================================================================

function test_invalid_option() {
  log_test_step "Testing that an unknown option returns error"

  assert_command_fails "$MODULE factorio --unknown-option-xyz" \
    "Unknown option should cause failure"

  local output
  output=$("$MODULE" factorio --unknown-option-xyz 2>&1 || true)
  assert_contains "$output" "Invalid argument" \
    "Should show invalid argument error for unknown option"
}

function test_invalid_option_before_blueprint() {
  log_test_step "Testing that --help before blueprint exits with 0"

  local output
  output=$("$MODULE" --help factorio 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help before blueprint should exit 0"
  assert_contains "$output" "blueprint" "Should show usage mentioning blueprint"
}

# =============================================================================
# MODULE STRUCTURE TESTS
# =============================================================================

function test_module_has_expected_options_in_help() {
  log_test_step "Testing help output contains all documented options"

  local output
  output=$("$MODULE" --help 2>&1)

  assert_contains "$output" "--install-dir" "Help should document --install-dir"
  assert_contains "$output" "--version" "Help should document --version"
  assert_contains "$output" "--name" "Help should document --name"
  assert_contains "$output" "-h" "Help should document -h short flag"
}

function test_module_shows_examples_in_help() {
  log_test_step "Testing help output contains usage examples"

  local output
  output=$("$MODULE" --help 2>&1)

  assert_contains "$output" "factorio" "Help examples should reference factorio blueprint"
}

