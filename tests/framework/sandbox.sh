#!/usr/bin/env bash
# KGSM Testing Framework - Sandbox Module
# Purpose: Manage isolated test environments (sandbox creation and cleanup)
# Dependencies: loader.sh (paths), config.sh (test configuration)
# Usage: source tests/framework/sandbox.sh

# ============================================================================
# Load Guard
# ============================================================================

# Prevent double-loading
if [[ -n "${TEST_SANDBOX_LOADED:-}" ]]; then
  return 0
fi

# ============================================================================
# Dependency Verification
# ============================================================================

# Note: TEST_SANDBOX_ROOT is set dynamically by runner.sh
# We use TEST_SANDBOX_ROOT_BASE from config.sh as fallback

# ============================================================================
# Sandbox ID Generation
# ============================================================================

# Generate unique sandbox identifier
# Usage: __generate_sandbox_id "test_name" "test_type"
# Returns: Unique sandbox ID (e.g., "unit_test_config_12345")
function __generate_sandbox_id() {
  local test_name="$1"
  local test_type="${2:-test}"

  # Sanitize test name (remove paths, special chars)
  local safe_name
  safe_name=$(basename "$test_name" .sh)
  safe_name="${safe_name//[^a-zA-Z0-9_]/_}"

  # Use timestamp + random for parallel safety
  local timestamp
  timestamp=$(date +%s)
  local random_suffix
  random_suffix=$(printf "%04d" $RANDOM)

  echo "${test_type}_${safe_name}_${timestamp}_${random_suffix}"
}

export -f __generate_sandbox_id

# ============================================================================
# Sandbox Creation
# ============================================================================

# Create isolated KGSM sandbox environment
# Usage: create_sandbox "sandbox_id"
# Returns: Path to created sandbox (stdout), exits 1 on failure
function create_sandbox() {
  local sandbox_id="$1"

  # Validate input
  if [[ -z "$sandbox_id" ]]; then
    echo "ERROR: Sandbox ID required" >&2
    return 1
  fi

  # Determine sandbox root (prefer TEST_SANDBOX_ROOT if set by runner, otherwise use base)
  local sandbox_root="${TEST_SANDBOX_ROOT:-${TEST_SANDBOX_ROOT_BASE}/kgsm-test-sandboxes}"
  local sandbox_path="${sandbox_root}/${sandbox_id}"

  # Create sandbox root if needed
  if [[ ! -d "$sandbox_root" ]]; then
    if ! mkdir -p "$sandbox_root"; then
      echo "ERROR: Failed to create sandbox root: $sandbox_root" >&2
      return 1
    fi
  fi

  # Remove existing sandbox if present
  if [[ -d "$sandbox_path" ]]; then
    if ! rm -rf "$sandbox_path"; then
      echo "ERROR: Failed to remove existing sandbox: $sandbox_path" >&2
      return 1
    fi
  fi

  # Create sandbox directory
  if ! mkdir -p "$sandbox_path"; then
    echo "ERROR: Failed to create sandbox directory: $sandbox_path" >&2
    return 1
  fi

  # Copy KGSM to sandbox
  if ! cp -r "$KGSM_ROOT"/* "$sandbox_path/"; then
    echo "ERROR: Failed to copy KGSM to sandbox" >&2
    rm -rf "$sandbox_path" # Cleanup partial copy
    return 1
  fi

  # Create test-specific config
  if ! create_test_config "$sandbox_path"; then
    echo "ERROR: Failed to create test config in sandbox" >&2
    rm -rf "$sandbox_path" # Cleanup incomplete sandbox
    return 1
  fi

  # Set executable permissions (REQUIRED - tests cannot proceed without correct permissions)
  if ! chmod +x "$sandbox_path/kgsm.sh"; then
    echo "ERROR: Failed to set executable permission on kgsm.sh" >&2
    rm -rf "$sandbox_path"
    return 1
  fi

  if ! find "$sandbox_path/commands" -type f -name "*.sh" -exec chmod +x {} \; 2> /dev/null; then
    echo "ERROR: Failed to set executable permissions on command scripts" >&2
    rm -rf "$sandbox_path"
    return 1
  fi

  if ! find "$sandbox_path/core" -type f -name "*.sh" -exec chmod +x {} \; 2> /dev/null; then
    echo "ERROR: Failed to set executable permissions on core scripts" >&2
    rm -rf "$sandbox_path"
    return 1
  fi

  # Verify sandbox is complete and usable
  if ! validate_sandbox "$sandbox_path"; then
    echo "ERROR: Sandbox validation failed" >&2
    rm -rf "$sandbox_path"
    return 1
  fi

  # Export sandbox path for test environment
  declare -g TEST_SANDBOX_DIR="$sandbox_path"
  export TEST_SANDBOX_DIR
  declare -g TEST_SANDBOX_KGSM_ROOT="$sandbox_path"
  export TEST_SANDBOX_KGSM_ROOT

  # Return sandbox path
  echo "$sandbox_path"
  return 0
}

export -f create_sandbox

# ============================================================================
# Test Configuration Creation
# ============================================================================

# Create test-specific config.ini in sandbox
# Usage: create_test_config "/path/to/sandbox"
# Returns: 0 on success, 1 on failure
function create_test_config() {
  local sandbox_path="$1"
  local config_file="${sandbox_path}/config.ini"
  local default_config="${sandbox_path}/config.default.ini"

  # Validate inputs
  if [[ -z "$sandbox_path" ]]; then
    echo "ERROR: Sandbox path required" >&2
    return 1
  fi

  if [[ ! -d "$sandbox_path" ]]; then
    echo "ERROR: Sandbox directory not found: $sandbox_path" >&2
    return 1
  fi

  if [[ ! -f "$default_config" ]]; then
    echo "ERROR: Default config not found: $default_config" >&2
    return 1
  fi

  # Copy default config as base
  if ! cp "$default_config" "$config_file"; then
    echo "ERROR: Failed to copy default config" >&2
    return 1
  fi

  # Append test environment overrides
  cat >> "$config_file" << 'EOF'

# =============================================================================
# TEST ENVIRONMENT OVERRIDES (Generated by testing framework)
# =============================================================================

[system]
# Disable system integrations that require root or external services
enable_systemd=false
enable_firewall_management=false
enable_port_forwarding=false
enable_event_broadcasting=false
enable_command_shortcuts=false

[instance_defaults]
# Set test-specific paths (relative to sandbox)
default_install_directory=instances
instance_suffix_length=3
instance_auto_update_before_start=false

[services]
# Reduce timeouts for faster test execution
instance_save_command_timeout_seconds=2
instance_stop_command_timeout_seconds=5
instance_start_command_timeout_seconds=10

[watchers]
# Disable resource-intensive watchers in tests
enable_log_watcher=false
enable_port_watcher=false

[accessibility]
# Enable logging for test debugging
enable_logging=true
log_level=DEBUG
log_console_enabled=false
log_max_size_kb=1024

[events]
# Disable network-based event systems
enable_webhook_events=false
enable_socket_events=false

EOF

  # Verify config was created
  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Config file not created: $config_file" >&2
    return 1
  fi

  return 0
}

export -f create_test_config

# ============================================================================
# Sandbox Cleanup
# ============================================================================

# Remove sandbox environment and all contents
# Usage: cleanup_sandbox "/path/to/sandbox"
# Returns: 0 (always succeeds, idempotent)
function cleanup_sandbox() {
  local sandbox_path="$1"

  # Skip if no path provided
  if [[ -z "$sandbox_path" ]]; then
    return 0
  fi

  # Safety check: Only delete paths under TEST_SANDBOX_ROOT or TEST_SANDBOX_ROOT_BASE
  local sandbox_root="${TEST_SANDBOX_ROOT:-${TEST_SANDBOX_ROOT_BASE}/kgsm-test-sandboxes}"
  if [[ "$sandbox_path" != "$sandbox_root"* ]] && [[ "$sandbox_path" != "/tmp/kgsm-test-sandbox"* ]]; then
    echo "WARNING: Refusing to delete path outside sandbox root: $sandbox_path" >&2
    return 0
  fi

  # Remove sandbox if it exists
  if [[ -d "$sandbox_path" ]]; then
    if ! rm -rf "$sandbox_path" 2> /dev/null; then
      echo "WARNING: Failed to remove sandbox: $sandbox_path" >&2
      # Continue anyway (non-fatal)
    fi
  fi

  # Unset sandbox environment variables
  unset TEST_SANDBOX_DIR
  unset TEST_SANDBOX_KGSM_ROOT

  return 0
}

export -f cleanup_sandbox

# ============================================================================
# Sandbox Validation
# ============================================================================

# Verify sandbox is complete and usable
# Usage: validate_sandbox "/path/to/sandbox"
# Returns: 0 if valid, 1 if invalid
function validate_sandbox() {
  local sandbox_path="$1"

  if [[ -z "$sandbox_path" ]]; then
    echo "ERROR: Sandbox path required" >&2
    return 1
  fi

  # Check sandbox directory exists
  if [[ ! -d "$sandbox_path" ]]; then
    echo "ERROR: Sandbox directory not found: $sandbox_path" >&2
    return 1
  fi

  # Check required files exist
  local required_files=(
    "kgsm.sh"
    "config.ini"
    "core/bootstrap.sh"
    "core/common.sh"
    "commands/instances.sh"
  )

  for file in "${required_files[@]}"; do
    if [[ ! -f "$sandbox_path/$file" ]]; then
      echo "ERROR: Required file missing in sandbox: $file" >&2
      return 1
    fi
  done

  # Check kgsm.sh is executable
  if [[ ! -x "$sandbox_path/kgsm.sh" ]]; then
    echo "ERROR: kgsm.sh not executable in sandbox" >&2
    return 1
  fi

  return 0
}

export -f validate_sandbox

# ============================================================================
# Utility Functions
# ============================================================================

# List all active sandboxes
# Usage: list_sandboxes
# Returns: Array of sandbox paths (one per line)
function list_sandboxes() {
  local sandbox_root="${TEST_SANDBOX_ROOT:-${TEST_SANDBOX_ROOT_BASE}/kgsm-test-sandboxes}"

  if [[ ! -d "$sandbox_root" ]]; then
    return 0
  fi

  find "$sandbox_root" -mindepth 1 -maxdepth 1 -type d 2> /dev/null
}

export -f list_sandboxes

# Remove sandboxes older than specified age
# Usage: cleanup_old_sandboxes [age_in_hours]
# Returns: Number of sandboxes removed
function cleanup_old_sandboxes() {
  local max_age_hours="${1:-24}"
  local sandbox_root="${TEST_SANDBOX_ROOT:-${TEST_SANDBOX_ROOT_BASE}/kgsm-test-sandboxes}"
  local removed_count=0

  if [[ ! -d "$sandbox_root" ]]; then
    echo "0"
    return 0
  fi

  # Find and remove old sandboxes
  while IFS= read -r sandbox_path; do
    if [[ -d "$sandbox_path" ]]; then
      # Check if sandbox is older than max_age_hours
      local sandbox_age
      sandbox_age=$(find "$sandbox_path" -maxdepth 0 -type d -mmin "+$((max_age_hours * 60))" 2> /dev/null || echo "")

      if [[ -n "$sandbox_age" ]]; then
        if cleanup_sandbox "$sandbox_path"; then
          ((removed_count++))
        fi
      fi
    fi
  done < <(list_sandboxes)

  echo "$removed_count"
  return 0
}

export -f cleanup_old_sandboxes

# Calculate total size of a sandbox
# Usage: get_sandbox_size "/path/to/sandbox"
# Returns: Size in KB
function get_sandbox_size() {
  local sandbox_path="$1"

  if [[ ! -d "$sandbox_path" ]]; then
    echo "0"
    return 0
  fi

  du -sk "$sandbox_path" 2> /dev/null | awk '{print $1}'
}

export -f get_sandbox_size

# ============================================================================
# Module Initialization Complete
# ============================================================================

declare -g TEST_SANDBOX_LOADED=1
export TEST_SANDBOX_LOADED
