#!/usr/bin/env bash

# KGSM Update-Available State Unit Tests
#
# Test Type: UNIT
# Target: the update-check state beside an instance, and the event it drives
#
# "An update is available" is derivable at any moment: installed != latest.
# "An update BECAME available" is a transition, and a transition needs a
# previous value. That value is a file beside the instance, written only by
# `check-update --emit` — which is what makes a repeated sweep silent and a
# check run by hand harmless.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="update_available_state"
readonly MODULE="$KGSM_ROOT/commands/instances.sh"
readonly EVENTS_HANDLER="$KGSM_ROOT/commands/handlers/events.sh"
readonly INSTANCES_HANDLER="$KGSM_ROOT/commands/handlers/instances.sh"

# =============================================================================
# TEST SETUP FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up update-available state tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "instances module should exist"
  assert_file_exists "$EVENTS_HANDLER" "events handler should exist"

  # shellcheck disable=SC1090
  source "$EVENTS_HANDLER"

  log_test_step "Environment validated"
}

function setup() {
  STATE_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kgsm-update-state-XXXXXX")"
  export STATE_TEST_DIR
}

function teardown() {
  [[ -n "${STATE_TEST_DIR:-}" && -d "$STATE_TEST_DIR" ]] &&
    rm -rf "$STATE_TEST_DIR"
  return 0
}

# Runs a snippet with a version module sourced against a scratch instance.
# $1 = runtime (native|container), $2 = snippet.
function run_in_version_module() {
  local runtime="$1"
  local snippet="$2"

  mkdir -p "$STATE_TEST_DIR/work"

  # The state accessors are taken from 01-config.sh — the structural module,
  # never overridden — which is where they have to live: an override module
  # replaces its default wholesale, so accessors in the overridable range would
  # go missing for every game that overrides it. Pulled out by function name
  # rather than by line range, because the rest of that module sources a real
  # instance config and cannot run here.
  local state_functions
  state_functions=$(awk \
    '/^function _(get_stored_latest_version|get_stored_latest_checked_at|save_latest_version)\(\)/,/^}$/' \
    "$KGSM_ROOT/templates/manage.${runtime}.d/01-config.sh")

  bash <<EOF 2>/dev/null
readonly EC_SUCCESS=0
readonly EC_ERROR=1
readonly EC_INVALID_ARG=8
function __print_info()    { :; }
function __print_error()   { :; }
function __print_warning() { :; }
function __print_success() { :; }
instance_working_dir="$STATE_TEST_DIR/work"
instance_compose_file="$STATE_TEST_DIR/work/docker-compose.yml"
instance_version_file="$STATE_TEST_DIR/work/.test.version"
instance_latest_version_file="$STATE_TEST_DIR/work/.test.latest"
$state_functions
$snippet
EOF
}

# =============================================================================
# THE EVENT IS DECLARED AND CARRIES BOTH VERSIONS
# =============================================================================

function test_update_available_event_type_exists() {
  log_test_step "Testing that instance_update_available is a declared event type"

  assert_not_null "$EVENT_INSTANCE_UPDATE_AVAILABLE" \
    "EVENT_INSTANCE_UPDATE_AVAILABLE should be declared"
  assert_equals "instance_update_available" "$EVENT_INSTANCE_UPDATE_AVAILABLE" \
    "The event type should be instance_update_available"
}

function test_update_available_event_declares_both_versions() {
  log_test_step "Testing the event's parameter spec"

  local spec="${EVENT_CONFIGS[$EVENT_INSTANCE_UPDATE_AVAILABLE]}"

  # Both versions, because "an update is available" without saying from what to
  # what is not something a reader can act on or audit.
  assert_contains "$spec" "instance" "The spec should carry the instance"
  assert_contains "$spec" "current_version" "The spec should carry the installed version"
  assert_contains "$spec" "latest_version" "The spec should carry the upstream version"
}

function test_update_available_event_validates() {
  log_test_step "Testing that the event type passes validation"

  __logic_validate_event_type "$EVENT_INSTANCE_UPDATE_AVAILABLE"
  assert_equals "0" "$?" "instance_update_available should be a valid event type"
}

# =============================================================================
# THE STATE FILE: WHAT WAS FOUND, AND WHEN IT WAS FETCHED
# =============================================================================

function test_no_state_reads_as_nothing_on_both_runtimes() {
  log_test_step "Testing that an instance with no recorded check reads as empty"

  local runtime
  for runtime in native container; do
    local version checked_at
    version=$(run_in_version_module "$runtime" '_get_stored_latest_version')
    checked_at=$(run_in_version_module "$runtime" '_get_stored_latest_checked_at')

    assert_null "$version" \
      "$runtime: an instance that has never been checked should report no version"
    assert_null "$checked_at" \
      "$runtime: and no check time — a version with no time would read as fresh"
  done
}

function test_saved_state_round_trips_with_a_timestamp() {
  log_test_step "Testing that a recorded check reads back with its fetch time"

  local runtime
  for runtime in native container; do
    local version checked_at
    version=$(run_in_version_module "$runtime" \
      '_save_latest_version "16302742" && _get_stored_latest_version')
    checked_at=$(run_in_version_module "$runtime" \
      '_get_stored_latest_checked_at')

    assert_equals "16302742" "$version" \
      "$runtime: the recorded upstream version should read back verbatim"
    assert_matches "$checked_at" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
      "$runtime: the fetch time should be recorded as ISO-8601 UTC"
  done
}

function test_saving_an_empty_version_is_refused() {
  log_test_step "Testing that an empty upstream version is not recorded"

  local runtime
  for runtime in native container; do
    local exit_code
    run_in_version_module "$runtime" '_save_latest_version ""'
    exit_code=$?

    assert_not_equals "0" "$exit_code" \
      "$runtime: recording an empty version would make the next check re-announce"
  done
}

function test_a_second_save_replaces_the_first() {
  log_test_step "Testing that the state holds the latest check, not a history"

  local version
  version=$(run_in_version_module native \
    '_save_latest_version "1" && _save_latest_version "2" && _get_stored_latest_version')

  assert_equals "2" "$version" "The state should hold only the most recent check"
}

# =============================================================================
# THE COMMAND SURFACE
# =============================================================================

function test_check_update_advertises_emit() {
  log_test_step "Testing that check-update documents --emit"

  local output
  output=$("$MODULE" check-update --help 2>&1 || true)

  assert_contains "$output" "--emit" "check-update --help should document --emit"
  assert_contains "$output" "instance_update_available" \
    "The help should name the event --emit produces"
}

function test_management_files_advertise_the_state_accessors() {
  log_test_step "Testing that the management templates document the state flags"

  local runtime
  for runtime in native container; do
    local help_module="$KGSM_ROOT/templates/manage.${runtime}.d/02-help.sh"
    assert_file_exists "$help_module" "$runtime help module should exist"

    assert_file_contains "$help_module" "stored-latest" \
      "$runtime: --help should document --stored-latest"
  done
}

function test_state_accessors_are_not_in_the_overridable_range() {
  log_test_step "Testing that the state accessors sit in a module no game override replaces"

  local runtime
  for runtime in native container; do
    local structural="$KGSM_ROOT/templates/manage.${runtime}.d/01-config.sh"
    local overridable="$KGSM_ROOT/templates/manage.${runtime}.d/05-version.sh"

    assert_file_contains "$structural" "_save_latest_version" \
      "$runtime: the state accessors belong in 01-config.sh, which is structural"

    # An override module replaces its default wholesale, so an accessor defined
    # in the overridable range goes missing for every game that overrides it —
    # and four games override 05-version.sh today.
    assert_command_fails "grep -q '_save_latest_version' '$overridable'" \
      "$runtime: 05-version.sh is overridable, so the accessors must not live there"
  done
}

function test_no_game_override_needs_to_carry_the_state_accessors() {
  log_test_step "Testing that existing game overrides are unaffected"

  local override
  for override in "$KGSM_ROOT"/overrides/*/05-version.sh; do
    [[ -f "$override" ]] || continue

    # If this ever fails, the accessors drifted back into the overridable range
    # and every one of these games silently lost them.
    assert_command_fails "grep -q '_save_latest_version' '$override'" \
      "$(basename "$(dirname "$override")") should not have to reproduce the state accessors"
  done
}

function test_the_state_path_is_derived_not_required() {
  log_test_step "Testing that an instance config without the key still resolves the state path"

  local runtime
  for runtime in native container; do
    local config_module="$KGSM_ROOT/templates/manage.${runtime}.d/01-config.sh"

    # Derived with :=, so a management file generated for an instance whose
    # config predates the key still knows where the state lives — no migration.
    assert_file_contains "$config_module" \
      ': "${instance_latest_version_file:=' \
      "$runtime: the state path should default when the instance config does not declare it"
  done
}
