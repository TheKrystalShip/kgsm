#!/usr/bin/env bash

# KGSM Instance Move Unit Tests
#
# Test Type: UNIT
# Target: the pure logic a move between libraries is built from — where an
# instance would land in a library, which of its config keys are paths inside
# its working directory, the rewrite that repoints them, the size measurement
# the target is gated on, the resumable copy, and the signal that says whether
# the instance has ever run.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instance_move"
readonly HANDLER="$KGSM_ROOT/commands/handlers/instances.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instance move tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Instances handler should exist"

  source "$HANDLER"

  assert_not_null "$EC_INSTANCE_RUNNING" "EC_INSTANCE_RUNNING should be defined"

  assert_function_exists "__logic_instance_target_working_dir" \
    "__logic_instance_target_working_dir should be exported"
  assert_function_exists "__logic_instance_path_keys_under" \
    "__logic_instance_path_keys_under should be exported"
  assert_function_exists "__logic_instance_rewrite_paths" \
    "__logic_instance_rewrite_paths should be exported"
  assert_function_exists "__logic_instance_tree_size_mb" \
    "__logic_instance_tree_size_mb should be exported"
  assert_function_exists "__logic_instance_copy_tree" \
    "__logic_instance_copy_tree should be exported"
  assert_function_exists "__logic_instance_has_run" \
    "__logic_instance_has_run should be exported"
}

function setup() {
  declare -g MOVE_TEST_DIR="${KGSM_TEST_SANDBOX}/move_${RANDOM}_$$"
  mkdir -p "$MOVE_TEST_DIR"
}

function teardown() {
  rm -rf "${MOVE_TEST_DIR:?}"
}

# Writes an instance config carrying every shape of path key a move has to tell
# apart: paths inside the working directory, paths deliberately outside it, and
# values that are not paths at all.
# Args: $1 = config file, $2 = working dir, $3 = library root
function _write_move_config() {
  local config_file="$1"
  local working_dir="$2"
  local library_dir="$3"

  mkdir -p "$(dirname "$config_file")"
  {
    printf '# a comment that happens to mention working_dir=/nowhere\n'
    printf 'name="probe"\n'
    printf 'runtime="native"\n'
    printf 'library_dir="%s"\n' "$library_dir"
    printf 'working_dir="%s"\n' "$working_dir"
    printf 'install_dir="%s/install"\n' "$working_dir"
    printf 'saves_dir="%s/saves"\n' "$working_dir"
    printf 'temp_dir="%s/temp"\n' "$working_dir"
    printf 'logs_dir="%s/logs"\n' "$working_dir"
    printf 'events_dir="%s/events"\n' "$working_dir"
    printf 'launch_dir="%s/install"\n' "$working_dir"
    printf 'management_file="%s/probe.manage.sh"\n' "$working_dir"
    printf 'version_file="%s/.probe.version"\n' "$working_dir"
    printf 'pid_file="%s/.probe.pid"\n' "$working_dir"
    printf 'log_file="%s/probe.log"\n' "$working_dir"
    printf 'backups_dir="%s/backups/probe"\n' "$MOVE_TEST_DIR"
    printf 'blueprint_file="%s/blueprints/factorio.bp.yaml"\n' "$MOVE_TEST_DIR"
    printf 'command_shortcut_file="%s/bin/probe"\n' "$MOVE_TEST_DIR"
    printf 'compose_file=""\n'
    printf 'executable_file="java"\n'
    printf 'auto_update="false"\n'
  } > "$config_file"
}

# =============================================================================
# TARGET LAYOUT
# =============================================================================

function test_target_working_dir_is_nested_under_the_library() {
  log_test_step "Testing where an instance lands in a library"

  local result
  result="$(__logic_instance_target_working_dir "/mnt/ssd" "factorio" "factorio-01")"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "A complete request should resolve"
  assert_equals "/mnt/ssd/instances/factorio/factorio-01" "$result" \
    "The target should be <library>/instances/<blueprint>/<instance>"
}

function test_target_working_dir_ignores_a_trailing_slash() {
  log_test_step "Testing a library root with a trailing slash"

  local result
  result="$(__logic_instance_target_working_dir "/mnt/ssd/" "factorio" "factorio-01")"

  assert_equals "/mnt/ssd/instances/factorio/factorio-01" "$result" \
    "A trailing slash should not double up in the target path"
}

function test_target_working_dir_refuses_an_incomplete_request() {
  log_test_step "Testing an incomplete target request"

  __logic_instance_target_working_dir "/mnt/ssd" "" "factorio-01" > /dev/null
  assert_equals "$?" "$EC_INVALID_ARG" "A missing blueprint should be refused"

  __logic_instance_target_working_dir "" "factorio" "factorio-01" > /dev/null
  assert_equals "$?" "$EC_INVALID_ARG" "A missing library root should be refused"
}

# =============================================================================
# ENUMERATING THE PATHS A MOVE OWNS
# =============================================================================

function test_path_keys_enumerates_everything_inside_the_working_dir() {
  log_test_step "Testing which config keys a move claims"

  local working_dir="${MOVE_TEST_DIR}/lib-a/instances/factorio/probe"
  local config_file="${working_dir}/probe.config.ini"
  _write_move_config "$config_file" "$working_dir" "${MOVE_TEST_DIR}/lib-a"

  local keys
  keys="$(__logic_instance_path_keys_under "$config_file" "$working_dir" | cut -f1 | sort | tr '\n' ' ')"

  assert_equals \
    "events_dir install_dir launch_dir log_file logs_dir management_file pid_file saves_dir temp_dir version_file working_dir " \
    "$keys" \
    "Every *_dir/*_file value inside the working directory should be claimed"
}

function test_path_keys_leaves_the_out_of_tree_keys_alone() {
  log_test_step "Testing which config keys a move must not touch"

  local working_dir="${MOVE_TEST_DIR}/lib-a/instances/factorio/probe"
  local config_file="${working_dir}/probe.config.ini"
  _write_move_config "$config_file" "$working_dir" "${MOVE_TEST_DIR}/lib-a"

  local keys
  keys="$(__logic_instance_path_keys_under "$config_file" "$working_dir" | cut -f1)"

  assert_not_contains "$keys" "backups_dir" \
    "backups_dir lives outside the working directory and must not move with it"
  assert_not_contains "$keys" "blueprint_file" \
    "blueprint_file points into the KGSM installation and must not move"
  assert_not_contains "$keys" "command_shortcut_file" \
    "command_shortcut_file points at a directory on the user's PATH"
  assert_not_contains "$keys" "library_dir" \
    "library_dir is not inside the working directory"
  assert_not_contains "$keys" "compose_file" \
    "An empty value names no path"
  assert_not_contains "$keys" "executable_file" \
    "A bare command name is not a path inside the working directory"
}

function test_path_keys_ignores_a_sibling_directory_with_a_shared_prefix() {
  log_test_step "Testing a sibling whose name starts with the working directory's"

  local working_dir="${MOVE_TEST_DIR}/lib-a/instances/factorio/probe"
  local config_file="${working_dir}/probe.config.ini"
  _write_move_config "$config_file" "$working_dir" "${MOVE_TEST_DIR}/lib-a"

  # `probe-backup` shares every character of `probe` and is a different instance.
  printf 'stray_dir="%s-backup/install"\n' "$working_dir" >> "$config_file"

  local keys
  keys="$(__logic_instance_path_keys_under "$config_file" "$working_dir" | cut -f1)"

  assert_not_contains "$keys" "stray_dir" \
    "A path that merely starts with the working directory's name is a different tree"
}

function test_path_keys_refuses_a_missing_config() {
  log_test_step "Testing enumeration against a config that is not there"

  __logic_instance_path_keys_under "${MOVE_TEST_DIR}/absent.ini" "/tmp" > /dev/null
  assert_equals "$?" "$EC_FILE_NOT_FOUND" "A missing config should be reported as missing"
}

# =============================================================================
# REWRITING THEM
# =============================================================================

function test_rewrite_leaves_no_key_pointing_at_the_old_path() {
  log_test_step "Testing that a rewrite is complete"

  local old_working_dir="${MOVE_TEST_DIR}/lib-a/instances/factorio/probe"
  local new_working_dir="${MOVE_TEST_DIR}/lib-b/instances/factorio/probe"
  local config_file="${new_working_dir}/probe.config.ini"
  _write_move_config "$config_file" "$old_working_dir" "${MOVE_TEST_DIR}/lib-a"

  __logic_instance_rewrite_paths "$config_file" "$old_working_dir" \
    "$new_working_dir" "${MOVE_TEST_DIR}/lib-b"
  assert_equals "$?" "$EC_SUCCESS" "The rewrite should succeed"

  local leftovers
  leftovers="$(grep -c "^[a-zA-Z_][a-zA-Z0-9_]*=\"${old_working_dir}" "$config_file" || true)"

  assert_equals "0" "$leftovers" \
    "No key should still reference the old working directory"
}

function test_rewrite_moves_every_claimed_key() {
  log_test_step "Testing the rewritten values"

  local old_working_dir="${MOVE_TEST_DIR}/lib-a/instances/factorio/probe"
  local new_working_dir="${MOVE_TEST_DIR}/lib-b/instances/factorio/probe"
  local config_file="${new_working_dir}/probe.config.ini"
  _write_move_config "$config_file" "$old_working_dir" "${MOVE_TEST_DIR}/lib-a"

  __logic_instance_rewrite_paths "$config_file" "$old_working_dir" \
    "$new_working_dir" "${MOVE_TEST_DIR}/lib-b"

  assert_file_contains "$config_file" "working_dir=\"${new_working_dir}\"" \
    "working_dir should point at the new tree"
  assert_file_contains "$config_file" "install_dir=\"${new_working_dir}/install\"" \
    "install_dir should keep its position under the new tree"
  assert_file_contains "$config_file" "management_file=\"${new_working_dir}/probe.manage.sh\"" \
    "management_file should point at the new tree"
  assert_file_contains "$config_file" "log_file=\"${new_working_dir}/probe.log\"" \
    "log_file should point at the new tree"
}

function test_rewrite_records_the_new_library() {
  log_test_step "Testing that a rewrite records where the instance now lives"

  local old_working_dir="${MOVE_TEST_DIR}/lib-a/instances/factorio/probe"
  local new_working_dir="${MOVE_TEST_DIR}/lib-b/instances/factorio/probe"
  local config_file="${new_working_dir}/probe.config.ini"
  _write_move_config "$config_file" "$old_working_dir" "${MOVE_TEST_DIR}/lib-a"

  __logic_instance_rewrite_paths "$config_file" "$old_working_dir" \
    "$new_working_dir" "${MOVE_TEST_DIR}/lib-b"

  assert_file_contains "$config_file" "library_dir=\"${MOVE_TEST_DIR}/lib-b\"" \
    "library_dir should name the new library root"
}

function test_rewrite_leaves_the_out_of_tree_keys_untouched() {
  log_test_step "Testing that a rewrite leaves backups where they are"

  local old_working_dir="${MOVE_TEST_DIR}/lib-a/instances/factorio/probe"
  local new_working_dir="${MOVE_TEST_DIR}/lib-b/instances/factorio/probe"
  local config_file="${new_working_dir}/probe.config.ini"
  _write_move_config "$config_file" "$old_working_dir" "${MOVE_TEST_DIR}/lib-a"

  __logic_instance_rewrite_paths "$config_file" "$old_working_dir" \
    "$new_working_dir" "${MOVE_TEST_DIR}/lib-b"

  assert_file_contains "$config_file" "backups_dir=\"${MOVE_TEST_DIR}/backups/probe\"" \
    "backups_dir should be exactly what it was"
  assert_file_contains "$config_file" "blueprint_file=\"${MOVE_TEST_DIR}/blueprints/factorio.bp.yaml\"" \
    "blueprint_file should be exactly what it was"
  assert_file_contains "$config_file" "executable_file=\"java\"" \
    "A value that is not a path should be exactly what it was"
}

function test_rewrite_refuses_an_incomplete_request() {
  log_test_step "Testing an incomplete rewrite request"

  __logic_instance_rewrite_paths "" "/a" "/b" "/lib"
  assert_equals "$?" "$EC_INVALID_ARG" "A missing config file should be refused"

  __logic_instance_rewrite_paths "${MOVE_TEST_DIR}/absent.ini" "/a" "/b" "/lib"
  assert_equals "$?" "$EC_FILE_NOT_FOUND" "A config that is not there should be reported"
}

# =============================================================================
# MEASURING WHAT IS ABOUT TO BE COPIED
# =============================================================================

function test_tree_size_is_measured_from_the_tree() {
  log_test_step "Testing the measured size of an instance"

  local tree="${MOVE_TEST_DIR}/tree"
  mkdir -p "$tree"
  dd if=/dev/zero of="${tree}/blob" bs=1M count=3 2> /dev/null

  local size
  size="$(__logic_instance_tree_size_mb "$tree")"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_SUCCESS" "A readable tree should measure"
  assert_greater_than "$size" "2" "A 3MB file should measure at least 3MB"
}

function test_tree_size_refuses_a_missing_directory() {
  log_test_step "Testing the size of a directory that is not there"

  __logic_instance_tree_size_mb "${MOVE_TEST_DIR}/absent" > /dev/null
  assert_equals "$?" "$EC_DIRECTORY_NOT_FOUND" "A missing tree should be reported as missing"
}

# =============================================================================
# THE COPY
# =============================================================================

function test_copy_reproduces_the_tree() {
  log_test_step "Testing the copy an instance is moved with"

  local source="${MOVE_TEST_DIR}/source"
  local target="${MOVE_TEST_DIR}/target"
  mkdir -p "${source}/install" "${source}/saves"
  echo "binary" > "${source}/install/game"
  echo "world" > "${source}/saves/world.zip"

  __logic_instance_copy_tree "$source" "$target"
  assert_equals "$?" "$EC_SUCCESS" "The copy should succeed"

  assert_file_exists "${target}/install/game" "Installed files should arrive"
  assert_file_exists "${target}/saves/world.zip" "Saves should arrive"
}

function test_copy_converges_after_an_interrupted_one() {
  log_test_step "Testing that re-running a move cleans up a partial copy"

  local source="${MOVE_TEST_DIR}/source"
  local target="${MOVE_TEST_DIR}/target"
  mkdir -p "${source}/install"
  echo "binary" > "${source}/install/game"

  # What an interrupted move leaves behind: some of the tree, plus a file the
  # source no longer has.
  mkdir -p "${target}/install"
  echo "stale" > "${target}/install/leftover"

  __logic_instance_copy_tree "$source" "$target"
  assert_equals "$?" "$EC_SUCCESS" "A re-run should succeed"

  assert_file_exists "${target}/install/game" "The re-run should complete the copy"
  assert_file_not_exists "${target}/install/leftover" \
    "The re-run should remove what the source does not have"
}

function test_copy_refuses_a_missing_source() {
  log_test_step "Testing a copy from a tree that is not there"

  __logic_instance_copy_tree "${MOVE_TEST_DIR}/absent" "${MOVE_TEST_DIR}/target"
  assert_equals "$?" "$EC_DIRECTORY_NOT_FOUND" "A missing source should be reported as missing"
}

# =============================================================================
# WHETHER THE INSTANCE HAS EVER RUN
# =============================================================================

function test_has_run_is_false_for_an_instance_that_never_started() {
  log_test_step "Testing the run signal of a freshly installed instance"

  local logs_dir="${MOVE_TEST_DIR}/logs"
  mkdir -p "$logs_dir"

  __logic_instance_has_run "${MOVE_TEST_DIR}/probe.log" "$logs_dir"
  assert_equals "$?" "1" "Neither a log file nor a rotated one means it never ran"
}

function test_has_run_is_true_when_a_log_file_exists() {
  log_test_step "Testing the run signal against a live log file"

  local logs_dir="${MOVE_TEST_DIR}/logs"
  mkdir -p "$logs_dir"
  touch "${MOVE_TEST_DIR}/probe.log"

  __logic_instance_has_run "${MOVE_TEST_DIR}/probe.log" "$logs_dir"
  assert_equals "$?" "0" "A log file is a run"
}

function test_has_run_is_true_when_only_a_rotated_log_exists() {
  log_test_step "Testing the run signal against a rotated log"

  local logs_dir="${MOVE_TEST_DIR}/logs"
  mkdir -p "$logs_dir"
  touch "${logs_dir}/probe.2026-08-23T00:00:00.log"

  __logic_instance_has_run "${MOVE_TEST_DIR}/probe.log" "$logs_dir"
  assert_equals "$?" "0" "A rotated log is a run the live file no longer shows"
}
