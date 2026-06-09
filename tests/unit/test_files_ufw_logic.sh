#!/usr/bin/env bash

# KGSM Files UFW Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/files.ufw.sh
#
# Tests all logic functions from files.ufw.sh:
# - __logic_enable_ufw_integration()
# - __logic_disable_ufw_integration()
#
# Note: Tests requiring actual UFW system tools or root access are skipped
# when those conditions are unavailable. This test suite focuses on:
# - Input validation (EC_INVALID_ARG, EC_FILE_NOT_FOUND)
# - Configuration validation (EC_INVALID_CONFIG)
# - State validation (EC_ERROR when rule already exists)
# - Disable idempotency (EC_SUCCESS_UFW_DISABLED when nothing configured)
# - Config update verification for disable path

# =============================================================================
# TEST SETUP
# =============================================================================

# shellcheck disable=SC2034
readonly TEST_NAME="files_ufw_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.ufw.sh"

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# Create a minimal instance config file for UFW testing
# Args: $1 = output_path, $2 = instance_name (optional)
# Returns: 0 on success
function __create_ufw_instance_config() {
  local output_path="$1"
  local instance_name="${2:-test_ufw_instance_$$}"

  cat > "$output_path" << EOF
name=${instance_name}
blueprint_file=${KGSM_SYSTEM_BLUEPRINTS_NATIVE_DIR}/factorio.bp
runtime=native
working_dir=/tmp/kgsm_test_${instance_name}
install_dir=/tmp/kgsm_test_${instance_name}/install
management_file=/tmp/kgsm_test_${instance_name}/manage.sh
EOF
  return 0
}

# Create a minimal KGSM config file with custom firewall_rules_dir
# Args: $1 = output_path, $2 = firewall_rules_dir (optional, empty to omit)
# Returns: 0 on success
function __create_ufw_kgsm_config() {
  local output_path="$1"
  local firewall_rules_dir="${2:-}"

  if [[ -n "$firewall_rules_dir" ]]; then
    echo "firewall_rules_dir=${firewall_rules_dir}" > "$output_path"
  else
    echo "# no firewall_rules_dir configured" > "$output_path"
  fi
  return 0
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up files.ufw logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM_ROOT directory should exist"
  assert_file_exists "$HANDLER" "UFW handler file should exist"

  # Source the handler (pulls in files.common.sh automatically)
  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "$KGSM_LOGIC_FILES_UFW_LOADED" "UFW handler should be loaded"

  # Verify required error codes
  assert_not_null "$EC_INVALID_ARG"   "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_CONFIG" "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_ERROR"         "EC_ERROR should be defined"
  assert_not_null "$EC_SUCCESS_UFW_ENABLED"  "EC_SUCCESS_UFW_ENABLED should be defined"
  assert_not_null "$EC_SUCCESS_UFW_DISABLED" "EC_SUCCESS_UFW_DISABLED should be defined"

  # Verify functions are exported
  assert_function_exists "__logic_enable_ufw_integration"  "__logic_enable_ufw_integration should be exported"
  assert_function_exists "__logic_disable_ufw_integration" "__logic_disable_ufw_integration should be exported"

  log_test_step "UFW test environment validated"
}

# =============================================================================
# __logic_enable_ufw_integration() TESTS
# =============================================================================

function test_enable_ufw_empty_arg() {
  log_test_step "Testing __logic_enable_ufw_integration with empty argument"

  __logic_enable_ufw_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance_config_file"
}

function test_enable_ufw_file_not_found() {
  log_test_step "Testing __logic_enable_ufw_integration with non-existent config file"

  __logic_enable_ufw_integration "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND for missing config file"
}

function test_enable_ufw_missing_name_in_config() {
  log_test_step "Testing __logic_enable_ufw_integration with config missing 'name' field"

  local temp_config
  temp_config=$(mktemp)

  # Config with no 'name' field
  echo "blueprint_file=/some/path/factorio.bp" > "$temp_config"
  echo "runtime=native" >> "$temp_config"

  __logic_enable_ufw_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  rm -f "$temp_config"

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" \
    "Should return EC_INVALID_CONFIG when 'name' is missing from instance config"
}

function test_enable_ufw_missing_firewall_rules_dir() {
  log_test_step "Testing __logic_enable_ufw_integration when firewall_rules_dir not configured"

  local temp_instance_config temp_kgsm_config
  temp_instance_config=$(mktemp)
  temp_kgsm_config=$(mktemp)

  __create_ufw_instance_config "$temp_instance_config" "test_ufw_no_dir_$$"
  # Create a KGSM config WITHOUT firewall_rules_dir
  __create_ufw_kgsm_config "$temp_kgsm_config" ""

  # Temporarily override CONFIG_FILE for this test
  local orig_config_file="$CONFIG_FILE"
  CONFIG_FILE="$temp_kgsm_config"

  __logic_enable_ufw_integration "$temp_instance_config" 2>/dev/null
  local exit_code=$?

  CONFIG_FILE="$orig_config_file"
  rm -f "$temp_instance_config" "$temp_kgsm_config"

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" \
    "Should return EC_INVALID_CONFIG when firewall_rules_dir is not configured"
}

function test_enable_ufw_rule_already_exists() {
  log_test_step "Testing __logic_enable_ufw_integration when firewall rule file already exists"

  local temp_instance_config temp_kgsm_config temp_firewall_dir temp_rule_file
  temp_instance_config=$(mktemp)
  temp_kgsm_config=$(mktemp)
  temp_firewall_dir=$(mktemp -d)

  local instance_name="test_ufw_exists_$$"
  __create_ufw_instance_config "$temp_instance_config" "$instance_name"
  __create_ufw_kgsm_config "$temp_kgsm_config" "$temp_firewall_dir"

  # Pre-create the rule file to simulate "already exists"
  temp_rule_file="${temp_firewall_dir}/kgsm-${instance_name}"
  touch "$temp_rule_file"

  local orig_config_file="$CONFIG_FILE"
  CONFIG_FILE="$temp_kgsm_config"

  __logic_enable_ufw_integration "$temp_instance_config" 2>/dev/null
  local exit_code=$?

  CONFIG_FILE="$orig_config_file"
  rm -f "$temp_instance_config" "$temp_kgsm_config" "$temp_rule_file"
  rmdir "$temp_firewall_dir" 2>/dev/null

  assert_equals "$EC_ERROR" "$exit_code" \
    "Should return EC_ERROR when firewall rule file already exists"
}

# =============================================================================
# __logic_disable_ufw_integration() TESTS
# =============================================================================

function test_disable_ufw_empty_arg() {
  log_test_step "Testing __logic_disable_ufw_integration with empty argument"

  __logic_disable_ufw_integration "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for empty instance_config_file"
}

function test_disable_ufw_file_not_found() {
  log_test_step "Testing __logic_disable_ufw_integration with non-existent config file"

  __logic_disable_ufw_integration "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND for missing config file"
}

function test_disable_ufw_missing_name_in_config() {
  log_test_step "Testing __logic_disable_ufw_integration with config missing 'name' field"

  local temp_config
  temp_config=$(mktemp)

  # Config without 'name' field
  echo "blueprint_file=/some/path/factorio.bp" > "$temp_config"
  echo "runtime=native" >> "$temp_config"

  __logic_disable_ufw_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  rm -f "$temp_config"

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" \
    "Should return EC_INVALID_CONFIG when 'name' is missing from instance config"
}

function test_disable_ufw_no_rule_configured() {
  log_test_step "Testing __logic_disable_ufw_integration when no firewall rule is configured"

  local temp_config
  temp_config=$(mktemp)

  # Config with name but no firewall_rule_file
  cat > "$temp_config" << EOF
name=test_ufw_nocfg_$$
runtime=native
EOF

  __logic_disable_ufw_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  rm -f "$temp_config"

  assert_equals "$EC_SUCCESS_UFW_DISABLED" "$exit_code" \
    "Should return EC_SUCCESS_UFW_DISABLED when no firewall_rule_file is configured (no-op)"
}

function test_disable_ufw_rule_file_not_exist() {
  log_test_step "Testing __logic_disable_ufw_integration when rule file path set but file doesn't exist"

  # This test triggers 'sudo ufw delete allow' which requires passwordless sudo or root.
  # Skip if not running as root and sudo is not passwordless.
  if [[ "$EUID" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    log_test_step "Skipping: test requires root or passwordless sudo (to avoid interactive sudo prompt)"
    return 0
  fi

  local temp_config
  temp_config=$(mktemp)

  local instance_name="test_ufw_notexist_$$"
  cat > "$temp_config" << EOF
name=${instance_name}
runtime=native
enable_firewall_management=true
firewall_rule_file=/nonexistent/ufw/kgsm-${instance_name}
EOF

  __logic_disable_ufw_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  rm -f "$temp_config"

  assert_equals "$EC_SUCCESS_UFW_DISABLED" "$exit_code" \
    "Should return EC_SUCCESS_UFW_DISABLED when rule file doesn't exist (UFW delete fails silently)"
}

function test_disable_ufw_updates_config() {
  log_test_step "Testing __logic_disable_ufw_integration updates config after disable"

  # This test triggers 'sudo ufw delete allow' which requires passwordless sudo or root.
  # Skip if not running as root and sudo is not passwordless.
  if [[ "$EUID" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    log_test_step "Skipping: test requires root or passwordless sudo (to avoid interactive sudo prompt)"
    return 0
  fi

  local temp_config
  temp_config=$(mktemp)

  local instance_name="test_ufw_cfgupdate_$$"
  cat > "$temp_config" << EOF
name=${instance_name}
runtime=native
enable_firewall_management=true
firewall_rule_file=/nonexistent/ufw/kgsm-${instance_name}
EOF

  __logic_disable_ufw_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_UFW_DISABLED" "$exit_code" \
    "Should return EC_SUCCESS_UFW_DISABLED"

  assert_file_contains "$temp_config" "enable_firewall_management=false" \
    "Config should have enable_firewall_management=false after disable"

  rm -f "$temp_config"
}

function test_disable_ufw_clears_rule_file_in_config() {
  log_test_step "Testing __logic_disable_ufw_integration clears firewall_rule_file in config"

  # This test triggers 'sudo ufw delete allow' which requires passwordless sudo or root.
  # Skip if not running as root and sudo is not passwordless.
  if [[ "$EUID" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    log_test_step "Skipping: test requires root or passwordless sudo (to avoid interactive sudo prompt)"
    return 0
  fi

  local temp_config
  temp_config=$(mktemp)

  local instance_name="test_ufw_clearrule_$$"
  cat > "$temp_config" << EOF
name=${instance_name}
runtime=native
enable_firewall_management=true
firewall_rule_file=/nonexistent/ufw/kgsm-${instance_name}
EOF

  __logic_disable_ufw_integration "$temp_config" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_UFW_DISABLED" "$exit_code" \
    "Should return EC_SUCCESS_UFW_DISABLED"

  assert_file_contains "$temp_config" "firewall_rule_file=" \
    "Config should have firewall_rule_file cleared after disable"

  rm -f "$temp_config"
}

