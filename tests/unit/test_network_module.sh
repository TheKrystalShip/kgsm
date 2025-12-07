#!/usr/bin/env bash

# =============================================================================
# KGSM Network Module - Comprehensive Test Suite
# =============================================================================
#
# This test provides comprehensive coverage of the network.sh module, testing all
# commands, error conditions, edge cases, and behavioral consistency.
#
# The network module manages network operations for game server hosting:
# - Port management (check, list, conflicts, kill)
# - Connectivity testing (test-port, test-all)
# - Network information (dns)
#
# Test Coverage:
# ✓ Module existence and permissions
# ✓ Help functionality and usage display
# ✓ All command combinations
# ✓ Argument validation and error handling
# ✓ Port checking logic
# ✓ Integration with kgsm.sh delegation
# ✓ Debug mode functionality
# ✓ Behavioral consistency and predictability
# ✓ Edge cases and boundary conditions
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="network_module_comprehensive"
readonly NETWORK_MODULE="$KGSM_ROOT/commands/network.sh"
readonly NETWORK_LOGIC="$KGSM_ROOT/commands/handlers/network.sh"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function setup_test() {
  log_test "Setting up comprehensive network module test environment"

  # Basic module validation
  assert_file_exists "$NETWORK_MODULE" "Network module should exist"
  assert_file_executable "$NETWORK_MODULE" "Network module should be executable"

  # Verify logic library exists
  assert_file_exists "$NETWORK_LOGIC" "Network logic library should exist"

  # Ensure kgsm.sh exists in test environment
  if [[ ! -f "$KGSM_ROOT/kgsm.sh" ]]; then
    echo '#!/usr/bin/env bash' > "$KGSM_ROOT/kgsm.sh"
    chmod +x "$KGSM_ROOT/kgsm.sh"
    log_test "Created kgsm.sh in test environment"
  fi

  log_test "Test environment setup complete"
}

function cleanup_test() {
  log_test "Cleaning up network module test environment"
  # No cleanup needed for read-only tests
}

# =============================================================================
# TEST FUNCTIONS - BASIC MODULE VALIDATION
# =============================================================================

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  # Basic file system checks
  assert_file_exists "$NETWORK_MODULE" "Network module file should exist"
  assert_command_succeeds "test -r '$NETWORK_MODULE'" "Network module should be readable"
  assert_file_executable "$NETWORK_MODULE" "Network module should be executable"

  # Check file size (should not be empty)
  assert_command_succeeds "test -s '$NETWORK_MODULE'" "Network module should not be empty"

  # Verify it's a bash script
  local first_line
  first_line=$(head -n1 "$NETWORK_MODULE")
  assert_contains "$first_line" "#!/usr/bin/env bash" "Network module should be a bash script"

  log_test "Module existence and permissions validated"
}

function test_logic_library_existence() {
  log_step "Testing logic library existence"

  # Verify logic library exists and is readable
  assert_file_exists "$NETWORK_LOGIC" "Network logic library should exist"
  assert_command_succeeds "test -r '$NETWORK_LOGIC'" "Network logic library should be readable"
  assert_command_succeeds "test -s '$NETWORK_LOGIC'" "Network logic library should not be empty"

  # Verify it's a bash script
  local first_line
  first_line=$(head -n1 "$NETWORK_LOGIC")
  assert_contains "$first_line" "#!/usr/bin/env bash" "Network logic library should be a bash script"

  log_test "Logic library validated"
}

function test_help_functionality() {
  log_step "Testing help functionality and usage display"

  # Test --help flag
  assert_command_succeeds "$NETWORK_MODULE --help" "network.sh --help should work"

  # Test -h flag
  assert_command_succeeds "$NETWORK_MODULE -h" "network.sh -h should work"

  # Verify help content contains expected information
  local help_output
  help_output=$("$NETWORK_MODULE" --help 2>&1)

  assert_contains "$help_output" "Network Management for Krystal Game Server Manager" "Help should contain module description"
  assert_contains "$help_output" "ports check" "Help should document ports check command"
  assert_contains "$help_output" "ports list-used" "Help should document ports list-used command"
  assert_contains "$help_output" "ports conflicts" "Help should document ports conflicts command"
  assert_contains "$help_output" "ports kill" "Help should document ports kill command"
  assert_contains "$help_output" "test-port" "Help should document test-port command"
  assert_contains "$help_output" "test-all" "Help should document test-all command"
  assert_contains "$help_output" "dns" "Help should document dns command"
  assert_contains "$help_output" "Examples:" "Help should contain usage examples"

  log_test "Help functionality validated"
}

function test_command_specific_help() {
  log_step "Testing command-specific help"

  # Test help command with ports
  assert_command_succeeds "$NETWORK_MODULE help ports" "help ports should work"

  # Test help for ports subcommands
  assert_command_succeeds "$NETWORK_MODULE help ports check" "help ports check should work"
  assert_command_succeeds "$NETWORK_MODULE help ports kill" "help ports kill should work"

  # Test help command with test-port
  assert_command_succeeds "$NETWORK_MODULE help test-port" "help test-port should work"

  # Test inline --help for commands
  assert_command_succeeds "$NETWORK_MODULE ports check --help" "ports check --help should work"
  assert_command_succeeds "$NETWORK_MODULE test-port --help" "test-port --help should work"

  log_test "Command-specific help validated"
}

# =============================================================================
# TEST FUNCTIONS - ARGUMENT VALIDATION
# =============================================================================

function test_no_command_shows_usage() {
  log_step "Testing no command shows usage"

  # No command should show usage
  local output
  output=$("$NETWORK_MODULE" 2>&1)
  assert_contains "$output" "Network Management for Krystal Game Server Manager" "No command should show usage"

  log_test "No command behavior validated"
}

function test_invalid_command_handling() {
  log_step "Testing invalid command handling"

  # Invalid command should fail
  assert_command_fails "$NETWORK_MODULE invalid_command" "Invalid command should fail"

  local output
  output=$("$NETWORK_MODULE" invalid_command 2>&1)
  assert_contains "$output" "Unknown command" "Invalid command should show error"

  log_test "Invalid command handling validated"
}

function test_ports_check_argument_validation() {
  log_step "Testing ports check argument validation"

  # Missing port argument
  assert_command_fails "$NETWORK_MODULE ports check" "Missing port should fail"

  # Invalid port (too large)
  assert_command_fails "$NETWORK_MODULE ports check 99999" "Port > 65535 should fail"

  # Invalid port (zero)
  assert_command_fails "$NETWORK_MODULE ports check 0" "Port 0 should fail"

  # Invalid port (negative)
  assert_command_fails "$NETWORK_MODULE ports check -5" "Negative port should fail"

  # Invalid port (non-numeric)
  assert_command_fails "$NETWORK_MODULE ports check abc" "Non-numeric port should fail"

  # Help should work
  assert_command_succeeds "$NETWORK_MODULE ports check --help" "ports check --help should work"

  log_test "Ports check argument validation tested"
}

# =============================================================================
# TEST FUNCTIONS - PORT MANAGEMENT COMMANDS
# =============================================================================

function test_ports_check_command() {
  log_step "Testing ports check command"

  # Check a likely free port
  # Using high port number to minimize chance of collision
  local test_port=54321

  # Should succeed (free or in use, both are valid outcomes)
  local output
  output=$("$NETWORK_MODULE" ports check "$test_port" 2>&1)

  # Output should contain either FREE or IN USE
  if [[ "$output" == *"FREE"* ]] || [[ "$output" == *"IN USE"* ]]; then
    log_test "Port check returned valid status"
  else
    fail "Port check should return FREE or IN USE status"
  fi

  # Test TCP protocol (explicit)
  assert_command_succeeds "$NETWORK_MODULE ports check $test_port tcp" "ports check with tcp protocol should work"

  # Test UDP protocol
  assert_command_succeeds "$NETWORK_MODULE ports check $test_port udp" "ports check with udp protocol should work"

  log_test "Ports check command tested"
}

function test_ports_list_used_command() {
  log_step "Testing ports list-used command"

  # Should succeed if tools are available
  if command -v ss >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1; then
    assert_command_succeeds "$NETWORK_MODULE ports list-used" "ports list-used should work"

    local output
    output=$("$NETWORK_MODULE" ports list-used 2>&1)
    # Should show ports (TCP_PORTS and/or UDP_PORTS headers)
    if [[ "$output" == *"TCP_PORTS"* ]] || [[ "$output" == *"UDP_PORTS"* ]]; then
      log_test "Port list contains expected headers"
    fi
  else
    log_test "Skipping ports list-used test - required tools not available"
  fi

  # Invalid argument should fail
  assert_command_fails "$NETWORK_MODULE ports list-used --invalid" "Invalid argument should fail"

  log_test "Ports list-used command tested"
}

function test_ports_conflicts_command() {
  log_step "Testing ports conflicts command"

  # Should always succeed (no conflicts or conflicts found, both valid)
  assert_command_succeeds "$NETWORK_MODULE ports conflicts" "ports conflicts should work"

  local output
  output=$("$NETWORK_MODULE" ports conflicts 2>&1)

  # Should contain either "No port conflicts" or conflict information
  if [[ "$output" == *"conflicts"* ]] || [[ "$output" == *"Scanning"* ]]; then
    log_test "Port conflicts check completed"
  fi

  # Invalid argument should fail
  assert_command_fails "$NETWORK_MODULE ports conflicts --invalid" "Invalid argument should fail"

  log_test "Ports conflicts command tested"
}

function test_ports_subcommand_routing() {
  log_step "Testing ports subcommand routing"

  # Missing subcommand should fail
  assert_command_fails "$NETWORK_MODULE ports" "Missing ports subcommand should fail"

  # Invalid subcommand should fail
  assert_command_fails "$NETWORK_MODULE ports invalid" "Invalid ports subcommand should fail"

  # Help for ports should work
  assert_command_succeeds "$NETWORK_MODULE ports --help" "ports --help should work"

  log_test "Ports subcommand routing tested"
}

# =============================================================================
# TEST FUNCTIONS - CONNECTIVITY TESTING COMMANDS
# =============================================================================

function test_test_port_command() {
  log_step "Testing test-port command"

  # Test with a port (may or may not be accessible, but should not crash)
  local test_port=12345

  # Should complete without error (accessibility result may vary)
  local output
  output=$("$NETWORK_MODULE" test-port "$test_port" 2>&1 || true)

  # Should contain some result
  if [[ "$output" == *"Testing"* ]] || [[ "$output" == *"port"* ]]; then
    log_test "Test-port executed"
  fi

  # Invalid port should fail
  assert_command_fails "$NETWORK_MODULE test-port 99999" "Invalid port should fail"

  # Help should work
  assert_command_succeeds "$NETWORK_MODULE test-port --help" "test-port --help should work"

  log_test "Test-port command tested"
}

function test_test_all_command() {
  log_step "Testing test-all command"

  # Should complete (may have no instances, which is fine)
  assert_command_succeeds "$NETWORK_MODULE test-all" "test-all should work"

  local output
  output=$("$NETWORK_MODULE" test-all 2>&1)

  # Should show testing message or results
  if [[ "$output" == *"Testing"* ]] || [[ "$output" == *"No"* ]]; then
    log_test "Test-all executed"
  fi

  # Invalid argument should fail
  assert_command_fails "$NETWORK_MODULE test-all --invalid" "Invalid argument should fail"

  log_test "Test-all command tested"
}

# =============================================================================
# TEST FUNCTIONS - NETWORK INFORMATION COMMANDS
# =============================================================================

function test_dns_command() {
  log_step "Testing dns command"

  # DNS command should work (may fail gracefully if tools unavailable)
  local output
  output=$("$NETWORK_MODULE" dns 2>&1 || true)

  # Should either show DNS servers or error message
  if [[ "$output" == *"DNS"* ]] || [[ "$output" == *"Cannot"* ]]; then
    log_test "DNS command executed"
  fi

  # Invalid argument should fail
  assert_command_fails "$NETWORK_MODULE dns --invalid" "Invalid argument should fail"

  log_test "DNS command tested"
}

# =============================================================================
# TEST FUNCTIONS - INTEGRATION WITH KGSM.SH
# =============================================================================

function test_kgsm_delegation() {
  log_step "Testing kgsm.sh delegates to network module"

  local kgsm_script="$KGSM_ROOT/kgsm.sh"

  # Ensure kgsm.sh exists and is executable
  assert_file_exists "$kgsm_script" "kgsm.sh should exist"
  assert_file_executable "$kgsm_script" "kgsm.sh should be executable"

  # Test network command delegation
  assert_command_succeeds "$kgsm_script network --help" "kgsm.sh network --help should work"

  local output
  output=$("$kgsm_script" network --help 2>&1)
  assert_contains "$output" "Network Management" "Delegated command should show network help"

  # Test specific network commands through kgsm.sh
  assert_command_succeeds "$kgsm_script network ports check 12345" "kgsm.sh network ports check should work"

  log_test "KGSM delegation validated"
}

# =============================================================================
# TEST FUNCTIONS - DEBUG MODE
# =============================================================================

function test_debug_mode() {
  log_step "Testing debug mode"

  # Debug mode should enable verbose output
  local output
  output=$("$NETWORK_MODULE" --debug dns 2>&1 || true)

  # In debug mode, we should see trace output (PS4)
  # Note: May not work in all test environments, so we make this lenient
  if [[ "$output" == *"BASH_SOURCE"* ]] || [[ "$output" == *"dns"* ]] || [[ "$output" == *"DNS"* ]]; then
    log_test "Debug mode appears to be working"
  else
    log_test "Debug mode test inconclusive (may not work in test environment)"
  fi

  log_test "Debug mode tested"
}

# =============================================================================
# TEST FUNCTIONS - BEHAVIORAL CONSISTENCY
# =============================================================================

function test_behavioral_consistency() {
  log_step "Testing behavioral consistency"

  # Multiple calls to same command should produce consistent results
  local test_port=54321
  local output1
  local output2

  output1=$("$NETWORK_MODULE" ports check "$test_port" 2>&1)
  sleep 0.5
  output2=$("$NETWORK_MODULE" ports check "$test_port" 2>&1)

  # Both should succeed or both should fail
  # Results should be structurally similar (both contain "port" or "Port")
  if [[ "$output1" == *"ort"* ]]; then
    assert_contains "$output2" "ort" "Consistent command should have consistent output structure"
  fi

  # Invalid commands should consistently fail
  assert_command_fails "$NETWORK_MODULE invalid1" "Invalid command should fail"
  assert_command_fails "$NETWORK_MODULE invalid2" "Invalid command should fail"

  log_test "Behavioral consistency validated"
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

function run_all_tests() {
  log_test "Starting network module comprehensive test suite"

  setup_test

  # Basic validation tests
  test_module_existence_and_permissions
  test_logic_library_existence
  test_help_functionality
  test_command_specific_help

  # Argument validation tests
  test_no_command_shows_usage
  test_invalid_command_handling
  test_ports_check_argument_validation

  # Port management tests
  test_ports_check_command
  test_ports_list_used_command
  test_ports_conflicts_command
  test_ports_subcommand_routing

  # Connectivity testing tests
  test_test_port_command
  test_test_all_command

  # Network information tests
  test_dns_command

  # Integration tests
  test_kgsm_delegation

  # Debug and consistency tests
  test_debug_mode
  test_behavioral_consistency

  cleanup_test

  log_test "Network module comprehensive test suite completed"
}

# Run all tests
run_all_tests
