#!/usr/bin/env bash

# KGSM Configuration Workflow E2E Tests
#
# Test Type: E2E
# Target: Complete configuration management workflow
#
# Tests the full config lifecycle:
#   validate → merge → backup creation → diff → rollback → validate after rollback
#   Plus: key access, error handling, and file integrity

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="configuration_workflow_e2e"
readonly CONFIG_MODULE="$KGSM_ROOT/commands/config.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up configuration workflow E2E tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$CONFIG_MODULE" "commands/config.sh should exist"
  assert_file_executable "$CONFIG_MODULE" "commands/config.sh should be executable"
  assert_file_exists "$KGSM_ROOT/kgsm.sh" "kgsm.sh should exist"

  # Ensure config file starts from a clean known state
  if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
    cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
  fi

  # Clean up any leftover backup files from previous test runs
  rm -f "${CONFIG_FILE}".{0..9} 2>/dev/null || true

  log_test_step "Configuration workflow E2E environment validated"
}

function teardown_file() {
  log_test_step "Cleaning up configuration workflow E2E tests"

  # Remove any backup files created during tests
  rm -f "${CONFIG_FILE}".{0..9} 2>/dev/null || true

  # Restore config to defaults
  if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
    cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
  fi

  log_test_step "Configuration workflow E2E cleanup complete"
}

# =============================================================================
# TEST 1: config validate - Valid Config Passes
# =============================================================================

function test_config_validate_with_valid_config() {
  log_test_step "Testing config validate succeeds with a valid default config"

  local output
  output=$("$KGSM_ROOT/kgsm.sh" config validate 2>&1)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$exit_code" \
    "Config validate should return EC_SUCCESS_CONFIG_VALIDATED with valid config"
  assert_contains "$output" "validation passed" \
    "Output should indicate validation passed"
}

# =============================================================================
# TEST 2: config merge - Merges with Defaults and Creates Backup
# =============================================================================

function test_config_merge_creates_backup() {
  log_test_step "Testing config merge creates a backup and succeeds"

  # Ensure no .0 backup exists before merge
  rm -f "${CONFIG_FILE}.0" 2>/dev/null || true

  local output
  output=$("$KGSM_ROOT/kgsm.sh" config merge 2>&1)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_CONFIG_MERGED" "$exit_code" \
    "Config merge should return EC_SUCCESS_CONFIG_MERGED"
  assert_contains "$output" "merged successfully" \
    "Output should indicate successful merge"

  # Verify backup was created
  assert_file_exists "${CONFIG_FILE}.0" \
    "Backup file .0 should be created after merge"
}

# =============================================================================
# TEST 3: Backup Integrity - Backup Is a Valid INI File
# =============================================================================

function test_backup_is_valid_ini() {
  log_test_step "Testing that the created backup file is a valid INI file"

  # Backup should exist from previous test; recreate if not
  if [[ ! -f "${CONFIG_FILE}.0" ]]; then
    "$KGSM_ROOT/kgsm.sh" config merge >/dev/null 2>&1
  fi

  assert_file_exists "${CONFIG_FILE}.0" "Backup file should exist"

  # A valid INI file should contain at least one key=value pair
  local kv_count
  kv_count=$(grep -c '^[a-zA-Z_].*=' "${CONFIG_FILE}.0" 2>/dev/null || true)
  assert_greater_than "$kv_count" 0 \
    "Backup file should contain key=value pairs"

  # Should contain the schema version marker
  assert_file_contains "${CONFIG_FILE}.0" "config_schema_version" \
    "Backup file should contain config_schema_version"
}

# =============================================================================
# TEST 4: config diff - Shows Differences from Backup
# =============================================================================

function test_config_diff_with_backup() {
  log_test_step "Testing config diff 0 shows diff output"

  # Ensure we have a backup - make a small change and merge
  if [[ ! -f "${CONFIG_FILE}.0" ]]; then
    # Create a backup manually with known different content
    cp "$CONFIG_FILE" "${CONFIG_FILE}.0"
    # Slightly modify the current config to produce a diff
    echo "# test_diff_marker" >> "$CONFIG_FILE"
  else
    # Slightly modify the current config to produce a diff
    echo "# test_diff_marker" >> "$CONFIG_FILE"
  fi

  local output
  output=$("$KGSM_ROOT/kgsm.sh" config diff 0 2>&1)
  local exit_code=$?

  assert_equals "0" "$exit_code" \
    "Config diff should succeed when backup exists"
  assert_not_null "$output" \
    "Config diff should produce output"

  # Remove the temporary marker line
  sed -i '/# test_diff_marker/d' "$CONFIG_FILE"
}

# =============================================================================
# TEST 5: config diff - Missing Backup Fails Gracefully
# =============================================================================

function test_config_diff_missing_backup_fails() {
  log_test_step "Testing config diff fails gracefully when backup does not exist"

  # Remove generation 9 backup (should not exist normally)
  rm -f "${CONFIG_FILE}.9" 2>/dev/null || true

  local output
  output=$("$KGSM_ROOT/kgsm.sh" config diff 9 2>&1)
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Config diff should fail with EC_FILE_NOT_FOUND when backup missing"
  assert_contains "$output" "Backup not found" \
    "Output should indicate backup not found"
}

# =============================================================================
# TEST 6: config rollback - Restores from Backup
# =============================================================================

function test_config_rollback_restores_from_backup() {
  log_test_step "Testing config rollback 0 restores config from backup"

  # Set a known value in config and create backup
  cat > "$CONFIG_FILE" << 'EOF'
config_schema_version=1

[system]
update_channel=stable
enable_logging=false
EOF
  cp "$CONFIG_FILE" "${CONFIG_FILE}.0"

  # Modify current config to a different value
  cat > "$CONFIG_FILE" << 'EOF'
config_schema_version=1

[system]
update_channel=modified_value
enable_logging=true
EOF

  # Verify the modification is in place
  assert_file_contains "$CONFIG_FILE" "update_channel=modified_value" \
    "Config should have the modified value before rollback"

  # Perform rollback
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config rollback 0 2>&1)
  local exit_code=$?

  assert_equals "0" "$exit_code" \
    "Config rollback should succeed"
  assert_contains "$output" "rolled back" \
    "Output should confirm rollback occurred"

  # Verify the original value is restored
  assert_file_contains "$CONFIG_FILE" "update_channel=stable" \
    "Config should be restored to original value after rollback"

  # Verify the modified value is gone
  assert_command_fails "grep -q 'update_channel=modified_value' '$CONFIG_FILE'" \
    "Modified value should not be present after rollback"
}

# =============================================================================
# TEST 7: Config Validate After Rollback
# =============================================================================

function test_config_validate_after_rollback() {
  log_test_step "Testing config validate passes after rollback operation"

  # Restore a full valid config, create backup, and rollback to it
  cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
  cp "$CONFIG_FILE" "${CONFIG_FILE}.0"

  "$KGSM_ROOT/kgsm.sh" config rollback 0 >/dev/null 2>&1

  # Now validate the restored config
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config validate 2>&1)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$exit_code" \
    "Config validate should pass after rollback to valid backup"
}

# =============================================================================
# TEST 8: Config Key Access - Keys Are Readable
# =============================================================================

function test_config_key_access() {
  log_test_step "Testing that key config values are accessible via config get"

  # Restore defaults for clean key access test
  cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"

  # Test reading enable_logging
  local enable_logging
  enable_logging=$("$KGSM_ROOT/kgsm.sh" config get enable_logging 2>&1)
  local exit_code=$?
  assert_equals "0" "$exit_code" \
    "config get enable_logging should succeed"
  assert_not_null "$enable_logging" \
    "enable_logging should have a value"

  # Test reading wget_timeout_seconds
  local wget_timeout
  wget_timeout=$("$KGSM_ROOT/kgsm.sh" config get wget_timeout_seconds 2>&1)
  assert_equals "0" "$?" \
    "config get wget_timeout_seconds should succeed"
  assert_matches "$wget_timeout" "^[0-9]+$" \
    "wget_timeout_seconds should be a numeric value"

  # Test reading instance_suffix_length
  local suffix_len
  suffix_len=$("$KGSM_ROOT/kgsm.sh" config get instance_suffix_length 2>&1)
  assert_equals "0" "$?" \
    "config get instance_suffix_length should succeed"
  assert_matches "$suffix_len" "^[0-9]+$" \
    "instance_suffix_length should be a numeric value"
}

# =============================================================================
# TEST 9: Invalid Rollback Generation - Fails Gracefully
# =============================================================================

function test_config_rollback_nonexistent_backup_fails() {
  log_test_step "Testing config rollback fails gracefully for nonexistent backup"

  # Ensure backup 8 does not exist
  rm -f "${CONFIG_FILE}.8" 2>/dev/null || true

  local output
  output=$("$KGSM_ROOT/kgsm.sh" config rollback 8 2>&1)
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Config rollback should fail with EC_FILE_NOT_FOUND for nonexistent backup"
  assert_contains "$output" "Backup not found" \
    "Output should indicate backup was not found"
}

# =============================================================================
# TEST 10: config list - Lists All Config Keys
# =============================================================================

function test_config_list_shows_all_keys() {
  log_test_step "Testing config list shows key configuration entries"

  cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"

  local output
  output=$("$KGSM_ROOT/kgsm.sh" config list 2>&1)
  local exit_code=$?

  assert_equals "0" "$exit_code" \
    "config list should succeed"
  assert_contains "$output" "enable_logging" \
    "config list should contain enable_logging"
  assert_contains "$output" "wget_timeout_seconds" \
    "config list should contain wget_timeout_seconds"
  assert_contains "$output" "instance_suffix_length" \
    "config list should contain instance_suffix_length"
}

# =============================================================================
# TEST 11: Config File Integrity After All Operations
# =============================================================================

function test_config_file_integrity_after_operations() {
  log_test_step "Testing config.ini is a valid INI file after all operations"

  # Run a merge to ensure config is fully normalized
  cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
  "$KGSM_ROOT/kgsm.sh" config merge >/dev/null 2>&1

  assert_file_exists "$CONFIG_FILE" \
    "config.ini should still exist after operations"

  # Should still contain the schema version
  assert_file_contains "$CONFIG_FILE" "config_schema_version" \
    "config.ini should contain config_schema_version after operations"

  # Should contain key=value pairs (valid INI format)
  local kv_count
  kv_count=$(grep -c '^[a-zA-Z_].*=' "$CONFIG_FILE" 2>/dev/null || true)
  assert_greater_than "$kv_count" 5 \
    "config.ini should contain multiple key=value pairs"

  # Config should still pass validation
  local exit_code
  "$KGSM_ROOT/kgsm.sh" config validate >/dev/null 2>&1
  exit_code=$?
  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$exit_code" \
    "config.ini should pass validation after all E2E operations"
}

# =============================================================================
# CLEANUP
# =============================================================================

function teardown_file() {
  log_test_step "Cleaning up E2E test artifacts"

  # Remove any backup files created during tests
  rm -f "${CONFIG_FILE}".{0..9} 2>/dev/null || true

  # Restore config to defaults
  if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
    cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
  fi
}

