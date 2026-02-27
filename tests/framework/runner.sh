#!/usr/bin/env bash

# KGSM Test Framework - Main Test Runner
#
# Author: The Krystal Ship Team
# Version: 4.0
#
# Simplified runner that auto-discovers test functions, executes them
# in sandboxed environments, and generates TAP v14 output directly.

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

# =============================================================================
# TEST EXECUTION
# =============================================================================

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

  # Show execution progress
  if [[ "$TEST_QUIET" != "true" ]]; then
    printf "\n${COLOR_BOLD}Running %d %s test(s):${NC}\n" "${#filtered_tests[@]}" "$test_type"
    for test_file in "${filtered_tests[@]}"; do
      printf "  - %s\n" "$(basename "$test_file")"
    done
  fi

  # Execute each test sequentially
  for test_file in "${filtered_tests[@]}"; do
    local test_name
    test_name=$(basename "$test_file" .sh)

    # Create sandbox
    local sandbox_path
    if ! sandbox_path=$(create_sandbox "$test_type" "$test_name" 2>&1); then
      log_error "Failed to create sandbox for test: $test_name"
      ALL_RESULTS+=("${test_name}|${test_type}|2|0|0|0|0|0|")
      continue
    fi

    # Generate log file path
    local test_log="${TEST_LOG_DIR}/${test_name}.log"

    # Execute test in sandbox
    declare -A test_result
    execute_test_in_sandbox "$test_file" "$test_type" "$sandbox_path" "$test_log" test_result

    # Store result for TAP output
    ALL_RESULTS+=("${test_result[test_name]}|${test_result[test_type]}|${test_result[exit_code]}|${test_result[duration_seconds]}|${test_result[assertions_passed]}|${test_result[assertions_failed]}|${test_result[assertions_total]}|${test_result[functions_skipped]}|${test_result[test_log_path]}")

    # Cleanup sandbox for passing tests
    if [[ "${test_result[exit_code]}" -eq 0 ]]; then
      cleanup_sandbox "$sandbox_path" >/dev/null 2>&1 || true
    fi

    unset test_result
  done
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
  local log_count=$(find "$logs_dir" -maxdepth 1 -type d -name "20*-*-*_*-*-*" | wc -l)

  if [[ $log_count -le 10 ]]; then
    print_info "Found $log_count log directories (keeping all, threshold is 10)"
    return 0
  fi

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
    --list-json         List tests as JSON array (machine-readable)
    -d, --debug         Enable debug mode (preserves sandboxes)
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress non-essential output
    --tap               Output results in TAP version 14 format (stdout)
    --clean-logs        Remove old test logs (keeps last 10)

FILTERING:
    --pattern REGEX     Only run tests matching pattern
    --exclude REGEX     Exclude tests matching pattern
    --function NAME     Run only the specified function within matched tests
                        (setup_test is always called first)

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
    $(basename "$0") --tap unit         # Run unit tests with TAP output
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
        exit 0
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
      --tap)
        TEST_TAP_OUTPUT=true
        TEST_QUIET=true
        ;;
      --clean-logs)
        clean_old_logs
        exit 0
        ;;
      -l | --list)
        shift
        list_tests "$@"
        exit 0
        ;;
      --list-json)
        shift
        list_tests_json "$@"
        exit 0
        ;;
      --pattern)
        shift
        TEST_PATTERNS+=("$1")
        ;;
      --exclude)
        shift
        TEST_EXCLUDE+=("$1")
        ;;
      --function)
        shift
        export KGSM_TEST_FUNCTION_FILTER="$1"
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
        exit 1
        ;;
    esac
    shift
  done

  # Default to all tests if none specified
  if [[ ${#TEST_TYPES[@]} -eq 0 ]]; then
    TEST_TYPES=("unit" "integration" "e2e")
  fi

  # Initialize testing environment
  TEST_SANDBOX_ROOT="$(mktemp -d -t kgsm-test-sandbox-XXXXXX)"

  # Create timestamped log directory
  local timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  TEST_LOG_DIR="$TESTS_ROOT/logs/$timestamp"
  mkdir -p "$TEST_LOG_DIR"

  # Environment info
  print_color "$CYAN" "Environment:"
  print_color "$GRAY" "  KGSM:      $(cat "$KGSM_ROOT/VERSION" 2>/dev/null || echo 'unknown')"
  print_color "$GRAY" "  Sandbox:   $TEST_SANDBOX_ROOT"
  print_color "$GRAY" "  Logs:      $TEST_LOG_DIR"

  # Set up signal handlers for cleanup
  trap 'cleanup_all' EXIT INT TERM

  # Collect all results
  declare -ga ALL_RESULTS=()

  # Run test suites
  for test_type in "${TEST_TYPES[@]}"; do
    run_test_suite "$test_type"
  done

  # Generate output
  if [[ "${TEST_TAP_OUTPUT:-false}" == "true" ]]; then
    generate_tap_from_results
  else
    print_human_summary
  fi

  # Create/update 'latest' symlink
  ln -sfn "$TEST_LOG_DIR" "$TEST_LATEST_LINK"
}

# ---------------------------------------------------------------------------
# Generate TAP v14 output directly from collected results
# ---------------------------------------------------------------------------
function generate_tap_from_results() {
  local total=${#ALL_RESULTS[@]}
  echo "TAP version 14"
  echo "1..${total}"

  local test_num=0
  for result_line in "${ALL_RESULTS[@]}"; do
    ((test_num++))
    IFS='|' read -r test_name test_type exit_code duration passed failed total_asserts skipped log_path <<< "$result_line"

    if [[ "$exit_code" -eq 0 ]]; then
      echo "ok ${test_num} - ${test_name} [${test_type}] # ${total_asserts} assertions in ${duration}ms"
    else
      echo "not ok ${test_num} - ${test_name} [${test_type}]"
      echo "  ---"
      echo "  severity: fail"
      echo "  message: \"${failed}/${total_asserts} assertions failed\""
      echo "  exit_code: ${exit_code}"
      echo "  duration_ms: ${duration}"
      echo "  assertions_passed: ${passed}"
      echo "  assertions_failed: ${failed}"
      echo "  assertions_total: ${total_asserts}"
      if [[ "$skipped" -gt 0 ]]; then
        echo "  functions_skipped: ${skipped}"
      fi

      # Determine relative file path from test name
      local test_file=""
      for type_dir in unit integration e2e; do
        if [[ -f "$TESTS_ROOT/${type_dir}/${test_name}.sh" ]]; then
          test_file="tests/${type_dir}/${test_name}.sh"
          break
        fi
      done
      if [[ -n "$test_file" ]]; then
        echo "  file: \"${test_file}\""
      fi

      # Emit failure details from log file
      if [[ -n "$log_path" && -f "$log_path" ]]; then
        __tap_emit_failure_details "$log_path" "$test_file"
      fi

      echo "  ..."
    fi
  done

  # Return non-zero if any test failed
  for result_line in "${ALL_RESULTS[@]}"; do
    IFS='|' read -r _ _ exit_code _ <<< "$result_line"
    if [[ "$exit_code" -ne 0 ]]; then
      return 1
    fi
  done
  return 0
}

export -f generate_tap_from_results

# ---------------------------------------------------------------------------
# Print human-readable summary
# ---------------------------------------------------------------------------
function print_human_summary() {
  local total=${#ALL_RESULTS[@]}
  local passed_count=0
  local failed_count=0

  printf "\n${COLOR_BOLD}=== Test Results ===${NC}\n"

  for result_line in "${ALL_RESULTS[@]}"; do
    IFS='|' read -r test_name test_type exit_code duration pass fail total_asserts skipped _ <<< "$result_line"
    if [[ "$exit_code" -eq 0 ]]; then
      printf "  ${GREEN}✓${NC} %s [%s] (%s assertions, %sms)\n" "$test_name" "$test_type" "$total_asserts" "$duration"
      ((passed_count++))
    else
      printf "  ${RED}✗${NC} %s [%s] (%s/%s assertions failed, %sms)\n" "$test_name" "$test_type" "$fail" "$total_asserts" "$duration"
      ((failed_count++))
    fi
  done

  printf "\n${COLOR_BOLD}Summary:${NC} %d passed, %d failed, %d total\n" "$passed_count" "$failed_count" "$total"

  if [[ $failed_count -gt 0 ]]; then
    return 1
  fi
  return 0
}

export -f print_human_summary

function cleanup_all() {
  if [[ "$TEST_DEBUG" != "true" && -n "$TEST_SANDBOX_ROOT" ]]; then
    rm -rf "$TEST_SANDBOX_ROOT"
  fi
}

export -f cleanup_all

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

declare -g TEST_RUNNER_LOADED=1
export TEST_RUNNER_LOADED
