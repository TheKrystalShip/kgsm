#!/usr/bin/env bash

# KGSM Test Framework - Main Test Runner
#
# Author: The Krystal Ship Team
# Version: 3.0
#
# This is a comprehensive testing framework for KGSM that provides:
# - Sandboxed environments for each test suite
# - Real code testing (no mocking)
# - Detailed logging and reporting
# - Colored console output
# - Debug capabilities
# - Test skip functionality
# - Modular design following SOLID principles

if [[ -n "${TEST_RUNNER_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
readonly TESTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export KGSM_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/bootstrap.sh" || {
  echo -e "\033[0;31mERROR: Failed to source bootstrap.sh\033[0m" >&2
  exit 1
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Print colored output
function print_color() {
  local color="$1"
  shift
  if [[ "$TEST_QUIET" != "true" ]]; then
    printf "${color}%s${NC}\n" "$*"
  fi
}

function print_info() { print_color "$BLUE" "[INFO] $*"; }
function print_success() { print_color "$GREEN" "[SUCCESS] $*"; }
function print_warning() { print_color "$YELLOW" "[WARNING] $*"; }
function print_error() { print_color "$RED" "[ERROR] $*"; }
function print_debug() { if [[ "$TEST_DEBUG" == "true" ]]; then print_color "$CYAN" "[DEBUG] $*"; fi; }

export -f print_color
export -f print_info
export -f print_success
export -f print_warning
export -f print_error
export -f print_debug

function run_test_suite() {
  local test_type="$1"

  local tests
  mapfile -t tests < <(discover_tests "$test_type")

  if [[ ${#tests[@]} -eq 0 ]]; then
    return 0
  fi

  # Filter tests based on skip conditions
  local filtered_tests=()
  for test_file in "${tests[@]}"; do
    if should_run_test "$test_file"; then
      filtered_tests+=("$test_file")
    fi
  done

  if [[ ${#filtered_tests[@]} -eq 0 ]]; then
    return 0
  fi

  # Show execution progress for this test type
  printf "\n${COLOR_BOLD}Running %d %s test(s):${NC}\n" "${#filtered_tests[@]}" "$test_type"

  # Print out the list of tests to be executed
  for test_file in "${filtered_tests[@]}"; do
    printf "  - %s\n" "$(basename "$test_file")"
  done

  # Delegate to execution module (handles sequential vs parallel internally)
  declare -A test_results
  execute_tests "$test_type" filtered_tests test_results

  # Aggregate results from execution into reporting module (writes to CSV)
  aggregate_results test_results
}

export -f run_test_suite

# =============================================================================
# LOG MANAGEMENT
# =============================================================================

function clean_old_logs() {
  local logs_dir="$TESTS_ROOT/logs"

  if [[ ! -d "$logs_dir" ]]; then
    print_info "No logs directory found"
    return 0
  fi

  print_info "Cleaning old test logs..."

  # Count current log directories (match new timestamp format YYYY-MM-DD_HH-MM-SS)
  local log_count=$(find "$logs_dir" -maxdepth 1 -type d -name "20*-*-*_*-*-*" | wc -l)

  if [[ $log_count -le 10 ]]; then
    print_info "Found $log_count log directories (keeping all, threshold is 10)"
    return 0
  fi

  # Remove all but the 10 most recent log directories
  find "$logs_dir" -maxdepth 1 -type d -name "20*-*-*_*-*-*" -printf '%T@ %p\n' \
                                                                                | sort -n | head -n -10 | cut -d' ' -f2- \
                                           | while IFS= read -r dir; do
      print_info "Removing old log directory: $(basename "$dir")"
      rm -rf "$dir"
    done

  local remaining=$(find "$logs_dir" -maxdepth 1 -type d -name "20*-*-*_*-*-*" | wc -l)
  print_success "Log cleanup complete. $remaining directories remaining."
}

export -f clean_old_logs

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function show_usage() {
  cat << EOF
KGSM Test Framework Runner

Usage: $(basename "$0") [OPTIONS] [TEST_TYPES...]

OPTIONS:
    -h, --help          Show this help message
    -l, --list          List available tests with status (no execution)
    -d, --debug         Enable debug mode (preserves sandboxes)
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress non-essential output
    -p, --parallel      Run tests in parallel (where possible)
    --clean-logs        Remove old test logs (keeps last 10)

FILTERING:
    --pattern REGEX     Only run tests matching pattern
    --exclude REGEX     Exclude tests matching pattern
    --failed [PATH]     Re-run tests that failed in the last run
                        (optionally specify explicit CSV path)

TEST TYPES:
    unit                Run unit tests
    integration         Run integration tests
    e2e                 Run end-to-end tests
    all                 Run all test types (default)

EXAMPLES:
    $(basename "$0")                    # Run all tests
    $(basename "$0") --list             # List all tests with status
    $(basename "$0") unit               # Run only unit tests
    $(basename "$0") --debug e2e        # Run e2e tests with debug
    $(basename "$0") --pattern "instance"  # Run tests matching "instance"
    $(basename "$0") --failed           # Re-run tests that failed last time
    $(basename "$0") --clean-logs       # Clean up old test logs

LOGS:
    Test logs are saved in tests/logs/ with timestamped directories.
    Use --clean-logs to remove old logs (keeps most recent 10).

EOF
}

export -f show_usage

function main() {
  export START_TIME="$(date +%s)"

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help)
        show_usage
        exit $EC_SUCCESS
        ;;
      -d | --debug)
        TEST_DEBUG=true
        ;;
      -v | --verbose)
        TEST_VERBOSE=true
        ;;
      -q | --quiet)
        TEST_QUIET=true
        ;;
      -p | --parallel)
        TEST_PARALLEL=true
        ;;
      --clean-logs)
        clean_old_logs
        exit $EC_SUCCESS
        ;;
      -l | --list)
        # List tests (delegate to discovery.sh list_tests function)
        shift
        list_tests "$@"
        exit $EC_SUCCESS
        ;;
      --pattern)
        shift
        TEST_PATTERNS+=("$1")
        ;;
      --exclude)
        shift
        TEST_EXCLUDE+=("$1")
        ;;
      --failed)
        # Check if next arg exists and doesn't start with '-'
        if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
          shift
          FAILED_CSV_PATH="$1"
        else
          # No path provided - use latest symlink
          FAILED_CSV_PATH="${TEST_LATEST_LINK}/results.csv"
        fi
        TEST_RERUN_FAILED=true
        ;;
      unit | integration | e2e)
        TEST_TYPES+=("$1")
        ;;
      all)
        TEST_TYPES=("unit" "integration" "e2e")
        ;;
      *)
        print_error "Unknown option: $1"
        show_usage
        exit $EC_ERROR
        ;;
    esac
    shift
  done

  # Default to all tests if none specified
  if [[ ${#TEST_TYPES[@]} -eq 0 ]]; then
    TEST_TYPES=("unit" "integration" "e2e")
  fi

  # Handle --failed flag: populate TEST_PATTERNS with failed test names
  if [[ "${TEST_RERUN_FAILED:-false}" == "true" ]]; then
    # If no explicit path provided, resolve via symlink
    if [[ "$FAILED_CSV_PATH" == "${TEST_LATEST_LINK}/results.csv" ]]; then
      FAILED_CSV_PATH="$(get_latest_results_csv)" || {
        print_error "Failed to find previous test results. Run tests at least once before using --failed."
        exit $EC_FAILURE
      }
    fi
    
    # Validate explicit path exists
    if [[ ! -f "$FAILED_CSV_PATH" ]]; then
      print_error "Results CSV not found: $FAILED_CSV_PATH"
      exit $EC_FAILURE
    fi
    
    # Get failed test names from CSV
    local failed_tests
    failed_tests="$(get_failed_tests_from_csv "$FAILED_CSV_PATH")" || exit $EC_FAILURE
    
    # Check if any tests failed
    if [[ -z "$failed_tests" ]]; then
      print_success "No failed tests found in previous run. All tests passed!"
      exit $EC_SUCCESS
    fi
    
    # Convert newline-separated list to array and add to TEST_PATTERNS
    while IFS= read -r test_name; do
      [[ -n "$test_name" ]] && TEST_PATTERNS+=("$test_name")
    done <<< "$failed_tests"
    
    print_info "Re-running $(echo "$failed_tests" | wc -l) failed test(s) from: $FAILED_CSV_PATH"
  fi

  # Initialize testing environment
  TEST_SANDBOX_ROOT="$(mktemp -d -t kgsm-test-sandbox-XXXXXX)"

  # Create timestamped log directory in project
  local timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  TEST_LOG_DIR="$TESTS_ROOT/logs/$timestamp"
  mkdir -p "$TEST_LOG_DIR"

  # Initialize reporting module (creates CSV file and sets up counters)
  init_reporting "$TEST_LOG_DIR"

  # Get environment information
  local env_info
  env_info=$(__get_environment_info)
  IFS='|' read -r os_name kernel_version bash_version kgsm_version framework_version <<< "$env_info"

  # Environment section
  print_color "$CYAN" "Environment:"
  print_color "$GRAY" "  OS:        $os_name $kernel_version"
  print_color "$GRAY" "  Bash:      $bash_version"
  print_color "$GRAY" "  KGSM:      $kgsm_version"
  print_color "$GRAY" "  Framework: $framework_version"

  # Execution section
  print_color "$CYAN" "Execution:"
  print_color "$GRAY" "  Mode:      $(get_active_executor)"
  if [[ "$(get_active_executor)" == "parallel" ]]; then
    print_color "$GRAY" "  Parallel:  ${TEST_PARALLEL:-1} jobs"
  fi
  if [[ -n "${TEST_PATTERNS:-}" ]]; then
    print_color "$GRAY" "  Patterns:  ${TEST_PATTERNS}"
  fi
  print_color "$GRAY" "  Sandbox:   $TEST_SANDBOX_ROOT"
  print_color "$GRAY" "  Logs:      $TEST_LOG_DIR"

  # Show test execution plan
  print_test_plan TEST_TYPES

  # Set up signal handlers for cleanup
  trap 'cleanup_all' EXIT INT TERM

  # Run test suites
  for test_type in "${TEST_TYPES[@]}"; do
    run_test_suite "$test_type"
  done

  # Display all results (read from CSV)
  print_all_results_from_csv

  # Generate final summary (uses reporting.sh module)
  generate_summary
  
  # Create/update 'latest' symlink for easy access to most recent run
  # Use -n flag to treat existing symlink-to-directory as a file
  ln -sfn "$TEST_LOG_DIR" "$TEST_LATEST_LINK"
}

function cleanup_all() {
  if [[ "$TEST_DEBUG" != "true" && -n "$TEST_SANDBOX_ROOT" ]]; then
    rm -rf "$TEST_SANDBOX_ROOT"
  fi
  # Note: TEST_LOG_DIR is kept in project directory for easy access
}

export -f cleanup_all

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

declare -g TEST_RUNNER_LOADED=1
export TEST_RUNNER_LOADED
