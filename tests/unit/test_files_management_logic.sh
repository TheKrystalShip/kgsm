#!/usr/bin/env bash

# KGSM File Management Logic Handler Unit Tests

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="files_management_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.management.sh"

# =============================================================================
# TEST SETUP FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up files.management logic tests"

  # Verify environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"

  # Verify handler exists
  assert_file_exists "$HANDLER" "Handler file should exist"

  # Source the handler
  # shellcheck disable=SC1090
  source "$HANDLER"

  # Verify module loaded
  assert_not_null "$KGSM_LOGIC_FILES_MANAGEMENT_LOADED" "Handler should be loaded"

  # Verify required template module directories exist
  assert_dir_exists "$KGSM_ROOT/templates/manage.native.d" "Native management template directory should exist"
  assert_dir_exists "$KGSM_ROOT/templates/manage.container.d" "Container management template directory should exist"

  log_test_step "Environment validated"
}

# =============================================================================
# __logic_create_container_compose_file() TESTS
# =============================================================================

function test_create_container_compose_empty_parameter() {
  log_test_step "Testing __logic_create_container_compose_file with empty parameter"

  __logic_create_container_compose_file ""
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty parameter"
}

function test_create_container_compose_file_not_found() {
  log_test_step "Testing __logic_create_container_compose_file with non-existent config"

  __logic_create_container_compose_file "/nonexistent/config.ini"
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing config"
}

function test_create_container_compose_missing_name() {
  log_test_step "Testing __logic_create_container_compose_file with missing name field"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_missing_name"
  mkdir -p "$test_dir"

  # Create config without name field
  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
blueprint_file=/some/blueprint.yml
working_dir=$test_dir
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing name"

  rm -rf "$test_dir"
}

function test_create_container_compose_missing_blueprint_file() {
  log_test_step "Testing __logic_create_container_compose_file with missing blueprint_file field"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_missing_blueprint"
  mkdir -p "$test_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
working_dir=$test_dir
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing blueprint_file"

  rm -rf "$test_dir"
}

function test_create_container_compose_missing_working_dir() {
  log_test_step "Testing __logic_create_container_compose_file with missing working_dir field"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_missing_workdir"
  mkdir -p "$test_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
blueprint_file=/some/blueprint.yml
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing working_dir"

  rm -rf "$test_dir"
}

function test_create_container_compose_blueprint_not_found() {
  log_test_step "Testing __logic_create_container_compose_file with non-existent blueprint"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_blueprint_missing"
  mkdir -p "$test_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
blueprint_file=/nonexistent/blueprint.yml
working_dir=$test_dir
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing blueprint"

  rm -rf "$test_dir"
}

function test_create_container_compose_template_expansion_fails() {
  log_test_step "Testing __logic_create_container_compose_file with template expansion failure"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_template_fail"
  mkdir -p "$test_dir"

  # Create a blueprint with invalid template syntax
  local blueprint_file="$test_dir/bad_template.yml"
  cat > "$blueprint_file" << 'EOF'
version: "3"
services:
  invalid_syntax: $(this will cause expansion to fail
EOF

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
working_dir=$test_dir
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_FAILED_TEMPLATE" "$exit_code" "Should return EC_FAILED_TEMPLATE for expansion failure"

  rm -rf "$test_dir"
}

function test_create_container_compose_readonly_working_dir() {
  log_test_step "Testing __logic_create_container_compose_file with readonly working directory"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_readonly"
  mkdir -p "$test_dir"
  chmod 555 "$test_dir"

  local blueprint_file="$KGSM_TEST_SANDBOX/test_blueprint.yml"
  cat > "$blueprint_file" << EOF
version: "3"
services:
  test: {}
EOF

  local config_file="$KGSM_TEST_SANDBOX/readonly_test.ini"
  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
working_dir=$test_dir
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  # Restore permissions for cleanup
  chmod 755 "$test_dir"

  assert_equals "$EC_FAILED_TEMPLATE" "$exit_code" "Should return EC_FAILED_TEMPLATE for readonly directory"

  rm -rf "$test_dir" "$blueprint_file" "$config_file"
}

function test_create_container_compose_success() {
  log_test_step "Testing __logic_create_container_compose_file success case"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_success"
  mkdir -p "$test_dir"

  # Create a simple blueprint
  local blueprint_file="$test_dir/blueprint.yml"
  cat > "$blueprint_file" << EOF
version: "3"
services:
  gameserver:
    image: test/image:latest
    ports:
      - "27015:27015"
EOF

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
working_dir=$test_dir
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 on success"
  assert_file_exists "$test_dir/testinstance.docker-compose.yml" "Should create docker-compose file"

  rm -rf "$test_dir"
}

function test_create_container_compose_with_env_vars() {
  log_test_step "Testing __logic_create_container_compose_file with environment variable expansion"

  local test_dir="$KGSM_TEST_SANDBOX/compose_test_env_vars"
  mkdir -p "$test_dir"

  # Create blueprint with variable references
  local blueprint_file="$test_dir/blueprint.yml"
  cat > "$blueprint_file" << 'EOF'
version: "3"
services:
  gameserver:
    image: test/image:${instance_name}
    environment:
      - SERVER_NAME=${instance_name}
EOF

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=myserver
blueprint_file=$blueprint_file
working_dir=$test_dir
EOF

  __logic_create_container_compose_file "$config_file"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 on success"

  local compose_file="$test_dir/myserver.docker-compose.yml"
  assert_file_exists "$compose_file" "Should create docker-compose file"
  assert_file_contains "$compose_file" "myserver" "Should expand instance_name variable"

  rm -rf "$test_dir"
}

# =============================================================================
# __logic_create_management_file() TESTS
# =============================================================================

function test_create_management_file_empty_parameter() {
  log_test_step "Testing __logic_create_management_file with empty parameter"

  __logic_create_management_file ""
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty parameter"
}

function test_create_management_file_config_not_found() {
  log_test_step "Testing __logic_create_management_file with non-existent config"

  __logic_create_management_file "/nonexistent/config.ini"
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing config"
}

function test_create_management_file_missing_name() {
  log_test_step "Testing __logic_create_management_file with missing name field"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_missing_name"
  mkdir -p "$test_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
runtime=native
management_file=$test_dir/manage.sh
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing name"

  rm -rf "$test_dir"
}

function test_create_management_file_missing_runtime() {
  log_test_step "Testing __logic_create_management_file with missing runtime field"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_missing_runtime"
  mkdir -p "$test_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
management_file=$test_dir/manage.sh
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing runtime"

  rm -rf "$test_dir"
}

function test_create_management_file_missing_management_file() {
  log_test_step "Testing __logic_create_management_file with missing management_file field"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_missing_mgmt_file"
  mkdir -p "$test_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
runtime=native
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing management_file"

  rm -rf "$test_dir"
}

function test_create_management_file_invalid_runtime() {
  log_test_step "Testing __logic_create_management_file with invalid runtime"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_invalid_runtime_$$"
  mkdir -p "$test_dir"

  local blueprint_file="$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/factorio.bp"
  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
runtime=invalid_runtime
management_file=$test_dir/manage.sh
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  # invalid_runtime has no module directory → __logic_assemble_management_file
  # fails with EC_FILE_NOT_FOUND → __logic_create_management_file wraps as EC_FAILED_TEMPLATE
  assert_equals "$EC_FAILED_TEMPLATE" "$exit_code" "Should return EC_FAILED_TEMPLATE for invalid runtime"

  rm -rf "$test_dir"
}

function test_create_management_file_copy_fails() {
  log_test_step "Testing __logic_create_management_file with copy failure"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_copy_fail"
  mkdir -p "$test_dir"

  # Create readonly destination directory
  local readonly_dir="$test_dir/readonly"
  mkdir -p "$readonly_dir"
  chmod 555 "$readonly_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
runtime=native
management_file=$readonly_dir/manage.sh
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  # Restore permissions for cleanup
  chmod 755 "$readonly_dir"

  assert_equals "$EC_FAILED_TEMPLATE" "$exit_code" "Should return EC_FAILED_TEMPLATE for copy failure"

  rm -rf "$test_dir"
}

function test_create_management_file_replaces_existing() {
  log_test_step "Testing __logic_create_management_file replaces existing file"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_replace_$$"
  mkdir -p "$test_dir"

  local blueprint_file="$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/factorio.bp"
  local mgmt_file="$test_dir/manage.sh"
  local config_file="$test_dir/test.ini"

  # Create existing management file with marker
  echo "# OLD MANAGEMENT FILE" > "$mgmt_file"

  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
runtime=native
management_file=$mgmt_file
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_MANAGEMENT_FILE_CREATED" "$exit_code" "Should return EC_SUCCESS_MANAGEMENT_FILE_CREATED"
  assert_file_exists "$mgmt_file" "Management file should exist"

  # Verify old content was replaced (truncated and reassembled from modules)
  if grep -q "OLD MANAGEMENT FILE" "$mgmt_file" 2>/dev/null; then
    fail_test "Management file should be replaced, not appended"
  fi

  rm -rf "$test_dir"
}

function test_create_management_file_native_success() {
  log_test_step "Testing __logic_create_management_file creates native management file"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_native_$$"
  mkdir -p "$test_dir"

  # Use necesse blueprint (no module overrides)
  local blueprint_file="$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/necesse.bp"
  local mgmt_file="$test_dir/manage.sh"
  local config_file="$test_dir/test.ini"

  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
runtime=native
management_file=$mgmt_file
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_MANAGEMENT_FILE_CREATED" "$exit_code" "Should return EC_SUCCESS_MANAGEMENT_FILE_CREATED"
  assert_file_exists "$mgmt_file" "Management file should be created"
  assert_file_executable "$mgmt_file" "Management file should be executable"
  assert_file_contains "$mgmt_file" "#!/usr/bin/env bash" "Management file should have bash shebang"

  rm -rf "$test_dir"
}

function test_create_management_file_native_with_module_overrides() {
  log_test_step "Testing __logic_create_management_file assembles factorio module overrides"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_factorio_$$"
  mkdir -p "$test_dir"

  # Use factorio blueprint which has module overrides (05-version.sh, 06-download.sh, 07-deploy.sh)
  local blueprint_file="$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/factorio.bp"
  local mgmt_file="$test_dir/manage.sh"
  local config_file="$test_dir/test.ini"

  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
runtime=native
management_file=$mgmt_file
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_MANAGEMENT_FILE_CREATED" "$exit_code" "Should return EC_SUCCESS_MANAGEMENT_FILE_CREATED"
  assert_file_exists "$mgmt_file" "Management file should be created"
  # Factorio overrides 05-version.sh uses factorio.com API
  assert_file_contains "$mgmt_file" "factorio.com" "Should contain factorio-specific version logic"

  rm -rf "$test_dir"
}

function test_create_management_file_container_compose_failure() {
  log_test_step "Testing __logic_create_management_file fails when container compose is missing blueprint_file"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_compose_fail_$$"
  mkdir -p "$test_dir"

  local mgmt_file="$test_dir/manage.sh"

  # Config missing blueprint_file needed for container compose file creation
  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=containertest
runtime=container
management_file=$mgmt_file
working_dir=$test_dir
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_FAILED_TEMPLATE" "$exit_code" "Should return EC_FAILED_TEMPLATE when container compose fails"

  rm -rf "$test_dir"
}

function test_create_management_file_assembles_all_modules() {
  log_test_step "Testing __logic_create_management_file assembles all 14 modules in order"

  local test_dir="$KGSM_TEST_SANDBOX/mgmt_test_modules_$$"
  mkdir -p "$test_dir"

  local blueprint_file="$KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR/factorio.bp"
  local mgmt_file="$test_dir/manage.sh"
  local config_file="$test_dir/test.ini"

  cat > "$config_file" << EOF
name=testinstance
blueprint_file=$blueprint_file
runtime=native
management_file=$mgmt_file
EOF

  __logic_create_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_MANAGEMENT_FILE_CREATED" "$exit_code" "Should succeed"

  # Verify assembled file contains content from key modules
  assert_file_contains "$mgmt_file" "#!/usr/bin/env bash" "Should contain header (00-header.sh)"
  assert_file_contains "$mgmt_file" "function _get_installed_version" "Should contain version functions (05-version.sh)"
  assert_file_contains "$mgmt_file" "function _download" "Should contain download function (06-download.sh)"
  assert_file_contains "$mgmt_file" "function _deploy" "Should contain deploy function (07-deploy.sh)"

  rm -rf "$test_dir"
}

# =============================================================================
# __logic_remove_management_file() TESTS
# =============================================================================

function test_remove_management_file_empty_parameter() {
  log_test_step "Testing __logic_remove_management_file with empty parameter"

  __logic_remove_management_file ""
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty parameter"
}

function test_remove_management_file_config_not_found() {
  log_test_step "Testing __logic_remove_management_file with non-existent config"

  __logic_remove_management_file "/nonexistent/config.ini"
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing config"
}

function test_remove_management_file_missing_management_file_field() {
  log_test_step "Testing __logic_remove_management_file with missing management_file field"

  local test_dir="$KGSM_TEST_SANDBOX/remove_test_missing_field"
  mkdir -p "$test_dir"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
runtime=native
EOF

  __logic_remove_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing management_file field"

  rm -rf "$test_dir"
}

function test_remove_management_file_readonly_directory() {
  log_test_step "Testing __logic_remove_management_file with readonly directory"

  local test_dir="$KGSM_TEST_SANDBOX/remove_test_readonly"
  mkdir -p "$test_dir"

  local mgmt_file="$test_dir/manage.sh"
  touch "$mgmt_file"

  # Make directory readonly
  chmod 555 "$test_dir"

  local config_file="$KGSM_TEST_SANDBOX/remove_readonly.ini"
  cat > "$config_file" << EOF
name=testinstance
runtime=native
management_file=$mgmt_file
EOF

  __logic_remove_management_file "$config_file"
  local exit_code=$?

  # Restore permissions for cleanup
  chmod 755 "$test_dir"

  assert_equals "$EC_FAILED_RM" "$exit_code" "Should return EC_FAILED_RM for readonly directory"

  rm -f "$config_file"
  rm -rf "$test_dir"
}

function test_remove_management_file_success() {
  log_test_step "Testing __logic_remove_management_file success case"

  local test_dir="$KGSM_TEST_SANDBOX/remove_test_success"
  mkdir -p "$test_dir"

  local mgmt_file="$test_dir/manage.sh"
  touch "$mgmt_file"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
runtime=native
management_file=$mgmt_file
EOF

  assert_file_exists "$mgmt_file" "Management file should exist before removal"

  __logic_remove_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_MANAGEMENT_FILE_REMOVED" "$exit_code" "Should return EC_SUCCESS_MANAGEMENT_FILE_REMOVED"
  assert_file_not_exists "$mgmt_file" "Management file should be removed"

  rm -rf "$test_dir"
}

function test_remove_management_file_already_removed() {
  log_test_step "Testing __logic_remove_management_file idempotent behavior"

  local test_dir="$KGSM_TEST_SANDBOX/remove_test_idempotent"
  mkdir -p "$test_dir"

  local mgmt_file="$test_dir/manage.sh"

  local config_file="$test_dir/test.ini"
  cat > "$config_file" << EOF
name=testinstance
runtime=native
management_file=$mgmt_file
EOF

  # File doesn't exist
  assert_file_not_exists "$mgmt_file" "Management file should not exist"

  __logic_remove_management_file "$config_file"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_MANAGEMENT_FILE_REMOVED" "$exit_code" "Should return EC_SUCCESS_MANAGEMENT_FILE_REMOVED even if file doesn't exist"

  rm -rf "$test_dir"
}

