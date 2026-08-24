#!/usr/bin/env bash

# KGSM Instance Move + Libraries Integration Tests
#
# Test Type: INTEGRATION
# Target: interaction between commands/instances.sh (move) and
# commands/libraries.sh (the registry, and draining one library into another)
#
# Integration points tested:
# - An instance's files, config, management file and registry entry all end up
#   in the target library, and the source tree is gone
# - Every path key the instance holds is rewritten; the ones that live outside
#   its working directory are not
# - A container instance's compose file is regenerated, so its bind mounts point
#   at the tree that now exists
# - The refusals: a running instance, an unknown or offline target, the same
#   library, a target with no room
# - A failure before the registry is re-pointed leaves the source authoritative,
#   and re-running the move converges
# - `libraries remove --drain` empties a library and then deregisters it

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instance_move_integration"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"
readonly LIBRARIES_MODULE="$KGSM_ROOT/commands/libraries.sh"

SOURCE_ROOT=""
TARGET_ROOT=""
SOURCE_LIBRARY=""
TARGET_LIBRARY=""

# =============================================================================
# HELPERS
# =============================================================================

# Creates an instance in the source library with enough content on disk for a
# backup to have something to capture, and echoes its name.
#
# Called in a command substitution, so nothing it records survives it — the
# teardown finds this test's instances by looking at where the registry points
# instead of by being told.
#
# Args: $1 = blueprint
function _make_instance() {
  local blueprint="$1"

  local instance
  instance="$(create_test_instance "$blueprint" "" "$SOURCE_ROOT")" || return 1

  "$KGSM_ROOT/kgsm.sh" directories create "$instance" > /dev/null 2>&1 || return 1

  local working_dir
  working_dir="$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" working_dir)" || return 1

  echo "content" > "${working_dir}/install/marker"
  echo "world" > "${working_dir}/saves/world"

  echo "$instance"
}

# Removes every registry entry pointing into this test's library roots, along
# with the backups those instances accumulated.
function _sweep_registry() {
  (
    shopt -s nullglob
    local link target instance
    for link in "$KGSM_INSTANCES_DIR"/*/*; do
      [[ -L "$link" ]] || continue
      target="$(readlink "$link")"
      case "$target" in
        "${SOURCE_ROOT}/"* | "${TARGET_ROOT}/"*)
          instance="$(basename "$link")"
          rm -f "$link"
          rm -rf "${KGSM_BACKUPS_DIR:?}/${instance:?}"
          ;;
      esac
    done

    local dir
    for dir in "$KGSM_INSTANCES_DIR"/*; do
      [[ -d "$dir" ]] && rmdir "$dir" 2> /dev/null
    done
  )

  return 0
}

LIVE_PID=""
LIVE_FD=""

# Leaves a genuinely running process behind in LIVE_PID, for the refusals that
# have to see a live server behind an instance's pid file.
#
# The holder blocks on a pipe this shell owns rather than on a duration, so no
# amount of elapsed time can end it early and let a refusal test pass because
# the process it described had quietly gone away. Closing the pipe ends it, and
# the shell dying closes the pipe, so it cannot outlive the test either.
function _spawn_live_process() {
  exec {LIVE_FD}> >(exec cat > /dev/null)
  LIVE_PID=$!
}

# Ends the holder and clears the pair, so a second call and a teardown that runs
# after an explicit reap are both no-ops.
function _reap_live_process() {
  [[ -n "$LIVE_PID" ]] || return 0

  exec {LIVE_FD}>&- 2> /dev/null || true
  kill "$LIVE_PID" 2> /dev/null || true
  wait "$LIVE_PID" 2> /dev/null || true

  LIVE_PID=""
  LIVE_FD=""
}

# Echoes the target of an instance's registry symlink.
function _registry_target() {
  local blueprint="$1"
  local instance="$2"

  readlink "${KGSM_INSTANCES_DIR}/${blueprint}/${instance}"
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instance move integration tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"
  assert_file_executable "$LIBRARIES_MODULE" "libraries.sh should be executable"

  assert_command_succeeds "command -v rsync" "Moving an instance requires rsync"
}

function setup() {
  SOURCE_ROOT="${KGSM_TEST_SANDBOX}/lib-source-${RANDOM}_$$"
  TARGET_ROOT="${KGSM_TEST_SANDBOX}/lib-target-${RANDOM}_$$"

  SOURCE_LIBRARY="$(__ensure_test_library "$SOURCE_ROOT")"
  TARGET_LIBRARY="$(__ensure_test_library "$TARGET_ROOT")"
}

function teardown() {
  _reap_live_process

  chmod u+rwx "$SOURCE_ROOT" "$TARGET_ROOT" 2> /dev/null || true

  _sweep_registry

  "$KGSM_ROOT/kgsm.sh" libraries remove "$SOURCE_LIBRARY" --force > /dev/null 2>&1 || true
  "$KGSM_ROOT/kgsm.sh" libraries remove "$TARGET_LIBRARY" --force > /dev/null 2>&1 || true

  rm -rf "${SOURCE_ROOT:?}" "${TARGET_ROOT:?}"
}

# =============================================================================
# THE MOVE
# =============================================================================

function test_move_places_the_instance_in_the_target_library() {
  log_test_step "Testing that a move lands the instance in the target library"

  local instance
  instance="$(_make_instance factorio)"
  assert_not_null "$instance" "The test instance should be created"

  local source_working_dir="${SOURCE_ROOT}/instances/factorio/${instance}"
  local target_working_dir="${TARGET_ROOT}/instances/factorio/${instance}"

  assert_dir_exists "$source_working_dir" "The instance should start in the source library"

  assert_command_succeeds \
    "$KGSM_ROOT/kgsm.sh instances move $instance --library $TARGET_LIBRARY" \
    "The move should succeed"

  assert_dir_exists "$target_working_dir" \
    "The instance should be nested under the target library's instances directory"
  assert_file_exists "${target_working_dir}/install/marker" \
    "The instance's files should have come with it"
  assert_dir_not_exists "$source_working_dir" \
    "The source tree should be gone once the move is done"
  assert_equals "$target_working_dir" "$(_registry_target factorio "$instance")" \
    "The registry entry should point at the new tree"
}

function test_move_rewrites_every_path_key() {
  log_test_step "Testing that no config key still points at the old tree"

  local instance
  instance="$(_make_instance factorio)"

  local source_working_dir="${SOURCE_ROOT}/instances/factorio/${instance}"
  local target_working_dir="${TARGET_ROOT}/instances/factorio/${instance}"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null

  local config_file="${target_working_dir}/${instance}.config.ini"
  assert_file_exists "$config_file" "The config should be at the new location"

  local leftovers
  leftovers="$(grep -c "${source_working_dir}" "$config_file" || true)"
  assert_equals "0" "$leftovers" \
    "No line in the config should still reference the old working directory"

  assert_file_contains "$config_file" "working_dir=\"${target_working_dir}\"" \
    "working_dir should name the new tree"
  assert_file_contains "$config_file" "library_dir=\"${TARGET_ROOT}\"" \
    "library_dir should name the target library's root"
}

function test_move_leaves_the_backups_directory_alone() {
  log_test_step "Testing that a move does not relocate backups"

  local instance
  instance="$(_make_instance factorio)"

  local backups_before
  backups_before="$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" backups_dir)"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null

  local backups_after
  backups_after="$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" backups_dir)"

  assert_equals "$backups_before" "$backups_after" \
    "backups_dir lives outside the instance and should not move with it"
}

function test_move_takes_a_backup_first() {
  log_test_step "Testing that a move backs the instance up before copying it"

  local instance
  instance="$(_make_instance factorio)"

  local backups_before
  backups_before="$("$KGSM_ROOT/kgsm.sh" instances backups "$instance" | grep -c . || true)"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null

  local backups_after
  backups_after="$("$KGSM_ROOT/kgsm.sh" instances backups "$instance" | grep -c . || true)"

  assert_greater_than "$backups_after" "$backups_before" \
    "The move should leave one more backup than it found"
}

function test_move_regenerates_the_management_file() {
  log_test_step "Testing that the management file is rebuilt at the new location"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null

  local target_working_dir="${TARGET_ROOT}/instances/factorio/${instance}"
  assert_file_executable "${target_working_dir}/${instance}.manage.sh" \
    "The management file should be executable at the new location"

  local management_file
  management_file="$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" management_file)"
  assert_equals "${target_working_dir}/${instance}.manage.sh" "$management_file" \
    "The config should name the management file at the new location"
}

function test_move_regenerates_a_container_compose_file() {
  log_test_step "Testing that a container's bind mounts follow it"

  local instance
  instance="$(_make_instance vrising)"
  assert_not_null "$instance" "The container test instance should be created"

  local source_working_dir="${SOURCE_ROOT}/instances/vrising/${instance}"
  local target_working_dir="${TARGET_ROOT}/instances/vrising/${instance}"
  local compose_file="${target_working_dir}/${instance}.docker-compose.yml"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null

  assert_file_exists "$compose_file" "The compose file should exist at the new location"

  local stale
  stale="$(grep -c "$source_working_dir" "$compose_file" || true)"
  assert_equals "0" "$stale" \
    "A bind mount pointing at the tree the move removed would never start"

  assert_file_contains "$compose_file" "$target_working_dir" \
    "The compose file should bind-mount the tree that now exists"
}

# =============================================================================
# REFUSALS
# =============================================================================

function test_move_refuses_a_running_instance() {
  log_test_step "Testing that a running instance is refused"

  local instance
  instance="$(_make_instance factorio)"

  local working_dir="${SOURCE_ROOT}/instances/factorio/${instance}"
  local pid_file
  pid_file="$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" pid_file)"

  # A process that is genuinely alive, so the management script's own liveness
  # check answers the way a running server would.
  _spawn_live_process
  echo "$LIVE_PID" > "$pid_file"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null 2>&1
  local exit_code=$?

  _reap_live_process
  rm -f "$pid_file"

  assert_equals "$exit_code" "$EC_INSTANCE_RUNNING" \
    "Moving a running instance should be refused with EC_INSTANCE_RUNNING"
  assert_dir_exists "$working_dir" "The instance should be exactly where it was"
  assert_dir_not_exists "${TARGET_ROOT}/instances/factorio/${instance}" \
    "Nothing should have been copied to the target"
}

function test_move_refuses_an_unregistered_target_library() {
  log_test_step "Testing a move into a library that is not registered"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "no-such-library" > /dev/null 2>&1
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" \
    "An unregistered target should be refused with EC_LIBRARY_NOT_FOUND"
}

function test_move_refuses_the_library_the_instance_is_already_in() {
  log_test_step "Testing a move into the instance's own library"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$SOURCE_LIBRARY" > /dev/null 2>&1
  assert_equals "$?" "$EC_INVALID_ARG" \
    "Moving an instance where it already is should be refused"
}

function test_move_refuses_an_offline_target_library() {
  log_test_step "Testing a move into a library that is not mounted"

  local instance
  instance="$(_make_instance factorio)"

  # What an unmounted disk leaves behind: the registered path, with no marker.
  mv "$TARGET_ROOT" "${TARGET_ROOT}.away"
  mkdir -p "$TARGET_ROOT"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null 2>&1
  local exit_code=$?

  rmdir "$TARGET_ROOT"
  mv "${TARGET_ROOT}.away" "$TARGET_ROOT"

  assert_equals "$exit_code" "$EC_LIBRARY_OFFLINE" \
    "An offline target should be refused with EC_LIBRARY_OFFLINE"
}

function test_move_refuses_a_target_with_no_room() {
  log_test_step "Testing the free-space gate on the target library"

  local instance
  instance="$(_make_instance factorio)"

  # A margin no filesystem can satisfy, so the gate refuses on a real
  # measurement rather than on a doctored one.
  export config_install_free_space_margin_mb=999999999

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null 2>&1
  local exit_code=$?

  assert_equals "$exit_code" "$EC_INSUFFICIENT_DISK" \
    "A target without room should be refused with EC_INSUFFICIENT_DISK"
  assert_dir_not_exists "${TARGET_ROOT}/instances/factorio/${instance}" \
    "Nothing should have been copied when the gate refused"

  unset config_install_free_space_margin_mb
}

function test_move_honors_skip_space_check() {
  log_test_step "Testing that --skip-space-check moves anyway"

  local instance
  instance="$(_make_instance factorio)"

  export config_install_free_space_margin_mb=999999999

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" \
    --skip-space-check > /dev/null 2>&1
  local exit_code=$?

  unset config_install_free_space_margin_mb

  assert_equals "$exit_code" "0" "--skip-space-check should move the instance"
  assert_dir_exists "${TARGET_ROOT}/instances/factorio/${instance}" \
    "The instance should have landed in the target library"
}

function test_move_requires_a_target_library() {
  log_test_step "Testing a move with no --library"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" > /dev/null 2>&1
  assert_equals "$?" "$EC_MISSING_ARG" "A move with no target should be refused"
}

# =============================================================================
# FAILING PARTWAY THROUGH
# =============================================================================

function test_move_failure_before_the_repoint_leaves_the_source_authoritative() {
  log_test_step "Testing a move that cannot write to the target"

  local instance
  instance="$(_make_instance factorio)"

  local source_working_dir="${SOURCE_ROOT}/instances/factorio/${instance}"

  # The target library is reachable and readable — its marker still answers —
  # but nothing can be created in it.
  chmod u-w "$TARGET_ROOT"

  "$KGSM_ROOT/kgsm.sh" instances move "$instance" --library "$TARGET_LIBRARY" > /dev/null 2>&1
  local exit_code=$?

  chmod u+w "$TARGET_ROOT"

  assert_not_equals "$exit_code" "0" "A move that cannot write the copy should fail"
  assert_dir_exists "$source_working_dir" "The source tree should still be there"
  assert_file_exists "${source_working_dir}/install/marker" \
    "The source tree should still be complete"
  assert_equals "$source_working_dir" "$(_registry_target factorio "$instance")" \
    "The registry entry should still point at the source"

  local config_file="${source_working_dir}/${instance}.config.ini"
  assert_file_contains "$config_file" "working_dir=\"${source_working_dir}\"" \
    "The authoritative config should be untouched"
}

function test_move_re_run_converges_after_a_partial_copy() {
  log_test_step "Testing that a re-run cleans up what an interrupted move left"

  local instance
  instance="$(_make_instance factorio)"

  local target_working_dir="${TARGET_ROOT}/instances/factorio/${instance}"

  # What an interrupted move leaves at the target: part of the tree, plus a file
  # the source does not have.
  mkdir -p "${target_working_dir}/install"
  echo "stale" > "${target_working_dir}/install/leftover"

  assert_command_succeeds \
    "$KGSM_ROOT/kgsm.sh instances move $instance --library $TARGET_LIBRARY" \
    "Re-running the move should succeed"

  assert_file_exists "${target_working_dir}/install/marker" \
    "The re-run should complete the copy"
  assert_file_not_exists "${target_working_dir}/install/leftover" \
    "The re-run should remove what the source does not have"
}

# =============================================================================
# DRAINING A LIBRARY
# =============================================================================

function test_drain_moves_every_resident_and_deregisters_the_library() {
  log_test_step "Testing that a drain empties a library and removes it"

  local first second
  first="$(_make_instance factorio)"
  second="$(_make_instance terraria)"

  assert_command_succeeds \
    "$KGSM_ROOT/kgsm.sh libraries remove $SOURCE_LIBRARY --drain $TARGET_LIBRARY" \
    "The drain should succeed"

  assert_dir_exists "${TARGET_ROOT}/instances/factorio/${first}" \
    "The first instance should be in the target library"
  assert_dir_exists "${TARGET_ROOT}/instances/terraria/${second}" \
    "The second instance should be in the target library"

  local listing
  listing="$("$KGSM_ROOT/kgsm.sh" libraries list)"
  assert_not_contains "$listing" "$SOURCE_LIBRARY" \
    "The drained library should no longer be registered"
}

function test_drain_refuses_while_a_resident_is_running() {
  log_test_step "Testing that a drain refuses to touch a running instance"

  local instance
  instance="$(_make_instance factorio)"

  local pid_file
  pid_file="$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" pid_file)"

  _spawn_live_process
  echo "$LIVE_PID" > "$pid_file"

  "$KGSM_ROOT/kgsm.sh" libraries remove "$SOURCE_LIBRARY" --drain "$TARGET_LIBRARY" > /dev/null 2>&1
  local exit_code=$?

  _reap_live_process
  rm -f "$pid_file"

  assert_equals "$exit_code" "$EC_INSTANCE_RUNNING" \
    "A drain with a running resident should be refused with EC_INSTANCE_RUNNING"
  assert_dir_exists "${SOURCE_ROOT}/instances/factorio/${instance}" \
    "Nothing should have been moved"

  local listing
  listing="$("$KGSM_ROOT/kgsm.sh" libraries list)"
  assert_contains "$listing" "$SOURCE_LIBRARY" \
    "The library should still be registered"
}

function test_drain_refuses_an_unregistered_target() {
  log_test_step "Testing a drain into a library that is not registered"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" libraries remove "$SOURCE_LIBRARY" --drain "no-such-library" > /dev/null 2>&1
  assert_equals "$?" "$EC_LIBRARY_NOT_FOUND" \
    "An unregistered drain target should be refused"
}

function test_drain_refuses_draining_into_itself() {
  log_test_step "Testing a drain into the library being removed"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" libraries remove "$SOURCE_LIBRARY" --drain "$SOURCE_LIBRARY" > /dev/null 2>&1
  assert_equals "$?" "$EC_INVALID_ARG" "A library cannot be drained into itself"
}

function test_drain_and_force_are_refused_together() {
  log_test_step "Testing --drain together with --force"

  "$KGSM_ROOT/kgsm.sh" libraries remove "$SOURCE_LIBRARY" \
    --drain "$TARGET_LIBRARY" --force > /dev/null 2>&1
  assert_equals "$?" "$EC_INVALID_ARG" \
    "--drain and --force ask for opposite things and should be refused together"

  local listing
  listing="$("$KGSM_ROOT/kgsm.sh" libraries list)"
  assert_contains "$listing" "$SOURCE_LIBRARY" \
    "The library should still be registered"
}

function test_drain_of_an_empty_library_just_deregisters_it() {
  log_test_step "Testing a drain of a library that holds nothing"

  assert_command_succeeds \
    "$KGSM_ROOT/kgsm.sh libraries remove $SOURCE_LIBRARY --drain $TARGET_LIBRARY" \
    "Draining an empty library should succeed"

  local listing
  listing="$("$KGSM_ROOT/kgsm.sh" libraries list)"
  assert_not_contains "$listing" "$SOURCE_LIBRARY" \
    "The library should have been deregistered"
}

# =============================================================================
# THE REFUSAL THAT POINTS AT THE DRAIN
# =============================================================================

function test_remove_refusal_names_the_drain() {
  log_test_step "Testing what a refused library removal advises"

  local instance
  instance="$(_make_instance factorio)"

  local output
  output="$("$KGSM_ROOT/kgsm.sh" libraries remove "$SOURCE_LIBRARY" 2>&1)"
  local exit_code=$?

  assert_equals "$exit_code" "$EC_LIBRARY_IN_USE" \
    "Removing a library that holds instances should be refused"
  assert_contains "$output" "--drain" \
    "The refusal should name the way to empty the library"
  assert_contains "$output" "$instance" \
    "The refusal should name the instances that block it"
  assert_not_contains "$output" "Broken pipe" \
    "The refusal should not be preceded by a write error"
}
