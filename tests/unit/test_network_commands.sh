#!/usr/bin/env bash

# KGSM Network Command CLI Tests
#
# Test Type: UNIT
# Target: commands/network.sh - CLI interface and argument handling
#
# Tests the CLI interface of network.sh including help system,
# error handling for missing/invalid args, and behavior without
# external network dependencies.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="network_commands"
readonly MODULE="$KGSM_ROOT/commands/network.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up network commands tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "network.sh module should exist"
  assert_file_executable "$MODULE" "network.sh should be executable"

  log_test_step "Test environment validated"
}

# =============================================================================
# HELP SYSTEM TESTS
# =============================================================================

function test_help_top_level() {
  log_test_step "Testing top-level help output"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should succeed"
  assert_contains "$output" "ports" "Help should mention ports command"
  assert_contains "$output" "test-port" "Help should mention test-port command"
  assert_contains "$output" "ip" "Help should mention ip command"
  assert_contains "$output" "dns" "Help should mention dns command"
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "ports" "Help output should mention ports"
}

function test_help_h_flag() {
  log_test_step "Testing -h flag output"

  local output
  output=$("$MODULE" -h 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "-h flag should succeed"
  assert_contains "$output" "ports" "Help output should mention ports"
}

function test_help_ports_command() {
  log_test_step "Testing help for ports command"

  local output
  output=$("$MODULE" help ports 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help ports should succeed"
  assert_contains "$output" "check" "Ports help should mention check subcommand"
  assert_contains "$output" "list-used" "Ports help should mention list-used subcommand"
  assert_contains "$output" "conflicts" "Ports help should mention conflicts subcommand"
  assert_contains "$output" "kill" "Ports help should mention kill subcommand"
}

function test_help_ports_check_command() {
  log_test_step "Testing help for ports check subcommand"

  local output
  output=$("$MODULE" help ports check 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help ports check should succeed"
  assert_contains "$output" "port" "Ports check help should mention port argument"
}

function test_help_ports_kill_command() {
  log_test_step "Testing help for ports kill subcommand"

  local output
  output=$("$MODULE" help ports kill 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help ports kill should succeed"
  assert_contains "$output" "port" "Ports kill help should mention port argument"
}

function test_help_test_port_command() {
  log_test_step "Testing help for test-port command"

  local output
  output=$("$MODULE" help test-port 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help test-port should succeed"
  assert_contains "$output" "port" "test-port help should mention port argument"
}

function test_help_ip_command() {
  log_test_step "Testing help for ip command"

  local output
  output=$("$MODULE" help ip 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help ip should succeed"
  assert_contains "$output" "IP" "ip help should mention IP"
}

function test_help_unknown_command() {
  log_test_step "Testing help for unknown command returns error"

  assert_command_fails "$MODULE help nonexistent_cmd_xyz" \
    "help for unknown command should fail"

  local output
  output=$("$MODULE" help nonexistent_cmd_xyz 2>&1 || true)
  assert_contains "$output" "Unknown command" "Should show unknown command error"
}

# =============================================================================
# NO COMMAND / UNKNOWN COMMAND TESTS
# =============================================================================

function test_no_command() {
  log_test_step "Testing module with no command shows usage and fails"

  local output
  output=$("$MODULE" 2>&1 || true)

  assert_contains "$output" "ports" "No-command output should mention ports"
}

function test_unknown_command() {
  log_test_step "Testing unknown top-level command returns EC_INVALID_ARG"

  assert_command_fails "$MODULE notacommand_xyz" \
    "Unknown command should fail"

  local output
  output=$("$MODULE" notacommand_xyz 2>&1 || true)
  assert_contains "$output" "Unknown command" "Should show unknown command error"
}

function test_unknown_command_exit_code() {
  log_test_step "Testing unknown top-level command returns EC_INVALID_ARG exit code"

  "$MODULE" unknowncmd 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Unknown command should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

# =============================================================================
# PORTS SUBCOMMAND ROUTING TESTS
# =============================================================================

function test_ports_no_subcommand() {
  log_test_step "Testing ports with no subcommand returns EC_MISSING_ARG"

  "$MODULE" ports 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "ports with no subcommand should return EC_MISSING_ARG ($EC_MISSING_ARG)"
}

function test_ports_unknown_subcommand() {
  log_test_step "Testing ports with unknown subcommand returns EC_INVALID_ARG"

  "$MODULE" ports notasubcmd 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports with unknown subcommand should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_help_flag() {
  log_test_step "Testing ports --help shows help"

  local output
  output=$("$MODULE" ports --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "ports --help should succeed"
  assert_contains "$output" "check" "Should mention check subcommand"
}

# =============================================================================
# PORTS CHECK TESTS
# =============================================================================

function test_ports_check_missing_port() {
  log_test_step "Testing ports check with missing port argument"

  "$MODULE" ports check 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "ports check with no port should return EC_MISSING_ARG ($EC_MISSING_ARG)"

  local output
  output=$("$MODULE" ports check 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_ports_check_invalid_port_zero() {
  log_test_step "Testing ports check with port 0 (below valid range)"

  "$MODULE" ports check 0 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports check with port 0 should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_check_invalid_port_too_high() {
  log_test_step "Testing ports check with port 65536 (above valid range)"

  "$MODULE" ports check 65536 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports check with port 65536 should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_check_invalid_port_text() {
  log_test_step "Testing ports check with non-numeric port"

  "$MODULE" ports check notaport 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports check with text port should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_check_invalid_protocol() {
  log_test_step "Testing ports check with invalid protocol via -p flag before port"

  # Protocol flag must come before port positional arg (loop breaks on first positional)
  "$MODULE" ports check -p badprotocol 27015 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports check with invalid protocol (-p badprotocol) should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_check_help() {
  log_test_step "Testing ports check --help"

  local output
  output=$("$MODULE" ports check --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "ports check --help should succeed"
  assert_contains "$output" "port" "Should show port argument info"
}

function test_ports_check_valid_port() {
  log_test_step "Testing ports check with valid port succeeds or missing dep"

  "$MODULE" ports check 27015 2>/dev/null
  local exit_code=$?

  # Should be a network success code (free or in-use) or missing dependency
  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_FREE ]] ||
     [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_IN_USE ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "ports check valid port should return a port status or missing dependency, got: $exit_code"
}

# =============================================================================
# PORTS LIST-USED TESTS
# =============================================================================

function test_ports_list_used_help() {
  log_test_step "Testing ports list-used --help"

  local output
  output=$("$MODULE" ports list-used --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "ports list-used --help should succeed"
}

function test_ports_list_used_invalid_arg() {
  log_test_step "Testing ports list-used with invalid argument"

  "$MODULE" ports list-used --invalid-flag-xyz 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports list-used with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_list_used_succeeds() {
  log_test_step "Testing ports list-used returns success or missing dependency"

  "$MODULE" ports list-used 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_CHECKED ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "ports list-used should succeed or report missing dependency, got: $exit_code"
}

# =============================================================================
# PORTS CONFLICTS TESTS
# =============================================================================

function test_ports_conflicts_help() {
  log_test_step "Testing ports conflicts --help"

  local output
  output=$("$MODULE" ports conflicts --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "ports conflicts --help should succeed"
}

function test_ports_conflicts_invalid_arg() {
  log_test_step "Testing ports conflicts with invalid argument"

  "$MODULE" ports conflicts --invalid-flag-xyz 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports conflicts with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_conflicts_succeeds_no_instances() {
  log_test_step "Testing ports conflicts succeeds in sandbox (no instances)"

  "$MODULE" ports conflicts 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "ports conflicts with no instances should return EC_SUCCESS_NETWORK_PORT_CHECKED ($EC_SUCCESS_NETWORK_PORT_CHECKED)"

  local output
  output=$("$MODULE" ports conflicts 2>&1 || true)
  assert_contains "$output" "No port conflicts" "Should report no conflicts when no instances"
}

# =============================================================================
# PORTS KILL TESTS
# =============================================================================

function test_ports_kill_missing_port() {
  log_test_step "Testing ports kill with missing port argument"

  "$MODULE" ports kill 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "ports kill with no port should return EC_MISSING_ARG ($EC_MISSING_ARG)"

  local output
  output=$("$MODULE" ports kill 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_ports_kill_invalid_port_zero() {
  log_test_step "Testing ports kill with port 0"

  "$MODULE" ports kill 0 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports kill with port 0 should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_kill_invalid_port_text() {
  log_test_step "Testing ports kill with non-numeric port"

  "$MODULE" ports kill notaport 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ports kill with text port should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_ports_kill_help() {
  log_test_step "Testing ports kill --help"

  local output
  output=$("$MODULE" ports kill --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "ports kill --help should succeed"
  assert_contains "$output" "port" "Should show port argument info"
}

# =============================================================================
# TEST-PORT TESTS
# =============================================================================

function test_test_port_missing_port() {
  log_test_step "Testing test-port with missing port argument"

  "$MODULE" test-port 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "test-port with no port should return EC_MISSING_ARG ($EC_MISSING_ARG)"

  local output
  output=$("$MODULE" test-port 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_test_port_invalid_port_zero() {
  log_test_step "Testing test-port with port 0"

  "$MODULE" test-port 0 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "test-port with port 0 should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_test_port_invalid_port_high() {
  log_test_step "Testing test-port with port 65536"

  "$MODULE" test-port 65536 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "test-port with port 65536 should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_test_port_invalid_port_text() {
  log_test_step "Testing test-port with non-numeric port"

  "$MODULE" test-port notaport 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "test-port with text port should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_test_port_help() {
  log_test_step "Testing test-port --help"

  local output
  output=$("$MODULE" test-port --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "test-port --help should succeed"
  assert_contains "$output" "port" "Should show port argument info"
}

function test_test_port_valid_port_not_listening() {
  log_test_step "Testing test-port with valid non-listening port returns success code"

  # Port 59999 is unlikely to be listening
  "$MODULE" test-port 59999 2>/dev/null
  local exit_code=$?

  # Should return EC_SUCCESS_NETWORK_PORT_CHECKED (port tested, not accessible) or EC_INVALID_ARG
  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_CHECKED ]] ||
     [[ $exit_code -eq $EC_INVALID_ARG ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "test-port on non-listening port should return a valid code, got: $exit_code"
}

# =============================================================================
# TEST-ALL TESTS
# =============================================================================

function test_test_all_help() {
  log_test_step "Testing test-all --help"

  local output
  output=$("$MODULE" test-all --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "test-all --help should succeed"
}

function test_test_all_invalid_arg() {
  log_test_step "Testing test-all with invalid argument"

  "$MODULE" test-all --invalid-flag-xyz 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "test-all with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_test_all_no_instances() {
  log_test_step "Testing test-all succeeds in sandbox (no instances or no ports)"

  "$MODULE" test-all 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_NETWORK_PORT_CHECKED" "$exit_code" \
    "test-all should return EC_SUCCESS_NETWORK_PORT_CHECKED ($EC_SUCCESS_NETWORK_PORT_CHECKED)"

  local output
  output=$("$MODULE" test-all 2>&1 || true)
  # Accept either "No KGSM instances" or "No ports configured" depending on sandbox state
  local has_expected_message=false
  if echo "$output" | grep -qi "No KGSM instances\|No ports configured\|no_instances\|no_ports_to_test"; then
    has_expected_message=true
  fi
  assert_equals "true" "$has_expected_message" \
    "test-all output should mention no instances or no ports, got: $output"
}

# =============================================================================
# IP COMMAND TESTS
# =============================================================================

function test_ip_help() {
  log_test_step "Testing ip --help"

  local output
  output=$("$MODULE" ip --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "ip --help should succeed"
  assert_contains "$output" "IP" "Should show IP info"
}

function test_ip_invalid_arg() {
  log_test_step "Testing ip with invalid argument"

  "$MODULE" ip --invalid-flag-xyz 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "ip with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

# =============================================================================
# DNS COMMAND TESTS
# =============================================================================

function test_dns_help() {
  log_test_step "Testing dns --help"

  local output
  output=$("$MODULE" dns --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "dns --help should succeed"
}

function test_dns_invalid_arg() {
  log_test_step "Testing dns with invalid argument"

  "$MODULE" dns --invalid-flag-xyz 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "dns with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_dns_succeeds_or_missing_dep() {
  log_test_step "Testing dns returns success or missing dependency"

  "$MODULE" dns 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_NETWORK_PORT_CHECKED ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "dns should succeed or report missing dependency, got: $exit_code"
}

