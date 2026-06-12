#!/usr/bin/env bash

# KGSM Configuration Migration Tests
#
# Tests migration scripts that transform config from one schema version to another

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="config_migrations"
readonly MIGRATION_DIR="$KGSM_ROOT/migrations/config"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up config migration tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$MIGRATION_DIR" "Migration directory should exist"

  # Verify migration scripts exist
  assert_file_exists "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "Migration 001 should exist"
  assert_file_executable "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "Migration 001 should be executable"
  assert_file_exists "$MIGRATION_DIR/002_v1_to_v2_add_cgroup_section.sh" "Migration 002 should exist"
  assert_file_executable "$MIGRATION_DIR/002_v1_to_v2_add_cgroup_section.sh" "Migration 002 should be executable"

  log_test_step "Config migration test environment validated"
}

# =============================================================================
# TEST: Migration 001 - Flat to Sectioned (Minimal Config)
# =============================================================================

function test_migration_001_minimal_config() {
  log_test_step "Testing migration 001 with minimal config"

  # Create minimal flat config (v0)
  local test_config="${KGSM_TEST_SANDBOX}/test_config_minimal.ini"
  cat > "$test_config" << 'EOF'
update_channel=main
enable_logging=false
enable_systemd=false
EOF

  # Run migration
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$test_config"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Migration should succeed"

  # Verify schema version was added
  local schema_version
  schema_version=$(grep "^config_schema_version=" "$test_config" | cut -d= -f2)
  assert_equals "$schema_version" "1" "Schema version should be 1"

  # Verify sections exist
  assert_command_succeeds "grep -q '^\[system\]' '$test_config'"
  assert_command_succeeds "grep -q '^\[services\]' '$test_config'"
  assert_command_succeeds "grep -q '^\[network\]' '$test_config'"

  # Verify values preserved
  local channel
  channel=$(grep "^update_channel=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$channel" "main" "update_channel value preserved"

  local logging
  logging=$(grep "^enable_logging=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$logging" "false" "enable_logging value preserved"

  # Verify backup was created
  assert_file_exists "${test_config}.pre-migration-v1.bak"
}

# =============================================================================
# TEST: Migration 001 - Flat to Sectioned (Full Config)
# =============================================================================

function test_migration_001_full_config() {
  log_test_step "Testing migration 001 with full config"

  # Create full flat config (v0) with all keys
  local test_config="${KGSM_TEST_SANDBOX}/test_config_full.ini"
  cat > "$test_config" << 'EOF'
update_channel=dev
auto_update_check=true
wget_timeout_seconds=120
enable_logging=true
log_max_size_kb=20480
STEAM_USERNAME=testuser
STEAM_PASSWORD=testpass
enable_systemd=true
systemd_files_dir=/custom/systemd
enable_firewall_management=true
firewall_rules_dir=/custom/ufw
enable_port_forwarding=true
enable_event_broadcasting=true
event_socket_filenames=custom.sock
enable_webhook_events=true
webhook_urls=https://example.com/webhook
webhook_timeout_seconds=20
webhook_retry_count=3
webhook_secret=mysecret
enable_watcher=true
watcher_global_timeout_seconds=900
watcher_ports_check_interval_seconds=10
default_install_directory=/custom/servers
instance_suffix_length=4
enable_backup_compression=true
instance_save_command_timeout_seconds=10
instance_stop_command_timeout_seconds=60
instance_auto_update_before_start=true
enable_command_shortcuts=true
command_shortcuts_directory=/custom/bin
EOF

  # Run migration
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$test_config"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Migration should succeed"

  # Verify all custom values preserved (spot check key ones)
  local channel
  channel=$(grep "^update_channel=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$channel" "dev" "Custom update_channel preserved"

  local timeout
  timeout=$(grep "^wget_timeout_seconds=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$timeout" "120" "Custom wget_timeout_seconds preserved"

  local username
  username=$(grep "^STEAM_USERNAME=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$username" "testuser" "Custom STEAM_USERNAME preserved"

  local suffix
  suffix=$(grep "^instance_suffix_length=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$suffix" "4" "Custom instance_suffix_length preserved"

  local shortcuts
  shortcuts=$(grep "^command_shortcuts_directory=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$shortcuts" "/custom/bin" "Custom command_shortcuts_directory preserved"
}

# =============================================================================
# TEST: Migration 001 - Idempotency (Can Run Twice Safely)
# =============================================================================

function test_migration_001_idempotent() {
  log_test_step "Testing migration 001 idempotency"

  # Create flat config
  local test_config="${KGSM_TEST_SANDBOX}/test_config_idempotent.ini"
  cat > "$test_config" << 'EOF'
update_channel=main
enable_logging=true
EOF

  # Run migration first time
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$test_config"
  assert_equals "$?" "0" "First migration should succeed"

  # Get schema version after first migration
  local schema_v1
  schema_v1=$(grep "^config_schema_version=" "$test_config" | cut -d= -f2)
  assert_equals "$schema_v1" "1" "Schema version should be 1 after first migration"

  # Run migration second time
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$test_config"
  assert_equals "$?" "0" "Second migration should succeed (idempotent)"

  # Verify schema version unchanged
  local schema_v2
  schema_v2=$(grep "^config_schema_version=" "$test_config" | cut -d= -f2)
  assert_equals "$schema_v2" "1" "Schema version should still be 1"

  # Verify values still preserved
  local channel
  channel=$(grep "^update_channel=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$channel" "main" "Values still preserved after second run"
}

# =============================================================================
# TEST: Migration 001 - Handles Missing Keys with Defaults
# =============================================================================

function test_migration_001_missing_keys_get_defaults() {
  log_test_step "Testing migration 001 adds defaults for missing keys"

  # Create config with only a few keys (missing most)
  local test_config="${KGSM_TEST_SANDBOX}/test_config_sparse.ini"
  cat > "$test_config" << 'EOF'
update_channel=dev
enable_systemd=true
EOF

  # Run migration
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$test_config"
  assert_equals "$?" "0" "Migration should succeed"

  # Verify custom values preserved
  local channel
  channel=$(grep "^update_channel=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$channel" "dev" "Custom update_channel preserved"

  local systemd
  systemd=$(grep "^enable_systemd=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$systemd" "true" "Custom enable_systemd preserved"

  # Verify missing keys got defaults
  local logging
  logging=$(grep "^enable_logging=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$logging" "false" "Missing enable_logging got default value"

  local timeout
  timeout=$(grep "^wget_timeout_seconds=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$timeout" "60" "Missing wget_timeout_seconds got default value"
}

# =============================================================================
# TEST: Migration 001 - Handles Empty Values
# =============================================================================

function test_migration_001_empty_values() {
  log_test_step "Testing migration 001 handles empty values"

  # Create config with empty values (which is valid)
  local test_config="${KGSM_TEST_SANDBOX}/test_config_empty.ini"
  cat > "$test_config" << 'EOF'
update_channel=main
STEAM_USERNAME=
STEAM_PASSWORD=
webhook_urls=
default_install_directory=
EOF

  # Run migration
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$test_config"
  assert_equals "$?" "0" "Migration should succeed with empty values"

  # Verify empty values preserved (these are legitimate empty configs)
  assert_command_succeeds "grep -q '^STEAM_USERNAME=\$' '$test_config'"
  assert_command_succeeds "grep -q '^STEAM_PASSWORD=\$' '$test_config'"
  assert_command_succeeds "grep -q '^default_install_directory=\$' '$test_config'"
}

# =============================================================================
# TEST: Migration 001 - Error Handling (File Not Found)
# =============================================================================

function test_migration_001_file_not_found() {
  log_test_step "Testing migration 001 error handling for missing file"

  local nonexistent_file="${KGSM_TEST_SANDBOX}/nonexistent.ini"

  # Run migration on nonexistent file
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$nonexistent_file" 2>/dev/null
  local exit_code=$?

  assert_not_equals "$exit_code" "0" "Migration should fail for nonexistent file"
}

# =============================================================================
# TEST: Migration 001 - Error Handling (No File Provided)
# =============================================================================

function test_migration_001_no_file_provided() {
  log_test_step "Testing migration 001 error handling without file argument"

  # Run migration without file argument
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" 2>/dev/null
  local exit_code=$?

  assert_not_equals "$exit_code" "0" "Migration should fail when no file provided"
}

# =============================================================================
# TEST: Migration 001 - Backup Creation
# =============================================================================

function test_migration_001_creates_backup() {
  log_test_step "Testing migration 001 creates backup file"

  local test_config="${KGSM_TEST_SANDBOX}/test_config_backup.ini"
  cat > "$test_config" << 'EOF'
update_channel=main
enable_logging=false
EOF

  # Verify backup doesn't exist yet
  assert_file_not_exists "${test_config}.pre-migration-v1.bak"

  # Run migration
  bash "$MIGRATION_DIR/001_v0_to_v1_flat_to_sectioned.sh" "$test_config"
  assert_equals "$?" "0" "Migration should succeed"

  # Verify backup was created
  assert_file_exists "${test_config}.pre-migration-v1.bak"

  # Verify backup contains original content
  assert_command_succeeds "grep -q '^update_channel=main' '${test_config}.pre-migration-v1.bak'"
  assert_command_fails "grep -q 'config_schema_version' '${test_config}.pre-migration-v1.bak'"
}

# =============================================================================
# TEST: Migration 002 - Adds [cgroup] Section
# =============================================================================

function test_migration_002_adds_cgroup_section() {
  log_test_step "Testing migration 002 adds the [cgroup] section"

  # Create a sectioned v1 config
  local test_config="${KGSM_TEST_SANDBOX}/test_config_v1_cgroup.ini"
  cat > "$test_config" << 'EOF'
config_schema_version=1

[system]
wget_timeout_seconds=60

[services]
enable_systemd=false
systemd_files_dir=/etc/systemd/system
EOF

  # Run migration
  bash "$MIGRATION_DIR/002_v1_to_v2_add_cgroup_section.sh" "$test_config"
  assert_equals "$?" "0" "Migration 002 should succeed"

  # Schema version bumped to 2
  local schema_version
  schema_version=$(grep "^config_schema_version=" "$test_config" | cut -d= -f2)
  assert_equals "$schema_version" "2" "Schema version should be 2"

  # [cgroup] section and its keys present
  assert_command_succeeds "grep -q '^\[cgroup\]' '$test_config'"
  assert_command_succeeds "grep -q '^enable_cgroups=true' '$test_config'"
  assert_command_succeeds "grep -q '^cgroup_mount_point=/sys/fs/cgroup' '$test_config'"
  assert_command_succeeds "grep -q '^cgroup_base_name=kgsm.slice' '$test_config'"
  assert_command_succeeds "grep -q '^cgroup_controllers=' '$test_config'"

  # Backup created
  assert_file_exists "${test_config}.pre-migration-v2.bak"
}

# =============================================================================
# TEST: Migration 002 - Idempotency (Can Run Twice Safely)
# =============================================================================

function test_migration_002_idempotent() {
  log_test_step "Testing migration 002 idempotency"

  local test_config="${KGSM_TEST_SANDBOX}/test_config_v1_idem.ini"
  cat > "$test_config" << 'EOF'
config_schema_version=1

[system]
wget_timeout_seconds=60
EOF

  # Run twice
  bash "$MIGRATION_DIR/002_v1_to_v2_add_cgroup_section.sh" "$test_config"
  assert_equals "$?" "0" "First migration run should succeed"

  bash "$MIGRATION_DIR/002_v1_to_v2_add_cgroup_section.sh" "$test_config"
  assert_equals "$?" "0" "Second migration run should succeed"

  # Section should appear exactly once
  local section_count
  section_count=$(grep -c '^\[cgroup\]' "$test_config")
  assert_equals "$section_count" "1" "[cgroup] section should appear exactly once"

  # Version remains 2
  local schema_version
  schema_version=$(grep "^config_schema_version=" "$test_config" | cut -d= -f2)
  assert_equals "$schema_version" "2" "Schema version should remain 2"
}

# =============================================================================
# TEST: Migration 002 - Preserves Existing Values
# =============================================================================

function test_migration_002_preserves_existing_values() {
  log_test_step "Testing migration 002 preserves existing values"

  local test_config="${KGSM_TEST_SANDBOX}/test_config_v1_preserve.ini"
  cat > "$test_config" << 'EOF'
config_schema_version=1

[system]
wget_timeout_seconds=120

[services]
enable_systemd=true
EOF

  bash "$MIGRATION_DIR/002_v1_to_v2_add_cgroup_section.sh" "$test_config"
  assert_equals "$?" "0" "Migration 002 should succeed"

  # Pre-existing values untouched
  local wget_timeout
  wget_timeout=$(grep "^wget_timeout_seconds=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$wget_timeout" "120" "wget_timeout_seconds preserved"

  local systemd
  systemd=$(grep "^enable_systemd=" "$test_config" | head -1 | cut -d= -f2)
  assert_equals "$systemd" "true" "enable_systemd preserved"
}

