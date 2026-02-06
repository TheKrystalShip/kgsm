#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - Reporting Module
# ==============================================================================
# Version: 1.0
# Description: Centralized test statistics collection, aggregation, and
#              presentation. Handles tracking test results, assertion counts,
#              timing information, and generates both console output (colored)
#              and file output (plain text/CSV) for post-execution analysis.
# Dependencies: loader.sh (paths, colors), config.sh (output settings),
#               logging.sh (dual output helpers)
# Usage: source tests/framework/reporting.sh (normally sourced by common.sh)
# ==============================================================================

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

# ==============================================================================
# Load Guard
# ==============================================================================

# Prevent double-loading
if [[ -n "${TEST_REPORTING_LOADED:-}" ]]; then
  return 0
fi

# ==============================================================================
# Module Constants
# ==============================================================================

declare -gr TEST_FRAMEWORK_VERSION="1.0"

# ==============================================================================
# Global Statistics Structure
# ==============================================================================

# Initialize empty REPORT_STATS - will be populated by init_reporting()
declare -gA REPORT_STATS=()

# ==============================================================================
# Initialization Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Initialize the reporting system for a test run
# ------------------------------------------------------------------------------
# Must be called at the start of a test run to reset counters and set paths.
# Creates the results CSV file with headers.
#
# Arguments:
#   $1 - log_dir: Absolute path to test logs directory (timestamped)
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
#   Side effects: Initializes REPORT_STATS, creates CSV file
# ------------------------------------------------------------------------------
function init_reporting() {
  local log_dir="$1"

  # Validate log directory
  if [[ -z "$log_dir" ]]; then
    log_error "init_reporting: log_dir is required"
    return $EC_FAILURE
  fi

  # Ensure log directory exists
  mkdir -p "$log_dir" || {
    log_error "Failed to create log directory: $log_dir"
    return $EC_FAILURE
  }

  # Initialize statistics structure
  # Using unset + declare to ensure clean state
  unset REPORT_STATS
  declare -gA REPORT_STATS=(
    # Test counts
     [tests_total]="0"
     [tests_passed]="0"
     [tests_failed]="0"
     [tests_skipped]="0"
     [tests_errors]="0"
     [tests_filtered]="0"

    # Assertion counts
     [assertions_total]="0"
     [assertions_passed]="0"
     [assertions_failed]="0"

    # Timing
     [start_time]="$(date +%s%3N)"
     [end_time]=""
     [total_runtime_seconds]="0"

    # Output paths
     [results_csv_path]="${log_dir}/results.csv"
     [summary_path]="${log_dir}/summary.txt"
     [log_dir]="$log_dir"
  )

  # Create CSV file with headers
  __create_results_csv_header "${REPORT_STATS[results_csv_path]}" || return $EC_FAILURE

  log_debug "Reporting initialized: log_dir=$log_dir"
  return $EC_SUCCESS
}
export -f init_reporting

# ==============================================================================
# CSV Management Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Create CSV file with column headers
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - csv_path: Absolute path to CSV file
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
# ------------------------------------------------------------------------------
function __create_results_csv_header() {
  local csv_path="$1"

  # Write CSV header row
  echo "test_name,test_type,exit_code,duration_ms,timestamp,assertions_passed,assertions_failed,assertions_total" \
    > "$csv_path" || {
    log_error "Failed to create CSV file: $csv_path"
    return $EC_FAILURE
  }

  return $EC_SUCCESS
}
export -f __create_results_csv_header

# ------------------------------------------------------------------------------
# Append a test result to the CSV file
# ------------------------------------------------------------------------------
# Thread-safe via flock for parallel execution scenarios where
# multiple processes might write to the same CSV.
#
# Arguments:
#   $1 - result_array_name: Name of associative array with test result
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
# ------------------------------------------------------------------------------
function __append_result_to_csv() {
  local result_array_name="$1"
  local -n _csv_result_ref="$result_array_name"

  local csv_path="${REPORT_STATS[results_csv_path]:-}"
  if [[ -z "$csv_path" ]]; then
    log_error "__append_result_to_csv: REPORT_STATS not initialized"
    return $EC_FAILURE
  fi

  # Build CSV row
  local csv_row="${_csv_result_ref[test_name]:-unknown}"
  csv_row+=",${_csv_result_ref[test_type]:-unknown}"
  csv_row+=",${_csv_result_ref[exit_code]:-1}"
  csv_row+=",${_csv_result_ref[duration_seconds]:-0}"
  csv_row+=",${_csv_result_ref[timestamp]:-$(date +%Y-%m-%dT%H:%M:%S%z)}"
  csv_row+=",${_csv_result_ref[assertions_passed]:-0}"
  csv_row+=",${_csv_result_ref[assertions_failed]:-0}"
  csv_row+=",${_csv_result_ref[assertions_total]:-0}"

  # Append with file locking for parallel safety
  # flock ensures only one process writes at a time
  (
    flock -x 200
    echo "$csv_row" >> "$csv_path"
  ) 200>> "$csv_path.lock" || {
    log_warning "Failed to acquire lock for CSV write, attempting direct write"
    echo "$csv_row" >> "$csv_path"
  }

  return $EC_SUCCESS
}
export -f __append_result_to_csv

# ==============================================================================
# Result Recording Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Record a single test result
# ------------------------------------------------------------------------------
# Records the result to CSV, updates statistics, and optionally prints
# immediate feedback to console.
#
# Arguments:
#   $1 - result_array_name: Name of associative array with test result
#   $2 - print_immediate: "true" to print result now, "false" to defer (default: "true")
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function record_test_result() {
  local result_array_name="$1"
  local print_immediate="${2:-true}"

  # Append to CSV file
  __append_result_to_csv "$result_array_name"

  # Update aggregate statistics
  __update_aggregate_stats "$result_array_name"

  # Print immediate feedback if requested
  if [[ "$print_immediate" == "true" ]]; then
    print_test_result "$result_array_name"
  fi

  return $EC_SUCCESS
}
export -f record_test_result

# ------------------------------------------------------------------------------
# Update aggregate statistics from a single test result
# ------------------------------------------------------------------------------
# Increments the appropriate counters based on test exit code.
#
# Arguments:
#   $1 - result_array_name: Name of associative array with test result
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function __update_aggregate_stats() {
  local result_array_name="$1"
  local -n _stats_result_ref="$result_array_name"

  local exit_code="${_stats_result_ref[exit_code]:-1}"

  # Increment total tests
  REPORT_STATS[tests_total]=$((REPORT_STATS[tests_total] + 1))

  # Increment status-specific counter
  case "$exit_code" in
    "$EC_SUCCESS" | 0)
      REPORT_STATS[tests_passed]=$((REPORT_STATS[tests_passed] + 1))
      ;;
    "$EC_SKIP" | 33)
      REPORT_STATS[tests_skipped]=$((REPORT_STATS[tests_skipped] + 1))
      ;;
    2)
      # EC_ERROR = 2 (internal error during test execution)
      REPORT_STATS[tests_errors]=$((REPORT_STATS[tests_errors] + 1))
      ;;
    *)
      REPORT_STATS[tests_failed]=$((REPORT_STATS[tests_failed] + 1))
      ;;
  esac

  # Increment assertion counters
  local passed="${_stats_result_ref[assertions_passed]:-0}"
  local failed="${_stats_result_ref[assertions_failed]:-0}"
  local total="${_stats_result_ref[assertions_total]:-0}"

  REPORT_STATS[assertions_passed]=$((REPORT_STATS[assertions_passed] + passed))
  REPORT_STATS[assertions_failed]=$((REPORT_STATS[assertions_failed] + failed))
  REPORT_STATS[assertions_total]=$((REPORT_STATS[assertions_total] + total))

  return $EC_SUCCESS
}
export -f __update_aggregate_stats

# ==============================================================================
# Batch Aggregation Functions (Parallel-Safe)
# ==============================================================================

# ------------------------------------------------------------------------------
# Aggregate results from compound-key results array to CSV
# ------------------------------------------------------------------------------
# Writes test results to CSV file. Statistics are calculated from CSV at
# summary time (single source of truth pattern).
#
# Arguments:
#   $1 - results_array_name: Name of associative array with compound keys
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Side effects: Appends results to CSV file
# ------------------------------------------------------------------------------
function aggregate_results() {
  local results_array_name="$1"
  local -n _agg_results_ref="$results_array_name"

  # Extract unique test names from compound keys and write to CSV
  local -A seen_tests=()
  local test_name key
  local count=0

  for key in "${!_agg_results_ref[@]}"; do
    # Extract test_name from compound key: "test_name__field"
    test_name="${key%%__*}"

    # Skip if already processed this test
    [[ -n "${seen_tests[$test_name]:-}" ]] && continue
    seen_tests[$test_name]=1

    # Write to CSV (single source of truth)
    declare -A _agg_single_result=(
       [test_name]="$test_name"
       [test_type]="${_agg_results_ref[${test_name}__test_type]:-unknown}"
       [exit_code]="${_agg_results_ref[${test_name}__exit_code]:-1}"
       [duration_seconds]="${_agg_results_ref[${test_name}__duration_seconds]:-0}"
       [timestamp]="${_agg_results_ref[${test_name}__timestamp]:-}"
       [assertions_passed]="${_agg_results_ref[${test_name}__assertions_passed]:-0}"
       [assertions_failed]="${_agg_results_ref[${test_name}__assertions_failed]:-0}"
       [assertions_total]="${_agg_results_ref[${test_name}__assertions_total]:-0}"
    )
    __append_result_to_csv _agg_single_result
    count=$((count + 1))
  done

  log_debug "Wrote $count test results to CSV"
  return $EC_SUCCESS
}
export -f aggregate_results

# ------------------------------------------------------------------------------
# Record filtered test count (tests not run due to patterns/config)
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - count: Number of tests filtered
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function record_filtered_tests() {
  local count="${1:-0}"
  REPORT_STATS[tests_filtered]=$((REPORT_STATS[tests_filtered] + count))
  return $EC_SUCCESS
}
export -f record_filtered_tests

# ==============================================================================
# Console Output Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Print test execution plan (discovered tests grouped by type)
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - test_types_array_name: Name of array with test types to run
# Returns:
#   Exit code: EC_SUCCESS (0)
# Output:
#   Formatted test plan to stdout
# ------------------------------------------------------------------------------
function print_test_plan() {
  local test_types_array_name="$1"
  local -n _plan_types_ref="$test_types_array_name"

  printf "\n"
  printf "${COLOR_BOLD}TEST EXECUTION PLAN${COLOR_RESET}\n"
  printf "${COLOR_BOLD}%s${COLOR_RESET}\n" "$(printf '=%.0s' {1..60})"

  local total_count=0
  for test_type in "${_plan_types_ref[@]}"; do
    local tests
    mapfile -t tests < <(discover_tests "$test_type" 2>/dev/null)

    # Filter tests based on skip conditions
    local filtered_count=0
    for test_file in "${tests[@]}"; do
      if should_run_test "$test_file"; then
        filtered_count=$((filtered_count + 1))
      fi
    done

    if [[ ${#tests[@]} -gt 0 ]]; then
      printf "${COLOR_BOLD}%s tests:${COLOR_RESET} %d discovered" "${test_type^}" "${#tests[@]}"
      if [[ $filtered_count -ne ${#tests[@]} ]]; then
        printf " (${COLOR_WARNING}%d will run${COLOR_RESET})" "$filtered_count"
      fi
      printf "\n"
      total_count=$((total_count + filtered_count))
    fi
  done

  printf "\n${COLOR_BOLD}Total tests to execute: %d${COLOR_RESET}\n" "$total_count"
  printf "${COLOR_BOLD}%s${COLOR_RESET}\n" "$(printf '=%.0s' {1..60})"

  return $EC_SUCCESS
}
export -f print_test_plan

# ------------------------------------------------------------------------------
# Print a single test result to console with color formatting
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - result_array_name: Name of associative array with test result
# Returns:
#   Exit code: EC_SUCCESS (0)
# Output:
#   Colored test result line to stdout
# Format:
#   ✓ test_name (15 assertions, 3s) - for pass
#   ✗ test_name (14/15 assertions, 3s) - for fail
#   ⊘ test_name (skipped) - for skip
# ------------------------------------------------------------------------------
function print_test_result() {
  local result_array_name="$1"
  local -n _print_result_ref="$result_array_name"

  local test_name="${_print_result_ref[test_name]:-unknown}"
  local exit_code="${_print_result_ref[exit_code]:-1}"
  local duration_ms="${_print_result_ref[duration_seconds]:-0}"  # Note: field name kept for compatibility
  local assertions_passed="${_print_result_ref[assertions_passed]:-0}"
  local assertions_failed="${_print_result_ref[assertions_failed]:-0}"
  local assertions_total="${_print_result_ref[assertions_total]:-0}"

  # Format duration for display
  local duration_formatted
  duration_formatted=$(__format_duration "$duration_ms")

  local symbol color message

  case "$exit_code" in
    "$EC_SUCCESS" | 0)
      symbol="✓"
      color="${COLOR_SUCCESS}"
      if [[ "$assertions_total" -gt 0 ]]; then
        message="$test_name (${assertions_total} assertions, ${duration_formatted})"
      else
        message="$test_name (${duration_formatted})"
      fi
      ;;
    "$EC_SKIP" | 33)
      symbol="⊘"
      color="${COLOR_WARNING}"
      message="$test_name (skipped)"
      ;;
    2)
      symbol="⚠"
      color="${COLOR_WARNING}"
      message="$test_name (error, ${duration_formatted})"
      ;;
    *)
      symbol="✗"
      color="${COLOR_FAILURE}"
      if [[ "$assertions_total" -gt 0 ]]; then
        message="$test_name (${assertions_passed}/${assertions_total} assertions passed, ${duration_formatted})"
      else
        message="$test_name (${duration_formatted})"
      fi
      ;;
  esac

  # Print colored output to console
  printf "${color}%s %s${COLOR_RESET}\n" "$symbol" "$message"

  return $EC_SUCCESS
}
export -f print_test_result

# ------------------------------------------------------------------------------
# Print all results from compound-key results array
# ------------------------------------------------------------------------------
# Used after parallel execution to display all results at once.
#
# Arguments:
#   $1 - results_array_name: Name of associative array with compound keys
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function print_all_results() {
  local results_array_name="$1"
  local -n _print_all_ref="$results_array_name"

  # Extract unique test names
  local -A seen_tests=()
  local test_names=()
  local key test_name

  for key in "${!_print_all_ref[@]}"; do
    test_name="${key%%__*}"
    if [[ -z "${seen_tests[$test_name]:-}" ]]; then
      seen_tests[$test_name]=1
      test_names+=("$test_name")
    fi
  done

  # Sort test names for consistent output
  local sorted_names
  IFS=$'\n' sorted_names=($(sort <<< "${test_names[*]}"))
  unset IFS

  # Print each result
  for test_name in "${sorted_names[@]}"; do
    declare -A _print_single_result=(
       [test_name]="$test_name"
       [test_type]="${_print_all_ref[${test_name}__test_type]:-unknown}"
       [exit_code]="${_print_all_ref[${test_name}__exit_code]:-1}"
       [duration_seconds]="${_print_all_ref[${test_name}__duration_seconds]:-0}"
       [assertions_passed]="${_print_all_ref[${test_name}__assertions_passed]:-0}"
       [assertions_failed]="${_print_all_ref[${test_name}__assertions_failed]:-0}"
       [assertions_total]="${_print_all_ref[${test_name}__assertions_total]:-0}"
    )
    print_test_result _print_single_result
  done

  return $EC_SUCCESS
}
export -f print_all_results

# ------------------------------------------------------------------------------
# Print all test results from CSV file, grouped by test type
# ------------------------------------------------------------------------------
# Reads the CSV file (single source of truth) and displays formatted results
# organized by test type (unit, integration, e2e).
#
# Arguments: None (reads from REPORT_STATS[results_csv_path])
# Returns:
#   Exit code: EC_SUCCESS (0)
# Output:
#   Formatted test results to stdout
# ------------------------------------------------------------------------------
function print_all_results_from_csv() {
  local csv_path="${REPORT_STATS[results_csv_path]:-}"

  printf "\n"
  printf "${COLOR_BOLD}TEST RESULTS${COLOR_RESET}\n"
  printf "${COLOR_BOLD}%s${COLOR_RESET}\n\n" "$(printf '=%.0s' {1..60})"

  # Group results by test type
  declare -A results_by_type=()
  local test_types_found=()

  # Callback function to collect results by type
  # shellcheck disable=SC2329
  function __collect_result() {
    local test_name="$1" test_type="$2" exit_code="$3" duration="$4"
    local timestamp="$5" a_passed="$6" a_failed="$7" a_total="$8"

    # Track test types we've seen
    if [[ ! " ${test_types_found[*]} " =~ " ${test_type} " ]]; then
      test_types_found+=("$test_type")
    fi

    # Store result
    local key="${test_type}::${test_name}"
    results_by_type["${key}::test_name"]="$test_name"
    results_by_type["${key}::test_type"]="$test_type"
    results_by_type["${key}::exit_code"]="$exit_code"
    results_by_type["${key}::duration"]="$duration"
    results_by_type["${key}::assertions_passed"]="$a_passed"
    results_by_type["${key}::assertions_failed"]="$a_failed"
    results_by_type["${key}::assertions_total"]="$a_total"
  }

  # Read CSV and organize by type using shared helper
  __foreach_csv_line "$csv_path" __collect_result

  # Print results grouped by type (in order: unit, integration, e2e)
  local ordered_types=("unit" "integration" "e2e")
  for test_type in "${ordered_types[@]}"; do
    # Skip if this type wasn't found
    [[ ! " ${test_types_found[*]} " =~ " ${test_type} " ]] && continue

    printf "${COLOR_BOLD}%s tests:${COLOR_RESET}\n" "${test_type^}"

    # Get all tests of this type and sort them
    local type_tests=()
    for key in "${!results_by_type[@]}"; do
      if [[ "$key" =~ ^${test_type}::(.+)::test_name$ ]]; then
        type_tests+=("${BASH_REMATCH[1]}")
      fi
    done

    # Sort test names
    IFS=$'\n' type_tests=($(sort <<< "${type_tests[*]}"))
    unset IFS

    # Print each test result
    for test_name in "${type_tests[@]}"; do
      local key="${test_type}::${test_name}"
      declare -A _csv_result=(
        [test_name]="${results_by_type[${key}::test_name]}"
        [test_type]="${results_by_type[${key}::test_type]}"
        [exit_code]="${results_by_type[${key}::exit_code]}"
        [duration_seconds]="${results_by_type[${key}::duration]}"
        [assertions_passed]="${results_by_type[${key}::assertions_passed]}"
        [assertions_failed]="${results_by_type[${key}::assertions_failed]}"
        [assertions_total]="${results_by_type[${key}::assertions_total]}"
      )
      print_test_result _csv_result
    done

    printf "\n"
  done

  return $EC_SUCCESS
}
export -f print_all_results_from_csv

# ==============================================================================
# CSV Parsing Helper Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Iterate over CSV lines and invoke callback for each valid row
# ------------------------------------------------------------------------------
# Handles CSV reading boilerplate: file reading, header skipping, empty line
# handling. Invokes callback function for each valid data row.
#
# Arguments:
#   $1 - csv_path: Path to CSV file
#   $2 - callback: Function name to invoke for each row
#        Callback receives: test_name test_type exit_code duration timestamp a_passed a_failed a_total
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
# ------------------------------------------------------------------------------
function __foreach_csv_line() {
  local csv_path="$1"
  local callback="$2"

  if [[ ! -f "$csv_path" ]]; then
    log_debug "CSV file not found: $csv_path"
    return $EC_SUCCESS
  fi

  # Read CSV line by line and invoke callback for each valid row
  while IFS=',' read -r test_name test_type exit_code duration_ms timestamp a_passed a_failed a_total; do
    # Skip header row
    [[ "$test_name" == "test_name" ]] && continue
    # Skip empty lines
    [[ -z "$test_name" ]] && continue

    # Invoke callback with parsed fields
    "$callback" "$test_name" "$test_type" "$exit_code" "$duration_ms" "$timestamp" "$a_passed" "$a_failed" "$a_total"
  done < "$csv_path"

  return $EC_SUCCESS
}
export -f __foreach_csv_line

# ------------------------------------------------------------------------------
# Get slowest N tests from CSV
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - csv_path: Path to CSV file
#   $2 - count: Number of slowest tests to return (default: 3)
# Returns:
#   Stdout: Lines in format "test_name,duration_ms"
# ------------------------------------------------------------------------------
function __get_slowest_tests() {
  local csv_path="$1"
  local count="${2:-3}"

  if [[ ! -f "$csv_path" ]]; then
    return $EC_SUCCESS
  fi

  # Skip header, sort by duration_ms (column 4) descending, take top N
  tail -n +2 "$csv_path" | sort -t',' -k4 -n -r | head -n "$count" | cut -d',' -f1,4
}
export -f __get_slowest_tests

# ------------------------------------------------------------------------------
# Get failure breakdown by test type
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - csv_path: Path to CSV file
# Returns:
#   Stdout: "unit_failed integration_failed e2e_failed unit_total integration_total e2e_total"
# ------------------------------------------------------------------------------
function __get_failure_breakdown_by_type() {
  local csv_path="$1"

  local -i unit_failed=0 integration_failed=0 e2e_failed=0
  local -i unit_total=0 integration_total=0 e2e_total=0

  # Callback to count failures per type
  function __count_by_type() {
    local test_name="$1" test_type="$2" exit_code="$3"

    case "$test_type" in
      unit)
        unit_total=$((unit_total + 1))
        [[ "$exit_code" == "1" ]] && unit_failed=$((unit_failed + 1))
        ;;
      integration)
        integration_total=$((integration_total + 1))
        [[ "$exit_code" == "1" ]] && integration_failed=$((integration_failed + 1))
        ;;
      e2e)
        e2e_total=$((e2e_total + 1))
        [[ "$exit_code" == "1" ]] && e2e_failed=$((e2e_failed + 1))
        ;;
    esac
  }

  __foreach_csv_line "$csv_path" __count_by_type
  echo "$unit_failed $integration_failed $e2e_failed $unit_total $integration_total $e2e_total"
}
export -f __get_failure_breakdown_by_type

# ------------------------------------------------------------------------------
# Get latest results CSV path
# ------------------------------------------------------------------------------
# Returns:
#   Stdout: Path to the most recent results.csv (via 'latest' symlink)
#   Exit code: EC_SUCCESS if found, EC_FAILURE if not
# ------------------------------------------------------------------------------
function get_latest_results_csv() {
  local latest_csv="${TEST_LATEST_LINK}/results.csv"
  
  if [[ ! -L "$TEST_LATEST_LINK" ]]; then
    log_error "No previous test results found (latest symlink missing)"
    return $EC_FAILURE
  fi
  
  if [[ ! -f "$latest_csv" ]]; then
    log_error "Latest results.csv not found at: $latest_csv"
    return $EC_FAILURE
  fi
  
  echo "$latest_csv"
  return $EC_SUCCESS
}
export -f get_latest_results_csv

# ------------------------------------------------------------------------------
# Get failed test names from CSV
# ------------------------------------------------------------------------------
# Extracts test names where exit_code != 0 and exit_code != 33 (skip)
# Arguments:
#   $1 - csv_path: Path to CSV file
# Returns:
#   Stdout: Space-separated list of failed test names
#   Exit code: EC_SUCCESS
# ------------------------------------------------------------------------------
function get_failed_tests_from_csv() {
  local csv_path="$1"
  
  if [[ ! -f "$csv_path" ]]; then
    log_error "CSV file not found: $csv_path"
    return $EC_FAILURE
  fi
  
  # Parse CSV: skip header, filter for failures (exit_code != 0 and != 33)
  local failed_tests
  failed_tests=$(tail -n +2 "$csv_path" | awk -F',' '$3 != 0 && $3 != 33 {print $1}')
  
  echo "$failed_tests"
  return $EC_SUCCESS
}
export -f get_failed_tests_from_csv

# ------------------------------------------------------------------------------
# Get tests with highest failure rates (≥25%)
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - csv_path: Path to CSV file
# Returns:
#   Stdout: Lines in format "test_name,failure_rate,assertions_failed,assertions_total"
# ------------------------------------------------------------------------------
function __get_highest_failure_rates() {
  local csv_path="$1"

  if [[ ! -f "$csv_path" ]]; then
    return $EC_SUCCESS
  fi

  # Skip header, calculate failure rate, filter ≥25%, sort by rate descending
  tail -n +2 "$csv_path" | awk -F',' '
    {
      if ($8 > 0) {
        rate = $7 / $8
        if (rate >= 0.25) {
          printf "%s,%.0f,%d,%d\n", $1, rate*100, $7, $8
        }
      }
    }
  ' | sort -t',' -k2 -n -r
}
export -f __get_highest_failure_rates

# ------------------------------------------------------------------------------
# Get environment information
# ------------------------------------------------------------------------------
# Returns:
#   Stdout: "os_name|kernel_version|bash_version|kgsm_version|framework_version"
# ------------------------------------------------------------------------------
function __get_environment_info() {
  local os_name
  local kernel_version
  local bash_version="${BASH_VERSION}"
  local kgsm_version="unknown"
  local framework_version="${TEST_FRAMEWORK_VERSION}"

  # Get OS information
  os_name=$(uname -s 2>/dev/null || echo "unknown")
  kernel_version=$(uname -r 2>/dev/null || echo "unknown")

  # Get KGSM version from .kgsm.version file
  if [[ -n "${KGSM_ROOT:-}" && -f "${KGSM_ROOT}/.kgsm.version" ]]; then
    kgsm_version=$(cat "${KGSM_ROOT}/.kgsm.version" 2>/dev/null || echo "unknown")
  fi

  echo "${os_name}|${kernel_version}|${bash_version}|${kgsm_version}|${framework_version}"
}
export -f __get_environment_info

# ==============================================================================
# Summary Generation Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Finalize timing and calculate total runtime
# ------------------------------------------------------------------------------
# Must be called at the end of a test run to record end time and calculate
# total runtime.
#
# Arguments: None
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function finalize_reporting() {
  REPORT_STATS[end_time]="$(date +%s%3N)"

  local start="${REPORT_STATS[start_time]:-$(date +%s%3N)}"
  local end="${REPORT_STATS[end_time]}"

  REPORT_STATS[total_runtime_seconds]=$((end - start))  # Note: field name kept for compatibility, but stores milliseconds

  return $EC_SUCCESS
}
export -f finalize_reporting

# ------------------------------------------------------------------------------
# Read statistics from CSV file (single source of truth)
# ------------------------------------------------------------------------------
# Parses the results CSV file and calculates totals. This ensures the summary
# always reflects exactly what was recorded, eliminating drift between
# in-memory counters and persisted results.
#
# Arguments: None (reads from REPORT_STATS[results_csv_path])
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Side effects: Updates REPORT_STATS with values calculated from CSV
# ------------------------------------------------------------------------------
function __read_stats_from_csv() {
  local csv_path="${REPORT_STATS[results_csv_path]:-}"

  # Initialize counters (use local scope to avoid pollution)
  local -i total=0 passed=0 failed=0 skipped=0 errors=0
  local -i assert_total=0 assert_passed=0 assert_failed=0

  # Callback function to process each CSV line
  # shellcheck disable=SC2329
  function __count_stats() {
    local test_name="$1" test_type="$2" exit_code="$3" duration="$4"
    local timestamp="$5" a_passed="$6" a_failed="$7" a_total="$8"

    total=$((total + 1))

    # Categorize by exit code
    case "$exit_code" in
      0)  passed=$((passed + 1)) ;;
      33) skipped=$((skipped + 1)) ;;
      2)  errors=$((errors + 1)) ;;
      *)  failed=$((failed + 1)) ;;
    esac

    # Accumulate assertion counts
    assert_passed=$((assert_passed + ${a_passed:-0}))
    assert_failed=$((assert_failed + ${a_failed:-0}))
    assert_total=$((assert_total + ${a_total:-0}))
  }

  # Iterate over CSV using shared helper
  __foreach_csv_line "$csv_path" __count_stats

  # Update REPORT_STATS with CSV-derived values
  REPORT_STATS[tests_total]=$total
  REPORT_STATS[tests_passed]=$passed
  REPORT_STATS[tests_failed]=$failed
  REPORT_STATS[tests_skipped]=$skipped
  REPORT_STATS[tests_errors]=$errors
  REPORT_STATS[assertions_total]=$assert_total
  REPORT_STATS[assertions_passed]=$assert_passed
  REPORT_STATS[assertions_failed]=$assert_failed

  log_debug "CSV stats: $total tests ($passed passed, $failed failed, $skipped skipped)"
  return $EC_SUCCESS
}
export -f __read_stats_from_csv

# ------------------------------------------------------------------------------
# Generate and display the final test summary
# ------------------------------------------------------------------------------
# Reads statistics from CSV file (single source of truth) and prints
# a formatted summary to console and file.
#
# Arguments: None (reads from CSV via REPORT_STATS[results_csv_path])
# Returns:
#   Exit code: EC_SUCCESS (0) if all tests passed, EC_FAILURE (1) if any failed
# Output:
#   Formatted summary to stdout (colored)
#   Plain text summary to $REPORT_STATS[summary_path]
# ------------------------------------------------------------------------------
function generate_summary() {
  # Ensure timing is finalized
  finalize_reporting

  # Read statistics from CSV (single source of truth)
  __read_stats_from_csv

  local total="${REPORT_STATS[tests_total]:-0}"
  local passed="${REPORT_STATS[tests_passed]:-0}"
  local failed="${REPORT_STATS[tests_failed]:-0}"
  local skipped="${REPORT_STATS[tests_skipped]:-0}"
  local errors="${REPORT_STATS[tests_errors]:-0}"
  local filtered="${REPORT_STATS[tests_filtered]:-0}"

  local assert_total="${REPORT_STATS[assertions_total]:-0}"
  local assert_passed="${REPORT_STATS[assertions_passed]:-0}"
  local assert_failed="${REPORT_STATS[assertions_failed]:-0}"

  local runtime="${REPORT_STATS[total_runtime_seconds]:-0}"
  local csv_path="${REPORT_STATS[results_csv_path]:-}"
  local log_dir="${REPORT_STATS[log_dir]:-}"
  local summary_path="${REPORT_STATS[summary_path]:-}"

  # Collect enhanced statistics
  local slowest_tests failure_breakdown env_info highest_failures
  slowest_tests=$(__get_slowest_tests "$csv_path" 3)
  failure_breakdown=$(__get_failure_breakdown_by_type "$csv_path")
  env_info=$(__get_environment_info)
  highest_failures=$(__get_highest_failure_rates "$csv_path")

  # Get execution mode details
  local exec_mode="sequential"
  local parallel_jobs="1"
  if [[ "${TEST_PARALLEL:-1}" -gt 1 ]]; then
    exec_mode="parallel"
    parallel_jobs="${TEST_PARALLEL}"
  fi

  # Build summary separator
  local separator
  separator=$(printf '=%.0s' {1..60})

  # Print to console (colored)
  __print_summary_console "$separator" "$total" "$passed" "$failed" "$skipped" \
    "$errors" "$filtered" "$assert_total" "$assert_passed" "$assert_failed" \
    "$runtime" "$csv_path" "$log_dir" "$slowest_tests" "$failure_breakdown" \
    "$env_info" "$exec_mode" "$parallel_jobs" "$highest_failures"

  # Write to file (plain text)
  if [[ -n "$summary_path" ]]; then
    __write_summary_file "$summary_path" "$separator" "$total" "$passed" "$failed" \
      "$skipped" "$errors" "$filtered" "$assert_total" "$assert_passed" \
      "$assert_failed" "$runtime" "$csv_path" "$log_dir" "$slowest_tests" \
      "$failure_breakdown" "$env_info" "$exec_mode" "$parallel_jobs" "$highest_failures"
  fi

  # Return failure if any tests failed
  if [[ "$failed" -gt 0 ]] || [[ "$errors" -gt 0 ]]; then
    return $EC_FAILURE
  fi

  return $EC_SUCCESS
}
export -f generate_summary

# ------------------------------------------------------------------------------
# Print colored summary to console
# ------------------------------------------------------------------------------
function __print_summary_console() {
  local separator="$1"
  local total="$2" passed="$3" failed="$4" skipped="$5"
  local errors="$6" filtered="$7"
  local assert_total="$8" assert_passed="$9" assert_failed="${10}"
  local runtime="${11}" csv_path="${12}" log_dir="${13}"
  local slowest_tests="${14}" failure_breakdown="${15}" env_info="${16}"
  local exec_mode="${17}" parallel_jobs="${18}" highest_failures="${19}"

  printf "\n"
  printf "${COLOR_BOLD}%s${COLOR_RESET}\n" "$separator"
  printf "${COLOR_BOLD}TEST SUMMARY - %s${COLOR_RESET}\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf "${COLOR_BOLD}%s${COLOR_RESET}\n" "$separator"

  # Tests line
  printf "%-20s %s total (" "Tests:" "$total"
  printf "${COLOR_SUCCESS}%s passed${COLOR_RESET}, " "$passed"
  printf "${COLOR_FAILURE}%s failed${COLOR_RESET}, " "$failed"
  printf "${COLOR_WARNING}%s skipped${COLOR_RESET}" "$skipped"
  if [[ "$errors" -gt 0 ]]; then
    printf ", ${COLOR_WARNING}%s errors${COLOR_RESET}" "$errors"
  fi
  printf ")\n"

  # Failure breakdown by type (only if failures exist)
  if [[ "$failed" -gt 0 && -n "$failure_breakdown" ]]; then
    read -r unit_failed integration_failed e2e_failed unit_total integration_total e2e_total <<< "$failure_breakdown"
    if [[ $unit_total -gt 0 ]]; then
      printf "  %-18s ${COLOR_FAILURE}%s${COLOR_RESET}/%s unit\n" "" "$unit_failed" "$unit_total"
    fi
    if [[ $integration_total -gt 0 ]]; then
      printf "  %-18s ${COLOR_FAILURE}%s${COLOR_RESET}/%s integration\n" "" "$integration_failed" "$integration_total"
    fi
    if [[ $e2e_total -gt 0 ]]; then
      printf "  %-18s ${COLOR_FAILURE}%s${COLOR_RESET}/%s e2e\n" "" "$e2e_failed" "$e2e_total"
    fi
  fi

  # Filtered line (if any)
  if [[ "$filtered" -gt 0 ]]; then
    printf "%-20s ${COLOR_DEBUG}%s (config/pattern)${COLOR_RESET}\n" "Filtered:" "$filtered"
  fi

  # Assertions line
  printf "%-20s %s total (" "Assertions:" "$assert_total"
  printf "${COLOR_SUCCESS}%s passed${COLOR_RESET}, " "$assert_passed"
  printf "${COLOR_FAILURE}%s failed${COLOR_RESET})\n" "$assert_failed"

  # Pass rate (based on assertions, not tests)
  if [[ "$assert_total" -gt 0 ]]; then
    local pass_rate=$((assert_passed * 100 / assert_total))
    printf "%-20s %d%%\n" "Pass rate:" "$pass_rate"
  fi

  # Runtime (format milliseconds for display)
  local runtime_formatted
  runtime_formatted=$(__format_duration "$runtime")
  printf "%-20s %s\n" "Runtime:" "$runtime_formatted"

  # Slowest tests
  if [[ -n "$slowest_tests" ]]; then
    printf "\n${COLOR_BOLD}Slowest tests:${COLOR_RESET}\n"
    while IFS=',' read -r test_name duration_ms; do
      [[ -z "$test_name" ]] && continue
      local duration_formatted
      duration_formatted=$(__format_duration "$duration_ms")
      printf "  ${COLOR_WARNING}%-40s${COLOR_RESET} %s\n" "$test_name" "$duration_formatted"
    done <<< "$slowest_tests"
  fi

  # Highest failure rates (only if failures exist)
  if [[ "$failed" -gt 0 && -n "$highest_failures" ]]; then
    printf "\n${COLOR_BOLD}Highest failure rates:${COLOR_RESET}\n"
    while IFS=',' read -r test_name failure_rate assertions_failed assertions_total; do
      [[ -z "$test_name" ]] && continue
      printf "  ${COLOR_FAILURE}%-40s${COLOR_RESET} %s%% (%s/%s assertions)\n" \
        "$test_name" "$failure_rate" "$assertions_failed" "$assertions_total"
    done <<< "$highest_failures"
  fi

  # File paths
  printf "\n"
  if [[ -n "$csv_path" && -f "$csv_path" ]]; then
    printf "%-20s %s\n" "Results file:" "$csv_path"
  fi

  printf "${COLOR_BOLD}%s${COLOR_RESET}\n" "$separator"
}
export -f __print_summary_console

# ------------------------------------------------------------------------------
# Write plain-text summary to file
# ------------------------------------------------------------------------------
function __write_summary_file() {
  local summary_path="$1"
  local separator="$2"
  local total="$3" passed="$4" failed="$5" skipped="$6"
  local errors="$7" filtered="$8"
  local assert_total="$9" assert_passed="${10}" assert_failed="${11}"
  local runtime="${12}" csv_path="${13}" log_dir="${14}"
  local slowest_tests="${15}" failure_breakdown="${16}" env_info="${17}"
  local exec_mode="${18}" parallel_jobs="${19}" highest_failures="${20}"

  {
    echo "$separator"
    echo "TEST SUMMARY"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "$separator"
    echo ""
    echo "Tests:       $total total ($passed passed, $failed failed, $skipped skipped, $errors errors)"

    # Failure breakdown by type
    if [[ "$failed" -gt 0 && -n "$failure_breakdown" ]]; then
      read -r unit_failed integration_failed e2e_failed unit_total integration_total e2e_total <<< "$failure_breakdown"
      [[ $unit_total -gt 0 ]] && echo "             $unit_failed/$unit_total unit"
      [[ $integration_total -gt 0 ]] && echo "             $integration_failed/$integration_total integration"
      [[ $e2e_total -gt 0 ]] && echo "             $e2e_failed/$e2e_total e2e"
    fi

    if [[ "$filtered" -gt 0 ]]; then
      echo "Filtered:    $filtered (config/pattern)"
    fi
    echo "Assertions:  $assert_total total ($assert_passed passed, $assert_failed failed)"

    # Pass rate (assertion-based)
    if [[ "$assert_total" -gt 0 ]]; then
      local pass_rate=$((assert_passed * 100 / assert_total))
      echo "Pass rate:   ${pass_rate}%"
    fi

    # Runtime
    local runtime_formatted
    runtime_formatted=$(__format_duration "$runtime")
    echo "Runtime:     $runtime_formatted"

    # Slowest tests
    if [[ -n "$slowest_tests" ]]; then
      echo ""
      echo "Slowest tests:"
      while IFS=',' read -r test_name duration_ms; do
        [[ -z "$test_name" ]] && continue
        local duration_formatted
        duration_formatted=$(__format_duration "$duration_ms")
        printf "  %-40s %s\n" "$test_name" "$duration_formatted"
      done <<< "$slowest_tests"
    fi

    # Highest failure rates
    if [[ "$failed" -gt 0 && -n "$highest_failures" ]]; then
      echo ""
      echo "Highest failure rates:"
      while IFS=',' read -r test_name failure_rate assertions_failed assertions_total; do
        [[ -z "$test_name" ]] && continue
        printf "  %-40s %s%% (%s/%s assertions)\n" \
          "$test_name" "$failure_rate" "$assertions_failed" "$assertions_total"
      done <<< "$highest_failures"
    fi

    echo ""
    if [[ -n "$csv_path" ]]; then
      echo "Results CSV: $csv_path"
    fi
    if [[ -n "$log_dir" ]]; then
      echo "Logs:        $log_dir"
    fi
    echo "$separator"
  } > "$summary_path" || {
    log_warning "Failed to write summary file: $summary_path"
    return $EC_FAILURE
  }

  return $EC_SUCCESS
}
export -f __write_summary_file

# ==============================================================================
# Accessor Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Get current statistics (for external access)
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - stat_name: Name of statistic to retrieve (e.g., "tests_passed")
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Stdout: Value of requested statistic
# ------------------------------------------------------------------------------
function get_stat() {
  local stat_name="$1"
  echo "${REPORT_STATS[$stat_name]:-0}"
}
export -f get_stat

# ------------------------------------------------------------------------------
# Get all statistics as formatted string (for debugging)
# ------------------------------------------------------------------------------
# Returns:
#   Stdout: Multi-line string with all statistics
# ------------------------------------------------------------------------------
function get_all_stats() {
  local key
  for key in "${!REPORT_STATS[@]}"; do
    echo "$key=${REPORT_STATS[$key]}"
  done | sort
}
export -f get_all_stats

# ------------------------------------------------------------------------------
# Check if any tests failed
# ------------------------------------------------------------------------------
# Returns:
#   Exit code: 0 if failures exist, 1 if no failures
# ------------------------------------------------------------------------------
function has_failures() {
  local failed="${REPORT_STATS[tests_failed]:-0}"
  local errors="${REPORT_STATS[tests_errors]:-0}"
  [[ "$failed" -gt 0 || "$errors" -gt 0 ]]
}
export -f has_failures

# ==============================================================================
# Legacy Compatibility Functions
# ==============================================================================

# Export legacy global variables for backward compatibility
# These mirror REPORT_STATS values for any scripts still using old variable names
# TODO: Remove in v2.0 after full migration
function __export_legacy_counters() {
  export TESTS_TOTAL="${REPORT_STATS[tests_total]:-0}"
  export TESTS_PASSED="${REPORT_STATS[tests_passed]:-0}"
  export TESTS_FAILED="${REPORT_STATS[tests_failed]:-0}"
  export TESTS_SKIPPED="${REPORT_STATS[tests_skipped]:-0}"
  export TESTS_ERRORS="${REPORT_STATS[tests_errors]:-0}"
  export TESTS_FILTERED="${REPORT_STATS[tests_filtered]:-0}"
  export GLOBAL_ASSERTIONS_TOTAL="${REPORT_STATS[assertions_total]:-0}"
  export GLOBAL_ASSERTIONS_PASSED="${REPORT_STATS[assertions_passed]:-0}"
  export GLOBAL_ASSERTIONS_FAILED="${REPORT_STATS[assertions_failed]:-0}"
}
export -f __export_legacy_counters

# ==============================================================================
# Module Initialization Complete
# ==============================================================================

declare -g TEST_REPORTING_LOADED=1
export TEST_REPORTING_LOADED
