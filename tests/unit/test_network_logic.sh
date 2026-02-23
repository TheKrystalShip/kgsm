#!/usr/bin/env bash

# KGSM Network Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/network.sh - Pure __logic_* functions
#
# Tests all logic functions for network operations including:
# - Port validation and checking
# - Port conflict detection across KGSM instances
# - IP address retrieval
# - DNS information retrieval

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="network_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/network.sh"

# Test install dir for instances created in these tests
TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up network logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Network handler should exist"

  # Source the handler
  source "$HANDLER"

  # Verify error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_MISSING_DEPENDENCY" "EC_MISSING_DEPENDENCY should be defined"
  assert_not_null "$EC_NOT_FOUND" "EC_NOT_FOUND should be defined"
  assert_not_null "$EC_SUCCESS" "EC_SUCCESS should be defined"
  assert_not_null "$EC_SUCCESS_NETWORK_PORT_FREE" "EC_SUCCESS_NETWORK_PORT_FREE should be defined"
  assert_not_null "$EC_SUCCESS_NETWORK_PORT_IN_USE" "EC_SUCCESS_NETWORK_PORT_IN_USE should be defined"
  assert_not_null "$EC_SUCCESS_NETWORK_PORT_CHECKED" "EC_SUCCESS_NETWORK_PORT_CHECKED should be defined"

  # Verify all logic functions are exported
  assert_function_exists "__logic_check_port" "check_port should be exported"
  assert_function_exists "__logic_list_used_ports" "list_used_ports should be exported"
  assert_function_exists "__logic_find_port_conflicts" "find_port_conflicts should be exported"
  assert_function_exists "__logic_kill_port_process" "kill_port_process should be exported"
  assert_function_exists "__logic_test_port_accessibility" "test_port_accessibility should be exported"
  assert_function_exists "__logic_test_all_instance_ports" "test_all_instance_ports should be exported"
  assert_function_exists "__logic_get_external_ip" "get_external_ip should be exported"
  assert_function_exists "__logic_get_local_ip" "get_local_ip should be exported"
  assert_function_exists "__logic_get_dns_info" "get_dns_info should be exported"

  # Set install dir for test instances
  TEST_INSTALL_DIR="$KGSM_ROOT/instances-test-install"

  log_test_step "Network logic test environment validated"
}

# =============================================================================
# __logic_check_port() TESTS
# =============================================================================

function test_check_port_empty_arg() {
  log_test_step "Testing __logic_check_port with empty port"

  __logic_check_port "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty port"
}

function test_check_port_zero() {
  log_test_step "Testing __logic_check_port with port 0 (invalid)"

  __logic_check_port "0" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for port 0"
}

function test_check_port_too_high() {
  log_test_step "Testing __logic_check_port with port > 65535"

  __logic_check_port "65536" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for port > 65535"
}

function test_check_port_non_numeric() {
  log_test_step "Testing __logic_check_port with non-numeric port"

  __logic_check_port "abc" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for non-numeric port"
}

function test_check_port_invalid_protocol() {
  log_test_step "Testing __logic_check_port with invalid protocol"

  __logic_check_port "8080" "ftp" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for invalid protocol"
}

function test_check_port_valid_tcp() {
  log_test_step "Testing __logic_check_port with valid TCP port"

  # Use a port very unlikely to be in use (high port range)
  __logic_check_port "62345" "tcp" 2>/dev/null
  local exit_code=$?

  # Result should be either free or in_use (both are success codes)
  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_FREE" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_IN_USE" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return port_free, port_in_use, or missing_dependency for valid port check"
}

function test_check_port_valid_udp() {
  log_test_step "Testing __logic_check_port with valid UDP port"

  __logic_check_port "62346" "udp" 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_FREE" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_IN_USE" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return port_free, port_in_use, or missing_dependency for valid UDP port"
}

function test_check_port_default_protocol_tcp() {
  log_test_step "Testing __logic_check_port with no protocol defaults to tcp"

  __logic_check_port "62347" 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_FREE" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_IN_USE" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should succeed with default TCP protocol"
}

function test_check_port_free_port_output() {
  log_test_step "Testing __logic_check_port output format for free port"

  # Skip if no tools available
  if ! command -v ss >/dev/null 2>&1 && \
     ! command -v netstat >/dev/null 2>&1 && \
     ! command -v lsof >/dev/null 2>&1; then
    skip_test "No port checking tools available (ss/netstat/lsof)"
    return 0
  fi

  local output
  output=$(__logic_check_port "62348" "tcp" 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_FREE" ]]; then
    assert_equals "free" "$output" "Output should be 'free' for free port"
  elif [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_IN_USE" ]]; then
    assert_starts_with "$output" "in_use:" "Output should start with 'in_use:' for used port"
  fi
}

function test_check_port_boundary_values() {
  log_test_step "Testing __logic_check_port with boundary port values"

  # Port 1 (lowest valid)
  __logic_check_port "1" 2>/dev/null
  local exit_code=$?
  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_FREE" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_IN_USE" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi
  assert_equals "true" "$is_valid" "Port 1 should be valid"

  # Port 65535 (highest valid)
  __logic_check_port "65535" 2>/dev/null
  exit_code=$?
  is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_FREE" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_IN_USE" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi
  assert_equals "true" "$is_valid" "Port 65535 should be valid"
}

# =============================================================================
# __logic_list_used_ports() TESTS
# =============================================================================

function test_list_used_ports_returns_valid_code() {
  log_test_step "Testing __logic_list_used_ports returns valid exit code"

  __logic_list_used_ports 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_CHECKED" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return EC_SUCCESS_NETWORK_PORT_CHECKED or EC_MISSING_DEPENDENCY"
}

function test_list_used_ports_output_format() {
  log_test_step "Testing __logic_list_used_ports output format"

  if ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1; then
    skip_test "No port listing tools available (ss/netstat)"
    return 0
  fi

  local output
  output=$(__logic_list_used_ports 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_CHECKED" ]]; then
    assert_contains "$output" "TCP_PORTS:" "Output should contain TCP_PORTS section"
    assert_contains "$output" "UDP_PORTS:" "Output should contain UDP_PORTS section"
  fi
}

# =============================================================================
# __logic_find_port_conflicts() TESTS
# =============================================================================

function test_find_port_conflicts_no_instances() {
  log_test_step "Testing __logic_find_port_conflicts with no instances"

  local output
  output=$(__logic_find_port_conflicts 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "Should return EC_SUCCESS_NETWORK_PORT_CHECKED"
  assert_contains "$output" "no_conflicts" "Should report no_conflicts with no instances"
}

function test_find_port_conflicts_with_instance() {
  log_test_step "Testing __logic_find_port_conflicts with a single instance (no conflicts)"

  local blueprint="factorio"
  local instance_name
  instance_name=$(generate_test_id "nettest")

  local instance_created
  instance_created=$(create_test_instance "$blueprint" "$instance_name") || {
    skip_test "Failed to create test instance"
    return 0
  }

  local output
  output=$(__logic_find_port_conflicts 2>/dev/null)
  local exit_code=$?

  # Cleanup
  remove_test_instance "$blueprint" "$instance_created" 2>/dev/null || true

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "Should return EC_SUCCESS_NETWORK_PORT_CHECKED with single instance"
  # Single instance should not have port conflicts with itself
  assert_not_contains "$output" "conflict:${instance_created}" \
    "Single instance should not conflict with itself"
}

# =============================================================================
# __logic_kill_port_process() TESTS
# =============================================================================

function test_kill_port_process_empty_arg() {
  log_test_step "Testing __logic_kill_port_process with empty port"

  __logic_kill_port_process "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty port"
}

function test_kill_port_process_invalid_port() {
  log_test_step "Testing __logic_kill_port_process with invalid port"

  __logic_kill_port_process "not_a_port" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for non-numeric port"
}

function test_kill_port_process_port_zero() {
  log_test_step "Testing __logic_kill_port_process with port 0 (out of range)"

  __logic_kill_port_process "0" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for port 0"
}

function test_kill_port_process_port_too_high() {
  log_test_step "Testing __logic_kill_port_process with port > 65535"

  __logic_kill_port_process "99999" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for port > 65535"
}

function test_kill_port_process_unused_port() {
  log_test_step "Testing __logic_kill_port_process with unused port"

  if ! command -v lsof >/dev/null 2>&1 && \
     ! command -v ss >/dev/null 2>&1 && \
     ! command -v netstat >/dev/null 2>&1; then
    skip_test "No port checking tools available"
    return 0
  fi

  # Port 62349 - very likely not in use
  __logic_kill_port_process "62349" "tcp" 2>/dev/null
  local exit_code=$?

  # Should return EC_NOT_FOUND since no process on this port
  assert_equals "$EC_NOT_FOUND" "$exit_code" \
    "Should return EC_NOT_FOUND for port with no process"
}

# =============================================================================
# __logic_test_port_accessibility() TESTS
# =============================================================================

function test_port_accessibility_empty_port() {
  log_test_step "Testing __logic_test_port_accessibility with empty port"

  __logic_test_port_accessibility "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for empty port"
}

function test_port_accessibility_invalid_port() {
  log_test_step "Testing __logic_test_port_accessibility with invalid port"

  __logic_test_port_accessibility "65536" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for out-of-range port"
}

function test_port_accessibility_non_numeric() {
  log_test_step "Testing __logic_test_port_accessibility with non-numeric port"

  __logic_test_port_accessibility "notaport" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg for non-numeric port"
}

function test_port_accessibility_unlistened_port() {
  log_test_step "Testing __logic_test_port_accessibility with non-listening port"

  if ! command -v ss >/dev/null 2>&1 && \
     ! command -v netstat >/dev/null 2>&1 && \
     ! command -v lsof >/dev/null 2>&1; then
    skip_test "No port checking tools available"
    return 0
  fi

  local output
  output=$(__logic_test_port_accessibility "62350" "tcp" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "Should return EC_SUCCESS_NETWORK_PORT_CHECKED"
  assert_contains "$output" "not_accessible" \
    "Non-listening port should be not accessible"
}

# =============================================================================
# __logic_test_all_instance_ports() TESTS
# =============================================================================

function test_all_instance_ports_no_instances() {
  log_test_step "Testing __logic_test_all_instance_ports with no instances"

  local output
  output=$(__logic_test_all_instance_ports 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "Should return EC_SUCCESS_NETWORK_PORT_CHECKED"

  # Either no_instances or no_ports_to_test is acceptable
  local is_valid=false
  if [[ "$output" == *"no_instances"* ]] || [[ "$output" == *"no_ports_to_test"* ]]; then
    is_valid=true
  fi
  assert_equals "true" "$is_valid" \
    "Should output no_instances or no_ports_to_test when no instances have ports"
}

# =============================================================================
# __logic_get_external_ip() TESTS
# =============================================================================

function test_get_external_ip_returns_valid_code() {
  log_test_step "Testing __logic_get_external_ip returns valid exit code"

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    skip_test "Neither curl nor wget available"
    return 0
  fi

  __logic_get_external_ip 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_CHECKED" ]] ||
     [[ "$exit_code" -eq "$EC_ERROR" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return EC_SUCCESS_NETWORK_PORT_CHECKED, EC_ERROR, or EC_MISSING_DEPENDENCY"
}

function test_get_external_ip_missing_tools() {
  log_test_step "Testing __logic_get_external_ip returns EC_MISSING_DEPENDENCY when no tools"

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    # Both unavailable - function should return EC_MISSING_DEPENDENCY
    __logic_get_external_ip 2>/dev/null
    local exit_code=$?
    assert_equals "$EC_MISSING_DEPENDENCY" "$exit_code" \
      "Should return EC_MISSING_DEPENDENCY when no curl or wget"
  else
    skip_test "curl or wget available - cannot test missing dependency scenario"
    return 0
  fi
}

# =============================================================================
# __logic_get_local_ip() TESTS
# =============================================================================

function test_get_local_ip_returns_valid_code() {
  log_test_step "Testing __logic_get_local_ip returns valid exit code"

  __logic_get_local_ip 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_CHECKED" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]] ||
     [[ "$exit_code" -eq "$EC_ERROR" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return success, missing_dependency, or error exit code"
}

function test_get_local_ip_output_not_empty() {
  log_test_step "Testing __logic_get_local_ip output is non-empty when successful"

  if ! command -v hostname >/dev/null 2>&1 && ! command -v ip >/dev/null 2>&1; then
    skip_test "Neither hostname nor ip command available"
    return 0
  fi

  local output
  output=$(__logic_get_local_ip 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_CHECKED" ]]; then
    assert_not_null "$output" "Local IP output should not be empty on success"
  fi
}

function test_get_local_ip_output_format() {
  log_test_step "Testing __logic_get_local_ip output is valid IP address"

  if ! command -v hostname >/dev/null 2>&1 && ! command -v ip >/dev/null 2>&1; then
    skip_test "Neither hostname nor ip command available"
    return 0
  fi

  local output
  output=$(__logic_get_local_ip 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_CHECKED" ]]; then
    # Check at least one line looks like an IP address
    local first_ip
    first_ip=$(echo "$output" | head -1)
    assert_matches "$first_ip" "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" \
      "Output should contain valid IPv4 address"
  fi
}

# =============================================================================
# __logic_get_dns_info() TESTS
# =============================================================================

function test_get_dns_info_returns_valid_code() {
  log_test_step "Testing __logic_get_dns_info returns valid exit code"

  __logic_get_dns_info 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_NETWORK_PORT_CHECKED" ]] ||
     [[ "$exit_code" -eq "$EC_MISSING_DEPENDENCY" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return EC_SUCCESS_NETWORK_PORT_CHECKED or EC_MISSING_DEPENDENCY"
}

function test_get_dns_info_output_when_resolv_conf_exists() {
  log_test_step "Testing __logic_get_dns_info when /etc/resolv.conf exists"

  if [[ ! -f /etc/resolv.conf ]]; then
    skip_test "/etc/resolv.conf does not exist"
    return 0
  fi

  if ! grep -q "^nameserver" /etc/resolv.conf 2>/dev/null; then
    skip_test "No nameserver entries in /etc/resolv.conf"
    return 0
  fi

  local output
  output=$(__logic_get_dns_info 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "Should succeed when resolv.conf has nameservers"
  assert_not_null "$output" "DNS output should not be empty"
}

# =============================================================================
# MODULE LOAD FLAG TESTS
# =============================================================================

function test_module_load_flag_set() {
  log_test_step "Testing KGSM_LOGIC_NETWORK_LOADED flag is set after sourcing"

  assert_not_null "${KGSM_LOGIC_NETWORK_LOADED:-}" \
    "KGSM_LOGIC_NETWORK_LOADED should be set after sourcing handler"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting network logic handler tests"

  setup_test

  # __logic_check_port tests
  test_check_port_empty_arg
  test_check_port_zero
  test_check_port_too_high
  test_check_port_non_numeric
  test_check_port_invalid_protocol
  test_check_port_valid_tcp
  test_check_port_valid_udp
  test_check_port_default_protocol_tcp
  test_check_port_free_port_output
  test_check_port_boundary_values

  # __logic_list_used_ports tests
  test_list_used_ports_returns_valid_code
  test_list_used_ports_output_format

  # __logic_find_port_conflicts tests
  test_find_port_conflicts_no_instances
  test_find_port_conflicts_with_instance

  # __logic_kill_port_process tests
  test_kill_port_process_empty_arg
  test_kill_port_process_invalid_port
  test_kill_port_process_port_zero
  test_kill_port_process_port_too_high
  test_kill_port_process_unused_port

  # __logic_test_port_accessibility tests
  test_port_accessibility_empty_port
  test_port_accessibility_invalid_port
  test_port_accessibility_non_numeric
  test_port_accessibility_unlistened_port

  # __logic_test_all_instance_ports tests
  test_all_instance_ports_no_instances

  # __logic_get_external_ip tests
  test_get_external_ip_returns_valid_code
  test_get_external_ip_missing_tools

  # __logic_get_local_ip tests
  test_get_local_ip_returns_valid_code
  test_get_local_ip_output_not_empty
  test_get_local_ip_output_format

  # __logic_get_dns_info tests
  test_get_dns_info_returns_valid_code
  test_get_dns_info_output_when_resolv_conf_exists

  # Module flag test
  test_module_load_flag_set

  log_test_step "Network logic handler tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All network logic tests passed"
  else
    fail_test "Some network logic tests failed"
  fi
}

main "$@"
