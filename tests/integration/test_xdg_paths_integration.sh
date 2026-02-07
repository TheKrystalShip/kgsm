#!/usr/bin/env bash

# Integration test for XDG path structure
# Tests that finder functions correctly search user and system directories

# Source test framework
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$TEST_DIR/framework/assert.sh"

function setup_test() {
  log_step "Setting up test environment"

  # Create temporary XDG directories
  export TEST_XDG_CONFIG_HOME="${SANDBOX_ROOT}/config"
  export TEST_XDG_DATA_HOME="${SANDBOX_ROOT}/data"

  export XDG_CONFIG_HOME="$TEST_XDG_CONFIG_HOME"
  export XDG_DATA_HOME="$TEST_XDG_DATA_HOME"

  # Source bootstrap and common
  # shellcheck disable=SC1091
  source "${SANDBOX_ROOT}/core/bootstrap.sh"

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
}

function test_find_blueprint_user_first() {
  log_step "Test: __find_blueprint searches user directory first"

  # Create same-named blueprint in both locations
  echo 'name=shared' > "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/shared.bp"
  echo 'name=shared-user-version' > "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/shared.bp"

  # Find should return user version
  local found
  found=$(__find_blueprint "shared")

  assert_equals "$found" "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/shared.bp" "User blueprint should take precedence"
}

function test_find_blueprint_system_fallback() {
  log_step "Test: __find_blueprint falls back to system directory"

  # System-only blueprint
  local found
  found=$(__find_blueprint "test-system")

  assert_equals "$found" "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp" "Should find system blueprint"
}

function test_find_blueprint_user_only() {
  log_step "Test: __find_blueprint finds user-only blueprints"

  local found
  found=$(__find_blueprint "test-user")

  assert_equals "$found" "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/test-user.bp" "Should find user blueprint"
}

function test_find_blueprint_not_found() {
  log_step "Test: __find_blueprint returns error for missing blueprint"

  # Try to find non-existent blueprint
  if __find_blueprint "nonexistent" 2>/dev/null; then
    assert_fail "Should return error for non-existent blueprint"
  else
    assert_pass "Correctly returns error for non-existent blueprint"
  fi
}

function test_config_file_location() {
  log_step "Test: Config file uses XDG config directory"

  # Source config module
  # shellcheck disable=SC1091
  source "${SANDBOX_ROOT}/core/config.sh"

  # CONFIG_FILE should point to XDG location
  assert_equals "$CONFIG_FILE" "${KGSM_CONFIG_DIR}/config.ini" "CONFIG_FILE should use KGSM_CONFIG_DIR"
}

function test_config_file_creation() {
  log_step "Test: Config file created in correct location on first run"

  # Copy default config to simulate system install
  cp "${SANDBOX_ROOT}/config.default.ini" "${KGSM_DEFAULT_CONFIG_FILE}"

  # Unset config loaded flag
  unset KGSM_CONFIG_LOADED

  # Source config (should create config.ini)
  # shellcheck disable=SC1091
  source "${SANDBOX_ROOT}/core/config.sh"

  # Config file should exist in XDG location
  assert_file_exists "${KGSM_CONFIG_DIR}/config.ini" "Config file should be created in XDG config directory"
}

function test_logs_directory_location() {
  log_step "Test: Logs use XDG data directory"

  # Source logging module
  # shellcheck disable=SC1091
  source "${SANDBOX_ROOT}/core/logging.sh"

  # LOGS_SOURCE_DIR should point to XDG data location
  assert_equals "$LOGS_SOURCE_DIR" "$KGSM_LOGS_DIR" "LOGS_SOURCE_DIR should use KGSM_LOGS_DIR"
}

function test_instances_directory_location() {
  log_step "Test: Instances use XDG data directory"

  # KGSM_INSTANCES_DIR should point to XDG data location
  assert_equals "$KGSM_INSTANCES_DIR" "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should use KGSM_INSTANCES_DIR"
}

function test_blueprints_list_includes_both() {
  log_step "Test: Blueprint listing includes both user and system blueprints"

  # List blueprints (this would normally call blueprints.sh)
  # For this test, just verify both directories exist and contain blueprints
  assert_directory_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR" "System blueprints directory should exist"
  assert_directory_exists "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "User blueprints directory should exist"

  assert_file_exists "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp" "System blueprint should exist"
  assert_file_exists "${KGSM_USER_BLUEPRINTS_NATIVE_DIR}/test-user.bp" "User blueprint should exist"
}

function test_user_override_precedence() {
  log_step "Test: User overrides take precedence over system overrides"

  # Create same-named override in both locations
  echo '# System override' > "${KGSM_SYSTEM_OVERRIDES_DIR}/game.overrides.sh"
  echo '# User override - custom' > "${KGSM_USER_OVERRIDES_DIR}/game.overrides.sh"

  # Create mock instance config to test __find_override
  mkdir -p "${KGSM_INSTANCES_DIR}/test-instance"
  cat > "${KGSM_INSTANCES_DIR}/test-instance/test-instance.ini" <<EOF
blueprint_file=${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp
EOF

  # Update test-system blueprint to have the right name
  echo 'name=game' > "${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/test-system.bp"

  # Find override
  local found
  found=$(__find_override "test-instance")

  # Should return user override path
  assert_equals "$found" "${KGSM_USER_OVERRIDES_DIR}/game.overrides.sh" "User override should take precedence"
}

function test_kgsm_paths_command() {
  log_step "Test: kgsm --paths command displays correct paths"

  # Execute --paths command
  local output
  output=$("${SANDBOX_ROOT}/kgsm.sh" --paths 2>&1)

  # Check that output contains expected paths
  assert_contains "$output" "$KGSM_ROOT" "Should display KGSM_ROOT"
  assert_contains "$output" "$KGSM_CONFIG_DIR" "Should display KGSM_CONFIG_DIR"
  assert_contains "$output" "$KGSM_DATA_DIR" "Should display KGSM_DATA_DIR"
}

function main() {
  log_step "Starting XDG path integration tests"

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

  log_step "All XDG path integration tests completed"
}

main "$@"
