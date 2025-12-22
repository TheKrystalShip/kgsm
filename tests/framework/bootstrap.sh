#!/usr/bin/env bash

# KGSM Testing Framework - Bootstrap
#
# This module initializes the testing framework environment by:
# - Detecting TEST_ROOT (framework location)
# - Detecting KGSM_ROOT (project root)
# - Handling --debug flag
# - Loading common.sh (framework orchestrator)
#
# This is the single entry point for the testing framework.
# All test files should source this module first.
#
# Usage:
#   source "$SCRIPT_DIR/../framework/bootstrap.sh"
#
# Environment Variables (exported):
#   TEST_ROOT            - Absolute path to tests/ directory
#   KGSM_ROOT           - Absolute path to KGSM project root
#   TEST_DEBUG          - Set to 'true' if debug mode enabled
#   TEST_BOOTSTRAP_LOADED - Set to '1' when this module loads

# Disabling SC2086 globally (exit codes safe for unquoted use)
# shellcheck disable=SC2086

# =============================================================================
# LOAD GUARD
# =============================================================================

# Prevent double-loading
if [[ -n "${TEST_BOOTSTRAP_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# DEBUG MODE HANDLING
# =============================================================================

# Function to enable debug tracing
__enable_test_debug() {
  export PS4='+(\033[0;33m${BASH_SOURCE}:${LINENO}\033[0m): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -x
}

# Check for --debug flag in arguments
# shellcheck disable=SC2199
if [[ $@ =~ "--debug" ]]; then
  declare -g TEST_DEBUG=true
  export TEST_DEBUG

  # Remove --debug from arguments to prevent downstream parsing errors
  _new_args=()
  for _arg in "$@"; do
    if [[ "$_arg" != "--debug" ]]; then
      _new_args+=("$_arg")
    fi
  done
  set -- "${_new_args[@]}"
  unset _new_args _arg
fi

# Enable debug mode if environment variable is set
if [[ "${TEST_DEBUG:-false}" == "true" ]]; then
  __enable_test_debug
fi

# Clean up helper function
unset -f __enable_test_debug

# =============================================================================
# PATH DETECTION
# =============================================================================

# Detect TEST_ROOT (tests/ directory)
if [[ -z "${TEST_ROOT:-}" ]]; then
  # This script (bootstrap.sh) is in tests/framework/
  # Its parent directory is tests/, which is TEST_ROOT
  _bootstrap_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _test_root="$(cd "$_bootstrap_dir/.." && pwd)"

  if [[ ! -d "$_test_root" ]]; then
    echo "ERROR: Failed to detect TEST_ROOT from bootstrap.sh location" >&2
    echo "ERROR: Computed path: $_test_root" >&2
    exit 1
  fi

  declare -g TEST_ROOT="$_test_root"
  export TEST_ROOT
  unset _bootstrap_dir _test_root
fi

# Detect KGSM_ROOT (project root directory)
if [[ -z "${KGSM_ROOT:-}" ]]; then
  # KGSM_ROOT is the parent of TEST_ROOT
  _kgsm_root="$(cd "$TEST_ROOT/.." && pwd)"

  # Verify KGSM_ROOT looks valid (has kgsm.sh)
  if [[ ! -f "$_kgsm_root/kgsm.sh" ]]; then
    echo "ERROR: Failed to detect KGSM_ROOT - kgsm.sh not found" >&2
    echo "ERROR: Looked in: $_kgsm_root/kgsm.sh" >&2
    echo "ERROR: TEST_ROOT: $TEST_ROOT" >&2
    exit 1
  fi

  declare -g KGSM_ROOT="$_kgsm_root"
  export KGSM_ROOT
  unset _kgsm_root
fi

# =============================================================================
# MARK BOOTSTRAP AS LOADED (BEFORE loading common.sh)
# =============================================================================

# Export module loaded status BEFORE sourcing common.sh
# This allows common.sh to verify bootstrap.sh was loaded
declare -g TEST_BOOTSTRAP_LOADED=1
export TEST_BOOTSTRAP_LOADED

# =============================================================================
# LOAD FRAMEWORK ORCHESTRATOR
# =============================================================================

# Load common.sh which orchestrates loading all framework modules
# shellcheck disable=SC1091
source "$TEST_ROOT/framework/common.sh" || {
  echo "ERROR: Failed to load testing framework orchestrator" >&2
  echo "ERROR: Tried to source: $TEST_ROOT/framework/common.sh" >&2
  echo "ERROR: TEST_ROOT: $TEST_ROOT" >&2
  echo "ERROR: Current directory: $(pwd)" >&2
  exit 1
}
