#!/usr/bin/env bash

# KGSM Files Management End-to-End Tests
#
# Test Type: E2E
# Target: Complete file management workflow - files.sh, files.management.sh,
#         files.ufw.sh, files.upnp.sh, files.symlink.sh
#
# Validates the full lifecycle:
#   1. Instance creation (prerequisite)
#   2. Directory creation (prerequisite for files)
#   3. Management file creation, verification, and removal
#   4. Orchestrated file creation and removal via files.sh
#   5. Config-dependent integrations (ufw, upnp, symlink)
#   6. Error handling for invalid instances

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_management_e2e"

readonly FILES_MODULE="$KGSM_ROOT/commands/files.sh"
readonly FILES_MANAGEMENT_MODULE="$KGSM_ROOT/commands/files.management.sh"
readonly FILES_UFW_MODULE="$KGSM_ROOT/commands/files.ufw.sh"
readonly FILES_UPNP_MODULE="$KGSM_ROOT/commands/files.upnp.sh"
readonly FILES_SYMLINK_MODULE="$KGSM_ROOT/commands/files.symlink.sh"
readonly DIRECTORIES_MODULE="$KGSM_ROOT/commands/directories.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up files management E2E tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs-e2e"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  assert_file_exists "$FILES_MODULE" "files.sh should exist"
  assert_file_executable "$FILES_MODULE" "files.sh should be executable"

  assert_file_exists "$FILES_MANAGEMENT_MODULE" "files.management.sh should exist"
  assert_file_executable "$FILES_MANAGEMENT_MODULE" "files.management.sh should be executable"

  assert_file_exists "$FILES_UFW_MODULE" "files.ufw.sh should exist"
  assert_file_executable "$FILES_UFW_MODULE" "files.ufw.sh should be executable"

  assert_file_exists "$FILES_UPNP_MODULE" "files.upnp.sh should exist"
  assert_file_executable "$FILES_UPNP_MODULE" "files.upnp.sh should be executable"

  assert_file_exists "$FILES_SYMLINK_MODULE" "files.symlink.sh should exist"
  assert_file_executable "$FILES_SYMLINK_MODULE" "files.symlink.sh should be executable"

  assert_file_exists "$DIRECTORIES_MODULE" "directories.sh should exist"
  assert_file_executable "$DIRECTORIES_MODULE" "directories.sh should be executable"

  log_test_step "E2E test environment validated"
}

# =============================================================================
# TEST 1: Management file is created and is executable
# =============================================================================

function test_management_file_create_and_verify() {
  log_test_step "Testing: management file creation - file exists and is executable"

  local instance_name="test-mgmt-create-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping management file creation test"
    return
  fi

  # Get expected management file path from instance config
  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_not_null "$manage_file" "Instance config should have management_file path"

  # Note: The management file is now created when calling "create_test_instance"
  # Before: management file should NOT exist
  # assert_file_not_exists "$manage_file" "Management file should not exist before files.management.sh create"
  # Create management file
  # assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" "files.management.sh create should succeed"

  # After: management file should exist
  assert_file_exists "$manage_file" "Management file should exist after files.management.sh create"

  # Management file should be executable
  assert_file_executable "$manage_file" "Management file should have execute permission"

  # Cleanup
  "$FILES_MANAGEMENT_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 2: Management file creation fails for nonexistent instance
# =============================================================================

function test_management_file_create_fails_for_invalid_instance() {
  log_test_step "Testing: management file creation fails for nonexistent instance"

  assert_command_fails "$FILES_MANAGEMENT_MODULE create nonexistent-instance-xyz-$$" \
    "files.management.sh create should fail for nonexistent instance"
}

# =============================================================================
# TEST 3: Management file removal
# =============================================================================

function test_management_file_remove() {
  log_test_step "Testing: management file removal"

  local instance_name="test-mgmt-remove-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping management file removal test"
    return
  fi

  # Create management file first
  "$FILES_MANAGEMENT_MODULE" create "$instance_name" >/dev/null 2>&1

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file" \
    "Management file should exist before removal"

  # Remove management file
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE remove $instance_name" \
    "files.management.sh remove should succeed"

  # After removal: management file should not exist
  assert_file_not_exists "$manage_file" \
    "Management file should not exist after files.management.sh remove"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 4: Management file removal fails for nonexistent instance
# =============================================================================

function test_management_file_remove_fails_for_invalid_instance() {
  log_test_step "Testing: management file removal fails for nonexistent instance"

  assert_command_fails "$FILES_MANAGEMENT_MODULE remove nonexistent-instance-xyz-$$" \
    "files.management.sh remove should fail for nonexistent instance"
}

# =============================================================================
# TEST 5: files.sh create orchestrates management file creation
# =============================================================================

function test_files_orchestrator_creates_management_file() {
  log_test_step "Testing: files.sh create orchestrates management file creation"

  local instance_name="test-files-create-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping files orchestrator test"
    return
  fi

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  # Create all files via orchestrator
  assert_command_succeeds "$FILES_MODULE create $instance_name" \
    "files.sh create should succeed"

  # Management file should exist after orchestrated creation
  assert_file_exists "$manage_file" \
    "Management file should exist after files.sh create"

  # Cleanup
  "$FILES_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 6: files.sh remove orchestrates management file removal
# =============================================================================

function test_files_orchestrator_removes_management_file() {
  log_test_step "Testing: files.sh remove orchestrates management file removal"

  local instance_name="test-files-remove-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping files orchestrator remove test"
    return
  fi

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  # Create files first
  "$FILES_MODULE" create "$instance_name" >/dev/null 2>&1

  assert_file_exists "$manage_file" \
    "Management file should exist before files.sh remove"

  # Remove all files via orchestrator
  assert_command_succeeds "$FILES_MODULE remove $instance_name" \
    "files.sh remove should succeed"

  # Management file should be gone
  assert_file_not_exists "$manage_file" \
    "Management file should not exist after files.sh remove"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 7: files.sh create fails for nonexistent instance
# =============================================================================

function test_files_orchestrator_fails_for_invalid_instance() {
  log_test_step "Testing: files.sh create/remove fails for nonexistent instance"

  assert_command_fails "$FILES_MODULE create nonexistent-instance-xyz-$$" \
    "files.sh create should fail for nonexistent instance"

  assert_command_fails "$FILES_MODULE remove nonexistent-instance-xyz-$$" \
    "files.sh remove should fail for nonexistent instance"
}

# =============================================================================
# TEST 9: UFW integration fails for nonexistent instance
# =============================================================================

function test_ufw_fails_for_invalid_instance() {
  log_test_step "Testing: files.ufw.sh fails for nonexistent instance"

  assert_command_fails "$FILES_UFW_MODULE enable nonexistent-instance-xyz-$$" \
    "files.ufw.sh enable should fail for nonexistent instance"

  assert_command_fails "$FILES_UFW_MODULE disable nonexistent-instance-xyz-$$" \
    "files.ufw.sh disable should fail for nonexistent instance"
}

# =============================================================================
# TEST 10: UPnP integration - enable/disable updates instance config
# =============================================================================

function test_upnp_enable_disable() {
  log_test_step "Testing: files.upnp.sh enable/disable updates instance config"

  local instance_name="test-upnp-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping upnp test"
    return
  fi

  # Enable UPnP
  assert_command_succeeds "$FILES_UPNP_MODULE enable $instance_name" \
    "files.upnp.sh enable should succeed"

  # Verify instance config reflects UPnP enabled
  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)

  assert_file_contains "$instance_config" "enable_port_forwarding=true" \
    "Instance config should show port_forwarding=true after upnp enable"

  # Disable UPnP
  "$FILES_UPNP_MODULE" disable "$instance_name" >/dev/null 2>&1
  local disable_exit=$?
  local disable_ok="false"
  [[ $disable_exit -eq 0 || $disable_exit -eq 219 ]] && disable_ok="true"
  assert_true "$disable_ok" \
    "files.upnp.sh disable should succeed (exit 0 or known success code)"

  # Verify instance config reflects UPnP disabled
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)

  assert_file_contains "$instance_config" "enable_port_forwarding=false" \
    "Instance config should show port_forwarding=false after upnp disable"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 11: UPnP integration fails for nonexistent instance
# =============================================================================

function test_upnp_fails_for_invalid_instance() {
  log_test_step "Testing: files.upnp.sh fails for nonexistent instance"

  assert_command_fails "$FILES_UPNP_MODULE enable nonexistent-instance-xyz-$$" \
    "files.upnp.sh enable should fail for nonexistent instance"
}

# =============================================================================
# TEST 13: Complete E2E workflow - create instance → directories → files → remove
# =============================================================================

function test_complete_e2e_workflow() {
  log_test_step "Testing: complete E2E workflow - create instance, directories, files, then remove all"

  local instance_name="test-full-e2e-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping complete E2E workflow test"
    return
  fi

  # Step 1: Create directories
  assert_command_succeeds "$DIRECTORIES_MODULE create $instance_name" \
    "E2E: directories.sh create should succeed"

  # Step 2: Create all files
  assert_command_succeeds "$FILES_MODULE create $instance_name" \
    "E2E: files.sh create should succeed"

  # Step 3: Verify management file exists and is executable
  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file" \
    "E2E: Management file should exist after files.sh create"
  assert_file_executable "$manage_file" \
    "E2E: Management file should be executable"

  # Step 4: Remove all files
  assert_command_succeeds "$FILES_MODULE remove $instance_name" \
    "E2E: files.sh remove should succeed"

  assert_file_not_exists "$manage_file" \
    "E2E: Management file should be gone after files.sh remove"

  # Step 5: Remove directories
  assert_command_succeeds "$DIRECTORIES_MODULE remove $instance_name" \
    "E2E: directories.sh remove should succeed"

  # Step 6: Cleanup instance
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 14: files.sh create is idempotent
# =============================================================================

function test_files_create_is_idempotent() {
  log_test_step "Testing: files.sh create is idempotent (can run twice safely)"

  local instance_name="test-idem-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping idempotency test"
    return
  fi

  assert_command_succeeds "$FILES_MODULE create $instance_name" \
    "First files.sh create should succeed"

  assert_command_succeeds "$FILES_MODULE create $instance_name" \
    "Second files.sh create should also succeed (idempotent)"

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file" \
    "Management file should still exist after second create"

  # Cleanup
  "$FILES_MODULE" remove "$instance_name" >/dev/null 2>&1 || true
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 15: Two instances have independent management files
# =============================================================================

function test_two_instances_have_independent_management_files() {
  log_test_step "Testing: two instances have independent management files"

  local instance1_name="test-two-inst-a-$$"
  local instance2_name="test-two-inst-b-$$"

  create_test_instance "factorio" "$instance1_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create1_exit=$?
  create_test_instance "factorio" "$instance2_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local create2_exit=$?

  if [[ $create1_exit -ne 0 || $create2_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping two-instance management file test"
    [[ $create1_exit -eq 0 ]] && remove_test_instance "factorio" "$instance1_name" "$TEST_INSTALL_DIR"
    [[ $create2_exit -eq 0 ]] && remove_test_instance "factorio" "$instance2_name" "$TEST_INSTALL_DIR"
    return
  fi

  # Create management files for both instances
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance1_name" \
    "Management file creation should succeed for instance 1"
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance2_name" \
    "Management file creation should succeed for instance 2"

  # Get each instance's management file path
  local config1
  config1=$("$KGSM_ROOT/kgsm.sh" instances find "$instance1_name" 2>/dev/null)
  local manage_file1
  manage_file1=$(grep "^management_file=" "$config1" 2>/dev/null | cut -d= -f2 | tr -d '"')

  local config2
  config2=$("$KGSM_ROOT/kgsm.sh" instances find "$instance2_name" 2>/dev/null)
  local manage_file2
  manage_file2=$(grep "^management_file=" "$config2" 2>/dev/null | cut -d= -f2 | tr -d '"')

  # Both management files should exist
  assert_file_exists "$manage_file1" "Instance 1 management file should exist"
  assert_file_exists "$manage_file2" "Instance 2 management file should exist"

  # They should be different files
  assert_not_equals "$manage_file1" "$manage_file2" \
    "Each instance should have its own management file path"

  # Remove one - should not affect the other
  "$FILES_MANAGEMENT_MODULE" remove "$instance1_name" >/dev/null 2>&1

  assert_file_not_exists "$manage_file1" \
    "Instance 1 management file should be gone after removal"
  assert_file_exists "$manage_file2" \
    "Instance 2 management file should still exist after instance 1 removal"

  # Cleanup
  "$FILES_MANAGEMENT_MODULE" remove "$instance2_name" >/dev/null 2>&1 || true
  remove_test_instance "factorio" "$instance1_name" "$TEST_INSTALL_DIR"
  remove_test_instance "factorio" "$instance2_name" "$TEST_INSTALL_DIR"
}

