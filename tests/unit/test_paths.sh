#!/usr/bin/env bash

# KGSM Paths Module Unit Tests
#
# Test Type: UNIT
# Target: core/paths.sh - XDG path management and directory initialization
#
# Tests path variable exports, XDG Base Directory compliance,
# user directory initialization, and load guard mechanism.

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="paths"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up paths module tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Verify core/paths.sh module exists
  assert_file_exists "${KGSM_ROOT}/core/paths.sh" "paths.sh module should exist"

  # Verify required function exists
  assert_function_exists "__init_user_directories" "__init_user_directories should be defined"

  # Verify KGSM_PATHS_LOADED guard is set (bootstrap loads paths.sh)
  assert_not_null "$KGSM_PATHS_LOADED" "KGSM_PATHS_LOADED should be set by bootstrap"

  log_test_step "Test environment validated"
}

# =============================================================================
# SYSTEM PATH EXPORTS TESTS
# =============================================================================

function test_system_paths_exported() {
  log_test_step "Testing system path variables are exported"

  assert_not_null "$KGSM_CORE_DIR" "KGSM_CORE_DIR should be set"
  assert_not_null "$KGSM_COMMANDS_DIR" "KGSM_COMMANDS_DIR should be set"
  assert_not_null "$KGSM_HANDLERS_DIR" "KGSM_HANDLERS_DIR should be set"
  assert_not_null "$KGSM_TEMPLATES_DIR" "KGSM_TEMPLATES_DIR should be set"
  assert_not_null "$KGSM_MIGRATIONS_DIR" "KGSM_MIGRATIONS_DIR should be set"
  assert_not_null "$KGSM_SYSTEM_BLUEPRINTS_DIR" "KGSM_SYSTEM_BLUEPRINTS_DIR should be set"
  assert_not_null "$KGSM_SYSTEM_OVERRIDES_DIR" "KGSM_SYSTEM_OVERRIDES_DIR should be set"
  assert_not_null "$KGSM_DEFAULT_CONFIG_FILE" "KGSM_DEFAULT_CONFIG_FILE should be set"
}

# =============================================================================
# USER PATH EXPORTS TESTS
# =============================================================================

function test_user_paths_exported() {
  log_test_step "Testing user path variables are exported"

  assert_not_null "$KGSM_CONFIG_DIR" "KGSM_CONFIG_DIR should be set"
  assert_not_null "$KGSM_DATA_DIR" "KGSM_DATA_DIR should be set"
  assert_not_null "$KGSM_CONFIG_FILE" "KGSM_CONFIG_FILE should be set"
  assert_not_null "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should be set"
  assert_not_null "$KGSM_LOGS_DIR" "KGSM_LOGS_DIR should be set"
  assert_not_null "$KGSM_USER_BLUEPRINTS_DIR" "KGSM_USER_BLUEPRINTS_DIR should be set"
  assert_not_null "$KGSM_USER_OVERRIDES_DIR" "KGSM_USER_OVERRIDES_DIR should be set"
}

# =============================================================================
# XDG COMPLIANCE TESTS
# =============================================================================

function test_xdg_compliance() {
  log_test_step "Testing XDG Base Directory compliance"

  # Config directory should contain 'config' in path
  assert_contains "$KGSM_CONFIG_DIR" "config" "KGSM_CONFIG_DIR should contain 'config'"

  # Data directory should contain expected path components
  assert_contains "$KGSM_DATA_DIR" "kgsm" "KGSM_DATA_DIR should contain 'kgsm'"

  # Config file should be in config directory
  assert_equals "${KGSM_CONFIG_DIR}/config.ini" "$KGSM_CONFIG_FILE" "KGSM_CONFIG_FILE should be in KGSM_CONFIG_DIR"
}

# =============================================================================
# DIRECTORY INITIALIZATION TESTS
# =============================================================================

function test_init_user_directories() {
  log_test_step "Testing user directories initialization"

  # Call init function
  __init_user_directories

  # Check all directories were created
  assert_dir_exists "$KGSM_CONFIG_DIR" "KGSM_CONFIG_DIR should exist"
  assert_dir_exists "$KGSM_DATA_DIR" "KGSM_DATA_DIR should exist"
  assert_dir_exists "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should exist"
  assert_dir_exists "$KGSM_LOGS_DIR" "KGSM_LOGS_DIR should exist"
  assert_dir_exists "$KGSM_USER_BLUEPRINTS_DIR" "KGSM_USER_BLUEPRINTS_DIR should exist"
  assert_dir_exists "$KGSM_USER_OVERRIDES_DIR" "KGSM_USER_OVERRIDES_DIR should exist"
}

# =============================================================================
# PATH VARIABLE VERIFICATION TESTS
# =============================================================================

function test_legacy_aliases_exported() {
  log_test_step "Testing legacy compatibility variables are exported"

  # Core path variables still exist
  assert_not_null "$KGSM_SYSTEM_BLUEPRINTS_DIR" "KGSM_SYSTEM_BLUEPRINTS_DIR should be set"
  assert_not_null "$KGSM_USER_BLUEPRINTS_DIR" "KGSM_USER_BLUEPRINTS_DIR should be set"
  assert_not_null "$KGSM_SYSTEM_OVERRIDES_DIR" "KGSM_SYSTEM_OVERRIDES_DIR should be set"
  assert_not_null "$KGSM_TEMPLATES_DIR" "KGSM_TEMPLATES_DIR should be set"
  assert_not_null "$KGSM_COMMANDS_DIR" "KGSM_COMMANDS_DIR should be set"
  assert_not_null "$KGSM_CORE_DIR" "KGSM_CORE_DIR should be set"
  assert_not_null "$KGSM_INSTANCES_DIR" "KGSM_INSTANCES_DIR should be set"
}

# =============================================================================
# LOAD GUARD TESTS
# =============================================================================

function test_paths_loaded_guard() {
  log_test_step "Testing KGSM_PATHS_LOADED guard prevents reload"

  # KGSM_PATHS_LOADED should be set
  assert_not_null "$KGSM_PATHS_LOADED" "KGSM_PATHS_LOADED should be set"

  # Verify guard value is set (can be '1', 'true', or any truthy value)
  assert_not_equals "0" "$KGSM_PATHS_LOADED" "KGSM_PATHS_LOADED should be truthy (non-zero)"
}

