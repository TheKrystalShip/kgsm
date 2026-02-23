#!/usr/bin/env bash

# KGSM Files Systemd Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/files.systemd.sh
#
# Tests all logic functions from files.systemd.sh:
# - __logic_enable_systemd_integration()
# - __logic_disable_systemd_integration()
#
# Notes:
# - Full success paths require root or passwordless sudo (systemctl daemon-reload)
# - Partial paths (up to mv/daemon-reload) are testable as non-root
# - "no files configured" early-return path is fully testable without systemd

# =============================================================================
# TEST SETUP
# =============================================================================

# shellcheck disable=SC2034
readonly TEST_NAME="files_systemd_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.systemd.sh"

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# Create a minimal instance config file for testing
# Args: $1 = output_path, $2+ = extra key=value lines
# Returns: 0 on success
function __create_minimal_systemd_config() {
  local output_path="$1"
  local instance_name="test_systemd_$$"
  shift

  cat > "$output_path" << EOF
name=${instance_name}
launch_dir=/tmp/test_launch_dir_$$
executable_file=server_executable
working_dir=/tmp/test_working_dir_$$
EOF

  # Append any extra fields
  for kv in "$@"; do
    echo "$kv" >> "$output_path"
  done

  return 0
}

# =============================================================================
# TEST FUNCTIONS - __logic_enable_systemd_integration()
# =============================================================================

function test_enable_empty_arg() {
  log_test_step "Testing __logic_enable_systemd_integration with empty argument"

  __logic_enable_systemd_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty argument"
}

function test_enable_config_not_found() {
  log_test_step "Testing __logic_enable_systemd_integration with non-existent config file"

  __logic_enable_systemd_integration "/nonexistent/path/config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing config file"
}

function test_enable_missing_name() {
  log_test_step "Testing __logic_enable_systemd_integration with missing name field"

  local config_file="$KGSM_TEST_SANDBOX/enable_test_missing_name_$$.ini"
  cat > "$config_file" << EOF
launch_dir=/tmp/test_launch
executable_file=server
working_dir=/tmp/test_working
EOF

  __logic_enable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing name"

  rm -f "$config_file"
}

function test_enable_missing_launch_dir() {
  log_test_step "Testing __logic_enable_systemd_integration with missing launch_dir field"

  local config_file="$KGSM_TEST_SANDBOX/enable_test_missing_launch_$$.ini"
  cat > "$config_file" << EOF
name=testinstance
executable_file=server
working_dir=/tmp/test_working
EOF

  __logic_enable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing launch_dir"

  rm -f "$config_file"
}

function test_enable_missing_executable_file() {
  log_test_step "Testing __logic_enable_systemd_integration with missing executable_file field"

  local config_file="$KGSM_TEST_SANDBOX/enable_test_missing_exec_$$.ini"
  cat > "$config_file" << EOF
name=testinstance
launch_dir=/tmp/test_launch
working_dir=/tmp/test_working
EOF

  __logic_enable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing executable_file"

  rm -f "$config_file"
}

function test_enable_missing_working_dir() {
  log_test_step "Testing __logic_enable_systemd_integration with missing working_dir field"

  local config_file="$KGSM_TEST_SANDBOX/enable_test_missing_workdir_$$.ini"
  cat > "$config_file" << EOF
name=testinstance
launch_dir=/tmp/test_launch
executable_file=server
EOF

  __logic_enable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing working_dir"

  rm -f "$config_file"
}

function test_enable_missing_systemd_files_dir() {
  log_test_step "Testing __logic_enable_systemd_integration with missing systemd_files_dir in KGSM config"

  # Create a KGSM config without systemd_files_dir
  local temp_kgsm_config="$KGSM_TEST_SANDBOX/temp_kgsm_config_$$.ini"
  cat > "$temp_kgsm_config" << EOF
# Minimal KGSM config without systemd_files_dir
enable_systemd=true
EOF

  # Create an instance config with all required fields
  local config_file="$KGSM_TEST_SANDBOX/enable_test_no_systemd_dir_$$.ini"
  cat > "$config_file" << EOF
name=testinstance_$$
launch_dir=/tmp/test_launch
executable_file=server
working_dir=/tmp/test_working
EOF

  # Temporarily override CONFIG_FILE
  local original_config_file="${CONFIG_FILE}"
  CONFIG_FILE="$temp_kgsm_config"
  export CONFIG_FILE

  __logic_enable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  # Restore CONFIG_FILE
  CONFIG_FILE="$original_config_file"
  export CONFIG_FILE

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG when systemd_files_dir not set"

  rm -f "$config_file" "$temp_kgsm_config"
}

function test_enable_mv_fails_readonly_dir() {
  log_test_step "Testing __logic_enable_systemd_integration mv failure with readonly systemd dir"

  # Create a readonly temp dir to act as the systemd_files_dir
  local readonly_systemd_dir="$KGSM_TEST_SANDBOX/readonly_systemd_dir_$$"
  mkdir -p "$readonly_systemd_dir"
  chmod 555 "$readonly_systemd_dir"

  # Override CONFIG_FILE to use our readonly systemd dir
  local temp_kgsm_config="$KGSM_TEST_SANDBOX/temp_kgsm_readonly_config_$$.ini"
  cp "$CONFIG_FILE" "$temp_kgsm_config"
  sed -i "s|systemd_files_dir=.*|systemd_files_dir=${readonly_systemd_dir}|" "$temp_kgsm_config"

  local original_config_file="${CONFIG_FILE}"
  CONFIG_FILE="$temp_kgsm_config"
  export CONFIG_FILE

  local config_file="$KGSM_TEST_SANDBOX/enable_test_mv_fail_$$.ini"
  cat > "$config_file" << EOF
name=testinstance_$$
launch_dir=/tmp/test_launch
executable_file=server
working_dir=/tmp/test_working
EOF

  # Run as current user (no sudo) - mv to readonly dir should fail
  # Temporarily set EUID workaround: if EUID=0 then SUDO is empty, mv will fail on chmod 555
  # If EUID!=0, sudo will be attempted - skip this case
  local expected_code="$EC_FAILED_MV"

  if [[ "$EUID" -ne 0 ]]; then
    # As non-root, sudo will be attempted. Skip to avoid interactive password prompt.
    chmod 755 "$readonly_systemd_dir"
    CONFIG_FILE="$original_config_file"
    export CONFIG_FILE
    rm -rf "$readonly_systemd_dir" "$config_file" "$temp_kgsm_config"
    skip_test "Skipping mv failure test - would trigger interactive sudo prompt as non-root"
    return 0
  fi

  __logic_enable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  # Restore permissions
  chmod 755 "$readonly_systemd_dir"
  CONFIG_FILE="$original_config_file"
  export CONFIG_FILE

  assert_equals "$EC_FAILED_MV" "$exit_code" "Should return EC_FAILED_MV when cannot write to systemd dir"

  rm -rf "$readonly_systemd_dir" "$config_file" "$temp_kgsm_config"
}

function test_enable_success_with_writable_systemd_dir() {
  log_test_step "Testing __logic_enable_systemd_integration success with writable systemd dir"

  # Skip if running as non-root without passwordless sudo (daemon-reload will fail)
  if [[ "$EUID" -ne 0 ]]; then
    if ! sudo -n systemctl daemon-reload 2>/dev/null; then
      skip_test "Cannot test success path without root or passwordless sudo"
      return 0
    fi
  fi

  # Create a writable temp dir to act as systemd_files_dir
  local temp_systemd_dir="$KGSM_TEST_SANDBOX/fake_systemd_$$"
  mkdir -p "$temp_systemd_dir"

  # Override CONFIG_FILE to use our temp systemd dir
  local temp_kgsm_config="$KGSM_TEST_SANDBOX/temp_kgsm_success_config_$$.ini"
  cp "$CONFIG_FILE" "$temp_kgsm_config"
  sed -i "s|systemd_files_dir=.*|systemd_files_dir=${temp_systemd_dir}|" "$temp_kgsm_config"

  local original_config_file="${CONFIG_FILE}"
  CONFIG_FILE="$temp_kgsm_config"
  export CONFIG_FILE

  local instance_name="test_systemd_success_$$"
  local config_file="$KGSM_TEST_SANDBOX/enable_test_success_$$.ini"
  cat > "$config_file" << EOF
name=${instance_name}
launch_dir=/tmp/test_launch_$$
executable_file=server
working_dir=/tmp/test_working_$$
EOF

  __logic_enable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  # Restore CONFIG_FILE
  CONFIG_FILE="$original_config_file"
  export CONFIG_FILE

  assert_equals "$EC_SUCCESS_SYSTEMD_ENABLED" "$exit_code" "Should return EC_SUCCESS_SYSTEMD_ENABLED"

  # Verify config was updated
  assert_file_contains "$config_file" "enable_systemd=true" "Config should have enable_systemd=true"
  assert_file_contains "$config_file" "lifecycle_manager=systemd" "Config should have lifecycle_manager=systemd"

  # Cleanup
  rm -rf "$temp_systemd_dir" "$config_file" "$temp_kgsm_config"
}

# =============================================================================
# TEST FUNCTIONS - __logic_disable_systemd_integration()
# =============================================================================

function test_disable_empty_arg() {
  log_test_step "Testing __logic_disable_systemd_integration with empty argument"

  __logic_disable_systemd_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return EC_INVALID_ARG for empty argument"
}

function test_disable_config_not_found() {
  log_test_step "Testing __logic_disable_systemd_integration with non-existent config file"

  __logic_disable_systemd_integration "/nonexistent/path/config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" "Should return EC_FILE_NOT_FOUND for missing config file"
}

function test_disable_missing_name() {
  log_test_step "Testing __logic_disable_systemd_integration with missing name field"

  local config_file="$KGSM_TEST_SANDBOX/disable_test_missing_name_$$.ini"
  cat > "$config_file" << EOF
systemd_service_file=/etc/systemd/system/test.service
systemd_socket_file=/etc/systemd/system/test.socket
EOF

  __logic_disable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return EC_INVALID_CONFIG for missing name"

  rm -f "$config_file"
}

function test_disable_no_systemd_files_configured() {
  log_test_step "Testing __logic_disable_systemd_integration with no systemd files configured"

  local config_file="$KGSM_TEST_SANDBOX/disable_test_no_files_$$.ini"
  cat > "$config_file" << EOF
name=testinstance_$$
EOF

  __logic_disable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYSTEMD_DISABLED" "$exit_code" \
    "Should return EC_SUCCESS_SYSTEMD_DISABLED early when no systemd files configured"

  rm -f "$config_file"
}

function test_disable_no_systemd_files_empty_values() {
  log_test_step "Testing __logic_disable_systemd_integration with empty systemd file values"

  local config_file="$KGSM_TEST_SANDBOX/disable_test_empty_files_$$.ini"
  cat > "$config_file" << EOF
name=testinstance_$$
systemd_service_file=
systemd_socket_file=
EOF

  __logic_disable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYSTEMD_DISABLED" "$exit_code" \
    "Should return EC_SUCCESS_SYSTEMD_DISABLED when systemd file values are empty"

  rm -f "$config_file"
}

function test_disable_daemon_reload_fails_non_root() {
  log_test_step "Testing __logic_disable_systemd_integration daemon-reload failure"

  # Skip for non-root: systemctl daemon-reload via sudo would prompt for password
  if [[ "$EUID" -ne 0 ]]; then
    if ! sudo -n systemctl daemon-reload 2>/dev/null; then
      skip_test "Skipping daemon-reload failure test - would trigger interactive sudo prompt"
      return 0
    fi
  fi

  local instance_name="test_disable_daemon_$$"
  local config_file="$KGSM_TEST_SANDBOX/disable_test_daemon_fail_$$.ini"
  cat > "$config_file" << EOF
name=${instance_name}
systemd_service_file=/etc/systemd/system/${instance_name}.service
systemd_socket_file=/etc/systemd/system/${instance_name}.socket
EOF

  # Service is not active/enabled (will skip stop/disable)
  # Service/socket files don't exist (will skip rm)
  # But daemon-reload requires privileges → EC_SYSTEMD
  __logic_disable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SYSTEMD" "$exit_code" \
    "Should return EC_SYSTEMD when daemon-reload fails"

  rm -f "$config_file"
}

function test_disable_success_with_no_files_present() {
  log_test_step "Testing __logic_disable_systemd_integration success when files don't exist on disk"

  # Skip if running as non-root without passwordless sudo (daemon-reload will fail)
  if [[ "$EUID" -ne 0 ]]; then
    if ! sudo -n systemctl daemon-reload 2>/dev/null; then
      skip_test "Cannot test success path without root or passwordless sudo"
      return 0
    fi
  fi

  local instance_name="test_disable_success_$$"
  local config_file="$KGSM_TEST_SANDBOX/disable_test_success_$$.ini"
  cat > "$config_file" << EOF
name=${instance_name}
systemd_service_file=/tmp/nonexistent_${instance_name}.service
systemd_socket_file=/tmp/nonexistent_${instance_name}.socket
EOF

  __logic_disable_systemd_integration "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYSTEMD_DISABLED" "$exit_code" \
    "Should return EC_SUCCESS_SYSTEMD_DISABLED when files don't exist and daemon-reload succeeds"

  # Verify config was updated
  assert_file_contains "$config_file" "enable_systemd=false" "Config should have enable_systemd=false"
  assert_file_contains "$config_file" "lifecycle_manager=standalone" "Config should have lifecycle_manager=standalone"

  rm -f "$config_file"
}

# =============================================================================
# TEST FUNCTIONS - Handler loading and function exports
# =============================================================================

function test_handler_functions_exported() {
  log_test_step "Testing that handler functions are properly exported"

  assert_function_exists "__logic_enable_systemd_integration" \
    "__logic_enable_systemd_integration should be exported"
  assert_function_exists "__logic_disable_systemd_integration" \
    "__logic_disable_systemd_integration should be exported"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting files.systemd logic tests"

  # Setup
  log_test_step "Setting up files.systemd logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"

  assert_file_exists "$HANDLER" "Handler file should exist"

  # Source the handler
  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "$KGSM_LOGIC_FILES_SYSTEMD_LOADED" "Handler should be loaded"

  # Verify error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FAILED_MV" "EC_FAILED_MV should be defined"
  assert_not_null "$EC_SYSTEMD" "EC_SYSTEMD should be defined"
  assert_not_null "$EC_SUCCESS_SYSTEMD_ENABLED" "EC_SUCCESS_SYSTEMD_ENABLED should be defined"
  assert_not_null "$EC_SUCCESS_SYSTEMD_DISABLED" "EC_SUCCESS_SYSTEMD_DISABLED should be defined"

  # Verify templates exist
  assert_file_exists "$KGSM_ROOT/templates/service.tp" "Service template should exist"
  assert_file_exists "$KGSM_ROOT/templates/socket.tp" "Socket template should exist"

  log_test_step "Environment validated"

  # Function export tests
  test_handler_functions_exported

  # __logic_enable_systemd_integration tests
  test_enable_empty_arg
  test_enable_config_not_found
  test_enable_missing_name
  test_enable_missing_launch_dir
  test_enable_missing_executable_file
  test_enable_missing_working_dir
  test_enable_missing_systemd_files_dir
  test_enable_mv_fails_non_root
  test_enable_success_with_writable_systemd_dir

  # __logic_disable_systemd_integration tests
  test_disable_empty_arg
  test_disable_config_not_found
  test_disable_missing_name
  test_disable_no_systemd_files_configured
  test_disable_no_systemd_files_empty_values
  test_disable_daemon_reload_fails_non_root
  test_disable_success_with_no_files_present

  log_test_step "files.systemd logic tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All files.systemd logic tests passed"
  else
    fail_test "Some files.systemd logic tests failed"
  fi
}

main "$@"
