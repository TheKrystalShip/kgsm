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
declare -gr TEST_LATEST_LINK="${TEST_LOGS_DIR}/latest"

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
declare -g KGSM_CORE_DIR="${KGSM_ROOT}/core"
declare -g KGSM_COMMANDS_DIR="${KGSM_ROOT}/commands"
declare -g KGSM_OVERRIDES_DIR="${KGSM_ROOT}/overrides"
declare -g KGSM_BLUEPRINTS_DIR="${KGSM_ROOT}/blueprints"
declare -g KGSM_TEMPLATES_DIR="${KGSM_ROOT}/templates"
declare -g KGSM_INSTANCES_DIR="${KGSM_ROOT}/instances"

# KGSM core files
declare -g KGSM_BOOTSTRAP_FILE="${KGSM_CORE_DIR}/bootstrap.sh"
declare -g KGSM_COMMON_FILE="${KGSM_CORE_DIR}/common.sh"
declare -g KGSM_LOADER_FILE="${KGSM_CORE_DIR}/loader.sh"
declare -g KGSM_CONFIG_FILE="${KGSM_ROOT}/config.ini"
declare -g KGSM_MAIN_SCRIPT="${KGSM_ROOT}/kgsm.sh"

# ============================================================================
# Path Constants - Sandbox (Runtime-Set)
# ============================================================================

# Sandbox base directory (set by run.sh or test script)
# These are NOT readonly because they're set at runtime by test runner
declare -g TEST_SANDBOX_DIR="${TEST_SANDBOX_DIR:-}"
declare -g TEST_SANDBOX_KGSM_ROOT="${TEST_SANDBOX_KGSM_ROOT:-}"
declare -g TEST_SANDBOX_INSTANCES_INSTALL_DIR="${TEST_SANDBOX_INSTANCES_INSTALL_DIR:-}"


# ============================================================================
# Module Initialization Complete
# ============================================================================

declare -g TEST_LOADER_LOADED=1
export TEST_LOADER_LOADED
