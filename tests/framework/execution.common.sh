#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - Shared Execution Helpers Module
# ==============================================================================
# Version: 1.0
# Description: Provides common helper functions shared by both sequential and
#              parallel test executors, including environment management,
#              output capture, result parsing, and serialization.
# Dependencies: loader.sh, config.sh, logging.sh
# ==============================================================================

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

# Load guard to prevent multiple sourcing
if [[ -n "${TEST_EXECUTION_COMMON_LOADED:-}" ]]; then
  return 0
fi

# ==============================================================================
# ENVIRONMENT MANAGEMENT
# ==============================================================================

# ------------------------------------------------------------------------------
# Setup test environment for sandbox execution
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - sandbox_path: Absolute path to sandbox directory
#   $2 - test_log: Absolute path to test log file
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Exit code: EC_FAILURE (1) on error
# ------------------------------------------------------------------------------
function __setup_test_environment() {
  local sandbox_path="$1"
  local test_log="$2"

  # Save original KGSM_ROOT for restoration
  local original_kgsm_root="${KGSM_ROOT:-}"

  # Set sandbox context environment variables
  declare -g KGSM_ROOT="$sandbox_path"
  export KGSM_ROOT
  declare -g KGSM_TEST_MODE="true"
  export KGSM_TEST_MODE
  declare -g KGSM_TEST_LOG="$test_log"
  export KGSM_TEST_LOG
  declare -g KGSM_TEST_SANDBOX="$sandbox_path"
  export KGSM_TEST_SANDBOX
  declare -g KGSM_LOG_CONSOLE_ENABLED="false"
  export KGSM_LOG_CONSOLE_ENABLED
  declare -g TEST_SANDBOX_INSTANCES_INSTALL_DIR="${sandbox_path}/test_instances"
  export TEST_SANDBOX_INSTANCES_INSTALL_DIR

  # Save original XDG variables for restoration.
  # XDG paths control where KGSM stores user data (instances, config, logs).
  # Without sandboxing these, tests pollute the real user's home directory.
  declare -g _ORIG_XDG_DATA_HOME="${XDG_DATA_HOME:-}"
  declare -g _ORIG_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}"
  declare -g _ORIG_XDG_DATA_HOME_WAS_SET="${XDG_DATA_HOME+set}"
  declare -g _ORIG_XDG_CONFIG_HOME_WAS_SET="${XDG_CONFIG_HOME+set}"

  # Override XDG paths to point inside the sandbox.
  # Subprocesses (e.g., kgsm.sh invocations) inherit these exports,
  # ensuring all paths resolve inside the sandbox.
  export XDG_DATA_HOME="${sandbox_path}/.local/share"
  export XDG_CONFIG_HOME="${sandbox_path}/.config"

  # Pre-create the XDG config directory and place the test config there BEFORE
  # sourcing bootstrap.sh. A sandbox without one is a valid state — core/config.sh
  # seeds the shipped defaults and carries on — but then the test would run against
  # those rather than against tests/config.test.ini, and the settings that make a
  # run a test run (TEST_PARALLEL among them) would not be in effect.
  mkdir -p "${sandbox_path}/.config/kgsm"
  if [[ -f "${sandbox_path}/config.ini" ]]; then
    cp "${sandbox_path}/config.ini" "${sandbox_path}/.config/kgsm/config.ini"
  fi

  # CRITICAL: Unset all module load flags to force fresh initialization in sandbox
  # The test framework loaded KGSM modules with HOST KGSM_ROOT, but tests need
  # modules loaded with SANDBOX KGSM_ROOT. By unsetting these flags, we force
  # modules to reload when the test sources them.
  unset KGSM_BOOTSTRAP_LOADED
  unset KGSM_COMMON_LOADED
  unset KGSM_LOADER_LOADED
  unset KGSM_CONFIG_LOADED
  unset KGSM_PARSER_LOADED
  unset KGSM_VALIDATION_LOADED
  unset KGSM_LOGGING_LOADED
  unset KGSM_EVENTS_LOADED
  unset KGSM_OVERRIDES_LOADED
  # Unset KGSM_PATHS_LOADED so core/paths.sh re-evaluates XDG-derived paths
  unset KGSM_PATHS_LOADED

  # Load KGSM bootstrap in sandbox context
  # This gives tests access to KGSM modules, error codes, and functions.
  # bootstrap.sh will source paths.sh (now with sandbox XDG vars) and call
  # __init_user_directories() to create the XDG directory structure inside
  # the sandbox.
  if [[ -f "${original_kgsm_root}/core/bootstrap.sh" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${original_kgsm_root}/core/bootstrap.sh" || {
      log_error "Failed to load KGSM bootstrap: ${original_kgsm_root}/core/bootstrap.sh"
      return $EC_FAILURE
    }
  else
    log_error "KGSM bootstrap not found: ${original_kgsm_root}/core/bootstrap.sh"
    return $EC_FAILURE
  fi

  # Debug: verify environment is set
  log_debug "Environment setup complete: KGSM_TEST_SANDBOX=$KGSM_TEST_SANDBOX KGSM_ROOT=$original_kgsm_root"

  return $EC_SUCCESS
}
export -f __setup_test_environment

# ------------------------------------------------------------------------------
# Restore test environment to host context
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - original_kgsm_root: Original KGSM_ROOT value from setup
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
function __restore_test_environment() {
  local original_kgsm_root="$1"

  # Restore original KGSM_ROOT
  if [[ -n "$original_kgsm_root" ]]; then
    export KGSM_ROOT="$original_kgsm_root"
  else
    unset KGSM_ROOT
  fi

  # Restore original XDG variables
  if [[ "${_ORIG_XDG_DATA_HOME_WAS_SET:-}" == "set" ]]; then
    export XDG_DATA_HOME="$_ORIG_XDG_DATA_HOME"
  else
    unset XDG_DATA_HOME
  fi

  if [[ "${_ORIG_XDG_CONFIG_HOME_WAS_SET:-}" == "set" ]]; then
    export XDG_CONFIG_HOME="$_ORIG_XDG_CONFIG_HOME"
  else
    unset XDG_CONFIG_HOME
  fi

  unset _ORIG_XDG_DATA_HOME _ORIG_XDG_CONFIG_HOME
  unset _ORIG_XDG_DATA_HOME_WAS_SET _ORIG_XDG_CONFIG_HOME_WAS_SET

  # Unset sandbox context variables
  unset KGSM_TEST_MODE
  unset KGSM_TEST_LOG
  unset KGSM_TEST_SANDBOX
  unset KGSM_LOG_CONSOLE_ENABLED

  # Re-export module load flags so subsequent code can see them
  # (they were unset to force sandbox reload)
  export KGSM_BOOTSTRAP_LOADED
  export KGSM_COMMON_LOADED
  export KGSM_LOADER_LOADED
  export KGSM_CONFIG_LOADED
  export KGSM_PATHS_LOADED

  return $EC_SUCCESS
}
export -f __restore_test_environment

# ==============================================================================
# TEST EXECUTION HELPERS
# ==============================================================================

# ------------------------------------------------------------------------------
# Wait for a process to complete or timeout
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - pid: Process ID to wait for
#   $2 - timeout: Max wait time in seconds
# Returns:
#   0 if process completed, 1 if timeout reached
# ------------------------------------------------------------------------------
function wait_with_timeout() {
  local pid=$1
  local timeout=$2
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
      return 1
    fi
    sleep 1
    ((elapsed++))
  done
  return 0
}
export -f wait_with_timeout

# ==============================================================================
# TEST FUNCTION DISCOVERY AND RECONCILIATION
# ==============================================================================

# ------------------------------------------------------------------------------
# List the test functions a test file declares, in file order
# ------------------------------------------------------------------------------
# This is the single definition of what "a test function" is. The runner records
# the list as a plan before execution and reconciles it against the per-function
# results afterwards, so this grep and the loop that runs the functions can never
# disagree about the set.
#
# Arguments:
#   $1 - test_file: Absolute path to test file
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Stdout: One function name per line
# ------------------------------------------------------------------------------
function __discover_test_functions() {
  local test_file="$1"

  grep -oP '^function \Ktest_\w+' "$test_file" 2>/dev/null || true
}
export -f __discover_test_functions

# ------------------------------------------------------------------------------
# Write the plan of test functions a run intends to execute
# ------------------------------------------------------------------------------
# Written to the test log before the file is sourced, so it survives anything the
# test does to the process afterwards. __reconcile_executed_functions reads it
# back.
#
# Arguments:
#   $1 - test_file: Absolute path to test file
# Returns:
#   Exit code: EC_SUCCESS (0)
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Echo the plan and per-function results belonging to a log's most recent run
# ------------------------------------------------------------------------------
# Two test files that share a basename share a log file, and a log is appended to
# rather than truncated. The plan marker opens a run's records, so everything from
# the last one onward is this run's and nothing before it is.
#
# Arguments:
#   $1 - test_log: Absolute path to test log file
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Stdout (__log_function_plan): space-separated planned function names, or
#          nothing when the log carries no plan marker
#   Stdout (__log_function_results): the run's KGSM_FUNC_RESULT lines, in order
# ------------------------------------------------------------------------------
function __log_plan_line_number() {
  local test_log="$1"

  grep -n "^KGSM_FUNC_PLAN:" "$test_log" 2>/dev/null | tail -1 | cut -d: -f1
}
export -f __log_plan_line_number

function __log_function_plan() {
  local test_log="$1"

  local lineno
  lineno=$(__log_plan_line_number "$test_log")
  [[ -z "$lineno" ]] && return 0

  sed -n "${lineno}s/^KGSM_FUNC_PLAN: //p" "$test_log" 2>/dev/null || true
  return 0
}
export -f __log_function_plan

function __log_function_results() {
  local test_log="$1"

  local lineno
  lineno=$(__log_plan_line_number "$test_log")
  if [[ -z "$lineno" ]]; then
    grep "^KGSM_FUNC_RESULT:" "$test_log" 2>/dev/null || true
    return 0
  fi

  tail -n "+$((lineno + 1))" "$test_log" 2>/dev/null |
    grep "^KGSM_FUNC_RESULT:" || true
  return 0
}
export -f __log_function_results

function __write_function_plan() {
  local test_file="$1"

  [[ -z "${KGSM_TEST_LOG:-}" ]] && return 0

  local -a planned
  if [[ -n "${KGSM_TEST_FUNCTION_FILTER:-}" ]]; then
    planned=("$KGSM_TEST_FUNCTION_FILTER")
  else
    mapfile -t planned < <(__discover_test_functions "$test_file")
  fi

  echo "KGSM_FUNC_PLAN: ${planned[*]}" >> "$KGSM_TEST_LOG"
  return 0
}
export -f __write_function_plan

# ------------------------------------------------------------------------------
# Fail a test file whose planned functions did not all report a result
# ------------------------------------------------------------------------------
# A harness that runs fewer tests than a file declares is the one failure a test
# harness must never absorb: the suite stays green while coverage disappears. Any
# planned function without a KGSM_FUNC_RESULT marker is recorded as `missing`,
# which the TAP reporter renders as a failing subtest.
#
# Arguments:
#   $1 - test_log: Absolute path to test log file
# Returns:
#   Exit code: EC_SUCCESS (0) when every planned function reported
#   Exit code: EC_FAILURE (1) when one or more never ran
# ------------------------------------------------------------------------------
function __reconcile_executed_functions() {
  local test_log="$1"

  [[ -z "$test_log" || ! -f "$test_log" ]] && return $EC_SUCCESS

  local plan
  plan=$(__log_function_plan "$test_log")
  [[ -z "$plan" ]] && return $EC_SUCCESS

  local -a planned
  read -r -a planned <<< "$plan"
  [[ ${#planned[@]} -eq 0 ]] && return $EC_SUCCESS

  local -A reported=()
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] && reported["$name"]=1
  done < <(__log_function_results "$test_log" | sed 's/^KGSM_FUNC_RESULT: //' | cut -d'|' -f1)

  local -a missing=()
  local fn
  for fn in "${planned[@]}"; do
    [[ -z "${reported[$fn]:-}" ]] && missing+=("$fn")
  done

  [[ ${#missing[@]} -eq 0 ]] && return $EC_SUCCESS

  # The FAIL line carries the source shape the TAP reporter parses, so a shortfall
  # renders as a failure detail like any other
  local timestamp source_name
  timestamp=$(date -Iseconds)
  source_name="$(basename "${test_log%.log}").sh"
  for fn in "${missing[@]}"; do
    echo "[$timestamp] [ERROR] [${source_name}:0 in ${fn}()] FAIL: test function is declared in the file but never executed" >> "$test_log"
    echo "KGSM_FUNC_RESULT: ${fn}|0|0|0|missing" >> "$test_log"
  done

  return $EC_FAILURE
}
export -f __reconcile_executed_functions

# ------------------------------------------------------------------------------
# Execute test file with timeout and capture output
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - test_file: Absolute path to test file
#   $2 - timeout_seconds: Max execution time (default: TEST_DEFAULT_TIMEOUT)
# Returns:
#   Exit code: Test's exit code (or EC_TIMEOUT if timeout)
#   Stdout: Captured output (stderr + stdout combined)
# ------------------------------------------------------------------------------
function __capture_test_output() {
  local test_file="$1"
  local timeout_seconds="${2:-${TEST_DEFAULT_TIMEOUT}}"

  local output_file="/tmp/kgsm-test-output-$$.txt"
  local exit_code

  (
    # Record the plan before sourcing, so it survives whatever the test does to
    # this process afterwards
    __write_function_plan "$test_file"

    # Source the test file — only defines functions (no main "$@" invocation)
    source "$test_file"

    # Run setup_file if defined
    if declare -f setup_file >/dev/null 2>&1; then
      setup_file
    fi

    if [[ -n "${KGSM_TEST_FUNCTION_FILTER:-}" ]]; then
      # A --function naming something this file does not define is a typo, not
      # an empty success. Leaving it without a result lets the reconciliation in
      # execute_test_in_sandbox report it as a function that never ran.
      if ! declare -f "$KGSM_TEST_FUNCTION_FILTER" >/dev/null 2>&1; then
        echo "[ERROR] Test function not found in $(basename "$test_file"): ${KGSM_TEST_FUNCTION_FILTER}" >&2
        echo "Available test functions:" >&2
        __discover_test_functions "$test_file" >&2
      else
        # Run only the specified function (with per-function tracking)
        if declare -f setup >/dev/null 2>&1; then
          setup
        fi

        # Snapshot counters AFTER setup() so setup assertions are not counted
        local _before_passed=${ASSERT_PASSED:-0}
        local _before_failed=${ASSERT_FAILED:-0}
        local _before_count=${ASSERT_COUNT:-0}
        local _before_skip_len=${#ASSERT_SKIPPED_FUNCTION_NAMES[@]}
        local _before_todo_len=${#ASSERT_TODO_FUNCTION_NAMES[@]}

        "${KGSM_TEST_FUNCTION_FILTER}"

        local _fn_passed=$(( ${ASSERT_PASSED:-0} - _before_passed ))
        local _fn_failed=$(( ${ASSERT_FAILED:-0} - _before_failed ))
        local _fn_total=$(( ${ASSERT_COUNT:-0} - _before_count ))
        local _fn_status="pass"

        if [[ ${#ASSERT_SKIPPED_FUNCTION_NAMES[@]} -gt $_before_skip_len ]]; then
          _fn_status="skip"
        elif [[ ${#ASSERT_TODO_FUNCTION_NAMES[@]} -gt $_before_todo_len ]]; then
          _fn_status="todo"
        elif [[ $_fn_failed -gt 0 ]]; then
          _fn_status="fail"
        fi

        if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
          echo "KGSM_FUNC_RESULT: ${KGSM_TEST_FUNCTION_FILTER}|${_fn_passed}|${_fn_failed}|${_fn_total}|${_fn_status}" >> "$KGSM_TEST_LOG"
        fi

        # Cleanup after single function run
        if declare -f teardown >/dev/null 2>&1; then
          teardown || true
        fi
      fi
    else
      # Auto-discover and run all test_* functions in file order
      local -a _test_functions
      mapfile -t _test_functions < <(__discover_test_functions "$test_file")
      for _fn in "${_test_functions[@]}"; do
        if declare -f "$_fn" >/dev/null 2>&1; then
          # Per-test setup (runs before each test function)
          if declare -f setup >/dev/null 2>&1; then
            setup
          fi

          # Snapshot counters AFTER setup() so setup assertions are not counted
          local _before_passed=${ASSERT_PASSED:-0}
          local _before_failed=${ASSERT_FAILED:-0}
          local _before_count=${ASSERT_COUNT:-0}
          local _before_skip_len=${#ASSERT_SKIPPED_FUNCTION_NAMES[@]}
          local _before_todo_len=${#ASSERT_TODO_FUNCTION_NAMES[@]}

          "$_fn"

          local _fn_passed=$(( ${ASSERT_PASSED:-0} - _before_passed ))
          local _fn_failed=$(( ${ASSERT_FAILED:-0} - _before_failed ))
          local _fn_total=$(( ${ASSERT_COUNT:-0} - _before_count ))
          local _fn_status="pass"

          if [[ ${#ASSERT_SKIPPED_FUNCTION_NAMES[@]} -gt $_before_skip_len ]]; then
            _fn_status="skip"
          elif [[ ${#ASSERT_TODO_FUNCTION_NAMES[@]} -gt $_before_todo_len ]]; then
            _fn_status="todo"
          elif [[ $_fn_failed -gt 0 ]]; then
            _fn_status="fail"
          fi

          if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
            echo "KGSM_FUNC_RESULT: ${_fn}|${_fn_passed}|${_fn_failed}|${_fn_total}|${_fn_status}" >> "$KGSM_TEST_LOG"
          fi

          # Per-test teardown (runs after each test function, failures ignored)
          if declare -f teardown >/dev/null 2>&1; then
            teardown || true
          fi
        fi
      done
    fi

    # Framework calls print_assert_summary — capture its exit code
    local _test_exit=0
    if declare -f print_assert_summary >/dev/null 2>&1; then
      print_assert_summary "${TEST_NAME:-}" || _test_exit=$?
    fi

    # Run teardown_file if defined (must not affect test result)
    if declare -f teardown_file >/dev/null 2>&1; then
      teardown_file
    fi

    exit $_test_exit
  ) >"$output_file" 2>&1 &

  local test_pid=$!

  # Wait for completion or timeout
  if ! wait_with_timeout "$test_pid" "$timeout_seconds"; then
    # Timeout - kill the test process
    kill -9 "$test_pid" 2>/dev/null
    wait "$test_pid" 2>/dev/null
    echo "TEST TIMEOUT: Test exceeded ${timeout_seconds}s limit" >> "$output_file"
    exit_code=$EC_TIMEOUT
  else
    wait "$test_pid"
    exit_code=$?
  fi

  local output
  if [[ -f "$output_file" ]]; then
    output=$(tr -d '\0' < "$output_file")
    rm -f "$output_file"
  else
    output="No output captured (output file missing)"
  fi

  echo "$output"
  return $exit_code
}
export -f __capture_test_output

# ------------------------------------------------------------------------------
# Execute test file inline (no subshell) for interactive debugging
# ------------------------------------------------------------------------------
# This function runs the same test lifecycle as __capture_test_output but
# without wrapping it in a subshell or background process. This allows
# debuggers like bashdb to step through the test code line by line.
#
# Arguments:
#   $1 - test_file: Absolute path to test file
# Returns:
#   Exit code: 0 if all assertions passed, 1 otherwise
# ------------------------------------------------------------------------------
function __execute_test_inline() {
  local test_file="$1"
  local _inline_shortfall=0

  # Source the test file — defines functions
  # shellcheck disable=SC1090
  source "$test_file"

  # Run setup_file if defined
  if declare -f setup_file >/dev/null 2>&1; then
    setup_file
  fi

  # Run target function(s)
  if [[ -n "${KGSM_TEST_FUNCTION_FILTER:-}" ]]; then
    if declare -f "$KGSM_TEST_FUNCTION_FILTER" >/dev/null 2>&1; then
      if declare -f setup >/dev/null 2>&1; then
        setup
      fi
      "$KGSM_TEST_FUNCTION_FILTER"
      if declare -f teardown >/dev/null 2>&1; then
        teardown || true
      fi
    else
      echo "ERROR: Function not found: $KGSM_TEST_FUNCTION_FILTER" >&2
      echo "Available test functions in $(basename "$test_file"):" >&2
      __discover_test_functions "$test_file" >&2
      return 1
    fi
  else
    local -a _test_functions
    mapfile -t _test_functions < <(__discover_test_functions "$test_file")
    local _executed=0
    for _fn in "${_test_functions[@]}"; do
      if declare -f "$_fn" >/dev/null 2>&1; then
        if declare -f setup >/dev/null 2>&1; then
          setup
        fi
        "$_fn"
        ((_executed++)) || true
        if declare -f teardown >/dev/null 2>&1; then
          teardown || true
        fi
      fi
    done

    # Same shortfall guard the sandboxed path applies, reported to the terminal
    if [[ $_executed -lt ${#_test_functions[@]} ]]; then
      echo "[ERROR] Only ${_executed} of ${#_test_functions[@]} declared test functions ran" >&2
      _inline_shortfall=1
    fi
  fi

  # Print assertion summary
  local _test_exit=0
  if declare -f print_assert_summary >/dev/null 2>&1; then
    print_assert_summary "${TEST_NAME:-}" || _test_exit=$?
  fi

  # Run teardown_file if defined (must not affect test result)
  if declare -f teardown_file >/dev/null 2>&1; then
    teardown_file
  fi

  if [[ $_inline_shortfall -ne 0 ]]; then
    _test_exit=$EC_FAILURE
  fi

  return $_test_exit
}
export -f __execute_test_inline

# ------------------------------------------------------------------------------
# Parse assertion statistics from test log
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - test_log: Absolute path to test log file
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Stdout: Five integers separated by spaces: "passed failed total skipped todo"
# ------------------------------------------------------------------------------
function __parse_assertion_stats() {
  local test_log="$1"

  # Check if log file exists
  if [[ ! -f "$test_log" ]]; then
    echo "0 0 0 0 0"
    return $EC_SUCCESS
  fi

  # Primary method: Look for KGSM_ASSERT_STATS marker
  local stats_line
  stats_line=$(grep "^KGSM_ASSERT_STATS:" "$test_log" 2>/dev/null | tail -1 || echo "")

  if [[ -n "$stats_line" ]]; then
    # Extract "passed/failed/total/skipped[/todo]" from marker
    local stats_value
    stats_value=$(echo "$stats_line" | sed 's/^KGSM_ASSERT_STATS: *//' | tr -d '[:space:]')

    # Parse format: 133/0/133/2/0 (passed/failed/total/skipped/todo)
    local passed failed total skipped todo
    IFS='/' read -r passed failed total skipped todo <<< "$stats_value"

    # If skipped/todo are not present, default to 0 (backward compatibility)
    [[ -z "$skipped" ]] && skipped=0
    [[ -z "$todo" ]] && todo=0

    # Validate extracted values are numbers
    if [[ "$passed" =~ ^[0-9]+$ ]] && [[ "$failed" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$skipped" =~ ^[0-9]+$ ]] && [[ "$todo" =~ ^[0-9]+$ ]]; then
      echo "$passed $failed $total $skipped $todo"
      return $EC_SUCCESS
    fi
  fi

  # Fallback method: Count PASS: and FAIL: markers
  local passed failed total skipped todo
  # Look for PASS: anywhere in the line (not just at beginning) to handle bash tracing output
  # `grep -c` prints its count and still exits 1 on no match, so the fallback is
  # `|| true` — an `|| echo 0` would append a second line and make the value
  # unusable in arithmetic
  passed=$(grep -c "PASS:" "$test_log" 2>/dev/null || true)
  failed=$(grep -c "FAIL:" "$test_log" 2>/dev/null || true)
  skipped=$(grep -c "^\[SKIP\]" "$test_log" 2>/dev/null || true)
  todo=$(grep -c "^\[TODO\]" "$test_log" 2>/dev/null || true)

  # Ensure we have clean numeric values (strip whitespace)
  passed=$(echo "$passed" | tr -d '[:space:]')
  failed=$(echo "$failed" | tr -d '[:space:]')
  skipped=$(echo "$skipped" | tr -d '[:space:]')
  todo=$(echo "$todo" | tr -d '[:space:]')

  # Validate they are numbers
  [[ ! "$passed" =~ ^[0-9]+$ ]] && passed=0
  [[ ! "$failed" =~ ^[0-9]+$ ]] && failed=0
  [[ ! "$skipped" =~ ^[0-9]+$ ]] && skipped=0
  [[ ! "$todo" =~ ^[0-9]+$ ]] && todo=0

  total=$((passed + failed))

  echo "$passed $failed $total $skipped $todo"
  return $EC_SUCCESS
}
export -f __parse_assertion_stats

# ------------------------------------------------------------------------------
# Calculate test duration in milliseconds
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - start_timestamp: Unix timestamp in milliseconds from 'date +%s%3N'
#   $2 - end_timestamp: Unix timestamp in milliseconds from 'date +%s%3N'
# Returns:
#   Exit code: EC_SUCCESS (0)
#   Stdout: Duration in milliseconds (integer)
# ------------------------------------------------------------------------------
function __calculate_duration() {
  local start_time="$1"
  local end_time="$2"

  local duration=$((end_time - start_time))
  echo "$duration"
}
export -f __calculate_duration

# ==============================================================================
# RESULT SERIALIZATION (for parallel IPC)
# ==============================================================================

# ------------------------------------------------------------------------------
# Serialize result array to temp file for inter-process communication
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - result_array_name: Name of associative array (as string, not nameref)
#   $2 - result_file: Absolute path to result file
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
# File format:
#   key=value (one per line)
#   Newlines in values escaped as \n
# ------------------------------------------------------------------------------
function __write_result_to_file() {
  local result_array_name="$1"
  local result_file="$2"

  # Validate inputs
  if [[ -z "$result_array_name" ]]; then
    log_error "__write_result_to_file: result_array_name is required"
    return $EC_FAILURE
  fi

  if [[ -z "$result_file" ]]; then
    log_error "__write_result_to_file: result_file is required"
    return $EC_FAILURE
  fi

  # Ensure result directory exists
  local result_dir
  result_dir=$(dirname "$result_file")
  if [[ ! -d "$result_dir" ]]; then
    mkdir -p "$result_dir" || {
      log_error "Failed to create result directory: $result_dir"
      return $EC_FAILURE
    }
  fi

  # Get nameref to array (indirect reference)
  local -n result_array_ref="$result_array_name"

  # Write key=value pairs to file
  {
    for key in "${!result_array_ref[@]}"; do
      # Escape special characters in value (preserve newlines, etc.)
      local value="${result_array_ref[$key]}"
      # Simple escaping: replace newlines with literal \n
      value="${value//$'\n'/\\n}"
      echo "${key}=${value}"
    done
  } > "$result_file" || {
    log_error "Failed to write result file: $result_file"
    return $EC_FAILURE
  }

  log_debug "Wrote result to file: $result_file"
  return $EC_SUCCESS
}
export -f __write_result_to_file

# ------------------------------------------------------------------------------
# Deserialize result file into associative array
# ------------------------------------------------------------------------------
# Arguments:
#   $1 - result_file: Absolute path to result file
#   $2 - result_array_name: Name of associative array to populate
# Returns:
#   Exit code: EC_SUCCESS (0) or EC_FAILURE (1)
# ------------------------------------------------------------------------------
function __read_result_from_file() {
  local result_file="$1"
  local result_array_name="$2"

  # Validate inputs
  if [[ -z "$result_file" ]]; then
    log_error "__read_result_from_file: result_file is required"
    return $EC_FAILURE
  fi

  if [[ ! -f "$result_file" ]]; then
    log_error "__read_result_from_file: result file not found: $result_file"
    return $EC_FAILURE
  fi

  if [[ -z "$result_array_name" ]]; then
    log_error "__read_result_from_file: result_array_name is required"
    return $EC_FAILURE
  fi

  # Get nameref to array
  local -n result_array_ref="$result_array_name"

  # Read key=value pairs from file
  local line key value
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Split on first = only (value may contain =)
    key="${line%%=*}"
    value="${line#*=}"

    # Skip if no key found
    [[ -z "$key" ]] && continue

    # Unescape newlines
    value="${value//\\n/$'\n'}"

    # Populate array
    result_array_ref["$key"]="$value"
  done < "$result_file"

  log_debug "Read result from file: $result_file (${#result_array_ref[@]} fields)"
  return $EC_SUCCESS
}
export -f __read_result_from_file

# ==============================================================================
# Core Execution Function (Used by both Sequential and Parallel executors)
# ==============================================================================

# ------------------------------------------------------------------------------
# Execute a single test in a sandbox environment
# ------------------------------------------------------------------------------
# This is the core test execution function used by both sequential and parallel
# executors. It sets up the environment, runs the test, captures output, and
# populates the result array.
#
# Arguments:
#   $1 - test_file: Absolute path to test file
#   $2 - test_type: "unit", "integration", or "e2e"
#   $3 - sandbox_path: Absolute path to sandbox directory
#   $4 - test_log: Absolute path to test log file
#   $5 - result_array: Name of associative array to populate with results
# Returns:
#   Exit code: EC_SUCCESS (always, test failure reflected in result data)
#   Side effect: Populates result_array with test results
# Result array fields:
#   test_name, test_type, exit_code, assertions_passed, assertions_failed,
#   assertions_total, duration_seconds, test_log_path, sandbox_path, timestamp
# ------------------------------------------------------------------------------
function execute_test_in_sandbox() {
  local test_file="$1"
  local test_type="$2"
  local sandbox_path="$3"
  local test_log="$4"
  local -n result_array="$5"

  # Extract test name from file path
  local test_name
  test_name=$(basename "$test_file" .sh)

  # Initialize result array
  result_array[test_name]="$test_name"
  result_array[test_type]="$test_type"
  result_array[exit_code]="$EC_FAILURE"
  result_array[assertions_passed]="0"
  result_array[assertions_failed]="0"
  result_array[assertions_total]="0"
  result_array[functions_skipped]="0"
  result_array[functions_todo]="0"
  result_array[duration_seconds]="0"
  result_array[test_log_path]="$test_log"
  result_array[sandbox_path]="$sandbox_path"
  result_array[timestamp]="$(date +%Y-%m-%dT%H:%M:%S%z)"

  # Validate sandbox exists
  if ! validate_sandbox "$sandbox_path" >/dev/null 2>&1; then
    log_error "Sandbox validation failed: $sandbox_path"
    result_array[exit_code]="$EC_ERROR"
    return $EC_SUCCESS
  fi

  # Save original KGSM_ROOT before setup modifies it
  local original_kgsm_root="${KGSM_ROOT:-}"

  # Setup environment (exports KGSM_TEST_SANDBOX and other variables)
  __setup_test_environment "$sandbox_path" "$test_log"

  # Ensure environment restoration via trap
  trap '__restore_test_environment' EXIT INT TERM

  # Record start time (in milliseconds for accurate tracking)
  local start_time end_time duration
  start_time=$(date +%s%3N)

  # Execute test and capture output using the common function
  local test_exit_code captured_output timeout_seconds
  timeout_seconds="${TEST_DEFAULT_TIMEOUT:-300}"

  if captured_output=$(__capture_test_output "$test_file" "$timeout_seconds"); then
    test_exit_code=$EC_SUCCESS
  else
    test_exit_code=$?
  fi

  # Write captured output to log
  if [[ -n "$captured_output" ]]; then
    echo "$captured_output" >> "$test_log"
  fi

  # Reconcile what the file declared against what actually reported. A harness
  # that quietly runs a subset of a file is a green suite over missing coverage,
  # so a shortfall fails the file. Bail out is the one deliberate early stop and
  # keeps its own exit code and reporting path.
  if [[ "$test_exit_code" -ne "${EC_BAIL_OUT:-99}" ]]; then
    if ! __reconcile_executed_functions "$test_log"; then
      if [[ "$test_exit_code" -eq 0 ]]; then
        test_exit_code=$EC_FAILURE
      fi
    fi
  fi

  # Record end time (in milliseconds)
  end_time=$(date +%s%3N)

  # Parse assertion statistics from log
  local stats
  stats=$(__parse_assertion_stats "$test_log")
  read -r passed failed total skipped todo <<< "$stats"

  # Calculate duration (in milliseconds)
  duration=$(__calculate_duration "$start_time" "$end_time")

  # Populate result array
  result_array[exit_code]="$test_exit_code"
  result_array[assertions_passed]="$passed"
  result_array[assertions_failed]="$failed"
  result_array[assertions_total]="$total"
  result_array[functions_skipped]="$skipped"
  result_array[functions_todo]="$todo"
  result_array[duration_seconds]="$duration"

  # Restore environment (also happens via trap)
  __restore_test_environment "$original_kgsm_root"

  # Remove trap
  trap - EXIT INT TERM

  return $EC_SUCCESS
}
export -f execute_test_in_sandbox

# ==============================================================================
# Module Initialization
# ==============================================================================

# Mark module as loaded
declare -g TEST_EXECUTION_COMMON_LOADED=1
export TEST_EXECUTION_COMMON_LOADED
