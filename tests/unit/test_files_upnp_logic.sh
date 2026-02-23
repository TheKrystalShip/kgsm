#!/usr/bin/env bash

# KGSM Files UPnP Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/files.upnp.sh
#
# Tests all logic functions from files.upnp.sh:
# - __logic_enable_upnp_integration()
# - __logic_disable_upnp_integration()
#
# Note: UPnP integration is config-only - no external files are created.
# Actual port forwarding is handled by the game server management process.
# These tests cover all logic paths including validation and config updates.

# =============================================================================
# TEST SETUP
# =============================================================================

# shellcheck disable=SC2034
readonly TEST_NAME="files_upnp_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.upnp.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up files.upnp logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"
  assert_file_exists "$HANDLER" "UPnP handler file should exist"

  # Source the handler
  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "$KGSM_LOGIC_FILES_UPNP_LOADED" "UPnP handler should be loaded"

  # Verify required error codes
  assert_not_null "$EC_INVALID_ARG"        "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND"     "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_SUCCESS_UPNP_ENABLED" "EC_SUCCESS_UPNP_ENABLED should be defined"

  # Verify functions are exported
  assert_function_exists "__logic_enable_upnp_integration"  "__logic_enable_upnp_integration should be exported"
  assert_function_exists "__logic_disable_upnp_integration" "__logic_disable_upnp_integration should be exported"

  log_test_step "UPnP test environment validated"
}

# =============================================================================
# __logic_enable_upnp_integration() TESTS
# =============================================================================

function test_enable_upnp_empty_arg() {
  log_test_step "Testing __logic_enable_upnp_integration with empty argument"

  __logic_enable_upnp_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance_config_file"
}

function test_enable_upnp_file_not_found() {
  log_test_step "Testing __logic_enable_upnp_integration with non-existent config file"

  __logic_enable_upnp_integration "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND for missing config file"
}

function test_enable_upnp_success() {
  log_test_step "Testing __logic_enable_upnp_integration with valid config file"

  local temp_config
  temp_config=$(mktemp)

  cat > "$temp_config" << EOF
name=test_upnp_enable_$$
runtime=native
enable_port_forwarding=false
EOF

  __logic_enable_upnp_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  rm -f "$temp_config"

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$exit_code" \
    "Should return EC_SUCCESS_UPNP_ENABLED on success"
}

function test_enable_upnp_sets_config_value() {
  log_test_step "Testing __logic_enable_upnp_integration sets enable_port_forwarding=true"

  local temp_config
  temp_config=$(mktemp)

  cat > "$temp_config" << EOF
name=test_upnp_setval_$$
runtime=native
enable_port_forwarding=false
EOF

  __logic_enable_upnp_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$exit_code" \
    "Should return EC_SUCCESS_UPNP_ENABLED"

  assert_file_contains "$temp_config" "enable_port_forwarding=true" \
    "Config should have enable_port_forwarding=true after enable"

  rm -f "$temp_config"
}

function test_enable_upnp_config_without_key() {
  log_test_step "Testing __logic_enable_upnp_integration adds key when not present"

  local temp_config
  temp_config=$(mktemp)

  # Config without enable_port_forwarding key
  cat > "$temp_config" << EOF
name=test_upnp_nokey_$$
runtime=native
EOF

  __logic_enable_upnp_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$exit_code" \
    "Should return EC_SUCCESS_UPNP_ENABLED even when key not pre-existing"

  assert_file_contains "$temp_config" "enable_port_forwarding=true" \
    "Config should have enable_port_forwarding=true appended when key was missing"

  rm -f "$temp_config"
}

# =============================================================================
# __logic_disable_upnp_integration() TESTS
# =============================================================================

function test_disable_upnp_empty_arg() {
  log_test_step "Testing __logic_disable_upnp_integration with empty argument"

  __logic_disable_upnp_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance_config_file"
}

function test_disable_upnp_file_not_found() {
  log_test_step "Testing __logic_disable_upnp_integration with non-existent config file"

  __logic_disable_upnp_integration "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND for missing config file"
}

function test_disable_upnp_success() {
  log_test_step "Testing __logic_disable_upnp_integration with valid config file"

  local temp_config
  temp_config=$(mktemp)

  cat > "$temp_config" << EOF
name=test_upnp_disable_$$
runtime=native
enable_port_forwarding=true
EOF

  __logic_disable_upnp_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  rm -f "$temp_config"

  # Note: handler returns EC_SUCCESS_UPNP_ENABLED for both enable and disable
  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$exit_code" \
    "Should return EC_SUCCESS_UPNP_ENABLED (used for both enable and disable operations)"
}

function test_disable_upnp_sets_config_value() {
  log_test_step "Testing __logic_disable_upnp_integration sets enable_port_forwarding=false"

  local temp_config
  temp_config=$(mktemp)

  cat > "$temp_config" << EOF
name=test_upnp_dissetval_$$
runtime=native
enable_port_forwarding=true
EOF

  __logic_disable_upnp_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$exit_code" \
    "Should return EC_SUCCESS_UPNP_ENABLED"

  assert_file_contains "$temp_config" "enable_port_forwarding=false" \
    "Config should have enable_port_forwarding=false after disable"

  rm -f "$temp_config"
}

function test_disable_upnp_config_without_key() {
  log_test_step "Testing __logic_disable_upnp_integration adds key when not present"

  local temp_config
  temp_config=$(mktemp)

  # Config without enable_port_forwarding key
  cat > "$temp_config" << EOF
name=test_upnp_disnokey_$$
runtime=native
EOF

  __logic_disable_upnp_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$exit_code" \
    "Should return EC_SUCCESS_UPNP_ENABLED even when key not pre-existing"

  assert_file_contains "$temp_config" "enable_port_forwarding=false" \
    "Config should have enable_port_forwarding=false appended when key was missing"

  rm -f "$temp_config"
}

# =============================================================================
# ROUND-TRIP TESTS
# =============================================================================

function test_upnp_enable_then_disable() {
  log_test_step "Testing UPnP enable then disable round-trip"

  local temp_config
  temp_config=$(mktemp)

  cat > "$temp_config" << EOF
name=test_upnp_roundtrip_$$
runtime=native
EOF

  # Enable UPnP
  __logic_enable_upnp_integration "$temp_config" 2>/dev/null
  local enable_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$enable_code" \
    "Enable should return EC_SUCCESS_UPNP_ENABLED"

  assert_file_contains "$temp_config" "enable_port_forwarding=true" \
    "Config should have enable_port_forwarding=true after enable"

  # Disable UPnP
  __logic_disable_upnp_integration "$temp_config" 2>/dev/null
  local disable_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$disable_code" \
    "Disable should return EC_SUCCESS_UPNP_ENABLED"

  assert_file_contains "$temp_config" "enable_port_forwarding=false" \
    "Config should have enable_port_forwarding=false after disable"

  rm -f "$temp_config"
}

function test_upnp_disable_then_enable() {
  log_test_step "Testing UPnP disable then enable round-trip"

  local temp_config
  temp_config=$(mktemp)

  cat > "$temp_config" << EOF
name=test_upnp_revtrip_$$
runtime=native
enable_port_forwarding=true
EOF

  # Disable UPnP
  __logic_disable_upnp_integration "$temp_config" 2>/dev/null
  local disable_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$disable_code" \
    "Disable should return EC_SUCCESS_UPNP_ENABLED"

  assert_file_contains "$temp_config" "enable_port_forwarding=false" \
    "Config should have enable_port_forwarding=false after disable"

  # Enable UPnP
  __logic_enable_upnp_integration "$temp_config" 2>/dev/null
  local enable_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$enable_code" \
    "Enable should return EC_SUCCESS_UPNP_ENABLED"

  assert_file_contains "$temp_config" "enable_port_forwarding=true" \
    "Config should have enable_port_forwarding=true after re-enable"

  rm -f "$temp_config"
}

function test_upnp_enable_idempotent() {
  log_test_step "Testing __logic_enable_upnp_integration is idempotent"

  local temp_config
  temp_config=$(mktemp)

  cat > "$temp_config" << EOF
name=test_upnp_idem_$$
runtime=native
enable_port_forwarding=false
EOF

  # Enable twice
  __logic_enable_upnp_integration "$temp_config" 2>/dev/null
  local first_code=$?
  __logic_enable_upnp_integration "$temp_config" 2>/dev/null
  local second_code=$?

  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$first_code" \
    "First enable should return EC_SUCCESS_UPNP_ENABLED"
  assert_equals "$EC_SUCCESS_UPNP_ENABLED" "$second_code" \
    "Second enable should also return EC_SUCCESS_UPNP_ENABLED (idempotent)"

  assert_file_contains "$temp_config" "enable_port_forwarding=true" \
    "Config should still have enable_port_forwarding=true after second enable"

  rm -f "$temp_config"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting files.upnp logic tests"

  setup_test

  # __logic_enable_upnp_integration tests
  test_enable_upnp_empty_arg
  test_enable_upnp_file_not_found
  test_enable_upnp_success
  test_enable_upnp_sets_config_value
  test_enable_upnp_config_without_key

  # __logic_disable_upnp_integration tests
  test_disable_upnp_empty_arg
  test_disable_upnp_file_not_found
  test_disable_upnp_success
  test_disable_upnp_sets_config_value
  test_disable_upnp_config_without_key

  # Round-trip tests
  test_upnp_enable_then_disable
  test_upnp_disable_then_enable
  test_upnp_enable_idempotent

  log_test_step "files.upnp logic tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All files.upnp logic tests passed"
  else
    fail_test "Some files.upnp logic tests failed"
  fi
}

main "$@"
