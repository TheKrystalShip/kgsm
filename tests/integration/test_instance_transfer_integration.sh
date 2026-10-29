#!/usr/bin/env bash

# KGSM Instance Transfer Integration Tests
#
# Test Type: INTEGRATION
# Target: interaction between commands/instances.sh (export, unlock, import),
# commands/uninstall.sh, commands/lifecycle.sh and the library registry
#
# Integration points tested:
# - export --manifest describes a stopped instance and, with --lock, holds it
# - a locked instance refuses start, restart, uninstall, move and update, and a
#   second token cannot take or release the lock
# - the tree streams out of one library and into another through import
#   begin, part and finish; the new instance has a fresh id, its own paths and
#   everything the source held
# - export --commit removes the source
# - the preflight lists every refusal at once, and begin stages nothing when it
#   refuses
# - abort removes the staging, an unknown id aborts quietly, list shows what is
#   staged
# - finish refuses a missing part

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instance_transfer_integration"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

SOURCE_ROOT=""
TARGET_ROOT=""
SOURCE_LIBRARY=""
TARGET_LIBRARY=""

# =============================================================================
# HELPERS
# =============================================================================

# Creates an instance in the source library with some content on disk, and
# echoes its name.
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

# Echoes an instance's manifest as the target would receive it. A game's
# declared ports would collide with the source on this one machine, so the
# manifest the target sees declares none.
#
# Args: $1 = instance, $2 = lock token
function _manifest_without_ports() {
  "$KGSM_ROOT/kgsm.sh" instances export "$1" --manifest --lock "$2" 2> /dev/null |
    jq '.instance.ports = []'
}

# Runs the whole import of an instance into the target library and echoes the
# new instance's name. The source stays locked with the given token.
#
# Args: $1 = instance, $2 = lock token
function _transfer_to_target() {
  local instance="$1"
  local token="$2"

  local manifest import_id
  manifest="$(_manifest_without_ports "$instance" "$token")" || return 1

  import_id="$("$KGSM_ROOT/kgsm.sh" instances import begin --library "$TARGET_LIBRARY" --json \
    <<< "$manifest" 2> /dev/null | jq -r '.import_id')" || return 1

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --part tree --lock "$token" 2> /dev/null |
    "$KGSM_ROOT/kgsm.sh" instances import part "$import_id" tree 2> /dev/null || return 1

  "$KGSM_ROOT/kgsm.sh" instances import finish "$import_id" --json 2> /dev/null |
    jq -r '.instance'
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instance transfer integration tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"

  # The host's own watchdog is not part of what is tested here, and a sandbox
  # that reached it would be asking it about instances it has never heard of.
  export KGSM_WATCHDOG_DISABLE=true
}

function setup() {
  SOURCE_ROOT="${KGSM_TEST_SANDBOX}/lib-source-${RANDOM}_$$"
  TARGET_ROOT="${KGSM_TEST_SANDBOX}/lib-target-${RANDOM}_$$"

  SOURCE_LIBRARY="$(__ensure_test_library "$SOURCE_ROOT")"
  TARGET_LIBRARY="$(__ensure_test_library "$TARGET_ROOT")"
}

function teardown() {
  _sweep_registry

  "$KGSM_ROOT/kgsm.sh" libraries remove "$SOURCE_LIBRARY" --force > /dev/null 2>&1 || true
  "$KGSM_ROOT/kgsm.sh" libraries remove "$TARGET_LIBRARY" --force > /dev/null 2>&1 || true

  rm -rf "${SOURCE_ROOT:?}" "${TARGET_ROOT:?}"
}

# =============================================================================
# THE MANIFEST
# =============================================================================

function test_manifest_describes_the_instance() {
  log_test_step "Testing that the manifest carries the instance and its tree"

  local instance
  instance="$(_make_instance factorio)"
  assert_not_null "$instance" "The test instance should be created"

  local manifest
  manifest="$("$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest 2> /dev/null)"
  assert_equals "0" "$?" "A stopped instance should export a manifest"

  assert_equals "1" "$(jq -r '.format' <<< "$manifest")" "The manifest is format 1"
  assert_equals "$KGSM_VERSION" "$(jq -r '.engine_version' <<< "$manifest")" \
    "The manifest names the engine that wrote it"
  assert_equals "$instance" "$(jq -r '.instance.id' <<< "$manifest")" "The instance id"
  assert_equals "factorio" "$(jq -r '.instance.blueprint' <<< "$manifest")" "The blueprint"
  assert_equals "native" "$(jq -r '.instance.runtime' <<< "$manifest")" "The runtime"
  assert_equals "$SOURCE_LIBRARY" "$(jq -r '.instance.library' <<< "$manifest")" "The library"
  assert_equals "false" "$(jq -r '.instance.has_run' <<< "$manifest")" \
    "An instance that never ran says so"
  assert_equals "false" "$(jq -r '.blueprint.custom' <<< "$manifest")" \
    "A bundled blueprint does not travel"
  assert_equals "tree" "$(jq -r '.parts[0].id' <<< "$manifest")" "The tree is the first part"

  local working_dir expected_files
  working_dir="${SOURCE_ROOT}/instances/factorio/${instance}"
  expected_files="$(find "$working_dir" ! -type d ! -type s | wc -l)"
  assert_equals "$expected_files" "$(jq -r '.parts[0].files' <<< "$manifest")" \
    "The tree part counts the files under the working directory"
}

function test_manifest_without_a_lock_leaves_the_instance_unlocked() {
  log_test_step "Testing that describing an instance does not lock it"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest > /dev/null 2>&1

  assert_equals "" "$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" transfer_lock 2> /dev/null)" \
    "No lock should be taken without --lock"
}

# =============================================================================
# THE LOCK
# =============================================================================

function test_lock_refuses_the_verbs_that_would_change_the_instance() {
  log_test_step "Testing that a locked instance refuses start, restart, uninstall, move and update"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest --lock T1 > /dev/null 2>&1
  assert_equals "T1" "$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" transfer_lock)" \
    "The lock should hold the token"

  local verb
  for verb in "start $instance" "restart $instance" "uninstall $instance --force" \
    "instances move $instance --library $TARGET_LIBRARY" "instances update $instance"; do
    # shellcheck disable=SC2086
    "$KGSM_ROOT/kgsm.sh" $verb > /dev/null 2>&1
    assert_equals "$EC_INSTANCE_LOCKED" "$?" "'$verb' should be refused while locked"
  done

  assert_file_exists "${SOURCE_ROOT}/instances/factorio/${instance}/install/marker" \
    "Nothing should have touched the files"
}

function test_lock_refuses_a_second_token() {
  log_test_step "Testing that another token can neither take nor release the lock"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest --lock T1 > /dev/null 2>&1

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest --lock T2 > /dev/null 2>&1
  assert_equals "$EC_INSTANCE_LOCKED" "$?" "A second token cannot take the lock"

  "$KGSM_ROOT/kgsm.sh" instances unlock "$instance" --lock T2 > /dev/null 2>&1
  assert_equals "$EC_INSTANCE_LOCKED" "$?" "A second token cannot release the lock"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --part tree --lock T2 > /dev/null 2>&1
  assert_equals "$EC_INSTANCE_LOCKED" "$?" "A second token cannot read a part"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest --lock T1 > /dev/null 2>&1
  assert_equals "0" "$?" "The holder can confirm its own lock"
}

function test_unlock_releases_the_lock() {
  log_test_step "Testing that unlock lifts the lock and --force lifts any lock"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest --lock T1 > /dev/null 2>&1
  "$KGSM_ROOT/kgsm.sh" instances unlock "$instance" --lock T1 > /dev/null 2>&1
  assert_equals "0" "$?" "The holder should be able to unlock"
  assert_equals "" "$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" transfer_lock 2> /dev/null)" \
    "The lock key should be gone"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest --lock T3 > /dev/null 2>&1
  "$KGSM_ROOT/kgsm.sh" instances unlock "$instance" --force > /dev/null 2>&1
  assert_equals "0" "$?" "--force should release any lock"

  "$KGSM_ROOT/kgsm.sh" instances unlock "$instance" --lock T1 > /dev/null 2>&1
  assert_equals "0" "$?" "Unlocking an instance that is not locked succeeds"
}

function test_lock_keys_are_not_settable() {
  log_test_step "Testing that config-set cannot forge or clear the lock"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances config-set "$instance" "transfer_lock=forged" > /dev/null 2>&1
  assert_not_equals "0" "$?" "transfer_lock is protected"
  "$KGSM_ROOT/kgsm.sh" instances config-set "$instance" "transfer_lock_autostart=true" > /dev/null 2>&1
  assert_not_equals "0" "$?" "transfer_lock_autostart is protected"
}

# =============================================================================
# THE ROUND TRIP
# =============================================================================

function test_round_trip_builds_a_new_instance_in_the_target_library() {
  log_test_step "Testing export, import and commit end to end"

  local instance
  instance="$(_make_instance factorio)"
  "$KGSM_ROOT/kgsm.sh" instances rename "$instance" "Survival" > /dev/null 2>&1

  local new_instance
  new_instance="$(_transfer_to_target "$instance" T1)"
  assert_not_null "$new_instance" "Import should report the new instance"
  assert_not_equals "$instance" "$new_instance" "The target gives the server a fresh id"

  local new_working_dir="${TARGET_ROOT}/instances/factorio/${new_instance}"
  assert_file_exists "${new_working_dir}/install/marker" "The install tree should have arrived"
  assert_file_exists "${new_working_dir}/saves/world" "The saves should have arrived"
  assert_file_exists "${new_working_dir}/${new_instance}.config.ini" \
    "The config should carry the new id"
  assert_file_exists "${new_working_dir}/${new_instance}.manage.sh" \
    "The management file should be regenerated under the new id"

  local config_file="${new_working_dir}/${new_instance}.config.ini"
  assert_file_contains "$config_file" "name=\"${new_instance}\"" "The config names the new instance"
  assert_file_contains "$config_file" "working_dir=\"${new_working_dir}\"" \
    "working_dir should name the new tree"
  assert_file_contains "$config_file" "library_dir=\"${TARGET_ROOT}\"" \
    "library_dir should name the target library"
  assert_file_contains "$config_file" "display_name=\"Survival\"" "The display name travels"

  assert_equals "0" "$(grep -c "${SOURCE_ROOT}" "$config_file" || true)" \
    "No line should still point into the source library"
  assert_equals "" "$("$KGSM_ROOT/kgsm.sh" instances config-get "$new_instance" transfer_lock 2> /dev/null)" \
    "The new instance is not locked"
  assert_equals "$new_working_dir" "$(readlink "${KGSM_INSTANCES_DIR}/factorio/${new_instance}")" \
    "The registry should point at the new tree"
  assert_dir_not_exists "${TARGET_ROOT}/.kgsm-import" "Finishing should remove the staging"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --commit --lock T1 > /dev/null 2>&1
  assert_equals "0" "$?" "The commit should succeed"
  assert_dir_not_exists "${SOURCE_ROOT}/instances/factorio/${instance}" \
    "The source tree should be gone after the commit"
  assert_file_not_exists "${KGSM_INSTANCES_DIR}/factorio/${instance}" \
    "The source should no longer be registered"
  assert_file_exists "${new_working_dir}/install/marker" "The new instance should be untouched"
}

function test_round_trip_carries_the_backups() {
  log_test_step "Testing that a backup travels into the target's backup location"

  local instance
  instance="$(_make_instance factorio)"

  local backups_dir
  backups_dir="$("$KGSM_ROOT/kgsm.sh" instances config-get "$instance" backups_dir)"
  mkdir -p "${backups_dir}/${instance}-backup-1"
  echo "saved" > "${backups_dir}/${instance}-backup-1/data"

  local new_instance
  new_instance="$(_transfer_to_target "$instance" T1)"
  assert_not_null "$new_instance" "Import should succeed"

  local new_backups_dir
  new_backups_dir="$("$KGSM_ROOT/kgsm.sh" instances config-get "$new_instance" backups_dir)"
  assert_not_equals "$backups_dir" "$new_backups_dir" "The backups belong to the new id"
  assert_file_exists "${new_backups_dir}/${instance}-backup-1/data" \
    "The backup should have arrived"
}

function test_import_aborts_when_a_part_is_missing() {
  log_test_step "Testing that finish refuses an import whose tree never arrived"

  local instance
  instance="$(_make_instance factorio)"

  local import_id
  import_id="$(_manifest_without_ports "$instance" T1 |
    "$KGSM_ROOT/kgsm.sh" instances import begin --library "$TARGET_LIBRARY" --json 2> /dev/null |
    jq -r '.import_id')"

  "$KGSM_ROOT/kgsm.sh" instances import finish "$import_id" > /dev/null 2>&1
  assert_equals "$EC_TRANSFER_INTEGRITY" "$?" "A missing part is an integrity failure"

  "$KGSM_ROOT/kgsm.sh" instances import part nope tree < /dev/null > /dev/null 2>&1
  assert_equals "$EC_IMPORT_NOT_FOUND" "$?" "An unknown import is not found"
}

# =============================================================================
# THE PREFLIGHT
# =============================================================================

function test_check_lists_every_refusal() {
  log_test_step "Testing that the preflight reports all refusals at once"

  local instance
  instance="$(_make_instance factorio)"

  local manifest verdict
  manifest="$("$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest 2> /dev/null |
    jq '.engine_version = "0.0.0"')"

  verdict="$("$KGSM_ROOT/kgsm.sh" instances import check --library "$TARGET_LIBRARY" --json \
    <<< "$manifest" 2> /dev/null)"
  local exit_code=$?

  assert_equals "$EC_ENGINE_VERSION_MISMATCH" "$exit_code" "The first refusal sets the exit code"
  assert_equals "false" "$(jq -r '.ok' <<< "$verdict")" "The verdict is a refusal"
  assert_contains "$(jq -r '[.refusals[].code] | join(",")' <<< "$verdict")" "engine_version_mismatch" \
    "The version mismatch is listed"
  assert_contains "$(jq -r '[.refusals[].code] | join(",")' <<< "$verdict")" "port_conflict" \
    "The port the source still holds is listed beside it"
}

function test_check_accepts_a_manifest_the_host_can_take() {
  log_test_step "Testing that the preflight writes nothing and accepts a good manifest"

  local instance
  instance="$(_make_instance factorio)"

  local verdict
  verdict="$(_manifest_without_ports "$instance" T1 |
    "$KGSM_ROOT/kgsm.sh" instances import check --library "$TARGET_LIBRARY" --json 2> /dev/null)"
  assert_equals "0" "$?" "A host that can take the instance accepts it"
  assert_equals "true" "$(jq -r '.ok' <<< "$verdict")" "The verdict is an acceptance"
  assert_dir_not_exists "${TARGET_ROOT}/.kgsm-import" "A check stages nothing"
}

function test_begin_stages_nothing_when_the_check_refuses() {
  log_test_step "Testing that a refused begin leaves no staging behind"

  local instance
  instance="$(_make_instance factorio)"

  "$KGSM_ROOT/kgsm.sh" instances export "$instance" --manifest 2> /dev/null |
    "$KGSM_ROOT/kgsm.sh" instances import begin --library "$TARGET_LIBRARY" --json > /dev/null 2>&1
  assert_equals "$EC_PORT_CONFLICT" "$?" "The source's own ports refuse the import on one machine"
  assert_dir_not_exists "${TARGET_ROOT}/.kgsm-import" "Nothing should be staged"
}

# =============================================================================
# ABORT AND LIST
# =============================================================================

function test_list_shows_a_staged_import_and_abort_removes_it() {
  log_test_step "Testing import list and import abort"

  local instance
  instance="$(_make_instance factorio)"

  local import_id
  import_id="$(_manifest_without_ports "$instance" T1 |
    "$KGSM_ROOT/kgsm.sh" instances import begin --library "$TARGET_LIBRARY" --json 2> /dev/null |
    jq -r '.import_id')"
  assert_not_null "$import_id" "Begin should stage an import"
  assert_dir_exists "${TARGET_ROOT}/.kgsm-import/${import_id}" "The staging should exist"

  local listed
  listed="$("$KGSM_ROOT/kgsm.sh" instances import list --json 2> /dev/null)"
  assert_equals "$instance" \
    "$(jq -r --arg id "$import_id" '.[] | select(.import_id == $id) | .instance' <<< "$listed")" \
    "The list names the instance the staged import came from"
  assert_equals "$TARGET_LIBRARY" \
    "$(jq -r --arg id "$import_id" '.[] | select(.import_id == $id) | .library' <<< "$listed")" \
    "The list names the library it is staged in"

  "$KGSM_ROOT/kgsm.sh" instances import abort "$import_id" > /dev/null 2>&1
  assert_equals "0" "$?" "Abort should succeed"
  assert_dir_not_exists "${TARGET_ROOT}/.kgsm-import/${import_id}" "Abort removes the staging"

  "$KGSM_ROOT/kgsm.sh" instances import abort "$import_id" > /dev/null 2>&1
  assert_equals "0" "$?" "Aborting an unknown import succeeds"
}

# =============================================================================
# REQUIREMENTS
# =============================================================================

function test_requirements_reports_what_a_blueprint_declares() {
  log_test_step "Testing blueprints requirements"

  local result
  result="$("$KGSM_ROOT/kgsm.sh" blueprints requirements factorio --json 2> /dev/null)"
  assert_equals "0" "$?" "A blueprint that declares nothing is satisfied"
  assert_equals "0" "$(jq -r '.requirements | length' <<< "$result")" \
    "Factorio declares no host requirement"

  "$KGSM_ROOT/kgsm.sh" blueprints requirements nonexistent-blueprint > /dev/null 2>&1
  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$?" "An unknown blueprint is not found"
}
