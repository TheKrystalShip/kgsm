#!/usr/bin/env bash

# KGSM Instance Lifecycle E2E Tests
#
# Test Type: E2E
# Target: Complete instance lifecycle workflow without external dependencies
#
# Workflow tested:
# 1. Setup validation          - All required modules exist and are executable
# 2. Instance creation         - factorio blueprint → instance config
# 3. Directory creation        - Instance directories are created
# 4. Management file creation  - Management script is created
# 5. Instance info             - Instance info is readable
# 6. Instance listing          - Instance appears in list
# 7. Files removal             - Management script is removed
# 8. Directory removal         - Directories are removed
# 9. Instance removal          - Instance record is removed
# 10. Negative cases           - Duplicate creation fails, invalid blueprint fails

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instance_lifecycle_e2e"

readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"
readonly DIRECTORIES_MODULE="$KGSM_ROOT/commands/directories.sh"
readonly FILES_MODULE="$KGSM_ROOT/commands/files.sh"
readonly FILES_MANAGEMENT_MODULE="$KGSM_ROOT/commands/files.management.sh"
readonly LIFECYCLE_MODULE="$KGSM_ROOT/commands/lifecycle.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up instance lifecycle E2E tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs-e2e"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  assert_file_exists "$INSTANCES_MODULE" "instances.sh should exist"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"

  assert_file_exists "$DIRECTORIES_MODULE" "directories.sh should exist"
  assert_file_executable "$DIRECTORIES_MODULE" "directories.sh should be executable"

  assert_file_exists "$FILES_MODULE" "files.sh should exist"
  assert_file_executable "$FILES_MODULE" "files.sh should be executable"

  assert_file_exists "$FILES_MANAGEMENT_MODULE" "files.management.sh should exist"
  assert_file_executable "$FILES_MANAGEMENT_MODULE" "files.management.sh should be executable"

  assert_file_exists "$LIFECYCLE_MODULE" "lifecycle.sh should exist"
  assert_file_executable "$LIFECYCLE_MODULE" "lifecycle.sh should be executable"

  log_test_step "E2E test environment validated"
}

# =============================================================================
# TEST 1: Blueprint-to-instance creation
# factorio blueprint → instance config file exists with expected content
# =============================================================================

function test_instance_creation_from_blueprint() {
  log_test_step "Testing: instance creation from factorio blueprint"

  local instance_name="e2e-create-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  assert_equals 0 "$create_exit" "Instance creation should succeed"

  # Verify instance config exists
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed for created instance"
  assert_file_exists "$instance_config" "Instance config file should exist"

  # Config must reference the factorio blueprint
  assert_file_contains "$instance_config" "factorio" \
    "Instance config should reference factorio blueprint"

  # Config must have a name field
  assert_file_contains "$instance_config" "name=" \
    "Instance config should contain name field"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 2: Directory creation
# directories.sh create → working_dir subdirectories exist
# =============================================================================

function test_directory_creation() {
  log_test_step "Testing: directory creation for instance"

  local instance_name="e2e-dirs-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created before directory test"

  # Create directories first, then read paths from the updated config
  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "directories.sh create should succeed"

  # Now read updated config paths
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  local working_dir
  working_dir=$(grep "^working_dir=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  assert_not_null "$working_dir" "Instance config should have working_dir"

  local install_dir
  install_dir=$(grep "^install_dir=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  assert_not_null "$install_dir" "Instance config should have install_dir"

  # Verify expected subdirectories were created
  assert_dir_exists "$install_dir" \
    "Install directory should be created"

  local backups_dir
  backups_dir=$(grep "^backups_dir=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  if [[ -n "$backups_dir" ]]; then
    assert_dir_exists "$backups_dir" "Backups directory should be created"
  fi

  local logs_dir
  logs_dir=$(grep "^logs_dir=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  if [[ -n "$logs_dir" ]]; then
    assert_dir_exists "$logs_dir" "Logs directory should be created"
  fi

  # Cleanup: remove instance first (while config is accessible), then directories
  "$INSTANCES_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  "$DIRECTORIES_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  local install_base="${TEST_INSTALL_DIR:-$TEST_SANDBOX_INSTANCES_INSTALL_DIR}"
  rm -rf "$install_base/factorio/$instance_name" 2>/dev/null || true
  rmdir "$install_base/factorio" 2>/dev/null || true
}

# =============================================================================
# TEST 3: Management file creation
# files.management.sh create → management script exists and is executable
# =============================================================================

function test_management_file_creation() {
  log_test_step "Testing: management file creation"

  local instance_name="e2e-files-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created before file test"

  # Create directories first (required for management file)
  "$DIRECTORIES_MODULE" create "$instance_name" >/dev/null 2>&1
  assert_equals 0 "$?" "Directories should be created before management file"

  # Get expected management file path
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  assert_not_null "$manage_file" "Instance config should have management_file path"

  # Note: The management file is now created when calling "create_test_instance"

  # Management file should NOT exist before creation
  # assert_file_not_exists "$manage_file" "Management file should not exist before files.management.sh create"
  # Create the management file
  # assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" "files.management.sh create should succeed"

  # Management file should now exist and be executable
  assert_file_exists "$manage_file" "Management file should exist after files.management.sh create"
  assert_file_executable "$manage_file" "Management file should be executable"

  # Cleanup
  "$FILES_MANAGEMENT_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  "$DIRECTORIES_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 4: Instance info is readable
# instances info returns structured output with expected fields
# =============================================================================

function test_instance_info_readable() {
  log_test_step "Testing: instance info is readable"

  local instance_name="e2e-info-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for info test"

  # instances info should succeed
  local info_output
  info_output=$("$INSTANCES_MODULE" info "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances info should succeed"
  assert_not_null "$info_output" "instances info should return output"

  # Should contain the instance name
  assert_contains "$info_output" "$instance_name" \
    "instances info output should contain instance name"

  # Should contain runtime info (native for factorio)
  assert_contains "$info_output" "factorio" \
    "instances info output should reference factorio"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 5: Instance appears in list after creation
# instances list must include the created instance name
# =============================================================================

function test_instance_appears_in_list() {
  log_test_step "Testing: instance appears in instances list"

  local instance_name="e2e-list-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for list test"

  # Instance should appear in global list
  local list_output
  list_output=$("$INSTANCES_MODULE" list 2>&1)
  assert_equals 0 "$?" "instances list should succeed"
  assert_contains "$list_output" "$instance_name" \
    "Instance should appear in instances list"

  # Instance should appear when filtering by blueprint
  local blueprint_list
  blueprint_list=$("$INSTANCES_MODULE" list factorio 2>&1)
  assert_equals 0 "$?" "instances list factorio should succeed"
  assert_contains "$blueprint_list" "$instance_name" \
    "Instance should appear in factorio-filtered list"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 6: Files removal cleans up management script
# files.management.sh remove → management file no longer exists
# =============================================================================

function test_files_removal() {
  log_test_step "Testing: management file removal"

  local instance_name="e2e-filesrm-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for file removal test"

  "$DIRECTORIES_MODULE" create "$instance_name" >/dev/null 2>&1
  "$FILES_MANAGEMENT_MODULE" create "$instance_name" >/dev/null 2>&1

  # Get management file path
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  assert_not_null "$manage_file" "Instance config should have management_file path"

  # Verify file exists before removal
  assert_file_exists "$manage_file" "Management file should exist before removal"

  # Remove the management file
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE remove $instance_name" \
    "files.management.sh remove should succeed"

  # File should no longer exist
  assert_file_not_exists "$manage_file" \
    "Management file should not exist after files.management.sh remove"

  # Cleanup
  "$DIRECTORIES_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 7: Directory removal cleans up directory structure
# directories.sh remove → install directory no longer exists
# =============================================================================

function test_directory_removal() {
  log_test_step "Testing: directory removal"

  local instance_name="e2e-dirsrm-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for directory removal test"

  "$DIRECTORIES_MODULE" create "$instance_name" >/dev/null 2>&1

  # Get install dir path
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  local install_dir
  install_dir=$(grep "^install_dir=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  assert_not_null "$install_dir" "Instance config should have install_dir path"
  assert_dir_exists "$install_dir" "Install directory should exist before removal"

  # Remove directories
  assert_command_succeeds "$DIRECTORIES_MODULE remove $instance_name" \
    "directories.sh remove should succeed"

  # Install dir should no longer exist
  assert_dir_not_exists "$install_dir" \
    "Install directory should not exist after directories.sh remove"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 8: Instance removal removes it from list
# instances remove → instance no longer appears in list or find
# =============================================================================

function test_instance_removal() {
  log_test_step "Testing: instance removal removes config and from list"

  local instance_name="e2e-instremove-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for removal test"

  # Verify instance exists before removal
  local config_before
  config_before=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should succeed before removal"
  assert_file_exists "$config_before" "Instance config should exist before removal"

  # Remove the instance config
  assert_command_succeeds "$INSTANCES_MODULE remove $instance_name" \
    "instances remove should succeed"

  # Instance config file should no longer exist
  assert_file_not_exists "$config_before" \
    "Instance config file should not exist after removal"

  # Instance should no longer appear in list
  local list_after
  list_after=$("$INSTANCES_MODULE" list 2>&1)
  assert_not_contains "$list_after" "$instance_name" \
    "Instance should not appear in list after removal"

  # Cleanup prereqs only (instance config already removed)
  local install_dir="${TEST_INSTALL_DIR:-$TEST_SANDBOX_INSTANCES_INSTALL_DIR}"
  rm -f "$KGSM_INSTANCES_DIR/factorio/$instance_name" 2>/dev/null || true
  rmdir "$KGSM_INSTANCES_DIR/factorio" 2>/dev/null || true
  rm -rf "$install_dir/factorio/$instance_name" 2>/dev/null || true
  rmdir "$install_dir/factorio" 2>/dev/null || true
}

# =============================================================================
# TEST 9: Complete lifecycle workflow end-to-end
# create → dirs → files → info → list → files remove → dirs remove → instance remove
# =============================================================================

function test_complete_lifecycle() {
  log_test_step "Testing: complete instance lifecycle workflow end-to-end"

  local instance_name="e2e-lifecycle-$$"

  # --- Step 1: Create instance from blueprint ---
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Step 1: Instance creation should succeed"

  # Verify instance exists
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "Step 1: instances find should succeed after creation"

  # --- Step 2: Create directories ---
  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "Step 2: Directory creation should succeed"

  # --- Step 3: Create management files ---
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" \
    "Step 3: Management file creation should succeed"

  # --- Step 4: Verify instance info is readable ---
  local info
  info=$("$INSTANCES_MODULE" info "$instance_name" 2>&1)
  assert_equals 0 "$?" "Step 4: instances info should succeed"
  assert_not_null "$info" "Step 4: instances info should return output"

  # --- Step 5: Verify instance appears in list ---
  local list
  list=$("$INSTANCES_MODULE" list 2>&1)
  assert_contains "$list" "$instance_name" \
    "Step 5: Instance should appear in list"

  # --- Step 6: Remove management files ---
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE remove $instance_name" \
    "Step 6: Management file removal should succeed"

  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  if [[ -n "$manage_file" ]]; then
    assert_file_not_exists "$manage_file" \
      "Step 6: Management file should not exist after removal"
  fi

  # --- Step 7: Remove instance config (symlink) BEFORE removing directories ---
  # Note: directories.sh remove deletes the working dir (including instance config),
  # so instances.sh remove must be called first while the config is still accessible.
  assert_command_succeeds "$INSTANCES_MODULE remove $instance_name" \
    "Step 7: Instance removal should succeed"

  # --- Step 8: Remove directories (working dir and subdirs) ---
  # The working directory still exists on disk; instances.sh remove only deleted the symlink.
  # Use the working_dir from config (read before symlink was removed)
  local working_dir
  working_dir=$(grep "^working_dir=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  if [[ -n "$working_dir" && -d "$working_dir" ]]; then
    rm -rf "$working_dir" 2>/dev/null || true
  fi

  # --- Step 9: Verify instance no longer exists ---
  local list_after
  list_after=$("$INSTANCES_MODULE" list 2>&1)
  assert_not_contains "$list_after" "$instance_name" \
    "Step 9: Instance should not appear in list after removal"

  # Cleanup prereqs
  local install_dir="${TEST_INSTALL_DIR:-$TEST_SANDBOX_INSTANCES_INSTALL_DIR}"
  rm -f "$KGSM_INSTANCES_DIR/factorio/$instance_name" 2>/dev/null || true
  rmdir "$KGSM_INSTANCES_DIR/factorio" 2>/dev/null || true
  rm -rf "$install_dir/factorio/$instance_name" 2>/dev/null || true
  rmdir "$install_dir/factorio" 2>/dev/null || true
}

# =============================================================================
# TEST 10: Duplicate instance creation fails
# Creating two instances with the same name should fail on second attempt
# =============================================================================

function test_duplicate_instance_creation_fails() {
  log_test_step "Testing: duplicate instance creation is rejected"

  local instance_name="e2e-dup-$$"

  # Create first instance
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "First instance creation should succeed"

  # Attempt to create second instance with same name (prereqs already exist)
  "$INSTANCES_MODULE" create factorio \
    --install-dir "$TEST_INSTALL_DIR" \
    --name "$instance_name" 2>/dev/null
  local dup_exit=$?

  assert_not_equals 0 "$dup_exit" \
    "Creating instance with duplicate name should fail"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 11: Invalid blueprint fails instance creation
# Using a nonexistent blueprint must be rejected
# =============================================================================

function test_invalid_blueprint_fails() {
  log_test_step "Testing: instance creation with invalid blueprint is rejected"

  local fake_blueprint="nonexistent_blueprint_xyz_abc_e2e"

  # Attempt instance creation with invalid blueprint
  "$INSTANCES_MODULE" create "$fake_blueprint" \
    --install-dir "$TEST_INSTALL_DIR" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "Instance creation with nonexistent blueprint should fail"

  # No instance directory should be created
  assert_dir_not_exists "$KGSM_ROOT/instances/$fake_blueprint" \
    "No instance directory should be created for invalid blueprint"
}

# =============================================================================
# TEST 12: Lifecycle commands return non-zero for non-running instance
# is-active should fail when server is not running (no game binaries)
# =============================================================================

function test_lifecycle_commands_on_stopped_instance() {
  log_test_step "Testing: lifecycle is-active returns failure for non-running instance"

  local instance_name="e2e-lc-$$"

  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance should be created for lifecycle test"

  "$DIRECTORIES_MODULE" create "$instance_name" >/dev/null 2>&1
  "$FILES_MANAGEMENT_MODULE" create "$instance_name" >/dev/null 2>&1

  # is-active should fail since the server is not running
  assert_command_fails "$LIFECYCLE_MODULE is-active $instance_name" \
    "is-active should return non-zero for a non-running instance"

  # Cleanup
  "$FILES_MANAGEMENT_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  "$DIRECTORIES_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

