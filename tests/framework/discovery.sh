#!/usr/bin/env bash

#
# KGSM Testing Framework - Test Discovery Module
#
# Responsible for finding and filtering test files across all test types.
# Implements pattern matching, skip conditions, and test listing functionality.
#
# Module: tests/framework/discovery.sh
# Version: 1.0
# Date: December 19, 2025
#

# =============================================================================
# LOAD GUARD
# =============================================================================

if [[ -n "${TEST_DISCOVERY_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# PUBLIC FUNCTIONS
# =============================================================================

#
# discover_tests()
#
# Discover all test files of a given type, recursively searching subdirectories.
#
# Arguments:
#   $1 - test_type (string, required): One of "unit", "integration", "e2e"
#
# Output:
#   Writes absolute paths to test files to stdout, one per line, sorted alphabetically
#   Empty output if no tests found or directory doesn't exist
#
# Return Codes:
#   0 - Success (even if zero tests found)
#   1 - Invalid test type (not unit/integration/e2e)
#
function discover_tests() {
  local test_type="$1"

  # Validate test type
  if [[ ! "$test_type" =~ ^(unit|integration|e2e)$ ]]; then
    log_error "Invalid test type: $test_type (must be unit, integration, or e2e)"
    return 1
  fi

  # Determine test directory
  local test_dir
  case "$test_type" in
    unit)        test_dir="$TEST_UNIT_DIR" ;;
    integration) test_dir="$TEST_INTEGRATION_DIR" ;;
    e2e)         test_dir="$TEST_E2E_DIR" ;;
  esac

  # Check directory exists
  if [[ ! -d "$test_dir" ]]; then
    log_warning "Test directory not found: $test_dir"
    return 0
  fi

  # Discover and sort test files (recursive find)
  find "$test_dir" -type f -name "test_*.sh" | sort

  return 0
}

export -f discover_tests

#
# should_run_test()
#
# Determine if a discovered test should be executed based on skip conditions and filters.
#
# A test runs unless its SKIP_<NAME> variable is set, or --pattern was given and
# none of the patterns match. A pattern matches either as a filename glob
# (`test_config_*.sh`, extension optional) or as a fragment of the file's name
# (`config`). Patterns are matched against the name as written on disk, and
# repeating --pattern unions them.
#
# Arguments:
#   $1 - test_file (string, required): Absolute path to test file
#
# Output:
#   None (purely decision function)
#
# Return Codes:
#   0 - Test should run (passes all filters)
#   1 - Test should be skipped (failed one or more filters)
#
function should_run_test() {
  local test_file="$1"
  local test_name

  test_name=$(get_test_name "$test_file")

  # Check configuration skip variable
  local skip_var="SKIP_${test_name^^}"
  if [[ "${!skip_var:-false}" == "true" ]]; then
    return 1
  fi

  # Check inclusion patterns (if any specified)
  if [[ ${#TEST_PATTERNS[@]} -gt 0 ]]; then
    local file_name
    file_name=$(basename "$test_file")

    local matched=false
    local pattern
    for pattern in "${TEST_PATTERNS[@]}"; do
      # A pattern selects a test two ways: as a filename glob
      # (`test_config_*.sh`, extension optional), or as a fragment of the name
      # (`config`). The glob comparisons leave their right-hand side unquoted on
      # purpose -- quoting it would make the glob a literal string and match
      # nothing -- while the fragment comparison quotes it so a pattern carrying
      # glob characters is not matched twice over.
      # shellcheck disable=SC2053
      if [[ "$file_name" == $pattern ]] ||
        [[ "$test_name" == $pattern ]] ||
        [[ "$file_name" == *"$pattern"* ]]; then
        matched=true
        break
      fi
    done

    if [[ "$matched" != "true" ]]; then
      return 1
    fi
  fi

  # All filters passed
  return 0
}

export -f should_run_test

#
# get_test_name()
#
# Extract standardized test name from file path (used for skip variable lookup and display).
#
# Arguments:
#   $1 - test_file (string, required): Absolute or relative path to test file
#
# Output:
#   Writes test name to stdout (single line)
#   Format: test_<name> (includes "test_" prefix)
#
# Return Codes:
#   0 - Success
#
function get_test_name() {
  local test_file="$1"
  basename "$test_file" .sh
}

export -f get_test_name

#
# list_tests_json()
#
# Output all discoverable tests as a JSON array for machine consumption.
#
# Arguments:
#   $@ - test_types (array, optional): Test types to list (default: all types)
#
# Output:
#   JSON array to stdout: [{"name":"test_paths","type":"unit","file":"tests/unit/test_paths.sh"}, ...]
#
# Return Codes:
#   0 - Success
#
function list_tests_json() {
  local test_types=("$@")

  # Default to all test types
  if [[ ${#test_types[@]} -eq 0 ]]; then
    test_types=("unit" "integration" "e2e")
  fi

  local first=true
  local kgsm_root="${KGSM_ROOT:-}"

  printf '['

  for test_type in "${test_types[@]}"; do
    local tests
    mapfile -t tests < <(discover_tests "$test_type")

    for test_file in "${tests[@]}"; do
      local test_name
      test_name=$(get_test_name "$test_file")

      # Make path relative to KGSM_ROOT
      local relative_path="$test_file"
      if [[ -n "$kgsm_root" && "$test_file" == "${kgsm_root}/"* ]]; then
        relative_path="${test_file#${kgsm_root}/}"
      fi

      if [[ "$first" == "true" ]]; then
        first=false
      else
        printf ','
      fi

      # Discover test functions in the file with line numbers
      local -a func_lines=()
      mapfile -t func_lines < <(grep -nP '^function (test_\w+|setup_test)' "$test_file" 2>/dev/null || true)

      local func_json="["
      local first_func=true
      for func_entry in "${func_lines[@]}"; do
        if [[ -z "$func_entry" ]]; then continue; fi
        # func_entry format: "LINE:function func_name() {" or "LINE:function func_name {"
        local func_line="${func_entry%%:*}"
        local func_name
        func_name=$(echo "$func_entry" | grep -oP 'function \K(test_\w+|setup_test)')
        if [[ -z "$func_name" ]]; then continue; fi
        if [[ "$first_func" == "true" ]]; then
          first_func=false
        else
          func_json+=","
        fi
        func_json+="{\"name\":\"${func_name}\",\"line\":${func_line}}"
      done
      func_json+="]"

      printf '{"name":"%s","type":"%s","file":"%s","functions":%s}' "$test_name" "$test_type" "$relative_path" "$func_json"
    done
  done

  printf ']\n'
}

export -f list_tests_json

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

declare -g TEST_DISCOVERY_LOADED=1
export TEST_DISCOVERY_LOADED
