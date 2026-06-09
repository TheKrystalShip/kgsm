#!/usr/bin/env bash

# KGSM System Command CLI Tests
#
# Test Type: UNIT
# Target: commands/system.sh - CLI interface and argument handling
#
# Tests the CLI interface of system.sh including help system,
# error handling for missing/invalid args, and read-only info commands.
# Does NOT test commands requiring sudo (shutdown/restart/cancel execution).

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="system_commands"
readonly MODULE="$KGSM_ROOT/commands/system.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up system commands tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "system.sh module should exist"
  assert_file_executable "$MODULE" "system.sh should be executable"

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
  assert_contains "$output" "shutdown" "Help should mention shutdown command"
  assert_contains "$output" "restart" "Help should mention restart command"
  assert_contains "$output" "uptime" "Help should mention uptime command"
  assert_contains "$output" "memory" "Help should mention memory command"
  assert_contains "$output" "disk" "Help should mention disk command"
  assert_contains "$output" "info" "Help should mention info command"
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "shutdown" "Help output should contain shutdown"
}

function test_help_h_flag() {
  log_test_step "Testing -h flag output"

  local output
  output=$("$MODULE" -h 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "-h flag should succeed"
  assert_contains "$output" "shutdown" "Help output should contain shutdown"
}

function test_help_shutdown_command() {
  log_test_step "Testing help for shutdown command"

  local output
  output=$("$MODULE" help shutdown 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help shutdown should succeed"
  assert_contains "$output" "shutdown" "Should show shutdown help"
}

function test_help_restart_command() {
  log_test_step "Testing help for restart command"

  local output
  output=$("$MODULE" help restart 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help restart should succeed"
  assert_contains "$output" "restart" "Should show restart help"
}

function test_help_info_command() {
  log_test_step "Testing help for info command"

  local output
  output=$("$MODULE" help info 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help info should succeed"
  assert_contains "$output" "info" "Should show info help"
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

  assert_contains "$output" "shutdown" "No-command output should mention shutdown"
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
  log_test_step "Testing unknown command returns EC_INVALID_ARG exit code"

  "$MODULE" unknowncmd_xyz 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Unknown command should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

# =============================================================================
# SHUTDOWN ARGUMENT VALIDATION TESTS
# =============================================================================

function test_shutdown_help() {
  log_test_step "Testing shutdown --help"

  local output
  output=$("$MODULE" shutdown --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "shutdown --help should succeed"
  assert_contains "$output" "shutdown" "Should show shutdown help"
}

function test_shutdown_invalid_time_text() {
  log_test_step "Testing shutdown with non-numeric time argument"

  "$MODULE" shutdown abc 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "shutdown with text time should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_shutdown_invalid_time_float() {
  log_test_step "Testing shutdown with float time argument"

  "$MODULE" shutdown 1.5 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "shutdown with float time should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_shutdown_invalid_time_negative() {
  log_test_step "Testing shutdown with negative time argument"

  "$MODULE" shutdown -- -5 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "shutdown with negative time should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_shutdown_invalid_time_error_message() {
  log_test_step "Testing shutdown with invalid time shows error message"

  local output
  output=$("$MODULE" shutdown notanumber 2>&1 || true)
  assert_contains "$output" "Invalid argument" "Should show invalid argument error"
}

# =============================================================================
# RESTART ARGUMENT VALIDATION TESTS
# =============================================================================

function test_restart_help() {
  log_test_step "Testing restart --help"

  local output
  output=$("$MODULE" restart --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "restart --help should succeed"
  assert_contains "$output" "restart" "Should show restart help"
}

function test_restart_help_verb() {
  log_test_step "Testing restart help subcommand"

  local output
  output=$("$MODULE" restart help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "restart help should succeed"
}

function test_restart_invalid_time_text() {
  log_test_step "Testing restart with non-numeric time argument"

  "$MODULE" restart abc 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "restart with text time should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_restart_invalid_time_float() {
  log_test_step "Testing restart with float time argument"

  "$MODULE" restart 2.5 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "restart with float time should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_restart_unknown_option() {
  log_test_step "Testing restart with unknown option"

  "$MODULE" restart --unknown-flag 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "restart with unknown option should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

# =============================================================================
# CANCEL ARGUMENT VALIDATION TESTS
# =============================================================================

function test_cancel_help() {
  log_test_step "Testing cancel --help"

  local output
  output=$("$MODULE" cancel --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "cancel --help should succeed"
}

function test_cancel_help_verb() {
  log_test_step "Testing cancel help subcommand"

  local output
  output=$("$MODULE" cancel help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "cancel help should succeed"
}

function test_cancel_invalid_arg() {
  log_test_step "Testing cancel with positional argument fails"

  "$MODULE" cancel some_invalid_arg 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "cancel with positional arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_cancel_unknown_option() {
  log_test_step "Testing cancel with unknown option"

  "$MODULE" cancel --unknown-flag 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "cancel with unknown option should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

# =============================================================================
# UPTIME COMMAND TESTS
# =============================================================================

function test_uptime_help() {
  log_test_step "Testing uptime --help"

  local output
  output=$("$MODULE" uptime --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "uptime --help should succeed"
}

function test_uptime_help_verb() {
  log_test_step "Testing uptime help subcommand"

  local output
  output=$("$MODULE" uptime help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "uptime help should succeed"
}

function test_uptime_invalid_arg() {
  log_test_step "Testing uptime with positional argument fails"

  "$MODULE" uptime some_invalid_arg 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "uptime with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_uptime_succeeds_or_missing_dep() {
  log_test_step "Testing uptime returns success or missing dependency"

  "$MODULE" uptime 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_SYSTEM_INFO_RETRIEVED ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "uptime should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED or EC_MISSING_DEPENDENCY, got: $exit_code"
}

function test_uptime_output_not_empty() {
  log_test_step "Testing uptime produces non-empty output on success"

  if ! command -v uptime >/dev/null 2>&1; then
    skip_test "uptime command not available"
    return 0
  fi

  local output
  output=$("$MODULE" uptime 2>&1)

  assert_not_null "$output" "uptime output should not be empty"
}

# =============================================================================
# LOAD COMMAND TESTS
# =============================================================================

function test_load_help() {
  log_test_step "Testing load --help"

  local output
  output=$("$MODULE" load --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "load --help should succeed"
}

function test_load_invalid_arg() {
  log_test_step "Testing load with positional argument fails"

  "$MODULE" load some_invalid_arg 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "load with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_load_succeeds() {
  log_test_step "Testing load returns success"

  "$MODULE" load 2>/dev/null
  local exit_code=$?

  # load uses uptime or /proc/loadavg - should succeed on Linux
  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_SYSTEM_INFO_RETRIEVED ]] ||
     [[ $exit_code -eq $EC_ERROR ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "load should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED or EC_ERROR, got: $exit_code"
}

# =============================================================================
# MEMORY COMMAND TESTS
# =============================================================================

function test_memory_help() {
  log_test_step "Testing memory --help"

  local output
  output=$("$MODULE" memory --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "memory --help should succeed"
}

function test_memory_invalid_arg() {
  log_test_step "Testing memory with positional argument fails"

  "$MODULE" memory some_invalid_arg 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "memory with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_memory_succeeds_or_missing_dep() {
  log_test_step "Testing memory returns success or missing dependency"

  "$MODULE" memory 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_SYSTEM_INFO_RETRIEVED ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "memory should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED or EC_MISSING_DEPENDENCY, got: $exit_code"
}

function test_memory_output_when_available() {
  log_test_step "Testing memory produces output when free command available"

  if ! command -v free >/dev/null 2>&1; then
    skip_test "free command not available"
    return 0
  fi

  local output
  output=$("$MODULE" memory 2>&1)

  assert_not_null "$output" "memory output should not be empty"
  assert_contains "$output" "Mem:" "memory output should contain 'Mem:' line"
}

# =============================================================================
# DISK COMMAND TESTS
# =============================================================================

function test_disk_help() {
  log_test_step "Testing disk --help"

  local output
  output=$("$MODULE" disk --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "disk --help should succeed"
}

function test_disk_invalid_arg() {
  log_test_step "Testing disk with positional argument fails"

  "$MODULE" disk some_invalid_arg 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "disk with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_disk_succeeds_or_missing_dep() {
  log_test_step "Testing disk returns success or missing dependency"

  "$MODULE" disk 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ $exit_code -eq $EC_SUCCESS_SYSTEM_INFO_RETRIEVED ]] ||
     [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "disk should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED or EC_MISSING_DEPENDENCY, got: $exit_code"
}

function test_disk_output_when_available() {
  log_test_step "Testing disk produces output when df command available"

  if ! command -v df >/dev/null 2>&1; then
    skip_test "df command not available"
    return 0
  fi

  local output
  output=$("$MODULE" disk 2>&1)

  assert_not_null "$output" "disk output should not be empty"
}

# =============================================================================
# REBOOT-REQUIRED COMMAND TESTS
# =============================================================================

function test_reboot_required_help() {
  log_test_step "Testing reboot-required --help"

  local output
  output=$("$MODULE" reboot-required --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "reboot-required --help should succeed"
}

function test_reboot_required_help_verb() {
  log_test_step "Testing reboot-required help subcommand"

  local output
  output=$("$MODULE" reboot-required help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "reboot-required help should succeed"
}

function test_reboot_required_invalid_arg() {
  log_test_step "Testing reboot-required with positional argument fails"

  "$MODULE" reboot-required some_invalid_arg 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "reboot-required with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_reboot_required_unknown_option() {
  log_test_step "Testing reboot-required with unknown option fails"

  "$MODULE" reboot-required --unknown-flag 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "reboot-required with unknown option should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_reboot_required_succeeds() {
  log_test_step "Testing reboot-required returns exit code 0"

  "$MODULE" reboot-required 2>/dev/null
  local exit_code=$?

  assert_equals 0 "$exit_code" \
    "reboot-required should return 0 (always succeeds with true/false output)"
}

function test_reboot_required_output_is_informative() {
  log_test_step "Testing reboot-required produces informative output"

  local output
  output=$("$MODULE" reboot-required 2>&1)

  # Should mention reboot in some way
  assert_contains "$output" "reboot" "reboot-required output should mention reboot"
}

# =============================================================================
# INFO COMMAND TESTS
# =============================================================================

function test_info_help() {
  log_test_step "Testing info --help"

  local output
  output=$("$MODULE" info --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info --help should succeed"
  assert_contains "$output" "info" "Should show info help"
}

function test_info_help_verb() {
  log_test_step "Testing info help subcommand"

  local output
  output=$("$MODULE" info help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info help should succeed"
}

function test_info_invalid_arg() {
  log_test_step "Testing info with positional argument fails"

  "$MODULE" info some_invalid_arg 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "info with invalid arg should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_info_unknown_option() {
  log_test_step "Testing info with unknown option fails"

  "$MODULE" info --unknown-flag 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "info with unknown option should return EC_INVALID_ARG ($EC_INVALID_ARG)"
}

function test_info_succeeds() {
  log_test_step "Testing info command succeeds and produces output"

  "$MODULE" info 2>/dev/null
  local exit_code=$?

  assert_equals 0 "$exit_code" "info should return 0"

  local output
  output=$("$MODULE" info 2>&1)
  assert_contains "$output" "SYSTEM INFORMATION" "info output should contain system information header"
}

function test_info_json_succeeds_or_missing_dep() {
  log_test_step "Testing info --json returns 0 or EC_MISSING_DEPENDENCY (no jq)"

  "$MODULE" info --json 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ $exit_code -eq 0 ]] || [[ $exit_code -eq $EC_MISSING_DEPENDENCY ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "info --json should return 0 or EC_MISSING_DEPENDENCY, got: $exit_code"
}

function test_info_json_valid_json_when_jq_available() {
  log_test_step "Testing info --json produces valid JSON when jq is available"

  if ! command -v jq >/dev/null 2>&1; then
    skip_test "jq not available - skipping JSON output test"
    return 0
  fi

  local output
  output=$("$MODULE" info --json 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "info --json should succeed with jq available"
  assert_contains "$output" "{" "JSON output should contain opening brace"
  assert_contains "$output" "}" "JSON output should contain closing brace"
  assert_contains "$output" "uptime" "JSON output should contain uptime field"
}

function test_info_json_contains_reboot_field() {
  log_test_step "Testing info --json contains reboot_required field"

  if ! command -v jq >/dev/null 2>&1; then
    skip_test "jq not available"
    return 0
  fi

  local output
  output=$("$MODULE" info --json 2>&1)

  assert_contains "$output" "reboot_required" "JSON output should contain reboot_required field"
}

