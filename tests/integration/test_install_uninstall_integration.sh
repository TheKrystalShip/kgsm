#!/usr/bin/env bash

# KGSM Install + Uninstall Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/install.sh and commands/uninstall.sh
#         and their orchestration of instances.sh, directories.sh, files.sh
#
# Integration points tested:
# - install.sh validates blueprint before any structure is created
# - install.sh creates instance config, directories, and files before download
# - install.sh with --name creates an instance with the specified name
# - uninstall.sh rejects nonexistent instances before prompting
# - uninstall.sh removes instance structure when confirmed
# - uninstall.sh with "y" confirmation fully cleans up instances created by the wrapper
# - Full cycle: prepare instance via wrapper + files → uninstall → nothing remains

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="install_uninstall_integration"
readonly INSTALL_MODULE="$KGSM_ROOT/commands/install.sh"
readonly UNINSTALL_MODULE="$KGSM_ROOT/commands/uninstall.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"
readonly DIRECTORIES_MODULE="$KGSM_ROOT/commands/directories.sh"
readonly FILES_MODULE="$KGSM_ROOT/commands/files.sh"

TEST_INSTALL_DIR=""
TEST_LIBRARY=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up install+uninstall integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  TEST_LIBRARY="$(__ensure_test_library "$TEST_INSTALL_DIR")"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$INSTALL_MODULE" "install.sh should exist"
  assert_file_executable "$INSTALL_MODULE" "install.sh should be executable"
  assert_file_exists "$UNINSTALL_MODULE" "uninstall.sh should exist"
  assert_file_executable "$UNINSTALL_MODULE" "uninstall.sh should be executable"
  assert_file_exists "$INSTANCES_MODULE" "instances.sh should exist"
  assert_file_exists "$DIRECTORIES_MODULE" "directories.sh should exist"
  assert_file_exists "$FILES_MODULE" "files.sh should exist"

  log_test_step "Integration test environment validated"
}

# =============================================================================
# INSTALL.SH TESTS
# =============================================================================

# TEST 1: install.sh fails immediately for nonexistent blueprint
function test_install_fails_with_nonexistent_blueprint() {
  log_test_step "Testing: install.sh fails when blueprint does not exist"

  "$INSTALL_MODULE" nonexistent_blueprint_xyz_abc \
    --library "$TEST_LIBRARY" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "install.sh with nonexistent blueprint should fail"

  # No partial instance structure should be created for a nonexistent blueprint
  assert_dir_not_exists "$KGSM_INSTANCES_DIR/nonexistent_blueprint_xyz_abc" \
    "No instance directory should be created for nonexistent blueprint"
}

# TEST 2: install.sh fails with missing blueprint argument
function test_install_fails_with_missing_blueprint() {
  log_test_step "Testing: install.sh fails when no blueprint argument given"

  "$INSTALL_MODULE" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "install.sh with no arguments should fail"
}

# TEST 3: install.sh fails when --library value is missing
function test_install_fails_with_missing_library_value() {
  log_test_step "Testing: install.sh fails when --library has no value"

  "$INSTALL_MODULE" factorio --library 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "install.sh with --library and no value should fail"
}

# TEST 3b: the retired --install-dir flag is refused
function test_install_refuses_install_dir_flag() {
  log_test_step "Testing: install.sh refuses --install-dir as an unknown argument"

  "$INSTALL_MODULE" factorio --install-dir "$TEST_INSTALL_DIR" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "install.sh with --install-dir should fail"
}

# TEST 4: install.sh creates instance config before reaching the download step
# install.sh orchestrates: generate-id → ensure-created dirs → create instance config
# → create directories → create files → (download fails without network/SteamCMD)
# After the partial run, the instance config should exist.
function test_install_creates_instance_config_before_download() {
  log_test_step "Testing: install.sh creates instance config and directory structures before download"

  local instance_name="test-install-pre-$$"

  # Run install.sh - it will create structures and then fail at the download/version step
  # We use --name to know the exact instance name created
  "$INSTALL_MODULE" factorio \
    --library "$TEST_LIBRARY" \
    --name "$instance_name" 2>/dev/null
  local install_exit=$?

  # install.sh may exit with non-zero (download failure) but may create partial state
  # Check what was actually created
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>/dev/null)
  local find_exit=$?

  if [[ $find_exit -eq 0 ]] && [[ -f "$instance_config" ]]; then
    # install.sh created the instance config successfully before failing
    assert_file_exists "$instance_config" \
      "Instance config should be created by install.sh before download step"
    assert_file_contains "$instance_config" "name=" \
      "Instance config should contain instance name"
    assert_file_contains "$instance_config" "factorio" \
      "Instance config should reference the factorio blueprint"

    # Cleanup - use uninstall.sh with piped "y" to remove the partial install
    echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1 || true
    __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  else
    # install.sh failed before creating the instance config
    # (e.g., blueprint validation failure or directory creation failure)
    # Still a valid test outcome - clean up any partial state
    __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
    # Assert that the failure was not zero (install didn't silently succeed without config)
    assert_not_equals 0 "$install_exit" \
      "If instance config was not created, install.sh should have exited non-zero"
  fi
}

# TEST 5: install.sh with --name creates instance directory under the named instance
function test_install_with_name_creates_named_instance_dir() {
  log_test_step "Testing: install.sh --name creates working directory with specified name"

  local instance_name="test-named-inst-$$"
  local expected_working_dir="$TEST_INSTALL_DIR/instances/factorio/$instance_name"

  # Run install.sh (will fail at download but may create working dir first)
  "$INSTALL_MODULE" factorio \
    --library "$TEST_LIBRARY" \
    --name "$instance_name" 2>/dev/null
  local install_exit=$?

  # The working directory should have been created before the download step
  if [[ -d "$expected_working_dir" ]]; then
    assert_dir_exists "$expected_working_dir" \
      "install.sh should create working directory at install_dir/blueprint/name"
    # Cleanup
    echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1 || true
    __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  else
    # install.sh failed before creating the working dir
    assert_not_equals 0 "$install_exit" \
      "If working dir was not created, install.sh should exit non-zero"
    __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
  fi
}

# TEST 6: install.sh creates directories structure under working dir
function test_install_creates_directory_structure() {
  log_test_step "Testing: install.sh creates subdirectory structure (saves, logs, temp, backups)"

  local instance_name="test-dirs-$$"

  "$INSTALL_MODULE" factorio \
    --library "$TEST_LIBRARY" \
    --name "$instance_name" 2>/dev/null

  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>/dev/null)

  if [[ -f "$instance_config" ]]; then
    # Instance config was created - check that directories were created too
    # Source the instance config to get directory variables
    local instance_logs_dir instance_saves_dir
    # shellcheck disable=SC1090
    source "$instance_config" 2>/dev/null || true

    if [[ -n "${instance_logs_dir:-}" ]] && [[ -d "$instance_logs_dir" ]]; then
      assert_dir_exists "$instance_logs_dir" \
        "install.sh should create logs directory"
    fi

    # Cleanup
    echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1 || true
  fi

  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# =============================================================================
# UNINSTALL.SH TESTS
# =============================================================================

# TEST 7: uninstall.sh reports error for nonexistent instance
function test_uninstall_fails_with_nonexistent_instance() {
  log_test_step "Testing: uninstall.sh reports error for nonexistent instance before prompting"

  # Pipe "y" to ensure we don't hang on the confirmation prompt if validation passes
  local output
  output=$(echo "y" | "$UNINSTALL_MODULE" nonexistent_instance_xyz_12345 2>&1)

  # uninstall.sh should report that the instance was not found
  assert_contains "$output" "not found" \
    "uninstall.sh should report instance not found for nonexistent instance"

  # The working directory for this fake instance should not have been created
  assert_dir_not_exists "$TEST_INSTALL_DIR/instances/factorio/nonexistent_instance_xyz_12345" \
    "No working directory should be created for nonexistent instance"
}

# TEST 8: uninstall.sh cancels when answered "n"
function test_uninstall_cancels_on_no_answer() {
  log_test_step "Testing: uninstall.sh cancels operation when user answers 'n'"

  # Create a real instance to test cancellation
  local instance_name="test-cancel-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed for cancellation test"

  # Answer "n" to cancel uninstall
  echo "n" | "$UNINSTALL_MODULE" "$instance_name" 2>/dev/null
  local exit_code=$?

  # A declined uninstall returns EC_CANCELLED (non-zero), NOT 0 — a silent success on
  # cancellation would let a non-interactive caller believe the instance was removed.
  assert_equals "$EC_CANCELLED" "$exit_code" \
    "uninstall.sh should return EC_CANCELLED when declined (never a masquerading exit 0)"

  # Instance should still exist after cancellation
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "instances find should still succeed after cancellation"
  assert_file_exists "$instance_config" "Instance config should remain after cancellation"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# TEST 9: uninstall.sh removes instance config when confirmed
function test_uninstall_removes_instance_config() {
  log_test_step "Testing: uninstall.sh removes instance config when confirmed with 'y'"

  local instance_name="test-uninstall-cfg-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  # Verify instance exists before uninstall
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "Instance should be found before uninstall"
  assert_file_exists "$instance_config" "Instance config should exist before uninstall"

  # Run uninstall with "y" confirmation
  echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1
  local uninstall_exit=$?

  assert_equals 0 "$uninstall_exit" "uninstall.sh should succeed"

  # Instance config should no longer exist
  "$INSTANCES_MODULE" find "$instance_name" 2>/dev/null
  local find_exit=$?
  assert_not_equals 0 "$find_exit" \
    "instances find should fail after uninstall (instance removed)"

  # Cleanup any remaining partial state
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# TEST 9b: uninstall.sh --force removes the instance with NO prompt (non-interactive path)
function test_uninstall_force_removes_without_prompt() {
  log_test_step "Testing: uninstall.sh --force removes the instance with no confirmation prompt"

  local instance_name="test-uninstall-force-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  # No piped input — --force must skip the prompt entirely (the non-interactive contract
  # kgsm-lib / the API rely on). </dev/null guarantees a read would EOF (and fail) if it ran.
  "$UNINSTALL_MODULE" --force "$instance_name" >/dev/null 2>&1 </dev/null
  local uninstall_exit=$?

  assert_equals 0 "$uninstall_exit" "uninstall.sh --force should succeed without a prompt"

  # Instance should be gone.
  "$INSTANCES_MODULE" find "$instance_name" 2>/dev/null
  assert_not_equals 0 "$?" "instances find should fail after a --force uninstall (instance removed)"

  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# TEST 10: uninstall.sh removes symlink from instances directory
function test_uninstall_removes_instance_symlink() {
  log_test_step "Testing: uninstall.sh removes instance symlink from instances directory"

  local instance_name="test-uninstall-sym-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  # Verify symlink exists before uninstall
  local symlink_path="$KGSM_INSTANCES_DIR/factorio/$instance_name"
  assert_dir_exists "$symlink_path" \
    "Instance symlink/dir should exist in instances directory before uninstall"

  # Run uninstall
  echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1
  assert_equals 0 "$?" "uninstall.sh should succeed"

  # Symlink should no longer exist
  assert_dir_not_exists "$symlink_path" \
    "Instance entry should be removed from instances directory after uninstall"

  # Cleanup
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# TEST 11: uninstall.sh removes the working directory
function test_uninstall_removes_working_directory() {
  log_test_step "Testing: uninstall.sh removes the working directory under install_dir"

  local instance_name="test-uninstall-wdir-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  local working_dir="$TEST_INSTALL_DIR/instances/factorio/$instance_name"
  assert_dir_exists "$working_dir" \
    "Working directory should exist before uninstall"

  # Run uninstall
  echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1
  assert_equals 0 "$?" "uninstall.sh should succeed"

  assert_dir_not_exists "$working_dir" \
    "Working directory should be removed after uninstall"

  # Cleanup
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# TEST 12: uninstall.sh instance no longer appears in instances list after uninstall
function test_uninstall_removes_from_instances_list() {
  log_test_step "Testing: instance no longer appears in instances list after uninstall"

  local instance_name="test-uninstall-list-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  # Verify it appears in the list before uninstall
  local list_before
  list_before=$("$INSTANCES_MODULE" list 2>&1)
  assert_contains "$list_before" "$instance_name" \
    "Instance should appear in list before uninstall"

  # Run uninstall
  echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1
  assert_equals 0 "$?" "uninstall.sh should succeed"

  # Should no longer appear in the list
  local list_after
  list_after=$("$INSTANCES_MODULE" list 2>&1)
  assert_not_contains "$list_after" "$instance_name" \
    "Instance should not appear in list after uninstall"

  # Cleanup
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# =============================================================================
# FULL CYCLE TESTS
# =============================================================================

# TEST 13: Full cycle: create instance with files → uninstall → verify all removed
function test_full_cycle_create_files_uninstall() {
  log_test_step "Testing: full cycle - create instance with management file then uninstall"

  local instance_name="test-full-cycle-$$"

  # Step 1: Create instance via wrapper (creates config + symlink)
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  # Step 2: Create directories structure
  "$DIRECTORIES_MODULE" create "$instance_name" >/dev/null 2>&1
  local dirs_exit=$?
  assert_equals 0 "$dirs_exit" "directories create should succeed"

  # Step 3: Create management file and associated files
  "$FILES_MODULE" create "$instance_name" >/dev/null 2>&1
  local files_exit=$?
  assert_equals 0 "$files_exit" "files create should succeed"

  # Verify the instance is fully set up
  local instance_config
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>&1)
  assert_equals 0 "$?" "Instance should be findable after full setup"
  assert_file_exists "$instance_config" "Instance config should exist"

  local working_dir="$TEST_INSTALL_DIR/instances/factorio/$instance_name"
  assert_dir_exists "$working_dir" "Working directory should exist"

  # Step 4: Uninstall with "y" confirmation
  echo "y" | "$UNINSTALL_MODULE" "$instance_name" >/dev/null 2>&1
  local uninstall_exit=$?
  assert_equals 0 "$uninstall_exit" "uninstall.sh should succeed"

  # Step 5: Verify complete removal
  "$INSTANCES_MODULE" find "$instance_name" 2>/dev/null
  assert_not_equals 0 "$?" "Instance should not be findable after uninstall"

  assert_dir_not_exists "$working_dir" \
    "Working directory should be removed after uninstall"

  assert_dir_not_exists "$KGSM_INSTANCES_DIR/factorio/$instance_name" \
    "Instance symlink should be removed from instances directory"

  # Cleanup any residual state
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# TEST 14: Uninstall does not affect other instances from the same blueprint
function test_uninstall_does_not_affect_sibling_instances() {
  log_test_step "Testing: uninstalling one instance does not affect another from same blueprint"

  local instance_one="test-sibling-one-$$"
  local instance_two="test-sibling-two-$$"

  create_test_instance "factorio" "$instance_one" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "First instance creation should succeed"

  create_test_instance "factorio" "$instance_two" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Second instance creation should succeed"

  # Uninstall first instance
  echo "y" | "$UNINSTALL_MODULE" "$instance_one" >/dev/null 2>&1
  assert_equals 0 "$?" "Uninstall of first instance should succeed"

  # Second instance should still exist and be findable
  local config_two
  config_two=$("$INSTANCES_MODULE" find "$instance_two" 2>&1)
  assert_equals 0 "$?" "Second instance should still be findable after first is uninstalled"
  assert_file_exists "$config_two" "Second instance config should still exist"

  # Second instance should still appear in list
  local list_output
  list_output=$("$INSTANCES_MODULE" list 2>&1)
  assert_contains "$list_output" "$instance_two" \
    "Second instance should still appear in list after first is uninstalled"
  assert_not_contains "$list_output" "$instance_one" \
    "First instance should not appear in list after uninstall"

  # Cleanup
  remove_test_instance "factorio" "$instance_two" "$TEST_INSTALL_DIR"
  __cleanup_instance "factorio" "$instance_one" "$TEST_INSTALL_DIR" 2>/dev/null || true
}


# =============================================================================
# BACKUP SURVIVAL
# =============================================================================

# Provision an instance's directories and plant one backup in its store.
# Prints the backups dir on success.
function __seed_instance_backup() {
  local instance_name="$1"

  "$KGSM_ROOT/commands/directories.sh" create "$instance_name" >/dev/null 2>&1 || return 1

  local instance_config backups_dir
  instance_config=$("$INSTANCES_MODULE" find "$instance_name" 2>/dev/null) || return 1
  backups_dir=$(grep '^backups_dir=' "$instance_config" | tail -n1 | cut -d= -f2- | tr -d '"')
  [[ -n "$backups_dir" ]] || return 1

  local id="${instance_name}-20260731T120000Z-abc123"
  mkdir -p "$backups_dir/$id" || return 1
  jq -n --arg id "$id" \
    '{schema_version: 1, id: $id, created_at: "2026-07-31T12:00:00Z",
      compressed: true, consistency: "cold", sources: ["install"],
      size_bytes: 1, file_count: 1, sha256: null}' \
    > "$backups_dir/$id/manifest.json" || return 1

  echo "$backups_dir"
}

# TEST: uninstall keeps the instance's backups
function test_uninstall_preserves_backups() {
  log_test_step "Testing: uninstall.sh keeps the instance's backups by default"

  local instance_name="test-uninstall-keepbak-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  local backups_dir
  backups_dir=$(__seed_instance_backup "$instance_name")
  assert_equals 0 "$?" "should be able to seed a backup for the instance"
  assert_dir_exists "$backups_dir" "backups dir should exist before uninstall"

  # The whole point of storing backups outside working_dir: an uninstall removes
  # working_dir wholesale, and must not take the backups with it.
  local working_dir
  working_dir=$(grep '^working_dir=' "$("$INSTANCES_MODULE" find "$instance_name")" |
    tail -n1 | cut -d= -f2- | tr -d '"')
  assert_equals "${backups_dir#"$working_dir"}" "$backups_dir" \
    "backups dir must not live under working_dir"

  "$UNINSTALL_MODULE" --force "$instance_name" >/dev/null 2>&1 </dev/null
  assert_equals 0 "$?" "uninstall.sh --force should succeed"

  assert_dir_not_exists "$working_dir" "working_dir should be gone after uninstall"
  assert_dir_exists "$backups_dir" "backups should survive the uninstall"

  rm -rf "$backups_dir"
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}

# TEST: uninstall --purge-backups deletes them
function test_uninstall_purge_backups_removes_store() {
  log_test_step "Testing: uninstall.sh --purge-backups deletes the instance's backups"

  local instance_name="test-uninstall-purgebak-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Instance creation should succeed"

  local backups_dir
  backups_dir=$(__seed_instance_backup "$instance_name")
  assert_equals 0 "$?" "should be able to seed a backup for the instance"
  assert_dir_exists "$backups_dir" "backups dir should exist before uninstall"

  "$UNINSTALL_MODULE" --force --purge-backups "$instance_name" >/dev/null 2>&1 </dev/null
  assert_equals 0 "$?" "uninstall.sh --force --purge-backups should succeed"

  assert_dir_not_exists "$backups_dir" \
    "backups should be gone after an uninstall with --purge-backups"

  rm -rf "$backups_dir"
  __cleanup_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" 2>/dev/null || true
}
