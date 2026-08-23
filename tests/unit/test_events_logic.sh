#!/usr/bin/env bash

# KGSM Events Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/events.sh - Pure logic functions only
#
# This test file focuses exclusively on the events handler logic layer:
# - __logic_validate_event_type()
# - __logic_validate_event_params()
# - __logic_get_event_param_spec()
# - __logic_event_name_to_type()
#
# Does NOT test:
# - Command execution (events.sh commands)
# - JSON payload generation (integration test)
# - Event transport/broadcasting (integration test)

# =============================================================================
# TEST SETUP
# =============================================================================

# Test variables
readonly TEST_NAME="events_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/events.sh"

# =============================================================================
# SETUP FUNCTION
# =============================================================================

function setup_file() {
  log_test_step "Setting up events logic tests"

  # Verify test environment
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  # Verify handler exists
  assert_file_exists "$HANDLER" "Events handler should exist"

  # Source the handler
  source "$HANDLER"

  # Verify module loaded guard
  assert_not_null "$KGSM_LOGIC_EVENTS_LOADED" "Handler should set loaded guard"
  assert_equals "$KGSM_LOGIC_EVENTS_LOADED" "1" "Loaded guard should be 1"

  # Verify error codes are defined
  assert_not_null "$EC_SUCCESS" "EC_SUCCESS should be defined"
  assert_not_null "$EC_EVENT_TYPE_INVALID" "EC_EVENT_TYPE_INVALID should be defined"
  assert_not_null "$EC_EVENT_PARAMS_INVALID" "EC_EVENT_PARAMS_INVALID should be defined"

  # Verify all logic functions are exported
  assert_function_exists "__logic_validate_event_type" \
    "__logic_validate_event_type should be exported"
  assert_function_exists "__logic_validate_event_params" \
    "__logic_validate_event_params should be exported"
  assert_function_exists "__logic_get_event_param_spec" \
    "__logic_get_event_param_spec should be exported"
  assert_function_exists "__logic_event_name_to_type" \
    "__logic_event_name_to_type should be exported"

  # Verify EVENT_CONFIGS is populated
  assert_not_null "${EVENT_CONFIGS[instance_created]}" \
    "EVENT_CONFIGS should contain instance_created"
  assert_not_null "${EVENT_CONFIGS[instance_removed]}" \
    "EVENT_CONFIGS should contain instance_removed"

  log_test_step "Events handler environment validated"
}

# =============================================================================
# TESTS: __logic_validate_event_type()
# =============================================================================

function test_validate_event_type_valid_single_param() {
  log_test_step "Testing __logic_validate_event_type with valid single-param event"

  __logic_validate_event_type "instance_ready"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type 'instance_ready'"
}

function test_validate_event_type_valid_multi_param() {
  log_test_step "Testing __logic_validate_event_type with valid multi-param event"

  __logic_validate_event_type "instance_version_updated"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type 'instance_version_updated'"
}

function test_validate_event_type_invalid_returns_error() {
  log_test_step "Testing __logic_validate_event_type with non-existent event type"

  __logic_validate_event_type "invalid_event_type" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for non-existent event type"
}

function test_validate_event_type_empty_returns_error() {
  log_test_step "Testing __logic_validate_event_type with empty parameter"

  __logic_validate_event_type "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for empty parameter"
}

function test_validate_event_type_all_40_constants() {
  log_test_step "Testing __logic_validate_event_type with all 41 event constants"

  local event_types=(
    "instance_created"
    "instance_directories_created"
    "instance_files_created"
    "instance_download_started"
    "instance_download_finished"
    "instance_download_failed"
    "instance_downloaded"
    "instance_deploy_started"
    "instance_deploy_finished"
    "instance_deploy_failed"
    "instance_deployed"
    "instance_update_started"
    "instance_update_finished"
    "instance_updated"
    "instance_version_updated"
    "instance_installation_started"
    "instance_installation_finished"
    "instance_installed"
    "instance_moved"
    "instance_started"
    "instance_stopped"
    "instance_restarted"
    "instance_crashed"
    "instance_failed"
    "instance_ready"
    "instance_backup_created"
    "instance_backup_restored"
    "instance_files_removed"
    "instance_directories_removed"
    "instance_removed"
    "instance_uninstall_started"
    "instance_uninstall_finished"
    "instance_uninstall_failed"
    "instance_uninstalled"
    "instance_ports_opened"
    "instance_ports_closed"
    "instance_upnp_opened"
    "instance_upnp_closed"
    "instance_upnp_reasserted"
    "instance_player_joined"
    "instance_player_left"
    "instance_config_changed"
    "instance_display_name_changed"
    "instance_input_sent"
    "blueprint_created"
    "blueprint_updated"
    "blueprint_removed"
    "library_added"
    "library_removed"
  )

  local failed_events=()
  for event_type in "${event_types[@]}"; do
    __logic_validate_event_type "$event_type"
    if [[ $? -ne $EC_SUCCESS ]]; then
      failed_events+=("$event_type")
    fi
  done

  assert_equals "${#failed_events[@]}" "0" \
    "All 45 event types should be valid. Failed: ${failed_events[*]}"
}

function test_validate_event_type_case_sensitive() {
  log_test_step "Testing __logic_validate_event_type is case-sensitive"

  __logic_validate_event_type "INSTANCE_CREATED" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for uppercase event type"
}

function test_validate_event_type_partial_match_fails() {
  log_test_step "Testing __logic_validate_event_type rejects partial matches"

  __logic_validate_event_type "instance_creat" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for partial match 'instance_creat'"
}

function test_validate_event_type_special_chars_fail() {
  log_test_step "Testing __logic_validate_event_type rejects special characters"

  __logic_validate_event_type "instance@created" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for event type with special chars"
}

# =============================================================================
# TESTS: __logic_validate_event_params()
# =============================================================================

function test_validate_params_single_param_valid() {
  log_test_step "Testing __logic_validate_event_params with valid single parameter"

  __logic_validate_event_params "instance_ready" "test_instance"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for instance_ready with 1 valid parameter"
}

function test_validate_params_two_param_valid() {
  log_test_step "Testing __logic_validate_event_params with valid two parameters"

  __logic_validate_event_params "instance_created" "test_instance" "factorio"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for instance_created with 2 valid parameters"
}

function test_validate_params_three_param_valid() {
  log_test_step "Testing __logic_validate_event_params with valid three parameters"

  __logic_validate_event_params "instance_version_updated" "test_instance" "1.0.0" "2.0.0"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for instance_version_updated with 3 valid parameters"
}

function test_validate_params_invalid_event_type() {
  log_test_step "Testing __logic_validate_event_params with invalid event type"

  __logic_validate_event_params "invalid_event" "param1" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for non-existent event type"
}

function test_validate_params_missing_all_params() {
  log_test_step "Testing __logic_validate_event_params with no parameters"

  __logic_validate_event_params "instance_ready" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID when required parameters missing"
}

function test_validate_params_missing_one_param() {
  log_test_step "Testing __logic_validate_event_params with insufficient parameters"

  __logic_validate_event_params "instance_created" "test_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID for instance_created missing blueprint parameter"
}

function test_validate_params_empty_first_param() {
  log_test_step "Testing __logic_validate_event_params with empty first parameter"

  __logic_validate_event_params "instance_ready" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID when first parameter is empty"
}

function test_validate_params_empty_middle_param() {
  log_test_step "Testing __logic_validate_event_params with empty middle parameter"

  __logic_validate_event_params "instance_version_updated" "test_instance" "" "2.0.0" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID when middle parameter is empty"
}

function test_validate_params_extra_params_allowed() {
  log_test_step "Testing __logic_validate_event_params allows extra parameters"

  __logic_validate_event_params "instance_ready" "test_instance" "extra1" "extra2"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS when extra parameters provided (only minimum validated)"
}

function test_validate_params_backup_source_version() {
  log_test_step "Testing __logic_validate_event_params with backup event (3 params)"

  __logic_validate_event_params "instance_backup_created" "test_instance" "/path/to/source" "1.2.3"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for instance_backup_created with 3 parameters"
}

function test_validate_params_special_chars_in_values() {
  log_test_step "Testing __logic_validate_event_params with special characters in parameter values"

  __logic_validate_event_params "instance_created" "test-instance_123" "factorio-modded"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS when parameters contain dashes/underscores"
}

# =============================================================================
# TESTS: __logic_get_event_param_spec()
# =============================================================================

function test_get_param_spec_single_param_event() {
  log_test_step "Testing __logic_get_event_param_spec for single parameter event"

  local spec
  spec=$(__logic_get_event_param_spec "instance_ready")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type"
  assert_equals "$spec" "instance" \
    "Should return 'instance' spec for instance_ready event"
}

function test_get_param_spec_two_param_event() {
  log_test_step "Testing __logic_get_event_param_spec for two parameter event"

  local spec
  spec=$(__logic_get_event_param_spec "instance_created")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type"
  assert_equals "$spec" "instance blueprint" \
    "Should return 'instance blueprint' spec for instance_created event"
}

function test_get_param_spec_three_param_event() {
  log_test_step "Testing __logic_get_event_param_spec for three parameter event"

  local spec
  spec=$(__logic_get_event_param_spec "instance_version_updated")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type"
  assert_equals "$spec" "instance old_version new_version" \
    "Should return 'instance old_version new_version' spec for instance_version_updated event"
}

function test_get_param_spec_returns_ec_okay() {
  log_test_step "Testing __logic_get_event_param_spec returns EC_SUCCESS on success"

  __logic_get_event_param_spec "instance_ready" >/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS exit code on successful spec retrieval"
}

function test_get_param_spec_invalid_event_type() {
  log_test_step "Testing __logic_get_event_param_spec with invalid event type"

  __logic_get_event_param_spec "invalid_event" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for non-existent event type"
}

function test_get_param_spec_empty_param() {
  log_test_step "Testing __logic_get_event_param_spec with empty parameter"

  __logic_get_event_param_spec "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for empty parameter"
}

function test_get_param_spec_lifecycle_events() {
  log_test_step "Testing __logic_get_event_param_spec for lifecycle events"

  local spec_started
  spec_started=$(__logic_get_event_param_spec "instance_started")
  local spec_stopped
  spec_stopped=$(__logic_get_event_param_spec "instance_stopped")

  assert_equals "$spec_started" "instance" \
    "Should return 'instance' for instance_started"
  assert_equals "$spec_stopped" "instance" \
    "Should return 'instance' for instance_stopped"
}

function test_get_param_spec_backup_events() {
  log_test_step "Testing __logic_get_event_param_spec for backup events"

  local spec_created
  spec_created=$(__logic_get_event_param_spec "instance_backup_created")
  local spec_restored
  spec_restored=$(__logic_get_event_param_spec "instance_backup_restored")

  assert_equals "$spec_created" "instance source version" \
    "Should return 'instance source version' for instance_backup_created"
  assert_equals "$spec_restored" "instance source version" \
    "Should return 'instance source version' for instance_backup_restored"
}

function test_get_param_spec_output_format_space_separated() {
  log_test_step "Testing __logic_get_event_param_spec output format"

  local spec
  spec=$(__logic_get_event_param_spec "instance_version_updated")

  # Verify no leading/trailing whitespace
  assert_equals "$spec" "${spec#"${spec%%[![:space:]]*}"}" \
    "Should not have leading whitespace"
  assert_equals "$spec" "${spec%"${spec##*[![:space:]]}"}" \
    "Should not have trailing whitespace"

  # Verify contains spaces between parameters
  assert_contains "$spec" " " \
    "Should contain spaces between parameters"
}

function test_get_param_spec_all_40_events() {
  log_test_step "Testing __logic_get_event_param_spec for all 41 events"

  local event_types=(
    "instance_created"
    "instance_directories_created"
    "instance_files_created"
    "instance_download_started"
    "instance_download_finished"
    "instance_download_failed"
    "instance_downloaded"
    "instance_deploy_started"
    "instance_deploy_finished"
    "instance_deploy_failed"
    "instance_deployed"
    "instance_update_started"
    "instance_update_finished"
    "instance_updated"
    "instance_version_updated"
    "instance_installation_started"
    "instance_installation_finished"
    "instance_installed"
    "instance_moved"
    "instance_started"
    "instance_stopped"
    "instance_restarted"
    "instance_crashed"
    "instance_failed"
    "instance_ready"
    "instance_backup_created"
    "instance_backup_restored"
    "instance_files_removed"
    "instance_directories_removed"
    "instance_removed"
    "instance_uninstall_started"
    "instance_uninstall_finished"
    "instance_uninstall_failed"
    "instance_uninstalled"
    "instance_ports_opened"
    "instance_ports_closed"
    "instance_upnp_opened"
    "instance_upnp_closed"
    "instance_upnp_reasserted"
    "instance_player_joined"
    "instance_player_left"
    "instance_config_changed"
    "instance_display_name_changed"
    "instance_input_sent"
    "blueprint_created"
    "blueprint_updated"
    "blueprint_removed"
    "library_added"
    "library_removed"
  )

  local failed_events=()
  for event_type in "${event_types[@]}"; do
    local spec
    spec=$(__logic_get_event_param_spec "$event_type")
    local exit_code=$?

    if [[ $exit_code -ne $EC_SUCCESS ]] || [[ -z "$spec" ]]; then
      failed_events+=("$event_type")
    fi
  done

  assert_equals "${#failed_events[@]}" "0" \
    "All 45 events should return valid specs. Failed: ${failed_events[*]}"
}

function test_get_param_spec_firewall_ports_events() {
  log_test_step "Testing __logic_get_event_param_spec for the firewall ports events"

  local spec_opened spec_closed
  spec_opened=$(__logic_get_event_param_spec "instance_ports_opened")
  spec_closed=$(__logic_get_event_param_spec "instance_ports_closed")

  assert_equals "instance ports" "$spec_opened" \
    "instance_ports_opened should require 'instance ports'"
  assert_equals "instance ports" "$spec_closed" \
    "instance_ports_closed should require 'instance ports'"
}

function test_get_param_spec_upnp_events() {
  log_test_step "Testing __logic_get_event_param_spec for the UPnP port-forwarding events"

  local spec_opened spec_closed spec_reasserted
  spec_opened=$(__logic_get_event_param_spec "instance_upnp_opened")
  spec_closed=$(__logic_get_event_param_spec "instance_upnp_closed")
  spec_reasserted=$(__logic_get_event_param_spec "instance_upnp_reasserted")

  # Same 'instance ports' spec as the firewall events — all carry the structured
  # Ports payload; the event TYPE (not the param shape) distinguishes router from host,
  # and a sweep's re-assert from a bring-up open.
  assert_equals "instance ports" "$spec_opened" \
    "instance_upnp_opened should require 'instance ports'"
  assert_equals "instance ports" "$spec_closed" \
    "instance_upnp_closed should require 'instance ports'"
  assert_equals "instance ports" "$spec_reasserted" \
    "instance_upnp_reasserted should require 'instance ports'"
}

# =============================================================================
# TESTS: player-presence events (nullable player_id / player_name)
# =============================================================================
# player_id and player_name are deliberately ABSENT from the EVENT_CONFIGS spec
# (only `instance` is required) so the validator never forces them non-empty —
# their nullability is what keeps the wire honest. The JSON-null rendering of an
# omitted value lives in _build_event_payload and is covered by the command-layer
# payload test, not here (this file tests pure logic only).

function test_validate_event_type_player_events() {
  log_test_step "Testing __logic_validate_event_type for player-presence events"

  __logic_validate_event_type "instance_player_joined"
  local joined_code=$?
  __logic_validate_event_type "instance_player_left"
  local left_code=$?

  assert_equals "$joined_code" "$EC_SUCCESS" \
    "instance_player_joined should be a valid event type"
  assert_equals "$left_code" "$EC_SUCCESS" \
    "instance_player_left should be a valid event type"
}

function test_get_param_spec_player_events_instance_only() {
  log_test_step "Testing player-presence events require only 'instance'"

  local spec_joined spec_left
  spec_joined=$(__logic_get_event_param_spec "instance_player_joined")
  spec_left=$(__logic_get_event_param_spec "instance_player_left")

  # Only `instance` is required: player_id/player_name are nullable, so they are
  # intentionally NOT part of the required-param spec.
  assert_equals "instance" "$spec_joined" \
    "instance_player_joined should require only 'instance' (id/name nullable)"
  assert_equals "instance" "$spec_left" \
    "instance_player_left should require only 'instance' (id/name nullable)"
}

function test_validate_params_player_joined_instance_only() {
  log_test_step "Testing instance_player_joined validates with only the instance"

  # A join with neither id nor name supplied must still pass validation — the
  # at-least-one-non-null guarantee is the emitting shim's job, not KGSM's.
  __logic_validate_event_params "instance_player_joined" "test_instance"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "instance_player_joined should validate with only the instance param"
}

function test_validate_params_player_joined_with_id_and_name() {
  log_test_step "Testing instance_player_joined validates with id and name"

  __logic_validate_event_params "instance_player_joined" \
    "test_instance" "76561198000000000" "Alice"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "instance_player_joined should validate with instance, id and name"
}

function test_validate_params_player_left_empty_instance_fails() {
  log_test_step "Testing instance_player_left rejects an empty instance"

  __logic_validate_event_params "instance_player_left" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "instance_player_left should reject an empty required instance param"
}

function test_event_name_to_type_player_events() {
  log_test_step "Testing dash-to-underscore conversion for player events"

  local joined left
  joined=$(__logic_event_name_to_type "instance-player-joined")
  left=$(__logic_event_name_to_type "instance-player-left")

  assert_equals "$joined" "instance_player_joined" \
    "Should convert 'instance-player-joined' to 'instance_player_joined'"
  assert_equals "$left" "instance_player_left" \
    "Should convert 'instance-player-left' to 'instance_player_left'"
}

# =============================================================================
# TESTS: instance_config_changed event (instance + key, NEVER the value)
# =============================================================================
# The value is deliberately ABSENT from the EVENT_CONFIGS spec — config-set holds
# secrets (RCON/admin passwords), so only the instance + key are audited. The
# value-never-carried property is proven in the integration test (it captures the
# real payload); this file tests pure logic only: validation, the param spec, and
# the dash-to-underscore name conversion.

function test_validate_event_type_config_changed() {
  log_test_step "Testing __logic_validate_event_type for instance_config_changed"

  __logic_validate_event_type "instance_config_changed"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "instance_config_changed should be a valid event type"
}

function test_get_param_spec_config_changed_instance_key() {
  log_test_step "Testing instance_config_changed requires 'instance key'"

  local spec
  spec=$(__logic_get_event_param_spec "instance_config_changed")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for instance_config_changed"
  # 'instance key' — the value is NOT a required param (and never carried).
  assert_equals "instance key" "$spec" \
    "instance_config_changed should require 'instance key' (never the value)"
}

function test_validate_params_config_changed_valid() {
  log_test_step "Testing instance_config_changed validates with instance + key"

  __logic_validate_event_params "instance_config_changed" "test_instance" "rcon_password"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "instance_config_changed should validate with instance and key params"
}

function test_validate_params_config_changed_missing_key_fails() {
  log_test_step "Testing instance_config_changed rejects a missing key"

  __logic_validate_event_params "instance_config_changed" "test_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "instance_config_changed should reject a missing key param"
}

function test_event_name_to_type_config_changed() {
  log_test_step "Testing dash-to-underscore conversion for instance-config-changed"

  local result
  result=$(__logic_event_name_to_type "instance-config-changed")

  assert_equals "$result" "instance_config_changed" \
    "Should convert 'instance-config-changed' to 'instance_config_changed'"
}

# =============================================================================
# TESTS: library_* events (library-scoped, not instance-scoped)
# =============================================================================
# Their subject is a placement root — a named disk instances live on — so their
# Data is keyed on LibraryName and Path rather than InstanceName.

function test_validate_event_type_library_events() {
  log_test_step "Testing __logic_validate_event_type for the two library events"

  local failed=()
  local event_type
  for event_type in library_added library_removed; do
    __logic_validate_event_type "$event_type"
    [[ $? -ne $EC_SUCCESS ]] && failed+=("$event_type")
  done

  assert_equals "${#failed[@]}" "0" \
    "All library event types should be valid. Failed: ${failed[*]}"
}

function test_get_param_spec_library_events() {
  log_test_step "Testing library_added/removed require 'name path'"

  local added removed
  added=$(__logic_get_event_param_spec "library_added")
  removed=$(__logic_get_event_param_spec "library_removed")

  # The path rides along because the name alone is not enough to act on: a
  # removal takes the name out of the registry, and a reader that only learns
  # the name cannot say which disk left.
  assert_equals "name path" "$added" "library_added should require 'name path'"
  assert_equals "name path" "$removed" "library_removed should require 'name path'"
}

function test_validate_params_library_added_requires_both() {
  log_test_step "Testing library_added rejects a name with no path"

  __logic_validate_event_params "library_added" "ssd" "/mnt/ssd"
  assert_equals "$?" "$EC_SUCCESS" "Both params should validate"

  __logic_validate_event_params "library_added" "ssd"
  assert_equals "$?" "$EC_EVENT_PARAMS_INVALID" "A missing path should be rejected"

  __logic_validate_event_params "library_added" "ssd" ""
  assert_equals "$?" "$EC_EVENT_PARAMS_INVALID" "An empty path should be rejected"
}

function test_event_name_to_type_library_events() {
  log_test_step "Testing dash-to-underscore conversion for the library events"

  assert_equals "$(__logic_event_name_to_type "library-added")" "library_added" \
    "library-added should convert to library_added"
  assert_equals "$(__logic_event_name_to_type "library-removed")" "library_removed" \
    "library-removed should convert to library_removed"
}

function test_build_payload_library_added_is_library_scoped() {
  log_test_step "Testing the library_added payload keys Data on LibraryName"

  local payload
  payload=$(__logic_build_event_payload "library_added" "ssd" "/mnt/ssd")
  assert_equals "$?" "$EC_SUCCESS" "Payload should build"

  assert_equals "$(echo "$payload" | jq -r '.EventType')" "library_added" \
    "EventType should be library_added"
  assert_equals "$(echo "$payload" | jq -r '.Data.LibraryName')" "ssd" \
    "Data should carry LibraryName"
  assert_equals "$(echo "$payload" | jq -r '.Data.Path')" "/mnt/ssd" \
    "Data should carry Path"
  assert_command_succeeds "echo '$payload' | jq -e '.Data.InstanceName == null'" \
    "A library event names no instance"
}

# =============================================================================
# TESTS: blueprint_* events (blueprint-scoped, not instance-scoped)
# =============================================================================
# The only events whose subject is a blueprint rather than an instance. This file
# tests pure logic: the param specs, validation, and name conversion. That the
# payload keys Data on BlueprintName (not InstanceName), renders the booleans as
# real JSON booleans, and honest-nulls an unknown runtime is proven in the
# integration test, which captures the real payload off the socket.

function test_validate_event_type_blueprint_events() {
  log_test_step "Testing __logic_validate_event_type for the three blueprint events"

  local failed=()
  local event_type
  for event_type in blueprint_created blueprint_updated blueprint_removed; do
    __logic_validate_event_type "$event_type"
    [[ $? -ne $EC_SUCCESS ]] && failed+=("$event_type")
  done

  assert_equals "${#failed[@]}" "0" \
    "All blueprint event types should be valid. Failed: ${failed[*]}"
}

function test_get_param_spec_blueprint_created_and_updated() {
  log_test_step "Testing blueprint_created/updated require 'blueprint tier overrides_system'"

  local created updated
  created=$(__logic_get_event_param_spec "blueprint_created")
  updated=$(__logic_get_event_param_spec "blueprint_updated")

  # `runtime` is deliberately NOT in the spec: it is nullable, read positionally,
  # and rendered as JSON null when the emitter could not determine it.
  assert_equals "blueprint tier overrides_system" "$created" \
    "blueprint_created should require 'blueprint tier overrides_system' (runtime is nullable)"
  assert_equals "blueprint tier overrides_system" "$updated" \
    "blueprint_updated should require 'blueprint tier overrides_system' (runtime is nullable)"
}

function test_get_param_spec_blueprint_removed() {
  log_test_step "Testing blueprint_removed requires 'blueprint tier reverted_to_system'"

  local spec
  spec=$(__logic_get_event_param_spec "blueprint_removed")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for blueprint_removed"
  # No `runtime`: the file is gone, so its runtime is no longer a fact the event
  # can state.
  assert_equals "blueprint tier reverted_to_system" "$spec" \
    "blueprint_removed should require 'blueprint tier reverted_to_system'"
}

function test_validate_params_blueprint_updated_valid() {
  log_test_step "Testing blueprint_updated validates with name, tier, and overrides flag"

  __logic_validate_event_params "blueprint_updated" "terraria" "user" "true"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "blueprint_updated should validate with its three required params"
}

function test_validate_params_blueprint_updated_accepts_optional_runtime() {
  log_test_step "Testing blueprint_updated accepts the optional trailing runtime"

  __logic_validate_event_params "blueprint_updated" "terraria" "user" "true" "native"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "blueprint_updated should accept a 4th positional runtime param"
}

function test_validate_params_blueprint_updated_missing_overrides_fails() {
  log_test_step "Testing blueprint_updated rejects a missing overrides_system flag"

  __logic_validate_event_params "blueprint_updated" "terraria" "user" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "blueprint_updated should reject a missing overrides_system param"
}

function test_validate_params_blueprint_removed_missing_reverted_fails() {
  log_test_step "Testing blueprint_removed rejects a missing reverted_to_system flag"

  __logic_validate_event_params "blueprint_removed" "terraria" "user" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "blueprint_removed should reject a missing reverted_to_system param"
}

function test_event_name_to_type_blueprint_events() {
  log_test_step "Testing dash-to-underscore conversion for blueprint events"

  local created updated removed
  created=$(__logic_event_name_to_type "blueprint-created")
  updated=$(__logic_event_name_to_type "blueprint-updated")
  removed=$(__logic_event_name_to_type "blueprint-removed")

  assert_equals "$created" "blueprint_created" \
    "Should convert 'blueprint-created' to 'blueprint_created'"
  assert_equals "$updated" "blueprint_updated" \
    "Should convert 'blueprint-updated' to 'blueprint_updated'"
  assert_equals "$removed" "blueprint_removed" \
    "Should convert 'blueprint-removed' to 'blueprint_removed'"
}

# =============================================================================
# TESTS: __logic_event_name_to_type()
# =============================================================================

function test_event_name_to_type_simple_conversion() {
  log_test_step "Testing __logic_event_name_to_type with simple dash-to-underscore conversion"

  local result
  result=$(__logic_event_name_to_type "instance-created")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid dash-separated event name"
  assert_equals "$result" "instance_created" \
    "Should convert 'instance-created' to 'instance_created'"
}

function test_event_name_to_type_multi_dash() {
  log_test_step "Testing __logic_event_name_to_type with multiple dashes"

  local result
  result=$(__logic_event_name_to_type "instance-version-updated")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for multi-dash event name"
  assert_equals "$result" "instance_version_updated" \
    "Should convert 'instance-version-updated' to 'instance_version_updated'"
}

function test_event_name_to_type_returns_ec_okay() {
  log_test_step "Testing __logic_event_name_to_type returns EC_SUCCESS on success"

  __logic_event_name_to_type "instance-ready" >/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS exit code for valid conversion"
}

function test_event_name_to_type_invalid_dash_name() {
  log_test_step "Testing __logic_event_name_to_type with invalid event name"

  __logic_event_name_to_type "invalid-event-name" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for non-existent event name"
}

function test_event_name_to_type_empty_param() {
  log_test_step "Testing __logic_event_name_to_type with empty parameter"

  __logic_event_name_to_type "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for empty parameter"
}

function test_event_name_to_type_already_underscore() {
  log_test_step "Testing __logic_event_name_to_type with already underscore-separated input"

  local result
  result=$(__logic_event_name_to_type "instance_created")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for underscore-separated input if it exists"
  assert_equals "$result" "instance_created" \
    "Should return 'instance_created' unchanged"
}

function test_event_name_to_type_validates_converted_exists() {
  log_test_step "Testing __logic_event_name_to_type validates converted type exists"

  __logic_event_name_to_type "instance-nonexistent" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID even after conversion if type doesn't exist"
}

function test_event_name_to_type_all_29_events() {
  log_test_step "Testing __logic_event_name_to_type for all 29 events with dash conversion"

  local dash_events=(
    "instance-created:instance_created"
    "instance-directories-created:instance_directories_created"
    "instance-files-created:instance_files_created"
    "instance-download-started:instance_download_started"
    "instance-download-finished:instance_download_finished"
    "instance-downloaded:instance_downloaded"
    "instance-deploy-started:instance_deploy_started"
    "instance-deploy-finished:instance_deploy_finished"
    "instance-deployed:instance_deployed"
    "instance-update-started:instance_update_started"
    "instance-update-finished:instance_update_finished"
    "instance-updated:instance_updated"
    "instance-version-updated:instance_version_updated"
    "instance-installation-started:instance_installation_started"
    "instance-installation-finished:instance_installation_finished"
    "instance-installed:instance_installed"
    "instance-moved:instance_moved"
    "instance-started:instance_started"
    "instance-stopped:instance_stopped"
    "instance-crashed:instance_crashed"
    "instance-failed:instance_failed"
    "instance-ready:instance_ready"
    "instance-backup-created:instance_backup_created"
    "instance-backup-restored:instance_backup_restored"
    "instance-files-removed:instance_files_removed"
    "instance-directories-removed:instance_directories_removed"
    "instance-removed:instance_removed"
    "instance-uninstall-started:instance_uninstall_started"
    "instance-uninstall-finished:instance_uninstall_finished"
    "instance-uninstalled:instance_uninstalled"
  )

  local failed_conversions=()
  for event_pair in "${dash_events[@]}"; do
    local dash_name="${event_pair%%:*}"
    local expected_result="${event_pair##*:}"

    local result
    result=$(__logic_event_name_to_type "$dash_name")
    local exit_code=$?

    if [[ $exit_code -ne $EC_SUCCESS ]] || [[ "$result" != "$expected_result" ]]; then
      failed_conversions+=("$dash_name->$result (expected $expected_result)")
    fi
  done

  assert_equals "${#failed_conversions[@]}" "0" \
    "All 29 dash-to-underscore conversions should succeed. Failed: ${failed_conversions[*]}"
}

function test_event_name_to_type_mixed_dash_underscore() {
  log_test_step "Testing __logic_event_name_to_type with mixed dashes and underscores"

  local result
  result=$(__logic_event_name_to_type "instance-version_updated" 2>/dev/null)
  local exit_code=$?

  # This should convert dashes to underscores, resulting in instance_version_updated
  # which is a valid event type
  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should handle mixed dash/underscore input by converting dashes"
  assert_equals "$result" "instance_version_updated" \
    "Should convert 'instance-version_updated' to 'instance_version_updated'"
}

function test_event_name_to_type_no_output_on_failure() {
  log_test_step "Testing __logic_event_name_to_type produces no output on failure"

  local output
  output=$(__logic_event_name_to_type "invalid-event" 2>/dev/null)

  assert_null "$output" \
    "Should not echo anything on failure (only on success)"
}

function test_event_name_to_type_partial_match_after_conversion() {
  log_test_step "Testing __logic_event_name_to_type rejects partial matches after conversion"

  __logic_event_name_to_type "instance-creat" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_TYPE_INVALID" \
    "Should return EC_EVENT_TYPE_INVALID for partial match even after conversion"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

function test_edge_case_very_long_parameter_values() {
  log_test_step "Testing validation with very long parameter values"

  local long_value
  long_value=$(printf 'a%.0s' {1..500})  # 500 character string

  __logic_validate_event_params "instance_created" "$long_value" "blueprint_name"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS even with 500+ character parameter values"
}

function test_edge_case_special_characters_in_params() {
  log_test_step "Testing validation with special characters in parameter values"

  # Test with paths, spaces in quotes would be separate args, so test path-like strings
  __logic_validate_event_params "instance_backup_created" "test-inst_123" "/path/to/source.tar.gz" "v1.2.3-beta"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS with special characters like dashes, underscores, slashes, dots"
}

function test_edge_case_all_events_have_configs() {
  log_test_step "Testing that all EVENT_* constants have EVENT_CONFIGS entries"

  # Get all EVENT_* constant names (exported variables). Matches every event
  # family, not just EVENT_INSTANCE_* — the blueprint events are not
  # instance-scoped and an instance-only match would leave them unguarded.
  # EVENT_CONFIGS is the spec map itself, not an event name, so it is excluded.
  local all_event_constants=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^EVENT_ && ! "$line" =~ ^EVENT_CONFIGS ]]; then
      # Extract the value of the constant
      local const_name="${line%%=*}"
      local const_value="${line#*=\"}"
      const_value="${const_value%\"}"
      all_event_constants+=("$const_value")
    fi
  done < <(declare -p | grep "^declare -[^ ]*x[^ ]* EVENT_")

  local missing_configs=()
  for event_const in "${all_event_constants[@]}"; do
    if [[ -z "${EVENT_CONFIGS[$event_const]}" ]]; then
      missing_configs+=("$event_const")
    fi
  done

  assert_equals "${#missing_configs[@]}" "0" \
    "All EVENT_* constants should have EVENT_CONFIGS entries. Missing: ${missing_configs[*]}"
}

function test_edge_case_event_count_matches_configs() {
  # A canary, not a rule: the number itself carries no meaning, but a change to it means the event
  # vocabulary grew or shrank, which is worth being deliberate about. Update it in the same commit
  # that adds or removes an event, together with the param spec beside it.
  log_test_step "Testing EVENT_CONFIGS count matches expected 67 events"

  local config_count="${#EVENT_CONFIGS[@]}"

  assert_equals "$config_count" "67" \
    "EVENT_CONFIGS should contain exactly 67 entries (found: $config_count)"
}

# Conformance guard: every event a call site actually emits must be registered
# in EVENT_CONFIGS. Emitting an unregistered name fails validation silently and
# never reaches any transport — the exact drift that hid instance-started,
# instance-restarted, and the *-failed events. Comment lines are excluded so the
# dispatcher's commented-out system-*/config-* TODOs do not false-positive.
function test_all_emit_call_sites_are_registered() {
  log_test_step "Testing every 'events.sh emit' call site is registered"

  local unregistered=()
  local name event_type
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    event_type="${name//-/_}"
    if [[ -z "${EVENT_CONFIGS[$event_type]}" ]]; then
      unregistered+=("$name")
    fi
  done < <(grep -rhE "events\.sh emit [a-z-]+" \
    "$KGSM_ROOT/commands" "$KGSM_ROOT/core" 2> /dev/null \
    | grep -vE "^[[:space:]]*#" \
    | grep -oE "events\.sh emit [a-z-]+" \
    | sed 's/events\.sh emit //' | sort -u)

  assert_equals "${#unregistered[@]}" "0" \
    "Every emitted event must be registered in EVENT_CONFIGS. Unregistered: ${unregistered[*]}"
}

