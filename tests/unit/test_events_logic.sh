#!/usr/bin/env bash

# Unit tests for commands/handlers/events.sh

# shellcheck disable=SC1091
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/common.sh"

readonly TEST_NAME="events_logic"

# Source bootstrap to get loader functions
# shellcheck disable=SC1091
source "$KGSM_ROOT/core/bootstrap.sh"

# Load the events logic library once
# shellcheck disable=SC1090
source "$KGSM_ROOT/commands/handlers/events.sh"

function test_validate_event_type_valid() {
  log_step "Testing event type validation - valid types"

  __logic_validate_event_type "instance_created"
  assert_equals 0 $? "Should validate instance_created event type"

  __logic_validate_event_type "instance_started"
  assert_equals 0 $? "Should validate instance_started event type"

  __logic_validate_event_type "instance_version_updated"
  assert_equals 0 $? "Should validate instance_version_updated event type"
}

function test_validate_event_type_invalid() {
  log_step "Testing event type validation - invalid types"

  __logic_validate_event_type "invalid_event"
  assert_equals "$EC_EVENT_TYPE_INVALID" $? "Should reject invalid event type"

  __logic_validate_event_type ""
  assert_equals "$EC_EVENT_TYPE_INVALID" $? "Should reject empty event type"
}

function test_validate_event_params_valid() {
  log_step "Testing event parameter validation - valid params"

  __logic_validate_event_params "instance_created" "myserver" "factorio"
  assert_equals 0 $? "Should validate params for instance_created"

  __logic_validate_event_params "instance_started" "myserver" "systemd"
  assert_equals 0 $? "Should validate params for instance_started"

  __logic_validate_event_params "instance_version_updated" "myserver" "1.0.0" "1.1.0"
  assert_equals 0 $? "Should validate params for instance_version_updated"
}

function test_validate_event_params_insufficient() {
  log_step "Testing event parameter validation - insufficient params"

  __logic_validate_event_params "instance_created" "myserver"
  assert_equals "$EC_EVENT_PARAMS_INVALID" $? "Should reject insufficient params for instance_created"

  __logic_validate_event_params "instance_version_updated" "myserver" "1.0.0"
  assert_equals "$EC_EVENT_PARAMS_INVALID" $? "Should reject insufficient params for instance_version_updated"
}

function test_validate_event_params_empty() {
  log_step "Testing event parameter validation - empty params"

  __logic_validate_event_params "instance_created" "" "factorio"
  assert_equals "$EC_EVENT_PARAMS_INVALID" $? "Should reject empty instance name"

  __logic_validate_event_params "instance_version_updated" "myserver" "" "1.1.0"
  assert_equals "$EC_EVENT_PARAMS_INVALID" $? "Should reject empty version param"
}

function test_get_event_param_spec() {
  log_step "Testing event parameter spec retrieval"

  local spec
  spec=$(__logic_get_event_param_spec "instance_created")
  assert_equals 0 $? "Should return spec for valid event"
  assert_equals "instance blueprint" "$spec" "Should return correct param spec"

  spec=$(__logic_get_event_param_spec "instance_version_updated")
  assert_equals 0 $? "Should return spec for version_updated event"
  assert_equals "instance old_version new_version" "$spec" "Should return correct param spec for version_updated"
}

function test_get_event_param_spec_invalid() {
  log_step "Testing event parameter spec retrieval - invalid"

  __logic_get_event_param_spec "invalid_event" > /dev/null 2>&1
  assert_equals "$EC_EVENT_TYPE_INVALID" $? "Should reject invalid event type"
}

function test_event_name_to_type() {
  log_step "Testing event name to type conversion"

  local result
  result=$(__logic_event_name_to_type "instance-created")
  assert_equals 0 $? "Should convert dash-separated name"
  assert_equals "instance_created" "$result" "Should convert instance-created to instance_created"

  result=$(__logic_event_name_to_type "instance-version-updated")
  assert_equals 0 $? "Should convert complex dash-separated name"
  assert_equals "instance_version_updated" "$result" "Should convert instance-version-updated correctly"
}

function test_event_name_to_type_invalid() {
  log_step "Testing event name to type conversion - invalid"

  __logic_event_name_to_type "invalid-event" > /dev/null 2>&1
  assert_equals "$EC_EVENT_TYPE_INVALID" $? "Should reject invalid event name"

  __logic_event_name_to_type "" > /dev/null 2>&1
  assert_equals "$EC_EVENT_TYPE_INVALID" $? "Should reject empty event name"
}

function test_all_event_constants_defined() {
  log_step "Testing all event constants are defined"

  # Test that all major event constants are defined
  assert_not_null "$EVENT_INSTANCE_CREATED" "EVENT_INSTANCE_CREATED should be defined"
  assert_not_null "$EVENT_INSTANCE_STARTED" "EVENT_INSTANCE_STARTED should be defined"
  assert_not_null "$EVENT_INSTANCE_STOPPED" "EVENT_INSTANCE_STOPPED should be defined"
  assert_not_null "$EVENT_INSTANCE_VERSION_UPDATED" "EVENT_INSTANCE_VERSION_UPDATED should be defined"
  assert_not_null "$EVENT_INSTANCE_INSTALLED" "EVENT_INSTANCE_INSTALLED should be defined"
  assert_not_null "$EVENT_INSTANCE_UNINSTALLED" "EVENT_INSTANCE_UNINSTALLED should be defined"
}

function main() {
  log_test "Starting events logic unit tests"

  # Run all tests
  test_validate_event_type_valid
  test_validate_event_type_invalid
  test_validate_event_params_valid
  test_validate_event_params_insufficient
  test_validate_event_params_empty
  test_get_event_param_spec
  test_get_event_param_spec_invalid
  test_event_name_to_type
  test_event_name_to_type_invalid
  test_all_event_constants_defined

  log_test "Events logic unit tests completed"

  # Print summary and determine exit code
  if print_assert_summary "$TEST_NAME"; then
    pass_test "All events logic unit tests passed"
  else
    fail_test "Some events logic unit tests failed"
  fi
}

# Execute main function
main "$@"
