#!/usr/bin/env bash

# KGSM Files Common Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/files.common.sh
#
# Tests all logic functions from files.common.sh:
# - __logic_inject_overrides()
# - __logic_set_file_ownership()
#
# Uses real blueprints:
# - factorio (native, has overrides)
# - terraria (native, has overrides)
# - necesse (native, no overrides)
# - vrising (container)

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
# shellcheck disable=SC2034
readonly TEST_NAME="files_common_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.common.sh"

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# Create a minimal management file with placeholder functions for testing
# Args: $1 = output_path
# Returns: 0 on success
function __create_temp_management_file() {
  local output_path="$1"

  cat > "$output_path" << 'MGMT_EOF'
#!/usr/bin/env bash

# Temporary management script for testing

function _get_latest_version() {
  echo "placeholder_version"
  return 0
}

function _download() {
  echo "placeholder_download"
  return 1
}

function _deploy() {
  echo "placeholder_deploy"
  return 1
}

MGMT_EOF

  chmod +x "$output_path"
  return 0
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up files.common logic tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"

  # Verify handler exists
  assert_file_exists "$HANDLER" "Handler file should exist"

  # Source the handler
  # shellcheck disable=SC1090
  source "$HANDLER"

  # Verify module loaded
  assert_not_null "$KGSM_LOGIC_FILES_COMMON_LOADED" "Handler should be loaded"

  # Verify error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_INSTANCE" "EC_INVALID_INSTANCE should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FAILED_SOURCE" "EC_FAILED_SOURCE should be defined"
  assert_not_null "$EC_FAILED_TEMPLATE" "EC_FAILED_TEMPLATE should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"

  # Verify functions are exported
  assert_function_exists "__logic_inject_overrides" "__logic_inject_overrides should be exported (no-op for backward compat)"
  assert_function_exists "__logic_assemble_management_file" "__logic_assemble_management_file should be exported"
  assert_function_exists "__resolve_module" "__resolve_module should be exported"
  assert_function_exists "__logic_set_file_ownership" "__logic_set_file_ownership should be exported"

  # Verify test blueprints exist
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/factorio.bp" "Factorio blueprint should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/terraria.bp" "Terraria blueprint should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/necesse.bp" "Necesse blueprint should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR/vrising.docker-compose.yml" "VRising blueprint should exist"

  # Verify module override directories for testing (new directory-based structure)
  assert_dir_exists "$KGSM_SYSTEM_OVERRIDES_DIR/factorio" "Factorio override directory should exist"
  assert_dir_exists "$KGSM_SYSTEM_OVERRIDES_DIR/terraria" "Terraria override directory should exist"

  # Verify necesse does NOT have an override directory (for no-override testing)
  assert_dir_not_exists "$KGSM_SYSTEM_OVERRIDES_DIR/necesse" "Necesse should NOT have override directory"

  log_test_step "Environment validated"
}

# =============================================================================
# __logic_inject_overrides() TESTS
# (This function is now a no-op retained for backward compatibility.)
# All calls return 0 regardless of arguments.
# =============================================================================

function test_inject_overrides_empty_instance_name() {
  log_test_step "Testing __logic_inject_overrides is a no-op with empty instance name"

  local temp_file="$KGSM_TEST_SANDBOX/temp_manage_empty_instance_$$.sh"
  __create_temp_management_file "$temp_file"

  __logic_inject_overrides "" "$temp_file" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "No-op should return 0 for any input"

  rm -f "$temp_file"
}

function test_inject_overrides_empty_management_file() {
  log_test_step "Testing __logic_inject_overrides is a no-op with empty management file path"

  __logic_inject_overrides "some-instance" "" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "No-op should return 0 for any input"
}

function test_inject_overrides_management_file_not_found() {
  log_test_step "Testing __logic_inject_overrides is a no-op with non-existent management file"

  __logic_inject_overrides "some-instance" "/nonexistent/path/manage.sh" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "No-op should return 0 for any input"
}

function test_inject_overrides_instance_not_found() {
  log_test_step "Testing __logic_inject_overrides is a no-op with non-existent instance"

  local temp_file="$KGSM_TEST_SANDBOX/temp_manage_instance_notfound_$$.sh"
  __create_temp_management_file "$temp_file"

  __logic_inject_overrides "nonexistent-instance-xyz-12345" "$temp_file" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "No-op should return 0 for any input"

  rm -f "$temp_file"
}

function test_inject_overrides_missing_blueprint_file_config() {
  log_test_step "Testing __logic_inject_overrides is a no-op regardless of missing blueprint_file"

  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_missing_bp_$$.sh"
  __create_temp_management_file "$temp_manage"

  __logic_inject_overrides "any-instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "No-op should return 0 for any input"

  rm -f "$temp_manage"
}

function test_inject_overrides_missing_blueprint_name() {
  log_test_step "Testing __logic_inject_overrides is a no-op regardless of missing blueprint name"

  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_missing_name_$$.sh"
  __create_temp_management_file "$temp_manage"

  __logic_inject_overrides "any-instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "No-op should return 0 for any input"

  rm -f "$temp_manage"
}

function test_inject_overrides_container_blueprint_skips() {
  log_test_step "Testing __logic_inject_overrides is a no-op (container or otherwise)"

  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_container_$$.sh"
  __create_temp_management_file "$temp_manage"
  local original_content
  original_content=$(cat "$temp_manage")

  __logic_inject_overrides "any-instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  local new_content
  new_content=$(cat "$temp_manage")

  assert_equals "0" "$exit_code" "No-op should return 0"
  assert_equals "$original_content" "$new_content" "No-op should not modify the management file"

  rm -f "$temp_manage"
}

function test_inject_overrides_no_override_file_exists() {
  log_test_step "Testing __logic_inject_overrides is a no-op (does not modify file)"

  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_no_override_$$.sh"
  __create_temp_management_file "$temp_manage"
  local original_content
  original_content=$(cat "$temp_manage")

  __logic_inject_overrides "any-instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  local new_content
  new_content=$(cat "$temp_manage")

  assert_equals "0" "$exit_code" "No-op should return 0"
  assert_equals "$original_content" "$new_content" "No-op should not modify the management file"

  rm -f "$temp_manage"
}

function test_inject_overrides_success_with_overrides() {
  log_test_step "Testing __logic_inject_overrides is a no-op even when override directories exist"

  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_success_$$.sh"
  __create_temp_management_file "$temp_manage"
  local original_content
  original_content=$(cat "$temp_manage")

  __logic_inject_overrides "any-instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  local new_content
  new_content=$(cat "$temp_manage")

  assert_equals "0" "$exit_code" "No-op should return 0"
  assert_equals "$original_content" "$new_content" "No-op should not modify the management file"

  rm -f "$temp_manage"
}

function test_inject_overrides_corrupt_override_file() {
  log_test_step "Testing __logic_inject_overrides is a no-op even with corrupt inputs"

  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_corrupt_$$.sh"
  __create_temp_management_file "$temp_manage"

  __logic_inject_overrides "any-instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "No-op should return 0"

  rm -f "$temp_manage"
}

# =============================================================================
# __resolve_module() TESTS
# =============================================================================

function test_resolve_module_non_overridable_always_default() {
  log_test_step "Testing __resolve_module returns default for non-overridable modules"

  # Modules 00, 01, 02, 12, 13 are non-overridable
  for module in "00-header.sh" "01-config.sh" "02-help.sh" "12-commands.sh" "13-dispatch.sh"; do
    # Create user and system overrides for these modules (should be ignored)
    mkdir -p "$KGSM_USER_OVERRIDES_DIR/fakegame"
    echo "# fake user override" > "$KGSM_USER_OVERRIDES_DIR/fakegame/${module}"
    mkdir -p "$KGSM_SYSTEM_OVERRIDES_DIR/fakegame"
    echo "# fake system override" > "$KGSM_SYSTEM_OVERRIDES_DIR/fakegame/${module}"

    local resolved
    resolved=$(__resolve_module "fakegame" "native" "$module")
    local exit_code=$?

    local expected_default="${KGSM_TEMPLATES_DIR}/manage.native.d/${module}"
    assert_equals "0" "$exit_code" "Should succeed for non-overridable module $module"
    assert_equals "$expected_default" "$resolved" "Non-overridable $module should always use default"
  done

  # Cleanup
  rm -rf "$KGSM_USER_OVERRIDES_DIR/fakegame" "$KGSM_SYSTEM_OVERRIDES_DIR/fakegame"
}

function test_resolve_module_overridable_uses_default_when_no_override() {
  log_test_step "Testing __resolve_module returns default for overridable module with no override"

  # Module 05-version.sh is overridable; use a game with no overrides
  local resolved
  resolved=$(__resolve_module "necesse" "native" "05-version.sh")
  local exit_code=$?

  local expected_default="${KGSM_TEMPLATES_DIR}/manage.native.d/05-version.sh"
  assert_equals "0" "$exit_code" "Should succeed when no override exists"
  assert_equals "$expected_default" "$resolved" "Should fall back to default when no override"
}

function test_resolve_module_system_override() {
  log_test_step "Testing __resolve_module uses system override directory"

  # factorio has a system override for 05-version.sh
  local resolved
  resolved=$(__resolve_module "factorio" "native" "05-version.sh")
  local exit_code=$?

  local expected_system="${KGSM_SYSTEM_OVERRIDES_DIR}/factorio/05-version.sh"
  assert_equals "0" "$exit_code" "Should succeed finding system override"
  assert_equals "$expected_system" "$resolved" "Should use system override when present"
}

function test_resolve_module_user_override_priority() {
  log_test_step "Testing __resolve_module: user override takes priority over system override"

  # Create a user override for a module that also has a system override
  mkdir -p "$KGSM_USER_OVERRIDES_DIR/factorio"
  echo "# user version override" > "$KGSM_USER_OVERRIDES_DIR/factorio/05-version.sh"

  local resolved
  resolved=$(__resolve_module "factorio" "native" "05-version.sh")
  local exit_code=$?

  local expected_user="${KGSM_USER_OVERRIDES_DIR}/factorio/05-version.sh"
  assert_equals "0" "$exit_code" "Should succeed finding user override"
  assert_equals "$expected_user" "$resolved" "User override should take priority over system override"

  # Cleanup
  rm -f "$KGSM_USER_OVERRIDES_DIR/factorio/05-version.sh"
  rmdir "$KGSM_USER_OVERRIDES_DIR/factorio" 2>/dev/null || true
}

function test_resolve_module_empty_blueprint_uses_default() {
  log_test_step "Testing __resolve_module with empty blueprint_name uses default"

  local resolved
  resolved=$(__resolve_module "" "native" "05-version.sh")
  local exit_code=$?

  local expected_default="${KGSM_TEMPLATES_DIR}/manage.native.d/05-version.sh"
  assert_equals "0" "$exit_code" "Should succeed with empty blueprint name"
  assert_equals "$expected_default" "$resolved" "Empty blueprint name should use default module"
}

function test_resolve_module_invalid_module_not_found() {
  log_test_step "Testing __resolve_module returns EC_FILE_NOT_FOUND for non-existent module"

  __resolve_module "factorio" "native" "99-nonexistent.sh" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing module"
}

# =============================================================================
# __logic_assemble_management_file() TESTS
# =============================================================================

function test_assemble_management_file_empty_runtime() {
  log_test_step "Testing __logic_assemble_management_file with empty runtime"

  local out_file="$KGSM_TEST_SANDBOX/assemble_test_$$.sh"

  __logic_assemble_management_file "" "factorio" "$out_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty runtime"

  rm -f "$out_file"
}

function test_assemble_management_file_empty_output_file() {
  log_test_step "Testing __logic_assemble_management_file with empty output file"

  __logic_assemble_management_file "native" "factorio" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty output file"
}

function test_assemble_management_file_invalid_runtime() {
  log_test_step "Testing __logic_assemble_management_file with non-existent runtime"

  local out_file="$KGSM_TEST_SANDBOX/assemble_invalid_runtime_$$.sh"

  __logic_assemble_management_file "nonexistent_runtime" "factorio" "$out_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for invalid runtime"

  rm -f "$out_file"
}

function test_assemble_management_file_native_success() {
  log_test_step "Testing __logic_assemble_management_file succeeds for native runtime"

  local out_file="$KGSM_TEST_SANDBOX/assemble_native_$$.sh"

  __logic_assemble_management_file "native" "" "$out_file"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful native assembly"
  assert_file_exists "$out_file" "Output file should be created"
  assert_file_contains "$out_file" "#!/usr/bin/env bash" "Assembled file should start with shebang"

  rm -f "$out_file"
}

function test_assemble_management_file_container_success() {
  log_test_step "Testing __logic_assemble_management_file succeeds for container runtime"

  local out_file="$KGSM_TEST_SANDBOX/assemble_container_$$.sh"

  __logic_assemble_management_file "container" "" "$out_file"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful container assembly"
  assert_file_exists "$out_file" "Output file should be created"
  assert_file_contains "$out_file" "#!/usr/bin/env bash" "Assembled file should start with shebang"

  rm -f "$out_file"
}

function test_assemble_management_file_applies_module_overrides() {
  log_test_step "Testing __logic_assemble_management_file applies factorio module overrides"

  local out_file="$KGSM_TEST_SANDBOX/assemble_factorio_$$.sh"

  # factorio has system overrides for 05-version.sh, 06-download.sh, 07-deploy.sh
  __logic_assemble_management_file "native" "factorio" "$out_file"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful assembly with overrides"
  assert_file_exists "$out_file" "Output file should be created"
  # Factorio 05-version.sh override uses factorio.com API
  assert_file_contains "$out_file" "factorio.com" "Should contain factorio-specific override content"

  rm -f "$out_file"
}

function test_assemble_management_file_non_overridable_modules_immutable() {
  log_test_step "Testing __logic_assemble_management_file keeps non-overridable modules unchanged"

  # Create a user override for a non-overridable module
  mkdir -p "$KGSM_USER_OVERRIDES_DIR/fakegame"
  echo "# FAKE HEADER OVERRIDE" > "$KGSM_USER_OVERRIDES_DIR/fakegame/00-header.sh"

  local out_file="$KGSM_TEST_SANDBOX/assemble_nonoverridable_$$.sh"

  __logic_assemble_management_file "native" "fakegame" "$out_file"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful assembly"

  # The fake header should NOT appear; the real header (shebang) should
  assert_file_contains "$out_file" "#!/usr/bin/env bash" "Should use real header, not fake override"
  if grep -q "FAKE HEADER OVERRIDE" "$out_file" 2>/dev/null; then
    fail_test "Non-overridable module should not be replaced by user override"
  fi

  # Cleanup
  rm -rf "$KGSM_USER_OVERRIDES_DIR/fakegame"
  rm -f "$out_file"
}

# =============================================================================
# __logic_set_file_ownership() TESTS
# =============================================================================

function test_set_file_ownership_empty_path() {
  log_test_step "Testing __logic_set_file_ownership with empty path"

  __logic_set_file_ownership "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty path"
}

function test_set_file_ownership_file_not_found() {
  log_test_step "Testing __logic_set_file_ownership with non-existent file"

  __logic_set_file_ownership "/nonexistent/path/file.txt" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing file"
}

function test_set_file_ownership_success_file() {
  log_test_step "Testing __logic_set_file_ownership with regular file"

  local test_file="$KGSM_TEST_SANDBOX/test_ownership_file_$$.txt"
  touch "$test_file"

  __logic_set_file_ownership "$test_file" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful file ownership change"

  # Verify file still exists
  assert_file_exists "$test_file" "File should still exist after ownership change"

  # Cleanup
  rm -f "$test_file"
}

function test_set_file_ownership_success_directory() {
  log_test_step "Testing __logic_set_file_ownership with directory"

  local test_dir="$KGSM_TEST_SANDBOX/test_ownership_dir_$$"
  mkdir -p "$test_dir"

  __logic_set_file_ownership "$test_dir" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful directory ownership change"

  # Verify directory still exists
  assert_dir_exists "$test_dir" "Directory should still exist after ownership change"

  # Cleanup
  rm -rf "$test_dir"
}

function test_set_file_ownership_permission_denied() {
  log_test_step "Testing __logic_set_file_ownership permission denied scenario"

  # This test only makes sense when NOT running as root
  if [[ "$EUID" -eq 0 ]]; then
    log_info "Skipping permission test - running as root"
    skip_test "Cannot test permission denial as root"
    return 0
  fi

  # Try to change ownership on a system file we don't own
  # /etc/passwd is a safe choice - readable but not chown-able by regular users
  __logic_set_file_ownership "/etc/passwd" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_PERMISSION" "$exit_code" "Should return EC_PERMISSION when chown fails"
}

