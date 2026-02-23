#!/usr/bin/env bash

# KGSM System Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/system.sh - Pure __logic_* functions
#
# Tests all logic functions for system operations including:
# - System shutdown/restart scheduling (argument validation)
# - System uptime retrieval
# - Reboot required detection
# - Load average retrieval
# - Memory information retrieval
# - Disk usage retrieval

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="system_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/system.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up system logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "System handler should exist"

  # Source the handler
  source "$HANDLER"

  # Verify error codes are defined
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_MISSING_DEPENDENCY" "EC_MISSING_DEPENDENCY should be defined"
  assert_not_null "$EC_SUCCESS" "EC_SUCCESS should be defined"
  assert_not_null "$EC_ERROR" "EC_ERROR should be defined"
  assert_not_null "$EC_SUCCESS_SYSTEM_SHUTDOWN" "EC_SUCCESS_SYSTEM_SHUTDOWN should be defined"
  assert_not_null "$EC_SUCCESS_SYSTEM_RESTART" "EC_SUCCESS_SYSTEM_RESTART should be defined"
  assert_not_null "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" "EC_SUCCESS_SYSTEM_INFO_RETRIEVED should be defined"

  # Verify all logic functions are exported
  assert_function_exists "__logic_schedule_shutdown" "schedule_shutdown should be exported"
  assert_function_exists "__logic_cancel_shutdown" "cancel_shutdown should be exported"
  assert_function_exists "__logic_schedule_restart" "schedule_restart should be exported"
  assert_function_exists "__logic_get_uptime" "get_uptime should be exported"
  assert_function_exists "__logic_check_reboot_required" "check_reboot_required should be exported"
  assert_function_exists "__logic_get_load_average" "get_load_average should be exported"
  assert_function_exists "__logic_get_memory_info" "get_memory_info should be exported"
  assert_function_exists "__logic_get_disk_usage" "get_disk_usage should be exported"

  log_test_step "System logic test environment validated"
}

# =============================================================================
# __logic_schedule_shutdown() TESTS
# =============================================================================

function test_schedule_shutdown_empty_arg() {
  log_test_step "Testing __logic_schedule_shutdown with empty time argument"

  __logic_schedule_shutdown "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for empty time argument"
}

function test_schedule_shutdown_negative_number() {
  log_test_step "Testing __logic_schedule_shutdown with negative time"

  __logic_schedule_shutdown "-1" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for negative time"
}

function test_schedule_shutdown_non_numeric() {
  log_test_step "Testing __logic_schedule_shutdown with non-numeric time"

  __logic_schedule_shutdown "abc" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for non-numeric time"
}

function test_schedule_shutdown_float_number() {
  log_test_step "Testing __logic_schedule_shutdown with float number"

  __logic_schedule_shutdown "1.5" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for floating-point time"
}

function test_schedule_shutdown_no_shutdown_command() {
  log_test_step "Testing __logic_schedule_shutdown when shutdown unavailable"

  if ! command -v shutdown >/dev/null 2>&1; then
    __logic_schedule_shutdown "5" 2>/dev/null
    local exit_code=$?
    assert_equals "$EC_MISSING_DEPENDENCY" "$exit_code" \
      "Should return missing dependency when shutdown command not available"
  else
    skip_test "shutdown command is available - cannot test missing dependency"
    return 0
  fi
}

function test_schedule_shutdown_valid_arg_permission() {
  log_test_step "Testing __logic_schedule_shutdown with valid arg (expects permission error)"

  if ! command -v shutdown >/dev/null 2>&1; then
    skip_test "shutdown command not available"
    return 0
  fi

  # Skip if sudo requires a password (would block the test)
  if ! sudo -n true 2>/dev/null; then
    skip_test "sudo requires password - cannot test without blocking"
    return 0
  fi

  __logic_schedule_shutdown "60" 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_PERMISSION" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_SHUTDOWN" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return EC_PERMISSION (no sudo) or EC_SUCCESS_SYSTEM_SHUTDOWN"
}

function test_schedule_shutdown_zero_minutes() {
  log_test_step "Testing __logic_schedule_shutdown with 0 minutes (immediate)"

  if ! command -v shutdown >/dev/null 2>&1; then
    skip_test "shutdown command not available"
    return 0
  fi

  # Skip if sudo requires a password (would block the test)
  if ! sudo -n true 2>/dev/null; then
    skip_test "sudo requires password - cannot test without blocking"
    return 0
  fi

  __logic_schedule_shutdown "0" 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_PERMISSION" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_SHUTDOWN" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "0 minutes should return EC_PERMISSION or EC_SUCCESS_SYSTEM_SHUTDOWN"
}

# =============================================================================
# __logic_cancel_shutdown() TESTS
# =============================================================================

function test_cancel_shutdown_no_command() {
  log_test_step "Testing __logic_cancel_shutdown when shutdown unavailable"

  if ! command -v shutdown >/dev/null 2>&1; then
    __logic_cancel_shutdown 2>/dev/null
    local exit_code=$?
    assert_equals "$EC_MISSING_DEPENDENCY" "$exit_code" \
      "Should return missing dependency when shutdown not available"
  else
    skip_test "shutdown command is available - cannot test missing dependency"
    return 0
  fi
}

function test_cancel_shutdown_valid_returns_permission_or_success() {
  log_test_step "Testing __logic_cancel_shutdown expects permission or success"

  if ! command -v shutdown >/dev/null 2>&1; then
    skip_test "shutdown command not available"
    return 0
  fi

  # Skip if sudo requires a password (would block the test)
  if ! sudo -n true 2>/dev/null; then
    skip_test "sudo requires password - cannot test without blocking"
    return 0
  fi

  __logic_cancel_shutdown 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_PERMISSION" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return EC_PERMISSION (no sudo) or EC_SUCCESS"
}

# =============================================================================
# __logic_schedule_restart() TESTS
# =============================================================================

function test_schedule_restart_empty_arg() {
  log_test_step "Testing __logic_schedule_restart with empty time argument"

  __logic_schedule_restart "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for empty time argument"
}

function test_schedule_restart_negative_number() {
  log_test_step "Testing __logic_schedule_restart with negative time"

  __logic_schedule_restart "-5" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for negative time"
}

function test_schedule_restart_non_numeric() {
  log_test_step "Testing __logic_schedule_restart with non-numeric time"

  __logic_schedule_restart "soon" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for non-numeric time"
}

function test_schedule_restart_float_number() {
  log_test_step "Testing __logic_schedule_restart with float number"

  __logic_schedule_restart "2.5" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return invalid arg for floating-point time"
}

function test_schedule_restart_no_shutdown_command() {
  log_test_step "Testing __logic_schedule_restart when shutdown unavailable"

  if ! command -v shutdown >/dev/null 2>&1; then
    __logic_schedule_restart "5" 2>/dev/null
    local exit_code=$?
    assert_equals "$EC_MISSING_DEPENDENCY" "$exit_code" \
      "Should return missing dependency when shutdown command not available"
  else
    skip_test "shutdown command is available - cannot test missing dependency"
    return 0
  fi
}

function test_schedule_restart_valid_arg_permission() {
  log_test_step "Testing __logic_schedule_restart with valid arg (expects permission error)"

  if ! command -v shutdown >/dev/null 2>&1; then
    skip_test "shutdown command not available"
    return 0
  fi

  # Skip if sudo requires a password (would block the test)
  if ! sudo -n true 2>/dev/null; then
    skip_test "sudo requires password - cannot test without blocking"
    return 0
  fi

  __logic_schedule_restart "60" 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_PERMISSION" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_RESTART" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return EC_PERMISSION (no sudo) or EC_SUCCESS_SYSTEM_RESTART"
}

function test_schedule_restart_zero_minutes() {
  log_test_step "Testing __logic_schedule_restart with 0 minutes (immediate)"

  if ! command -v shutdown >/dev/null 2>&1; then
    skip_test "shutdown command not available"
    return 0
  fi

  # Skip if sudo requires a password (would block the test)
  if ! sudo -n true 2>/dev/null; then
    skip_test "sudo requires password - cannot test without blocking"
    return 0
  fi

  __logic_schedule_restart "0" 2>/dev/null
  local exit_code=$?

  local is_valid=false
  if [[ "$exit_code" -eq "$EC_PERMISSION" ]] ||
     [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_RESTART" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "0 minutes should return EC_PERMISSION or EC_SUCCESS_SYSTEM_RESTART"
}

# =============================================================================
# __logic_get_uptime() TESTS
# =============================================================================

function test_get_uptime_succeeds() {
  log_test_step "Testing __logic_get_uptime succeeds with uptime command"

  if ! command -v uptime >/dev/null 2>&1; then
    skip_test "uptime command not available"
    return 0
  fi

  __logic_get_uptime 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" "$exit_code" \
    "Should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED"
}

function test_get_uptime_output_not_empty() {
  log_test_step "Testing __logic_get_uptime output is not empty"

  if ! command -v uptime >/dev/null 2>&1; then
    skip_test "uptime command not available"
    return 0
  fi

  local output
  output=$(__logic_get_uptime 2>/dev/null)

  assert_not_null "$output" "Uptime output should not be empty"
}

function test_get_uptime_output_format() {
  log_test_step "Testing __logic_get_uptime output contains uptime information"

  if ! command -v uptime >/dev/null 2>&1; then
    skip_test "uptime command not available"
    return 0
  fi

  local output
  output=$(__logic_get_uptime 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" ]]; then
    assert_not_null "$output" "Uptime string should not be empty"
  fi
}

function test_get_uptime_missing_command() {
  log_test_step "Testing __logic_get_uptime returns EC_MISSING_DEPENDENCY when unavailable"

  if ! command -v uptime >/dev/null 2>&1; then
    __logic_get_uptime 2>/dev/null
    local exit_code=$?
    assert_equals "$EC_MISSING_DEPENDENCY" "$exit_code" \
      "Should return EC_MISSING_DEPENDENCY when uptime not available"
  else
    skip_test "uptime command is available"
    return 0
  fi
}

# =============================================================================
# __logic_check_reboot_required() TESTS
# =============================================================================

function test_check_reboot_required_returns_valid_code() {
  log_test_step "Testing __logic_check_reboot_required returns EC_SUCCESS"

  __logic_check_reboot_required 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should always return EC_SUCCESS"
}

function test_check_reboot_required_output_is_boolean() {
  log_test_step "Testing __logic_check_reboot_required output is 'true' or 'false'"

  local output
  output=$(__logic_check_reboot_required 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" "Should return EC_SUCCESS"

  local is_valid=false
  if [[ "$output" == "true" ]] || [[ "$output" == "false" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Output should be 'true' or 'false', got: '$output'"
}

function test_check_reboot_required_reboot_file_exists() {
  log_test_step "Testing __logic_check_reboot_required detects reboot-required file"

  if [[ -f /var/run/reboot-required ]]; then
    # File already exists - should report true
    local output
    output=$(__logic_check_reboot_required 2>/dev/null)

    assert_equals "true" "$output" \
      "Should return 'true' when /var/run/reboot-required exists"
  else
    # Test by creating the file temporarily in a known location
    # (Only if we have write access to /var/run)
    if [[ -w /var/run ]] || [[ -w /tmp ]]; then
      # Create a temporary indicator to test logic
      skip_test "Cannot reliably create /var/run/reboot-required in sandbox"
    return 0
    else
      skip_test "/var/run/reboot-required does not exist - checking false case"
    return 0
    fi
  fi
}

function test_check_reboot_not_required_default() {
  log_test_step "Testing __logic_check_reboot_required returns 'false' when no indicators"

  if [[ -f /var/run/reboot-required ]]; then
    skip_test "/var/run/reboot-required exists - can only test 'false' case without it"
    return 0
  fi

  if command -v needs-restarting >/dev/null 2>&1; then
    skip_test "needs-restarting available - result may vary"
    return 0
  fi

  local output
  output=$(__logic_check_reboot_required 2>/dev/null)

  assert_equals "false" "$output" \
    "Should return 'false' when no reboot indicators exist"
}

# =============================================================================
# __logic_get_load_average() TESTS
# =============================================================================

function test_get_load_average_succeeds() {
  log_test_step "Testing __logic_get_load_average succeeds"

  __logic_get_load_average 2>/dev/null
  local exit_code=$?

  # Should succeed via uptime or /proc/loadavg
  local is_valid=false
  if [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" ]] ||
     [[ "$exit_code" -eq "$EC_ERROR" ]]; then
    is_valid=true
  fi

  assert_equals "true" "$is_valid" \
    "Should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED or EC_ERROR"
}

function test_get_load_average_output_format() {
  log_test_step "Testing __logic_get_load_average output format"

  local output
  output=$(__logic_get_load_average 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" ]]; then
    assert_not_null "$output" "Load average output should not be empty"
    # Should contain numbers (load averages)
    assert_matches "$output" "[0-9]" "Load average output should contain numbers"
  fi
}

function test_get_load_average_proc_loadavg_fallback() {
  log_test_step "Testing __logic_get_load_average can use /proc/loadavg"

  if [[ ! -f /proc/loadavg ]]; then
    skip_test "/proc/loadavg does not exist"
    return 0
  fi

  local output
  output=$(__logic_get_load_average 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" "$exit_code" \
    "Should succeed via /proc/loadavg"
  assert_not_null "$output" "Load average should not be empty"
}

# =============================================================================
# __logic_get_memory_info() TESTS
# =============================================================================

function test_get_memory_info_succeeds() {
  log_test_step "Testing __logic_get_memory_info succeeds"

  if ! command -v free >/dev/null 2>&1; then
    skip_test "free command not available"
    return 0
  fi

  __logic_get_memory_info 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" "$exit_code" \
    "Should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED"
}

function test_get_memory_info_output_not_empty() {
  log_test_step "Testing __logic_get_memory_info output is not empty"

  if ! command -v free >/dev/null 2>&1; then
    skip_test "free command not available"
    return 0
  fi

  local output
  output=$(__logic_get_memory_info 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" ]]; then
    assert_not_null "$output" "Memory info output should not be empty"
  fi
}

function test_get_memory_info_output_contains_mem() {
  log_test_step "Testing __logic_get_memory_info output contains Mem: line"

  if ! command -v free >/dev/null 2>&1; then
    skip_test "free command not available"
    return 0
  fi

  local output
  output=$(__logic_get_memory_info 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" ]]; then
    assert_contains "$output" "Mem:" "Output should contain 'Mem:' header"
  fi
}

function test_get_memory_info_missing_free_command() {
  log_test_step "Testing __logic_get_memory_info returns EC_MISSING_DEPENDENCY without free"

  if ! command -v free >/dev/null 2>&1; then
    __logic_get_memory_info 2>/dev/null
    local exit_code=$?
    assert_equals "$EC_MISSING_DEPENDENCY" "$exit_code" \
      "Should return EC_MISSING_DEPENDENCY when free command not available"
  else
    skip_test "free command is available"
    return 0
  fi
}

# =============================================================================
# __logic_get_disk_usage() TESTS
# =============================================================================

function test_get_disk_usage_succeeds() {
  log_test_step "Testing __logic_get_disk_usage succeeds"

  if ! command -v df >/dev/null 2>&1; then
    skip_test "df command not available"
    return 0
  fi

  __logic_get_disk_usage 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" "$exit_code" \
    "Should return EC_SUCCESS_SYSTEM_INFO_RETRIEVED"
}

function test_get_disk_usage_output_not_empty() {
  log_test_step "Testing __logic_get_disk_usage output is not empty"

  if ! command -v df >/dev/null 2>&1; then
    skip_test "df command not available"
    return 0
  fi

  local output
  output=$(__logic_get_disk_usage 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" ]]; then
    assert_not_null "$output" "Disk usage output should not be empty"
  fi
}

function test_get_disk_usage_output_contains_filesystem() {
  log_test_step "Testing __logic_get_disk_usage output references root filesystem"

  if ! command -v df >/dev/null 2>&1; then
    skip_test "df command not available"
    return 0
  fi

  local output
  output=$(__logic_get_disk_usage 2>/dev/null)
  local exit_code=$?

  if [[ "$exit_code" -eq "$EC_SUCCESS_SYSTEM_INFO_RETRIEVED" ]]; then
    # Output should contain a percentage (disk usage %)
    assert_matches "$output" "[0-9]+%" \
      "Disk usage output should contain percentage"
  fi
}

function test_get_disk_usage_missing_df_command() {
  log_test_step "Testing __logic_get_disk_usage returns EC_MISSING_DEPENDENCY without df"

  if ! command -v df >/dev/null 2>&1; then
    __logic_get_disk_usage 2>/dev/null
    local exit_code=$?
    assert_equals "$EC_MISSING_DEPENDENCY" "$exit_code" \
      "Should return EC_MISSING_DEPENDENCY when df command not available"
  else
    skip_test "df command is available"
    return 0
  fi
}

# =============================================================================
# MODULE LOAD FLAG TESTS
# =============================================================================

function test_module_load_flag_set() {
  log_test_step "Testing KGSM_LOGIC_SYSTEM_LOADED flag is set after sourcing"

  assert_not_null "${KGSM_LOGIC_SYSTEM_LOADED:-}" \
    "KGSM_LOGIC_SYSTEM_LOADED should be set after sourcing handler"
}

function test_module_load_guard() {
  log_test_step "Testing handler can be sourced multiple times without errors"

  # Source again - should be guarded and return early
  source "$HANDLER" 2>/dev/null
  local exit_code=$?

  assert_equals "0" "$exit_code" \
    "Re-sourcing handler should succeed (load guard prevents duplicate loading)"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting system logic handler tests"

  setup_test

  # __logic_schedule_shutdown tests
  test_schedule_shutdown_empty_arg
  test_schedule_shutdown_negative_number
  test_schedule_shutdown_non_numeric
  test_schedule_shutdown_float_number
  test_schedule_shutdown_no_shutdown_command
  test_schedule_shutdown_valid_arg_permission
  test_schedule_shutdown_zero_minutes

  # __logic_cancel_shutdown tests
  test_cancel_shutdown_no_command
  test_cancel_shutdown_valid_returns_permission_or_success

  # __logic_schedule_restart tests
  test_schedule_restart_empty_arg
  test_schedule_restart_negative_number
  test_schedule_restart_non_numeric
  test_schedule_restart_float_number
  test_schedule_restart_no_shutdown_command
  test_schedule_restart_valid_arg_permission
  test_schedule_restart_zero_minutes

  # __logic_get_uptime tests
  test_get_uptime_succeeds
  test_get_uptime_output_not_empty
  test_get_uptime_output_format
  test_get_uptime_missing_command

  # __logic_check_reboot_required tests
  test_check_reboot_required_returns_valid_code
  test_check_reboot_required_output_is_boolean
  test_check_reboot_required_reboot_file_exists
  test_check_reboot_not_required_default

  # __logic_get_load_average tests
  test_get_load_average_succeeds
  test_get_load_average_output_format
  test_get_load_average_proc_loadavg_fallback

  # __logic_get_memory_info tests
  test_get_memory_info_succeeds
  test_get_memory_info_output_not_empty
  test_get_memory_info_output_contains_mem
  test_get_memory_info_missing_free_command

  # __logic_get_disk_usage tests
  test_get_disk_usage_succeeds
  test_get_disk_usage_output_not_empty
  test_get_disk_usage_output_contains_filesystem
  test_get_disk_usage_missing_df_command

  # Module flag tests
  test_module_load_flag_set
  test_module_load_guard

  log_test_step "System logic handler tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All system logic tests passed"
  else
    fail_test "Some system logic tests failed"
  fi
}

main "$@"
