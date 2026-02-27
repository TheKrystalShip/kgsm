#!/usr/bin/env bash

# KGSM Watcher Handler Logic Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/watchers.sh
#         commands/handlers/watchers.logs.sh
#         commands/handlers/watchers.ports.sh
#
# Tests pure __logic_* functions from all three watcher handlers:
#
# watchers.sh:
#   - __logic_determine_strategy()
#
# watchers.logs.sh:
#   - __logic_test_log_pattern()
#   - __logic_get_log_status_data()
#
# watchers.ports.sh:
#   - __logic_extract_first_port()
#   - __logic_test_port_status()
#   - __logic_get_port_status_data()
#
# Does NOT test:
#   - __logic_execute_log_watch()  (requires live running server process + log streaming)
#   - __logic_execute_port_watch() (requires live running server process + active port)

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="watchers_logic"
readonly HANDLER_WATCHERS="$KGSM_ROOT/commands/handlers/watchers.sh"
readonly HANDLER_WATCHERS_LOGS="$KGSM_ROOT/commands/handlers/watchers.logs.sh"
readonly HANDLER_WATCHERS_PORTS="$KGSM_ROOT/commands/handlers/watchers.ports.sh"

# Temp directory for test fixture config files
_TEST_FIXTURES_DIR=""

# =============================================================================
# SETUP FUNCTION
# =============================================================================

function setup_test() {
  log_test_step "Setting up watchers logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Verify all three handler files exist
  assert_file_exists "$HANDLER_WATCHERS" "watchers.sh handler should exist"
  assert_file_exists "$HANDLER_WATCHERS_LOGS" "watchers.logs.sh handler should exist"
  assert_file_exists "$HANDLER_WATCHERS_PORTS" "watchers.ports.sh handler should exist"

  # Source all three handlers
  # shellcheck disable=SC1090
  source "$HANDLER_WATCHERS"
  # shellcheck disable=SC1090
  source "$HANDLER_WATCHERS_LOGS"
  # shellcheck disable=SC1090
  source "$HANDLER_WATCHERS_PORTS"

  # Verify load guards are set
  assert_not_null "$KGSM_LOGIC_WATCHERS_LOADED" "watchers.sh loaded guard should be set"
  assert_not_null "$KGSM_LOGIC_WATCHERS_LOGS_LOADED" "watchers.logs.sh loaded guard should be set"
  assert_not_null "$KGSM_LOGIC_WATCHERS_PORTS_LOADED" "watchers.ports.sh loaded guard should be set"

  # Verify all expected logic functions are exported
  assert_function_exists "__logic_determine_strategy" \
    "__logic_determine_strategy should be exported"
  assert_function_exists "__logic_execute_log_watch" \
    "__logic_execute_log_watch should be exported"
  assert_function_exists "__logic_test_log_pattern" \
    "__logic_test_log_pattern should be exported"
  assert_function_exists "__logic_get_log_status_data" \
    "__logic_get_log_status_data should be exported"
  assert_function_exists "__logic_extract_first_port" \
    "__logic_extract_first_port should be exported"
  assert_function_exists "__logic_execute_port_watch" \
    "__logic_execute_port_watch should be exported"
  assert_function_exists "__logic_test_port_status" \
    "__logic_test_port_status should be exported"
  assert_function_exists "__logic_get_port_status_data" \
    "__logic_get_port_status_data should be exported"

  # Verify required error codes are defined
  assert_not_null "$EC_SUCCESS" "EC_SUCCESS should be defined"
  assert_not_null "$EC_MISSING_ARG" "EC_MISSING_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND" "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_WATCHER_NO_STRATEGY" "EC_WATCHER_NO_STRATEGY should be defined"
  assert_not_null "$EC_WATCHER_PATTERN_NOT_FOUND" "EC_WATCHER_PATTERN_NOT_FOUND should be defined"
  assert_not_null "$EC_WATCHER_LOG_FILE_MISSING" "EC_WATCHER_LOG_FILE_MISSING should be defined"
  assert_not_null "$EC_WATCHER_PORT_NOT_ACTIVE" "EC_WATCHER_PORT_NOT_ACTIVE should be defined"
  assert_not_null "$EC_SUCCESS_INSTANCE_READY" "EC_SUCCESS_INSTANCE_READY should be defined"

  # Create a temp directory for test fixture config files
  _TEST_FIXTURES_DIR=$(mktemp -d)

  log_test_step "Watchers logic environment validated"
}

# =============================================================================
# FIXTURE HELPERS
# =============================================================================

# Create a minimal instance config file for testing
# Args: $1 = filename, rest = variable assignments (e.g. "instance_ports='34197'")
function _create_fixture_config() {
  local filename="$1"
  shift
  local filepath="${_TEST_FIXTURES_DIR}/${filename}"

  # Write each variable assignment
  for assignment in "$@"; do
    echo "${assignment}" >> "$filepath"
  done

  echo "$filepath"
}

# =============================================================================
# TESTS: __logic_determine_strategy()
# =============================================================================

function test_determine_strategy_missing_arg() {
  log_test_step "Testing __logic_determine_strategy with no arguments"

  __logic_determine_strategy 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "Should return EC_MISSING_ARG when no config file path provided"
}

function test_determine_strategy_file_not_found() {
  log_test_step "Testing __logic_determine_strategy with non-existent config file"

  __logic_determine_strategy "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when config file does not exist"
}

function test_determine_strategy_logs_when_regex_configured() {
  log_test_step "Testing __logic_determine_strategy returns 'logs' when startup_success_regex is set"

  local config_file
  config_file=$(_create_fixture_config "strategy_logs.ini" \
    "instance_startup_success_regex=\"Hosting game at IP ADDR\"" \
    "instance_ports='34197'")

  local strategy
  strategy=$(__logic_determine_strategy "$config_file" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS when startup_success_regex is configured"
  assert_equals "logs" "$strategy" \
    "Should echo 'logs' when startup_success_regex is configured"
}

function test_determine_strategy_ports_when_only_ports_configured() {
  log_test_step "Testing __logic_determine_strategy returns 'ports' when only ports configured"

  local config_file
  config_file=$(_create_fixture_config "strategy_ports.ini" \
    "instance_startup_success_regex=\"\"" \
    "instance_ports='14159/tcp|14159/udp'")

  local strategy
  strategy=$(__logic_determine_strategy "$config_file" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS when ports are configured"
  assert_equals "ports" "$strategy" \
    "Should echo 'ports' when only ports are configured"
}

function test_determine_strategy_no_strategy_when_nothing_configured() {
  log_test_step "Testing __logic_determine_strategy returns EC_WATCHER_NO_STRATEGY when nothing configured"

  local config_file
  config_file=$(_create_fixture_config "strategy_none.ini" \
    "instance_startup_success_regex=\"\"" \
    "instance_ports=\"\"")

  __logic_determine_strategy "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_WATCHER_NO_STRATEGY" "$exit_code" \
    "Should return EC_WATCHER_NO_STRATEGY when neither regex nor ports are configured"
}

function test_determine_strategy_logs_preferred_over_ports() {
  log_test_step "Testing __logic_determine_strategy prefers 'logs' when both regex and ports configured"

  local config_file
  config_file=$(_create_fixture_config "strategy_both.ini" \
    "instance_startup_success_regex=\"Server ready\"" \
    "instance_ports='7777/udp'")

  local strategy
  strategy=$(__logic_determine_strategy "$config_file" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS when both are configured"
  assert_equals "logs" "$strategy" \
    "Should prefer 'logs' strategy when both regex and ports are configured"
}

function test_determine_strategy_empty_string_arg() {
  log_test_step "Testing __logic_determine_strategy with empty string argument"

  __logic_determine_strategy "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "Should return EC_MISSING_ARG when config file path is empty string"
}

# =============================================================================
# TESTS: __logic_test_log_pattern()
# =============================================================================

function test_test_log_pattern_missing_arg() {
  log_test_step "Testing __logic_test_log_pattern with no arguments"

  __logic_test_log_pattern 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "Should return EC_MISSING_ARG when no config file path provided"
}

function test_test_log_pattern_file_not_found() {
  log_test_step "Testing __logic_test_log_pattern with non-existent config file"

  __logic_test_log_pattern "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when config file does not exist"
}

function test_test_log_pattern_no_pattern_configured() {
  log_test_step "Testing __logic_test_log_pattern when startup_success_regex is empty"

  local config_file
  config_file=$(_create_fixture_config "log_pattern_none.ini" \
    "instance_startup_success_regex=\"\"" \
    "instance_log_file=\"/tmp/nonexistent.log\"")

  __logic_test_log_pattern "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_WATCHER_PATTERN_NOT_FOUND" "$exit_code" \
    "Should return EC_WATCHER_PATTERN_NOT_FOUND when startup_success_regex is not set"
}

function test_test_log_pattern_log_file_missing() {
  log_test_step "Testing __logic_test_log_pattern when log file does not exist"

  local config_file
  config_file=$(_create_fixture_config "log_pattern_missing_log.ini" \
    "instance_startup_success_regex=\"Server started\"" \
    "instance_log_file=\"/nonexistent/path/server.log\"")

  __logic_test_log_pattern "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_WATCHER_LOG_FILE_MISSING" "$exit_code" \
    "Should return EC_WATCHER_LOG_FILE_MISSING when log file does not exist"
}

function test_test_log_pattern_pattern_found_in_log() {
  log_test_step "Testing __logic_test_log_pattern when pattern exists in log file"

  # Create a temp log file with the ready pattern
  local log_file="${_TEST_FIXTURES_DIR}/server_ready.log"
  echo "Server initialization..." > "$log_file"
  echo "Loading world data..." >> "$log_file"
  echo "Hosting game at IP ADDR" >> "$log_file"
  echo "Server running." >> "$log_file"

  local config_file
  config_file=$(_create_fixture_config "log_pattern_found.ini" \
    "instance_startup_success_regex=\"Hosting game at IP ADDR\"" \
    "instance_log_file=\"${log_file}\"")

  __logic_test_log_pattern "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS when pattern is found in log file"
}

function test_test_log_pattern_pattern_not_found_in_log() {
  log_test_step "Testing __logic_test_log_pattern when pattern does NOT exist in log file"

  # Create a temp log file without the ready pattern
  local log_file="${_TEST_FIXTURES_DIR}/server_starting.log"
  echo "Server initialization..." > "$log_file"
  echo "Loading world data..." >> "$log_file"

  local config_file
  config_file=$(_create_fixture_config "log_pattern_not_found.ini" \
    "instance_startup_success_regex=\"Hosting game at IP ADDR\"" \
    "instance_log_file=\"${log_file}\"")

  __logic_test_log_pattern "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_WATCHER_PATTERN_NOT_FOUND" "$exit_code" \
    "Should return EC_WATCHER_PATTERN_NOT_FOUND when pattern is not in log file"
}

function test_test_log_pattern_empty_log_file() {
  log_test_step "Testing __logic_test_log_pattern when log file is empty"

  local log_file="${_TEST_FIXTURES_DIR}/server_empty.log"
  touch "$log_file"

  local config_file
  config_file=$(_create_fixture_config "log_pattern_empty_log.ini" \
    "instance_startup_success_regex=\"Server ready\"" \
    "instance_log_file=\"${log_file}\"")

  __logic_test_log_pattern "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_WATCHER_PATTERN_NOT_FOUND" "$exit_code" \
    "Should return EC_WATCHER_PATTERN_NOT_FOUND when log file is empty"
}

# =============================================================================
# TESTS: __logic_get_log_status_data()
# =============================================================================

function test_get_log_status_data_missing_arg() {
  log_test_step "Testing __logic_get_log_status_data with no arguments"

  __logic_get_log_status_data 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "Should return EC_MISSING_ARG when no config file path provided"
}

function test_get_log_status_data_file_not_found() {
  log_test_step "Testing __logic_get_log_status_data with non-existent config file"

  __logic_get_log_status_data "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when config file does not exist"
}

function test_get_log_status_data_returns_success() {
  log_test_step "Testing __logic_get_log_status_data returns EC_SUCCESS with valid config"

  local config_file
  config_file=$(_create_fixture_config "log_status_valid.ini" \
    "instance_startup_success_regex=\"Hosting game at IP ADDR\"" \
    "instance_log_file=\"/nonexistent/server.log\"")

  __logic_get_log_status_data "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for valid config file"
}

function test_get_log_status_data_format_when_log_missing() {
  log_test_step "Testing __logic_get_log_status_data output format when log file is absent"

  local expected_log="/nonexistent/path/server.log"
  local config_file
  config_file=$(_create_fixture_config "log_status_no_log.ini" \
    "instance_startup_success_regex=\"Server ready\"" \
    "instance_log_file=\"${expected_log}\"")

  local output
  output=$(__logic_get_log_status_data "$config_file" 2>/dev/null)

  # Format: pattern|log_file|log_exists|pattern_found
  assert_contains "$output" "Server ready" \
    "Output should contain the startup_success_regex pattern"
  assert_contains "$output" "$expected_log" \
    "Output should contain the log file path"
  assert_contains "$output" "false" \
    "Output should indicate log_exists=false when log file is missing"
}

function test_get_log_status_data_format_when_log_exists_with_pattern() {
  log_test_step "Testing __logic_get_log_status_data output when log file exists and contains pattern"

  local log_file="${_TEST_FIXTURES_DIR}/status_log_with_pattern.log"
  echo "Started server using port 14159" > "$log_file"

  local config_file
  config_file=$(_create_fixture_config "log_status_log_with_pattern.ini" \
    "instance_startup_success_regex=\"Started server using port\"" \
    "instance_log_file=\"${log_file}\"")

  local output
  output=$(__logic_get_log_status_data "$config_file" 2>/dev/null)

  # Format: pattern|log_file|log_exists|pattern_found
  local log_exists_field
  log_exists_field=$(echo "$output" | cut -d'|' -f3)
  local pattern_found_field
  pattern_found_field=$(echo "$output" | cut -d'|' -f4)

  assert_equals "true" "$log_exists_field" \
    "Should report log_exists=true when log file exists"
  assert_equals "true" "$pattern_found_field" \
    "Should report pattern_found=true when pattern is in log file"
}

function test_get_log_status_data_format_when_log_exists_without_pattern() {
  log_test_step "Testing __logic_get_log_status_data output when log file exists but pattern absent"

  local log_file="${_TEST_FIXTURES_DIR}/status_log_no_pattern.log"
  echo "Server is starting up..." > "$log_file"

  local config_file
  config_file=$(_create_fixture_config "log_status_log_no_pattern.ini" \
    "instance_startup_success_regex=\"Started server using port\"" \
    "instance_log_file=\"${log_file}\"")

  local output
  output=$(__logic_get_log_status_data "$config_file" 2>/dev/null)

  local log_exists_field
  log_exists_field=$(echo "$output" | cut -d'|' -f3)
  local pattern_found_field
  pattern_found_field=$(echo "$output" | cut -d'|' -f4)

  assert_equals "true" "$log_exists_field" \
    "Should report log_exists=true when log file exists"
  assert_equals "false" "$pattern_found_field" \
    "Should report pattern_found=false when pattern is absent from log file"
}

function test_get_log_status_data_no_pattern_configured() {
  log_test_step "Testing __logic_get_log_status_data output format when no pattern configured"

  local log_file="${_TEST_FIXTURES_DIR}/status_no_pattern_config.log"
  echo "Server running." > "$log_file"

  local config_file
  config_file=$(_create_fixture_config "log_status_no_pattern_config.ini" \
    "instance_startup_success_regex=\"\"" \
    "instance_log_file=\"${log_file}\"")

  local output
  output=$(__logic_get_log_status_data "$config_file" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS even when no pattern is configured"
  # Format: pattern|log_file|log_exists|pattern_found
  # pattern should be empty, log_exists true, pattern_found false
  local pattern_found_field
  pattern_found_field=$(echo "$output" | cut -d'|' -f4)
  assert_equals "false" "$pattern_found_field" \
    "Should report pattern_found=false when no pattern is configured"
}

# =============================================================================
# TESTS: __logic_extract_first_port()
# =============================================================================

function test_extract_first_port_missing_arg() {
  log_test_step "Testing __logic_extract_first_port with empty string"

  __logic_extract_first_port "" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "Should return EC_MISSING_ARG when ports string is empty"
}

function test_extract_first_port_single_port_no_protocol() {
  log_test_step "Testing __logic_extract_first_port with single port (no protocol)"

  local port
  port=$(__logic_extract_first_port "34197" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for single port without protocol"
  assert_equals "34197" "$port" \
    "Should echo '34197' for single port '34197'"
}

function test_extract_first_port_single_port_with_protocol() {
  log_test_step "Testing __logic_extract_first_port with single port and protocol"

  local port
  port=$(__logic_extract_first_port "7777/udp" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for single port with protocol"
  assert_equals "7777" "$port" \
    "Should echo '7777' from '7777/udp'"
}

function test_extract_first_port_single_port_tcp_protocol() {
  log_test_step "Testing __logic_extract_first_port with single port and tcp protocol"

  local port
  port=$(__logic_extract_first_port "25565/tcp" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for single port with tcp"
  assert_equals "25565" "$port" \
    "Should echo '25565' from '25565/tcp'"
}

function test_extract_first_port_range_no_protocol() {
  log_test_step "Testing __logic_extract_first_port with port range (no protocol)"

  local port
  port=$(__logic_extract_first_port "26900:26903" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for port range without protocol"
  assert_equals "26900" "$port" \
    "Should echo start port '26900' from range '26900:26903'"
}

function test_extract_first_port_range_with_protocol() {
  log_test_step "Testing __logic_extract_first_port with port range and protocol"

  local port
  port=$(__logic_extract_first_port "26900:26903/tcp" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for port range with protocol"
  assert_equals "26900" "$port" \
    "Should echo start port '26900' from range '26900:26903/tcp'"
}

function test_extract_first_port_multiple_ports_pipe_separated() {
  log_test_step "Testing __logic_extract_first_port with multiple ports (pipe-separated)"

  local port
  port=$(__logic_extract_first_port "14159/tcp|14159/udp" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for pipe-separated ports"
  assert_equals "14159" "$port" \
    "Should echo first port '14159' from '14159/tcp|14159/udp'"
}

function test_extract_first_port_multiple_different_ports() {
  log_test_step "Testing __logic_extract_first_port extracts only the first of multiple ports"

  local port
  port=$(__logic_extract_first_port "27015/tcp|27016/udp|27017" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for multiple pipe-separated ports"
  assert_equals "27015" "$port" \
    "Should echo only the first port '27015' from '27015/tcp|27016/udp|27017'"
}

function test_extract_first_port_invalid_format() {
  log_test_step "Testing __logic_extract_first_port with invalid port format"

  __logic_extract_first_port "not-a-port" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Should return EC_INVALID_ARG for non-numeric port format"
}

function test_extract_first_port_range_with_udp() {
  log_test_step "Testing __logic_extract_first_port with UDP port range"

  local port
  port=$(__logic_extract_first_port "26900:26903/udp" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for UDP port range"
  assert_equals "26900" "$port" \
    "Should echo start port '26900' from UDP range '26900:26903/udp'"
}

# =============================================================================
# TESTS: __logic_test_port_status()
# =============================================================================

function test_test_port_status_missing_arg() {
  log_test_step "Testing __logic_test_port_status with no arguments"

  __logic_test_port_status 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "Should return EC_MISSING_ARG when no config file path provided"
}

function test_test_port_status_file_not_found() {
  log_test_step "Testing __logic_test_port_status with non-existent config file"

  __logic_test_port_status "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when config file does not exist"
}

function test_test_port_status_no_ports_configured() {
  log_test_step "Testing __logic_test_port_status when no ports are configured"

  local config_file
  config_file=$(_create_fixture_config "port_status_no_ports.ini" \
    "instance_ports=\"\"")

  __logic_test_port_status "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_WATCHER_PORT_NOT_ACTIVE" "$exit_code" \
    "Should return EC_WATCHER_PORT_NOT_ACTIVE when instance_ports is empty"
}

function test_test_port_status_with_ports_returns_success() {
  log_test_step "Testing __logic_test_port_status with ports configured returns EC_SUCCESS"

  # Use a port that is extremely unlikely to be in use: ephemeral high port
  local config_file
  config_file=$(_create_fixture_config "port_status_with_ports.ini" \
    "instance_ports='59876/tcp'")

  __logic_test_port_status "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS when ports are configured (even if not active)"
}

function test_test_port_status_output_format() {
  log_test_step "Testing __logic_test_port_status output format is 'port_count|active_count'"

  local config_file
  config_file=$(_create_fixture_config "port_status_format.ini" \
    "instance_ports='59877/tcp|59878/udp'")

  local output
  output=$(__logic_test_port_status "$config_file" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS when ports are configured"

  local port_count
  port_count=$(echo "$output" | cut -d'|' -f1)
  local active_count
  active_count=$(echo "$output" | cut -d'|' -f2)

  assert_equals "2" "$port_count" \
    "Should report 2 ports for '59877/tcp|59878/udp'"
  assert_equals "0" "$active_count" \
    "Should report 0 active ports (test ports are not listening)"
}

function test_test_port_status_range_counts_as_one() {
  log_test_step "Testing __logic_test_port_status counts a port range as one port entry"

  local config_file
  config_file=$(_create_fixture_config "port_status_range.ini" \
    "instance_ports='59880:59883/tcp'")

  local output
  output=$(__logic_test_port_status "$config_file" 2>/dev/null)

  local port_count
  port_count=$(echo "$output" | cut -d'|' -f1)

  assert_equals "1" "$port_count" \
    "A port range should be counted as 1 port definition entry"
}

# =============================================================================
# TESTS: __logic_get_port_status_data()
# =============================================================================

function test_get_port_status_data_missing_arg() {
  log_test_step "Testing __logic_get_port_status_data with no arguments"

  __logic_get_port_status_data 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_MISSING_ARG" "$exit_code" \
    "Should return EC_MISSING_ARG when no config file path provided"
}

function test_get_port_status_data_file_not_found() {
  log_test_step "Testing __logic_get_port_status_data with non-existent config file"

  __logic_get_port_status_data "/nonexistent/path/to/instance.config.ini" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_FILE_NOT_FOUND" "$exit_code" \
    "Should return EC_FILE_NOT_FOUND when config file does not exist"
}

function test_get_port_status_data_returns_success() {
  log_test_step "Testing __logic_get_port_status_data returns EC_SUCCESS with valid config"

  local config_file
  config_file=$(_create_fixture_config "port_data_valid.ini" \
    "instance_ports='34197'")

  __logic_get_port_status_data "$config_file" 2>/dev/null
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS for valid config file with ports"
}

function test_get_port_status_data_output_contains_ports() {
  log_test_step "Testing __logic_get_port_status_data output contains configured ports"

  local config_file
  config_file=$(_create_fixture_config "port_data_ports.ini" \
    "instance_ports='34197'")

  local output
  output=$(__logic_get_port_status_data "$config_file" 2>/dev/null)

  # Format: ports|first_port|port_count|active_count
  assert_contains "$output" "34197" \
    "Output should contain the configured port '34197'"
}

function test_get_port_status_data_output_format() {
  log_test_step "Testing __logic_get_port_status_data output format is 'ports|first_port|port_count|active_count'"

  # Use a single port (no '|' in port value) so field parsing is unambiguous
  local config_file
  config_file=$(_create_fixture_config "port_data_format.ini" \
    "instance_ports='34197'")

  local output
  output=$(__logic_get_port_status_data "$config_file" 2>/dev/null)

  # Format: ports|first_port|port_count|active_count
  # With single port '34197', output is: 34197|34197|1|0  (4 fields)
  local first_port
  first_port=$(echo "$output" | cut -d'|' -f2)
  local port_count
  port_count=$(echo "$output" | cut -d'|' -f3)
  local active_count
  active_count=$(echo "$output" | cut -d'|' -f4)

  assert_equals "34197" "$first_port" \
    "Should extract '34197' as first port"
  assert_equals "1" "$port_count" \
    "Should count 1 port entry for single port '34197'"
  assert_equals "0" "$active_count" \
    "Should report 0 active ports (test port is not listening)"
}

function test_get_port_status_data_no_ports_configured() {
  log_test_step "Testing __logic_get_port_status_data when no ports configured"

  local config_file
  config_file=$(_create_fixture_config "port_data_no_ports.ini" \
    "instance_ports=\"\"")

  local output
  output=$(__logic_get_port_status_data "$config_file" 2>/dev/null)
  local exit_code=$?

  assert_equals "$EC_SUCCESS" "$exit_code" \
    "Should return EC_SUCCESS even when no ports configured"

  # When no ports: first_port and counts should reflect empty state
  local port_count
  port_count=$(echo "$output" | cut -d'|' -f3)
  local active_count
  active_count=$(echo "$output" | cut -d'|' -f4)

  assert_equals "0" "$port_count" \
    "Should report 0 ports when instance_ports is empty"
  assert_equals "0" "$active_count" \
    "Should report 0 active ports when instance_ports is empty"
}

# =============================================================================
# TEARDOWN
# =============================================================================

function teardown_test() {
  log_test_step "Cleaning up test fixtures"

  if [[ -n "${_TEST_FIXTURES_DIR:-}" && -d "$_TEST_FIXTURES_DIR" ]]; then
    rm -rf "$_TEST_FIXTURES_DIR"
  fi
}

