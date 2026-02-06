#!/usr/bin/env bash

#
# KGSM Testing Framework - Test Discovery Module
#
# Responsible for finding and filtering test files across all test types.
# Implements pattern matching, skip conditions, and test listing functionality.
#
# Module: tests/framework/discovery.sh
# Version: 1.0
# Date: December 19, 2025
#

# =============================================================================
# LOAD GUARD
# =============================================================================

if [[ -n "${TEST_KGSM_WRAPPER_LOADED:-}" ]]; then
  return 0
fi

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# =============================================================================
# PUBLIC FUNCTIONS
# =============================================================================

#
# create_test_instance()
#
# Create a temporary KGSM instance for testing.
#
# Arguments:
#   $1 - blueprint (string, required): The blueprint to use for the instance
#   $2 - instance_name (string, optional): Name for the instance; defaults to
#     "test_instance_<blueprint>_<timestamp>"
#
# Output:
#   None
#
# Return Codes:
#   0 - Success
#   1 - Failure
#
function create_test_instance() {
  local blueprint="$1"

  "$KGSM_MAIN_SCRIPT" directories ensure-created "$TEST_SANDBOX_INSTANCES_INSTALL_DIR"

  "$KGSM_MAIN_SCRIPT" instances create "$blueprint" --install-dir "$TEST_SANDBOX_INSTANCES_INSTALL_DIR"
  return $?
}

export -f create_test_instance

#
# remove_test_instance()
#
# Remove a temporary KGSM instance used for testing.
#
# Arguments:
#   $1 - instance_name (string, required): Name of the instance to remove
#
# Output:
#   None
#
# Return Codes:
#   0 - Success
#   1 - Failure
#
function remove_test_instance() {
  local instance_name="$1"

  "$KGSM_MAIN_SCRIPT" instances remove "$instance_name"
  return $?
}

export -f remove_test_instance

#
# generate_test_id()
#
# Generate a unique test instance ID based on a blueprint.
#
# Arguments:
#   $1 - blueprint (string, optional): The blueprint to base the ID on
#
# Output:
#   Writes generated instance ID to stdout (single line)
#
# Return Codes:
#   0 - Success
#   1 - Failure
#
function generate_test_id() {
  local blueprint="${1:-test_blueprint}"

  "$KGSM_MAIN_SCRIPT" instances generate-id "$blueprint"
  return $?
}

export -f generate_test_id

declare -g TEST_KGSM_WRAPPER_LOADED=1
export TEST_KGSM_WRAPPER_LOADED
