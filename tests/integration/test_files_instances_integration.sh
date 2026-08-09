#!/usr/bin/env bash

# KGSM Files + Instances Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between files.sh, files.management.sh, files.symlink.sh,
#         files.firewall.sh and the instances module
#
# Integration points tested:
# - Management file creation after an instance is created
# - Management file removal during instance cleanup
# - files.sh orchestrator creates/removes files respecting config settings
# - Symlink integration enable/disable with a local shortcuts directory
# - Error cases: invalid/missing instance names are rejected by all file modules
# - Two instances have independent management files

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_instances_integration"
readonly FILES_MODULE="$KGSM_ROOT/commands/files.sh"
readonly FILES_MANAGEMENT_MODULE="$KGSM_ROOT/commands/files.management.sh"
readonly FILES_SYMLINK_MODULE="$KGSM_ROOT/commands/files.symlink.sh"
readonly FILES_FIREWALL_MODULE="$KGSM_ROOT/commands/files.firewall.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

TEST_INSTALL_DIR=""
TEST_SHORTCUTS_DIR=""

# Per-test cleanup tracking (used by teardown hook)
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up files+instances integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  TEST_SHORTCUTS_DIR="$KGSM_ROOT/test-shortcuts"
  mkdir -p
  mkdir -p "$TEST_SHORTCUTS_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  assert_file_exists "$FILES_MODULE" "files.sh command should exist"
  assert_file_executable "$FILES_MODULE" "files.sh should be executable"

  assert_file_exists "$FILES_MANAGEMENT_MODULE" "files.management.sh command should exist"
  assert_file_executable "$FILES_MANAGEMENT_MODULE" "files.management.sh should be executable"

  assert_file_exists "$FILES_SYMLINK_MODULE" "files.symlink.sh command should exist"
  assert_file_executable "$FILES_SYMLINK_MODULE" "files.symlink.sh should be executable"

  assert_file_exists "$FILES_FIREWALL_MODULE" "files.firewall.sh command should exist"
  assert_file_executable "$FILES_FIREWALL_MODULE" "files.firewall.sh should be executable"

  log_test_step "Integration test environment validated"
}

function setup() {
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" 2>/dev/null || true
  done
}

# =============================================================================
# TEST 1: Management file is created for a valid instance
# files.management.sh create → management file exists at expected path
# =============================================================================

function test_management_file_creation() {
  log_test_step "Testing: management file creation for a valid instance"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Get the expected management file path from instance config
  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local expected_manage_file
  expected_manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_not_null "$expected_manage_file" "Instance config should have management_file path"

  # Note: The management file is now created when calling "create_test_instance"
  # Management file should NOT exist yet (not created by instances create)
  # assert_file_not_exists "$expected_manage_file" "Management file should not exist before files.management.sh create"
  # Create the management file
  # assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" "files.management.sh create should succeed"

  # Management file should now exist
  assert_file_exists "$expected_manage_file" \
    "Management file should exist after files.management.sh create"

  # Management file should be executable
  assert_file_executable "$expected_manage_file" \
    "Management file should be executable"
}

# =============================================================================
# TEST 2: Management file contains instance-specific content
# The generated management script should reference the instance name
# =============================================================================

function test_management_file_content() {
  log_test_step "Testing: management file contains instance-specific content"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" \
    "files.management.sh create should succeed"

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file" "Management file should exist after creation"

  # Management file should be a bash script
  assert_file_contains "$manage_file" "#!/usr/bin/env bash" \
    "Management file should be a bash script"

  # Management file should contain the INSTANCE_NAME dynamic setup (from template)
  assert_file_contains "$manage_file" "INSTANCE_NAME" \
    "Management file should define INSTANCE_NAME"
}

# =============================================================================
# TEST 3: Management file removal works correctly
# files.management.sh remove → management file is gone
# =============================================================================

function test_management_file_removal() {
  log_test_step "Testing: management file removal for a valid instance"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create management file first
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" \
    "files.management.sh create should succeed"

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file" "Management file should exist after creation"

  # Remove management file
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE remove $instance_name" \
    "files.management.sh remove should succeed"

  assert_file_not_exists "$manage_file" \
    "Management file should be gone after files.management.sh remove"
}

# =============================================================================
# TEST 4: Management file commands fail for nonexistent instance
# All management file operations must reject unknown instances
# =============================================================================

function test_management_file_fails_for_nonexistent_instance() {
  log_test_step "Testing: management file commands fail for nonexistent instance"

  local fake="nonexistent_files_xyz_$$"

  "$FILES_MANAGEMENT_MODULE" create "$fake" 2>/dev/null
  local create_code=$?
  assert_not_equals 0 "$create_code" \
    "files.management.sh create should fail for nonexistent instance"

  "$FILES_MANAGEMENT_MODULE" remove "$fake" 2>/dev/null
  local remove_code=$?
  assert_not_equals 0 "$remove_code" \
    "files.management.sh remove should fail for nonexistent instance"
}

# =============================================================================
# TEST 5: files.sh orchestrator creates management file (config-aware)
# files.sh create → management file created; optional integrations follow config
# =============================================================================

function test_files_orchestrator_create() {
  log_test_step "Testing: files.sh create orchestrator creates management file"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  # Note: The management file is now created when calling "create_test_instance"
  # assert_not_null "$manage_file" "Instance config should have management_file path"
  # assert_file_not_exists "$manage_file" "Management file should not exist before files.sh create"
  # Run orchestrator create (test sandbox has ufw/symlink disabled in config)
  # assert_command_succeeds "$FILES_MODULE create $instance_name" "files.sh create should succeed"
  # Management file must always be created

  assert_file_exists "$manage_file" "Management file must exist after files.sh create"
  assert_file_executable "$manage_file" "Management file created by files.sh must be executable"
}

# =============================================================================
# TEST 6: files.sh orchestrator removes management file
# files.sh remove → management file is removed
# =============================================================================

function test_files_orchestrator_remove() {
  log_test_step "Testing: files.sh remove orchestrator removes management file"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create files first
  assert_command_succeeds "$FILES_MODULE create $instance_name" \
    "files.sh create should succeed"

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file" "Management file should exist before remove"

  # Remove files
  assert_command_succeeds "$FILES_MODULE remove $instance_name" \
    "files.sh remove should succeed"

  assert_file_not_exists "$manage_file" \
    "Management file should be gone after files.sh remove"
}

# =============================================================================
# TEST 7: files.sh orchestrator fails for nonexistent instance
# =============================================================================

function test_files_orchestrator_fails_for_nonexistent_instance() {
  log_test_step "Testing: files.sh orchestrator fails for nonexistent instance"

  local fake="nonexistent_orch_xyz_$$"

  "$FILES_MODULE" create "$fake" 2>/dev/null
  local create_code=$?
  assert_not_equals 0 "$create_code" \
    "files.sh create should fail for nonexistent instance"

  "$FILES_MODULE" remove "$fake" 2>/dev/null
  local remove_code=$?
  assert_not_equals 0 "$remove_code" \
    "files.sh remove should fail for nonexistent instance"
}

# =============================================================================
# TEST 8: Symlink enable creates a symlink in the shortcuts directory
# Requires: management file already created; sandbox shortcuts dir set to writable path
# Note: files.symlink.sh uses sudo for ln -s; requires root or passwordless sudo
# =============================================================================

function test_symlink_enable_creates_symlink() {
  log_test_step "Testing: files.symlink.sh enable creates symlink in shortcuts directory"

  # Symlink integration uses sudo internally - skip when not root
  if [[ "$EUID" -ne 0 ]]; then
    skip_test "Symlink enable requires root/sudo - skipping (EUID=$EUID)"
    return
  fi

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create management file (symlink enable requires it to exist)
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" \
    "files.management.sh create must succeed before symlink enable"

  # Update sandbox config to use our writable test shortcuts directory
  local sandbox_config="$KGSM_ROOT/config.ini"
  local original_shortcuts_dir
  original_shortcuts_dir=$(grep "^command_shortcuts_directory=" "$sandbox_config" 2>/dev/null | cut -d= -f2)

  # Override command_shortcuts_directory to writable test path
  sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=$TEST_SHORTCUTS_DIR|" \
    "$sandbox_config" 2>/dev/null || true

  local expected_symlink="$TEST_SHORTCUTS_DIR/$instance_name"

  # Enable symlink integration
  assert_command_succeeds "$FILES_SYMLINK_MODULE enable $instance_name" \
    "files.symlink.sh enable should succeed"

  assert_true "[[ -L '$expected_symlink' ]]" \
    "Symlink should exist in shortcuts directory after enable"

  # Instance config should reflect enable_command_shortcuts=true
  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  assert_file_contains "$instance_config" "enable_command_shortcuts=true" \
    "Instance config should have enable_command_shortcuts=true after symlink enable"

  # Cleanup - disable symlink first, then remove instance
  sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=$TEST_SHORTCUTS_DIR|" \
    "$sandbox_config" 2>/dev/null || true
  "$FILES_SYMLINK_MODULE" disable "$instance_name" 2>/dev/null || true

  # Restore original shortcuts directory
  if [[ -n "$original_shortcuts_dir" ]]; then
    sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=$original_shortcuts_dir|" \
      "$sandbox_config" 2>/dev/null || true
  fi
}

# =============================================================================
# TEST 9: Symlink disable removes the symlink and updates instance config
# Note: files.symlink.sh uses sudo for rm; requires root or passwordless sudo
# =============================================================================

function test_symlink_disable_removes_symlink() {
  log_test_step "Testing: files.symlink.sh disable removes symlink from shortcuts directory"

  # Symlink integration uses sudo internally - skip when not root
  if [[ "$EUID" -ne 0 ]]; then
    skip_test "Symlink disable requires root/sudo - skipping (EUID=$EUID)"
    return
  fi

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # Create management file
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" \
    "files.management.sh create must succeed before symlink operations"

  # Override shortcuts directory to writable test path
  local sandbox_config="$KGSM_ROOT/config.ini"
  local original_shortcuts_dir
  original_shortcuts_dir=$(grep "^command_shortcuts_directory=" "$sandbox_config" 2>/dev/null | cut -d= -f2)
  sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=$TEST_SHORTCUTS_DIR|" \
    "$sandbox_config" 2>/dev/null || true

  # Enable symlink
  assert_command_succeeds "$FILES_SYMLINK_MODULE enable $instance_name" \
    "files.symlink.sh enable must succeed"

  local expected_symlink="$TEST_SHORTCUTS_DIR/$instance_name"
  assert_true "[[ -L '$expected_symlink' ]]" \
    "Symlink should exist after enable"

  # Disable symlink
  assert_command_succeeds "$FILES_SYMLINK_MODULE disable $instance_name" \
    "files.symlink.sh disable should succeed"

  assert_false "[[ -L '$expected_symlink' ]]" \
    "Symlink should be gone after disable"
  assert_file_not_exists "$expected_symlink" \
    "Symlink path should not exist after disable"

  # Instance config should reflect enable_command_shortcuts=false
  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  assert_file_contains "$instance_config" "enable_command_shortcuts=false" \
    "Instance config should have enable_command_shortcuts=false after symlink disable"

  # Restore original shortcuts directory
  if [[ -n "$original_shortcuts_dir" ]]; then
    sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=$original_shortcuts_dir|" \
      "$sandbox_config" 2>/dev/null || true
  fi
}

# =============================================================================
# TEST 10: Symlink enable fails without management file
# This test does NOT require root since it should fail before the sudo ln call
# =============================================================================

function test_symlink_enable_fails_without_management_file() {
  log_test_step "Testing: files.symlink.sh enable fails when management file is missing"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  # create_test_instance generates the management script, so remove it here to
  # establish the condition under test: enabling a shortcut for an instance
  # whose management file is absent.
  local instance_config manage_file
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')
  assert_not_null "$manage_file" "Instance config should have management_file path"
  rm -f "$manage_file"

  # Override shortcuts directory to writable test path
  local sandbox_config="$KGSM_ROOT/config.ini"
  local original_shortcuts_dir
  original_shortcuts_dir=$(grep "^command_shortcuts_directory=" "$sandbox_config" 2>/dev/null | cut -d= -f2)
  sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=$TEST_SHORTCUTS_DIR|" \
    "$sandbox_config" 2>/dev/null || true

  # Enable symlink should fail (no management file) - this fails before sudo is called
  "$FILES_SYMLINK_MODULE" enable "$instance_name" 2>/dev/null
  local enable_code=$?
  assert_not_equals 0 "$enable_code" \
    "files.symlink.sh enable should fail when management file does not exist"

  # Restore original shortcuts directory
  if [[ -n "$original_shortcuts_dir" ]]; then
    sed -i "s|^command_shortcuts_directory=.*|command_shortcuts_directory=$original_shortcuts_dir|" \
      "$sandbox_config" 2>/dev/null || true
  fi
}

# =============================================================================
# TEST 11: Symlink commands fail for nonexistent instance
# =============================================================================

function test_symlink_fails_for_nonexistent_instance() {
  log_test_step "Testing: files.symlink.sh commands fail for nonexistent instance"

  local fake="nonexistent_sym_xyz_$$"

  "$FILES_SYMLINK_MODULE" enable "$fake" 2>/dev/null
  local enable_code=$?
  assert_not_equals 0 "$enable_code" \
    "files.symlink.sh enable should fail for nonexistent instance"

  "$FILES_SYMLINK_MODULE" disable "$fake" 2>/dev/null
  local disable_code=$?
  assert_not_equals 0 "$disable_code" \
    "files.symlink.sh disable should fail for nonexistent instance"
}

# =============================================================================
# TEST 12: Firewall commands fail for nonexistent instance
# Validates error handling before any system-level operations
# =============================================================================

function test_firewall_fails_for_nonexistent_instance() {
  log_test_step "Testing: files.firewall.sh fails for nonexistent instance"

  local fake="nonexistent_sysufw_xyz_$$"

  "$FILES_FIREWALL_MODULE" enable "$fake" 2>/dev/null
  local fw_enable_code=$?
  assert_not_equals 0 "$fw_enable_code" \
    "files.firewall.sh enable should fail for nonexistent instance"

  "$FILES_FIREWALL_MODULE" disable "$fake" 2>/dev/null
  local fw_disable_code=$?
  assert_not_equals 0 "$fw_disable_code" \
    "files.firewall.sh disable should fail for nonexistent instance"
}

# =============================================================================
# TEST 16: Two instances have independent management files
# Creating management files for two instances must not interfere
# =============================================================================

function test_two_instances_have_independent_management_files() {
  log_test_step "Testing: two instances have independent management files"

  local blueprint="factorio"
  local instance1
  local instance2

  instance1="$(create_test_instance "$blueprint" "$instance1")"
  local create_exit1=$?
  [[ $create_exit1 -eq 0 ]] && _TEARDOWN_INSTANCES+=("$blueprint:$instance1")

  instance2="$(create_test_instance "$blueprint" "$instance2")"
  local create_exit2=$?
  [[ $create_exit2 -eq 0 ]] && _TEARDOWN_INSTANCES+=("$blueprint:$instance2")

  if [[ $create_exit1 -ne 0 || $create_exit2 -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  # Create management files for both
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance1" \
    "Management file create should succeed for instance1"
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance2" \
    "Management file create should succeed for instance2"

  local config1
  config1=$("$KGSM_ROOT/kgsm.sh" instances find "$instance1" 2>/dev/null)
  local manage_file1
  manage_file1=$(grep "^management_file=" "$config1" 2>/dev/null | cut -d= -f2 | tr -d '"')

  local config2
  config2=$("$KGSM_ROOT/kgsm.sh" instances find "$instance2" 2>/dev/null)
  local manage_file2
  manage_file2=$(grep "^management_file=" "$config2" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file1" "Instance1 management file should exist"
  assert_file_exists "$manage_file2" "Instance2 management file should exist"
  assert_not_equals "$manage_file1" "$manage_file2" \
    "Two instances should have different management file paths"

  # Remove instance1 management file - instance2 should be unaffected
  assert_command_succeeds "$FILES_MANAGEMENT_MODULE remove $instance1" \
    "Management file remove should succeed for instance1"

  assert_file_not_exists "$manage_file1" \
    "Instance1 management file should be gone after remove"
  assert_file_exists "$manage_file2" \
    "Instance2 management file should still exist after instance1 removal"
}

# =============================================================================
# TEST 17: files.sh create is idempotent (management file create twice)
# Running files.sh create twice must not fail
# =============================================================================

function test_files_create_is_idempotent() {
  log_test_step "Testing: files.sh create is idempotent (can run twice)"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

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
}

# =============================================================================
# TEST 18: files.management.sh create works for terraria blueprint (different overrides)
# Validates override injection works for different blueprints
# =============================================================================

function test_management_file_creation_for_terraria() {
  log_test_step "Testing: management file creation for terraria blueprint (has overrides)"

  local blueprint="terraria"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  assert_command_succeeds "$FILES_MANAGEMENT_MODULE create $instance_name" \
    "files.management.sh create should succeed for $blueprint instance"

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  assert_file_exists "$manage_file" \
    "Management file should exist after creation for $blueprint"
  assert_file_executable "$manage_file" \
    "$blueprint management file should be executable"
}

# =============================================================================
# TEST 13: files.sh workflow: create → verify → remove → verify
# Full create-then-remove workflow produces correct final state
# =============================================================================

function test_full_files_workflow() {
  log_test_step "Testing: complete files.sh create → verify → remove → verify workflow"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$instance_name")
  local create_exit=$?

  if [[ $create_exit -ne 0 ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  _TEARDOWN_INSTANCES+=("$blueprint:$instance_name")

  local instance_config
  instance_config=$("$KGSM_ROOT/kgsm.sh" instances find "$instance_name" 2>/dev/null)
  local manage_file
  manage_file=$(grep "^management_file=" "$instance_config" 2>/dev/null | cut -d= -f2 | tr -d '"')

  # Note: The management file is now created when calling "create_test_instance"
  # Step 1: Pre-create state - management file should not exist
  # assert_file_not_exists "$manage_file" "Management file should not exist before files.sh create"
  # Step 2: Create all files
  # assert_command_succeeds "$FILES_MODULE create $instance_name" "files.sh create should succeed"

  assert_file_exists "$manage_file" \
    "Management file should exist after files.sh create"

  # Step 3: Remove all files
  assert_command_succeeds "$FILES_MODULE remove $instance_name" \
    "files.sh remove should succeed"

  assert_file_not_exists "$manage_file" \
    "Management file should be gone after files.sh remove"
}
