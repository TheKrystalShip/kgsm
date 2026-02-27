#!/usr/bin/env bash

# KGSM Configuration Commands Integration Tests
#
# Tests the config command CLI (merge, rollback, diff, validate)

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="config_commands"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up config commands integration tests"

  # Verify config command exists
  assert_file_exists "$KGSM_ROOT/commands/config.sh" "config command should exist"

  log_test_step "Config commands test environment validated"
}

# =============================================================================
# TEST: config merge - Merges User Config with Defaults
# =============================================================================

function test_config_merge_command() {
  log_test_step "Testing ./kgsm.sh config merge command"

  # Create test user config that's already at schema v1 (to avoid migration)
  cat > "$CONFIG_FILE" << 'EOF'
config_schema_version=1

[system]
update_channel=dev
enable_logging=true
old_deprecated_key=value

[network]
enable_firewall_management=false
EOF

  # Run merge command
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config merge 2>&1)
  local exit_code=$?

  # Should return success code for merged config
  assert_equals "$exit_code" "$EC_SUCCESS_CONFIG_MERGED" "Merge command should return success code"

  # Verify user value preserved
  assert_command_succeeds "grep -q 'update_channel=dev' '$CONFIG_FILE'"

  # Verify new keys added
  assert_command_succeeds "grep -q 'wget_timeout_seconds=' '$CONFIG_FILE'"

  # Verify deprecated key commented out
  assert_command_succeeds "grep -q 'DEPRECATED.*old_deprecated_key' '$CONFIG_FILE'"

  # Verify backup created
  assert_file_exists "${CONFIG_FILE}.0"

  # Verify schema version maintained
  assert_command_succeeds "grep -q '^config_schema_version=1' '$CONFIG_FILE'"
}

# =============================================================================
# TEST: config rollback - Restores Previous Backup
# =============================================================================

function test_config_rollback_command() {
  log_test_step "Testing ./kgsm.sh config rollback command"

  # Create initial config
  cat > "$CONFIG_FILE" << 'EOF'
config_schema_version=1
[system]
update_channel=stable
EOF

  # Create backup
  cp "$CONFIG_FILE" "${CONFIG_FILE}.0"

  # Modify current config
  cat > "$CONFIG_FILE" << 'EOF'
config_schema_version=1
[system]
update_channel=modified
EOF

  # Run rollback command
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config rollback 0 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "Rollback should succeed"

  # Verify config was restored (without ^ anchor since it might have spaces)
  assert_command_succeeds "grep -q 'update_channel=stable' '$CONFIG_FILE'"

  # Verify it doesn't contain the modified value
  assert_command_fails "grep -q 'update_channel=modified' '$CONFIG_FILE'"
}

# =============================================================================
# TEST: config rollback - Handles Invalid Generation
# =============================================================================

function test_config_rollback_invalid_generation() {
  log_test_step "Testing config rollback with invalid generation"

  # Try to rollback to non-existent backup
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config rollback 9 2>&1)
  local exit_code=$?

  # Should fail with file not found
  assert_equals "$exit_code" "$EC_FILE_NOT_FOUND" "Should fail with file not found error"

  # Error message should mention backup not found
  assert_contains "$output" "Backup not found" "Should indicate backup not found"
}

# =============================================================================
# TEST: config diff - Shows Differences from Backup
# =============================================================================

function test_config_diff_command() {
  log_test_step "Testing ./kgsm.sh config diff command"

  # Create backup with different content
  cat > "${CONFIG_FILE}.0" << 'EOF'
config_schema_version=1
[system]
update_channel=stable
EOF

  # Create current config with changes
  cat > "$CONFIG_FILE" << 'EOF'
config_schema_version=1
[system]
update_channel=dev
enable_logging=true
EOF

  # Run diff command
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config diff 0 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "0" "Diff should succeed"

  # Output should contain diff markers
  assert_contains "$output" "update_channel" "Diff should show changed key"
}

# =============================================================================
# TEST: config diff - Handles Missing Backup
# =============================================================================

function test_config_diff_missing_backup() {
  log_test_step "Testing config diff with missing backup"

  # Remove any backups
  rm -f "${CONFIG_FILE}".{0..9}

  # Try to diff against non-existent backup
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config diff 0 2>&1)
  local exit_code=$?

  assert_equals "$exit_code" "$EC_FILE_NOT_FOUND" "Should fail with file not found"
  assert_contains "$output" "Backup not found" "Should indicate backup not found"
}

# =============================================================================
# TEST: config validate - Validates Current Config
# =============================================================================

function test_config_validate_command() {
  log_test_step "Testing ./kgsm.sh config validate command"

  # Create valid config
  cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"

  # Run validate command
  local output
  output=$("$KGSM_ROOT/kgsm.sh" config validate 2>&1)
  local exit_code=$?

  # Config validate returns EC_SUCCESS_CONFIG_VALIDATED (242)
  assert_equals "$EC_SUCCESS_CONFIG_VALIDATED" "$exit_code" "Valid config should pass validation"
}

# =============================================================================
# TEST: config help - Shows Command Help
# =============================================================================

function test_config_help_commands() {
  log_test_step "Testing config help for new commands"

  # Test merge help
  local merge_help
  merge_help=$("$KGSM_ROOT/kgsm.sh" config help merge 2>&1)
  assert_contains "$merge_help" "Merge user configuration" "Should show merge help"

  # Test rollback help
  local rollback_help
  rollback_help=$("$KGSM_ROOT/kgsm.sh" config help rollback 2>&1)
  assert_contains "$rollback_help" "Rollback configuration" "Should show rollback help"

  # Test diff help
  local diff_help
  diff_help=$("$KGSM_ROOT/kgsm.sh" config help diff 2>&1)
  assert_contains "$diff_help" "Show differences" "Should show diff help"
}

