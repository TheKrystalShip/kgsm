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

# 4. Reporting module (test statistics and summary generation)
__load_module "reporting.sh" "Reporting Module" || return 1

# 5. Discovery module (test discovery and filtering)
__load_module "discovery.sh" "Discovery Module" || return 1

# 6. Sandbox module (test environment isolation)
__load_module "sandbox.sh" "Sandbox Module" || return 1

# 7. Execution orchestrator module (delegates to sequential or parallel)
#    This module internally loads execution.common.sh and the appropriate executor
__load_module "execution.sh" "Execution Module" || return 1

# 8. Assertion module (independent utility)
__load_module "assert.sh" "Assertion Module" || return 1

# 9. Fixtures module (independent utility)
__load_module "fixtures.sh" "Fixtures Module" || return 1

# ============================================================================
# KGSM Bootstrap Loading
# ============================================================================

# NOTE: KGSM bootstrap is NOT loaded here during framework initialization.
# This is intentional - tests run in sandboxed environments with different
# KGSM_ROOT values. If we load KGSM modules here, they get the HOST paths.
# Instead, each test wrapper script loads KGSM bootstrap AFTER setting up
# the sandbox environment, ensuring modules are loaded with correct paths.

# ============================================================================
# Debug Mode Output
# ============================================================================

# If debug mode is enabled, show module load status
if [[ "${TEST_DEBUG:-false}" == "true" ]]; then
  echo "[DEBUG] Testing Framework modules loaded:" >&2
  echo "  - loader.sh:              ${TEST_LOADER_LOADED:-not loaded}" >&2
  echo "  - logging.sh:             ${TEST_LOGGING_LOADED:-not loaded}" >&2
  echo "  - config.sh:              ${TEST_CONFIG_LOADED:-not loaded}" >&2
  echo "  - reporting.sh:           ${TEST_REPORTING_LOADED:-not loaded}" >&2
  echo "  - discovery.sh:           ${TEST_DISCOVERY_LOADED:-not loaded}" >&2
  echo "  - sandbox.sh:             ${TEST_SANDBOX_LOADED:-not loaded}" >&2
  echo "  - assert.sh:              ${TEST_ASSERT_LOADED:-not loaded}" >&2
  echo "  - fixtures.sh:            ${TEST_FIXTURES_LOADED:-not loaded}" >&2
  echo "  - execution.sh:           ${TEST_EXECUTION_LOADED:-not loaded}" >&2
  echo "    - common:               ${TEST_EXECUTION_COMMON_LOADED:-not loaded}" >&2
  echo "    - sequential:           ${TEST_EXECUTION_SEQUENTIAL_LOADED:-not loaded}" >&2
  echo "    - parallel:             ${TEST_EXECUTION_PARALLEL_LOADED:-not loaded}" >&2
  echo "    - active executor:      ${_active_executor:-unknown}" >&2
  echo "[DEBUG] KGSM core loaded: ${KGSM_COMMON_LOADED:-not loaded}" >&2
fi

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

# Mark test as skipped
function skip_test() {
  local reason="${1:-Test skipped}"
  log_test_step "SKIP: $reason"
  printf "${YELLOW}[SKIP]${NC} %s\n" "$reason" >&2
  # Use literal 33 to avoid KGSM core overwriting EC_SKIP (KGSM uses 35)
  exit $EC_TEST_SKIP
}

export -f skip_test

# ============================================================================
# Module Initialization Complete
# ============================================================================

declare -g TEST_COMMON_LOADED=1
export TEST_COMMON_LOADED
