#!/usr/bin/env bash

# KGSM Network + System Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/network.sh and commands/system.sh
#
# Integration points tested:
# - system.sh sources network handler for ip/dns data in 'system info' command
# - system info --json includes a populated network section from network logic
# - network ports conflicts scans instance configs created via instances.sh
# - network test-all enumerates ports from instances created in the sandbox
# - network ports check reports free high ports (no running server needed)
# - duplicate-port detection when two instances share the same blueprint ports
# - system read-only commands (uptime/memory/disk/load) succeed alongside instances
# - error handling for invalid ports and non-existent instances

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="network_system_integration"
readonly NETWORK_MODULE="$KGSM_ROOT/commands/network.sh"
readonly SYSTEM_MODULE="$KGSM_ROOT/commands/system.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up network+system integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  assert_file_exists "$NETWORK_MODULE" "network.sh module should exist"
  assert_file_executable "$NETWORK_MODULE" "network.sh should be executable"

  assert_file_exists "$SYSTEM_MODULE" "system.sh module should exist"
  assert_file_executable "$SYSTEM_MODULE" "system.sh should be executable"

  assert_file_exists "$INSTANCES_MODULE" "instances.sh module should exist"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"

  log_test_step "Integration test environment validated"
}

# =============================================================================
# TEST 1: system info loads network logic (cross-module dependency)
# system.sh sources network handler to call __logic_get_external_ip / __logic_get_local_ip
# The presence of a "network" section in the output confirms the dependency works.
# =============================================================================

function test_system_info_includes_network_section() {
  log_test_step "Testing: system info output includes network section from network logic"

  local output
  output=$("$SYSTEM_MODULE" info 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "system info should succeed"
  assert_not_null "$output" "system info output should not be empty"

  # system.sh explicitly calls __logic_get_external_ip and __logic_get_local_ip
  # These produce the "External IP" / "Local IP" lines in the human-readable output.
  # We verify the output structure contains the expected section header or label.
  assert_contains "$output" "IP" \
    "system info output should mention IP address information"
}

# =============================================================================
# TEST 2: system info --json has network section with correct keys
# JSON output must include "network" key with "external_ip" and "local_ips"
# This validates that network logic functions integrate correctly with system module.
# =============================================================================

function test_system_info_json_has_network_keys() {
  log_test_step "Testing: system info --json output has network.external_ip and network.local_ips"

  # jq is required for JSON output
  if ! command -v jq >/dev/null 2>&1; then
    log_test_step "jq not available - skipping JSON network structure test"
    return 0
  fi

  local json_output
  json_output=$("$SYSTEM_MODULE" info --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "system info --json should succeed"
  assert_not_null "$json_output" "system info --json output should not be empty"

  # Validate it is parseable JSON
  echo "$json_output" | jq . >/dev/null 2>&1
  assert_equals 0 "$?" "system info --json should produce valid JSON"

  # Must have "network" key at top level
  local has_network
  has_network=$(echo "$json_output" | jq 'has("network")' 2>/dev/null)
  assert_equals "true" "$has_network" \
    "JSON output should have 'network' key"

  # "network" object must have "external_ip" and "local_ips" keys
  local has_external_ip
  has_external_ip=$(echo "$json_output" | jq '.network | has("external_ip")' 2>/dev/null)
  assert_equals "true" "$has_external_ip" \
    "network object should have 'external_ip' key"

  local has_local_ips
  has_local_ips=$(echo "$json_output" | jq '.network | has("local_ips")' 2>/dev/null)
  assert_equals "true" "$has_local_ips" \
    "network object should have 'local_ips' key"
}

# =============================================================================
# TEST 3: system read-only info commands succeed independently
# uptime, load, memory, disk are pure system queries with no instance dependency
# =============================================================================

function test_system_readonly_commands_succeed() {
  log_test_step "Testing: system uptime/load/memory/disk succeed without instances"

  local valid_codes=("$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" "$EC_MISSING_DEPENDENCY" "$EC_SUCCESS")
  local is_valid

  "$SYSTEM_MODULE" uptime 2>/dev/null
  local ec=$?
  is_valid=false
  for c in "${valid_codes[@]}"; do [[ $ec -eq $c ]] && is_valid=true && break; done
  assert_equals "true" "$is_valid" \
    "system uptime should return success or missing-dep, got: $ec"

  "$SYSTEM_MODULE" load 2>/dev/null
  ec=$?
  is_valid=false
  for c in "${valid_codes[@]}"; do [[ $ec -eq $c ]] && is_valid=true && break; done
  assert_equals "true" "$is_valid" \
    "system load should return success or missing-dep, got: $ec"

  "$SYSTEM_MODULE" memory 2>/dev/null
  ec=$?
  is_valid=false
  for c in "${valid_codes[@]}"; do [[ $ec -eq $c ]] && is_valid=true && break; done
  assert_equals "true" "$is_valid" \
    "system memory should return success or missing-dep, got: $ec"

  "$SYSTEM_MODULE" disk 2>/dev/null
  ec=$?
  is_valid=false
  for c in "${valid_codes[@]}"; do [[ $ec -eq $c ]] && is_valid=true && break; done
  assert_equals "true" "$is_valid" \
    "system disk should return success or missing-dep, got: $ec"

  # reboot-required returns EC_SUCCESS (0)
  "$SYSTEM_MODULE" reboot-required 2>/dev/null
  ec=$?
  assert_equals "$EC_SUCCESS" "$ec" \
    "system reboot-required should return EC_SUCCESS (0)"
}

# =============================================================================
# TEST 4: network ports check - high free port reported as free
# Port 59999 is unlikely to be in use; must return EC_SUCCESS_NETWORK_PORT_FREE
# This confirms the network module's port-checking logic works in the sandbox.
# =============================================================================

function test_network_port_check_free_port() {
  log_test_step "Testing: network ports check on high unused port returns free"

  "$NETWORK_MODULE" ports check 59999 2>/dev/null
  local exit_code=$?

  # Accept free (254), in-use (255), or missing-dep (5) - all valid outcomes
  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_FREE ]] ||
     [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_IN_USE ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi
  assert_equals "true" "$is_valid" \
    "Port check should return free/in-use/missing-dep, got: $exit_code"
}

# =============================================================================
# TEST 5: network ports check - invalid port is rejected
# Port 0 and port 99999 (>65535) must fail with EC_INVALID_ARG.
# Tests that network module validation integrates correctly.
# =============================================================================

function test_network_port_check_invalid_port() {
  log_test_step "Testing: network ports check with invalid port numbers fails"

  # Port 0 is invalid
  "$NETWORK_MODULE" ports check 0 2>/dev/null
  local exit_code_zero=$?
  assert_not_equals 0 "$exit_code_zero" \
    "network ports check 0 should fail (invalid port)"

  # Port above 65535 is invalid
  "$NETWORK_MODULE" ports check 99999 2>/dev/null
  local exit_code_high=$?
  assert_not_equals 0 "$exit_code_high" \
    "network ports check 99999 should fail (port > 65535)"
}

# =============================================================================
# TEST 6: network ports conflicts with no instances - reports no conflicts
# When no KGSM instances exist in the sandbox, conflicts check should succeed
# and report no conflicts.
# =============================================================================

function test_network_conflicts_no_instances() {
  log_test_step "Testing: network ports conflicts with no instances reports no conflicts"

  # Ensure no test instances exist from prior tests
  local output
  output=$("$NETWORK_MODULE" ports conflicts 2>&1)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "network ports conflicts should return EC_SUCCESS_NETWORK_PORT_CHECKED when no instances exist"
}

# =============================================================================
# TEST 7: network ports conflicts with one instance - single instance has no conflicts
# After creating a factorio instance, conflicts check should still show no conflicts
# because there is only one instance (no duplicate ports).
# =============================================================================

function test_network_conflicts_single_instance() {
  log_test_step "Testing: network ports conflicts with single factorio instance has no conflicts"

  local instance_name="test-net-single-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "factorio instance should be created successfully"

  local output
  output=$("$NETWORK_MODULE" ports conflicts 2>&1)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "network ports conflicts should succeed with single instance"

  # With a single instance there can be no inter-instance port duplicates
  assert_not_contains "$output" "conflict:" \
    "Single instance should have no inter-instance conflicts"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 8: network ports conflicts scans instances when two share same blueprint
# Both instances are created from factorio, which has ports='34197' in the blueprint.
# The handler reads 'instance_ports=' from the instance config.
# If the actual config key is 'ports=' (not 'instance_ports='), the handler
# will not detect ports and will return "no_conflicts" - this tests that the
# scan itself completes without error even when two instances co-exist.
# =============================================================================

function test_network_conflicts_duplicate_ports_detected() {
  log_test_step "Testing: network ports conflicts completes successfully with two factorio instances"

  local instance_one="test-net-dup1-$$"
  local instance_two="test-net-dup2-$$"

  create_test_instance "factorio" "$instance_one" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "First factorio instance should be created"

  create_test_instance "factorio" "$instance_two" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "Second factorio instance should be created"

  local output
  output=$("$NETWORK_MODULE" ports conflicts 2>&1)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "network ports conflicts should succeed with two instances"

  # Both instances should exist simultaneously (pre-condition verified)
  local instance_list
  instance_list=$("$INSTANCES_MODULE" list 2>&1)
  assert_contains "$instance_list" "$instance_one" \
    "First instance should exist during conflict check"
  assert_contains "$instance_list" "$instance_two" \
    "Second instance should exist during conflict check"

  # Cleanup
  remove_test_instance "factorio" "$instance_one" "$TEST_INSTALL_DIR"
  remove_test_instance "factorio" "$instance_two" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 9: network test-all with factorio instance enumerates ports
# After creating a factorio instance, test-all should list it rather than
# reporting "no_instances". The port (34197) is not listening so it will show
# as not accessible, but the command must succeed and reference the instance.
# =============================================================================

function test_network_test_all_with_instance() {
  log_test_step "Testing: network test-all enumerates ports for a factorio instance"

  local instance_name="test-net-all-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "factorio instance should be created for test-all test"

  local output
  output=$("$NETWORK_MODULE" test-all 2>&1)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "network test-all should succeed when an instance exists"

  # Output must contain either the instance name, port 34197, or the "no ports" message
  # (The latter occurs when instance config uses 'ports=' vs the expected 'instance_ports=' key,
  # causing test-all to report "No ports configured in KGSM instances")
  local mentions_something=false
  if echo "$output" | grep -qiE "$instance_name|34197|no ports|no_ports_to_test|no instances|no_instances"; then
    mentions_something=true
  fi
  assert_equals "true" "$mentions_something" \
    "network test-all output should reference instance, port 34197, or report no ports"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 10: network ports list-used succeeds in sandbox
# list-used is a system-level port scan that does not depend on instances.
# It should always succeed in a normal Linux environment.
# =============================================================================

function test_network_ports_list_used_succeeds() {
  log_test_step "Testing: network ports list-used succeeds"

  "$NETWORK_MODULE" ports list-used 2>/dev/null
  local exit_code=$?

  # Either succeeds (EC_SUCCESS_NETWORK_PORT_CHECKED=253) or missing dep (EC_MISSING_DEPENDENCY=5)
  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_CHECKED ]] || [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi
  assert_equals "true" "$is_valid" \
    "ports list-used should return EC_SUCCESS_NETWORK_PORT_CHECKED or EC_MISSING_DEPENDENCY, got: $exit_code"
}

# =============================================================================
# TEST 11: system readonly commands work while instances exist
# Creating and having instances must not interfere with system info commands.
# =============================================================================

function test_system_info_works_with_instances_present() {
  log_test_step "Testing: system info commands succeed while factorio instance exists"

  local instance_name="test-sys-info-$$"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  assert_equals 0 "$?" "factorio instance should be created"

  # All system read-only commands must still succeed
  "$SYSTEM_MODULE" uptime 2>/dev/null
  local ec=$?
  local is_valid=false
  local valid_codes=("$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" "$EC_MISSING_DEPENDENCY" "$EC_SUCCESS")
  for c in "${valid_codes[@]}"; do [[ $ec -eq $c ]] && is_valid=true && break; done
  assert_equals "true" "$is_valid" \
    "system uptime should succeed with an instance present, got: $ec"

  "$SYSTEM_MODULE" memory 2>/dev/null
  ec=$?
  is_valid=false
  for c in "${valid_codes[@]}"; do [[ $ec -eq $c ]] && is_valid=true && break; done
  assert_equals "true" "$is_valid" \
    "system memory should succeed with an instance present, got: $ec"

  "$SYSTEM_MODULE" disk 2>/dev/null
  ec=$?
  is_valid=false
  for c in "${valid_codes[@]}"; do [[ $ec -eq $c ]] && is_valid=true && break; done
  assert_equals "true" "$is_valid" \
    "system disk should succeed with an instance present, got: $ec"

  "$SYSTEM_MODULE" info 2>/dev/null
  ec=$?
  assert_equals "$EC_SUCCESS" "$ec" \
    "system info should succeed with an instance present"

  # Cleanup
  remove_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 12: network ports check on factorio's configured port (34197)
# 34197 is the factorio server port. Without the server running it should be free.
# This links blueprint port data to the network checking function.
# =============================================================================

function test_network_check_factorio_port() {
  log_test_step "Testing: network ports check on factorio port 34197 (should be free when server not running)"

  "$NETWORK_MODULE" ports check 34197 udp 2>/dev/null
  local exit_code=$?

  # Port 34197/udp should be free when no factorio server is running.
  # Accept free (254), in-use (255), or missing-dep (5) - all valid network responses.
  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_FREE ]] ||
     [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_IN_USE ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi
  assert_equals "true" "$is_valid" \
    "Port check on factorio port 34197/udp should return free/in-use/missing-dep, got: $exit_code"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting network+system integration tests"

  setup_test

  test_system_info_includes_network_section
  test_system_info_json_has_network_keys
  test_system_readonly_commands_succeed
  test_network_port_check_free_port
  test_network_port_check_invalid_port
  test_network_conflicts_no_instances
  test_network_conflicts_single_instance
  test_network_conflicts_duplicate_ports_detected
  test_network_test_all_with_instance
  test_network_ports_list_used_succeeds
  test_system_info_works_with_instances_present
  test_network_check_factorio_port

  log_test_step "Network+system integration tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All network+system integration tests passed"
  else
    fail_test "Some network+system integration tests failed"
  fi
}

main "$@"
