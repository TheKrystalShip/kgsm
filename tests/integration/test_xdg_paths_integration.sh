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

  # Verify required functions exist (loader.sh functions)
  assert_function_exists "__find_blueprint" "__find_blueprint should be defined"
  assert_function_exists "__find_override" "__find_override should be defined"

  # Source files.common.sh to get __resolve_module for override directory tests
  local files_common_handler
  files_common_handler=$(__find_command_handler files.common.sh 2>/dev/null)
  if [[ -n "$files_common_handler" && -f "$files_common_handler" ]]; then
    # shellcheck disable=SC1090
    source "$files_common_handler"
  fi
  assert_function_exists "__resolve_module" "__resolve_module should be defined"
  assert_function_exists "__logic_assemble_management_file" "__logic_assemble_management_file should be defined"

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

  # Create legacy .overrides.sh test files (for __find_override backward compat testing)
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
# __resolve_module() TESTS - Directory-based override resolution
# =============================================================================

function test_resolve_module_system_override_directory() {
  log_test_step "Testing __resolve_module uses system override directory for overridable modules"

  # Create only a system override (no user override) so system path is returned
  mkdir -p "${KGSM_SYSTEM_OVERRIDES_DIR}/test-sysonly"
  echo '# System module override' > "${KGSM_SYSTEM_OVERRIDES_DIR}/test-sysonly/05-version.sh"

  local resolved
  resolved=$(__resolve_module "test-sysonly" "native" "05-version.sh")
  local exit_code=$?

  # Cleanup
  rm -rf "${KGSM_SYSTEM_OVERRIDES_DIR}/test-sysonly"

  assert_equals "0" "$exit_code" "Should succeed finding system module override"
  assert_equals "${KGSM_SYSTEM_OVERRIDES_DIR}/test-sysonly/05-version.sh" "$resolved" \
    "Should return system override directory path"
}

function test_resolve_module_user_override_directory_priority() {
  log_test_step "Testing __resolve_module: user override directory takes priority over system"

  # Create both user and system overrides; user should win
  mkdir -p "${KGSM_SYSTEM_OVERRIDES_DIR}/test-modpriority"
  echo '# System module override' > "${KGSM_SYSTEM_OVERRIDES_DIR}/test-modpriority/05-version.sh"
  mkdir -p "${KGSM_USER_OVERRIDES_DIR}/test-modpriority"
  echo '# User module override' > "${KGSM_USER_OVERRIDES_DIR}/test-modpriority/05-version.sh"

  local resolved
  resolved=$(__resolve_module "test-modpriority" "native" "05-version.sh")
  local exit_code=$?

  # Cleanup
  rm -rf "${KGSM_SYSTEM_OVERRIDES_DIR}/test-modpriority"
  rm -rf "${KGSM_USER_OVERRIDES_DIR}/test-modpriority"

  assert_equals "0" "$exit_code" "Should succeed finding user module override"
  assert_equals "${KGSM_USER_OVERRIDES_DIR}/test-modpriority/05-version.sh" "$resolved" \
    "User override directory should take priority over system override directory"
}

function test_resolve_module_non_overridable_ignores_override_dirs() {
  log_test_step "Testing __resolve_module ignores override directories for non-overridable modules"

  # Create an override for a non-overridable module (should be ignored)
  mkdir -p "${KGSM_USER_OVERRIDES_DIR}/test-nooverride"
  echo '# fake header' > "${KGSM_USER_OVERRIDES_DIR}/test-nooverride/00-header.sh"
  mkdir -p "${KGSM_SYSTEM_OVERRIDES_DIR}/test-nooverride"
  echo '# fake header' > "${KGSM_SYSTEM_OVERRIDES_DIR}/test-nooverride/00-header.sh"

  local resolved
  resolved=$(__resolve_module "test-nooverride" "native" "00-header.sh")
  local exit_code=$?

  # Cleanup
  rm -rf "${KGSM_USER_OVERRIDES_DIR}/test-nooverride"
  rm -rf "${KGSM_SYSTEM_OVERRIDES_DIR}/test-nooverride"

  local expected_default="${KGSM_TEMPLATES_DIR}/manage.native.d/00-header.sh"
  assert_equals "0" "$exit_code" "Should succeed for non-overridable module"
  assert_equals "$expected_default" "$resolved" \
    "Non-overridable module 00-header.sh must always use default, ignoring override dirs"

  if grep -q "FAKE HEADER OVERRIDE" "$resolved" 2>/dev/null; then
    fail_test "Non-overridable module should not be replaced by user override"
  fi
}

function test_override_directories_exist_for_known_games() {
  log_test_step "Testing override directories exist for games with module overrides"

  # These games have known module overrides in the system overrides directory
  assert_dir_exists "${KGSM_SYSTEM_OVERRIDES_DIR}/factorio" \
    "factorio should have a system override directory"
  assert_dir_exists "${KGSM_SYSTEM_OVERRIDES_DIR}/terraria" \
    "terraria should have a system override directory"
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

