#!/usr/bin/env bash

# KGSM Files Orchestrator Commands Tests
#
# Test Type: UNIT
# Target: commands/files.sh - CLI interface and component routing
#
# Tests the CLI interface of files.sh including help system,
# subcommand routing, argument validation, and create/remove
# operations with real test instances.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_commands"
readonly MODULE="$KGSM_ROOT/commands/files.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up files commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "files.sh module should exist"
  assert_file_executable "$MODULE" "files.sh should be executable"

  log_test_step "Test environment validated"
}

# =============================================================================
# HELP SYSTEM TESTS
# =============================================================================

function test_help_command() {
  log_test_step "Testing 'help' command shows usage"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should exit 0"
  assert_contains "$output" "create" "Help should mention create command"
  assert_contains "$output" "remove" "Help should mention remove command"
  assert_contains "$output" "management" "Help should mention management component"
}

function test_help_flag() {
  log_test_step "Testing --help flag shows usage"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help should exit 0"
  assert_contains "$output" "create" "Help should mention create command"
  assert_contains "$output" "remove" "Help should mention remove command"
}

function test_help_short_flag() {
  log_test_step "Testing -h flag shows usage"

  local output
  output=$("$MODULE" -h 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "-h flag should exit 0"
  assert_contains "$output" "File Management" "Help should describe file management"
}

function test_help_create_subcommand() {
  log_test_step "Testing 'help create' shows create-specific usage"

  local output
  output=$("$MODULE" help create 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help create should exit 0"
  assert_contains "$output" "Create" "Should show create command help"
  assert_contains "$output" "instance" "Should mention instance argument"
}

function test_help_remove_subcommand() {
  log_test_step "Testing 'help remove' shows remove-specific usage"

  local output
  output=$("$MODULE" help remove 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help remove should exit 0"
  assert_contains "$output" "Remove" "Should show remove command help"
  assert_contains "$output" "instance" "Should mention instance argument"
}

function test_help_unknown_subcommand() {
  log_test_step "Testing 'help' with unknown subcommand returns error"

  assert_command_fails "$MODULE help nonexistent_cmd_xyz" \
    "help for unknown command should fail"
}

# =============================================================================
# NO COMMAND / UNKNOWN COMMAND TESTS
# =============================================================================

function test_no_command_shows_usage() {
  log_test_step "Testing that no arguments shows usage and returns error"

  assert_command_fails "$MODULE" \
    "No arguments should return error"

  local output
  output=$("$MODULE" 2>&1 || true)
  assert_contains "$output" "create" "No-command output should mention create"
  assert_contains "$output" "remove" "No-command output should mention remove"
}

function test_unknown_command_returns_error() {
  log_test_step "Testing that unknown command returns error"

  assert_command_fails "$MODULE notacommand_xyz" \
    "Unknown command should fail"

  local output
  output=$("$MODULE" notacommand_xyz 2>&1 || true)
  assert_contains "$output" "Unknown command" "Should show unknown command error"
}

# =============================================================================
# CREATE SUBCOMMAND TESTS
# =============================================================================

function test_create_missing_instance() {
  log_test_step "Testing 'create' with no instance argument returns error"

  assert_command_fails "$MODULE create" \
    "create with no instance should fail"

  local output
  output=$("$MODULE" create 2>&1 || true)
  assert_contains "$output" "Missing required argument" \
    "Should show missing argument error"
}

function test_create_invalid_instance() {
  log_test_step "Testing 'create' with invalid instance name returns error"

  assert_command_fails "$MODULE create nonexistent_instance_xyz_12345" \
    "create with invalid instance should fail"

  local output
  output=$("$MODULE" create nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" \
    "Should show instance not found error"
}

function test_create_invalid_option() {
  log_test_step "Testing 'create' with invalid option flag returns error"

  assert_command_fails "$MODULE create --unknown-flag" \
    "create with unknown flag should fail"

  local output
  output=$("$MODULE" create --unknown-flag 2>&1 || true)
  assert_contains "$output" "Invalid option" \
    "Should show invalid option error"
}

# =============================================================================
# REMOVE SUBCOMMAND TESTS
# =============================================================================

function test_remove_missing_instance() {
  log_test_step "Testing 'remove' with no instance argument returns error"

  assert_command_fails "$MODULE remove" \
    "remove with no instance should fail"

  local output
  output=$("$MODULE" remove 2>&1 || true)
  assert_contains "$output" "Missing required argument" \
    "Should show missing argument error"
}

function test_remove_invalid_instance() {
  log_test_step "Testing 'remove' with invalid instance name returns error"

  assert_command_fails "$MODULE remove nonexistent_instance_xyz_12345" \
    "remove with invalid instance should fail"

  local output
  output=$("$MODULE" remove nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" \
    "Should show instance not found error"
}

function test_remove_invalid_option() {
  log_test_step "Testing 'remove' with invalid option flag returns error"

  assert_command_fails "$MODULE remove --unknown-flag" \
    "remove with unknown flag should fail"

  local output
  output=$("$MODULE" remove --unknown-flag 2>&1 || true)
  assert_contains "$output" "Invalid option" \
    "Should show invalid option error"
}

# =============================================================================
# COMPONENT ROUTING TESTS
# =============================================================================

function test_management_component_routes_to_submodule() {
  log_test_step "Testing 'management' routes to files.management.sh"

  # management with no args should show management help or error from submodule
  local output
  output=$("$MODULE" management 2>&1 || true)

  # Should produce output (not silent failure)
  assert_not_null "$output" "management component routing should produce output"
}

function test_firewall_component_routes_to_submodule() {
  log_test_step "Testing 'firewall' routes to files.firewall.sh"

  local output
  output=$("$MODULE" firewall 2>&1 || true)

  assert_not_null "$output" "firewall component routing should produce output"
}

function test_symlink_component_routes_to_submodule() {
  log_test_step "Testing 'symlink' routes to files.symlink.sh"

  local output
  output=$("$MODULE" symlink 2>&1 || true)

  assert_not_null "$output" "symlink component routing should produce output"
}

# =============================================================================
# CREATE/REMOVE WITH VALID INSTANCE
# =============================================================================

function test_create_with_valid_instance() {
  log_test_step "Testing 'create' succeeds with a valid test instance"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output
  output=$("$MODULE" create "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "create on valid instance should succeed"
  assert_contains "$output" "created successfully" \
    "Should show success message after creating files"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

# Regression: command shortcuts are a convenience, so a non-writable shortcuts
# directory must NOT abort instance creation and must NOT escalate to sudo — it
# warns and continues. This is the real upgrade path: existing configs keep
# command_shortcuts_directory=/usr/local/bin, which a non-root user cannot write,
# and KGSM no longer prompts for a password there.
function test_create_skips_shortcuts_when_dir_not_writable() {
  log_test_step "Testing 'create' warns and continues when shortcuts dir is not writable"

  if [[ "$EUID" -eq 0 ]]; then
    skip_test "Root bypasses directory write permissions" && return
  fi

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # A directory that exists but is not writable by this (non-root) user, and
  # lives outside $HOME so it is never auto-created.
  local ro_dir="$TEST_INSTALL_DIR/ro_shortcuts_$$"
  mkdir -p "$ro_dir"
  chmod 555 "$ro_dir"

  # Enable shortcuts pointing at the non-writable dir. The config loader takes
  # the LAST occurrence of a key, but the sandbox config can carry duplicate
  # keys (created during instance setup), so remove any existing entries and
  # append a single clean value the `files create` subprocess will read.
  local orig_dir
  orig_dir=$(grep -m1 '^command_shortcuts_directory=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- || echo "")
  sed -i '/^enable_command_shortcuts=/d; /^command_shortcuts_directory=/d' "$CONFIG_FILE"
  printf 'enable_command_shortcuts=true\ncommand_shortcuts_directory=%s\n' "$ro_dir" >> "$CONFIG_FILE"

  # KGSM exports its loaded config into config_* vars and propagates them to
  # child processes via KGSM_CONFIG_LOADED=1 (children reuse them instead of
  # re-reading the file). The create gate reads $config_enable_command_shortcuts,
  # while the symlink handler reads command_shortcuts_directory from the file
  # itself — so enable the gate via the propagated var and the dir via the file.
  local output exit_code
  output=$(KGSM_CONFIG_LOADED=1 config_enable_command_shortcuts=true \
    "$MODULE" create "$instance_name" 2>&1)
  exit_code=$?

  # Restore a clean, single-entry shortcuts config so later tests are unaffected
  sed -i '/^enable_command_shortcuts=/d; /^command_shortcuts_directory=/d' "$CONFIG_FILE"
  printf 'enable_command_shortcuts=false\ncommand_shortcuts_directory=%s\n' "${orig_dir:-\$HOME/.local/bin}" >> "$CONFIG_FILE"
  chmod 755 "$ro_dir" 2>/dev/null || true

  assert_equals 0 "$exit_code" \
    "create should still succeed (exit 0) when shortcuts dir is not writable"
  assert_contains "$output" "created successfully" \
    "Instance creation should complete despite unusable shortcuts dir"
  assert_contains "$output" "skipping shortcuts" \
    "Should warn that command shortcuts were skipped"

  local created="false"
  [[ -e "$ro_dir/$instance_name" ]] && created="true"
  assert_false "$created" \
    "No shortcut symlink should be created in the non-writable directory (no sudo)"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
  rm -rf "$ro_dir" 2>/dev/null || true
}

function test_remove_with_valid_instance() {
  log_test_step "Testing 'remove' succeeds with a valid test instance"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # First create files so remove has something to work with
  "$MODULE" create "$instance_name" 2>/dev/null || true

  local output
  output=$("$MODULE" remove "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "remove on valid instance should succeed"
  assert_contains "$output" "removed successfully" \
    "Should show success message after removing files"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_create_then_remove_cycle() {
  log_test_step "Testing create followed by remove produces clean state"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)

  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Create
  "$MODULE" create "$instance_name" 2>/dev/null
  local create_exit=$?
  assert_equals 0 "$create_exit" "create should succeed"

  # Remove
  "$MODULE" remove "$instance_name" 2>/dev/null
  local remove_exit=$?
  assert_equals 0 "$remove_exit" "remove should succeed after create"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

