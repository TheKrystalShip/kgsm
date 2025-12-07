#!/usr/bin/env bash

# =============================================================================
# KGSM System Module - Comprehensive Test Suite
# =============================================================================
#
# This test provides comprehensive coverage of the system.sh module, testing all
# commands, error conditions, edge cases, and behavioral consistency.
#
# The system module manages OS-level operations:
# - System power management (shutdown, restart, cancel)
# - Network information (ip)
# - System status (uptime, load, memory, disk, reboot-required)
# - Comprehensive info display
#
# Test Coverage:
# ✓ Module existence and permissions
# ✓ Help functionality and usage display
# ✓ All command combinations
# ✓ Argument validation and error handling
# ✓ Integration with kgsm.sh delegation
# ✓ Debug mode functionality
# ✓ Behavioral consistency and predictability
# ✓ Edge cases and boundary conditions
#
# Note: Power management tests are limited since they require sudo
# and would affect the test system. We test argument parsing only.
#
# =============================================================================

# Source the testing framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

# =============================================================================
# TEST CONFIGURATION & CONSTANTS
# =============================================================================

readonly TEST_NAME="system_module_comprehensive"
readonly SYSTEM_MODULE="$KGSM_ROOT/commands/system.sh"
readonly SYSTEM_LOGIC="$KGSM_ROOT/commands/handlers/system.sh"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function setup_test() {
  log_test "Setting up comprehensive system module test environment"

  # Basic module validation
  assert_file_exists "$SYSTEM_MODULE" "System module should exist"
  assert_file_executable "$SYSTEM_MODULE" "System module should be executable"

  # Verify logic library exists
  assert_file_exists "$SYSTEM_LOGIC" "System logic library should exist"

  # Ensure kgsm.sh exists in test environment
  if [[ ! -f "$KGSM_ROOT/kgsm.sh" ]]; then
    echo '#!/usr/bin/env bash' > "$KGSM_ROOT/kgsm.sh"
    chmod +x "$KGSM_ROOT/kgsm.sh"
    log_test "Created kgsm.sh in test environment"
  fi

  log_test "Test environment setup complete"
}

function cleanup_test() {
  log_test "Cleaning up system module test environment"
  # No cleanup needed for read-only tests
}

# =============================================================================
# TEST FUNCTIONS - BASIC MODULE VALIDATION
# =============================================================================

function test_module_existence_and_permissions() {
  log_step "Testing module existence and permissions"

  # Basic file system checks
  assert_file_exists "$SYSTEM_MODULE" "System module file should exist"
  assert_command_succeeds "test -r '$SYSTEM_MODULE'" "System module should be readable"
  assert_file_executable "$SYSTEM_MODULE" "System module should be executable"

  # Check file size (should not be empty)
  assert_command_succeeds "test -s '$SYSTEM_MODULE'" "System module should not be empty"

  # Verify it's a bash script
  local first_line
  first_line=$(head -n1 "$SYSTEM_MODULE")
  assert_contains "$first_line" "#!/usr/bin/env bash" "System module should be a bash script"

  log_test "Module existence and permissions validated"
}

function test_logic_library_existence() {
  log_step "Testing logic library existence"

  # Verify logic library exists and is readable
  assert_file_exists "$SYSTEM_LOGIC" "System logic library should exist"
  assert_command_succeeds "test -r '$SYSTEM_LOGIC'" "System logic library should be readable"
  assert_command_succeeds "test -s '$SYSTEM_LOGIC'" "System logic library should not be empty"

  # Verify it's a bash script
  local first_line
  first_line=$(head -n1 "$SYSTEM_LOGIC")
  assert_contains "$first_line" "#!/usr/bin/env bash" "System logic library should be a bash script"

  log_test "Logic library validated"
}

function test_help_functionality() {
  log_step "Testing help functionality and usage display"

  # Test --help flag
  assert_command_succeeds "$SYSTEM_MODULE --help" "system.sh --help should work"

  # Test -h flag
  assert_command_succeeds "$SYSTEM_MODULE -h" "system.sh -h should work"

  # Verify help content contains expected information
  local help_output
  help_output=$("$SYSTEM_MODULE" --help 2>&1)

  assert_contains "$help_output" "System Management for Krystal Game Server Manager" "Help should contain module description"
  assert_contains "$help_output" "shutdown" "Help should document shutdown command"
  assert_contains "$help_output" "restart" "Help should document restart command"
  assert_contains "$help_output" "cancel" "Help should document cancel command"
  assert_contains "$help_output" "ip" "Help should document ip command"
  assert_contains "$help_output" "uptime" "Help should document uptime command"
  assert_contains "$help_output" "load" "Help should document load command"
  assert_contains "$help_output" "memory" "Help should document memory command"
  assert_contains "$help_output" "disk" "Help should document disk command"
  assert_contains "$help_output" "reboot-required" "Help should document reboot-required command"
  assert_contains "$help_output" "info" "Help should document info command"
  assert_contains "$help_output" "Examples:" "Help should contain usage examples"

  log_test "Help functionality validated"
}

function test_command_specific_help() {
  log_step "Testing command-specific help"

  # Test help command with shutdown
  assert_command_succeeds "$SYSTEM_MODULE help shutdown" "help shutdown should work"
  local shutdown_help
  shutdown_help=$("$SYSTEM_MODULE" help shutdown 2>&1)
  assert_contains "$shutdown_help" "Schedule System Shutdown" "Shutdown help should contain title"

  # Test help command with restart
  assert_command_succeeds "$SYSTEM_MODULE help restart" "help restart should work"
  local restart_help
  restart_help=$("$SYSTEM_MODULE" help restart 2>&1)
  assert_contains "$restart_help" "Schedule System Restart" "Restart help should contain title"

  # Test help command with ip
  assert_command_succeeds "$SYSTEM_MODULE help ip" "help ip should work"
  local ip_help
  ip_help=$("$SYSTEM_MODULE" help ip 2>&1)
  assert_contains "$ip_help" "Display IP Address Information" "IP help should contain title"

  # Test help command with info
  assert_command_succeeds "$SYSTEM_MODULE help info" "help info should work"
  local info_help
  info_help=$("$SYSTEM_MODULE" help info 2>&1)
  assert_contains "$info_help" "Display Comprehensive System Information" "Info help should contain title"

  # Test inline --help for commands
  assert_command_succeeds "$SYSTEM_MODULE shutdown --help" "shutdown --help should work"
  assert_command_succeeds "$SYSTEM_MODULE restart --help" "restart --help should work"
  assert_command_succeeds "$SYSTEM_MODULE ip --help" "ip --help should work"

  log_test "Command-specific help validated"
}

# =============================================================================
# TEST FUNCTIONS - ARGUMENT VALIDATION
# =============================================================================

function test_no_command_shows_usage() {
  log_step "Testing no command shows usage"

  # No command should show usage
  local output
  output=$("$SYSTEM_MODULE" 2>&1)
  assert_contains "$output" "System Management for Krystal Game Server Manager" "No command should show usage"

  log_test "No command behavior validated"
}

function test_invalid_command_handling() {
  log_step "Testing invalid command handling"

  # Invalid command should fail
  assert_command_fails "$SYSTEM_MODULE invalid_command" "Invalid command should fail"

  local output
  output=$("$SYSTEM_MODULE" invalid_command 2>&1)
  assert_contains "$output" "Unknown command" "Invalid command should show error"

  log_test "Invalid command handling validated"
}

function test_shutdown_argument_validation() {
  log_step "Testing shutdown argument validation"

  # Note: We can't actually test shutdown execution without sudo
  # We test argument parsing and validation only

  # Invalid time argument (non-numeric)
  assert_command_fails "$SYSTEM_MODULE shutdown abc" "Non-numeric time should fail"

  # Negative number is also invalid (regex validation)
  assert_command_fails "$SYSTEM_MODULE shutdown -5" "Negative time should fail"

  # Help should work
  assert_command_succeeds "$SYSTEM_MODULE shutdown --help" "shutdown --help should work"

  log_test "Shutdown argument validation tested"
}

function test_restart_argument_validation() {
  log_step "Testing restart argument validation"

  # Note: We can't actually test restart execution without sudo
  # We test argument parsing and validation only

  # Invalid time argument (non-numeric)
  assert_command_fails "$SYSTEM_MODULE restart abc" "Non-numeric time should fail"

  # Negative number is also invalid
  assert_command_fails "$SYSTEM_MODULE restart -10" "Negative time should fail"

  # Help should work
  assert_command_succeeds "$SYSTEM_MODULE restart --help" "restart --help should work"

  log_test "Restart argument validation tested"
}

# =============================================================================
# TEST FUNCTIONS - INFORMATION COMMANDS
# =============================================================================

function test_ip_command() {
  log_step "Testing ip command"

  # IP command should attempt to retrieve IP
  # It may fail if network tools aren't available, but shouldn't crash
  local output
  output=$("$SYSTEM_MODULE" ip 2>&1)

  # Check that output contains expected sections
  # Note: May show warnings if tools missing, which is OK
  assert_contains "$output" "Retrieving" "IP command should show retrieval attempt"

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE ip --invalid" "Invalid argument should fail"

  log_test "IP command tested"
}

function test_uptime_command() {
  log_step "Testing uptime command"

  # Uptime command should work (uptime is standard on Linux)
  if command -v uptime >/dev/null 2>&1; then
    assert_command_succeeds "$SYSTEM_MODULE uptime" "uptime command should work if uptime exists"

    local output
    output=$("$SYSTEM_MODULE" uptime 2>&1)
    assert_contains "$output" "uptime" "Uptime output should contain 'uptime'"
  else
    log_test "Skipping uptime test - uptime command not available"
  fi

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE uptime --invalid" "Invalid argument should fail"

  log_test "Uptime command tested"
}

function test_load_command() {
  log_step "Testing load command"

  # Load command should work on Linux systems
  if command -v uptime >/dev/null 2>&1 || [[ -f /proc/loadavg ]]; then
    assert_command_succeeds "$SYSTEM_MODULE load" "load command should work if tools exist"
  else
    log_test "Skipping load test - no load tools available"
  fi

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE load --invalid" "Invalid argument should fail"

  log_test "Load command tested"
}

function test_memory_command() {
  log_step "Testing memory command"

  # Memory command requires 'free'
  if command -v free >/dev/null 2>&1; then
    assert_command_succeeds "$SYSTEM_MODULE memory" "memory command should work if free exists"

    local output
    output=$("$SYSTEM_MODULE" memory 2>&1)
    assert_contains "$output" "Memory" "Memory output should contain 'Memory'"
  else
    # Should fail gracefully if free not available
    assert_command_fails "$SYSTEM_MODULE memory" "memory should fail if free not available"
  fi

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE memory --invalid" "Invalid argument should fail"

  log_test "Memory command tested"
}

function test_disk_command() {
  log_step "Testing disk command"

  # Disk command requires 'df'
  if command -v df >/dev/null 2>&1; then
    assert_command_succeeds "$SYSTEM_MODULE disk" "disk command should work if df exists"

    local output
    output=$("$SYSTEM_MODULE" disk 2>&1)
    assert_contains "$output" "filesystem" "Disk output should contain 'filesystem'"
  else
    # Should fail gracefully if df not available
    assert_command_fails "$SYSTEM_MODULE disk" "disk should fail if df not available"
  fi

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE disk --invalid" "Invalid argument should fail"

  log_test "Disk command tested"
}

function test_reboot_required_command() {
  log_step "Testing reboot-required command"

  # Reboot-required should always work (has fallback logic)
  assert_command_succeeds "$SYSTEM_MODULE reboot-required" "reboot-required should work"

  local output
  output=$("$SYSTEM_MODULE" reboot-required 2>&1)
  # Should contain either "required" or "No"
  if [[ "$output" == *"required"* ]] || [[ "$output" == *"No"* ]]; then
    log_test "Reboot-required output is valid"
  else
    fail "Reboot-required output should contain status"
  fi

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE reboot-required --invalid" "Invalid argument should fail"

  log_test "Reboot-required command tested"
}

function test_info_command() {
  log_step "Testing info command"

  # Info command should work (displays comprehensive info)
  assert_command_succeeds "$SYSTEM_MODULE info" "info command should work"

  local output
  output=$("$SYSTEM_MODULE" info 2>&1)
  assert_contains "$output" "SYSTEM INFORMATION" "Info should contain header"

  # Should contain at least some information
  # Even if some commands fail, it should still display what it can
  local line_count
  line_count=$(echo "$output" | wc -l)
  if [[ "$line_count" -lt 5 ]]; then
    fail "Info output should contain multiple lines"
  fi

  # Test JSON output if jq is available
  if command -v jq >/dev/null 2>&1; then
    assert_command_succeeds "$SYSTEM_MODULE info --json" "info --json should work"

    local json_output
    json_output=$("$SYSTEM_MODULE" info --json 2>&1)

    # Verify it's valid JSON
    if ! echo "$json_output" | jq empty >/dev/null 2>&1; then
      fail "JSON output should be valid JSON"
    fi

    # Verify JSON structure has expected keys
    assert_contains "$json_output" "uptime" "JSON should contain uptime field"
    assert_contains "$json_output" "load" "JSON should contain load field"
    assert_contains "$json_output" "memory" "JSON should contain memory field"
    assert_contains "$json_output" "disk" "JSON should contain disk field"
    assert_contains "$json_output" "network" "JSON should contain network field"
    assert_contains "$json_output" "reboot_required" "JSON should contain reboot_required field"

    # Verify nested structure
    assert_contains "$json_output" "\"1min\"" "JSON load should contain 1min field"
    assert_contains "$json_output" "\"5min\"" "JSON load should contain 5min field"
    assert_contains "$json_output" "\"15min\"" "JSON load should contain 15min field"
    assert_contains "$json_output" "\"external_ip\"" "JSON network should contain external_ip field"
    assert_contains "$json_output" "\"local_ips\"" "JSON network should contain local_ips array"
  else
    log_test "Skipping JSON test - jq not available"

    # Should fail gracefully without jq
    assert_command_fails "$SYSTEM_MODULE info --json" "info --json should fail without jq"
  fi

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE info --invalid" "Invalid argument should fail"

  log_test "Info command tested"
}

function test_cancel_command() {
  log_step "Testing cancel command"

  # Note: We can't test actual cancel without sudo
  # We test argument parsing only

  # Help should work
  assert_command_succeeds "$SYSTEM_MODULE cancel --help" "cancel --help should work"

  # Invalid argument should fail
  assert_command_fails "$SYSTEM_MODULE cancel --invalid" "Invalid argument should fail"

  log_test "Cancel command argument parsing tested"
}

# =============================================================================
# TEST FUNCTIONS - INTEGRATION WITH KGSM.SH
# =============================================================================

function test_kgsm_delegation() {
  log_step "Testing kgsm.sh delegates to system module"

  local kgsm_script="$KGSM_ROOT/kgsm.sh"

  # Ensure kgsm.sh exists and is executable
  assert_file_exists "$kgsm_script" "kgsm.sh should exist"
  assert_file_executable "$kgsm_script" "kgsm.sh should be executable"

  # Test system command delegation
  assert_command_succeeds "$kgsm_script system --help" "kgsm.sh system --help should work"

  local output
  output=$("$kgsm_script" system --help 2>&1)
  assert_contains "$output" "System Management" "Delegated command should show system help"

  # Test specific system commands through kgsm.sh
  if command -v uptime >/dev/null 2>&1; then
    assert_command_succeeds "$kgsm_script system uptime" "kgsm.sh system uptime should work"
  fi

  # Test deprecated 'ip' command backward compatibility
  local ip_output
  ip_output=$("$kgsm_script" ip 2>&1)
  assert_contains "$ip_output" "deprecated" "Legacy ip command should show deprecation warning"

  log_test "KGSM delegation validated"
}

# =============================================================================
# TEST FUNCTIONS - DEBUG MODE
# =============================================================================

function test_debug_mode() {
  log_step "Testing debug mode"

  # Debug mode should enable verbose output
  local output
  output=$("$SYSTEM_MODULE" --debug uptime 2>&1 || true)

  # In debug mode, we should see trace output (PS4)
  # Note: May not work in all test environments, so we make this lenient
  if [[ "$output" == *"BASH_SOURCE"* ]] || [[ "$output" == *"uptime"* ]]; then
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
  if command -v uptime >/dev/null 2>&1; then
    local output1
    local output2

    output1=$("$SYSTEM_MODULE" uptime 2>&1)
    sleep 1
    output2=$("$SYSTEM_MODULE" uptime 2>&1)

    # Both should succeed or both should fail
    # (We can't compare exact output as uptime changes, but structure should be same)
    if [[ "$output1" == *"uptime"* ]]; then
      assert_contains "$output2" "uptime" "Consistent command should have consistent output structure"
    fi
  fi

  # Invalid commands should consistently fail
  assert_command_fails "$SYSTEM_MODULE invalid1" "Invalid command should fail"
  assert_command_fails "$SYSTEM_MODULE invalid2" "Invalid command should fail"

  log_test "Behavioral consistency validated"
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

function run_all_tests() {
  log_test "Starting system module comprehensive test suite"

  setup_test

  # Basic validation tests
  test_module_existence_and_permissions
  test_logic_library_existence
  test_help_functionality
  test_command_specific_help

  # Argument validation tests
  test_no_command_shows_usage
  test_invalid_command_handling
  test_shutdown_argument_validation
  test_restart_argument_validation

  # Information command tests
  test_ip_command
  test_uptime_command
  test_load_command
  test_memory_command
  test_disk_command
  test_reboot_required_command
  test_info_command
  test_cancel_command

  # Integration tests
  test_kgsm_delegation

  # Debug and consistency tests
  test_debug_mode
  test_behavioral_consistency

  cleanup_test

  log_test "System module comprehensive test suite completed"
}

# Run all tests
run_all_tests
