#!/usr/bin/env bash

# KGSM XDG Path Structure Integration Tests
#
# Test Type: INTEGRATION
# Target: XDG path structure and user/system directory precedence
#
# Tests __find_blueprint() and __find_override() from core/loader.sh
# to verify correct search order: user directories take precedence over system directories.
# Also validates that config, logs, and instances use correct XDG-compliant paths.

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="xdg_paths"

function setup_test() {
  log_test_step "Setting up XDG path integration tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Verify required functions exist
  assert_function_exists "__find_blueprint" "__find_blueprint should be defined"
  assert_function_exists "__find_override" "__find_override should be defined"

  # Verify required directories exist
  assert_not_null "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR" "System blueprints directory variable should be set"
  assert_not_null "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "User blueprints directory variable should be set"
  assert_not_null "$KGSM_SYSTEM_OVERRIDES_DIR" "System overrides directory variable should be set"
  assert_not_null "$KGSM_USER_OVERRIDES_DIR" "User overrides directory variable should be set"

  # Create test blueprints in system directory
  mkdir -p "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}"
  echo 'name=test-system' > "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp"

  # Create test blueprints in user directory
  mkdir -p "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}"
  echo 'name=test-user' > "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/test-user.bp"

  # Create override test files
  mkdir -p "${KGSM_SYSTEM_OVERRIDES_DIR}"
  echo '# System override' > "${KGSM_SYSTEM_OVERRIDES_DIR}/test-game.overrides.sh"

  mkdir -p "${KGSM_USER_OVERRIDES_DIR}"
  echo '# User override' > "${KGSM_USER_OVERRIDES_DIR}/test-custom.overrides.sh"

  log_test_step "Test environment validated"
}

function test_find_blueprint_user_first() {
  log_test_step "Testing __find_blueprint searches user directory first"

  # Create same-named blueprint in both locations
  echo 'name=shared' > "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/shared.bp"
  echo 'name=shared-user-version' > "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/shared.bp"

  # Find should return user version
  local found
  found=$(__find_blueprint "shared")

  assert_equals "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/shared.bp" "$found" "User blueprint should take precedence"

  # Cleanup
  rm -f "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/shared.bp"
  rm -f "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/shared.bp"
}

function test_find_blueprint_system_fallback() {
  log_test_step "Testing __find_blueprint falls back to system directory"

  # System-only blueprint
  local found
  found=$(__find_blueprint "test-system")

  assert_equals "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp" "$found" "Should find system blueprint"
}

function test_find_blueprint_user_only() {
  log_test_step "Testing __find_blueprint finds user-only blueprints"

  local found
  found=$(__find_blueprint "test-user")

  assert_equals "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/test-user.bp" "$found" "Should find user blueprint"
}

function test_find_blueprint_not_found() {
  log_test_step "Testing __find_blueprint returns error for missing blueprint"

  __find_blueprint "nonexistent-blueprint-xyz" 2>/dev/null
  local exit_code=$?

  assert_not_equals "0" "$exit_code" "Should return non-zero exit code for nonexistent blueprint"
}

# =============================================================================
# CONFIG LOCATION TESTS
# =============================================================================

function test_config_file_location() {
  log_test_step "Testing config file uses XDG config directory"

  # CONFIG_FILE should point to XDG location (already set by bootstrap)
  assert_not_null "$KGSM_CONFIG_DIR" "KGSM_CONFIG_DIR should be set"
  assert_contains "$KGSM_CONFIG_DIR" "config" "Config directory should contain 'config' in path"
}

function test_config_file_creation() {
  log_test_step "Testing config file exists in XDG location"

  # Config file should exist in XDG location (sandbox creates it)
  assert_not_null "$KGSM_CONFIG_DIR" "KGSM_CONFIG_DIR should be set"
  assert_dir_exists "$KGSM_CONFIG_DIR" "Config directory should exist"

  # Verify default config file exists
  assert_file_exists "${KGSM_ROOT}/config.default.ini" "Default config should exist"
}

# =============================================================================
# DIRECTORY LOCATION TESTS
# =============================================================================

function test_logs_directory_location() {
  log_test_step "Testing logs use XDG data directory"

  assert_not_null "$KGSM_LOGS_DIR" "KGSM_LOGS_DIR should be set"
  assert_not_null "$KGSM_DATA_DIR" "KGSM_DATA_DIR should be set"
  assert_contains "$KGSM_LOGS_DIR" "$KGSM_DATA_DIR" "Logs directory should be under data directory"
}

function test_instances_directory_location() {
  log_test_step "Testing instances use XDG data directory"

  # KGSM_INSTANCES_DIR should point to XDG data location
  assert_not_null "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should be set"
  assert_not_null "$KGSM_DATA_DIR" "KGSM_DATA_DIR should be set"
  assert_contains "$KGSM_INSTANCES_DIR" "$KGSM_DATA_DIR" "Instances directory should be under data directory"
}

function test_blueprints_list_includes_both() {
  log_test_step "Testing blueprint listing includes both user and system blueprints"

  # Verify both directories exist and contain blueprints
  assert_dir_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR" "System blueprints directory should exist"
  assert_dir_exists "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "User blueprints directory should exist"

  assert_file_exists "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp" "System blueprint should exist"
  assert_file_exists "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/test-user.bp" "User blueprint should exist"
}

# =============================================================================
# __find_override() TESTS
# =============================================================================

function test_user_override_precedence() {
  log_test_step "Testing user overrides take precedence over system overrides"

  # Create same-named override in both locations
  echo '# System override' > "${KGSM_SYSTEM_OVERRIDES_DIR}/game.overrides.sh"
  echo '# User override - custom' > "${KGSM_USER_OVERRIDES_DIR}/game.overrides.sh"

  # Update test-system blueprint to have the right name for this test
  echo 'name=game' > "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp"

  # Create mock instance config to test __find_override
  # The structure must be: $KGSM_INSTANCES_DIR/<blueprint>/<instance>/<instance>.config.ini
  mkdir -p "${KGSM_INSTANCES_DIR}/test-system/test-instance"
  cat > "${KGSM_INSTANCES_DIR}/test-system/test-instance/test-instance.config.ini" <<EOF
blueprint_file=${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp
EOF

  # Find override
  local found
  found=$(__find_override "test-instance")

  # Should return user override path
  assert_equals "${KGSM_USER_OVERRIDES_DIR}/game.overrides.sh" "$found" "User override should take precedence"

  # Cleanup
  rm -rf "${KGSM_INSTANCES_DIR}/test-system"
  rm -f "${KGSM_SYSTEM_OVERRIDES_DIR}/game.overrides.sh"
  rm -f "${KGSM_USER_OVERRIDES_DIR}/game.overrides.sh"
  # Restore original test-system blueprint
  echo 'name=test-system' > "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp"
}

# =============================================================================
# kgsm.sh CLI TESTS
# =============================================================================

function test_kgsm_paths_command() {
  log_test_step "Testing kgsm --paths command displays correct paths"

  # Execute --paths command
  local output
  output=$("${KGSM_ROOT}/kgsm.sh" --paths 2>&1)

  # Check that output contains expected paths
  assert_contains "$output" "$KGSM_ROOT" "Should display KGSM_ROOT"
  assert_contains "$output" "$KGSM_CONFIG_DIR" "Should display KGSM_CONFIG_DIR"
  assert_contains "$output" "$KGSM_DATA_DIR" "Should display KGSM_DATA_DIR"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting XDG path integration tests"

  setup_test

  test_find_blueprint_user_first
  test_find_blueprint_system_fallback
  test_find_blueprint_user_only
  test_find_blueprint_not_found
  test_config_file_location
  test_config_file_creation
  test_logs_directory_location
  test_instances_directory_location
  test_blueprints_list_includes_both
  test_user_override_precedence
  test_kgsm_paths_command

  log_test_step "XDG path integration tests completed"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All XDG path integration tests passed"
  else
    fail_test "Some XDG path integration tests failed"
  fi
}

main "$@"
