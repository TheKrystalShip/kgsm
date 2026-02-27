#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - TAP Reporter Module
# ==============================================================================
# Version: 1.0
# Description: Generates TAP (Test Anything Protocol) version 14 output from
#              test results CSV. Designed for consumption by TAP-aware tools
#              and VS Code test extensions.
# Dependencies: loader.sh (exit codes), reporting.sh (CSV helpers, REPORT_STATS)
# Usage: source tests/framework/reporting.tap.sh (normally sourced by common.sh)
# ==============================================================================

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

# ==============================================================================
# Load Guard
# ==============================================================================

if [[ -n "${TEST_REPORTING_TAP_LOADED:-}" ]]; then
  return 0
fi

# ==============================================================================
# TAP Output Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Generate complete TAP version 14 output from CSV results
# ------------------------------------------------------------------------------
# Reads the results CSV (single source of truth) and outputs valid TAP v14
# to stdout. All non-TAP output is suppressed when this is called.
#
# Arguments: None (reads from REPORT_STATS[results_csv_path])
# Returns:
#   Exit code: EC_SUCCESS (0) if all tests passed, EC_FAILURE (1) if any failed
# Output:
#   TAP version 14 formatted output to stdout
# ------------------------------------------------------------------------------
function generate_tap_output() {
  local csv_path="${REPORT_STATS[results_csv_path]:-}"

  if [[ -z "$csv_path" || ! -f "$csv_path" ]]; then
    echo "TAP version 14"
    echo "1..0 # no test results found"
    return $EC_SUCCESS
  fi

  # Count total tests from CSV (exclude header)
  local total_tests
  total_tests=$(tail -n +2 "$csv_path" | grep -c -v '^$' || echo "0")

  # Emit TAP header
  echo "TAP version 14"
  echo "1..${total_tests}"

  # Track test number and failure status
  local -i test_number=0
  local -i has_failures=0

  # Callback function for each CSV row
  function __tap_emit_result() {
    local test_name="$1" test_type="$2" exit_code="$3" duration_ms="$4"
    local timestamp="$5" a_passed="$6" a_failed="$7" a_total="$8"
    local f_skipped="${9:-0}"

    test_number=$((test_number + 1))

    # Determine test file path from test name and type
    local test_file
    test_file=$(__tap_resolve_file_path "$test_name" "$test_type")

    # Build the TAP result line
    case "$exit_code" in
      0)
        # Passed
        printf "ok %d - %s [%s]" "$test_number" "$test_name" "$test_type"
        if [[ "$a_total" -gt 0 ]]; then
          printf " # %s assertions in %sms" "$a_total" "$duration_ms"
        fi
        printf "\n"
        ;;
      33)
        # Skipped
        printf "ok %d - %s [%s] # SKIP\n" "$test_number" "$test_name" "$test_type"
        ;;
      *)
        # Failed or error
        has_failures=1
        printf "not ok %d - %s [%s]\n" "$test_number" "$test_name" "$test_type"
        # Emit YAML diagnostic block
        __tap_emit_yaml_diagnostic "$test_name" "$test_type" "$exit_code" \
          "$duration_ms" "$a_passed" "$a_failed" "$a_total" "$f_skipped" "$test_file"
        ;;
    esac
  }

  # Iterate over CSV using shared helper from reporting.sh
  __foreach_csv_line "$csv_path" __tap_emit_result

  if [[ $has_failures -gt 0 ]]; then
    return $EC_FAILURE
  fi

  return $EC_SUCCESS
}
export -f generate_tap_output

# ------------------------------------------------------------------------------
# Emit a TAP YAML diagnostic block for a failed test
# ------------------------------------------------------------------------------
# TAP v14 diagnostics use indented YAML between --- and ... markers.
#
# Arguments:
#   $1 - test_name
#   $2 - test_type
#   $3 - exit_code
#   $4 - duration_ms
#   $5 - assertions_passed
#   $6 - assertions_failed
#   $7 - assertions_total
#   $8 - functions_skipped
#   $9 - test_file (resolved path)
# Returns:
#   Exit code: EC_SUCCESS (0)
# Output:
#   Indented YAML diagnostic block to stdout
# ------------------------------------------------------------------------------
function __tap_emit_yaml_diagnostic() {
  local test_name="$1" test_type="$2" exit_code="$3" duration_ms="$4"
  local a_passed="$5" a_failed="$6" a_total="$7" f_skipped="$8"
  local test_file="$9"

  echo "  ---"

  # Severity based on exit code
  if [[ "$exit_code" -eq 2 ]]; then
    echo "  severity: error"
    echo "  message: \"Internal framework error during test execution\""
  else
    echo "  severity: fail"
    if [[ "$a_total" -gt 0 ]]; then
      echo "  message: \"${a_failed}/${a_total} assertions failed\""
    else
      echo "  message: \"Test exited with code ${exit_code}\""
    fi
  fi

  echo "  exit_code: ${exit_code}"
  echo "  duration_ms: ${duration_ms}"

  if [[ "$a_total" -gt 0 ]]; then
    echo "  assertions_passed: ${a_passed}"
    echo "  assertions_failed: ${a_failed}"
    echo "  assertions_total: ${a_total}"
  fi

  if [[ "$f_skipped" -gt 0 ]]; then
    echo "  functions_skipped: ${f_skipped}"
  fi

  if [[ -n "$test_file" ]]; then
    echo "  file: \"${test_file}\""
  fi

  echo "  ..."
}
export -f __tap_emit_yaml_diagnostic

# ------------------------------------------------------------------------------
# Resolve test file path from test name and type
# ------------------------------------------------------------------------------
# Attempts to find the actual test file on disk for source mapping.
#
# Arguments:
#   $1 - test_name: Test name (e.g., "test_paths")
#   $2 - test_type: Test type (e.g., "unit")
# Returns:
#   Stdout: Relative path to test file (e.g., "tests/unit/test_paths.sh")
#           or empty string if not found
# ------------------------------------------------------------------------------
function __tap_resolve_file_path() {
  local test_name="$1"
  local test_type="$2"

  local test_dir
  case "$test_type" in
    unit)        test_dir="${TEST_UNIT_DIR:-${TEST_ROOT}/unit}" ;;
    integration) test_dir="${TEST_INTEGRATION_DIR:-${TEST_ROOT}/integration}" ;;
    e2e)         test_dir="${TEST_E2E_DIR:-${TEST_ROOT}/e2e}" ;;
    *)           echo ""; return 0 ;;
  esac

  local test_file="${test_dir}/${test_name}.sh"

  if [[ -f "$test_file" ]]; then
    # Output path relative to KGSM_ROOT
    local kgsm_root="${KGSM_ROOT:-}"
    if [[ -n "$kgsm_root" && "$test_file" == "${kgsm_root}/"* ]]; then
      echo "${test_file#${kgsm_root}/}"
    else
      echo "$test_file"
    fi
  else
    echo ""
  fi

  return 0
}
export -f __tap_resolve_file_path

# ==============================================================================
# Module Initialization
# ==============================================================================

declare -g TEST_REPORTING_TAP_LOADED=1
export TEST_REPORTING_TAP_LOADED
