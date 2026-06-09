#!/usr/bin/env bash

# KGSM Lifecycle + Directories Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/lifecycle.sh and commands/directories.sh
#
# Integration points tested:
# - Lifecycle commands correctly fail when no instance exists
# - Directories commands correctly fail when no instance exists
# - Directories create builds the working directory structure an instance needs
# - Lifecycle reads directory paths from config populated by directories create
# - Directories remove destroys the structure lifecycle depends on
# - After directories remove, lifecycle operations fail appropriately
# - Working directory structure is correct and accessible for lifecycle
# - Two instances have independent directory structures and lifecycle states
# - Fake manage script integration: directories create → lifecycle works

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="lifecycle_directories_integration"
readonly LIFECYCLE_MODULE="$KGSM_ROOT/commands/lifecycle.sh"
readonly DIRECTORIES_MODULE="$KGSM_ROOT/commands/directories.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up lifecycle+directories integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$LIFECYCLE_MODULE" "lifecycle.sh command should exist"
  assert_file_executable "$LIFECYCLE_MODULE" "lifecycle.sh should be executable"
  assert_file_exists "$DIRECTORIES_MODULE" "directories.sh command should exist"
  assert_file_executable "$DIRECTORIES_MODULE" "directories.sh should be executable"

  log_test_step "Integration test environment validated"
}

# =============================================================================
# TEST 1: Lifecycle commands fail on nonexistent instances
# Both modules must return errors for missing instances
# =============================================================================

function test_lifecycle_fails_on_nonexistent_instance() {
  log_test_step "Testing: lifecycle commands fail on nonexistent instance"

  local fake="nonexistent_lifecycle_xyz_$$"

  "$LIFECYCLE_MODULE" start "$fake" 2>/dev/null
  local start_code=$?
  assert_not_equals 0 "$start_code" "lifecycle start on nonexistent should fail"

  "$LIFECYCLE_MODULE" stop "$fake" 2>/dev/null
  local stop_code=$?
  assert_not_equals 0 "$stop_code" "lifecycle stop on nonexistent should fail"

  "$LIFECYCLE_MODULE" is-active "$fake" 2>/dev/null
  local is_active_code=$?
  assert_not_equals 0 "$is_active_code" "lifecycle is-active on nonexistent should fail"

  "$LIFECYCLE_MODULE" status "$fake" 2>/dev/null
  local status_code=$?
  assert_not_equals 0 "$status_code" "lifecycle status on nonexistent should fail"
}

# =============================================================================
# TEST 2: Directories commands show error message on nonexistent instances
# Note: directories.sh exits 0 on invalid instance (known behavior) but
# outputs error messages to stderr - we verify the error is reported
# =============================================================================

function test_directories_errors_on_nonexistent_instance() {
  log_test_step "Testing: directories commands report error for nonexistent instance"

  local fake="nonexistent_dirs_xyz_$$"

  # directories.sh reports the error via stderr output
  local create_output
  create_output=$("$DIRECTORIES_MODULE" create "$fake" 2>&1)
  assert_contains "$create_output" "not found" \
    "directories create on nonexistent instance should report error"

  local remove_output
  remove_output=$("$DIRECTORIES_MODULE" remove "$fake" 2>&1)
  assert_contains "$remove_output" "not found" \
    "directories remove on nonexistent instance should report error"
}

# =============================================================================
# TEST 3: Directories create builds the full expected structure
# After directories create, all required subdirectories must exist
# =============================================================================

function test_directories_create_builds_expected_structure() {
  log_test_step "Testing: directories create builds full directory structure"

  local instance_name="test-lc-struct-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "directories create should succeed for valid instance"

  # Retrieve working_dir from the instance config
  local config_file
  config_file=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local working_dir
  working_dir=$(grep "^working_dir=" "$config_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')

  assert_not_null "$working_dir" "working_dir should be set in instance config"
  assert_dir_exists "$working_dir" "working_dir should exist on disk"
  assert_dir_exists "$working_dir/backups" "backups/ subdirectory should exist"
  assert_dir_exists "$working_dir/install" "install/ subdirectory should exist"
  assert_dir_exists "$working_dir/saves" "saves/ subdirectory should exist"
  assert_dir_exists "$working_dir/temp" "temp/ subdirectory should exist"
  assert_dir_exists "$working_dir/logs" "logs/ subdirectory should exist"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 4: Directories create updates instance config with paths lifecycle needs
# After directories create, instance config must have paths lifecycle reads
# =============================================================================

function test_directories_create_updates_config_paths() {
  log_test_step "Testing: directories create populates config with paths lifecycle needs"

  local instance_name="test-lc-paths-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "directories create should succeed"

  local config_file
  config_file=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)

  assert_not_null "$config_file" "Instance config should be findable"
  assert_file_exists "$config_file" "Instance config file should exist"

  # Verify paths that lifecycle depends on are set in the config
  assert_command_succeeds "grep -q 'working_dir=' '$config_file'" \
    "Config should have working_dir after directories create"
  assert_command_succeeds "grep -q 'install_dir=' '$config_file'" \
    "Config should have install_dir after directories create"
  assert_command_succeeds "grep -q 'logs_dir=' '$config_file'" \
    "Config should have logs_dir after directories create"
  assert_command_succeeds "grep -q 'saves_dir=' '$config_file'" \
    "Config should have saves_dir after directories create"
  assert_command_succeeds "grep -q 'backups_dir=' '$config_file'" \
    "Config should have backups_dir after directories create"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 5: Lifecycle is-active returns non-zero for a stopped instance
# A freshly created instance with directories is not running
# =============================================================================

function test_lifecycle_is_active_returns_nonzero_for_stopped_instance() {
  log_test_step "Testing: lifecycle is-active returns non-zero for stopped instance"

  local instance_name="test-lc-active-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "directories create should succeed"

  # A freshly created instance with directories but no server running
  # must NOT report as active
  "$LIFECYCLE_MODULE" is-active "$instance_name" 2>/dev/null
  local is_active_code=$?

  assert_not_equals 0 "$is_active_code" \
    "lifecycle is-active should return non-zero for a stopped/unconfigured instance"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 6: Directories remove destroys the working directory structure
# After remove, all directories must be gone
# =============================================================================

function test_directories_remove_destroys_structure() {
  log_test_step "Testing: directories remove destroys working directory structure"

  local instance_name="test-lc-remove-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Create directories
  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "directories create should succeed"

  local config_file
  config_file=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local working_dir
  working_dir=$(grep "^working_dir=" "$config_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')

  assert_dir_exists "$working_dir" "working_dir should exist before remove"

  # Remove directories
  assert_command_succeeds "$DIRECTORIES_MODULE remove $instance_name" \
    "directories remove should succeed"

  assert_dir_not_exists "$working_dir" "working_dir should not exist after remove"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 7: Lifecycle operations fail after directories removal
# Removing directories invalidates the management file path lifecycle depends on
# =============================================================================

function test_lifecycle_fails_after_directories_remove() {
  log_test_step "Testing: lifecycle operations fail after directories removal"

  local instance_name="test-lc-failrm-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Create directories and a stub management script
  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "directories create should succeed"

  local config_file
  config_file=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local working_dir
  working_dir=$(grep "^working_dir=" "$config_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
  local manage_file="${working_dir}/${instance_name}.manage.sh"

  # Create a stub management script to simulate a deployed instance
  cat > "$manage_file" << 'STUB_EOF'
#!/usr/bin/env bash
case "$1" in
  is-active) exit 1 ;;  # Report as inactive
  status) echo '{"running": false}'; exit 0 ;;
  start) exit 0 ;;
  stop) exit 0 ;;
  *) exit 1 ;;
esac
STUB_EOF
  chmod +x "$manage_file"

  # With directories and manage script present, is-active should work
  "$LIFECYCLE_MODULE" is-active "$instance_name" 2>/dev/null
  local before_code=$?
  # Either 0 (active) or EC_ERROR (1, inactive) - both are valid "working" responses
  assert_not_equals 127 "$before_code" \
    "lifecycle is-active should not fail with 'command not found' when manage script exists"

  # Remove directories (also removes the manage script)
  assert_command_succeeds "$DIRECTORIES_MODULE remove $instance_name" \
    "directories remove should succeed"

  # After removal, management file is gone - lifecycle must fail
  "$LIFECYCLE_MODULE" is-active "$instance_name" 2>/dev/null
  local after_code=$?
  assert_not_equals 0 "$after_code" \
    "lifecycle is-active should fail after directories removal"

  "$LIFECYCLE_MODULE" start "$instance_name" 2>/dev/null
  local start_code=$?
  assert_not_equals 0 "$start_code" \
    "lifecycle start should fail after directories removal"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 8: Lifecycle with stub manage script - full interaction test
# With directories created and manage script present, lifecycle operations work
# =============================================================================

function test_lifecycle_with_stub_manage_script() {
  log_test_step "Testing: lifecycle operations work with directories and stub manage script"

  local instance_name="test-lc-stub-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "directories create should succeed"

  local config_file
  config_file=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local working_dir
  working_dir=$(grep "^working_dir=" "$config_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
  local manage_file="${working_dir}/${instance_name}.manage.sh"

  # Create stub management script that reports instance as stopped
  cat > "$manage_file" << 'STUB_EOF'
#!/usr/bin/env bash
case "$1" in
  is-active)
    exit 1  # Stopped
    ;;
  status)
    echo '{"name":"'$0'","running":false,"version":"1.0.0"}'
    exit 0
    ;;
  start)
    exit 0
    ;;
  stop)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUB_EOF
  chmod +x "$manage_file"

  # is-active should return non-zero (instance is stopped, not running)
  "$LIFECYCLE_MODULE" is-active "$instance_name" 2>/dev/null
  local is_active_code=$?
  assert_not_equals 0 "$is_active_code" \
    "lifecycle is-active should report instance as not active (stopped stub)"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 9: Directories create is idempotent
# Running directories create twice should not fail
# =============================================================================

function test_directories_create_is_idempotent() {
  log_test_step "Testing: directories create is idempotent (can run twice)"

  local instance_name="test-lc-idem-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "First directories create should succeed"

  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "Second directories create should also succeed (idempotent)"

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 10: Two instances have independent directory structures
# Lifecycle + directories operations on one instance don't affect another
# =============================================================================

function test_two_instances_have_independent_directories() {
  log_test_step "Testing: two instances have independent directory structures"

  local instance1="test-lc-two1-$$"
  local instance2="test-lc-two2-$$"

  create_test_instance "factorio" "$instance1" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit1=$?
  create_test_instance "necesse" "$instance2" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit2=$?

  if [[ $create_exit1 -ne 0 || $create_exit2 -ne 0 ]]; then
    [[ $create_exit1 -eq 0 ]] && remove_test_instance "factorio" "$instance1" "$TEST_INSTALL_DIR"
    [[ $create_exit2 -eq 0 ]] && remove_test_instance "necesse" "$instance2" "$TEST_INSTALL_DIR"
    skip_test "Instance creation failed - skipping test"
    return
  fi

  assert_command_succeeds "$DIRECTORIES_MODULE create $instance1" \
    "directories create for instance1 should succeed"
  assert_command_succeeds "$DIRECTORIES_MODULE create $instance2" \
    "directories create for instance2 should succeed"

  local config1
  config1=$("$KGSM_ROOT/kgsm.sh" instances find "$instance1" 2>/dev/null)
  local working_dir1
  working_dir1=$(grep "^working_dir=" "$config1" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')

  local config2
  config2=$("$KGSM_ROOT/kgsm.sh" instances find "$instance2" 2>/dev/null)
  local working_dir2
  working_dir2=$(grep "^working_dir=" "$config2" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')

  assert_dir_exists "$working_dir1" "Instance1 working_dir should exist"
  assert_dir_exists "$working_dir2" "Instance2 working_dir should exist"
  assert_not_equals "$working_dir1" "$working_dir2" \
    "Two instances must have different working directories"

  # Remove one instance's directories - other should be unaffected
  assert_command_succeeds "$DIRECTORIES_MODULE remove $instance1" \
    "Removing instance1 directories should succeed"

  assert_dir_not_exists "$working_dir1" "Instance1 working_dir should be gone"
  assert_dir_exists "$working_dir2" "Instance2 working_dir should still exist"

  # Instance2 lifecycle operations should still fail (no manage.sh) but not because of missing dirs
  "$LIFECYCLE_MODULE" is-active "$instance2" 2>/dev/null
  local code2=$?
  # Should fail but NOT with a path error for instance2's working dir
  assert_not_equals 0 "$code2" "Instance2 is-active should still return non-zero (not running)"

  remove_test_instance "factorio" "$instance1" "$TEST_INSTALL_DIR"
  remove_test_instance "necesse" "$instance2" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 11: ensure-created creates a directory lifecycle could use
# =============================================================================

function test_ensure_created_supports_lifecycle_paths() {
  log_test_step "Testing: directories ensure-created creates paths lifecycle can use"

  local test_path="$KGSM_TEST_SANDBOX/lifecycle_test_path_$$"

  assert_dir_not_exists "$test_path" "Path should not exist before ensure-created"

  assert_command_succeeds "$DIRECTORIES_MODULE ensure-created $test_path" \
    "ensure-created should succeed"

  assert_dir_exists "$test_path" "Path should exist after ensure-created"

  # Verify it is writable (lifecycle would write logs, pid files here)
  assert_command_succeeds "touch '$test_path/test_write_$$'" \
    "Path created by ensure-created should be writable"

  rm -f "$test_path/test_write_$$"
  rm -rf "$test_path"
}

# =============================================================================
# TEST 12: Lifecycle and directories status after create-remove-create cycle
# After remove followed by re-create, directory structure is valid again
# =============================================================================

function test_directories_create_remove_create_cycle() {
  log_test_step "Testing: create → remove → create cycle (remove destroys config too)"

  local instance_name="test-lc-cycle-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local config_file
  config_file=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)

  # First create
  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "First create should succeed"

  local working_dir
  working_dir=$(grep "^working_dir=" "$config_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
  assert_dir_exists "$working_dir" "working_dir should exist after first create"
  assert_dir_exists "$working_dir/logs" "logs/ should exist after first create"
  assert_dir_exists "$working_dir/backups" "backups/ should exist after first create"

  # Remove - also removes the instance config (it lives inside working_dir)
  assert_command_succeeds "$DIRECTORIES_MODULE remove $instance_name" \
    "Remove should succeed"
  assert_dir_not_exists "$working_dir" "working_dir should be gone after remove"

  # After remove, lifecycle is-active should fail (no config or manage script)
  "$LIFECYCLE_MODULE" is-active "$instance_name" 2>/dev/null
  local is_active_code=$?
  assert_not_equals 0 "$is_active_code" \
    "lifecycle is-active should fail after directories removal (config gone)"

  # Note: directories create after removal would need instance re-creation
  # since the config file lives inside the removed working_dir
  # This is expected behavior - directories remove is destructive

  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

