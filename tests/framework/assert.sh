#!/usr/bin/env bash

# KGSM Test Framework - Assertion Library
#
# Author: The Krystal Ship Team
# Version: 3.0
#
# Comprehensive assertion library for KGSM tests providing:
# - Multiple assertion types
# - Detailed error reporting
# - Test statistics tracking
# - Colored output support

# Disabling shellcheck SC2086 for exit and return codes to allow variable usage
# shellcheck disable=SC2086
# shellcheck disable=SC2155

if [[ -n "${TEST_ASSERT_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# CONSTANTS
# =============================================================================

# Exit codes (only define if not already defined)
if [[ -z "${ASSERT_SUCCESS:-}" ]]; then
  readonly ASSERT_SUCCESS=0
  readonly ASSERT_FAILURE=1
fi

# Color codes (if not already set)
if [[ -z "${RED:-}" ]]; then
  readonly RED='\033[0;31m'
  readonly GREEN='\033[0;32m'
  readonly YELLOW='\033[1;33m'
  readonly BLUE='\033[0;34m'
  readonly PURPLE='\033[0;35m'
  readonly CYAN='\033[0;36m'
  readonly WHITE='\033[1;37m'
  readonly GRAY='\033[0;37m'
  readonly NC='\033[0m'
  readonly BOLD='\033[1m'
fi

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

declare -gi ASSERT_COUNT=0
declare -gi ASSERT_PASSED=0
declare -gi ASSERT_FAILED=0
declare -gi ASSERT_FUNCTIONS_SKIPPED=0
declare -ga ASSERT_SKIPPED_FUNCTION_NAMES=()

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get calling function info for better error reporting
function get_caller_info() {
  local frame="${1:-2}" # Default to 2 frames up (caller of assert function)
  local func="${FUNCNAME[$frame]:-main}"
  local line="${BASH_LINENO[$((frame - 1))]:-0}"
  local file="${BASH_SOURCE[$frame]:-unknown}"

  echo "$(basename "$file"):$line in $func()"
}

export -f get_caller_info

# Print assertion result
function print_assert_result() {
  local result="$1"
  local message="$2"
  local caller_info="$3"

  ((ASSERT_COUNT++))

  if [[ "$result" == "PASS" ]]; then
    ((ASSERT_PASSED++))
  else
    ((ASSERT_FAILED++))
  fi

  log_assertion "$result" "$message" "$caller_info"
}

export -f print_assert_result

# =============================================================================
# BASIC ASSERTIONS
# =============================================================================

# Assert that two values are equal
function assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$expected" == "$actual" ]]; then
    print_assert_result "PASS" "$message: '$actual' equals '$expected'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: expected '$expected', got '$actual'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_equals

# Assert that two values are not equal
function assert_not_equals() {
  local not_expected="$1"
  local actual="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$not_expected" != "$actual" ]]; then
    print_assert_result "PASS" "$message: '$actual' does not equal '$not_expected'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: '$actual' should not equal '$not_expected'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_not_equals

# Assert that a condition is true
function assert_true() {
  local condition="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]]; then
    print_assert_result "PASS" "$message: condition is true" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: expected true, got '$condition'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_true

# Assert that a condition is false
function assert_false() {
  local condition="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$condition" == "false" ]] || [[ "$condition" == "1" ]]; then
    print_assert_result "PASS" "$message: condition is false" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: expected false, got '$condition'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_false

# Assert that a value is null or empty
function assert_null() {
  local value="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ -z "$value" ]]; then
    print_assert_result "PASS" "$message: value is null/empty" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: expected null/empty, got '$value'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_null

# Assert that a value is not null or empty
function assert_not_null() {
  local value="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ -n "$value" ]]; then
    print_assert_result "PASS" "$message: value is not null/empty" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: expected non-null/non-empty value, got empty" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_not_null

# =============================================================================
# STRING ASSERTIONS
# =============================================================================

# Assert that a string contains a substring
function assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$haystack" == *"$needle"* ]]; then
    print_assert_result "PASS" "$message: '$haystack' contains '$needle'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: '$haystack' does not contain '$needle'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_contains

# Assert that a string does not contain a substring
function assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$haystack" != *"$needle"* ]]; then
    print_assert_result "PASS" "$message: '$haystack' does not contain '$needle'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: '$haystack' should not contain '$needle'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_not_contains

# Assert that a string matches a regex pattern
function assert_matches() {
  local string="$1"
  local pattern="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$string" =~ $pattern ]]; then
    print_assert_result "PASS" "$message: '$string' matches pattern '$pattern'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: '$string' does not match pattern '$pattern'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_matches

# Assert that a string starts with a prefix
function assert_starts_with() {
  local string="$1"
  local prefix="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$string" == "$prefix"* ]]; then
    print_assert_result "PASS" "$message: '$string' starts with '$prefix'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: '$string' does not start with '$prefix'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_starts_with

# Assert that a string ends with a suffix
function assert_ends_with() {
  local string="$1"
  local suffix="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ "$string" == *"$suffix" ]]; then
    print_assert_result "PASS" "$message: '$string' ends with '$suffix'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: '$string' does not end with '$suffix'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_ends_with

# =============================================================================
# EXACT MATCH ASSERTIONS
# =============================================================================

# Assert that a multi-line string contains an exact line match
function assert_contains_line() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if echo "$haystack" | grep -Fxq "$needle"; then
    print_assert_result "PASS" "$message: text contains exact line '$needle'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: text does not contain exact line '$needle'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_contains_line

# Assert that a multi-line string does not contain an exact line match
function assert_not_contains_line() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if echo "$haystack" | grep -Fxq "$needle"; then
    print_assert_result "FAIL" "$message: text should not contain exact line '$needle'" "$caller_info"
    return $ASSERT_FAILURE
  else
    print_assert_result "PASS" "$message: text does not contain exact line '$needle'" "$caller_info"
    return $ASSERT_SUCCESS
  fi
}

export -f assert_not_contains_line

# Assert that a list (newline-separated) contains a specific item exactly
function assert_list_contains() {
  local list_output="$1"
  local expected_item="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if printf '%s\n' "$list_output" | grep -Fxq "$expected_item"; then
    print_assert_result "PASS" "$message: list contains item '$expected_item'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: list does not contain item '$expected_item'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_list_contains

# Assert that a list (newline-separated) does not contain a specific item exactly
function assert_list_not_contains() {
  local list_output="$1"
  local expected_item="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if printf '%s\n' "$list_output" | grep -Fxq "$expected_item"; then
    print_assert_result "FAIL" "$message: list should not contain item '$expected_item'" "$caller_info"
    return $ASSERT_FAILURE
  else
    print_assert_result "PASS" "$message: list does not contain item '$expected_item'" "$caller_info"
    return $ASSERT_SUCCESS
  fi
}

export -f assert_list_not_contains

# =============================================================================
# NUMERIC ASSERTIONS
# =============================================================================

# Assert that two numbers are equal
function assert_numeric_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if ((expected == actual)); then
    print_assert_result "PASS" "$message: $actual equals $expected" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: expected $expected, got $actual" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_numeric_equals

# Assert that first number is greater than second
function assert_greater_than() {
  local actual="$1"
  local threshold="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if ((actual > threshold)); then
    print_assert_result "PASS" "$message: $actual is greater than $threshold" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: $actual is not greater than $threshold" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_greater_than

# Assert that first number is less than second
function assert_less_than() {
  local actual="$1"
  local threshold="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if ((actual < threshold)); then
    print_assert_result "PASS" "$message: $actual is less than $threshold" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: $actual is not less than $threshold" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_less_than

# =============================================================================
# FILE SYSTEM ASSERTIONS
# =============================================================================

# Assert that a file exists
function assert_file_exists() {
  local file_path="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ -f "$file_path" ]]; then
    print_assert_result "PASS" "$message: file '$file_path' exists" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: file '$file_path' does not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_file_exists

# Assert that a file does not exist
function assert_file_not_exists() {
  local file_path="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ ! -f "$file_path" ]]; then
    print_assert_result "PASS" "$message: file '$file_path' does not exist" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: file '$file_path' should not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_file_not_exists

# Assert that a directory exists
function assert_dir_exists() {
  local dir_path="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ -d "$dir_path" ]]; then
    print_assert_result "PASS" "$message: directory '$dir_path' exists" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: directory '$dir_path' does not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_dir_exists

# Assert that a directory does not exist
function assert_dir_not_exists() {
  local dir_path="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ ! -d "$dir_path" ]]; then
    print_assert_result "PASS" "$message: directory '$dir_path' does not exist" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: directory '$dir_path' should not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_dir_not_exists

# Assert that a file is executable
function assert_file_executable() {
  local file_path="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ -x "$file_path" ]]; then
    print_assert_result "PASS" "$message: file '$file_path' is executable" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: file '$file_path' is not executable" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_file_executable

# Assert that a file contains specific content
function assert_file_contains() {
  local file_path="$1"
  local expected_content="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ ! -f "$file_path" ]]; then
    print_assert_result "FAIL" "$message: file '$file_path' does not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi

  if grep -q "$expected_content" "$file_path"; then
    print_assert_result "PASS" "$message: file '$file_path' contains '$expected_content'" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: file '$file_path' does not contain '$expected_content'" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_file_contains

# Assert that a socket file exists
function assert_socket_exists() {
  local socket_path="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ -S "$socket_path" ]]; then
    print_assert_result "PASS" "$message: socket file '$socket_path' exists" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: socket file '$socket_path' does not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_socket_exists

# Assert that a socket file does not exist
function assert_socket_not_exists() {
  local socket_path="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if [[ ! -S "$socket_path" ]]; then
    print_assert_result "PASS" "$message: socket file '$socket_path' does not exist" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: socket file '$socket_path' should not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_socket_not_exists

# Assert that a command is available in PATH
function assert_command_available() {
  local command_name="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if command -v "$command_name" >/dev/null 2>&1; then
    print_assert_result "PASS" "$message: command '$command_name' is available" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: command '$command_name' is not available" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_command_available

# Assert that a command is not available in PATH
function assert_command_not_available() {
  local command_name="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    print_assert_result "PASS" "$message: command '$command_name' is not available" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: command '$command_name' should not be available" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_command_not_available

# =============================================================================
# COMMAND EXECUTION ASSERTIONS
# =============================================================================

# Assert that a command succeeds (exit code 0)
function assert_command_succeeds() {
  local command="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  local output
  local exit_code

  if output=$(eval "$command" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  if [[ $exit_code -eq 0 ]]; then
    print_assert_result "PASS" "$message: command '$command' succeeded" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: command '$command' failed with exit code $exit_code" "$caller_info"
    if [[ -n "$output" ]]; then
      printf "${RED}Command output:${NC}\n%s\n" "$output" >&2
    fi
    return $ASSERT_FAILURE
  fi
}

export -f assert_command_succeeds

# Assert that a command fails (non-zero exit code)
function assert_command_fails() {
  local command="$1"
  local message="${2:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  local output
  local exit_code

  if output=$(eval "$command" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  if [[ $exit_code -ne 0 ]]; then
    print_assert_result "PASS" "$message: command '$command' failed as expected (exit code $exit_code)" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: command '$command' should have failed but succeeded" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_command_fails

# Assert that a command produces specific output
function assert_command_output() {
  local command="$1"
  local expected_output="$2"
  local message="${3:-Assertion failed}"
  local caller_info="$(get_caller_info)"

  local actual_output
  local exit_code

  if actual_output=$(eval "$command" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  if [[ "$actual_output" == *"$expected_output"* ]]; then
    print_assert_result "PASS" "$message: command output contains expected text" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: command output does not contain expected text" "$caller_info"
    printf "${RED}Expected:${NC} %s\n" "$expected_output" >&2
    printf "${RED}Actual:${NC} %s\n" "$actual_output" >&2
    return $ASSERT_FAILURE
  fi
}

export -f assert_command_output

# Assert that a function exists in the current shell
function assert_function_exists() {
  local function_name="$1"
  local message="${2:-Function should exist}"
  local caller_info="$(get_caller_info)"

  if declare -F "$function_name" >/dev/null 2>&1; then
    print_assert_result "PASS" "$message: $function_name exists" "$caller_info"
    return $ASSERT_SUCCESS
  else
    print_assert_result "FAIL" "$message: $function_name does not exist" "$caller_info"
    return $ASSERT_FAILURE
  fi
}

export -f assert_function_exists

# =============================================================================
# TEST STATISTICS AND REPORTING
# =============================================================================

# Get assertion statistics
function get_assert_stats() {
  echo "Assertions: $ASSERT_COUNT, Passed: $ASSERT_PASSED, Failed: $ASSERT_FAILED"
}

export -f get_assert_stats

# Reset assertion counters (should be called at start of each test)
function reset_assert_stats() {
  ASSERT_COUNT=0
  ASSERT_PASSED=0
  ASSERT_FAILED=0
  ASSERT_FUNCTIONS_SKIPPED=0
  ASSERT_SKIPPED_FUNCTION_NAMES=()

  # Also reset in case they were exported from parent shell
  declare -gi ASSERT_COUNT=0
  declare -gi ASSERT_PASSED=0
  declare -gi ASSERT_FAILED=0
  declare -gi ASSERT_FUNCTIONS_SKIPPED=0
  declare -ga ASSERT_SKIPPED_FUNCTION_NAMES=()
}

export -f reset_assert_stats

# Print assertion summary
function print_assert_summary() {
  local test_name="${1:-Test}"

  # Make copies of global counters
  local assert_count=$ASSERT_COUNT
  local assert_passed=$ASSERT_PASSED
  local assert_failed=$ASSERT_FAILED
  local functions_skipped=$ASSERT_FUNCTIONS_SKIPPED

  # Reset counters for next test
  reset_assert_stats

  printf "\n${BOLD}=== %s Assertion Summary ===${NC}\n" "$test_name"
  printf "Total assertions: %d\n" "${assert_count:-0}"
  printf "${GREEN}Passed: %d${NC}\n" "${assert_passed:-0}"
  printf "${RED}Failed: %d${NC}\n" "${assert_failed:-0}"

  if [[ $functions_skipped -gt 0 ]]; then
    printf "${YELLOW}Test functions skipped: %d${NC}\n" "$functions_skipped"
  fi

  # Write assertion stats marker to test log for runner to parse
  if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
    echo "KGSM_ASSERT_STATS: ${assert_passed}/${assert_failed}/${assert_count}/${functions_skipped}" >>"$KGSM_TEST_LOG" 2>/dev/null || true
  fi

  if [[ $assert_failed -gt 0 ]]; then
    printf "\n${RED}Test failed with %d assertion failures${NC}\n" "$assert_failed"
    return 1 # ASSERT_FAILURE
  else
    printf "\n${GREEN}All assertions passed${NC}\n"
    return 0 # ASSERT_SUCCESS
  fi
}

export -f print_assert_summary

# =============================================================================
# HELPER FUNCTIONS FOR KGSM-SPECIFIC TESTING
# =============================================================================

# Assert that KGSM command succeeds
function assert_kgsm_succeeds() {
  local kgsm_args="$1"
  local message="${2:-KGSM command failed}"

  assert_command_succeeds "$KGSM_ROOT/kgsm.sh $kgsm_args" "$message"
}

export -f assert_kgsm_succeeds

# Assert that KGSM command fails
function assert_kgsm_fails() {
  local kgsm_args="$1"
  local message="${2:-KGSM command should have failed}"

  assert_command_fails "$KGSM_ROOT/kgsm.sh $kgsm_args" "$message"
}

export -f assert_kgsm_fails

# Assert that instance exists
function assert_instance_exists() {
  local instance_name="$1"
  local message="${2:-Instance should exist}"

  assert_command_succeeds "$KGSM_ROOT/commands/instances.sh --find '$instance_name'" "$message"
}

export -f assert_instance_exists

# Assert that instance does not exist
function assert_instance_not_exists() {
  local instance_name="$1"
  local message="${2:-Instance should not exist}"

  assert_command_fails "$KGSM_ROOT/commands/instances.sh --find '$instance_name'" "$message"
}

export -f assert_instance_not_exists

# Reset global assertion counters on module load
reset_assert_stats 2>/dev/null || true

declare -g TEST_ASSERT_LOADED=1
export TEST_ASSERT_LOADED
