#!/usr/bin/env bash

# KGSM Directory Commands Unit Tests
#
# Tests the CLI interface of commands/directories.sh, including:
# create, remove, ensure-created, link-instance, unlink-instance, help

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="directories_commands"
readonly MODULE="$KGSM_ROOT/commands/directories.sh"

# Blueprint used for all instance-related tests
readonly TEST_BLUEPRINT="factorio"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up directories command tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "directories command should exist"
  assert_file_executable "$MODULE" "directories command should be executable"

  log_test_step "Directories command test environment validated"
}

# =============================================================================
# help TESTS
# =============================================================================

function test_help_no_args_shows_usage() {
  log_test_step "Testing that help (no args) shows usage information"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help should exit 0"
  assert_contains "$output" "create" "help output should mention create"
  assert_contains "$output" "remove" "help output should mention remove"
  assert_contains "$output" "ensure-created" "help output should mention ensure-created"
}

function test_help_flag_shows_usage() {
  log_test_step "Testing that --help flag shows usage information"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "--help should exit 0"
  assert_contains "$output" "create" "--help output should mention create"
}

function test_help_create_subcommand() {
  log_test_step "Testing 'help create' subcommand"

  local output
  output=$("$MODULE" help create 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help create should exit 0"
  assert_contains "$output" "backups" "help create should describe directory structure"
}

function test_help_remove_subcommand() {
  log_test_step "Testing 'help remove' subcommand"

  local output
  output=$("$MODULE" help remove 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help remove should exit 0"
  assert_contains "$output" "Warning" "help remove should include warning about data loss"
}

function test_help_ensure_created_subcommand() {
  log_test_step "Testing 'help ensure-created' subcommand"

  local output
  output=$("$MODULE" help ensure-created 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "help ensure-created should exit 0"
  assert_contains "$output" "ensure-created" "help ensure-created should describe the command"
}

function test_help_unknown_command() {
  log_test_step "Testing 'help' with unknown subcommand returns error"

  assert_command_fails "$MODULE help unknownxyz" \
    "help with unknown command should fail"
}

# =============================================================================
# ensure-created TESTS
# =============================================================================

function test_ensure_created_creates_directory() {
  log_test_step "Testing 'ensure-created' creates a new directory"

  local test_dir="$KGSM_TEST_SANDBOX/ensure_created_test_$$"

  assert_dir_not_exists "$test_dir" "Directory should not exist before test"

  assert_command_succeeds "$MODULE ensure-created $test_dir" \
    "ensure-created should succeed"

  assert_dir_exists "$test_dir" "Directory should exist after ensure-created"

  rm -rf "$test_dir"
}

function test_ensure_created_idempotent() {
  log_test_step "Testing 'ensure-created' is idempotent"

  local test_dir="$KGSM_TEST_SANDBOX/ensure_created_idempotent_$$"

  "$MODULE" ensure-created "$test_dir"
  assert_command_succeeds "$MODULE ensure-created $test_dir" \
    "Second ensure-created call should succeed (idempotent)"

  assert_dir_exists "$test_dir" "Directory should still exist"

  rm -rf "$test_dir"
}

function test_ensure_created_missing_arg() {
  log_test_step "Testing 'ensure-created' without path argument returns error"

  assert_command_fails "$MODULE ensure-created" \
    "ensure-created without argument should fail"
}

function test_ensure_created_help_flag() {
  log_test_step "Testing 'ensure-created --help'"

  local output
  output=$("$MODULE" ensure-created --help 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "ensure-created --help should exit 0"
  assert_contains "$output" "ensure-created" "ensure-created help should describe command"
}

# =============================================================================
# create TESTS
# =============================================================================

function test_create_directories_success() {
  log_test_step "Testing 'create' creates directory structure for a valid instance"

  local instance_name
  instance_name=$(create_test_instance "$TEST_BLUEPRINT" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  assert_command_succeeds "$MODULE create $instance_name" \
    "create should succeed for a valid instance"

  # Retrieve working_dir from the instance config to verify directories
  local working_dir
  working_dir=$(__get_instance_config_value "$instance_name" "working_dir" 2>/dev/null)

  assert_dir_exists "$working_dir" "working_dir should exist after create"
  assert_dir_exists "$working_dir/install" "install dir should exist after create"
  assert_dir_exists "$working_dir/saves" "saves dir should exist after create"
  assert_dir_exists "$working_dir/temp" "temp dir should exist after create"
  assert_dir_exists "$working_dir/logs" "logs dir should exist after create"

  # Backups live outside working_dir so that uninstalling the instance (which
  # removes working_dir wholesale) leaves them intact.
  local backups_dir
  backups_dir=$(__get_instance_config_value "$instance_name" "backups_dir" 2>/dev/null)
  assert_dir_exists "$backups_dir" "backups dir should exist after create"
  assert_equals "${backups_dir#"$working_dir"}" "$backups_dir" \
    "backups dir must not live under working_dir"

  remove_test_instance "$TEST_BLUEPRINT" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_create_missing_instance_arg() {
  log_test_step "Testing 'create' without instance argument returns error"

  assert_command_fails "$MODULE create" \
    "create without instance name should fail"
}

function test_create_help_flag() {
  log_test_step "Testing 'create --help'"

  local output
  output=$("$MODULE" create --help 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "create --help should exit 0"
  assert_contains "$output" "working_dir" "create help should describe directory structure"
}

# =============================================================================
# remove TESTS
# =============================================================================

function test_remove_directories_success() {
  log_test_step "Testing 'remove' removes directory structure for a valid instance"

  local instance_name
  instance_name=$(create_test_instance "$TEST_BLUEPRINT" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Create directories first
  "$MODULE" create "$instance_name"

  local working_dir
  working_dir=$(__get_instance_config_value "$instance_name" "working_dir" 2>/dev/null)

  assert_dir_exists "$working_dir" "working_dir should exist before remove"

  assert_command_succeeds "$MODULE remove $instance_name" \
    "remove should succeed for a valid instance"

  assert_dir_not_exists "$working_dir" "working_dir should not exist after remove"

  remove_test_instance "$TEST_BLUEPRINT" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_remove_missing_instance_arg() {
  log_test_step "Testing 'remove' without instance argument returns error"

  assert_command_fails "$MODULE remove" \
    "remove without instance name should fail"
}

function test_remove_invalid_instance_name() {
  log_test_step "Testing 'remove' with invalid instance name returns error"

  assert_command_fails "$MODULE remove nonexistent_xyz_instance_$$" \
    "remove with invalid instance name should fail"
}

function test_remove_help_flag() {
  log_test_step "Testing 'remove --help'"

  local output
  output=$("$MODULE" remove --help 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "remove --help should exit 0"
  assert_contains "$output" "Warning" "remove help should include warning"
}

# =============================================================================
# link-instance / unlink-instance TESTS
# =============================================================================

function test_link_instance_success() {
  log_test_step "Testing 'link-instance' creates symlink"

  local instance_name
  instance_name="test-link-$$"
  local working_dir="$KGSM_TEST_SANDBOX/link_test_working_$$"

  mkdir -p "$working_dir"

  assert_command_succeeds "$MODULE link-instance $TEST_BLUEPRINT $instance_name $working_dir" \
    "link-instance should succeed"

  local symlink_path="$KGSM_INSTANCES_DIR/$TEST_BLUEPRINT/$instance_name"
  assert_command_succeeds "test -L '$symlink_path'" \
    "Symlink should exist after link-instance"

  # Cleanup
  rm -f "$symlink_path"
  rmdir "$KGSM_INSTANCES_DIR/$TEST_BLUEPRINT" 2>/dev/null || true
  rm -rf "$working_dir"
}

function test_link_instance_missing_blueprint() {
  log_test_step "Testing 'link-instance' without blueprint returns error"

  assert_command_fails "$MODULE link-instance" \
    "link-instance without blueprint should fail"
}

function test_link_instance_missing_instance() {
  log_test_step "Testing 'link-instance' without instance returns error"

  assert_command_fails "$MODULE link-instance $TEST_BLUEPRINT" \
    "link-instance without instance should fail"
}

function test_link_instance_missing_working_dir() {
  log_test_step "Testing 'link-instance' without working-dir returns error"

  assert_command_fails "$MODULE link-instance $TEST_BLUEPRINT testinstance" \
    "link-instance without working-dir should fail"
}

function test_unlink_instance_success() {
  log_test_step "Testing 'unlink-instance' removes symlink"

  local instance_name="test-unlink-$$"
  local working_dir="$KGSM_TEST_SANDBOX/unlink_test_working_$$"

  mkdir -p "$working_dir"
  "$MODULE" link-instance "$TEST_BLUEPRINT" "$instance_name" "$working_dir"

  local symlink_path="$KGSM_INSTANCES_DIR/$TEST_BLUEPRINT/$instance_name"
  assert_command_succeeds "test -L '$symlink_path'" \
    "Symlink should exist before unlink-instance"

  assert_command_succeeds "$MODULE unlink-instance $TEST_BLUEPRINT $instance_name" \
    "unlink-instance should succeed"

  assert_command_fails "test -L '$symlink_path'" \
    "Symlink should not exist after unlink-instance"

  # Cleanup
  rmdir "$KGSM_INSTANCES_DIR/$TEST_BLUEPRINT" 2>/dev/null || true
  rm -rf "$working_dir"
}

function test_unlink_instance_missing_blueprint() {
  log_test_step "Testing 'unlink-instance' without blueprint returns error"

  assert_command_fails "$MODULE unlink-instance" \
    "unlink-instance without blueprint should fail"
}

function test_unlink_instance_missing_instance() {
  log_test_step "Testing 'unlink-instance' without instance returns error"

  assert_command_fails "$MODULE unlink-instance $TEST_BLUEPRINT" \
    "unlink-instance without instance should fail"
}

# =============================================================================
# unknown command / no command TESTS
# =============================================================================

function test_no_command_returns_error() {
  log_test_step "Testing that no command returns error"

  assert_command_fails "$MODULE" \
    "directories command with no args should fail"
}

function test_unknown_command_returns_error() {
  log_test_step "Testing that unknown command returns error"

  assert_command_fails "$MODULE unknowncommand" \
    "directories command with unknown subcommand should fail"
}

