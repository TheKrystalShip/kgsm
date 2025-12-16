#!/usr/bin/env bash

# KGSM Configuration Merge Logic Tests
#
# Tests the config merge engine that combines user config with default config

# =============================================================================
# TEST SETUP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Framework common functions
source "$SCRIPT_DIR/../framework/common.sh"

# KGSM bootstrapper
source "$KGSM_ROOT/core/bootstrap.sh"

# Test variables
readonly TEST_NAME="config_merge_logic"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_step "Setting up config merge logic tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$KGSM_ROOT/core/config.sh" "config.sh should exist"

  # Source config module
  source "$KGSM_ROOT/core/config.sh"

  # Verify required error codes
  assert_not_null "$EC_SUCCESS_CONFIG_MERGED" "EC_SUCCESS_CONFIG_MERGED should be defined"
  assert_not_null "$EC_FAILED_BACKUP" "EC_FAILED_BACKUP should be defined"
  assert_not_null "$EC_MIGRATION_FAILED" "EC_MIGRATION_FAILED should be defined"

  # Verify functions are exported
  assert_function_exists "__create_config_backup" "create_config_backup should be exported"
  assert_function_exists "__parse_config_to_map" "parse_config_to_map should be exported"
  assert_function_exists "__run_config_migrations" "run_config_migrations should be exported"
  assert_function_exists "__handle_deprecated_keys" "handle_deprecated_keys should be exported"
  assert_function_exists "__merge_user_config_with_default" "merge_user_config_with_default should be exported"

  log_test "Config merge logic test environment validated"
}

# =============================================================================
# TEST: __create_config_backup - Creates Numbered Backups
# =============================================================================

function test_create_config_backup() {
  log_step "Testing __create_config_backup creates numbered backup"

  # Create test config
  local test_config="${KGSM_TEST_SANDBOX}/test_backup.ini"
  echo "test_key=test_value" > "$test_config"

  # Override CONFIG_FILE for this test
  local original_config="$CONFIG_FILE"
  CONFIG_FILE="$test_config"

  # Create backup
  __create_config_backup
  local exit_code=$?

  # Restore original
  CONFIG_FILE="$original_config"

  assert_equals "$exit_code" "0" "Backup creation should succeed"
  assert_file_exists "${test_config}.0" "Backup file .0 should exist"

  # Verify content
  local backup_content
  backup_content=$(<"${test_config}.0")
  assert_equals "$backup_content" "test_key=test_value" "Backup should contain original content"

  # Cleanup
  rm -f "$test_config" "${test_config}.0"
}

# =============================================================================
# TEST: __create_config_backup - Rotates Old Backups
# =============================================================================

function test_create_config_backup_rotation() {
  log_step "Testing __create_config_backup rotates old backups"

  # Create test config
  local test_config="${KGSM_TEST_SANDBOX}/test_rotation.ini"
  echo "version=1" > "$test_config"

  # Override CONFIG_FILE
  local original_config="$CONFIG_FILE"
  CONFIG_FILE="$test_config"

  # Create first backup
  __create_config_backup
  assert_file_exists "${test_config}.0" "First backup should exist at .0"

  # Modify config and create second backup
  echo "version=2" > "$test_config"
  __create_config_backup

  # Verify rotation
  assert_file_exists "${test_config}.0" "Latest backup should be at .0"
  assert_file_exists "${test_config}.1" "Previous backup should be at .1"

  # Verify content
  local latest
  latest=$(<"${test_config}.0")
  assert_equals "$latest" "version=2" "Latest backup should have version 2"

  local previous
  previous=$(<"${test_config}.1")
  assert_equals "$previous" "version=1" "Previous backup should have version 1"

  # Restore and cleanup
  CONFIG_FILE="$original_config"
  rm -f "$test_config" "${test_config}".{0,1}
}

# =============================================================================
# TEST: __parse_config_to_map - Parses Config Into Array
# =============================================================================

function test_parse_config_to_map() {
  log_step "Testing __parse_config_to_map parses config correctly"

  # Create test config with sections
  local test_config="${KGSM_TEST_SANDBOX}/test_parse.ini"
  cat > "$test_config" << 'EOF'
config_schema_version=1

[system]
update_channel=main
enable_logging=true

[network]
enable_firewall_management=false
EOF

  # Parse into map
  declare -A config_map
  __parse_config_to_map "$test_config" config_map

  # Verify keys were extracted
  assert_equals "${config_map[config_schema_version]}" "1" "Schema version should be parsed"
  assert_equals "${config_map[update_channel]}" "main" "update_channel should be parsed"
  assert_equals "${config_map[enable_logging]}" "true" "enable_logging should be parsed"
  assert_equals "${config_map[enable_firewall_management]}" "false" "enable_firewall_management should be parsed"

  # Cleanup
  rm -f "$test_config"
}

# =============================================================================
# TEST: __parse_config_to_map - Handles Empty Values
# =============================================================================

function test_parse_config_to_map_empty_values() {
  log_step "Testing __parse_config_to_map handles empty values"

  # Create config with empty values
  local test_config="${KGSM_TEST_SANDBOX}/test_empty.ini"
  cat > "$test_config" << 'EOF'
STEAM_USERNAME=
STEAM_PASSWORD=
webhook_urls=
EOF

  # Parse into map
  declare -A config_map
  __parse_config_to_map "$test_config" config_map

  # Verify empty values are preserved
  assert_equals "${config_map[STEAM_USERNAME]}" "" "Empty STEAM_USERNAME should be preserved"
  assert_equals "${config_map[STEAM_PASSWORD]}" "" "Empty STEAM_PASSWORD should be preserved"
  assert_equals "${config_map[webhook_urls]}" "" "Empty webhook_urls should be preserved"

  # Cleanup
  rm -f "$test_config"
}

# =============================================================================
# TEST: __handle_deprecated_keys - Comments Out Deprecated Keys
# =============================================================================
# NOTE: This function is tested as part of test_merge_handles_deprecated_keys
# because it needs a complete config file to append to. Testing in isolation
# doesn't reflect real usage.

# =============================================================================
# TEST: __merge_user_config_with_default - Merges Configs Successfully
# =============================================================================

function test_merge_user_config_with_default() {
  log_step "Testing __merge_user_config_with_default full merge"

  # Create test user config
  local test_user_config="${KGSM_TEST_SANDBOX}/user.ini"
  cat > "$test_user_config" << 'EOF'
config_schema_version=1

[system]
update_channel=dev
enable_logging=true

[network]
enable_firewall_management=false
EOF

  # Create test default config
  local test_default_config="${KGSM_TEST_SANDBOX}/default.ini"
  cat > "$test_default_config" << 'EOF'
config_schema_version=1

[system]
update_channel=main
enable_logging=false
wget_timeout_seconds=60

[network]
enable_firewall_management=false
enable_port_forwarding=false
EOF

  # Override global config paths
  local original_config="$CONFIG_FILE"
  local original_default="$DEFAULT_CONFIG_FILE"
  CONFIG_FILE="$test_user_config"
  DEFAULT_CONFIG_FILE="$test_default_config"

  # Perform merge
  __merge_user_config_with_default
  local exit_code=$?

  # Restore originals
  CONFIG_FILE="$original_config"
  DEFAULT_CONFIG_FILE="$original_default"

  assert_equals "$exit_code" "$EC_SUCCESS_CONFIG_MERGED" "Merge should return success code"

  # Verify user values preserved
  assert_command_succeeds "grep -q '^update_channel=dev' '$test_user_config'"
  assert_command_succeeds "grep -q '^enable_logging=true' '$test_user_config'"

  # Verify new keys added
  assert_command_succeeds "grep -q '^wget_timeout_seconds=' '$test_user_config'"
  assert_command_succeeds "grep -q '^enable_port_forwarding=' '$test_user_config'"

  # Verify backup created
  assert_file_exists "${test_user_config}.0"

  # Cleanup
  rm -f "$test_user_config" "$test_default_config" "${test_user_config}.0"
}

# =============================================================================
# TEST: __merge_user_config_with_default - Handles Deprecated Keys
# =============================================================================

function test_merge_handles_deprecated_keys() {
  log_step "Testing __merge_user_config_with_default handles deprecated keys"

  # Create user config with old key
  local test_user_config="${KGSM_TEST_SANDBOX}/user_old.ini"
  cat > "$test_user_config" << 'EOF'
config_schema_version=1

[system]
update_channel=main
old_removed_setting=value
EOF

  # Create default config without old key
  local test_default_config="${KGSM_TEST_SANDBOX}/default_new.ini"
  cat > "$test_default_config" << 'EOF'
config_schema_version=1

[system]
update_channel=main
EOF

  # Override paths
  local original_config="$CONFIG_FILE"
  local original_default="$DEFAULT_CONFIG_FILE"
  CONFIG_FILE="$test_user_config"
  DEFAULT_CONFIG_FILE="$test_default_config"

  # Perform merge
  __merge_user_config_with_default 2>/dev/null
  local exit_code=$?

  # Restore
  CONFIG_FILE="$original_config"
  DEFAULT_CONFIG_FILE="$original_default"

  assert_equals "$exit_code" "$EC_SUCCESS_CONFIG_MERGED" "Merge should succeed with deprecated keys"

  # Verify deprecated key section header exists
  assert_command_succeeds "grep -q '# DEPRECATED KEYS' '$test_user_config'"

  # Verify deprecated key is commented (regex pattern to match)
  assert_command_succeeds "grep -q 'DEPRECATED.*old_removed_setting' '$test_user_config'"

  # Cleanup
  rm -f "$test_user_config" "$test_default_config" "${test_user_config}.0"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test "Starting config merge logic tests"

  # Setup
  setup_test

  # Run all tests
  test_create_config_backup
  test_create_config_backup_rotation
  test_parse_config_to_map
  test_parse_config_to_map_empty_values
  test_merge_user_config_with_default
  test_merge_handles_deprecated_keys

  # Summary
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All config merge logic tests passed"
  else
    fail_test "Some config merge logic tests failed"
  fi
}

main "$@"
