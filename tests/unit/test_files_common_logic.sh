#!/usr/bin/env bash

# KGSM File Management Common Logic Handler Unit Tests
#
# Tests all __logic_* functions from commands/handlers/files.common.sh
# Uses real factorio.bp blueprint and factorio.overrides.sh from the sandbox
# to ensure realistic testing conditions.

# =============================================================================
# TEST SETUP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Framework common functions
source "$SCRIPT_DIR/../framework/common.sh"

# KGSM bootstrapper
source "$KGSM_ROOT/core/bootstrap.sh"

# Test variables
readonly TEST_NAME="files_common_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.common.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up files.common logic tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Files.common handler should exist"

  # Source the handler
  source "$HANDLER"

  # Verify required error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_INSTANCE" "EC_INVALID_INSTANCE should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FAILED_SOURCE" "EC_FAILED_SOURCE should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"

  # Verify logic functions are exported
  assert_function_exists "__logic_inject_overrides" "__logic_inject_overrides should be exported"
  assert_function_exists "__logic_set_file_ownership" "__logic_set_file_ownership should be exported"

  # Verify module loaded guard
  assert_not_null "$KGSM_LOGIC_FILES_COMMON_LOADED" "Module should be loaded"

  # Verify real factorio blueprint exists
  assert_file_exists "$KGSM_ROOT/blueprints/native/default/factorio.bp" "Factorio blueprint should exist"

  # Verify real factorio overrides exist
  assert_file_exists "$KGSM_ROOT/overrides/factorio.overrides.sh" "Factorio overrides should exist"

  log_test "Files.common logic test environment validated"
}

# =============================================================================
# __logic_inject_overrides() TESTS
# =============================================================================

function test_inject_overrides_success_single_function() {
  log_step "Testing __logic_inject_overrides with single function"

  # Use real factorio blueprint
  local blueprint_file="$KGSM_ROOT/blueprints/native/default/factorio.bp"
  local instance_name="test-factorio-inject-$$"

  # Create mock instance config
  local instance_config
  instance_config=$(create_mock_instance_config "$instance_name" "$blueprint_file")

  # Create mock management script with placeholder function
  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  create_mock_management_script "$mgmt_script" "_get_latest_version"

  # Create simple override file with one function
  local override_file
  override_file=$(create_mock_override_file "factorio" "_get_latest_version")

  # Inject overrides
  __logic_inject_overrides "$instance_name" "$mgmt_script"
  local exit_code=$?

  assert_equals "$EC_OKAY" "$exit_code" "Should return success"
  assert_file_exists "$mgmt_script" "Management script should still exist"

  # Verify the function was injected (check for mock implementation)
  assert_command_succeeds "grep -q 'Mock _get_latest_version implementation' '$mgmt_script'"

  # Verify placeholder was removed
  assert_command_fails "grep -q 'Placeholder _get_latest_version' '$mgmt_script'"

  # Cleanup
  cleanup_mock_files "$instance_config" "$mgmt_script" "$override_file"
  rm -rf "$(dirname "$instance_config")"
}

function test_inject_overrides_success_multiple_functions() {
  log_step "Testing __logic_inject_overrides with multiple functions"

  local blueprint_file="$KGSM_ROOT/blueprints/native/default/factorio.bp"
  local instance_name="test-factorio-multi-$$"

  local instance_config
  instance_config=$(create_mock_instance_config "$instance_name" "$blueprint_file")

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  create_mock_management_script "$mgmt_script" "_get_latest_version" "_download" "_deploy"

  local override_file
  override_file=$(create_mock_override_file "factorio" "_get_latest_version" "_download" "_deploy")

  __logic_inject_overrides "$instance_name" "$mgmt_script"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should return success"

  # Verify all functions were injected
  assert_file_contains "$mgmt_script" "Mock _get_latest_version implementation" "Should contain _get_latest_version"
  assert_file_contains "$mgmt_script" "Mock _download implementation" "Should contain _download"
  assert_file_contains "$mgmt_script" "Mock _deploy implementation" "Should contain _deploy"

  # Verify no placeholders remain
  assert_command_fails "grep -q 'Placeholder _get_latest_version' '$mgmt_script'"

  cleanup_mock_files "$instance_config" "$mgmt_script" "$override_file"
  rm -rf "$(dirname "$instance_config")"
}

function test_inject_overrides_no_override_file() {
  log_step "Testing __logic_inject_overrides with non-existent override file (valid case)"

  # Create a mock blueprint with a name that has no override file
  local blueprint_file
  blueprint_file=$(create_mock_blueprint "nooverrides-$$" "native")

  local instance_name="test-nooverrides-$$"

  local instance_config
  instance_config=$(create_mock_instance_config "$instance_name" "$blueprint_file")

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  create_mock_management_script "$mgmt_script" "_get_latest_version"

  # Call inject_overrides - should return 0 even with no override file
  __logic_inject_overrides "$instance_name" "$mgmt_script"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should return success when no override file exists"
  assert_file_exists "$mgmt_script" "Management script should still exist"

  # Verify placeholder remains unchanged
  assert_file_contains "$mgmt_script" "Placeholder _get_latest_version" "Placeholder should remain"

  cleanup_mock_files "$instance_config" "$mgmt_script" "$blueprint_file"
  rm -rf "$(dirname "$instance_config")" "$(dirname "$blueprint_file")"
}

function test_inject_overrides_empty_instance_name() {
  log_step "Testing __logic_inject_overrides with empty instance_name"

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_empty_$$.sh"
  touch "$mgmt_script"

  __logic_inject_overrides "" "$mgmt_script" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"

  cleanup_mock_files "$mgmt_script"
}

function test_inject_overrides_empty_management_file() {
  log_step "Testing __logic_inject_overrides with empty management_file"

  __logic_inject_overrides "test-instance-$$" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
}

function test_inject_overrides_management_file_not_found() {
  log_step "Testing __logic_inject_overrides with non-existent management file"

  local mgmt_script="$KGSM_TEST_SANDBOX/nonexistent_$$.sh"

  __logic_inject_overrides "test-instance-$$" "$mgmt_script" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_FILE_NOT_FOUND" "Should return EC_FILE_NOT_FOUND"
}

function test_inject_overrides_instance_config_not_found() {
  log_step "Testing __logic_inject_overrides with non-existent instance config"

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_noconfig_$$.sh"
  touch "$mgmt_script"

  # Use an instance name that doesn't have a config
  __logic_inject_overrides "nonexistent-instance-$$" "$mgmt_script" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_INSTANCE" "Should return EC_INVALID_INSTANCE"

  cleanup_mock_files "$mgmt_script"
}

function test_inject_overrides_blueprint_file_missing_from_config() {
  log_step "Testing __logic_inject_overrides with blueprint_file missing from config"

  local instance_name="test-nobpfile-$$"
  local instance_dir="$KGSM_ROOT/instances/testgame"
  mkdir -p "$instance_dir"

  local instance_config="$instance_dir/${instance_name}.ini"

  # Create config without blueprint_file field
  cat > "$instance_config" << EOF
name=$instance_name
type=native
EOF

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  touch "$mgmt_script"

  __logic_inject_overrides "$instance_name" "$mgmt_script" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_CONFIG" "Should return EC_INVALID_CONFIG"

  cleanup_mock_files "$instance_config" "$mgmt_script"
  rm -rf "$instance_dir"
}

function test_inject_overrides_blueprint_name_missing() {
  log_step "Testing __logic_inject_overrides with blueprint name field missing"

  local instance_name="test-noname-$$"
  local blueprint_file="$KGSM_ROOT/blueprints/native/custom/noname-$$.bp"

  mkdir -p "$(dirname "$blueprint_file")"

  # Create blueprint without name field
  cat > "$blueprint_file" << EOF
# Mock blueprint without name field
ports='27015'
executable_file=test.sh
EOF

  local instance_dir="$KGSM_ROOT/instances/testgame"
  mkdir -p "$instance_dir"

  local instance_config="$instance_dir/${instance_name}.ini"
  cat > "$instance_config" << EOF
name=$instance_name
blueprint_file=$blueprint_file
type=native
EOF

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  touch "$mgmt_script"

  __logic_inject_overrides "$instance_name" "$mgmt_script" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_CONFIG" "Should return EC_INVALID_CONFIG"

  cleanup_mock_files "$instance_config" "$mgmt_script" "$blueprint_file"
  rm -rf "$instance_dir" "$(dirname "$blueprint_file")"
}

function test_inject_overrides_malformed_override_file() {
  log_step "Testing __logic_inject_overrides with malformed override file"

  local blueprint_file="$KGSM_ROOT/blueprints/native/default/factorio.bp"
  local instance_name="test-malformed-$$"

  local instance_config
  instance_config=$(create_mock_instance_config "$instance_name" "$blueprint_file")

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  create_mock_management_script "$mgmt_script" "_get_latest_version"

  # Create malformed override file (syntax error)
  local override_file="$OVERRIDES_SOURCE_DIR/factorio.overrides.sh"
  local override_backup="${override_file}.backup.$$"

  # Backup real override file
  cp "$override_file" "$override_backup"

  # Create malformed override
  cat > "$override_file" << 'EOF'
#!/usr/bin/env bash
function _get_latest_version() {
  echo "Missing closing brace"
EOF

  __logic_inject_overrides "$instance_name" "$mgmt_script" 2>/dev/null
  local exit_code=$?

  # Restore original override file
  mv "$override_backup" "$override_file"

  assert_equals "$exit_code" "$EC_FAILED_SOURCE" "Should return EC_FAILED_SOURCE for malformed override"

  cleanup_mock_files "$instance_config" "$mgmt_script"
  rm -rf "$(dirname "$instance_config")"
}

function test_inject_overrides_readonly_management_file() {
  log_step "Testing __logic_inject_overrides with read-only management file"

  local blueprint_file="$KGSM_ROOT/blueprints/native/default/factorio.bp"
  local instance_name="test-readonly-$$"

  local instance_config
  instance_config=$(create_mock_instance_config "$instance_name" "$blueprint_file")

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  create_mock_management_script "$mgmt_script" "_get_latest_version"

  local override_file
  override_file=$(create_mock_override_file "factorio" "_get_latest_version")

  # Make parent directory read-only instead of the file itself
  # This prevents sed from creating temporary files
  local parent_dir
  parent_dir="$(dirname "$mgmt_script")"
  chmod 555 "$parent_dir"

  __logic_inject_overrides "$instance_name" "$mgmt_script" 2>/dev/null
  local exit_code=$?

  # Restore permissions for cleanup
  chmod 755 "$parent_dir"

  # sed -i should fail when it can't create temp files in read-only directory
  # However, the exact behavior may vary, so we accept either permission error
  # or the operation silently failing (exit code 0 but no changes)
  if [[ "$exit_code" -eq 0 ]]; then
    log_test "Operation returned 0, checking if injection actually occurred"
    # Verify injection didn't actually happen
    assert_command_succeeds "grep -q 'Placeholder _get_latest_version' '$mgmt_script'" "Placeholder should remain since injection failed"
    assert_command_fails "grep -q 'Mock _get_latest_version implementation' '$mgmt_script'" "Function should not be injected despite read-only directory"
  else
    log_test "Function was not injected as expected (sed failed silently)"
  fi

  cleanup_mock_files "$instance_config" "$mgmt_script" "$override_file"
  rm -rf "$(dirname "$instance_config")"
}

function test_inject_overrides_idempotency() {
  log_step "Testing __logic_inject_overrides idempotency (inject twice)"

  local blueprint_file="$KGSM_ROOT/blueprints/native/default/factorio.bp"
  local instance_name="test-idempotent-$$"

  local instance_config
  instance_config=$(create_mock_instance_config "$instance_name" "$blueprint_file")

  local mgmt_script="$KGSM_TEST_SANDBOX/manage_${instance_name}.sh"
  create_mock_management_script "$mgmt_script" "_get_latest_version"

  local override_file
  override_file=$(create_mock_override_file "factorio" "_get_latest_version")

  # First injection
  __logic_inject_overrides "$instance_name" "$mgmt_script"
  local exit_code1=$?

  # Second injection (should also succeed)
  __logic_inject_overrides "$instance_name" "$mgmt_script"
  local exit_code2=$?

  assert_equals "$exit_code1" "0" "First injection should succeed"
  assert_equals "$exit_code2" "0" "Second injection should succeed"

  # Verify function is still present
  assert_file_contains "$mgmt_script" "Mock _get_latest_version implementation" "Function should still be injected"

  # Count occurrences - should only appear once
  local count
  count=$(grep -c "Mock _get_latest_version implementation" "$mgmt_script")
  assert_equals "$count" "1" "Function should appear exactly once"

  cleanup_mock_files "$instance_config" "$mgmt_script" "$override_file"
  rm -rf "$(dirname "$instance_config")"
}

# =============================================================================
# __logic_set_file_ownership() TESTS
# =============================================================================

function test_set_file_ownership_success() {
  log_step "Testing __logic_set_file_ownership with valid file"

  local test_file="$KGSM_TEST_SANDBOX/test_ownership_$$.txt"
  touch "$test_file"

  __logic_set_file_ownership "$test_file"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should return success"

  # Verify ownership
  local owner
  owner=$(stat -c "%U" "$test_file")
  assert_equals "$owner" "$USER" "Owner should be current user"

  cleanup_mock_files "$test_file"
}

function test_set_file_ownership_empty_path() {
  log_step "Testing __logic_set_file_ownership with empty file_path"

  __logic_set_file_ownership "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
}

function test_set_file_ownership_file_not_found() {
  log_step "Testing __logic_set_file_ownership with non-existent file"

  local test_file="$KGSM_TEST_SANDBOX/nonexistent_$$.txt"

  __logic_set_file_ownership "$test_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_FILE_NOT_FOUND" "Should return EC_FILE_NOT_FOUND"
}

function test_set_file_ownership_symlink() {
  log_step "Testing __logic_set_file_ownership with symlink"

  local real_file="$KGSM_TEST_SANDBOX/real_file_$$.txt"
  local symlink="$KGSM_TEST_SANDBOX/symlink_$$.txt"

  touch "$real_file"
  ln -s "$real_file" "$symlink"

  __logic_set_file_ownership "$symlink"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should return success for symlink"

  # Verify ownership of the symlink itself
  local owner
  owner=$(stat -c "%U" "$symlink")
  assert_equals "$owner" "$USER" "Symlink owner should be current user"

  cleanup_mock_files "$real_file" "$symlink"
}

function test_set_file_ownership_permission_denied() {
  log_step "Testing __logic_set_file_ownership with permission denied"

  # Create a directory with restricted permissions
  local test_dir="$KGSM_TEST_SANDBOX/restricted_dir_$$"
  mkdir -p "$test_dir"

  local test_file="$test_dir/file.txt"
  touch "$test_file"

  # Make directory read-only (prevents changing file ownership if not owner)
  chmod 555 "$test_dir"

  # Try to change ownership (this may or may not fail depending on filesystem)
  # We're testing that the function handles chown errors gracefully
  __logic_set_file_ownership "$test_file" 2>/dev/null
  local exit_code=$?

  # Restore permissions for cleanup
  chmod 755 "$test_dir"

  # The exact behavior depends on the system, but it should not crash
  # It either succeeds (0) or returns permission error
  if [[ "$exit_code" -ne 0 ]]; then
    assert_equals "$exit_code" "$EC_PERMISSION" "Should return EC_PERMISSION on failure"
  fi

  cleanup_mock_files "$test_dir"
}

function test_set_file_ownership_regular_user_context() {
  log_step "Testing __logic_set_file_ownership in regular user context"

  local test_file="$KGSM_TEST_SANDBOX/test_user_context_$$.txt"
  touch "$test_file"

  # Verify EUID is not 0 (not running as root)
  if [[ "$EUID" -eq 0 ]]; then
    skip_test "Running as root, skipping regular user context test"
    cleanup_mock_files "$test_file"
    return
  fi

  __logic_set_file_ownership "$test_file"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed in regular user context"

  # Verify ownership is set to current user (not SUDO_USER)
  local owner
  owner=$(stat -c "%U" "$test_file")
  assert_equals "$owner" "$USER" "Owner should be \$USER in regular context"

  cleanup_mock_files "$test_file"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting files.common logic tests"

  # Setup
  setup_test

  # __logic_inject_overrides() tests
  test_inject_overrides_success_single_function
  test_inject_overrides_success_multiple_functions
  test_inject_overrides_no_override_file
  test_inject_overrides_empty_instance_name
  test_inject_overrides_empty_management_file
  test_inject_overrides_management_file_not_found
  test_inject_overrides_instance_config_not_found
  test_inject_overrides_blueprint_file_missing_from_config
  test_inject_overrides_blueprint_name_missing
  test_inject_overrides_malformed_override_file
  test_inject_overrides_readonly_management_file
  test_inject_overrides_idempotency

  # __logic_set_file_ownership() tests
  test_set_file_ownership_success
  test_set_file_ownership_empty_path
  test_set_file_ownership_file_not_found
  test_set_file_ownership_symlink
  test_set_file_ownership_permission_denied
  test_set_file_ownership_regular_user_context

  # Print summary and exit
  if print_assert_summary "$TEST_NAME"; then
    log_test "All tests passed"
    exit 0
  else
    log_test "Some tests failed"
    exit 1
  fi
}

main "$@"
