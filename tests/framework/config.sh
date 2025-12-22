#!/usr/bin/env bash
# KGSM Testing Framework - Configuration Module
# Purpose: Load and manage test framework configuration
# Dependencies: loader.sh (paths), logging.sh (logging functions)
# Usage: source tests/framework/config.sh

# ============================================================================
# Load Guard
# ============================================================================

# Prevent double-loading
if [[ -n "${TEST_CONFIG_LOADED:-}" ]]; then
  return 0
fi

# ============================================================================
# Dependency Verification
# ============================================================================

# Verify required paths are set
if [[ -z "${TEST_ROOT:-}" ]] || [[ -z "${TEST_CONFIG_DIR:-}" ]]; then
  echo "ERROR: TEST_ROOT and TEST_CONFIG_DIR must be set" >&2
  return 1
fi

# ============================================================================
# Apply Configuration Defaults
# ============================================================================

# Apply default configuration values
# Usage: __apply_config_defaults
# Returns: 0 (always succeeds)
function __apply_config_defaults() {
  # Framework Control

  # TEST_DEBUG is unique, it gets set by starting tests with the "--debug" flag
  # So we verify first if it's already been set, that way we don't override the
  # value
  if [[ -z "${TEST_DEBUG}" ]]; then
    declare -g TEST_DEBUG=false
  fi

  declare -g TEST_VERBOSE=false
  declare -g TEST_QUIET=false

  # TEST_PARALLEL: Only set default if not already set (allows env var override)
  if [[ -z "${TEST_PARALLEL:-}" ]]; then
    declare -g TEST_PARALLEL=1  # Default: sequential execution
  fi
  declare -g TEST_MAX_PARALLEL=4  # Legacy, kept for backward compatibility

  # Sandbox Configuration
  declare -g TEST_SANDBOX_ROOT_BASE="/tmp"
  declare -g TEST_KEEP_SANDBOXES=false

  # Timeout Settings (seconds)
  declare -g TEST_DEFAULT_TIMEOUT=300
  declare -g TEST_INSTANCE_CREATE_TIMEOUT=600
  declare -g TEST_SERVER_STARTUP_TIMEOUT=120

  # Path Configuration
  declare -g TEST_DATA_DIR="${TEST_ROOT}/data"
  declare -g TEST_TEMP_BASE="/tmp"

  # Logging Configuration
  declare -g TEST_VERBOSE_LOGGING=false
  declare -g TEST_MAX_LOG_SIZE=10240

  # Skip Controls (defaults to false, test.conf overrides)
  declare -g SKIP_NETWORK_TESTS=false
  declare -g SKIP_LONG_DOWNLOAD_TESTS=false
  declare -g SKIP_DOCKER_TESTS=false
  declare -g SKIP_STEAMCMD_TESTS=false
  declare -g SKIP_PERFORMANCE_TESTS=true
  declare -g SKIP_STRESS_TESTS=true

  # Game Selection
  declare -g TEST_GAMES="factorio necesse vrising"
  declare -g SKIP_FACTORIO_TESTS=false
  declare -g SKIP_NECESSE_TESTS=false
  declare -g SKIP_VRISING_TESTS=false

  # Runtime Variables (set by runner, not config file)
  declare -g TEST_SANDBOX_ROOT=""
  declare -g TEST_LOG_DIR=""
  declare -g TEST_RESULTS_FILE=""
  declare -ga TEST_TYPES=()
  declare -ga TEST_PATTERNS=()
  declare -ga TEST_EXCLUDE=()

  # Test Counters (runtime only)
  declare -g TESTS_TOTAL=0
  declare -g TESTS_PASSED=0
  declare -g TESTS_FAILED=0
  declare -g TESTS_SKIPPED=0
  declare -g TESTS_ERRORS=0
  declare -g GLOBAL_ASSERTIONS_TOTAL=0
  declare -g GLOBAL_ASSERTIONS_PASSED=0
  declare -g GLOBAL_ASSERTIONS_FAILED=0

  return 0
}

# ============================================================================
# Load Test Configuration File
# ============================================================================

# Load test configuration from tests/config/test.conf
# Usage: __load_test_config_file
# Returns: 0 on success or if file missing, 1 on load failure
function __load_test_config_file() {
  local config_file="${TEST_CONFIG_DIR}/config.test.ini"

  # Missing config file is not fatal
  if [[ ! -f "$config_file" ]]; then
    log_info "Test configuration file not found: $config_file"
    log_info "Using default configuration values"
    return 0
  fi

  # Source the configuration file
  if ! source "$config_file"; then
    log_error "Failed to load test configuration: $config_file"
    return 1
  fi

  log_debug "Loaded test configuration from: $config_file"
  return 0
}

# ============================================================================
# Validate Configuration Basics
# ============================================================================

# Perform basic validation of critical configuration values
# Usage: __validate_config_basics
# Returns: 0 if valid, 1 if invalid
function __validate_config_basics() {
  local validation_failed=false

  # Validate timeout values are positive integers
  if ! [[ "$TEST_DEFAULT_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TEST_DEFAULT_TIMEOUT" -le 0 ]]; then
    log_error "TEST_DEFAULT_TIMEOUT must be positive integer, got: $TEST_DEFAULT_TIMEOUT"
    validation_failed=true
  fi

  if ! [[ "$TEST_INSTANCE_CREATE_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TEST_INSTANCE_CREATE_TIMEOUT" -le 0 ]]; then
    log_error "TEST_INSTANCE_CREATE_TIMEOUT must be positive integer, got: $TEST_INSTANCE_CREATE_TIMEOUT"
    validation_failed=true
  fi

  if ! [[ "$TEST_SERVER_STARTUP_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TEST_SERVER_STARTUP_TIMEOUT" -le 0 ]]; then
    log_error "TEST_SERVER_STARTUP_TIMEOUT must be positive integer, got: $TEST_SERVER_STARTUP_TIMEOUT"
    validation_failed=true
  fi

  # TEST_PARALLEL is validated and normalized by __normalize_test_parallel()
  # Just verify it's a valid integer here (it should be after normalization)
  if ! [[ "$TEST_PARALLEL" =~ ^[0-9]+$ ]] || [[ "$TEST_PARALLEL" -lt 1 ]]; then
    log_error "TEST_PARALLEL must be positive integer >= 1, got: $TEST_PARALLEL"
    validation_failed=true
  fi

  # Validate max log size is positive integer
  if ! [[ "$TEST_MAX_LOG_SIZE" =~ ^[0-9]+$ ]] || [[ "$TEST_MAX_LOG_SIZE" -le 0 ]]; then
    log_error "TEST_MAX_LOG_SIZE must be positive integer, got: $TEST_MAX_LOG_SIZE"
    validation_failed=true
  fi

  # Validate TEST_SANDBOX_ROOT_BASE exists (not created yet, but base should be valid)
  if [[ ! -d "$TEST_SANDBOX_ROOT_BASE" ]]; then
    log_warning "TEST_SANDBOX_ROOT_BASE does not exist: $TEST_SANDBOX_ROOT_BASE"
    log_info "Sandbox creation may fail if base directory is not writable"
  fi

  # Validate TEST_DATA_DIR exists (if tests need data files)
  if [[ ! -d "$TEST_DATA_DIR" ]]; then
    log_debug "TEST_DATA_DIR does not exist: $TEST_DATA_DIR"
    log_debug "This is normal if no test data files are present"
  fi

  if [[ "$validation_failed" == "true" ]]; then
    return 1
  fi

  return 0
}

# ============================================================================
# Normalize TEST_PARALLEL Configuration
# ============================================================================

# Normalize TEST_PARALLEL to an integer value
# Handles backward compatibility with boolean values (true/false)
# Handles "auto" detection based on CPU cores
# Usage: __normalize_test_parallel
# Returns: 0 (always succeeds, invalid values default to 1)
function __normalize_test_parallel() {
  local original_value="${TEST_PARALLEL}"

  # Handle legacy boolean values (backward compatibility)
  if [[ "${TEST_PARALLEL}" == "true" ]]; then
    log_warning "TEST_PARALLEL=true is deprecated, using TEST_PARALLEL=${TEST_MAX_PARALLEL:-4}"
    TEST_PARALLEL="${TEST_MAX_PARALLEL:-4}"
  elif [[ "${TEST_PARALLEL}" == "false" ]]; then
    # false means sequential (1 job at a time)
    TEST_PARALLEL=1
  fi

  # Handle auto-detection
  if [[ "${TEST_PARALLEL}" == "auto" ]]; then
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || echo "4")
    TEST_PARALLEL=$((cpu_count / 2))
    # Ensure at least 1
    [[ $TEST_PARALLEL -lt 1 ]] && TEST_PARALLEL=1
    log_info "Auto-detected TEST_PARALLEL=${TEST_PARALLEL} (CPU cores: ${cpu_count})"
  fi

  # Validate integer range
  if ! [[ "${TEST_PARALLEL}" =~ ^[0-9]+$ ]]; then
    log_warning "Invalid TEST_PARALLEL='${TEST_PARALLEL}', using default: 1"
    TEST_PARALLEL=1
  elif [[ "${TEST_PARALLEL}" -lt 1 ]]; then
    log_warning "TEST_PARALLEL must be >= 1, using: 1"
    TEST_PARALLEL=1
  elif [[ "${TEST_PARALLEL}" -gt 32 ]]; then
    log_warning "TEST_PARALLEL exceeds maximum (32), using: 32"
    TEST_PARALLEL=32
  fi

  # Resource warnings for high concurrency
  if [[ "${TEST_PARALLEL}" -gt 16 ]]; then
    log_warning "TEST_PARALLEL=${TEST_PARALLEL} is very high, may cause resource contention"
  fi

  # Log if value was changed
  if [[ "$original_value" != "$TEST_PARALLEL" ]]; then
    log_debug "Normalized TEST_PARALLEL: '$original_value' -> '$TEST_PARALLEL'"
  fi

  return 0
}

# ============================================================================
# Export Configuration Variables
# ============================================================================

# Export configuration variables for use by framework modules and tests
# Usage: __export_config_variables
# Returns: 0 (always succeeds)
function __export_config_variables() {
  # Framework Control
  export TEST_DEBUG
  export TEST_VERBOSE
  export TEST_QUIET
  export TEST_PARALLEL
  export TEST_MAX_PARALLEL

  # Sandbox Configuration
  export TEST_SANDBOX_ROOT_BASE
  export TEST_KEEP_SANDBOXES

  # Timeout Settings
  export TEST_DEFAULT_TIMEOUT
  export TEST_INSTANCE_CREATE_TIMEOUT
  export TEST_SERVER_STARTUP_TIMEOUT

  # Path Configuration
  export TEST_DATA_DIR
  export TEST_TEMP_BASE

  # Logging Configuration
  export TEST_VERBOSE_LOGGING
  export TEST_MAX_LOG_SIZE

  # Skip Controls (all SKIP_* variables)
  export SKIP_NETWORK_TESTS
  export SKIP_LONG_DOWNLOAD_TESTS
  export SKIP_DOCKER_TESTS
  export SKIP_STEAMCMD_TESTS
  export SKIP_PERFORMANCE_TESTS
  export SKIP_STRESS_TESTS
  export SKIP_FACTORIO_TESTS
  export SKIP_NECESSE_TESTS
  export SKIP_VRISING_TESTS

  # Game Selection
  export TEST_GAMES

  # Runtime Variables (exported for consistency)
  export TEST_SANDBOX_ROOT
  export TEST_LOG_DIR
  export TEST_RESULTS_FILE
  export TEST_TYPES
  export TEST_PATTERNS
  export TEST_EXCLUDE

  # Test Counters (exported for reporting)
  export TESTS_TOTAL
  export TESTS_PASSED
  export TESTS_FAILED
  export TESTS_SKIPPED
  export TESTS_ERRORS
  export GLOBAL_ASSERTIONS_TOTAL
  export GLOBAL_ASSERTIONS_PASSED
  export GLOBAL_ASSERTIONS_FAILED

  return 0
}

# ============================================================================
# Initialize Configuration System
# ============================================================================

# Initialize the test configuration system
# This is the main entry point called by common.sh
# Usage: __init_test_config
# Returns: 0 on success, 1 on failure
function __init_test_config() {
    log_debug "Initializing test configuration system"

    # Step 1: Apply defaults
    __apply_config_defaults

    # Step 2: Load user configuration
    if ! __load_test_config_file; then
        log_error "Failed to load test configuration file"
        return 1
    fi

    # Step 3: Normalize TEST_PARALLEL (backward compatibility + validation)
    __normalize_test_parallel

    # Step 4: Validate configuration
    if ! __validate_config_basics; then
        log_error "Configuration validation failed"
        return 1
    fi

    # Step 5: Export variables
    __export_config_variables

    log_debug "Test configuration system initialized successfully"
}

# Immediately call initialization when sourced
if ! __init_test_config; then
  echo "ERROR: Test configuration initialization failed" >&2
  exit 1
fi

# ============================================================================
# Module Initialization Complete
# ============================================================================

declare -g TEST_CONFIG_LOADED=1
export TEST_CONFIG_LOADED
