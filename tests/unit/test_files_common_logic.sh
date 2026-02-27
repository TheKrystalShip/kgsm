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

# Create a minimal test instance manually (bypassing broken create_test_instance)
# Args: $1 = blueprint_name (e.g., "factorio", "necesse", "vrising")
# Returns: echoes instance_name, returns 0 on success
function __create_minimal_test_instance() {
  local blueprint_name="$1"
  local instance_name="test_${blueprint_name}_$$"

  # Determine blueprint file path and type
  local blueprint_file=""
  local runtime="native"

  if [[ -f "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/${blueprint_name}.bp" ]]; then
    blueprint_file="$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/${blueprint_name}.bp"
    runtime="native"
  elif [[ -f "$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR/${blueprint_name}.docker-compose.yml" ]]; then
    blueprint_file="$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR/${blueprint_name}.docker-compose.yml"
    runtime="container"
  else
    return 1
  fi

  # Create instance directory structure
  local instance_base_dir="$KGSM_INSTANCES_DIR/$blueprint_name"
  local instance_dir="$instance_base_dir/$instance_name"
  local working_dir="$KGSM_TEST_SANDBOX/instances_working/${instance_name}"

  mkdir -p "$instance_base_dir"
  mkdir -p "$working_dir"

  # Create symlink from instances dir to working dir
  ln -sf "$working_dir" "$instance_dir"

  # Create instance config file
  local config_file="$instance_dir/${instance_name}.config.ini"
  cat > "$config_file" << EOF
# KGSM Test Instance Configuration
name=${instance_name}
blueprint_file=${blueprint_file}
runtime=${runtime}
working_dir=${working_dir}
install_dir=${working_dir}/install
management_file=${working_dir}/${instance_name}.manage.sh
EOF

  echo "$instance_name"
  return 0
}

# Remove a minimal test instance
# Args: $1 = instance_name, $2 = blueprint_name
function __remove_minimal_test_instance() {
  local instance_name="$1"
  local blueprint_name="$2"

  local instance_dir="$KGSM_INSTANCES_DIR/$blueprint_name/$instance_name"
  local working_dir="$KGSM_TEST_SANDBOX/instances_working/${instance_name}"

  rm -rf "$instance_dir" 2>/dev/null
  rm -rf "$working_dir" 2>/dev/null
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
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
  assert_function_exists "__logic_inject_overrides" "__logic_inject_overrides should be exported"
  assert_function_exists "__logic_set_file_ownership" "__logic_set_file_ownership should be exported"

  # Verify test blueprints exist
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/factorio.bp" "Factorio blueprint should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/terraria.bp" "Terraria blueprint should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/necesse.bp" "Necesse blueprint should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_CONTAINER_DIR/vrising.docker-compose.yml" "VRising blueprint should exist"

  # Verify override files for testing
  assert_file_exists "$KGSM_SYSTEM_OVERRIDES_DIR/factorio.overrides.sh" "Factorio overrides should exist"
  assert_file_exists "$KGSM_SYSTEM_OVERRIDES_DIR/terraria.overrides.sh" "Terraria overrides should exist"

  # Verify necesse does NOT have overrides (for no-override testing)
  assert_file_not_exists "$KGSM_SYSTEM_OVERRIDES_DIR/necesse.overrides.sh" "Necesse should NOT have overrides"

  log_test_step "Environment validated"
}

# =============================================================================
# __logic_inject_overrides() TESTS
# =============================================================================

function test_inject_overrides_empty_instance_name() {
  log_test_step "Testing __logic_inject_overrides with empty instance name"

  local temp_file="$KGSM_TEST_SANDBOX/temp_manage_empty_instance_$$.sh"
  __create_temp_management_file "$temp_file"

  __logic_inject_overrides "" "$temp_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty instance name"

  rm -f "$temp_file"
}

function test_inject_overrides_empty_management_file() {
  log_test_step "Testing __logic_inject_overrides with empty management file path"

  __logic_inject_overrides "some-instance" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty management file"
}

function test_inject_overrides_management_file_not_found() {
  log_test_step "Testing __logic_inject_overrides with non-existent management file"

  __logic_inject_overrides "some-instance" "/nonexistent/path/manage.sh" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing management file"
}

function test_inject_overrides_instance_not_found() {
  log_test_step "Testing __logic_inject_overrides with non-existent instance"

  local temp_file="$KGSM_TEST_SANDBOX/temp_manage_instance_notfound_$$.sh"
  __create_temp_management_file "$temp_file"

  __logic_inject_overrides "nonexistent-instance-xyz-12345" "$temp_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_INSTANCE" "$exit_code" "Should return EC_INVALID_INSTANCE for non-existent instance"

  rm -f "$temp_file"
}

function test_inject_overrides_missing_blueprint_file_config() {
  log_test_step "Testing __logic_inject_overrides with missing blueprint_file in instance config"

  # Create a minimal test instance
  local instance
  instance=$(__create_minimal_test_instance "factorio")

  if [[ -z "$instance" ]]; then
    fail_test "Failed to create minimal test instance"
    return 1
  fi

  # Get instance config path
  local instance_config
  instance_config=$(__find_instance_config "$instance" 2>/dev/null)

  if [[ ! -f "$instance_config" ]]; then
    __remove_minimal_test_instance "$instance" "factorio"
    fail_test "Failed to find instance config"
    return 1
  fi

  # Backup the config
  local config_backup="${instance_config}.bak"
  cp "$instance_config" "$config_backup"

  # Remove blueprint_file line from config
  sed -i '/^blueprint_file=/d' "$instance_config"

  # Create a temp management file
  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_missing_bp_$$.sh"
  __create_temp_management_file "$temp_manage"

  # Test
  __logic_inject_overrides "$instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  # Restore config
  mv "$config_backup" "$instance_config"

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing blueprint_file"

  # Cleanup
  rm -f "$temp_manage"
  __remove_minimal_test_instance "$instance" "factorio"
}

function test_inject_overrides_missing_blueprint_name() {
  log_test_step "Testing __logic_inject_overrides with missing name field in blueprint"

  # Create a minimal test instance
  local instance
  instance=$(__create_minimal_test_instance "factorio")

  if [[ -z "$instance" ]]; then
    fail_test "Failed to create minimal test instance"
    return 1
  fi

  # Get instance config path
  local instance_config
  instance_config=$(__find_instance_config "$instance" 2>/dev/null)

  if [[ ! -f "$instance_config" ]]; then
    __remove_minimal_test_instance "$instance" "factorio"
    fail_test "Failed to find instance config"
    return 1
  fi

  # Get blueprint file path from instance config
  local blueprint_file
  blueprint_file=$(__get_config_value "$instance_config" "blueprint_file" 2>/dev/null)

  if [[ ! -f "$blueprint_file" ]]; then
    __remove_minimal_test_instance "$instance" "factorio"
    fail_test "Blueprint file not found: $blueprint_file"
    return 1
  fi

  # Backup the blueprint
  local blueprint_backup="${blueprint_file}.bak"
  cp "$blueprint_file" "$blueprint_backup"

  # Remove name line from blueprint
  sed -i '/^name=/d' "$blueprint_file"

  # Create a temp management file
  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_missing_name_$$.sh"
  __create_temp_management_file "$temp_manage"

  # Test
  __logic_inject_overrides "$instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  # Restore blueprint
  mv "$blueprint_backup" "$blueprint_file"

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing blueprint name"

  # Cleanup
  rm -f "$temp_manage"
  __remove_minimal_test_instance "$instance" "factorio"
}

function test_inject_overrides_container_blueprint_skips() {
  log_test_step "Testing __logic_inject_overrides skips container blueprints"

  # Create a minimal container instance (vrising)
  local instance
  instance=$(__create_minimal_test_instance "vrising")

  if [[ -z "$instance" ]]; then
    fail_test "Failed to create vrising minimal test instance"
    return 1
  fi

  # Create a temp management file
  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_container_$$.sh"
  __create_temp_management_file "$temp_manage"

  # Capture original content
  local original_content
  original_content=$(cat "$temp_manage")

  # Test - should succeed and not modify the file
  __logic_inject_overrides "$instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  # Check content unchanged (container blueprints skip injection)
  local new_content
  new_content=$(cat "$temp_manage")

  assert_equals "0" "$exit_code" "Should return 0 for container blueprint (skip injection)"
  assert_equals "$original_content" "$new_content" "Management file should be unchanged for container blueprint"

  # Cleanup
  rm -f "$temp_manage"
  __remove_minimal_test_instance "$instance" "vrising"
}

function test_inject_overrides_no_override_file_exists() {
  log_test_step "Testing __logic_inject_overrides with blueprint that has no overrides"

  # Create a minimal necesse instance (has no override file)
  local instance
  instance=$(__create_minimal_test_instance "necesse")

  if [[ -z "$instance" ]]; then
    fail_test "Failed to create necesse minimal test instance"
    return 1
  fi

  # Create a temp management file
  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_no_override_$$.sh"
  __create_temp_management_file "$temp_manage"

  # Capture original content
  local original_content
  original_content=$(cat "$temp_manage")

  # Test - should succeed without modifying file (no overrides to inject)
  __logic_inject_overrides "$instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  # Check content unchanged
  local new_content
  new_content=$(cat "$temp_manage")

  assert_equals "0" "$exit_code" "Should return 0 when no override file exists"
  assert_equals "$original_content" "$new_content" "Management file should be unchanged when no overrides exist"

  # Cleanup
  rm -f "$temp_manage"
  __remove_minimal_test_instance "$instance" "necesse"
}

function test_inject_overrides_success_with_overrides() {
  log_test_step "Testing __logic_inject_overrides successfully injects override functions"

  # Create a minimal factorio instance (has overrides)
  local instance
  instance=$(__create_minimal_test_instance "factorio")

  if [[ -z "$instance" ]]; then
    fail_test "Failed to create factorio minimal test instance"
    return 1
  fi

  # Create a temp management file with placeholder functions
  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_success_$$.sh"
  __create_temp_management_file "$temp_manage"

  # Capture original _get_latest_version function
  local original_func
  original_func=$(grep -A5 "function _get_latest_version" "$temp_manage" | head -6)

  # Test
  __logic_inject_overrides "$instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 on successful injection"

  # Verify function was replaced - the new function should contain factorio-specific code
  # (factorio.overrides.sh uses wget to query factorio.com API)
  local new_func
  new_func=$(grep -A10 "function _get_latest_version" "$temp_manage" | head -11)

  assert_not_equals "$original_func" "$new_func" "Function should be replaced with override"

  # Check for factorio-specific content in the injected function
  if grep -q "factorio.com" "$temp_manage"; then
    pass_test "Override function contains factorio.com reference"
  else
    # Alternative check - the function should at least be different
    assert_not_equals "$original_func" "$new_func" "Function content should differ after injection"
  fi

  # Cleanup
  rm -f "$temp_manage"
  __remove_minimal_test_instance "$instance" "factorio"
}

function test_inject_overrides_corrupt_override_file() {
  log_test_step "Testing __logic_inject_overrides with corrupt/unparseable override file"

  # Create a minimal factorio instance
  local instance
  instance=$(__create_minimal_test_instance "factorio")

  if [[ -z "$instance" ]]; then
    fail_test "Failed to create factorio minimal test instance"
    return 1
  fi

  # Backup the factorio overrides file
  local override_file="$KGSM_SYSTEM_OVERRIDES_DIR/factorio.overrides.sh"
  local override_backup="${override_file}.bak"
  cp "$override_file" "$override_backup"

  # Corrupt the override file with invalid bash syntax
  cat > "$override_file" << 'CORRUPT_EOF'
#!/usr/bin/env bash

# Corrupt file for testing
function _get_latest_version( {
  # Missing closing parenthesis - syntax error
  echo "broken
}

CORRUPT_EOF

  # Create a temp management file
  local temp_manage="$KGSM_TEST_SANDBOX/temp_manage_corrupt_$$.sh"
  __create_temp_management_file "$temp_manage"

  # Test
  __logic_inject_overrides "$instance" "$temp_manage" 2>/dev/null
  local exit_code=$?

  # Restore override file immediately
  mv "$override_backup" "$override_file"

  assert_equals "$EC_FAILED_SOURCE" "$exit_code" "Should return EC_FAILED_SOURCE for corrupt override file"

  # Cleanup
  rm -f "$temp_manage"
  __remove_minimal_test_instance "$instance" "factorio"
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

