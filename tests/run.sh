#!/usr/bin/env bash

# KGSM Test Framework - VS Code Test Runner Integration
#
# Author: The Krystal Ship Team
# Version: 6.0
#
# VS Code Test Adapter entry point. Discovers tests, executes them
# in sandboxed environments, and outputs results in TAP v14 format.
# Not intended for standalone CLI use.

# =============================================================================
# SCRIPT SETUP
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FRAMEWORK_DIR="$SCRIPT_DIR/framework"
readonly TESTS_ROOT="$SCRIPT_DIR"
export KGSM_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"

# shellcheck disable=SC1091
source "$FRAMEWORK_DIR/bootstrap.sh" || {
  echo "Bail out! Failed to source bootstrap.sh" >&2
  exit 1
}

# =============================================================================
# TAP OUTPUT (streaming — results emitted immediately as tests complete)
# =============================================================================

# Global state for incremental TAP emission
declare -g TAP_TEST_NUM=0
declare -g TAP_HAS_FAILURES=0
declare -g TAP_BAIL_OUT=0

# Emit a single TAP result line to stdout immediately.
# Called inline after each test completes (sequential or parallel).
function _emit_tap_result() {
  local result_line="$1"
  ((TAP_TEST_NUM++))

  IFS='|' read -r test_name test_type exit_code duration passed failed total_asserts skipped log_path todo <<< "$result_line"

  # Default todo to 0 if not provided (backward compatibility)
  [[ -z "$todo" ]] && todo=0

  # Handle Bail out!
  if [[ "$exit_code" -eq 99 ]]; then
    local bail_reason=""
    if [[ -n "$log_path" && -f "$log_path" ]]; then
      bail_reason=$(grep "^KGSM_BAIL_OUT:" "$log_path" 2>/dev/null | sed 's/^KGSM_BAIL_OUT: //' | head -1 || true)
    fi
    echo "Bail out! ${bail_reason}"
    TAP_BAIL_OUT=1
    return 0
  fi

  # Emit subtests before parent line (TAP v14)
  if [[ -n "$log_path" && -f "$log_path" ]]; then
    local has_subtests
    has_subtests=$(grep -c "^KGSM_FUNC_RESULT:" "$log_path" 2>/dev/null || echo "0")
    if [[ "$has_subtests" -gt 0 ]]; then
      echo "# Subtest: ${test_name}"
      __tap_emit_subtests "$log_path"
    fi
  fi

  # Determine if failures are TODO-only (not real test failures)
  local is_todo_only=0
  if [[ "$exit_code" -ne 0 && "$todo" -gt 0 && -n "$log_path" && -f "$log_path" ]]; then
    local real_fail_count
    real_fail_count=$(grep -c "^KGSM_FUNC_RESULT:.*|fail$" "$log_path" 2>/dev/null || echo "0")
    [[ "$real_fail_count" == "0" ]] && is_todo_only=1
  fi

  if [[ "$exit_code" -eq 0 ]] || [[ "$is_todo_only" -eq 1 ]]; then
    echo "ok ${TAP_TEST_NUM} - ${test_name} [${test_type}] # ${total_asserts} assertions in ${duration}ms"
  else
    TAP_HAS_FAILURES=1
    echo "not ok ${TAP_TEST_NUM} - ${test_name} [${test_type}]"
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
    if [[ "$todo" -gt 0 ]]; then
      echo "  functions_todo: ${todo}"
    fi

    local test_file=""
    if [[ -f "$TESTS_ROOT/${test_type}/${test_name}.sh" ]]; then
      test_file="tests/${test_type}/${test_name}.sh"
    fi
    if [[ -n "$test_file" ]]; then
      echo "  file: \"${test_file}\""
    fi

    if [[ -n "$log_path" && -f "$log_path" ]]; then
      __tap_emit_failure_details "$log_path" "$test_file"
    fi

    echo "  ..."
  fi
}

export -f _emit_tap_result

# Count filtered tests for a given type (for TAP plan line).
function _count_filtered_tests() {
  local test_type="$1"
  local count=0
  local tests
  mapfile -t tests < <(discover_tests "$test_type")
  for test_file in "${tests[@]}"; do
    if should_run_test "$test_file"; then
      ((count++)) || true
    fi
  done
  echo "$count"
}

export -f _count_filtered_tests

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

  # Delegate to parallel or sequential execution
  if [[ "${TEST_PARALLEL:-1}" -gt 1 && ${#filtered_tests[@]} -gt 1 ]]; then
    _run_tests_parallel "$test_type" "${filtered_tests[@]}"
  else
    _run_tests_sequential "$test_type" "${filtered_tests[@]}"
  fi
}

export -f run_test_suite

function _run_tests_sequential() {
  local test_type="$1"
  shift
  local filtered_tests=("$@")

  for test_file in "${filtered_tests[@]}"; do
    local test_name
    test_name=$(basename "$test_file" .sh)

    local sandbox_path
    if ! sandbox_path=$(create_sandbox "$test_name" 2>&1); then
      log_error "Failed to create sandbox for test: $test_name"
      _emit_tap_result "${test_name}|${test_type}|2|0|0|0|0|0||0"
      continue
    fi

    local test_log="${TEST_LOG_DIR}/${test_name}.log"

    declare -A test_result
    execute_test_in_sandbox "$test_file" "$test_type" "$sandbox_path" "$test_log" test_result

    # Emit TAP result immediately
    _emit_tap_result "${test_result[test_name]}|${test_result[test_type]}|${test_result[exit_code]}|${test_result[duration_seconds]}|${test_result[assertions_passed]}|${test_result[assertions_failed]}|${test_result[assertions_total]}|${test_result[functions_skipped]}|${test_result[test_log_path]}|${test_result[functions_todo]}"

    # Stop on bail out
    if [[ "$TAP_BAIL_OUT" -eq 1 ]]; then
      break
    fi

    if [[ "${test_result[exit_code]}" -eq 0 ]]; then
      cleanup_sandbox "$sandbox_path" >/dev/null 2>&1 || true
    fi

    unset test_result
  done
}

export -f _run_tests_sequential

# Parallel execution with streaming result emission.
# Uses an event loop: launch jobs up to concurrency limit, poll for completed
# result files, and emit TAP lines as soon as each test finishes.
# Result files use atomic rename (.tmp -> .result) to prevent partial reads.
function _run_tests_parallel() {
  local test_type="$1"
  shift
  local filtered_tests=("$@")

  local max_jobs="${TEST_PARALLEL:-4}"
  local result_dir
  result_dir="$(mktemp -d -t kgsm-test-results-XXXXXX)"

  local -a active_pids=()
  local -a all_names=()
  local -A emitted=()
  local launch_idx=0
  local num_tests=${#filtered_tests[@]}

  # Event loop: launch jobs, poll for results, emit TAP
  while [[ ${#emitted[@]} -lt $num_tests ]]; do

    # 1. Emit any completed results
    for name in "${all_names[@]}"; do
      if [[ -z "${emitted[$name]:-}" && -f "${result_dir}/${name}.result" ]]; then
        declare -A _r=()
        __read_result_from_file "${result_dir}/${name}.result" "_r"
        _emit_tap_result "${_r[test_name]:-$name}|${_r[test_type]:-$test_type}|${_r[exit_code]:-2}|${_r[duration_seconds]:-0}|${_r[assertions_passed]:-0}|${_r[assertions_failed]:-0}|${_r[assertions_total]:-0}|${_r[functions_skipped]:-0}|${_r[test_log_path]:-}|${_r[functions_todo]:-0}"
        unset _r
        emitted[$name]=1
      fi
    done

    # 2. Prune finished PIDs
    local new_pids=()
    for pid in "${active_pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        new_pids+=("$pid")
      fi
    done
    active_pids=("${new_pids[@]}")

    # 3. Launch new jobs while under concurrency limit
    while [[ $launch_idx -lt $num_tests && ${#active_pids[@]} -lt $max_jobs ]]; do
      local test_file="${filtered_tests[$launch_idx]}"
      local test_name
      test_name=$(basename "$test_file" .sh)
      all_names+=("$test_name")
      local result_file="${result_dir}/${test_name}.result"

      (
        local sandbox_path
        if ! sandbox_path=$(create_sandbox "$test_name" 2>&1); then
          {
            echo "test_name=${test_name}"
            echo "test_type=${test_type}"
            echo "exit_code=2"
            echo "duration_seconds=0"
            echo "assertions_passed=0"
            echo "assertions_failed=0"
            echo "assertions_total=0"
            echo "functions_skipped=0"
            echo "functions_todo=0"
            echo "test_log_path="
          } > "${result_file}.tmp"
          mv "${result_file}.tmp" "$result_file"
          exit 2
        fi

        local test_log="${TEST_LOG_DIR}/${test_name}.log"

        declare -A test_result
        execute_test_in_sandbox "$test_file" "$test_type" "$sandbox_path" "$test_log" test_result

        # Atomic write: tmp then rename
        __write_result_to_file "test_result" "${result_file}.tmp"
        mv "${result_file}.tmp" "$result_file"

        if [[ "${test_result[exit_code]}" -eq 0 ]]; then
          cleanup_sandbox "$sandbox_path" >/dev/null 2>&1 || true
        fi
      ) &
      active_pids+=($!)
      ((launch_idx++))
    done

    # 4. If all jobs dead but results missing, emit errors for crashed jobs
    if [[ ${#active_pids[@]} -eq 0 && $launch_idx -ge $num_tests && ${#emitted[@]} -lt $num_tests ]]; then
      for name in "${all_names[@]}"; do
        if [[ -z "${emitted[$name]:-}" ]]; then
          _emit_tap_result "${name}|${test_type}|2|0|0|0|0|0||0"
          emitted[$name]=1
        fi
      done
      break
    fi

    # 5. Brief sleep before next poll iteration
    [[ ${#emitted[@]} -lt $num_tests ]] && sleep 0.2
  done

  # Reap zombie processes
  wait 2>/dev/null || true

  rm -rf "$result_dir" 2>/dev/null || true
}

export -f _run_tests_parallel

# =============================================================================
# DEBUG EXECUTION (inline, for interactive debuggers like bashdb)
# =============================================================================

function debug_run_test() {
  local test_file="$1"

  # Resolve to absolute path if relative
  if [[ "$test_file" != /* ]]; then
    test_file="$KGSM_ROOT/$test_file"
  fi

  if [[ ! -f "$test_file" ]]; then
    echo "[ERROR] Test file not found: $test_file" >&2
    return 1
  fi

  # Determine test type from path
  local test_type="unit"
  if [[ "$test_file" == *"/integration/"* ]]; then
    test_type="integration"
  elif [[ "$test_file" == *"/e2e/"* ]]; then
    test_type="e2e"
  fi

  local test_name
  test_name=$(basename "$test_file" .sh)

  # Create sandbox
  TEST_SANDBOX_ROOT="$(mktemp -d -t kgsm-debug-sandbox-XXXXXX)"
  export TEST_SANDBOX_ROOT

  local sandbox_path
  if ! sandbox_path=$(create_sandbox "$test_name" 2>&1); then
    echo "[ERROR] Failed to create sandbox for: $test_name" >&2
    rm -rf "$TEST_SANDBOX_ROOT" 2>/dev/null || true
    return 1
  fi

  local debug_log="/tmp/kgsm-debug-${test_name}-$$.log"

  # Setup environment (switches KGSM_ROOT to sandbox, loads modules)
  __setup_test_environment "$sandbox_path" "$debug_log"

  # Execute test inline — no subshell, so debugger can step through
  local exit_code=0
  __execute_test_inline "$test_file" || exit_code=$?

  # Cleanup sandbox
  rm -rf "$sandbox_path" 2>/dev/null || true
  rm -rf "$TEST_SANDBOX_ROOT" 2>/dev/null || true

  return $exit_code
}

export -f debug_run_test

# =============================================================================
# CLEANUP
# =============================================================================

function cleanup_all() {
  if [[ -n "${TEST_SANDBOX_ROOT:-}" ]]; then
    rm -rf "$TEST_SANDBOX_ROOT"
  fi
}

export -f cleanup_all

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function main() {
  export START_TIME="$(date +%s)"

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --list-json)
        shift
        list_tests_json "$@"
        exit 0
        ;;
      --pattern)
        shift
        TEST_PATTERNS+=("$1")
        ;;
      --function)
        shift
        export KGSM_TEST_FUNCTION_FILTER="$1"
        ;;
      --debug-run)
        shift
        DEBUG_RUN_FILE="$1"
        ;;
      unit | integration | e2e)
        TEST_TYPES+=("$1")
        ;;
      *)
        echo "[ERROR] Unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  # Handle --debug-run mode (inline execution for interactive debugging)
  if [[ -n "${DEBUG_RUN_FILE:-}" ]]; then
    debug_run_test "$DEBUG_RUN_FILE"
    return $?
  fi

  # Default to all tests if none specified
  if [[ ${#TEST_TYPES[@]} -eq 0 ]]; then
    TEST_TYPES=("unit" "integration" "e2e")
  fi

  # Initialize testing environment
  TEST_SANDBOX_ROOT="$(mktemp -d -t kgsm-test-sandbox-XXXXXX)"

  # Normalize parallel setting
  __normalize_test_parallel
  export TEST_PARALLEL

  # Create timestamped log directory
  local timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  TEST_LOG_DIR="$TESTS_ROOT/logs/$timestamp"
  mkdir -p "$TEST_LOG_DIR"

  # Set up signal handlers for cleanup
  trap 'cleanup_all' EXIT INT TERM

  # Count total tests across all types for TAP plan line
  local total_tests=0
  for test_type in "${TEST_TYPES[@]}"; do
    ((total_tests += $(_count_filtered_tests "$test_type")))
  done

  # Emit TAP header
  echo "TAP version 14"
  echo "1..${total_tests}"

  # Initialize streaming TAP state
  TAP_TEST_NUM=0
  TAP_HAS_FAILURES=0
  TAP_BAIL_OUT=0

  # Run test suites (TAP results emitted inline as tests complete)
  for test_type in "${TEST_TYPES[@]}"; do
    run_test_suite "$test_type"
    # Stop all suites on bail out
    [[ "$TAP_BAIL_OUT" -eq 1 ]] && break
  done

  # Create/update 'latest' symlink
  ln -sfn "$TEST_LOG_DIR" "$TEST_LATEST_LINK"

  # Return non-zero if any test failed
  [[ $TAP_HAS_FAILURES -ne 0 ]] && return 1
  return 0
}

main "$@"
exit $?
