#!/usr/bin/env bash

# Test suite for core/paths.sh
# Tests path variable exports and XDG compliance

# Source test framework
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$TEST_DIR/framework/assert.sh"

function setup_test() {
  log_step "Setting up test environment"

  # Create temporary XDG directories
  export TEST_XDG_CONFIG_HOME="${SANDBOX_ROOT}/config"
  export TEST_XDG_DATA_HOME="${SANDBOX_ROOT}/data"

  # Set XDG variables for test
  export XDG_CONFIG_HOME="$TEST_XDG_CONFIG_HOME"
  export XDG_DATA_HOME="$TEST_XDG_DATA_HOME"

  # Source paths.sh
  # shellcheck disable=SC1091
  source "${SANDBOX_ROOT}/core/paths.sh"
}

function test_system_paths_exported() {
  log_step "Test: System path variables are exported"

  assert_not_empty "$KGSM_CORE_DIR" "KGSM_CORE_DIR should be set"
  assert_not_empty "$KGSM_COMMANDS_DIR" "KGSM_COMMANDS_DIR should be set"
  assert_not_empty "$KGSM_HANDLERS_DIR" "KGSM_HANDLERS_DIR should be set"
  assert_not_empty "$KGSM_TEMPLATES_DIR" "KGSM_TEMPLATES_DIR should be set"
  assert_not_empty "$KGSM_MIGRATIONS_DIR" "KGSM_MIGRATIONS_DIR should be set"
  assert_not_empty "$KGSM_SYSTEM_BLUEPRINTS_DIR" "KGSM_SYSTEM_BLUEPRINTS_DIR should be set"
  assert_not_empty "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR" "KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR should be set"
  assert_not_empty "$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR" "KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR should be set"
  assert_not_empty "$KGSM_SYSTEM_OVERRIDES_DIR" "KGSM_SYSTEM_OVERRIDES_DIR should be set"
  assert_not_empty "$KGSM_DEFAULT_CONFIG_FILE" "KGSM_DEFAULT_CONFIG_FILE should be set"
}

function test_user_paths_exported() {
  log_step "Test: User path variables are exported"

  assert_not_empty "$KGSM_CONFIG_DIR" "KGSM_CONFIG_DIR should be set"
  assert_not_empty "$KGSM_DATA_DIR" "KGSM_DATA_DIR should be set"
  assert_not_empty "$KGSM_CONFIG_FILE" "KGSM_CONFIG_FILE should be set"
  assert_not_empty "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should be set"
  assert_not_empty "$KGSM_LOGS_DIR" "KGSM_LOGS_DIR should be set"
  assert_not_empty "$KGSM_USER_BLUEPRINTS_DIR" "KGSM_USER_BLUEPRINTS_DIR should be set"
  assert_not_empty "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "KGSM_USER_BLUEPRINTS_NATIVE_DIR should be set"
  assert_not_empty "$KGSM_USER_BLUEPRINTS_CONTAINER_DIR" "KGSM_USER_BLUEPRINTS_CONTAINER_DIR should be set"
  assert_not_empty "$KGSM_USER_OVERRIDES_DIR" "KGSM_USER_OVERRIDES_DIR should be set"
}

function test_xdg_compliance() {
  log_step "Test: XDG Base Directory compliance"

  # Config directory should use XDG_CONFIG_HOME
  assert_equals "$KGSM_CONFIG_DIR" "${XDG_CONFIG_HOME}/kgsm" "KGSM_CONFIG_DIR should use XDG_CONFIG_HOME"

  # Data directory should use XDG_DATA_HOME
  assert_equals "$KGSM_DATA_DIR" "${XDG_DATA_HOME}/kgsm" "KGSM_DATA_DIR should use XDG_DATA_HOME"

  # Config file should be in config directory
  assert_equals "$KGSM_CONFIG_FILE" "${KGSM_CONFIG_DIR}/config.ini" "KGSM_CONFIG_FILE should be in KGSM_CONFIG_DIR"
}

function test_xdg_fallback_defaults() {
  log_step "Test: XDG fallback to default values"

  # Unset XDG variables
  unset XDG_CONFIG_HOME
  unset XDG_DATA_HOME

  # Re-source paths.sh
  unset KGSM_PATHS_LOADED
  # shellcheck disable=SC1091
  source "${SANDBOX_ROOT}/core/paths.sh"

  # Should fall back to $HOME/.config and $HOME/.local/share
  assert_equals "$KGSM_CONFIG_DIR" "$HOME/.config/kgsm" "Should fall back to \$HOME/.config/kgsm"
  assert_equals "$KGSM_DATA_DIR" "$HOME/.local/share/kgsm" "Should fall back to \$HOME/.local/share/kgsm"
}

function test_init_user_directories() {
  log_step "Test: User directories initialization"

  # Call init function
  __init_user_directories

  # Check all directories were created
  assert_directory_exists "$KGSM_CONFIG_DIR" "KGSM_CONFIG_DIR should exist"
  assert_directory_exists "$KGSM_DATA_DIR" "KGSM_DATA_DIR should exist"
  assert_directory_exists "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should exist"
  assert_directory_exists "$KGSM_LOGS_DIR" "KGSM_LOGS_DIR should exist"
  assert_directory_exists "$KGSM_USER_BLUEPRINTS_DIR" "KGSM_USER_BLUEPRINTS_DIR should exist"
  assert_directory_exists "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "KGSM_USER_BLUEPRINTS_NATIVE_DIR should exist"
  assert_directory_exists "$KGSM_USER_BLUEPRINTS_CONTAINER_DIR" "KGSM_USER_BLUEPRINTS_CONTAINER_DIR should exist"
  assert_directory_exists "$KGSM_USER_OVERRIDES_DIR" "KGSM_USER_OVERRIDES_DIR should exist"
}

function test_legacy_aliases_exported() {
  log_step "Test: Legacy compatibility aliases are exported"

  # Test that legacy variables still exist
  assert_not_empty "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR" "KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR should be set"
  assert_not_empty "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "KGSM_USER_BLUEPRINTS_NATIVE_DIR should be set"
  assert_not_empty "$KGSM_SYSTEM_OVERRIDES_DIR" "KGSM_SYSTEM_OVERRIDES_DIR should be set"
  assert_not_empty "$KGSM_TEMPLATES_DIR" "KGSM_TEMPLATES_DIR should be set"
  assert_not_empty "$KGSM_COMMANDS_DIR" "KGSM_COMMANDS_DIR should be set"
  assert_not_empty "$KGSM_CORE_DIR" "KGSM_CORE_DIR should be set"
  assert_not_empty "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should be set"
}

function test_legacy_aliases_map_correctly() {
  log_step "Test: Legacy aliases map to new variables"

  assert_equals "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "$KGSM_USER_BLUEPRINTS_NATIVE_DIR" "KGSM_USER_BLUEPRINTS_NATIVE_DIR should map to KGSM_USER_BLUEPRINTS_NATIVE_DIR"
  assert_equals "$KGSM_SYSTEM_OVERRIDES_DIR" "$KGSM_SYSTEM_OVERRIDES_DIR" "KGSM_SYSTEM_OVERRIDES_DIR should map to KGSM_SYSTEM_OVERRIDES_DIR"
  assert_equals "$KGSM_INSTANCES_DIR" "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should map to KGSM_INSTANCES_DIR"
}

function test_paths_loaded_guard() {
  log_step "Test: KGSM_PATHS_LOADED guard prevents reload"

  # KGSM_PATHS_LOADED should be set
  assert_not_empty "$KGSM_PATHS_LOADED" "KGSM_PATHS_LOADED should be set"

  # Set a marker variable
  export TEST_MARKER="first_load"

  # Source paths.sh again - should return immediately
  # shellcheck disable=SC1091
  source "${SANDBOX_ROOT}/core/paths.sh"

  # Marker should still be "first_load"
  assert_equals "$TEST_MARKER" "first_load" "paths.sh should not reload when KGSM_PATHS_LOADED is set"
}

function main() {
  log_step "Starting core/paths.sh test suite"

  setup_test

  test_system_paths_exported
  test_user_paths_exported
  test_xdg_compliance
  test_xdg_fallback_defaults
  test_init_user_directories
  test_legacy_aliases_exported
  test_legacy_aliases_map_correctly
  test_paths_loaded_guard

  log_step "All core/paths.sh tests completed"
}

main "$@"
