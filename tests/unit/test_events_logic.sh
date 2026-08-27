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

  # Verify EVENT_CONFIGS is populated
  assert_not_null "${EVENT_CONFIGS[server.install.created]}" \
    "EVENT_CONFIGS should contain server.install.created"
  assert_not_null "${EVENT_CONFIGS[server.uninstall.removed]}" \
    "EVENT_CONFIGS should contain server.uninstall.removed"

  log_test_step "Events handler environment validated"
}

# =============================================================================
# TESTS: __logic_validate_event_type()
# =============================================================================

function test_validate_event_type_valid_single_param() {
  log_test_step "Testing __logic_validate_event_type with valid single-param event"

  __logic_validate_event_type "server.ready"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type 'server.ready'"
}

function test_validate_event_type_valid_multi_param() {
  log_test_step "Testing __logic_validate_event_type with valid multi-param event"

  __logic_validate_event_type "server.updated"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type 'server.updated'"
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
    "server.install.created"
    "server.install.directories_created"
    "server.install.files_created"
    "server.download.started"
    "server.download.finished"
    "server.download.failed"
    "server.download.completed"
    "server.deploy.started"
    "server.deploy.finished"
    "server.deploy.failed"
    "server.deploy.completed"
    "server.update.started"
    "server.update.finished"
    "server.update.completed"
    "server.updated"
    "server.install.started"
    "server.install.finished"
    "server.installed"
    "server.moved"
    "server.started"
    "server.stopped"
    "server.restarted"
    "server.crashed"
    "server.crash.exhausted"
    "server.ready"
    "backup.created"
    "backup.restored"
    "server.uninstall.files_removed"
    "server.uninstall.directories_removed"
    "server.uninstall.removed"
    "server.uninstall.started"
    "server.uninstall.finished"
    "server.uninstall.failed"
    "server.uninstalled"
    "network.ports.opened"
    "network.ports.closed"
    "network.upnp.opened"
    "network.upnp.closed"
    "network.upnp.reasserted"
    "player.joined"
    "player.left"
    "config.changed"
    "server.renamed"
    "console.input.sent"
    "blueprint.created"
    "blueprint.updated"
    "blueprint.removed"
    "library.added"
    "library.removed"
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

  __logic_validate_event_params "server.ready" "test_instance"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for server.ready with 1 valid parameter"
}

function test_validate_params_two_param_valid() {
  log_test_step "Testing __logic_validate_event_params with valid two parameters"

  __logic_validate_event_params "server.install.created" "test_instance" "factorio"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for server.install.created with 2 valid parameters"
}

function test_validate_params_three_param_valid() {
  log_test_step "Testing __logic_validate_event_params with valid three parameters"

  __logic_validate_event_params "server.updated" "test_instance" "1.0.0" "2.0.0"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for server.updated with 3 valid parameters"
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

  __logic_validate_event_params "server.ready" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID when required parameters missing"
}

function test_validate_params_missing_one_param() {
  log_test_step "Testing __logic_validate_event_params with insufficient parameters"

  __logic_validate_event_params "server.install.created" "test_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID for server.install.created missing blueprint parameter"
}

function test_validate_params_empty_first_param() {
  log_test_step "Testing __logic_validate_event_params with empty first parameter"

  __logic_validate_event_params "server.ready" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID when first parameter is empty"
}

function test_validate_params_empty_middle_param() {
  log_test_step "Testing __logic_validate_event_params with empty middle parameter"

  __logic_validate_event_params "server.updated" "test_instance" "" "2.0.0" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "Should return EC_EVENT_PARAMS_INVALID when middle parameter is empty"
}

function test_validate_params_extra_params_allowed() {
  log_test_step "Testing __logic_validate_event_params allows extra parameters"

  __logic_validate_event_params "server.ready" "test_instance" "extra1" "extra2"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS when extra parameters provided (only minimum validated)"
}

function test_validate_params_backup_source_version() {
  log_test_step "Testing __logic_validate_event_params with backup event (3 params)"

  __logic_validate_event_params "backup.created" "test_instance" "/path/to/source" "1.2.3"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for backup.created with 3 parameters"
}

function test_validate_params_special_chars_in_values() {
  log_test_step "Testing __logic_validate_event_params with special characters in parameter values"

  __logic_validate_event_params "server.install.created" "test-instance_123" "factorio-modded"
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
  spec=$(__logic_get_event_param_spec "server.ready")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type"
  assert_equals "$spec" "instance" \
    "Should return 'instance' spec for server.ready event"
}

function test_get_param_spec_two_param_event() {
  log_test_step "Testing __logic_get_event_param_spec for two parameter event"

  local spec
  spec=$(__logic_get_event_param_spec "server.install.created")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type"
  assert_equals "$spec" "instance blueprint" \
    "Should return 'instance blueprint' spec for server.install.created event"
}

function test_get_param_spec_three_param_event() {
  log_test_step "Testing __logic_get_event_param_spec for three parameter event"

  local spec
  spec=$(__logic_get_event_param_spec "server.updated")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for valid event type"
  assert_equals "$spec" "instance old_version new_version" \
    "Should return 'instance old_version new_version' spec for server.updated event"
}

function test_get_param_spec_returns_ec_okay() {
  log_test_step "Testing __logic_get_event_param_spec returns EC_SUCCESS on success"

  __logic_get_event_param_spec "server.ready" >/dev/null
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
  spec_started=$(__logic_get_event_param_spec "server.started")
  local spec_stopped
  spec_stopped=$(__logic_get_event_param_spec "server.stopped")

  assert_equals "$spec_started" "instance" \
    "Should return 'instance' for server.started"
  assert_equals "$spec_stopped" "instance" \
    "Should return 'instance' for server.stopped"
}

function test_get_param_spec_backup_events() {
  log_test_step "Testing __logic_get_event_param_spec for backup events"

  local spec_created
  spec_created=$(__logic_get_event_param_spec "backup.created")
  local spec_restored
  spec_restored=$(__logic_get_event_param_spec "backup.restored")

  assert_equals "$spec_created" "instance source version" \
    "Should return 'instance source version' for backup.created"
  assert_equals "$spec_restored" "instance source version" \
    "Should return 'instance source version' for backup.restored"
}

function test_get_param_spec_output_format_space_separated() {
  log_test_step "Testing __logic_get_event_param_spec output format"

  local spec
  spec=$(__logic_get_event_param_spec "server.updated")

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
    "server.install.created"
    "server.install.directories_created"
    "server.install.files_created"
    "server.download.started"
    "server.download.finished"
    "server.download.failed"
    "server.download.completed"
    "server.deploy.started"
    "server.deploy.finished"
    "server.deploy.failed"
    "server.deploy.completed"
    "server.update.started"
    "server.update.finished"
    "server.update.completed"
    "server.updated"
    "server.install.started"
    "server.install.finished"
    "server.installed"
    "server.moved"
    "server.started"
    "server.stopped"
    "server.restarted"
    "server.crashed"
    "server.crash.exhausted"
    "server.ready"
    "backup.created"
    "backup.restored"
    "server.uninstall.files_removed"
    "server.uninstall.directories_removed"
    "server.uninstall.removed"
    "server.uninstall.started"
    "server.uninstall.finished"
    "server.uninstall.failed"
    "server.uninstalled"
    "network.ports.opened"
    "network.ports.closed"
    "network.upnp.opened"
    "network.upnp.closed"
    "network.upnp.reasserted"
    "player.joined"
    "player.left"
    "config.changed"
    "server.renamed"
    "console.input.sent"
    "blueprint.created"
    "blueprint.updated"
    "blueprint.removed"
    "library.added"
    "library.removed"
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
  spec_opened=$(__logic_get_event_param_spec "network.ports.opened")
  spec_closed=$(__logic_get_event_param_spec "network.ports.closed")

  assert_equals "instance ports" "$spec_opened" \
    "network.ports.opened should require 'instance ports'"
  assert_equals "instance ports" "$spec_closed" \
    "network.ports.closed should require 'instance ports'"
}

function test_get_param_spec_upnp_events() {
  log_test_step "Testing __logic_get_event_param_spec for the UPnP port-forwarding events"

  local spec_opened spec_closed spec_reasserted
  spec_opened=$(__logic_get_event_param_spec "network.upnp.opened")
  spec_closed=$(__logic_get_event_param_spec "network.upnp.closed")
  spec_reasserted=$(__logic_get_event_param_spec "network.upnp.reasserted")

  # Same 'instance ports' spec as the firewall events — all carry the structured
  # Ports payload; the event TYPE (not the param shape) distinguishes router from host,
  # and a sweep's re-assert from a bring-up open.
  assert_equals "instance ports" "$spec_opened" \
    "network.upnp.opened should require 'instance ports'"
  assert_equals "instance ports" "$spec_closed" \
    "network.upnp.closed should require 'instance ports'"
  assert_equals "instance ports" "$spec_reasserted" \
    "network.upnp.reasserted should require 'instance ports'"
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

  __logic_validate_event_type "player.joined"
  local joined_code=$?
  __logic_validate_event_type "player.left"
  local left_code=$?

  assert_equals "$joined_code" "$EC_SUCCESS" \
    "player.joined should be a valid event type"
  assert_equals "$left_code" "$EC_SUCCESS" \
    "player.left should be a valid event type"
}

function test_get_param_spec_player_events_instance_only() {
  log_test_step "Testing player-presence events require only 'instance'"

  local spec_joined spec_left
  spec_joined=$(__logic_get_event_param_spec "player.joined")
  spec_left=$(__logic_get_event_param_spec "player.left")

  # Only `instance` is required: player_id/player_name are nullable, so they are
  # intentionally NOT part of the required-param spec.
  assert_equals "instance" "$spec_joined" \
    "player.joined should require only 'instance' (id/name nullable)"
  assert_equals "instance" "$spec_left" \
    "player.left should require only 'instance' (id/name nullable)"
}

function test_validate_params_player_joined_instance_only() {
  log_test_step "Testing player.joined validates with only the instance"

  # A join with neither id nor name supplied must still pass validation — the
  # at-least-one-non-null guarantee is the emitting shim's job, not KGSM's.
  __logic_validate_event_params "player.joined" "test_instance"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "player.joined should validate with only the instance param"
}

function test_validate_params_player_joined_with_id_and_name() {
  log_test_step "Testing player.joined validates with id and name"

  __logic_validate_event_params "player.joined" \
    "test_instance" "76561198000000000" "Alice"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "player.joined should validate with instance, id and name"
}

function test_validate_params_player_left_empty_instance_fails() {
  log_test_step "Testing player.left rejects an empty instance"

  __logic_validate_event_params "player.left" "" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "player.left should reject an empty required instance param"
}

# =============================================================================
# TESTS: config.changed event (instance + key, NEVER the value)
# =============================================================================
# The value is deliberately ABSENT from the EVENT_CONFIGS spec — config-set holds
# secrets (RCON/admin passwords), so only the instance + key are audited. The
# value-never-carried property is proven in the integration test (it captures the
# real payload); this file tests pure logic only: validation and the param spec.

function test_validate_event_type_config_changed() {
  log_test_step "Testing __logic_validate_event_type for config.changed"

  __logic_validate_event_type "config.changed"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "config.changed should be a valid event type"
}

function test_get_param_spec_config_changed_instance_key() {
  log_test_step "Testing config.changed requires 'instance key'"

  local spec
  spec=$(__logic_get_event_param_spec "config.changed")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for config.changed"
  # 'instance key' — the value is NOT a required param (and never carried).
  assert_equals "instance key" "$spec" \
    "config.changed should require 'instance key' (never the value)"
}

function test_validate_params_config_changed_valid() {
  log_test_step "Testing config.changed validates with instance + key"

  __logic_validate_event_params "config.changed" "test_instance" "rcon_password"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "config.changed should validate with instance and key params"
}

function test_validate_params_config_changed_missing_key_fails() {
  log_test_step "Testing config.changed rejects a missing key"

  __logic_validate_event_params "config.changed" "test_instance" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "config.changed should reject a missing key param"
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
  for event_type in library.added library.removed; do
    __logic_validate_event_type "$event_type"
    [[ $? -ne $EC_SUCCESS ]] && failed+=("$event_type")
  done

  assert_equals "${#failed[@]}" "0" \
    "All library event types should be valid. Failed: ${failed[*]}"
}

function test_get_param_spec_library_events() {
  log_test_step "Testing library.added/removed require 'name path'"

  local added removed
  added=$(__logic_get_event_param_spec "library.added")
  removed=$(__logic_get_event_param_spec "library.removed")

  # The path rides along because the name alone is not enough to act on: a
  # removal takes the name out of the registry, and a reader that only learns
  # the name cannot say which disk left.
  assert_equals "name path" "$added" "library.added should require 'name path'"
  assert_equals "name path" "$removed" "library.removed should require 'name path'"
}

function test_validate_params_library_added_requires_both() {
  log_test_step "Testing library.added rejects a name with no path"

  __logic_validate_event_params "library.added" "ssd" "/mnt/ssd"
  assert_equals "$?" "$EC_SUCCESS" "Both params should validate"

  __logic_validate_event_params "library.added" "ssd"
  assert_equals "$?" "$EC_EVENT_PARAMS_INVALID" "A missing path should be rejected"

  __logic_validate_event_params "library.added" "ssd" ""
  assert_equals "$?" "$EC_EVENT_PARAMS_INVALID" "An empty path should be rejected"
}

function test_build_payload_library_added_is_library_scoped() {
  log_test_step "Testing the library.added payload keys Data on LibraryName"

  local payload
  payload=$(__logic_build_event_payload "library.added" "ssd" "/mnt/ssd")
  assert_equals "$?" "$EC_SUCCESS" "Payload should build"

  assert_equals "$(echo "$payload" | jq -r '.EventType')" "library.added" \
    "EventType should be library.added"
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
  for event_type in blueprint.created blueprint.updated blueprint.removed; do
    __logic_validate_event_type "$event_type"
    [[ $? -ne $EC_SUCCESS ]] && failed+=("$event_type")
  done

  assert_equals "${#failed[@]}" "0" \
    "All blueprint event types should be valid. Failed: ${failed[*]}"
}

function test_get_param_spec_blueprint_created_and_updated() {
  log_test_step "Testing blueprint.created/updated require 'blueprint tier overrides_system'"

  local created updated
  created=$(__logic_get_event_param_spec "blueprint.created")
  updated=$(__logic_get_event_param_spec "blueprint.updated")

  # `runtime` is deliberately NOT in the spec: it is nullable, read positionally,
  # and rendered as JSON null when the emitter could not determine it.
  assert_equals "blueprint tier overrides_system" "$created" \
    "blueprint.created should require 'blueprint tier overrides_system' (runtime is nullable)"
  assert_equals "blueprint tier overrides_system" "$updated" \
    "blueprint.updated should require 'blueprint tier overrides_system' (runtime is nullable)"
}

function test_get_param_spec_blueprint_removed() {
  log_test_step "Testing blueprint.removed requires 'blueprint tier reverted_to_system'"

  local spec
  spec=$(__logic_get_event_param_spec "blueprint.removed")
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS for blueprint.removed"
  # No `runtime`: the file is gone, so its runtime is no longer a fact the event
  # can state.
  assert_equals "blueprint tier reverted_to_system" "$spec" \
    "blueprint.removed should require 'blueprint tier reverted_to_system'"
}

function test_validate_params_blueprint_updated_valid() {
  log_test_step "Testing blueprint.updated validates with name, tier, and overrides flag"

  __logic_validate_event_params "blueprint.updated" "terraria" "user" "true"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "blueprint.updated should validate with its three required params"
}

function test_validate_params_blueprint_updated_accepts_optional_runtime() {
  log_test_step "Testing blueprint.updated accepts the optional trailing runtime"

  __logic_validate_event_params "blueprint.updated" "terraria" "user" "true" "native"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "blueprint.updated should accept a 4th positional runtime param"
}

function test_validate_params_blueprint_updated_missing_overrides_fails() {
  log_test_step "Testing blueprint.updated rejects a missing overrides_system flag"

  __logic_validate_event_params "blueprint.updated" "terraria" "user" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "blueprint.updated should reject a missing overrides_system param"
}

function test_validate_params_blueprint_removed_missing_reverted_fails() {
  log_test_step "Testing blueprint.removed rejects a missing reverted_to_system flag"

  __logic_validate_event_params "blueprint.removed" "terraria" "user" 2>/dev/null
  local exit_code=$?

  assert_equals "$exit_code" "$EC_EVENT_PARAMS_INVALID" \
    "blueprint.removed should reject a missing reverted_to_system param"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

function test_edge_case_very_long_parameter_values() {
  log_test_step "Testing validation with very long parameter values"

  local long_value
  long_value=$(printf 'a%.0s' {1..500})  # 500 character string

  __logic_validate_event_params "server.install.created" "$long_value" "blueprint_name"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" \
    "Should return EC_SUCCESS even with 500+ character parameter values"
}

function test_edge_case_special_characters_in_params() {
  log_test_step "Testing validation with special characters in parameter values"

  # Test with paths, spaces in quotes would be separate args, so test path-like strings
  __logic_validate_event_params "backup.created" "test-inst_123" "/path/to/source.tar.gz" "v1.2.3-beta"
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
  log_test_step "Testing EVENT_CONFIGS count matches expected 68 events"

  local config_count="${#EVENT_CONFIGS[@]}"

  assert_equals "$config_count" "68" \
    "EVENT_CONFIGS should contain exactly 68 entries (found: $config_count)"
}

# Conformance guard: every event a call site actually emits must be registered
# in EVENT_CONFIGS. Emitting an unregistered name fails validation silently and
# never reaches any transport, which is as close to compile time as the engine's
# shell gets. Comment lines are excluded so the dispatcher's commented-out
# config-set TODO does not false-positive; a call site that builds its name from
# a variable carries no literal to check and is not seen here.
function test_all_emit_call_sites_are_registered() {
  log_test_step "Testing every __emit_event call site names a declared event"

  local unregistered=()
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ -z "${EVENT_CONFIGS[$name]}" ]]; then
      unregistered+=("$name")
    fi
  done < <(grep -rhE "__emit_event \"?[a-z][a-z._]+" \
    "$KGSM_ROOT/commands" "$KGSM_ROOT/core" 2> /dev/null \
    | grep -vE "^[[:space:]]*#" \
    | grep -vE "__emit_event \"[a-z._]*\\\$" \
    | grep -oE "__emit_event \"?[a-z][a-z._]+" \
    | sed 's/__emit_event "\?//' | sort -u)

  assert_equals "${#unregistered[@]}" "0" \
    "Every emitted event must be registered in EVENT_CONFIGS. Unregistered: ${unregistered[*]}"
}

# Every declared name is lowercase, dotted and at least two segments — the shape
# a reader keys its icon and its category filter on. A name that loses its dots
# collapses onto the root of that hierarchy and renders generic.
function test_all_event_names_are_well_formed() {
  log_test_step "Testing every declared event name is a dotted lowercase name"

  local malformed=()
  local event_type
  for event_type in "${!EVENT_CONFIGS[@]}"; do
    if [[ ! "$event_type" =~ ^[a-z0-9_]+(\.[a-z0-9_]+)+$ ]]; then
      malformed+=("$event_type")
    fi
  done

  assert_equals "${#malformed[@]}" "0" \
    "Every event name must be lowercase and dotted. Malformed: ${malformed[*]}"
}

# Severity and outcome ride on every line, so an event missing its grading emits
# a null where a reader expects a value — and a reader that has to cope with a
# missing severity is a reader holding a default of its own.
function test_all_events_are_graded() {
  log_test_step "Testing every declared event carries a severity and an outcome"

  local ungraded=()
  local event_type severity outcome
  for event_type in "${!EVENT_CONFIGS[@]}"; do
    read -r severity outcome <<< "${EVENT_GRADES[$event_type]:-}"
    case "$severity" in
      info | warn | danger) ;;
      *) ungraded+=("$event_type:severity=${severity:-none}") ;;
    esac
    case "$outcome" in
      success | failure | neutral) ;;
      *) ungraded+=("$event_type:outcome=${outcome:-none}") ;;
    esac
  done

  assert_equals "${#ungraded[@]}" "0" \
    "Every event needs a valid severity and outcome. Bad: ${ungraded[*]}"
}


# =============================================================================
# ACTOR PROVENANCE
# =============================================================================

# An actor names the principal who asked for the action. The only actor the engine
# will write is one a reader can parse back into a provider and a name; anything
# else is refused, because attributing an audit record to something unresolvable is
# worse than admitting the action was unattributed.
function test_wellformed_actors_are_accepted() {
  log_test_step "Testing 'provider:name' actors are accepted"

  assert_command_succeeds "__logic_actor_is_wellformed 'discord:heisen9386'" \
    "A discord identity should be accepted"
  assert_command_succeeds "__logic_actor_is_wellformed 'local:claude'" \
    "A local identity should be accepted"
  assert_command_succeeds "__logic_actor_is_wellformed 'system:watchdog'" \
    "An autonomous producer should be accepted"

  # The provider set is a host's configuration, not this engine's knowledge, so a
  # provider it has never heard of is still well-formed.
  assert_command_succeeds "__logic_actor_is_wellformed 'github:someone'" \
    "A provider the engine does not know should still be accepted"

  # Only the FIRST colon separates: names carry their own punctuation.
  assert_command_succeeds "__logic_actor_is_wellformed 'discord:name:with:colons'" \
    "A name containing colons should be accepted"
  assert_command_succeeds "__logic_actor_is_wellformed 'discord:Claude (agent)'" \
    "A name containing spaces should be accepted"
}

# The OS user is who owns the process, not who asked for the action. It reached the
# journal 1817 times as a bare name, and a bare name is exactly what must not pass.
function test_bare_names_are_refused_as_actors() {
  log_test_step "Testing a bare name is refused as an actor"

  assert_command_fails "__logic_actor_is_wellformed 'heisen'" \
    "An OS username should be refused"
  assert_command_fails "__logic_actor_is_wellformed 'claude'" \
    "A bare agent name should be refused"
  assert_command_fails "__logic_actor_is_wellformed 'root'" \
    "A bare privileged username should be refused"
}

function test_malformed_actors_are_refused() {
  log_test_step "Testing half-written actors are refused"

  assert_command_fails "__logic_actor_is_wellformed ''" \
    "An empty actor should be refused"
  assert_command_fails "__logic_actor_is_wellformed ':name'" \
    "An actor with no provider should be refused"
  assert_command_fails "__logic_actor_is_wellformed 'provider:'" \
    "An actor with no name should be refused"
  assert_command_fails "__logic_actor_is_wellformed 'Discord:heisen'" \
    "A provider is a lowercase token, so a capitalised one should be refused"
  assert_command_fails "__logic_actor_is_wellformed 'two words:name'" \
    "A provider containing a space should be refused"
}
