#!/usr/bin/env bash
# KGSM Testing Framework - Loader Module
# Purpose: Provides path constants, color constants, and helper utilities
# Dependencies: bootstrap.sh (TEST_ROOT, KGSM_ROOT)
# Usage: source tests/framework/loader.sh

# ============================================================================
# Load Guard
# ============================================================================

# Prevent double-loading
if [[ -n "${TEST_LOADER_LOADED:-}" ]]; then
  return 0
fi

# ============================================================================
# Exit codes - Testing Framework
# ============================================================================
declare -g EC_SUCCESS=0
export EC_SUCCESS

declare -g EC_FAILURE=1
export EC_FAILURE

# Custom exit code indicating a test was skipped
declare -g EC_SKIP=33
export EC_SKIP

# ============================================================================
# Path Constants - Testing Framework
# ============================================================================

# Core framework directories
declare -gr TEST_FRAMEWORK_DIR="${TEST_ROOT}/framework"
declare -gr TEST_TEMPLATES_DIR="${TEST_ROOT}/templates"
declare -gr TEST_CONFIG_DIR="${TEST_ROOT}"
declare -gr TEST_LOGS_DIR="${TEST_ROOT}/logs"

# Test suite directories
declare -gr TEST_UNIT_DIR="${TEST_ROOT}/unit"
declare -gr TEST_INTEGRATION_DIR="${TEST_ROOT}/integration"
declare -gr TEST_E2E_DIR="${TEST_ROOT}/e2e"

# Core framework files
declare -gr TEST_BOOTSTRAP_FILE="${TEST_FRAMEWORK_DIR}/bootstrap.sh"
declare -gr TEST_COMMON_FILE="${TEST_FRAMEWORK_DIR}/common.sh"
declare -gr TEST_ASSERT_FILE="${TEST_FRAMEWORK_DIR}/assert.sh"
declare -gr TEST_LOGGING_FILE="${TEST_FRAMEWORK_DIR}/logging.sh"
declare -gr TEST_FIXTURES_FILE="${TEST_FRAMEWORK_DIR}/fixtures.sh"

# Template files
declare -gr TEST_TEMPLATE_FILE="${TEST_TEMPLATES_DIR}/test.template.sh"

# Runner script
declare -gr TEST_RUNNER_FILE="${TEST_ROOT}/run.sh"

# ============================================================================
# Path Constants - KGSM Core
# ============================================================================

# KGSM core directories
declare -gr KGSM_CORE_DIR="${KGSM_ROOT}/core"
declare -gr KGSM_COMMANDS_DIR="${KGSM_ROOT}/commands"
declare -gr KGSM_OVERRIDES_DIR="${KGSM_ROOT}/overrides"
declare -gr KGSM_BLUEPRINTS_DIR="${KGSM_ROOT}/blueprints"
declare -gr KGSM_TEMPLATES_DIR="${KGSM_ROOT}/templates"
declare -gr KGSM_INSTANCES_DIR="${KGSM_ROOT}/instances"

# KGSM core files
declare -gr KGSM_BOOTSTRAP_FILE="${KGSM_CORE_DIR}/bootstrap.sh"
declare -gr KGSM_COMMON_FILE="${KGSM_CORE_DIR}/common.sh"
declare -gr KGSM_LOADER_FILE="${KGSM_CORE_DIR}/loader.sh"
declare -gr KGSM_CONFIG_FILE="${KGSM_ROOT}/config.ini"
declare -gr KGSM_MAIN_SCRIPT="${KGSM_ROOT}/kgsm.sh"

# ============================================================================
# Path Constants - Sandbox (Runtime-Set)
# ============================================================================

# Sandbox base directory (set by run.sh or test script)
# These are NOT readonly because they're set at runtime by test runner
declare -g TEST_SANDBOX_DIR="${TEST_SANDBOX_DIR:-}"
declare -g TEST_SANDBOX_KGSM_ROOT="${TEST_SANDBOX_KGSM_ROOT:-}"

# ============================================================================
# Color Constants - ANSI Codes
# ============================================================================

# Text colors
declare -g COLOR_RED='\033[0;31m'
declare -g COLOR_GREEN='\033[0;32m'
declare -g COLOR_YELLOW='\033[1;33m'
declare -g COLOR_BLUE='\033[0;34m'
declare -g COLOR_MAGENTA='\033[0;35m'
declare -g COLOR_CYAN='\033[0;36m'
declare -g COLOR_WHITE='\033[1;37m'
declare -g COLOR_GRAY='\033[0;90m'

# Text styles
declare -g COLOR_BOLD='\033[1m'
declare -g COLOR_DIM='\033[2m'
declare -g COLOR_UNDERLINE='\033[4m'

# Reset
declare -g COLOR_RESET='\033[0m'

# ============================================================================
# Color Constants - Semantic Aliases
# ============================================================================

# Semantic aliases for common use cases
declare -g COLOR_SUCCESS="${COLOR_GREEN}"
declare -g COLOR_FAILURE="${COLOR_RED}"
declare -g COLOR_WARNING="${COLOR_YELLOW}"
declare -g COLOR_INFO="${COLOR_CYAN}"
declare -g COLOR_DEBUG="${COLOR_GRAY}"
declare -g COLOR_HIGHLIGHT="${COLOR_BOLD}"

# ============================================================================
# Helper Functions
# ============================================================================

# Find a file by searching standard test directories
# Usage: __test_find_file "filename.sh"
# Returns: Full path to file or empty string if not found
function __test_find_file() {
  local filename="$1"

  # Search order: framework → unit → integration → e2e → templates
  local search_dirs=(
    "${TEST_FRAMEWORK_DIR}"
    "${TEST_UNIT_DIR}"
    "${TEST_INTEGRATION_DIR}"
    "${TEST_E2E_DIR}"
    "${TEST_TEMPLATES_DIR}"
  )

  for dir in "${search_dirs[@]}"; do
    if [[ -f "${dir}/${filename}" ]]; then
      echo "${dir}/${filename}"
      return 0
    fi
  done

  # Not found
  return 1
}

export -f __test_find_file

# Verify a directory exists and is readable
# Usage: __test_validate_dir "/path/to/dir" "description"
# Returns: 0 if valid, 1 if invalid
function __test_validate_dir() {
  local dir_path="$1"
  local description="${2:-directory}"

  if [[ ! -d "$dir_path" ]]; then
    echo "ERROR: ${description} not found: ${dir_path}" >&2
    return 1
  fi

  if [[ ! -r "$dir_path" ]]; then
    echo "ERROR: ${description} not readable: ${dir_path}" >&2
    return 1
  fi

  return 0
}

export -f __test_validate_dir

# Verify a file exists and is readable
# Usage: __test_validate_file "/path/to/file" "description"
# Returns: 0 if valid, 1 if invalid
function __test_validate_file() {
  local file_path="$1"
  local description="${2:-file}"

  if [[ ! -f "$file_path" ]]; then
    echo "ERROR: ${description} not found: ${file_path}" >&2
    return 1
  fi

  if [[ ! -r "$file_path" ]]; then
    echo "ERROR: ${description} not readable: ${file_path}" >&2
    return 1
  fi

  return 0
}

export -f __test_validate_file

# ============================================================================
# Module Initialization Complete
# ============================================================================

declare -g TEST_LOADER_LOADED=1
export TEST_LOADER_LOADED
