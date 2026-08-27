#!/usr/bin/env bash

# KGSM Library Command Unit Tests
#
# Test Type: UNIT
# Target: commands/libraries.sh — the CLI surface over the library registry:
# argument parsing, the messages a refusal carries, and the two output shapes of
# `list`.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="libraries_commands"
readonly MODULE="$KGSM_ROOT/commands/libraries.sh"
readonly HANDLER="$KGSM_ROOT/commands/handlers/libraries.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

# The newest segment in a journal directory. Segment names are dates, so ordinal
# order is chronological and the newest file is the one an event just landed
# in — true whether or not the UTC day turned over mid-command, which a computed
# name would get wrong.
#
# Args: $1 = journal directory
function _newest_journal_segment() {
  find "$1" -maxdepth 1 -type f -name '*.ndjson' 2> /dev/null | sort | tail -1
}

function setup_file() {
  log_test_step "Setting up library command tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "Libraries module should exist"
  assert_file_executable "$MODULE" "Libraries module should be executable"

  # Sourced for the registry-path helper the per-test reset uses.
  source "$HANDLER"

  log_test_step "Library command test environment validated"
}

function setup() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  declare -g LIBRARY_TEST_DIR="${KGSM_TEST_SANDBOX}/libcmd_${RANDOM}_$$"
  mkdir -p "$LIBRARY_TEST_DIR"
}

function teardown() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  rm -rf "${LIBRARY_TEST_DIR:?}"
}

# Places a fake instance in a library: the registry symlink KGSM enumerates,
# pointing at a working directory inside the library root.
# Args: $1 = library root, $2 = blueprint, $3 = instance
function _place_instance() {
  local working_dir="$1/$2/$3"
  mkdir -p "$working_dir"
  mkdir -p "${KGSM_INSTANCES_DIR}/$2"
  ln -s "$working_dir" "${KGSM_INSTANCES_DIR}/$2/$3"
}

# =============================================================================
# USAGE
# =============================================================================

function test_no_command_shows_usage_and_fails() {
  log_test_step "Testing 'libraries' with no command"

  local output
  output="$("$MODULE" 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_ERROR" "Should fail without a command"
  assert_contains "$output" "Usage:" "Should print usage"
}

function test_help_lists_every_verb() {
  log_test_step "Testing 'libraries --help'"

  local output
  output="$("$MODULE" --help 2>&1)"

  assert_equals "$?" "0" "Help should succeed"
  assert_contains "$output" "add" "Should document add"
  assert_contains "$output" "remove" "Should document remove"
  assert_contains "$output" "list" "Should document list"
  assert_contains "$output" "rename" "Should document rename"
}

function test_unknown_command_is_rejected() {
  log_test_step "Testing 'libraries bogus'"

  local output
  output="$("$MODULE" bogus 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
  assert_contains "$output" "Unknown command" "Should say what went wrong"
}

# =============================================================================
# ADD
# =============================================================================

function test_add_without_a_path_is_rejected() {
  log_test_step "Testing 'libraries add' with no path"

  local output
  output="$("$MODULE" add 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_MISSING_ARG" "Should return EC_MISSING_ARG"
  assert_contains "$output" "<path>" "Should name the missing argument"
}

function test_add_registers_a_library() {
  log_test_step "Testing 'libraries add <path> --name <name>'"

  local output
  output="$("$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "0" "Should succeed"
  assert_contains "$output" "ssd" "Should name the library"
  assert_file_exists "${LIBRARY_TEST_DIR}/ssd/.kgsm-library" "Marker should be written"
  assert_file_contains "$(__library_registry_file)" "[ssd]" "Registry should carry the section"
}

function test_add_a_second_time_names_the_library_already_there() {
  log_test_step "Testing 'libraries add' on a registered path"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1

  local output
  output="$("$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name other 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_LIBRARY_EXISTS" "Should return EC_LIBRARY_EXISTS"
  assert_contains "$output" "already registered as library 'ssd'" \
    "Should name the library already at that path"
}

function test_add_with_a_taken_name_asks_for_another() {
  log_test_step "Testing 'libraries add' with a name in use"

  "$MODULE" add "${LIBRARY_TEST_DIR}/one" --name shared > /dev/null 2>&1

  local output
  output="$("$MODULE" add "${LIBRARY_TEST_DIR}/two" --name shared 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_LIBRARY_EXISTS" "Should return EC_LIBRARY_EXISTS"
  assert_contains "$output" "--name" "Should point at the remedy"
}

function test_add_with_an_invalid_name_is_rejected() {
  log_test_step "Testing 'libraries add --name' with an invalid name"

  local output
  output="$("$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name "Not A Name" 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
  assert_contains "$output" "Invalid library name" "Should say the name is invalid"
}

function test_add_emits_library_added() {
  log_test_step "Testing that 'libraries add' records the event"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  assert_equals "$?" "0" "Add should succeed"

  local journal_dir
  journal_dir="${config_event_journal_dir:-}"
  assert_not_null "$journal_dir" "The sandbox should redirect the journal"

  local segment
  segment="$(_newest_journal_segment "$journal_dir")"
  assert_not_null "$segment" "The journal segment should exist"
  assert_file_contains "$segment" "library.added" "The event type should be recorded"
  assert_file_contains "$segment" "LibraryName" "The payload should be library-scoped"
}

# =============================================================================
# LIST
# =============================================================================

function test_list_with_no_libraries_says_so() {
  log_test_step "Testing 'libraries list' with an empty registry"

  local output
  output="$("$MODULE" list 2>&1)"

  assert_equals "$?" "0" "Should succeed"
  assert_contains "$output" "No libraries registered" "Should say the registry is empty"
}

function test_list_reports_state_capacity_and_use() {
  log_test_step "Testing 'libraries list'"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"

  local output
  output="$("$MODULE" list 2>&1)"

  assert_equals "$?" "0" "Should succeed"
  assert_contains "$output" "NAME" "Should print a header"
  assert_contains "$output" "ssd" "Should list the library"
  assert_contains "$output" "online" "Should report the measured state"
  assert_contains "$output" "${LIBRARY_TEST_DIR}/ssd" "Should print the root"
}

function test_list_reports_an_offline_library_without_inventing_figures() {
  log_test_step "Testing 'libraries list' with an unreachable root"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  mv "${LIBRARY_TEST_DIR}/ssd" "${LIBRARY_TEST_DIR}/ssd.away"

  local output
  output="$("$MODULE" list 2>&1)"

  assert_equals "$?" "0" "Offline is a state, never an error"
  assert_contains "$output" "offline" "Should report the library as offline"
}

function test_list_json_shape() {
  log_test_step "Testing 'libraries list --json'"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"

  local output
  output="$("$MODULE" list --json 2>&1)"
  assert_equals "$?" "0" "Should succeed"

  assert_command_succeeds "echo '$output' | jq -e '. | type == \"array\"'" \
    "Should emit a JSON array"
  assert_equals "$(echo "$output" | jq -r '.[0].name')" "ssd" "Should carry the name"
  assert_equals "$(echo "$output" | jq -r '.[0].path')" "${LIBRARY_TEST_DIR}/ssd" \
    "Should carry the root"
  assert_equals "$(echo "$output" | jq -r '.[0].state')" "online" "Should carry the state"
  assert_equals "$(echo "$output" | jq -r '.[0].instance_count')" "1" \
    "Should carry the instance count"
  assert_command_succeeds "echo '$output' | jq -e '.[0].free_bytes | type == \"number\"'" \
    "Free space should be a number for an online library"
  assert_command_succeeds "echo '$output' | jq -e '.[0].total_bytes | type == \"number\"'" \
    "Total space should be a number for an online library"
}

function test_list_json_reports_null_capacity_when_offline() {
  log_test_step "Testing 'libraries list --json' with an unreachable root"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  mv "${LIBRARY_TEST_DIR}/ssd" "${LIBRARY_TEST_DIR}/ssd.away"

  local output
  output="$("$MODULE" list --json 2>&1)"
  assert_equals "$?" "0" "Should succeed"

  assert_equals "$(echo "$output" | jq -r '.[0].state')" "offline" "Should report offline"
  assert_command_succeeds "echo '$output' | jq -e '.[0].free_bytes == null'" \
    "An unmeasured figure is null, never a number nothing measured"
  assert_command_succeeds "echo '$output' | jq -e '.[0].total_bytes == null'" \
    "An unmeasured figure is null, never a number nothing measured"
}

# =============================================================================
# RENAME
# =============================================================================

function test_rename_needs_both_names() {
  log_test_step "Testing 'libraries rename' with one argument"

  local output
  output="$("$MODULE" rename onlyone 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_MISSING_ARG" "Should return EC_MISSING_ARG"
  assert_contains "$output" "<new>" "Should name the missing argument"
}

function test_rename_renames_a_library() {
  log_test_step "Testing 'libraries rename <old> <new>'"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1

  local output
  output="$("$MODULE" rename ssd fast 2>&1)"
  assert_equals "$?" "0" "Should succeed"
  assert_contains "$output" "fast" "Should report the new name"

  assert_file_contains "$(__library_registry_file)" "[fast]" "Registry should carry the new name"
  assert_file_contains "${LIBRARY_TEST_DIR}/ssd/.kgsm-library" "name=fast" \
    "Marker should carry the new name"
}

function test_rename_of_an_unregistered_library_is_reported() {
  log_test_step "Testing 'libraries rename' with an unknown name"

  local output
  output="$("$MODULE" rename nope other 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_LIBRARY_NOT_FOUND" "Should return EC_LIBRARY_NOT_FOUND"
  assert_contains "$output" "not registered" "Should say the library is unknown"
}

# =============================================================================
# REMOVE
# =============================================================================

function test_remove_deregisters_a_library() {
  log_test_step "Testing 'libraries remove <name>'"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1

  local output
  output="$("$MODULE" remove ssd 2>&1)"
  assert_equals "$?" "0" "Should succeed"
  assert_contains "$output" "ssd" "Should name the library"

  assert_file_not_exists "${LIBRARY_TEST_DIR}/ssd/.kgsm-library" "Marker should be removed"
  assert_dir_exists "${LIBRARY_TEST_DIR}/ssd" "The root should be left in place"
}

function test_remove_refuses_while_instances_resolve_to_it() {
  log_test_step "Testing 'libraries remove' with instances in the library"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"

  local output
  output="$("$MODULE" remove ssd 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_LIBRARY_IN_USE" "Should return EC_LIBRARY_IN_USE"
  assert_contains "$output" "factorio-01" "Should name the blocking instance"
  assert_contains "$output" "--force" "Should point at the remedy"
  assert_file_contains "$(__library_registry_file)" "[ssd]" "The library should still be registered"
}

function test_remove_force_deregisters_and_leaves_the_files() {
  log_test_step "Testing 'libraries remove --force'"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"

  local output
  output="$("$MODULE" remove ssd --force 2>&1)"
  assert_equals "$?" "0" "Should succeed"
  assert_contains "$output" "factorio-01" "Should report what was left behind"

  assert_dir_exists "${LIBRARY_TEST_DIR}/ssd/factorio/factorio-01" \
    "Instance files should be untouched"
}

function test_remove_emits_library_removed() {
  log_test_step "Testing that 'libraries remove' records the event"

  "$MODULE" add "${LIBRARY_TEST_DIR}/ssd" --name ssd > /dev/null 2>&1
  "$MODULE" remove ssd > /dev/null 2>&1
  assert_equals "$?" "0" "Remove should succeed"

  local segment
  segment="$(_newest_journal_segment "$config_event_journal_dir")"
  assert_not_null "$segment" "The journal segment should exist"
  assert_file_contains "$segment" "library.removed" "The event type should be recorded"
}

function test_remove_of_an_unregistered_library_is_reported() {
  log_test_step "Testing 'libraries remove' with an unknown name"

  local output
  output="$("$MODULE" remove nope 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_LIBRARY_NOT_FOUND" "Should return EC_LIBRARY_NOT_FOUND"
  assert_contains "$output" "not registered" "Should say the library is unknown"
}
