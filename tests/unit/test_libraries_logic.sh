#!/usr/bin/env bash

# KGSM Library Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/libraries.sh — the registry, the marker, and the
# queries and verbs built on the pair of them.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="libraries_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/libraries.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up library logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Library handler should exist"

  source "$HANDLER"

  assert_not_null "$EC_LIBRARY_NOT_FOUND" "EC_LIBRARY_NOT_FOUND should be defined"
  assert_not_null "$EC_LIBRARY_EXISTS" "EC_LIBRARY_EXISTS should be defined"
  assert_not_null "$EC_LIBRARY_IN_USE" "EC_LIBRARY_IN_USE should be defined"
  assert_not_null "$EC_SUCCESS_LIBRARY_ADDED" "EC_SUCCESS_LIBRARY_ADDED should be defined"
  assert_not_null "$EC_SUCCESS_LIBRARY_REMOVED" "EC_SUCCESS_LIBRARY_REMOVED should be defined"

  assert_function_exists "__logic_library_add" "__logic_library_add should be exported"
  assert_function_exists "__logic_library_remove" "__logic_library_remove should be exported"
  assert_function_exists "__logic_library_rename" "__logic_library_rename should be exported"
  assert_function_exists "__logic_library_is_online" "__logic_library_is_online should be exported"
  assert_function_exists "__logic_library_instances" "__logic_library_instances should be exported"

  assert_not_null "$KGSM_LOGIC_LIBRARIES_LOADED" "Module should be loaded"

  log_test_step "Library logic test environment validated"
}

# Every test starts from an empty registry and an empty instance tree, so no
# test can pass or fail on what a previous one left behind.
function setup() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  declare -g LIBRARY_TEST_DIR="${KGSM_TEST_SANDBOX}/libraries_${RANDOM}_$$"
  mkdir -p "$LIBRARY_TEST_DIR"
}

function teardown() {
  rm -f "$(__library_registry_file)"
  rm -rf "${KGSM_INSTANCES_DIR:?}"/*
  rm -rf "${LIBRARY_TEST_DIR:?}"
}

# Registers a library root under the per-test scratch directory.
# Args: $1 = root basename, $2 = library name (optional)
function _add_library() {
  local root="${LIBRARY_TEST_DIR}/$1"
  mkdir -p "$root"
  __logic_library_add "$root" "${2:-}"
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
# NAME VALIDATION
# =============================================================================

function test_validate_library_name_accepts_lowercase_digits_and_dashes() {
  log_test_step "Testing __logic_validate_library_name with valid names"

  local name
  for name in ssd archive-2 a 0 fast-nvme-01; do
    __logic_validate_library_name "$name"
    assert_equals "$?" "$EC_SUCCESS" "'$name' should be a valid library name"
  done
}

function test_validate_library_name_rejects_the_rest() {
  log_test_step "Testing __logic_validate_library_name with invalid names"

  local name
  for name in "" "SSD" "with space" "under_score" "-leading" "dot.name" "/mnt/ssd"; do
    __logic_validate_library_name "$name"
    assert_equals "$?" "$EC_INVALID_ARG" "'$name' should be rejected"
  done
}

# =============================================================================
# REGISTRY CRUD
# =============================================================================

function test_add_registers_a_library_and_writes_its_marker() {
  log_test_step "Testing __logic_library_add on an empty directory"

  _add_library "ssd" "ssd"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_LIBRARY_ADDED" \
    "Should return EC_SUCCESS_LIBRARY_ADDED"
  assert_equals "$__library_add_name_out" "ssd" "Should report the registered name"
  assert_equals "$__library_add_path_out" "${LIBRARY_TEST_DIR}/ssd" \
    "Should report the canonical root"
  assert_equals "$__library_add_adopted_out" "false" \
    "A directory with no marker is registered, not adopted"

  assert_file_exists "$(__library_registry_file)" "Registry should be created by the first add"
  assert_file_exists "${LIBRARY_TEST_DIR}/ssd/.kgsm-library" "Marker should be written"

  local marker_id registry_id
  marker_id="$(__library_marker_read "${LIBRARY_TEST_DIR}/ssd" id)"
  registry_id="$(__logic_library_id ssd)"
  assert_equals "$marker_id" "$registry_id" "Marker and registry should agree on the id"
  assert_equals "${#registry_id}" "16" "The id should be 16 hex characters"

  local marker_name
  marker_name="$(__library_marker_read "${LIBRARY_TEST_DIR}/ssd" name)"
  assert_equals "$marker_name" "ssd" "Marker should carry the name"
}

function test_add_creates_a_root_that_does_not_exist() {
  log_test_step "Testing __logic_library_add creates a missing root"

  local root="${LIBRARY_TEST_DIR}/not-yet"
  __logic_library_add "$root" "created"

  assert_equals "$?" "$EC_SUCCESS_LIBRARY_ADDED" "Should register"
  assert_dir_exists "$root" "Root should be created"
}

function test_add_defaults_the_name_to_the_directory_name() {
  log_test_step "Testing __logic_library_add derives a name from the basename"

  _add_library "archive"

  assert_equals "$?" "$EC_SUCCESS_LIBRARY_ADDED" "Should register"
  assert_equals "$__library_add_name_out" "archive" "Name should come from the directory"
}

function test_add_rejects_a_directory_name_that_is_not_a_valid_library_name() {
  log_test_step "Testing __logic_library_add on a directory whose name cannot be used"

  _add_library "Not_A_Name"

  assert_equals "$?" "$EC_INVALID_ARG" \
    "Should return EC_INVALID_ARG so the caller asks for --name"
  assert_equals "$(__logic_library_list)" "" "Nothing should be registered"
}

function test_add_refuses_a_path_that_is_already_registered() {
  log_test_step "Testing __logic_library_add on an already registered path"

  _add_library "ssd" "ssd"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_ADDED" "First add should succeed"

  __logic_library_add "${LIBRARY_TEST_DIR}/ssd" "other"
  assert_equals "$?" "$EC_LIBRARY_EXISTS" "Second add should be refused"
  assert_equals "$__library_add_conflict_out" "path" "Conflict should be reported as the path"
  assert_equals "$__library_add_name_out" "ssd" "Should name the library already there"
}

function test_add_refuses_a_name_that_is_already_taken() {
  log_test_step "Testing __logic_library_add with a name another library holds"

  _add_library "one" "shared"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_ADDED" "First add should succeed"

  _add_library "two" "shared"
  assert_equals "$?" "$EC_LIBRARY_EXISTS" "Second add should be refused"
  assert_equals "$__library_add_conflict_out" "name" "Conflict should be reported as the name"
}

function test_add_refuses_an_unwritable_root() {
  log_test_step "Testing __logic_library_add on an unwritable directory"

  local root="${LIBRARY_TEST_DIR}/readonly"
  mkdir -p "$root"
  chmod 500 "$root"

  __logic_library_add "$root" "readonly"
  local exit_code=$?

  chmod 755 "$root"

  assert_equals "$exit_code" "$EC_PERMISSION" "Should return EC_PERMISSION"
  assert_equals "$(__logic_library_list)" "" "Nothing should be registered"
}

function test_list_reports_every_registered_library() {
  log_test_step "Testing __logic_library_list with several libraries"

  _add_library "one" "one"
  _add_library "two" "two"
  _add_library "three" "three"

  local names
  names="$(__logic_library_list)"

  assert_contains "$names" "one" "Should list 'one'"
  assert_contains "$names" "two" "Should list 'two'"
  assert_contains "$names" "three" "Should list 'three'"
  assert_equals "$(echo "$names" | grep -c .)" "3" "Should list exactly three"
}

function test_exists_and_path_answer_for_a_registered_library() {
  log_test_step "Testing __logic_library_exists and __logic_library_path"

  _add_library "ssd" "ssd"

  __logic_library_exists "ssd"
  assert_equals "$?" "$EC_SUCCESS" "A registered library should exist"

  __logic_library_exists "nope"
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" "An unregistered name should not"

  assert_equals "$(__logic_library_path ssd)" "${LIBRARY_TEST_DIR}/ssd" \
    "Should report the registered root"

  __logic_library_path nope > /dev/null 2>&1
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" "An unregistered name should have no path"
}

function test_remove_deregisters_and_takes_the_marker_with_it() {
  log_test_step "Testing __logic_library_remove on an empty library"

  _add_library "ssd" "ssd"

  __logic_library_remove "ssd"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS_LIBRARY_REMOVED" \
    "Should return EC_SUCCESS_LIBRARY_REMOVED"
  assert_equals "$__library_remove_path_out" "${LIBRARY_TEST_DIR}/ssd" \
    "Should report the deregistered root"

  __logic_library_exists "ssd"
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" "Library should be gone from the registry"
  assert_file_not_exists "${LIBRARY_TEST_DIR}/ssd/.kgsm-library" "Marker should be removed"
  assert_dir_exists "${LIBRARY_TEST_DIR}/ssd" "The root itself should be left alone"
}

function test_remove_leaves_the_other_libraries_intact() {
  log_test_step "Testing __logic_library_remove removes exactly one section"

  _add_library "one" "one"
  _add_library "two" "two"
  _add_library "three" "three"

  __logic_library_remove "two"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_REMOVED" "Should remove"

  local names
  names="$(__logic_library_list)"
  assert_contains "$names" "one" "'one' should survive"
  assert_contains "$names" "three" "'three' should survive"
  assert_not_contains "$names" "two" "'two' should be gone"
  assert_equals "$(echo "$names" | grep -c .)" "2" "Two libraries should remain"

  assert_equals "$(__logic_library_path one)" "${LIBRARY_TEST_DIR}/one" \
    "'one' should still resolve to its root"
  assert_equals "$(__logic_library_path three)" "${LIBRARY_TEST_DIR}/three" \
    "'three' should still resolve to its root"
}

function test_remove_reports_an_unregistered_library() {
  log_test_step "Testing __logic_library_remove with an unknown name"

  __logic_library_remove "nope"
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" "Should return EC_LIBRARY_NOT_FOUND"
}

function test_rename_updates_the_registry_and_the_marker() {
  log_test_step "Testing __logic_library_rename on an online library"

  _add_library "ssd" "ssd"
  local id
  id="$(__logic_library_id ssd)"

  __logic_library_rename "ssd" "fast"
  assert_equals "$?" "$EC_SUCCESS" "Rename should succeed"
  assert_equals "$__library_rename_marker_out" "true" "The marker should be rewritten"

  __logic_library_exists "ssd"
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" "The old name should be gone"
  __logic_library_exists "fast"
  assert_equals "$?" "$EC_SUCCESS" "The new name should be registered"

  assert_equals "$(__logic_library_id fast)" "$id" "The id should be unchanged"
  assert_equals "$(__logic_library_path fast)" "${LIBRARY_TEST_DIR}/ssd" \
    "The root should be unchanged"
  assert_equals "$(__library_marker_read "${LIBRARY_TEST_DIR}/ssd" name)" "fast" \
    "The marker should carry the new name"
}

function test_rename_refuses_a_name_that_is_taken() {
  log_test_step "Testing __logic_library_rename onto an existing name"

  _add_library "one" "one"
  _add_library "two" "two"

  __logic_library_rename "one" "two"
  assert_equals "$?" "$EC_LIBRARY_EXISTS" "Should return EC_LIBRARY_EXISTS"
  __logic_library_exists "one"
  assert_equals "$?" "$EC_SUCCESS" "The library should keep its name"
}

function test_rename_rejects_an_invalid_new_name() {
  log_test_step "Testing __logic_library_rename with an invalid name"

  _add_library "ssd" "ssd"

  __logic_library_rename "ssd" "Not A Name"
  assert_equals "$?" "$EC_INVALID_ARG" "Should return EC_INVALID_ARG"
  __logic_library_exists "ssd"
  assert_equals "$?" "$EC_SUCCESS" "The library should keep its name"
}

# =============================================================================
# MARKER ADOPTION
# =============================================================================

function test_add_adopts_a_root_that_already_carries_a_marker() {
  log_test_step "Testing __logic_library_add adopts an existing marker"

  _add_library "ssd" "ssd"
  local original_id
  original_id="$(__logic_library_id ssd)"

  # Deregistering with the root unreachable is what leaves a marker behind — the
  # same state a disk arrives in from another host.
  local root="${LIBRARY_TEST_DIR}/ssd"
  mv "$root" "${root}.away"
  __logic_library_remove "ssd"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_REMOVED" "Removal should succeed"
  mv "${root}.away" "$root"
  assert_file_exists "${root}/.kgsm-library" "The marker should have survived"

  __logic_library_add "$root"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_ADDED" "Re-adding should succeed"
  assert_equals "$__library_add_adopted_out" "true" "Should report an adoption"
  assert_equals "$__library_add_name_out" "ssd" "Should take the name from the marker"
  assert_equals "$(__logic_library_id ssd)" "$original_id" \
    "Should keep the id the disk carries"
}

function test_add_adopts_under_a_different_name_when_asked() {
  log_test_step "Testing __logic_library_add adopts with an explicit name"

  _add_library "ssd" "ssd"
  local original_id
  original_id="$(__logic_library_id ssd)"

  local root="${LIBRARY_TEST_DIR}/ssd"
  mv "$root" "${root}.away"
  __logic_library_remove "ssd"
  mv "${root}.away" "$root"

  __logic_library_add "$root" "renamed"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_ADDED" "Re-adding should succeed"
  assert_equals "$__library_add_name_out" "renamed" "The requested name should win"
  assert_equals "$(__logic_library_id renamed)" "$original_id" \
    "The id should still come from the marker"
  assert_equals "$(__library_marker_read "$root" name)" "renamed" \
    "The marker should be rewritten with the new name"
}

function test_add_refuses_a_marker_whose_id_is_registered_elsewhere() {
  log_test_step "Testing __logic_library_add with a duplicated marker id"

  _add_library "ssd" "ssd"

  local copy="${LIBRARY_TEST_DIR}/copy"
  mkdir -p "$copy"
  cp "${LIBRARY_TEST_DIR}/ssd/.kgsm-library" "${copy}/.kgsm-library"

  __logic_library_add "$copy" "copy"
  assert_equals "$?" "$EC_LIBRARY_EXISTS" "Should be refused"
  assert_equals "$__library_add_conflict_out" "id" "Conflict should be reported as the id"
  assert_equals "$__library_add_name_out" "ssd" "Should name the library holding that id"
}

# =============================================================================
# ONLINE / OFFLINE
# =============================================================================

function test_a_registered_library_with_its_marker_is_online() {
  log_test_step "Testing __logic_library_is_online on a reachable root"

  _add_library "ssd" "ssd"

  __logic_library_is_online "ssd"
  assert_equals "$?" "0" "A reachable root with a matching marker is online"
}

function test_a_library_whose_root_is_gone_is_offline() {
  log_test_step "Testing __logic_library_is_online with the root renamed away"

  _add_library "ssd" "ssd"
  mv "${LIBRARY_TEST_DIR}/ssd" "${LIBRARY_TEST_DIR}/ssd.away"

  __logic_library_is_online "ssd"
  assert_equals "$?" "1" "A missing root is offline"

  __logic_library_exists "ssd"
  assert_equals "$?" "$EC_SUCCESS" "Offline is a state, not a deregistration"
}

function test_an_empty_mount_point_is_offline() {
  log_test_step "Testing __logic_library_is_online on a root with no marker"

  _add_library "ssd" "ssd"

  # Exactly what an unmounted disk leaves behind: the directory is there and
  # empty. Without the marker check this would read as the library.
  rm -f "${LIBRARY_TEST_DIR}/ssd/.kgsm-library"

  __logic_library_is_online "ssd"
  assert_equals "$?" "1" "A root with no marker is offline"
}

function test_a_root_carrying_another_librarys_marker_is_offline() {
  log_test_step "Testing __logic_library_is_online with a mismatched marker id"

  _add_library "ssd" "ssd"
  __library_marker_write "${LIBRARY_TEST_DIR}/ssd" "0123456789abcdef" "ssd"

  __logic_library_is_online "ssd"
  assert_equals "$?" "1" "A marker id that is not the registered one is offline"
}

function test_online_reports_an_unregistered_library_as_not_found() {
  log_test_step "Testing __logic_library_is_online with an unknown name"

  __logic_library_is_online "nope"
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" "Should return EC_LIBRARY_NOT_FOUND"
}

function test_a_library_comes_back_online_when_its_root_returns() {
  log_test_step "Testing that re-mounting restores a library with no commands"

  _add_library "ssd" "ssd"
  mv "${LIBRARY_TEST_DIR}/ssd" "${LIBRARY_TEST_DIR}/ssd.away"
  __logic_library_is_online "ssd"
  assert_equals "$?" "1" "Should be offline while the root is away"

  mv "${LIBRARY_TEST_DIR}/ssd.away" "${LIBRARY_TEST_DIR}/ssd"
  __logic_library_is_online "ssd"
  assert_equals "$?" "0" "Should be online again with nothing else done"
}

# =============================================================================
# CAPACITY
# =============================================================================

function test_capacity_reports_two_byte_figures() {
  log_test_step "Testing __logic_library_capacity"

  _add_library "ssd" "ssd"

  local free total
  read -r free total < <(__logic_library_capacity "${LIBRARY_TEST_DIR}/ssd")

  assert_matches "$free" "^[0-9]+$" "Free should be a byte count"
  assert_matches "$total" "^[0-9]+$" "Total should be a byte count"
  assert_greater_than "$total" "0" "Total should be positive"
  assert_greater_than "$total" "$((free - 1))" "Total should be at least the free figure"
}

function test_capacity_refuses_a_path_that_is_not_there() {
  log_test_step "Testing __logic_library_capacity on a missing path"

  __logic_library_capacity "${LIBRARY_TEST_DIR}/absent" > /dev/null 2>&1
  assert_equals "$?" "$EC_DIRECTORY_NOT_FOUND" "Should return EC_DIRECTORY_NOT_FOUND"
}

# =============================================================================
# INSTANCE RESOLUTION AND THE REMOVE REFUSAL
# =============================================================================

function test_an_instance_resolves_to_the_library_it_sits_in() {
  log_test_step "Testing __logic_library_for_working_dir"

  _add_library "ssd" "ssd"
  _add_library "archive" "archive"

  assert_equals "$(__logic_library_for_working_dir "${LIBRARY_TEST_DIR}/ssd/factorio/factorio-01")" \
    "ssd" "A working dir under a library root resolves to it"

  __logic_library_for_working_dir "/somewhere/else/factorio/factorio-01" > /dev/null 2>&1
  assert_equals "$?" "$EC_NOT_FOUND" "A working dir in no library resolves to nothing"
}

function test_a_nested_library_wins_the_longest_prefix() {
  log_test_step "Testing __logic_library_for_working_dir with nested roots"

  _add_library "outer" "outer"
  mkdir -p "${LIBRARY_TEST_DIR}/outer/inner"
  __logic_library_add "${LIBRARY_TEST_DIR}/outer/inner" "inner"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_ADDED" "The nested library should register"

  assert_equals "$(__logic_library_for_working_dir "${LIBRARY_TEST_DIR}/outer/inner/factorio/f-01")" \
    "inner" "The innermost library should win"
  assert_equals "$(__logic_library_for_working_dir "${LIBRARY_TEST_DIR}/outer/factorio/f-01")" \
    "outer" "A working dir outside the nested root stays with the outer library"
}

function test_library_instances_lists_what_is_placed_in_it() {
  log_test_step "Testing __logic_library_instances"

  _add_library "ssd" "ssd"
  _add_library "archive" "archive"
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "terraria" "terraria-01"
  _place_instance "${LIBRARY_TEST_DIR}/archive" "factorio" "factorio-02"

  local instances
  instances="$(__logic_library_instances ssd)"
  assert_contains "$instances" "factorio-01" "Should list factorio-01"
  assert_contains "$instances" "terraria-01" "Should list terraria-01"
  assert_not_contains "$instances" "factorio-02" "Should not list another library's instance"
  assert_equals "$(echo "$instances" | grep -c .)" "2" "Should count exactly two"
}

function test_library_instances_counts_an_offline_library() {
  log_test_step "Testing __logic_library_instances with the root renamed away"

  _add_library "ssd" "ssd"
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"
  mv "${LIBRARY_TEST_DIR}/ssd" "${LIBRARY_TEST_DIR}/ssd.away"

  # The symlink is broken now, so its target is read rather than followed. An
  # unmounted disk must not make its instances uncountable.
  local instances
  instances="$(__logic_library_instances ssd)"
  assert_equals "$instances" "factorio-01" "A broken symlink still names its instance"
}

function test_remove_refuses_a_library_holding_instances() {
  log_test_step "Testing __logic_library_remove refuses while instances resolve to it"

  _add_library "ssd" "ssd"
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"

  __logic_library_remove "ssd"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_LIBRARY_IN_USE" "Should return EC_LIBRARY_IN_USE"
  assert_contains "$__library_remove_instances_out" "factorio-01" \
    "Should name the blocking instance"
  __logic_library_exists "ssd"
  assert_equals "$?" "$EC_SUCCESS" "The library should still be registered"
  assert_file_exists "${LIBRARY_TEST_DIR}/ssd/.kgsm-library" "The marker should be untouched"
}

function test_force_removes_a_library_holding_instances_without_touching_files() {
  log_test_step "Testing __logic_library_remove --force"

  _add_library "ssd" "ssd"
  _place_instance "${LIBRARY_TEST_DIR}/ssd" "factorio" "factorio-01"
  echo "world" > "${LIBRARY_TEST_DIR}/ssd/factorio/factorio-01/save.dat"

  __logic_library_remove "ssd" "true"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_REMOVED" "Should deregister"

  __logic_library_exists "ssd"
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" "The library should be deregistered"
  assert_file_exists "${LIBRARY_TEST_DIR}/ssd/factorio/factorio-01/save.dat" \
    "Instance files should be left where they are"
  assert_command_succeeds "[[ -L '${KGSM_INSTANCES_DIR}/factorio/factorio-01' ]]" \
    "The instance's registry symlink should be left alone"
}

function test_remove_of_an_offline_library_leaves_its_marker_on_the_disk() {
  log_test_step "Testing __logic_library_remove with the root unreachable"

  _add_library "ssd" "ssd"
  mv "${LIBRARY_TEST_DIR}/ssd" "${LIBRARY_TEST_DIR}/ssd.away"

  __logic_library_remove "ssd"
  assert_equals "$?" "$EC_SUCCESS_LIBRARY_REMOVED" "Should deregister"

  assert_file_exists "${LIBRARY_TEST_DIR}/ssd.away/.kgsm-library" \
    "The identity stays on the disk so re-adding it adopts rather than re-creates"
}
