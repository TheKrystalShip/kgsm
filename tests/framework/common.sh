#!/usr/bin/env bash
# KGSM Testing Framework - Common Module (Orchestrator)
# Purpose: Load all testing framework modules in correct order
# Dependencies: bootstrap.sh (TEST_ROOT, KGSM_ROOT, TEST_BOOTSTRAP_LOADED)
# Usage: source tests/framework/common.sh (normally sourced by bootstrap.sh)

# ============================================================================
# Load Guard
# ============================================================================

# Prevent double-loading
if [[ -n "${TEST_COMMON_LOADED:-}" ]]; then
  return 0
fi

# Special exit codes exclusive to the testing framework
declare -g -r EC_TEST_SUCCESS=0
export EC_TEST_SUCCESS
declare -g -r EC_TEST_FAILURE=1
export EC_TEST_FAILURE
declare -g -r EC_TEST_SKIP=33
export EC_TEST_SKIP

# ============================================================================
# Dependency Verification
# ============================================================================

# Verify bootstrap.sh was sourced first

# Verify TEST_ROOT is set
if [[ -z "${TEST_ROOT:-}" ]]; then
  echo "ERROR: TEST_ROOT not set by bootstrap.sh" >&2
  return 1
fi

# Verify KGSM_ROOT is set
if [[ -z "${KGSM_ROOT:-}" ]]; then
  echo "ERROR: KGSM_ROOT not set by bootstrap.sh" >&2
  return 1
fi

# ============================================================================
# Module Loading Helper
# ============================================================================

# Load a framework module with error handling
# Usage: __load_module "module_name.sh" "Module Description"
function __load_module() {
  local module_file="$1"
  local module_desc="$2"
  local module_path="${TEST_ROOT}/framework/${module_file}"

  # Check if module file exists
  if [[ ! -f "$module_path" ]]; then
    echo "ERROR: ${module_desc} not found: ${module_path}" >&2
    return 1
  fi

  # Check if module is readable
  if [[ ! -r "$module_path" ]]; then
    echo "ERROR: ${module_desc} not readable: ${module_path}" >&2
    return 1
  fi

  # Source the module
  # shellcheck disable=SC1090
  if ! source "$module_path"; then
    echo "ERROR: Failed to load ${module_desc}: ${module_path}" >&2
    return 1
  fi

  return 0
}

export -f __load_module

# ============================================================================
# Load Framework Modules (Dependency Order)
# ============================================================================

# 1. Loader module (foundation - provides constants and helpers)
__load_module "loader.sh" "Loader Module" || return 1

# 2. Logging module (early - provides logging for other modules)
__load_module "logging.sh" "Logging Module" || return 1

# 3. Configuration module (loads test configuration)
__load_module "config.sh" "Config Module" || return 1

# 4. Reporting module (TAP v14 output for VS Code integration)
__load_module "reporting.tap.sh" "TAP Reporting Module" || return 1

# 5. Discovery module (test discovery and filtering)
__load_module "discovery.sh" "Discovery Module" || return 1

# 6. Sandbox module (test environment isolation)
__load_module "sandbox.sh" "Sandbox Module" || return 1

# 7. Execution module (test execution in sandboxed environments)
__load_module "execution.common.sh" "Execution Module" || return 1

# 8. Assertion module (independent utility)
__load_module "assert.sh" "Assertion Module" || return 1

# 9. KGSM wrapper module (provides KGSM-specific test utilities)
__load_module "kgsm.wrapper.sh" "KGSM Wrapper Module" || return 1

# ============================================================================
# KGSM Bootstrap Loading
# ============================================================================

# NOTE: KGSM bootstrap is NOT loaded here during framework initialization.
# This is intentional - tests run in sandboxed environments with different
# KGSM_ROOT values. If we load KGSM modules here, they get the HOST paths.
# Instead, each test wrapper script loads KGSM bootstrap AFTER setting up
# the sandbox environment, ensuring modules are loaded with correct paths.

# Mark test as passed
function pass_test() {
  local message="${1:-Test passed}"
  log_test_step "PASS: $message"
  # Use literal 0 to avoid KGSM core overwriting EC_SUCCESS
  exit $EC_TEST_SUCCESS
}

export -f pass_test

# Mark test as failed
function fail_test() {
  local message="${1:-Test failed}"
  log_test_step "FAIL: $message"
  printf "${RED}[FAIL]${NC} %s\n" "$message" >&2
  # Use literal 1 to avoid KGSM core overwriting EC_FAILURE (KGSM uses 33)
  exit $EC_TEST_FAILURE
}

export -f fail_test

# Mark current test function as skipped
# NOTE: This function does NOT exit the test file - it only marks the current
# test function as skipped. The calling function should return immediately after.
# Usage: skip_test "reason" && return
function skip_test() {
  local reason="${1:-Test skipped}"
  local func_name="${FUNCNAME[1]:-unknown}"

  # Track skipped function (if assert.sh is loaded)
  if declare -p ASSERT_FUNCTIONS_SKIPPED &>/dev/null; then
    ((ASSERT_FUNCTIONS_SKIPPED++))
    ASSERT_SKIPPED_FUNCTION_NAMES+=("$func_name")
  fi

  # Print skip message to stderr (only if not being captured by test framework)
  # During test execution, KGSM_LOG_CONSOLE_ENABLED is set to "false" to prevent
  # duplicate log entries (stderr is captured and appended to log separately)
  if [[ "${KGSM_LOG_CONSOLE_ENABLED:-true}" == "true" ]]; then
    printf "${YELLOW}[SKIP]${NC} %s: %s\n" "$func_name" "$reason" >&2
  fi

  # Write skip marker to test log for reporting
  if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
    echo "[SKIP] $func_name: $reason" >>"$KGSM_TEST_LOG"
  fi

  # Return success so caller can use: skip_test "reason" && return
  return 0
}

export -f skip_test

# ============================================================================
# Module Initialization Complete
# ============================================================================

declare -g TEST_COMMON_LOADED=1
export TEST_COMMON_LOADED
