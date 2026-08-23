#!/usr/bin/env bash

# KGSM Offline Library Unit Tests
#
# Test Type: UNIT
# Target: what the engine says and refuses to do about an instance whose library
# is not mounted. An unplugged disk is a measured absence, not an uninstall: the
# instance keeps enumerating, reports its state as such, and nothing removes the
# record that is all the host still holds of it.
#
# Offline is simulated by renaming the library root out from under the registry,
# which produces exactly what an unmounted disk produces — a registered path that
# is not there, and a dangling instance symlink above it — with no privilege and
# no real filesystem involved.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="library_offline"
readonly HANDLER="$KGSM_ROOT/commands/handlers/libraries.sh"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"
readonly LIFECYCLE_MODULE="$KGSM_ROOT/commands/lifecycle.sh"
readonly DIRECTORIES_MODULE="$KGSM_ROOT/commands/directories.sh"
readonly UNINSTALL_MODULE="$KGSM_ROOT/commands/uninstall.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up offline library tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Library handler should exist"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"
  assert_file_executable "$LIFECYCLE_MODULE" "lifecycle.sh should be executable"
  assert_file_executable "$DIRECTORIES_MODULE" "directories.sh should be executable"
  assert_file_executable "$UNINSTALL_MODULE" "uninstall.sh should be executable"

  source "$HANDLER"

  assert_not_null "$EC_LIBRARY_OFFLINE" "EC_LIBRARY_OFFLINE should be defined"
  assert_function_exists "__logic_instance_symlink" \
    "__logic_instance_symlink should be exported"
  assert_function_exists "__logic_instance_library_state" \
    "__logic_instance_library_state should be exported"
}

# Every test starts from an empty registry and an empty instance tree, so no test
# can pass or fail on what another one left behind.
function setup() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  unset config_default_library
  declare -g OFFLINE_TEST_DIR="${KGSM_TEST_SANDBOX}/offline_${RANDOM}_$$"
  declare -g OFFLINE_LIB_ROOT="${OFFLINE_TEST_DIR}/disk"
  declare -g OFFLINE_LIB_AWAY="${OFFLINE_TEST_DIR}/disk.unplugged"
  declare -g OFFLINE_INSTANCE=""
  mkdir -p "$OFFLINE_TEST_DIR"
}

function teardown() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  rm -rf "${OFFLINE_TEST_DIR:?}"
}

# Registers a library at the per-test root and creates one instance in it.
# Echoes the instance name.
function _place_instance() {
  local instance_name="offline-probe-$$"

  mkdir -p "$OFFLINE_LIB_ROOT"
  __logic_library_add "$OFFLINE_LIB_ROOT" "probe-lib" > /dev/null

  mkdir -p "${OFFLINE_LIB_ROOT}/instances/factorio/${instance_name}"
  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "${OFFLINE_LIB_ROOT}/instances/factorio/${instance_name}" \
    "${KGSM_INSTANCES_DIR}/factorio/${instance_name}"

  "$INSTANCES_MODULE" create factorio --library probe-lib \
    --name "$instance_name" > /dev/null 2>&1

  declare -g OFFLINE_INSTANCE="$instance_name"
  echo "$instance_name"
}

# Echoes true while the host still holds a registry entry for an instance.
function _entry_exists() {
  if [[ -L "${KGSM_INSTANCES_DIR}/factorio/$1" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Takes the library's disk away, the way an unmount does: the registered path
# stops existing and the instance symlink above it dangles.
function _unplug() {
  mv "$OFFLINE_LIB_ROOT" "$OFFLINE_LIB_AWAY"
}

# Puts it back.
function _replug() {
  mv "$OFFLINE_LIB_AWAY" "$OFFLINE_LIB_ROOT"
}

# =============================================================================
# THE MEASUREMENT
# =============================================================================

function test_state_is_online_while_the_library_is_there() {
  log_test_step "Testing the state of an instance in a mounted library"

  local instance
  instance="$(_place_instance)"

  local state
  state="$(__logic_instance_library_state "$instance")"

  assert_equals "online" "$state" "A mounted library should report online"
}

function test_state_is_offline_once_the_library_is_gone() {
  log_test_step "Testing the state of an instance whose library was unplugged"

  local instance
  instance="$(_place_instance)"
  _unplug

  __logic_instance_library_state "$instance" > /dev/null

  assert_equals "offline" "$__instance_library_state_out" \
    "An absent library root should report offline"
  assert_equals "probe-lib" "$__instance_library_name_out" \
    "The measurement should name the library"
  assert_equals "$OFFLINE_LIB_ROOT" "$__instance_library_path_out" \
    "The measurement should carry where the library is expected"
  assert_equals "factorio" "$__instance_blueprint_out" \
    "The blueprint should be read from the registry, not from the config"
  assert_equals "${OFFLINE_LIB_ROOT}/instances/factorio/${instance}" \
    "$__instance_working_dir_out" \
    "The working directory should be read from the dangling symlink"
}

function test_state_is_unregistered_outside_every_library() {
  log_test_step "Testing an instance under no registered library"

  local instance="offline-orphan-$$"
  local elsewhere="${OFFLINE_TEST_DIR}/elsewhere/factorio/${instance}"

  mkdir -p "$elsewhere"
  mkdir -p "${KGSM_INSTANCES_DIR}/factorio"
  ln -s "$elsewhere" "${KGSM_INSTANCES_DIR}/factorio/${instance}"

  local state
  state="$(__logic_instance_library_state "$instance")"

  assert_equals "unregistered" "$state" \
    "An instance no library contains should be reported as such, never offline"
}

function test_state_reports_an_instance_that_is_not_registered() {
  log_test_step "Testing an instance name with no registry entry"

  __logic_instance_library_state "no-such-instance"

  assert_equals "$?" "$EC_NOT_FOUND" \
    "A name the registry does not hold should not resolve"
}

function test_symlink_is_found_while_it_dangles() {
  log_test_step "Testing the registry entry is locatable with the disk away"

  local instance
  instance="$(_place_instance)"
  _unplug

  local symlink
  symlink="$(__logic_instance_symlink "$instance")"

  assert_equals "${KGSM_INSTANCES_DIR}/factorio/${instance}" "$symlink" \
    "A dangling entry should still be found"
}

# =============================================================================
# ENUMERATION AND STATUS
# =============================================================================

function test_offline_instance_still_enumerates() {
  log_test_step "Testing instances list with an unplugged library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" list 2>&1)"

  assert_contains "$output" "$instance" \
    "An instance whose disk is away must not vanish from the roster"
}

function test_offline_instance_enumerates_in_json() {
  log_test_step "Testing instances list --json with an unplugged library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" --json list 2>&1)"

  assert_contains "$output" "$instance" \
    "The machine listing must carry the instance too"
}

function test_detailed_listing_reports_the_offline_state() {
  log_test_step "Testing instances list --detailed with an unplugged library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" list --detailed 2>&1)"

  assert_contains "$output" "library_state=offline" \
    "The detailed listing should state the library is offline"
  assert_contains "$output" "library=probe-lib" \
    "The detailed listing should name the library"
}

function test_detailed_json_listing_reports_the_offline_state() {
  log_test_step "Testing instances list --json --detailed with an unplugged library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output state
  output="$("$INSTANCES_MODULE" --json list --detailed 2>&1)"
  state="$(echo "$output" | jq -r --arg i "$instance" '.[$i].library_state')"

  assert_equals "offline" "$state" \
    "The machine listing should carry library_state offline"
}

function test_info_reports_the_offline_state() {
  log_test_step "Testing instances info with an unplugged library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" info "$instance" 2>&1)"
  local exit_code=$?

  assert_equals 0 "$exit_code" \
    "info about an unreachable instance is a measurement, not an error"
  assert_contains "$output" "library_state=offline" \
    "info should state the library is offline"
  assert_contains "$output" "$OFFLINE_LIB_ROOT" \
    "info should say where the library is expected"
}

function test_info_json_reports_the_offline_state() {
  log_test_step "Testing instances info --json with an unplugged library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" --json info "$instance" 2>&1)"

  assert_equals "offline" "$(echo "$output" | jq -r '.library_state')" \
    "The JSON should carry library_state offline"
  assert_equals "probe-lib" "$(echo "$output" | jq -r '.library')" \
    "The JSON should name the library"
  assert_equals "factorio" "$(echo "$output" | jq -r '.blueprint')" \
    "The JSON should carry the blueprint read from the registry"
}

function test_info_json_reports_online_for_a_reachable_library() {
  log_test_step "Testing library_state on an instance whose library is mounted"

  local instance
  instance="$(_place_instance)"

  local output
  output="$("$INSTANCES_MODULE" --json info "$instance" 2>&1)"

  assert_equals "online" "$(echo "$output" | jq -r '.library_state')" \
    "A mounted library should be reported as online on the same field"
}

function test_status_json_invents_no_reading() {
  log_test_step "Testing instances status --json with an unplugged library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" --json status "$instance" 2>&1)"

  assert_equals "offline" "$(echo "$output" | jq -r '.library_state')" \
    "Status should carry the library state"
  assert_equals "null" "$(echo "$output" | jq -r '.status')" \
    "Whether an unreadable instance is running is unknown, never false"
  assert_equals "null" "$(echo "$output" | jq -r '.version.current')" \
    "No version can be read off a disk that is away"
}

function test_status_listing_survives_an_offline_instance() {
  log_test_step "Testing instances list --status does not die on an offline instance"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" --json list --status 2>&1)"
  local exit_code=$?

  assert_equals 0 "$exit_code" "A fleet status listing should still complete"
  assert_equals "offline" \
    "$(echo "$output" | jq -r --arg i "$instance" '.[$i].library_state')" \
    "The offline instance should appear in the fleet status"
}

# =============================================================================
# REFUSALS
# =============================================================================

function test_start_refuses_and_names_the_library() {
  log_test_step "Testing start against an instance whose library is away"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$LIFECYCLE_MODULE" start "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "start should refuse with EC_LIBRARY_OFFLINE"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
  assert_contains "$output" "$OFFLINE_LIB_ROOT" \
    "The refusal should say where the library is expected"
}

function test_stop_refuses_and_names_the_library() {
  log_test_step "Testing stop against an instance whose library is away"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$LIFECYCLE_MODULE" stop "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "stop should refuse with EC_LIBRARY_OFFLINE"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
}

function test_restart_refuses_and_names_the_library() {
  log_test_step "Testing restart against an instance whose library is away"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$LIFECYCLE_MODULE" restart "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "restart should refuse with EC_LIBRARY_OFFLINE"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
}

function test_is_active_refuses_and_names_the_library() {
  log_test_step "Testing is-active against an instance whose library is away"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$LIFECYCLE_MODULE" is-active "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "is-active should refuse rather than answer inactive"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
}

function test_logs_refuses_and_names_the_library() {
  log_test_step "Testing logs against an instance whose library is away"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$LIFECYCLE_MODULE" logs "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "logs should refuse with EC_LIBRARY_OFFLINE"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
}

function test_lifecycle_status_refuses_and_names_the_library() {
  log_test_step "Testing lifecycle status against an instance whose library is away"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$LIFECYCLE_MODULE" status "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "status should refuse with EC_LIBRARY_OFFLINE"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
}

# =============================================================================
# THE RECORD SURVIVES
# =============================================================================

function test_remove_refuses_and_leaves_the_entry() {
  log_test_step "Testing instances remove against an offline library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$INSTANCES_MODULE" remove "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "remove should refuse with EC_LIBRARY_OFFLINE"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
  assert_true "$(_entry_exists "$instance")" \
    "The registry entry must survive the refusal"
}

function test_remove_force_forgets_the_instance_and_keeps_its_files() {
  log_test_step "Testing instances remove --force against an offline library"

  local instance
  instance="$(_place_instance)"
  _unplug

  "$INSTANCES_MODULE" remove "$instance" --force > /dev/null 2>&1
  local exit_code=$?

  assert_equals 0 "$exit_code" "--force should deregister the instance"
  assert_false "$(_entry_exists "$instance")" \
    "The registry entry should be gone"
  assert_file_exists \
    "${OFFLINE_LIB_AWAY}/instances/factorio/${instance}/${instance}.config.ini" \
    "The instance's own files must be left where they are"
}

function test_unlink_refuses_a_dangling_entry_of_an_offline_library() {
  log_test_step "Testing directories unlink-instance against an offline library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$DIRECTORIES_MODULE" unlink-instance factorio "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "unlink-instance should refuse to drop the entry"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
  assert_true "$(_entry_exists "$instance")" \
    "The dangling entry must survive"
}

function test_unlink_still_removes_an_entry_of_an_online_library() {
  log_test_step "Testing directories unlink-instance while the library is mounted"

  local instance
  instance="$(_place_instance)"

  "$DIRECTORIES_MODULE" unlink-instance factorio "$instance" > /dev/null 2>&1
  local exit_code=$?

  assert_equals 0 "$exit_code" "A reachable instance should still unlink"
  assert_false "$(_entry_exists "$instance")" \
    "The entry should be gone"
}

function test_uninstall_refuses_and_leaves_everything() {
  log_test_step "Testing uninstall against an offline library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$UNINSTALL_MODULE" "$instance" 2>&1)"
  local exit_code=$?

  assert_equals "$EC_LIBRARY_OFFLINE" "$exit_code" \
    "uninstall should refuse with EC_LIBRARY_OFFLINE"
  assert_contains "$output" "probe-lib" "The refusal should name the library"
  assert_true "$(_entry_exists "$instance")" \
    "The registry entry must survive the refusal"
  assert_file_exists \
    "${OFFLINE_LIB_AWAY}/instances/factorio/${instance}/${instance}.config.ini" \
    "The instance's files must survive the refusal"
}

function test_uninstall_force_deregisters_only() {
  log_test_step "Testing uninstall --force against an offline library"

  local instance
  instance="$(_place_instance)"
  _unplug

  local output
  output="$("$UNINSTALL_MODULE" "$instance" --force 2>&1)"
  local exit_code=$?

  assert_equals 0 "$exit_code" "--force should deregister the instance"
  assert_contains "$output" "${OFFLINE_LIB_ROOT}/instances/factorio/${instance}" \
    "It should say where the files it did not touch are"
  assert_false "$(_entry_exists "$instance")" \
    "The registry entry should be gone"
  assert_file_exists \
    "${OFFLINE_LIB_AWAY}/instances/factorio/${instance}/${instance}.config.ini" \
    "Not one file of the instance should have been removed"
}

# =============================================================================
# COMING BACK
# =============================================================================

function test_remounting_restores_everything_with_no_commands() {
  log_test_step "Testing the library coming back"

  local instance
  instance="$(_place_instance)"
  _unplug

  assert_equals "offline" "$(__logic_instance_library_state "$instance")" \
    "The instance should be offline while the disk is away"

  _replug

  assert_equals "online" "$(__logic_instance_library_state "$instance")" \
    "Putting the disk back should be the whole of the recovery"

  local output
  output="$("$INSTANCES_MODULE" --json info "$instance" 2>&1)"

  assert_equals "online" "$(echo "$output" | jq -r '.library_state')" \
    "info should report the library online again"
  assert_equals "$instance" "$(echo "$output" | jq -r '.name')" \
    "The instance's own config should be readable again"
  assert_equals "probe-lib" "$(echo "$output" | jq -r '.library')" \
    "It should still resolve to the same library"
}

function test_remounting_makes_the_refusals_stop() {
  log_test_step "Testing a refused verb is accepted again once the disk is back"

  local instance
  instance="$(_place_instance)"
  _unplug

  "$INSTANCES_MODULE" remove "$instance" > /dev/null 2>&1
  assert_equals "$EC_LIBRARY_OFFLINE" "$?" "remove should refuse while offline"

  _replug

  "$INSTANCES_MODULE" remove "$instance" > /dev/null 2>&1
  assert_equals 0 "$?" "remove should be accepted once the disk is back"
}
