#!/usr/bin/env bash
# ==============================================================================
# KGSM Testing Framework - Debug Wrapper
# ==============================================================================
# Version: 1.0
# Description: Standalone entry point for debugging test functions with bashdb.
#              Sets up a sandboxed test environment and runs a specific test
#              function inline (no subshell) so the debugger can step through it.
#
# Usage:
#   debug-wrapper.sh <test_file> [function_name]
#
# Arguments:
#   test_file      - Absolute path to the test file
#   function_name  - Optional: specific test function to run (default: all)
#
# Environment Variables (optional):
#   KGSM_DEBUG     - Set to 'true' for verbose output
#
# This script is designed to be launched by the rogalmic.bash-debug (bashdb)
# VS Code extension via the KGSM Test Adapter's Debug profile.
# ==============================================================================

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

set -eo pipefail

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

if [[ $# -lt 1 ]]; then
  echo "Usage: debug-wrapper.sh <test_file> [function_name]" >&2
  exit 1
fi

readonly DEBUG_TEST_FILE="$1"
readonly DEBUG_FUNCTION_NAME="${2:-}"

if [[ ! -f "$DEBUG_TEST_FILE" ]]; then
  echo "ERROR: Test file not found: $DEBUG_TEST_FILE" >&2
  exit 1
fi

# =============================================================================
# FRAMEWORK INITIALIZATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
TESTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly TESTS_ROOT

export KGSM_ROOT
KGSM_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"

# Source the testing framework bootstrap (loads all framework modules)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/bootstrap.sh" || {
  echo "ERROR: Failed to source testing framework bootstrap" >&2
  exit 1
}

# =============================================================================
# DETERMINE TEST METADATA
# =============================================================================

readonly DEBUG_TEST_NAME="$(basename "$DEBUG_TEST_FILE" .sh)"

# Determine test type from file path
DEBUG_TEST_TYPE="unit"
if [[ "$DEBUG_TEST_FILE" == *"/integration/"* ]]; then
  DEBUG_TEST_TYPE="integration"
elif [[ "$DEBUG_TEST_FILE" == *"/e2e/"* ]]; then
  DEBUG_TEST_TYPE="e2e"
fi
readonly DEBUG_TEST_TYPE

# =============================================================================
# SANDBOX SETUP
# =============================================================================

# Create a temporary sandbox root
TEST_SANDBOX_ROOT="$(mktemp -d -t kgsm-debug-sandbox-XXXXXX)"
export TEST_SANDBOX_ROOT

# Create sandbox for this test
sandbox_path=$(create_sandbox "$DEBUG_TEST_TYPE" "$DEBUG_TEST_NAME") || {
  echo "ERROR: Failed to create sandbox for: $DEBUG_TEST_NAME" >&2
  exit 1
}

# Create a debug log file
debug_log="/tmp/kgsm-debug-${DEBUG_TEST_NAME}-$$.log"

# Setup the test environment (switches KGSM_ROOT to sandbox, loads modules)
__setup_test_environment "$sandbox_path" "$debug_log"

# =============================================================================
# TEST EXECUTION (inline — no subshell, so bashdb can step through)
# =============================================================================

# Disable strict mode before sourcing test file (tests manage their own errors)
set +eu

# Source the test file — this defines the test functions
# shellcheck disable=SC1090
source "$DEBUG_TEST_FILE"

# Run setup_test() if defined by the test file
if declare -f setup_test >/dev/null 2>&1; then
  setup_test
fi

# Run the target function(s)
if [[ -n "$DEBUG_FUNCTION_NAME" ]]; then
  # Run only the specified function
  if declare -f "$DEBUG_FUNCTION_NAME" >/dev/null 2>&1; then
    "$DEBUG_FUNCTION_NAME"
  else
    echo "ERROR: Function not found: $DEBUG_FUNCTION_NAME" >&2
    echo "Available test functions in $DEBUG_TEST_FILE:" >&2
    grep -oP '^function \Ktest_\w+' "$DEBUG_TEST_FILE" >&2
    exit 1
  fi
else
  # Run all test_* functions in file order
  while IFS= read -r fn_name; do
    if declare -f "$fn_name" >/dev/null 2>&1; then
      "$fn_name"
    fi
  done < <(grep -oP '^function \Ktest_\w+' "$DEBUG_TEST_FILE")
fi

# Print assertion summary
if declare -f print_assert_summary >/dev/null 2>&1; then
  print_assert_summary "$DEBUG_TEST_NAME" || true
fi

# Run cleanup_test() if defined
if declare -f cleanup_test >/dev/null 2>&1; then
  cleanup_test
fi

# =============================================================================
# CLEANUP
# =============================================================================

# Clean up sandbox (debug sessions may want to inspect — keep on failure)
if [[ -d "$sandbox_path" ]]; then
  rm -rf "$sandbox_path" 2>/dev/null || true
fi

if [[ -d "$TEST_SANDBOX_ROOT" ]]; then
  rm -rf "$TEST_SANDBOX_ROOT" 2>/dev/null || true
fi

echo ""
echo "Debug session complete. Log: $debug_log"
