#!/usr/bin/env bash

# KGSM Lifecycle Logic Unit Tests
#
# This test suite provides comprehensive unit testing for the pure logic functions
# in lib/logic/lifecycle.sh. These tests focus on testing the business logic
# in isolation without external dependencies.

# =============================================================================
# TEST SETUP
# =============================================================================

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="lifecycle_logic"

# Test instance names for different scenarios
readonly TEST_SYSTEMD_INSTANCE="test_systemd_$(date +%s)_$$"
readonly TEST_STANDALONE_INSTANCE="test_standalone_$(date +%s)_$$"
readonly TEST_INVALID_INSTANCE="nonexistent_instance_$(date +%s)_$$"

# =============================================================================
# MOCK FUNCTIONS
# =============================================================================

# Mock systemctl command for testing systemd operations
function mock_systemctl() {
  local action="$1"
  local service="$2"

  log_test "Mock systemctl called: $action $service"

  # Store the call for verification
  echo "$action $service" >> "$KGSM_TEST_SANDBOX/systemctl_calls.log"

  # Simulate different behaviors based on service name and action
  case "$service" in
    *fail*)
      log_test "Mock systemctl: simulating failure for $service"
      return 1
      ;;
    *)
      log_test "Mock systemctl: simulating success for $service"
      case "$action" in
        "is-active")
          echo "active"
          ;;
        "start" | "stop")
          return 0
          ;;
        *)
          return 0
          ;;
      esac
      ;;
  esac
}

# Mock management script for testing standalone operations
function mock_management_script() {
  local script_path="$1"
  shift
  local args="$@"

  log_test "Mock management script called: $script_path $args"

  # Store the call for verification
  echo "$script_path $args" >> "$KGSM_TEST_SANDBOX/management_calls.log"

  # Simulate different behaviors based on script path and arguments
  case "$script_path" in
    *fail*)
      log_test "Mock management script: simulating failure for $script_path"
      return 1
      ;;
    *)
      log_test "Mock management script: simulating success for $script_path"
      case "$args" in
        *"--is-active"*)
          return 0  # Active
          ;;
        *"--start"* | *"--stop"* | *"--logs"* | *"--status"*)
          return 0
          ;;
        *)
          return 0
          ;;
      esac
      ;;
  esac
}

# Mock journalctl command for testing systemd log operations
function mock_journalctl() {
  local args="$@"

  log_test "Mock journalctl called: $args"
  echo "$args" >> "$KGSM_TEST_SANDBOX/journalctl_calls.log"

  # Simulate log output
  echo "Mock log entry 1"
  echo "Mock log entry 2"
  echo "Mock log entry 3"

  return 0
}

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

# Create a test instance configuration file
function create_test_instance_config() {
  local instance_name="$1"
  local lifecycle_manager="$2"
  local management_file="${3:-$KGSM_TEST_SANDBOX/mock_management.sh}"

  local config_file="$KGSM_INSTANCES_DIR/${instance_name}.ini"

  log_test "Creating test instance config: $config_file"

  # Ensure instances directory exists
  mkdir -p "$KGSM_INSTANCES_DIR"

  # Create the configuration file
  cat > "$config_file" << EOF
# Test instance configuration
name="$instance_name"
lifecycle_manager="$lifecycle_manager"
management_file="$management_file"
runtime="native"
pid_file="$KGSM_TEST_SANDBOX/${instance_name}.pid"
log_file="$KGSM_TEST_SANDBOX/${instance_name}.log"
startup_success_regex="Server started"
stop_command="/quit"
save_command="/save"
EOF

  # Create mock management script if it doesn't exist
  if [[ ! -f "$management_file" ]]; then
    cat > "$management_file" << 'EOF'
#!/usr/bin/env bash
# Mock management script for testing
mock_management_script "$0" "$@"
EOF
    chmod +x "$management_file"
  fi

  log_test "Test instance config created: $config_file"
  return 0
}

# Remove test instance configuration
function remove_test_instance_config() {
  local instance_name="$1"
  local config_file="$KGSM_INSTANCES_DIR/${instance_name}.ini"

  if [[ -f "$config_file" ]]; then
    rm -f "$config_file"
    log_test "Removed test instance config: $config_file"
  fi
}

# Setup mock environment for testing
function setup_mock_environment() {
  log_step "Setting up mock environment for lifecycle logic testing"

  # Create mock call log files
  touch "$KGSM_TEST_SANDBOX/systemctl_calls.log"
  touch "$KGSM_TEST_SANDBOX/management_calls.log"
  touch "$KGSM_TEST_SANDBOX/journalctl_calls.log"

  # Create mock bin directory and add to PATH
  mkdir -p "$KGSM_TEST_SANDBOX/mock_bin"
  export PATH="$KGSM_TEST_SANDBOX/mock_bin:$PATH"

  # Create mock sudo script that passes through to our mocks
  cat > "$KGSM_TEST_SANDBOX/mock_bin/sudo" << EOF
#!/usr/bin/env bash
# Mock sudo for testing - just pass through to the actual command
# Skip the -E flag and execute the rest
if [[ "\$1" == "-E" ]]; then
  shift
fi
exec "\$@"
EOF
  chmod +x "$KGSM_TEST_SANDBOX/mock_bin/sudo"

  # Create mock systemctl script
  cat > "$KGSM_TEST_SANDBOX/mock_bin/systemctl" << EOF
#!/usr/bin/env bash
# Mock systemctl for testing
KGSM_TEST_SANDBOX="$KGSM_TEST_SANDBOX"

function mock_systemctl() {
  local action="\$1"
  local service="\$2"

  echo "Mock systemctl called: \$action \$service" >&2

  # Store the call for verification
  echo "\$action \$service" >> "\$KGSM_TEST_SANDBOX/systemctl_calls.log"

  # Simulate different behaviors based on service name and action
  case "\$service" in
    *fail*)
      echo "Mock systemctl: simulating failure for \$service" >&2
      return 1
      ;;
    *)
      echo "Mock systemctl: simulating success for \$service" >&2
      case "\$action" in
        "is-active")
          echo "active"
          ;;
        "start"|"stop")
          return 0
          ;;
        *)
          return 0
          ;;
      esac
      ;;
  esac
}

mock_systemctl "\$@"
EOF
  chmod +x "$KGSM_TEST_SANDBOX/mock_bin/systemctl"

  # Create mock journalctl script
  cat > "$KGSM_TEST_SANDBOX/mock_bin/journalctl" << EOF
#!/usr/bin/env bash
# Mock journalctl for testing
KGSM_TEST_SANDBOX="$KGSM_TEST_SANDBOX"

function mock_journalctl() {
  local args="\$@"

  echo "Mock journalctl called: \$args" >&2
  echo "\$args" >> "\$KGSM_TEST_SANDBOX/journalctl_calls.log"

  # Simulate log output
  echo "Mock log entry 1"
  echo "Mock log entry 2"
  echo "Mock log entry 3"

  return 0
}

mock_journalctl "\$@"
EOF
  chmod +x "$KGSM_TEST_SANDBOX/mock_bin/journalctl"

  # Export mock functions so they can be used by the mock scripts
  export -f mock_systemctl
  export -f mock_management_script
  export -f mock_journalctl

  log_test "Mock environment setup complete"
}

# Cleanup mock environment
function cleanup_mock_environment() {
  log_step "Cleaning up mock environment"

  # Remove test instance configs
  remove_test_instance_config "$TEST_SYSTEMD_INSTANCE"
  remove_test_instance_config "$TEST_STANDALONE_INSTANCE"

  # Clean up mock log files
  rm -f "$KGSM_TEST_SANDBOX/systemctl_calls.log"
  rm -f "$KGSM_TEST_SANDBOX/management_calls.log"
  rm -f "$KGSM_TEST_SANDBOX/journalctl_calls.log"

  log_test "Mock environment cleanup complete"
}

# Verify that a mock command was called with specific arguments
function assert_mock_called() {
  local mock_type="$1"  # systemctl, management, or journalctl
  local expected_call="$2"
  local message="${3:-Mock call assertion failed}"

  local log_file="$KGSM_TEST_SANDBOX/${mock_type}_calls.log"

  if [[ -f "$log_file" ]] && grep -q "$expected_call" "$log_file"; then
    assert_true "true" "$message: $mock_type was called with '$expected_call'"
  else
    assert_true "false" "$message: $mock_type was NOT called with '$expected_call'"
    if [[ -f "$log_file" ]]; then
      log_test "Actual $mock_type calls:"
      cat "$log_file" | while read -r line; do
        log_test "  $line"
      done
    fi
  fi
}

# =============================================================================
# LIFECYCLE LOGIC LIBRARY LOADING TESTS
# =============================================================================

function test_lifecycle_logic_library_loading() {
  log_step "Testing lifecycle logic library loading"

  # Source the lifecycle logic library
  local logic_lib="$KGSM_ROOT/lib/logic/lifecycle.sh"
  assert_file_exists "$logic_lib" "Lifecycle logic library should exist"

  # Source the library (this should load all required dependencies)
  if source "$logic_lib"; then
    assert_true "true" "Lifecycle logic library should load successfully"
  else
    assert_true "false" "Lifecycle logic library should load successfully"
  fi

  # Verify that key functions are available
  assert_function_exists "__logic_instance_start" "Start logic function should be available"
  assert_function_exists "__logic_instance_stop" "Stop logic function should be available"
  assert_function_exists "__logic_instance_restart" "Restart logic function should be available"
  assert_function_exists "__logic_instance_is_active" "Is active logic function should be available"
  assert_function_exists "__logic_instance_status" "Status logic function should be available"
  assert_function_exists "__logic_instance_logs" "Logs logic function should be available"
  assert_function_exists "__get_lifecycle_manager" "Helper function should be available"
}

# =============================================================================
# HELPER FUNCTION TESTS
# =============================================================================

function test_get_lifecycle_manager_function() {
  log_step "Testing __get_lifecycle_manager helper function"

  # Test with valid systemd instance
  create_test_instance_config "$TEST_SYSTEMD_INSTANCE" "systemd"
  local config_file="$KGSM_INSTANCES_DIR/${TEST_SYSTEMD_INSTANCE}.ini"

  local result
  result=$(__get_lifecycle_manager "$config_file")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return success for valid config"
  assert_equals "systemd" "$result" "Should return correct lifecycle manager"

  # Test with valid standalone instance
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone"
  config_file="$KGSM_INSTANCES_DIR/${TEST_STANDALONE_INSTANCE}.ini"

  result=$(__get_lifecycle_manager "$config_file")
  exit_code=$?

  assert_equals "0" "$exit_code" "Should return success for valid standalone config"
  assert_equals "standalone" "$result" "Should return correct lifecycle manager"

  # Test with missing argument
  __get_lifecycle_manager ""
  exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg error for empty argument"

  # Test with nonexistent file
  __get_lifecycle_manager "/nonexistent/file.ini"
  exit_code=$?
  assert_not_equals "0" "$exit_code" "Should return error for nonexistent file"
}

# =============================================================================
# INSTANCE START LOGIC TESTS
# =============================================================================

function test_instance_start_logic_systemd() {
  log_step "Testing __logic_instance_start with systemd instance"

  # Create test systemd instance
  create_test_instance_config "$TEST_SYSTEMD_INSTANCE" "systemd"

  # systemctl is mocked via PATH in setup_mock_environment

  # Test successful start
  __logic_instance_start "$TEST_SYSTEMD_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_STARTED" "$exit_code" "Should return instance started success code"
  assert_mock_called "systemctl" "start ${TEST_SYSTEMD_INSTANCE%.ini}" "systemctl start should be called"
}

function test_instance_start_logic_standalone() {
  log_step "Testing __logic_instance_start with standalone instance"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test successful start
  __logic_instance_start "$TEST_STANDALONE_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_STARTED" "$exit_code" "Should return instance started success code"
  assert_mock_called "management" "$management_file --start --background" "Management script should be called with start"
}

function test_instance_start_logic_invalid_args() {
  log_step "Testing __logic_instance_start with invalid arguments"

  # Test with empty instance name
  __logic_instance_start ""
  local exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg error for empty instance name"

  # Test with nonexistent instance
  __logic_instance_start "$TEST_INVALID_INSTANCE"
  exit_code=$?
  assert_not_equals "0" "$exit_code" "Should return error for nonexistent instance"
  assert_not_equals "$EC_SUCCESS_INSTANCE_STARTED" "$exit_code" "Should not return success for nonexistent instance"
}

function test_instance_start_logic_systemd_failure() {
  log_step "Testing __logic_instance_start with systemd instance - failure case"

  # Create test systemd instance with 'fail' in name to trigger mock failure
  local fail_instance="${TEST_SYSTEMD_INSTANCE}_fail"
  create_test_instance_config "$fail_instance" "systemd"

  # systemctl is mocked via PATH in setup_mock_environment

  # Test failed start
  __logic_instance_start "$fail_instance"
  local exit_code=$?

  assert_equals "$EC_SYSTEMD" "$exit_code" "Should return systemd error code for failed start"
  assert_mock_called "systemctl" "start ${fail_instance%.ini}" "systemctl start should be called even on failure"

  # Cleanup
  remove_test_instance_config "$fail_instance"
}

function test_instance_start_logic_standalone_failure() {
  log_step "Testing __logic_instance_start with standalone instance - failure case"

  # Create test standalone instance with 'fail' in management file path
  local fail_management_file="$KGSM_TEST_SANDBOX/test_management_fail.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$fail_management_file"

  # Test failed start
  __logic_instance_start "$TEST_STANDALONE_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_GENERAL" "$exit_code" "Should return general error code for failed standalone start"
  assert_mock_called "management" "$fail_management_file --start --background" "Management script should be called even on failure"
}

function test_instance_start_logic_standalone_missing_management_file() {
  log_step "Testing __logic_instance_start with standalone instance - missing management file config"

  # Create instance config without management_file
  local temp_instance="temp_$(date +%s)_$$"
  local config_file="$KGSM_INSTANCES_DIR/${temp_instance}.ini"
  mkdir -p "$KGSM_INSTANCES_DIR"

  cat > "$config_file" << EOF
name="$temp_instance"
lifecycle_manager="standalone"
runtime="native"
EOF

  # Test start with missing management file config
  __logic_instance_start "$temp_instance"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for missing management file"

  # Cleanup
  rm -f "$config_file"
}

function test_instance_start_logic_invalid_lifecycle_manager() {
  log_step "Testing __logic_instance_start with invalid lifecycle manager"

  # Create instance with invalid lifecycle manager
  local temp_instance="temp_invalid_$(date +%s)_$$"
  create_test_instance_config "$temp_instance" "invalid_manager"

  # Test start with invalid lifecycle manager
  __logic_instance_start "$temp_instance"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for invalid lifecycle manager"

  # Cleanup
  remove_test_instance_config "$temp_instance"
}

# =============================================================================
# INSTANCE STOP LOGIC TESTS
# =============================================================================

function test_instance_stop_logic_systemd() {
  log_step "Testing __logic_instance_stop with systemd instance"

  # Create test systemd instance
  create_test_instance_config "$TEST_SYSTEMD_INSTANCE" "systemd"

  # systemctl is mocked via PATH in setup_mock_environment

  # Test successful stop
  __logic_instance_stop "$TEST_SYSTEMD_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_STOPPED" "$exit_code" "Should return instance stopped success code"
  assert_mock_called "systemctl" "stop ${TEST_SYSTEMD_INSTANCE%.ini}" "systemctl stop should be called"
}

function test_instance_stop_logic_standalone() {
  log_step "Testing __logic_instance_stop with standalone instance"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test successful stop
  __logic_instance_stop "$TEST_STANDALONE_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_STOPPED" "$exit_code" "Should return instance stopped success code"
  assert_mock_called "management" "$management_file --stop" "Management script should be called with stop"
}

function test_instance_stop_logic_invalid_args() {
  log_step "Testing __logic_instance_stop with invalid arguments"

  # Test with empty instance name
  __logic_instance_stop ""
  local exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg error for empty instance name"

  # Test with nonexistent instance
  __logic_instance_stop "$TEST_INVALID_INSTANCE"
  exit_code=$?
  assert_not_equals "0" "$exit_code" "Should return error for nonexistent instance"
  assert_not_equals "$EC_SUCCESS_INSTANCE_STOPPED" "$exit_code" "Should not return success for nonexistent instance"
}

function test_instance_stop_logic_systemd_failure() {
  log_step "Testing __logic_instance_stop with systemd instance - failure case"

  # Create test systemd instance with 'fail' in name to trigger mock failure
  local fail_instance="${TEST_SYSTEMD_INSTANCE}_fail"
  create_test_instance_config "$fail_instance" "systemd"

  # systemctl is mocked via PATH in setup_mock_environment

  # Test failed stop
  __logic_instance_stop "$fail_instance"
  local exit_code=$?

  assert_equals "$EC_SYSTEMD" "$exit_code" "Should return systemd error code for failed stop"
  assert_mock_called "systemctl" "stop ${fail_instance%.ini}" "systemctl stop should be called even on failure"

  # Cleanup
  remove_test_instance_config "$fail_instance"
}

function test_instance_stop_logic_standalone_failure() {
  log_step "Testing __logic_instance_stop with standalone instance - failure case"

  # Create test standalone instance with 'fail' in management file path
  local fail_management_file="$KGSM_TEST_SANDBOX/test_management_fail.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$fail_management_file"

  # Test failed stop
  __logic_instance_stop "$TEST_STANDALONE_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_GENERAL" "$exit_code" "Should return general error code for failed standalone stop"
  assert_mock_called "management" "$fail_management_file --stop" "Management script should be called even on failure"
}

function test_instance_stop_logic_standalone_missing_management_file() {
  log_step "Testing __logic_instance_stop with standalone instance - missing management file config"

  # Create instance config without management_file
  local temp_instance="temp_stop_$(date +%s)_$$"
  local config_file="$KGSM_INSTANCES_DIR/${temp_instance}.ini"
  mkdir -p "$KGSM_INSTANCES_DIR"

  cat > "$config_file" << EOF
name="$temp_instance"
lifecycle_manager="standalone"
runtime="native"
EOF

  # Test stop with missing management file config
  __logic_instance_stop "$temp_instance"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for missing management file"

  # Cleanup
  rm -f "$config_file"
}

function test_instance_stop_logic_invalid_lifecycle_manager() {
  log_step "Testing __logic_instance_stop with invalid lifecycle manager"

  # Create instance with invalid lifecycle manager
  local temp_instance="temp_stop_invalid_$(date +%s)_$$"
  create_test_instance_config "$temp_instance" "invalid_manager"

  # Test stop with invalid lifecycle manager
  __logic_instance_stop "$temp_instance"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for invalid lifecycle manager"

  # Cleanup
  remove_test_instance_config "$temp_instance"
}

# =============================================================================
# INSTANCE RESTART LOGIC TESTS
# =============================================================================

function test_instance_restart_logic() {
  log_step "Testing __logic_instance_restart functionality"

  # Create test systemd instance
  create_test_instance_config "$TEST_SYSTEMD_INSTANCE" "systemd"

  # systemctl is mocked via PATH in setup_mock_environment

  # Test successful restart
  __logic_instance_restart "$TEST_SYSTEMD_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_RESTARTED" "$exit_code" "Should return instance restarted success code"

  # Verify both stop and start were called
  assert_mock_called "systemctl" "stop ${TEST_SYSTEMD_INSTANCE%.ini}" "systemctl stop should be called during restart"
  assert_mock_called "systemctl" "start ${TEST_SYSTEMD_INSTANCE%.ini}" "systemctl start should be called during restart"
}

function test_instance_restart_logic_invalid_args() {
  log_step "Testing __logic_instance_restart with invalid arguments"

  # Test with empty instance name
  __logic_instance_restart ""
  local exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg error for empty instance name"
}

function test_instance_restart_logic_standalone() {
  log_step "Testing __logic_instance_restart with standalone instance"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test successful restart
  __logic_instance_restart "$TEST_STANDALONE_INSTANCE"
  local exit_code=$?

  assert_equals "$EC_SUCCESS_INSTANCE_RESTARTED" "$exit_code" "Should return instance restarted success code"

  # Verify both stop and start were called
  assert_mock_called "management" "$management_file --stop" "Management script stop should be called during restart"
  assert_mock_called "management" "$management_file --start --background" "Management script start should be called during restart"
}

function test_instance_restart_logic_stop_failure() {
  log_step "Testing __logic_instance_restart with stop failure"

  # Create test systemd instance with 'fail' in name to trigger mock failure
  local fail_instance="${TEST_SYSTEMD_INSTANCE}_fail"
  create_test_instance_config "$fail_instance" "systemd"

  # systemctl is mocked via PATH in setup_mock_environment

  # Test restart with stop failure
  __logic_instance_restart "$fail_instance"
  local exit_code=$?

  assert_equals "$EC_SYSTEMD" "$exit_code" "Should return systemd error code when stop fails"
  assert_mock_called "systemctl" "stop ${fail_instance%.ini}" "systemctl stop should be called during restart"

  # Cleanup
  remove_test_instance_config "$fail_instance"
}

function test_instance_restart_logic_nonexistent_instance() {
  log_step "Testing __logic_instance_restart with nonexistent instance"

  # Test restart with nonexistent instance
  __logic_instance_restart "$TEST_INVALID_INSTANCE"
  local exit_code=$?

  assert_not_equals "0" "$exit_code" "Should return error for nonexistent instance"
  assert_not_equals "$EC_SUCCESS_INSTANCE_RESTARTED" "$exit_code" "Should not return success for nonexistent instance"
}

# =============================================================================
# INSTANCE STATUS LOGIC TESTS
# =============================================================================

function test_instance_is_active_logic_systemd() {
  log_step "Testing __logic_instance_is_active with systemd instance"

  # Create test systemd instance
  create_test_instance_config "$TEST_SYSTEMD_INSTANCE" "systemd"

  # systemctl is mocked via PATH in setup_mock_environment

  # Test active instance
  __logic_instance_is_active "$TEST_SYSTEMD_INSTANCE"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for active instance"
  assert_mock_called "systemctl" "is-active ${TEST_SYSTEMD_INSTANCE%.ini}" "systemctl is-active should be called"
}

function test_instance_is_active_logic_standalone() {
  log_step "Testing __logic_instance_is_active with standalone instance"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test active instance
  __logic_instance_is_active "$TEST_STANDALONE_INSTANCE"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for active instance"
  assert_mock_called "management" "$management_file --is-active" "Management script should be called with is-active"
}

function test_instance_status_logic() {
  log_step "Testing __logic_instance_status functionality"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test status call
  local output
  output=$(__logic_instance_status "$TEST_STANDALONE_INSTANCE")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful status call"
  assert_mock_called "management" "$management_file --status" "Management script should be called with status"
}

function test_instance_is_active_logic_invalid_args() {
  log_step "Testing __logic_instance_is_active with invalid arguments"

  # Test with empty instance name
  __logic_instance_is_active ""
  local exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg error for empty instance name"

  # Test with nonexistent instance
  __logic_instance_is_active "$TEST_INVALID_INSTANCE"
  exit_code=$?
  assert_not_equals "0" "$exit_code" "Should return error for nonexistent instance"
}

function test_instance_is_active_logic_systemd_inactive() {
  log_step "Testing __logic_instance_is_active with systemd instance - inactive case"

  # Create test systemd instance with 'inactive' in name
  local inactive_instance="${TEST_SYSTEMD_INSTANCE}_inactive"
  create_test_instance_config "$inactive_instance" "systemd"

  # Override systemctl with mock that returns inactive
  function systemctl() {
    local action="$1"
    local service="$2"

    log_test "Mock systemctl called: $action $service"
    echo "$action $service" >> "$KGSM_TEST_SANDBOX/systemctl_calls.log"

    if [[ "$service" == *"inactive"* && "$action" == "is-active" ]]; then
      echo "inactive"
      return 3  # systemctl returns 3 for inactive services
    else
      mock_systemctl "$@"
    fi
  }
  export -f systemctl

  # Test inactive instance
  __logic_instance_is_active "$inactive_instance"
  local exit_code=$?

  assert_equals "1" "$exit_code" "Should return 1 for inactive instance"
  assert_mock_called "systemctl" "is-active ${inactive_instance%.ini}" "systemctl is-active should be called"

  # Cleanup
  remove_test_instance_config "$inactive_instance"
}

function test_instance_is_active_logic_standalone_inactive() {
  log_step "Testing __logic_instance_is_active with standalone instance - inactive case"

  # Create test standalone instance with 'inactive' in management file path
  local inactive_management_file="$KGSM_TEST_SANDBOX/test_management_inactive.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$inactive_management_file"

  # Override mock to return inactive for this specific file
  function mock_management_script() {
    local script_path="$1"
    shift
    local args="$@"

    log_test "Mock management script called: $script_path $args"
    echo "$script_path $args" >> "$KGSM_TEST_SANDBOX/management_calls.log"

    if [[ "$script_path" == *"inactive"* && "$args" == *"--is-active"* ]]; then
      return 1  # Inactive
    else
      return 0  # Active
    fi
  }
  export -f mock_management_script

  # Test inactive instance
  __logic_instance_is_active "$TEST_STANDALONE_INSTANCE"
  local exit_code=$?

  assert_equals "1" "$exit_code" "Should return 1 for inactive instance"
  assert_mock_called "management" "$inactive_management_file --is-active" "Management script should be called with is-active"
}

function test_instance_status_logic_invalid_args() {
  log_step "Testing __logic_instance_status with invalid arguments"

  # Test with empty instance name
  __logic_instance_status ""
  local exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg error for empty instance name"

  # Test with nonexistent instance
  __logic_instance_status "$TEST_INVALID_INSTANCE"
  exit_code=$?
  assert_not_equals "0" "$exit_code" "Should return error for nonexistent instance"
}

function test_instance_status_logic_systemd() {
  log_step "Testing __logic_instance_status with systemd instance"

  # Create test systemd instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_SYSTEMD_INSTANCE" "systemd" "$management_file"

  # Test status call
  local output
  output=$(__logic_instance_status "$TEST_SYSTEMD_INSTANCE")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful status call"
  assert_mock_called "management" "$management_file --status" "Management script should be called with status"
}

function test_instance_status_logic_with_json_flag() {
  log_step "Testing __logic_instance_status with JSON flag"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test status call with JSON flag
  local output
  output=$(__logic_instance_status "$TEST_STANDALONE_INSTANCE" "true")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful status call with JSON"
  assert_mock_called "management" "$management_file --status --json" "Management script should be called with status and json flags"
}

function test_instance_status_logic_with_fast_flag() {
  log_step "Testing __logic_instance_status with fast flag"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test status call with fast flag
  local output
  output=$(__logic_instance_status "$TEST_STANDALONE_INSTANCE" "" "true")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful status call with fast flag"
  assert_mock_called "management" "$management_file --status --fast" "Management script should be called with status and fast flags"
}

function test_instance_status_logic_with_both_flags() {
  log_step "Testing __logic_instance_status with both JSON and fast flags"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test status call with both flags
  local output
  output=$(__logic_instance_status "$TEST_STANDALONE_INSTANCE" "true" "true")
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful status call with both flags"
  assert_mock_called "management" "$management_file --status --json --fast" "Management script should be called with status, json, and fast flags"
}

function test_instance_status_logic_missing_management_file() {
  log_step "Testing __logic_instance_status with missing management file config"

  # Create instance config without management_file
  local temp_instance="temp_status_$(date +%s)_$"
  local config_file="$KGSM_INSTANCES_DIR/${temp_instance}.ini"
  mkdir -p "$KGSM_INSTANCES_DIR"

  cat > "$config_file" << EOF
name="$temp_instance"
lifecycle_manager="standalone"
runtime="native"
EOF

  # Test status with missing management file config
  __logic_instance_status "$temp_instance"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for missing management file"

  # Cleanup
  rm -f "$config_file"
}

# =============================================================================
# INSTANCE LOGS LOGIC TESTS
# =============================================================================

function test_instance_logs_logic_standalone_missing_management_file() {
  log_step "Testing __logic_instance_logs with standalone instance - missing management file config"

  # Create instance config without management_file
  local temp_instance="temp_logs_$(date +%s)_$"
  local config_file="$KGSM_INSTANCES_DIR/${temp_instance}.ini"
  mkdir -p "$KGSM_INSTANCES_DIR"

  cat > "$config_file" << EOF
name="$temp_instance"
lifecycle_manager="standalone"
runtime="native"
EOF

  # Test logs with missing management file config
  __logic_instance_logs "$temp_instance"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for missing management file"

  # Cleanup
  rm -f "$config_file"
}

function test_instance_logs_logic_invalid_lifecycle_manager() {
  log_step "Testing __logic_instance_logs with invalid lifecycle manager"

  # Create instance with invalid lifecycle manager
  local temp_instance="temp_logs_invalid_$(date +%s)_$"
  create_test_instance_config "$temp_instance" "invalid_manager"

  # Test logs with invalid lifecycle manager
  __logic_instance_logs "$temp_instance"
  local exit_code=$?

  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for invalid lifecycle manager"

  # Cleanup
  remove_test_instance_config "$temp_instance"
}

# =============================================================================
# INSTANCE LOGS LOGIC TESTS
# =============================================================================

function test_instance_logs_logic_standalone() {
  log_step "Testing __logic_instance_logs with standalone instance"

  # Create test standalone instance
  local management_file="$KGSM_TEST_SANDBOX/test_management.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$management_file"

  # Test logs without follow
  __logic_instance_logs "$TEST_STANDALONE_INSTANCE" "false" "10"
  local exit_code=$?

  assert_equals "0" "$exit_code" "Should return 0 for successful logs call"
  assert_mock_called "management" "$management_file --logs --tail 10" "Management script should be called with logs"
}

function test_instance_logs_logic_invalid_args() {
  log_step "Testing __logic_instance_logs with invalid arguments"

  # Test with empty instance name
  __logic_instance_logs "" "false" "10"
  local exit_code=$?
  assert_equals "$EC_INVALID_ARG" "$exit_code" "Should return invalid arg error for empty instance name"

  # Test with nonexistent instance
  __logic_instance_logs "$TEST_INVALID_INSTANCE" "false" "10"
  exit_code=$?
  assert_not_equals "0" "$exit_code" "Should return error for nonexistent instance"
}

function test_instance_logs_logic_standalone_failure() {
  log_step "Testing __logic_instance_logs with standalone instance - failure case"

  # Create test standalone instance with 'fail' in management file path
  local fail_management_file="$KGSM_TEST_SANDBOX/test_management_fail.sh"
  create_test_instance_config "$TEST_STANDALONE_INSTANCE" "standalone" "$fail_management_file"

  # Test failed logs
  __logic_instance_logs "$TEST_STANDALONE_INSTANCE" "false" "10"
  local exit_code=$?

  assert_equals "$EC_GENERAL" "$exit_code" "Should return general error code for failed standalone logs"
  assert_mock_called "management" "$fail_management_file --logs --tail 10" "Management script should be called even on failure"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

function test_error_handling_invalid_lifecycle_manager() {
  log_step "Testing error handling for invalid lifecycle manager"

  # Create instance with invalid lifecycle manager
  create_test_instance_config "$TEST_SYSTEMD_INSTANCE" "invalid_manager"

  # Test that all functions return appropriate error
  __logic_instance_start "$TEST_SYSTEMD_INSTANCE"
  local exit_code=$?
  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for invalid lifecycle manager"

  __logic_instance_stop "$TEST_SYSTEMD_INSTANCE"
  exit_code=$?
  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for invalid lifecycle manager"

  __logic_instance_is_active "$TEST_SYSTEMD_INSTANCE"
  exit_code=$?
  assert_equals "$EC_INVALID_CONFIG" "$exit_code" "Should return invalid config error for invalid lifecycle manager"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function setup_test() {
  log_step "Setting up lifecycle logic unit tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Setup mock environment
  setup_mock_environment

  # Source required libraries
  source "$KGSM_ROOT/lib/bootstrap.sh"

  log_test "Test environment setup complete"
}

function cleanup_test() {
  log_step "Cleaning up lifecycle logic unit tests"
  cleanup_mock_environment
  log_test "Test cleanup complete"
}

function main() {
  log_test "Starting lifecycle logic unit tests"

  # Initialize test environment
  setup_test

  # Execute library loading tests
  test_lifecycle_logic_library_loading

  # Execute helper function tests
  test_get_lifecycle_manager_function

  # Execute start logic tests
  test_instance_start_logic_systemd
  test_instance_start_logic_standalone
  test_instance_start_logic_invalid_args
  test_instance_start_logic_systemd_failure
  test_instance_start_logic_standalone_failure
  test_instance_start_logic_standalone_missing_management_file
  test_instance_start_logic_invalid_lifecycle_manager

  # Execute stop logic tests
  test_instance_stop_logic_systemd
  test_instance_stop_logic_standalone
  test_instance_stop_logic_invalid_args
  test_instance_stop_logic_systemd_failure
  test_instance_stop_logic_standalone_failure
  test_instance_stop_logic_standalone_missing_management_file
  test_instance_stop_logic_invalid_lifecycle_manager

  # Execute restart logic tests
  test_instance_restart_logic
  test_instance_restart_logic_invalid_args
  test_instance_restart_logic_standalone
  test_instance_restart_logic_stop_failure
  test_instance_restart_logic_start_failure_after_successful_stop
  test_instance_restart_logic_nonexistent_instance

  # Execute status logic tests
  test_instance_is_active_logic_systemd
  test_instance_is_active_logic_standalone
  test_instance_status_logic

  # Execute logs logic tests
  test_instance_logs_logic_systemd
  test_instance_logs_logic_systemd_with_follow
  test_instance_logs_logic_standalone
  test_instance_logs_logic_standalone_with_follow
  test_instance_logs_logic_invalid_args
  test_instance_logs_logic_systemd_failure
  test_instance_logs_logic_standalone_failure

  # Execute additional status logic tests
  test_instance_is_active_logic_invalid_args
  test_instance_is_active_logic_systemd_inactive
  test_instance_is_active_logic_standalone_inactive
  test_instance_status_logic_invalid_args
  test_instance_status_logic_systemd
  test_instance_status_logic_with_json_flag
  test_instance_status_logic_with_fast_flag
  test_instance_status_logic_with_both_flags
  test_instance_status_logic_missing_management_file
  test_instance_logs_logic_default_parameters
  test_instance_logs_logic_standalone_missing_management_file
  test_instance_logs_logic_invalid_lifecycle_manager

  # Execute error handling tests
  test_error_handling_invalid_lifecycle_manager

  # Cleanup
  cleanup_test

  log_test "Lifecycle logic unit tests completed"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All lifecycle logic unit tests completed successfully"
  else
    fail_test "Some lifecycle logic unit tests failed"
  fi
}

# Execute main function
main "$@"
