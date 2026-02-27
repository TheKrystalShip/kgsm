#!/usr/bin/env bash

# KGSM Execution Serialization Tests
#
# Test Type: UNIT
# Target: tests/framework/execution.common.sh serialization functions
#
# Tests the serialization layer used for cross-process communication
# in parallel test execution. Verifies:
# - Result writing to files
# - Result reading from files
# - Round-trip serialization (write then read)
# - Edge cases: newlines, special characters, empty values

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="execution_serialization"

# Temp directory for serialization tests
TEST_TEMP_DIR=""

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up execution serialization tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_not_null "${TEST_EXECUTION_COMMON_LOADED:-}" "execution.common.sh should be loaded"

  # Create temp directory for test files
  TEST_TEMP_DIR=$(mktemp -d -t "kgsm-serial-test-XXXXXX")
  assert_dir_exists "$TEST_TEMP_DIR" "Temp directory should be created"

  # Verify serialization functions exist
  assert_function_exists "__write_result_to_file" "Write function should be available"
  assert_function_exists "__read_result_from_file" "Read function should be available"
  assert_function_exists "__flatten_result_to_compound_keys" "Flatten function should be available"

  log_test_step "Test environment validated"
}

function cleanup_test() {
  log_test_step "Cleaning up serialization test resources"

  # Remove temp directory
  if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# =============================================================================
# WRITE RESULT TESTS
# =============================================================================

function test_write_result_basic() {
  log_test_step "Testing __write_result_to_file with basic data"

  # Setup
  declare -A result=(
    [test_name]="test_example"
    [test_type]="unit"
    [exit_code]="0"
    [assertions_passed]="5"
    [assertions_failed]="0"
    [assertions_total]="5"
    [duration_seconds]="3"
    [test_log_path]="/tmp/test.log"
    [sandbox_path]="/tmp/sandbox"
    [timestamp]="2024-01-01T12:00:00+0000"
  )

  local output_file="$TEST_TEMP_DIR/basic_result.txt"

  # Execute
  __write_result_to_file result "$output_file"
  local exit_code=$?

  # Assert
  assert_equals "$exit_code" "0" "Write should succeed"
  assert_file_exists "$output_file" "Output file should be created"

  # Verify file content contains expected keys
  local content
  content=$(cat "$output_file")
  assert_contains "$content" "test_name=test_example" "Should contain test_name"
  assert_contains "$content" "exit_code=0" "Should contain exit_code"
  assert_contains "$content" "assertions_passed=5" "Should contain assertions_passed"
}

function test_write_result_special_characters() {
  log_test_step "Testing __write_result_to_file with special characters"

  # Setup - test_log_path may contain spaces and special chars
  declare -A result=(
    [test_name]="test_with_underscores_and_123"
    [test_type]="integration"
    [exit_code]="1"
    [assertions_passed]="10"
    [assertions_failed]="2"
    [assertions_total]="12"
    [duration_seconds]="15"
    [test_log_path]="/tmp/path with spaces/test.log"
    [sandbox_path]="/tmp/special-chars_here"
    [timestamp]="2024-12-21T16:00:00-0500"
  )

  local output_file="$TEST_TEMP_DIR/special_result.txt"

  # Execute
  __write_result_to_file result "$output_file"
  local exit_code=$?

  # Assert
  assert_equals "$exit_code" "0" "Write should succeed with special chars"
  assert_file_exists "$output_file" "Output file should be created"

  # Verify path with spaces is preserved
  local content
  content=$(cat "$output_file")
  assert_contains "$content" "path with spaces" "Should preserve spaces in path"
}

function test_write_result_empty_values() {
  log_test_step "Testing __write_result_to_file with empty values"

  # Setup - some fields may be empty
  declare -A result=(
    [test_name]="test_empty_fields"
    [test_type]="unit"
    [exit_code]="0"
    [assertions_passed]="0"
    [assertions_failed]="0"
    [assertions_total]="0"
    [duration_seconds]="0"
    [test_log_path]=""
    [sandbox_path]=""
    [timestamp]=""
  )

  local output_file="$TEST_TEMP_DIR/empty_result.txt"

  # Execute
  __write_result_to_file result "$output_file"
  local exit_code=$?

  # Assert
  assert_equals "$exit_code" "0" "Write should succeed with empty values"
  assert_file_exists "$output_file" "Output file should be created"
}

# =============================================================================
# READ RESULT TESTS
# =============================================================================

function test_read_result_basic() {
  log_test_step "Testing __read_result_from_file with basic data"

  # Setup - create a result file manually
  local input_file="$TEST_TEMP_DIR/read_basic.txt"
  cat > "$input_file" << 'EOF'
test_name=test_read_example
test_type=unit
exit_code=0
assertions_passed=7
assertions_failed=1
assertions_total=8
duration_seconds=5
test_log_path=/tmp/read.log
sandbox_path=/tmp/read-sandbox
timestamp=2024-01-01T15:30:00+0000
EOF

  declare -A read_result

  # Execute
  __read_result_from_file "$input_file" read_result
  local exit_code=$?

  # Assert
  assert_equals "$exit_code" "0" "Read should succeed"
  assert_equals "${read_result[test_name]}" "test_read_example" "test_name should match"
  assert_equals "${read_result[exit_code]}" "0" "exit_code should match"
  assert_equals "${read_result[assertions_passed]}" "7" "assertions_passed should match"
  assert_equals "${read_result[assertions_failed]}" "1" "assertions_failed should match"
  assert_equals "${read_result[duration_seconds]}" "5" "duration_seconds should match"
}

function test_read_result_missing_file() {
  log_test_step "Testing __read_result_from_file with missing file"

  declare -A read_result

  # Execute - file doesn't exist
  __read_result_from_file "$TEST_TEMP_DIR/nonexistent.txt" read_result
  local exit_code=$?

  # Assert - should return non-zero for missing file
  assert_not_equals "$exit_code" "0" "Read should fail for missing file"
}

function test_read_result_empty_file() {
  log_test_step "Testing __read_result_from_file with empty file"

  # Setup
  local input_file="$TEST_TEMP_DIR/empty_file.txt"
  touch "$input_file"

  declare -A read_result

  # Execute
  __read_result_from_file "$input_file" read_result
  local exit_code=$?

  # Assert - should succeed but result should have no/empty values
  assert_equals "$exit_code" "0" "Read should succeed for empty file"
  assert_equals "${read_result[test_name]:-}" "" "test_name should be empty"
}

# =============================================================================
# ROUND-TRIP TESTS
# =============================================================================

function test_round_trip_basic() {
  log_test_step "Testing round-trip serialization (write then read)"

  # Setup - original data
  declare -A original=(
    [test_name]="test_roundtrip"
    [test_type]="unit"
    [exit_code]="0"
    [assertions_passed]="15"
    [assertions_failed]="2"
    [assertions_total]="17"
    [duration_seconds]="8"
    [test_log_path]="/tmp/roundtrip.log"
    [sandbox_path]="/tmp/roundtrip-sandbox"
    [timestamp]="2024-12-21T18:00:00+0000"
  )

  local file="$TEST_TEMP_DIR/roundtrip.txt"

  # Write
  __write_result_to_file original "$file"
  assert_file_exists "$file" "File should be created after write"

  # Read
  declare -A restored
  __read_result_from_file "$file" restored

  # Assert all fields match
  assert_equals "${restored[test_name]}" "${original[test_name]}" "test_name round-trip"
  assert_equals "${restored[test_type]}" "${original[test_type]}" "test_type round-trip"
  assert_equals "${restored[exit_code]}" "${original[exit_code]}" "exit_code round-trip"
  assert_equals "${restored[assertions_passed]}" "${original[assertions_passed]}" "assertions_passed round-trip"
  assert_equals "${restored[assertions_failed]}" "${original[assertions_failed]}" "assertions_failed round-trip"
  assert_equals "${restored[assertions_total]}" "${original[assertions_total]}" "assertions_total round-trip"
  assert_equals "${restored[duration_seconds]}" "${original[duration_seconds]}" "duration_seconds round-trip"
  assert_equals "${restored[test_log_path]}" "${original[test_log_path]}" "test_log_path round-trip"
  assert_equals "${restored[sandbox_path]}" "${original[sandbox_path]}" "sandbox_path round-trip"
  assert_equals "${restored[timestamp]}" "${original[timestamp]}" "timestamp round-trip"
}

function test_round_trip_with_spaces() {
  log_test_step "Testing round-trip with spaces in values"

  # Setup
  declare -A original=(
    [test_name]="test_spaces"
    [test_type]="unit"
    [exit_code]="0"
    [assertions_passed]="5"
    [assertions_failed]="0"
    [assertions_total]="5"
    [duration_seconds]="2"
    [test_log_path]="/path/with spaces/and more spaces/test.log"
    [sandbox_path]="/another path/with spaces"
    [timestamp]="2024-12-21T18:30:00+0000"
  )

  local file="$TEST_TEMP_DIR/roundtrip_spaces.txt"

  # Write
  __write_result_to_file original "$file"

  # Read
  declare -A restored
  __read_result_from_file "$file" restored

  # Assert paths with spaces preserved
  assert_equals "${restored[test_log_path]}" "${original[test_log_path]}" "Path with spaces preserved"
  assert_equals "${restored[sandbox_path]}" "${original[sandbox_path]}" "Another path with spaces preserved"
}

# =============================================================================
# FLATTEN TO COMPOUND KEYS TESTS
# =============================================================================

function test_flatten_result_basic() {
  log_step "Testing __flatten_result_to_compound_keys"

  # Setup - single test result
  declare -A single_result=(
    [test_name]="test_flatten"
    [test_type]="unit"
    [exit_code]="0"
    [assertions_passed]="10"
    [assertions_failed]="0"
    [assertions_total]="10"
    [duration_seconds]="4"
    [test_log_path]="/tmp/flatten.log"
    [sandbox_path]="/tmp/flatten-sandbox"
    [timestamp]="2024-12-21T19:00:00+0000"
  )

  declare -A flattened

  # Execute - signature is (test_name, result_array_name, results_array_name)
  __flatten_result_to_compound_keys "test_flatten" single_result flattened

  # Assert compound keys created
  assert_equals "${flattened[test_flatten__test_name]}" "test_flatten" "Compound key for test_name"
  assert_equals "${flattened[test_flatten__exit_code]}" "0" "Compound key for exit_code"
  assert_equals "${flattened[test_flatten__assertions_passed]}" "10" "Compound key for assertions_passed"
  assert_equals "${flattened[test_flatten__duration_seconds]}" "4" "Compound key for duration_seconds"
}

function test_flatten_multiple_results() {
  log_test_step "Testing __flatten_result_to_compound_keys with multiple tests"

  # Setup - multiple test results
  declare -A result1=(
    [test_name]="test_one"
    [exit_code]="0"
    [assertions_passed]="5"
  )

  declare -A result2=(
    [test_name]="test_two"
    [exit_code]="1"
    [assertions_passed]="3"
  )

  declare -A combined

  # Flatten both - signature is (test_name, result_array_name, results_array_name)
  __flatten_result_to_compound_keys "test_one" result1 combined
  __flatten_result_to_compound_keys "test_two" result2 combined

  # Assert both sets of keys exist without collision
  assert_equals "${combined[test_one__test_name]}" "test_one" "First test's name"
  assert_equals "${combined[test_one__exit_code]}" "0" "First test's exit_code"
  assert_equals "${combined[test_two__test_name]}" "test_two" "Second test's name"
  assert_equals "${combined[test_two__exit_code]}" "1" "Second test's exit_code"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

function test_value_with_equals_sign() {
  log_test_step "Testing serialization with equals sign in value"

  # Setup - timestamp might have = in format (unlikely but test edge case)
  declare -A original=(
    [test_name]="test_equals"
    [test_type]="unit"
    [exit_code]="0"
    [assertions_passed]="1"
    [assertions_failed]="0"
    [assertions_total]="1"
    [duration_seconds]="1"
    [test_log_path]="/tmp/key=value/test.log"
    [sandbox_path]="/tmp/sandbox"
    [timestamp]="2024-12-21T19:30:00+0000"
  )

  local file="$TEST_TEMP_DIR/equals_test.txt"

  # Write and read
  __write_result_to_file original "$file"

  declare -A restored
  __read_result_from_file "$file" restored

  # Assert - the path with = should be preserved
  assert_equals "${restored[test_log_path]}" "${original[test_log_path]}" "Path with equals sign preserved"
}

function test_numeric_field_types() {
  log_test_step "Testing numeric fields are preserved as strings"

  # Setup
  declare -A original=(
    [test_name]="test_numbers"
    [test_type]="unit"
    [exit_code]="124"
    [assertions_passed]="999"
    [assertions_failed]="001"
    [assertions_total]="1000"
    [duration_seconds]="3600"
    [test_log_path]="/tmp/test.log"
    [sandbox_path]="/tmp/sandbox"
    [timestamp]="2024-12-21T20:00:00+0000"
  )

  local file="$TEST_TEMP_DIR/numeric_test.txt"

  # Write and read
  __write_result_to_file original "$file"

  declare -A restored
  __read_result_from_file "$file" restored

  # Assert numeric values preserved exactly
  assert_equals "${restored[exit_code]}" "124" "Exit code 124 preserved"
  assert_equals "${restored[assertions_passed]}" "999" "Large assertion count preserved"
  assert_equals "${restored[duration_seconds]}" "3600" "Large duration preserved"
}

