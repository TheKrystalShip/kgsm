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
# GLOBAL VARIABLES
# =============================================================================

# Counter for filtered tests (not counted in TESTS_SKIPPED)
declare -gi TESTS_FILTERED=0
export TESTS_FILTERED

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
# Arguments:
#   $1 - test_file (string, required): Absolute path to test file
#
# Output:
#   None (purely decision function)
#   Side effects: Increments TESTS_FILTERED and logs filter reason if skipped
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
    log_info "Skipping test (config): $test_name"
    ((TESTS_FILTERED++))
    return 1
  fi

  # Check inclusion patterns (if any specified)
  if [[ ${#TEST_PATTERNS[@]} -gt 0 ]]; then
    local matched=false
    for pattern in "${TEST_PATTERNS[@]}"; do
      if [[ "$test_name" =~ $pattern ]]; then
        matched=true
        break
      fi
    done

    if [[ "$matched" != "true" ]]; then
      log_info "Skipping test (pattern mismatch): $test_name"
      ((TESTS_FILTERED++))
      return 1
    fi
  fi

  # Check exclusion patterns
  for exclude in "${TEST_EXCLUDE[@]}"; do
    if [[ "$test_name" =~ $exclude ]]; then
      log_info "Skipping test (excluded): $test_name"
      ((TESTS_FILTERED++))
      return 1
    fi
  done

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
# get_filter_reason()
#
# Determine why a test would be filtered (or "RUN" if it would execute).
#
# Arguments:
#   $1 - test_file (string, required): Absolute path to test file
#
# Output:
#   Writes filter reason to stdout (single line)
#   Possible values: RUN, SKIP-CONFIG, SKIP-PATTERN, SKIP-EXCLUDE
#
# Return Codes:
#   0 - Success
#
# Note:
#   This function duplicates the filtering logic from should_run_test() for display purposes.
#   Consider refactoring if logic becomes more complex.
#
function get_filter_reason() {
  local test_file="$1"
  local test_name

  test_name=$(get_test_name "$test_file")

  # Check configuration skip
  local skip_var="SKIP_${test_name^^}"
  if [[ "${!skip_var:-false}" == "true" ]]; then
    echo "SKIP-CONFIG"
    return 0
  fi

  # Check pattern match (if patterns specified)
  if [[ ${#TEST_PATTERNS[@]} -gt 0 ]]; then
    local matched=false
    for pattern in "${TEST_PATTERNS[@]}"; do
      if [[ "$test_name" =~ $pattern ]]; then
        matched=true
        break
      fi
    done

    if [[ "$matched" != "true" ]]; then
      echo "SKIP-PATTERN"
      return 0
    fi
  fi

  # Check exclusion patterns
  for exclude in "${TEST_EXCLUDE[@]}"; do
    if [[ "$test_name" =~ $exclude ]]; then
      echo "SKIP-EXCLUDE"
      return 0
    fi
  done

  # Test will run
  echo "RUN"
  return 0
}

export -f get_filter_reason

#
# list_tests()
#
# Display formatted list of all discoverable tests with their skip status.
#
# Arguments:
#   $@ - test_types (array, optional): Test types to list (default: all types)
#        Examples: list_tests, list_tests unit, list_tests unit integration
#
# Output:
#   Formatted list to stdout with color coding:
#     [RUN] - Test will run (green)
#     [SKIP-CONFIG] - Skipped by configuration (yellow)
#     [SKIP-PATTERN] - Filtered by pattern (yellow)
#     [SKIP-EXCLUDE] - Excluded by pattern (yellow)
#   Organized by test type (unit, integration, e2e)
#   Summary counts at end
#
# Return Codes:
#   0 - Success
#
function list_tests() {
  local test_types=("$@")

  # Default to all test types
  if [[ ${#test_types[@]} -eq 0 ]]; then
    test_types=("unit" "integration" "e2e")
  fi

  local total=0
  local runnable=0
  local filtered=0
  local tests

  for test_type in "${test_types[@]}"; do
    echo
    echo "${TEST_COLOR_CYAN}=== ${test_type^} Tests ===${TEST_COLOR_NC}"

    mapfile -t tests < <(discover_tests "$test_type")

    if [[ ${#tests[@]} -eq 0 ]]; then
      echo "${TEST_COLOR_GRAY}  (no tests found)${TEST_COLOR_NC}"
      continue
    fi

    for test_file in "${tests[@]}"; do
      local test_name
      test_name=$(get_test_name "$test_file")

      local filter_reason
      filter_reason=$(get_filter_reason "$test_file")

      if [[ "$filter_reason" == "RUN" ]]; then
        echo "  ${TEST_COLOR_GREEN}[RUN]${TEST_COLOR_NC} $test_name"
        ((runnable++))
      else
        echo "  ${TEST_COLOR_YELLOW}[$filter_reason]${TEST_COLOR_NC} $test_name"
        ((filtered++))
      fi

      ((total++))
    done
  done

  # Print summary
  echo
  echo "${TEST_COLOR_BOLD}Summary:${TEST_COLOR_NC}"
  echo "  Total tests: $total"
  echo "  Will run: ${TEST_COLOR_GREEN}$runnable${TEST_COLOR_NC}"
  echo "  Filtered: ${TEST_COLOR_YELLOW}$filtered${TEST_COLOR_NC}"
}

export -f list_tests

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

declare -g TEST_DISCOVERY_LOADED=1
export TEST_DISCOVERY_LOADED
