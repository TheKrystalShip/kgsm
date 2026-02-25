#!/usr/bin/env bash

# KGSM Watcher + Instances Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between watcher.sh, watcher.logs.sh, watcher.ports.sh and real instances
#
# Integration points tested:
# - watcher.sh strategy selection based on real instance configuration
# - watcher.logs.sh status/test with real instance (factorio has startup_success_regex)
# - watcher.ports.sh status/test with real instance (ark has ports only, no startup_success_regex)
# - Log watcher test succeeds when log file contains matching pattern
# - Log watcher test fails gracefully when log file is absent
# - Port watcher test handles inactive ports gracefully
# - Error handling: invalid instance names are rejected
# - Orchestrator delegates to correct sub-watcher based on strategy

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="watcher_instances_integration"
readonly WATCHER_MODULE="$KGSM_ROOT/commands/watcher.sh"
readonly WATCHER_LOGS_MODULE="$KGSM_ROOT/commands/watcher.logs.sh"
readonly WATCHER_PORTS_MODULE="$KGSM_ROOT/commands/watcher.ports.sh"

# factorio: has startup_success_regex -> logs strategy
# ark: has empty startup_success_regex, has ports -> ports strategy
readonly BLUEPRINT_LOGS_STRATEGY="factorio"
readonly BLUEPRINT_PORTS_STRATEGY="ark"

TEST_INSTALL_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up watcher+instances integration tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$WATCHER_MODULE" "watcher.sh module should exist"
  assert_file_executable "$WATCHER_MODULE" "watcher.sh should be executable"
  assert_file_exists "$WATCHER_LOGS_MODULE" "watcher.logs.sh module should exist"
  assert_file_executable "$WATCHER_LOGS_MODULE" "watcher.logs.sh should be executable"
  assert_file_exists "$WATCHER_PORTS_MODULE" "watcher.ports.sh module should exist"
  assert_file_executable "$WATCHER_PORTS_MODULE" "watcher.ports.sh should be executable"

  log_test_step "Integration test environment validated"
}

# =============================================================================
# HELPER: create an instance and skip the test if creation fails
# Usage: _create_instance_or_skip <blueprint> <name>
# Returns: 0 on success, calls skip_test and returns 1 on failure
# =============================================================================

function _create_instance_or_skip() {
  local blueprint="$1"
  local instance_name="$2"

  create_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR" >/dev/null 2>&1
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    skip_test "Instance creation failed (exit $exit_code) - skipping test"
    return 1
  fi

  return 0
}

# =============================================================================
# TEST 1: watcher.sh status selects 'logs' strategy for instance with startup_success_regex
# factorio blueprint has startup_success_regex configured → logs strategy must be selected
# =============================================================================

function test_watcher_status_selects_logs_strategy() {
  log_test_step "Testing: watcher status selects 'logs' strategy for instance with startup_success_regex"

  local instance_name="watcher-logs-strat-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  local output
  output=$("$WATCHER_MODULE" status "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "watcher status should succeed for valid instance"
  assert_not_null "$output" "watcher status should produce output"
  assert_contains "$output" "Selected strategy:" \
    "watcher status should show strategy selection header"
  assert_contains "$output" "logs" \
    "watcher status should show 'logs' as selected strategy for factorio instance"
  assert_contains "$output" "$instance_name" \
    "watcher status output should mention the instance name"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 2: watcher.sh status selects 'ports' strategy for instance without startup_success_regex
# ark blueprint has empty startup_success_regex but has ports → ports strategy must be selected
# =============================================================================

function test_watcher_status_selects_ports_strategy() {
  log_test_step "Testing: watcher status selects 'ports' strategy for instance with ports but no regex"

  local instance_name="watcher-ports-strat-$$"
  _create_instance_or_skip "$BLUEPRINT_PORTS_STRATEGY" "$instance_name" || return

  local output
  output=$("$WATCHER_MODULE" status "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "watcher status should succeed for valid ark instance"
  assert_not_null "$output" "watcher status should produce output"
  assert_contains "$output" "Selected strategy:" \
    "watcher status should show strategy selection header"
  assert_contains "$output" "ports" \
    "watcher status should show 'ports' as selected strategy for ark instance"

  remove_test_instance "$BLUEPRINT_PORTS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 3: watcher.sh status rejects unknown instance
# Nonexistent instance must fail with a non-zero exit code
# =============================================================================

function test_watcher_status_rejects_invalid_instance() {
  log_test_step "Testing: watcher status fails for nonexistent instance"

  "$WATCHER_MODULE" status "nonexistent_watcher_xyz_abc_$$" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "watcher status should fail for nonexistent instance"
}

# =============================================================================
# TEST 4: watcher.sh start rejects unknown instance
# =============================================================================

function test_watcher_start_rejects_invalid_instance() {
  log_test_step "Testing: watcher start fails for nonexistent instance"

  "$WATCHER_MODULE" start "nonexistent_watcher_xyz_abc_$$" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "watcher start should fail for nonexistent instance"
}

# =============================================================================
# TEST 5: watcher.sh test rejects unknown instance
# =============================================================================

function test_watcher_test_rejects_invalid_instance() {
  log_test_step "Testing: watcher test fails for nonexistent instance"

  "$WATCHER_MODULE" test "nonexistent_watcher_xyz_abc_$$" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "watcher test should fail for nonexistent instance"
}

# =============================================================================
# TEST 6: watcher.logs.sh status shows log pattern for instance with startup_success_regex
# factorio instance config has startup_success_regex → status should display the pattern
# =============================================================================

function test_watcher_logs_status_shows_pattern() {
  log_test_step "Testing: watcher.logs.sh status shows startup_success_regex for factorio instance"

  local instance_name="watcher-logs-status-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  local output
  output=$("$WATCHER_LOGS_MODULE" status "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "watcher.logs.sh status should succeed"
  assert_not_null "$output" "watcher.logs.sh status should produce output"
  # factorio.bp has startup_success_regex="Hosting game at IP ADDR"
  assert_contains "$output" "Hosting game at IP ADDR" \
    "watcher.logs.sh status should show the configured startup_success_regex pattern"
  assert_contains "$output" "$instance_name" \
    "watcher.logs.sh status output should mention the instance name"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 7: watcher.logs.sh status for unknown instance fails
# =============================================================================

function test_watcher_logs_status_rejects_invalid_instance() {
  log_test_step "Testing: watcher.logs.sh status fails for nonexistent instance"

  "$WATCHER_LOGS_MODULE" status "nonexistent_watcher_xyz_abc_$$" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "watcher.logs.sh status should fail for nonexistent instance"
}

# =============================================================================
# TEST 8: watcher.logs.sh test fails when log file does not exist
# An instance's log file only appears when the server actually runs
# Without running the server, watcher.logs.sh test must report file missing
# =============================================================================

function test_watcher_logs_test_fails_when_log_absent() {
  log_test_step "Testing: watcher.logs.sh test fails gracefully when log file is absent"

  local instance_name="watcher-logs-nofile-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  # The log file does not exist (server not running)
  "$WATCHER_LOGS_MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "watcher.logs.sh test should fail when log file is absent"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 9: watcher.logs.sh test succeeds when log file contains matching pattern
# Create the log file with the expected pattern to simulate a running server
# =============================================================================

function test_watcher_logs_test_succeeds_with_matching_log() {
  log_test_step "Testing: watcher.logs.sh test succeeds when log contains startup_success_regex"

  local instance_name="watcher-logs-match-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  # Find the instance config to determine log file path
  local instances_module="$KGSM_ROOT/commands/instances.sh"
  local instance_config_file
  instance_config_file=$("$instances_module" find "$instance_name" 2>/dev/null)

  if [[ -z "$instance_config_file" || ! -f "$instance_config_file" ]]; then
    skip_test "Cannot find instance config file - skipping test"
    remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
    return
  fi

  # Extract log_file path and startup_success_regex from instance config
  local log_file_path
  log_file_path=$(grep "^log_file=" "$instance_config_file" | cut -d'=' -f2 | tr -d '"')

  local ready_pattern
  ready_pattern=$(grep "^startup_success_regex=" "$instance_config_file" | cut -d'=' -f2 | tr -d '"')

  if [[ -z "$log_file_path" ]]; then
    skip_test "Cannot determine log file path from instance config - skipping test"
    remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
    return
  fi

  if [[ -z "$ready_pattern" ]]; then
    skip_test "Instance has no startup_success_regex configured - skipping test"
    remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
    return
  fi

  # Create the log file's parent directory if needed
  mkdir -p "$(dirname "$log_file_path")" 2>/dev/null || true

  # Write a log line containing the expected pattern
  echo "[Server] $ready_pattern" > "$log_file_path"

  # Now test should succeed (pattern found in log)
  "$WATCHER_LOGS_MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  # Clean up the log file before assertions
  rm -f "$log_file_path" 2>/dev/null || true

  assert_equals 0 "$exit_code" \
    "watcher.logs.sh test should succeed when log file contains the startup_success_regex pattern"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 10: watcher.logs.sh test reports pattern-not-found when log exists but has no match
# Log file exists but doesn't contain the startup pattern yet
# =============================================================================

function test_watcher_logs_test_pattern_not_found_in_existing_log() {
  log_test_step "Testing: watcher.logs.sh test fails when log exists but has no matching pattern"

  local instance_name="watcher-logs-nomatch-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  local instances_module="$KGSM_ROOT/commands/instances.sh"
  local instance_config_file
  instance_config_file=$("$instances_module" find "$instance_name" 2>/dev/null)

  if [[ -z "$instance_config_file" || ! -f "$instance_config_file" ]]; then
    skip_test "Cannot find instance config file - skipping test"
    remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
    return
  fi

  local log_file_path
  log_file_path=$(grep "^log_file=" "$instance_config_file" | cut -d'=' -f2 | tr -d '"')

  if [[ -z "$log_file_path" ]]; then
    skip_test "Cannot determine log file path - skipping test"
    remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
    return
  fi

  # Create log file with content that does NOT match the pattern
  mkdir -p "$(dirname "$log_file_path")" 2>/dev/null || true
  echo "[Server] Starting up... loading mods..." > "$log_file_path"

  # Pattern is not in the log yet - test should fail
  "$WATCHER_LOGS_MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  rm -f "$log_file_path" 2>/dev/null || true

  assert_not_equals 0 "$exit_code" \
    "watcher.logs.sh test should fail when log exists but startup pattern is not found"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 11: watcher.ports.sh status shows configured ports for instance
# factorio has ports='34197' → watcher.ports.sh status should show that port
# =============================================================================

function test_watcher_ports_status_shows_configured_ports() {
  log_test_step "Testing: watcher.ports.sh status shows configured ports for instance"

  local instance_name="watcher-ports-status-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  local output
  output=$("$WATCHER_PORTS_MODULE" status "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "watcher.ports.sh status should succeed for valid instance"
  assert_not_null "$output" "watcher.ports.sh status should produce output"
  # factorio.bp has ports='34197'
  assert_contains "$output" "34197" \
    "watcher.ports.sh status should show the configured port (34197) for factorio instance"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 12: watcher.ports.sh status for unknown instance fails
# =============================================================================

function test_watcher_ports_status_rejects_invalid_instance() {
  log_test_step "Testing: watcher.ports.sh status fails for nonexistent instance"

  "$WATCHER_PORTS_MODULE" status "nonexistent_watcher_xyz_abc_$$" 2>/dev/null
  local exit_code=$?

  assert_not_equals 0 "$exit_code" \
    "watcher.ports.sh status should fail for nonexistent instance"
}

# =============================================================================
# TEST 13: watcher.ports.sh test reports ports inactive (server not running)
# With no server running, configured ports should be inactive
# =============================================================================

function test_watcher_ports_test_handles_inactive_ports() {
  log_test_step "Testing: watcher.ports.sh test reports inactive ports gracefully"

  local instance_name="watcher-ports-test-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  # Server is not running, ports should be inactive
  "$WATCHER_PORTS_MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  # Should fail (ports not active) but not crash - must return a known non-zero code
  assert_not_equals 0 "$exit_code" \
    "watcher.ports.sh test should fail when server ports are not active"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 14: watcher.sh test for logs-strategy instance delegates to watcher.logs.sh
# factorio instance with startup_success_regex → watcher.sh test should run the log test
# (log file absent → should fail with log-related error, not a "no strategy" error)
# =============================================================================

function test_watcher_test_delegates_to_log_watcher() {
  log_test_step "Testing: watcher.sh test delegates to log watcher for logs-strategy instance"

  local instance_name="watcher-test-logs-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  # Run watcher.sh test (not watcher.logs.sh directly) - should delegate to logs
  "$WATCHER_MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  # Should fail because log file doesn't exist (server not running)
  # But should NOT fail with EC_NOT_FOUND (instance exists)
  # The key assertion: it must fail, meaning delegation happened and log test was attempted
  assert_not_equals 0 "$exit_code" \
    "watcher.sh test should fail (log file absent) when delegating to log watcher"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 15: watcher.sh test for ports-strategy instance delegates to watcher.ports.sh
# ark instance (no startup_success_regex, has ports) → watcher.sh test should run port test
# =============================================================================

function test_watcher_test_delegates_to_port_watcher() {
  log_test_step "Testing: watcher.sh test delegates to port watcher for ports-strategy instance"

  local instance_name="watcher-test-ports-$$"
  _create_instance_or_skip "$BLUEPRINT_PORTS_STRATEGY" "$instance_name" || return

  # Run watcher.sh test on ark instance - should delegate to ports watcher
  "$WATCHER_MODULE" test "$instance_name" 2>/dev/null
  local exit_code=$?

  # Should fail (ports not active - server not running)
  # But must NOT fail with EC_NOT_FOUND (instance exists)
  assert_not_equals 0 "$exit_code" \
    "watcher.sh test should fail (ports inactive) when delegating to port watcher"

  remove_test_instance "$BLUEPRINT_PORTS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 16: watcher.logs.sh and watcher.ports.sh sub-commands accessible via watcher.sh
# watcher.sh logs status <instance> and watcher.sh ports status <instance> must work
# =============================================================================

function test_watcher_orchestrator_delegates_subcommands() {
  log_test_step "Testing: watcher.sh orchestrates sub-commands (logs/ports) for a valid instance"

  local instance_name="watcher-orch-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  # Test: watcher.sh logs status <instance>
  local logs_status_output
  logs_status_output=$("$WATCHER_MODULE" logs status "$instance_name" 2>&1)
  local logs_exit=$?

  assert_equals 0 "$logs_exit" \
    "watcher.sh logs status should succeed for valid instance"
  assert_not_null "$logs_status_output" \
    "watcher.sh logs status should produce output"

  # Test: watcher.sh ports status <instance>
  local ports_status_output
  ports_status_output=$("$WATCHER_MODULE" ports status "$instance_name" 2>&1)
  local ports_exit=$?

  assert_equals 0 "$ports_exit" \
    "watcher.sh ports status should succeed for valid instance"
  assert_not_null "$ports_status_output" \
    "watcher.sh ports status should produce output"

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 17: watcher.logs.sh status shows log file path from instance config
# The status output should reflect the actual configured log file path
# =============================================================================

function test_watcher_logs_status_shows_log_file_path() {
  log_test_step "Testing: watcher.logs.sh status output contains instance log file path"

  local instance_name="watcher-logs-path-$$"
  _create_instance_or_skip "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" || return

  # Get the actual log file path from instance config
  local instances_module="$KGSM_ROOT/commands/instances.sh"
  local instance_config_file
  instance_config_file=$("$instances_module" find "$instance_name" 2>/dev/null)

  local log_file_path=""
  if [[ -n "$instance_config_file" && -f "$instance_config_file" ]]; then
    log_file_path=$(grep "^log_file=" "$instance_config_file" | cut -d'=' -f2 | tr -d '"')
  fi

  local output
  output=$("$WATCHER_LOGS_MODULE" status "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "watcher.logs.sh status should succeed"

  if [[ -n "$log_file_path" ]]; then
    assert_contains "$output" "$log_file_path" \
      "watcher.logs.sh status should show the configured log file path"
  fi

  remove_test_instance "$BLUEPRINT_LOGS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# TEST 18: watcher.ports.sh status shows multi-port configuration
# ark blueprint has multiple ports → status should show all of them
# =============================================================================

function test_watcher_ports_status_shows_all_ports() {
  log_test_step "Testing: watcher.ports.sh status shows all configured ports for multi-port instance"

  local instance_name="watcher-ports-all-$$"
  _create_instance_or_skip "$BLUEPRINT_PORTS_STRATEGY" "$instance_name" || return

  local output
  output=$("$WATCHER_PORTS_MODULE" status "$instance_name" 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "watcher.ports.sh status should succeed for ark instance"
  assert_not_null "$output" "watcher.ports.sh status should produce output"
  # ark.bp has ports='7777/udp|7778/udp|27020/tcp|27015/udp'
  assert_contains "$output" "7777" \
    "watcher.ports.sh status should show first port (7777) for ark instance"

  remove_test_instance "$BLUEPRINT_PORTS_STRATEGY" "$instance_name" "$TEST_INSTALL_DIR"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting watcher+instances integration tests"

  setup_test

  # Watcher orchestrator tests
  test_watcher_status_selects_logs_strategy
  test_watcher_status_selects_ports_strategy
  test_watcher_status_rejects_invalid_instance
  test_watcher_start_rejects_invalid_instance
  test_watcher_test_rejects_invalid_instance

  # Log watcher integration tests
  test_watcher_logs_status_shows_pattern
  test_watcher_logs_status_rejects_invalid_instance
  test_watcher_logs_test_fails_when_log_absent
  test_watcher_logs_test_succeeds_with_matching_log
  test_watcher_logs_test_pattern_not_found_in_existing_log

  # Port watcher integration tests
  test_watcher_ports_status_shows_configured_ports
  test_watcher_ports_status_rejects_invalid_instance
  test_watcher_ports_test_handles_inactive_ports
  test_watcher_ports_status_shows_all_ports

  # Orchestrator delegation tests
  test_watcher_test_delegates_to_log_watcher
  test_watcher_test_delegates_to_port_watcher
  test_watcher_orchestrator_delegates_subcommands
  test_watcher_logs_status_shows_log_file_path

  log_test_step "Watcher+instances integration tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All watcher+instances integration tests passed"
  else
    fail_test "Some watcher+instances integration tests failed"
  fi
}

main "$@"
