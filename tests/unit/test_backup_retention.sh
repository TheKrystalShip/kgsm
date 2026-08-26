#!/usr/bin/env bash

# KGSM Backup Reason & Retention Tests
#
# Test Type: UNIT
# Target: templates/manage.*.d/08-backup.sh - _create_backup, _set_backup_retention
#         commands/instances.sh             - _cmd_prune_backups, pin/unpin
#
# A backup records WHY it was taken and WHETHER rotation may take it. The two are
# separate on purpose: the reason is a fact fixed at capture, the retention is a
# policy an operator revises, and a slot they shared could never diverge.
#
# These drive the management file directly with an explicit --run-state, as the
# consistency tests do — the CLI resolves that from the watchdog, which is not
# reachable in the sandbox.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="backup_retention"
readonly MODULE="$KGSM_ROOT/commands/instances.sh"

TEST_INSTALL_DIR=""
_TEARDOWN_INSTANCES=()

# =============================================================================
# HELPERS
# =============================================================================

# Where an instance's working tree and its backups store live in these tests.
# They are deliberately siblings rather than nested: the CLI repoints any
# instance whose backups sit INSIDE its working directory at the canonical
# out-of-tree path, and a test whose store moved out from under it would be
# asserting against an empty directory.
function _root_of() {
  echo "$TEST_INSTALL_DIR/${1}-root"
}

function _backups_of() {
  echo "$TEST_INSTALL_DIR/${1}-backups"
}

# Provision a created instance so its management file can actually build a
# backup: real install/saves subtrees under a working dir, a temp dir to stage
# in, and a backups dir to publish into. 01-config sources every config line
# with last-wins semantics, so appending them takes effect at runtime.
#
# Args: $1 = instance
function _provision_backup_instance() {
  local instance_name="$1"

  local cfg
  cfg=$("$MODULE" find "$instance_name" 2>/dev/null)
  [[ -f "$cfg" ]] || return 1

  local root backups
  root=$(_root_of "$instance_name")
  backups=$(_backups_of "$instance_name")

  mkdir -p "$root/install" "$root/saves" "$root/temp" "$backups" || return 1
  echo "game binary" > "$root/install/server.bin"
  echo "the world" > "$root/saves/world.dat"
  echo "1.0.0" > "$root/version.txt"

  {
    printf 'working_dir="%s"\n' "$root"
    printf 'install_dir="%s"\n' "$root/install"
    printf 'saves_dir="%s"\n' "$root/saves"
    printf 'temp_dir="%s"\n' "$root/temp"
    printf 'backups_dir="%s"\n' "$backups"
    printf 'version_file="%s"\n' "$root/version.txt"
    printf 'compress_backups="false"\n'
    printf 'save_command=""\n'
  } >> "$cfg"
}

function _management_file_of() {
  local instance_name="$1"
  local cfg
  cfg=$("$MODULE" find "$instance_name" 2>/dev/null)
  [[ -f "$cfg" ]] || return 1
  grep -oP '^management_file="\K[^"]*' "$cfg" | tail -n1
}

# Create one backup and echo its id. Extra arguments go to create-backup.
function _make_backup() {
  local instance_name="$1"
  shift

  local mgmt
  mgmt=$(_management_file_of "$instance_name") || return 1
  "$mgmt" create-backup --run-state inactive "$@" 2>/dev/null | tail -n1
}

function _manifest_of() {
  local instance_name="$1"
  local backup_id="$2"
  cat "$(_backups_of "$instance_name")/$backup_id/manifest.json" 2>/dev/null
}

# Strip the pin-backup verb out of a generated management file's help, which is
# the token the CLI reads to decide whether the file records these fields. That
# reproduces the gate an instance generated before they existed hits, without
# needing an old KGSM to generate one. Only the CLI's decision is simulated — the
# file below it still writes what a current one writes.
function _blind_management_file() {
  local instance_name="$1"
  local mgmt
  mgmt=$(_management_file_of "$instance_name") || return 1
  sed -i 's/^  pin-backup <id>.*$//; s/^  unpin-backup <id>.*$//' "$mgmt"
}

function _new_instance() {
  local instance_name="$1"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" > /dev/null 2>&1 || return 1
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")
}

# A backup as it looked before the manifest carried either field: the two keys
# removed and the schema version put back to 1. This is what every backup on a
# host that predates the fields actually looks like.
function _downgrade_to_v1() {
  local instance_name="$1"
  local backup_id="$2"
  local manifest
  manifest="$(_backups_of "$instance_name")/$backup_id/manifest.json"

  jq 'del(.reason, .retention) | .schema_version = 1' "$manifest" > "${manifest}.v1" &&
    mv "${manifest}.v1" "$manifest"
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up backup reason and retention tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "instances.sh command should exist"
}

function setup() {
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" > /dev/null 2>&1
  done
  _TEARDOWN_INSTANCES=()
}

function test_a_backup_records_a_reason_and_a_retention() {
  log_test_step "Testing a backup states why it was taken and whether it may be pruned"

  local instance_name="test-br-default-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  _provision_backup_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be provisioned"

  local backups
  backups=$(_backups_of "$instance_name")

  local backup_id manifest
  backup_id=$(_make_backup "$instance_name")
  assert_not_null "$backup_id" "a backup should have been created"

  manifest=$(_manifest_of "$instance_name" "$backup_id")
  assert_equals "2" "$(printf '%s' "$manifest" | jq -r '.schema_version')" \
    "a manifest carrying both fields declares schema version 2"
  # An ad-hoc request that states nothing else is a manual capture: it belongs
  # to no update, no restore and no announced cadence.
  assert_equals "manual" "$(printf '%s' "$manifest" | jq -r '.reason')" \
    "an unqualified create-backup records a manual reason"
  assert_equals "prunable" "$(printf '%s' "$manifest" | jq -r '.retention')" \
    "a backup is prunable unless something says otherwise"
}

function test_a_stated_reason_and_retention_are_recorded() {
  log_test_step "Testing a stated reason and retention reach the manifest"

  local instance_name="test-br-stated-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  local backup_id manifest
  backup_id=$(_make_backup "$instance_name" --reason incident --retention pinned)
  assert_not_null "$backup_id" "a backup should have been created"

  manifest=$(_manifest_of "$instance_name" "$backup_id")
  assert_equals "incident" "$(printf '%s' "$manifest" | jq -r '.reason')" \
    "the stated reason is recorded"
  assert_equals "pinned" "$(printf '%s' "$manifest" | jq -r '.retention')" \
    "the stated retention is recorded"
}

function test_an_unknown_reason_is_refused_before_anything_is_archived() {
  log_test_step "Testing an unknown reason publishes nothing rather than an unlabelled backup"

  local instance_name="test-br-badreason-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  # A word no consumer recognises in the one record of what a backup is would be
  # worse than no word: it reads as a classification without being one.
  "$mgmt" create-backup --run-state inactive --reason whenever > /dev/null 2>&1
  assert_not_equals 0 "$?" "an unknown reason should be refused"

  local published
  published=$(find "$backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
  assert_equals 0 "$published" "no backup should have been published"
}

function test_a_pre_restore_safety_backup_says_so() {
  log_test_step "Testing the safety archive a restore takes is identifiable as one"

  local instance_name="test-br-prerestore-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  local mgmt backup_id
  mgmt=$(_management_file_of "$instance_name")
  backup_id=$(_make_backup "$instance_name")
  assert_not_null "$backup_id" "a backup should exist to restore from"

  "$mgmt" restore-backup "$backup_id" --run-state inactive > /dev/null 2>&1
  assert_equals 0 "$?" "the restore should succeed"

  local safety_dir
  safety_dir=$(find "$backups" -mindepth 1 -maxdepth 1 -type d \
    ! -name "$backup_id" 2>/dev/null | head -n1)
  assert_not_null "$safety_dir" "the restore should have taken a safety backup"
  # Without the reason this archive is indistinguishable from a routine one, and
  # it is what somebody reaches for when the restore was the mistake.
  assert_equals "pre-restore" "$(jq -r '.reason' "$safety_dir/manifest.json" 2>/dev/null)" \
    "the safety archive records that a restore took it"
}

function test_pin_and_unpin_change_the_policy_and_not_the_fact() {
  log_test_step "Testing pinning flips the retention and leaves the reason alone"

  local instance_name="test-br-pin-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  local mgmt backup_id
  mgmt=$(_management_file_of "$instance_name")
  backup_id=$(_make_backup "$instance_name" --reason scheduled)
  assert_not_null "$backup_id" "a backup should have been created"

  "$mgmt" pin-backup "$backup_id" > /dev/null 2>&1
  assert_equals 0 "$?" "pinning should succeed"
  assert_equals "pinned" "$(_manifest_of "$instance_name" "$backup_id" | jq -r '.retention')" \
    "the backup should now be pinned"
  # The reason is a fact about how the archive was produced; a fact that can be
  # rewritten is not one.
  assert_equals "scheduled" "$(_manifest_of "$instance_name" "$backup_id" | jq -r '.reason')" \
    "pinning must not touch why the backup was taken"

  "$mgmt" unpin-backup "$backup_id" > /dev/null 2>&1
  assert_equals 0 "$?" "unpinning should succeed"
  assert_equals "prunable" "$(_manifest_of "$instance_name" "$backup_id" | jq -r '.retention')" \
    "the backup should be prunable again"
}

function test_a_manifest_without_the_fields_reads_back_as_prunable_and_unknown() {
  log_test_step "Testing a manifest predating the fields reads prunable, with no reason invented"

  local instance_name="test-br-v1-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  local mgmt backup_id
  mgmt=$(_management_file_of "$instance_name")
  backup_id=$(_make_backup "$instance_name")
  _downgrade_to_v1 "$instance_name" "$backup_id"
  assert_equals 0 "$?" "the manifest should have been downgraded"

  local listing
  listing=$("$mgmt" backups --json 2>/dev/null)
  assert_not_null "$listing" "the backup should still be listed"

  # Absent retention IS prunable — that is what the field's absence means, and it
  # is the behaviour the backup already had, so nothing changes for one that
  # already exists.
  assert_equals "prunable" \
    "$(printf '%s' "$listing" | jq -r --arg id "$backup_id" '.[] | select(.id == $id) | .retention')" \
    "a manifest with no retention reads as prunable"
  # Absent reason stays null. Which archive this was cannot be recovered after
  # the fact, and a filled-in guess would be read as a measurement.
  assert_equals "null" \
    "$(printf '%s' "$listing" | jq -r --arg id "$backup_id" '.[] | select(.id == $id) | .reason')" \
    "a manifest with no reason reads as unknown rather than a guess"
}

function test_pinning_an_old_manifest_upgrades_it_without_inventing_a_reason() {
  log_test_step "Testing pinning a manifest that predates the fields records a null reason"

  local instance_name="test-br-v1pin-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  local mgmt backup_id
  mgmt=$(_management_file_of "$instance_name")
  backup_id=$(_make_backup "$instance_name")
  _downgrade_to_v1 "$instance_name" "$backup_id"

  "$mgmt" pin-backup "$backup_id" > /dev/null 2>&1
  assert_equals 0 "$?" "pinning an old manifest should succeed"

  local manifest
  manifest=$(_manifest_of "$instance_name" "$backup_id")
  assert_equals "pinned" "$(printf '%s' "$manifest" | jq -r '.retention')" \
    "the old backup should now be pinned"
  assert_equals "2" "$(printf '%s' "$manifest" | jq -r '.schema_version')" \
    "a manifest carrying both keys declares schema version 2"
  assert_equals "null" "$(printf '%s' "$manifest" | jq -r '.reason')" \
    "the upgrade records that this backup does not say why it was taken"
}

function test_prune_skips_pinned_backups_and_does_not_count_them() {
  log_test_step "Testing a pinned backup survives a prune and does not consume a keep slot"

  local instance_name="test-br-prune-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  # Four backups, oldest first. The oldest is pinned, so a --keep=2 sweep must
  # keep the two newest PRUNABLE ones plus the pin, and delete exactly the one
  # prunable backup left over.
  local oldest second third newest
  oldest=$(_make_backup "$instance_name" --reason incident --retention pinned)
  sleep 1
  second=$(_make_backup "$instance_name")
  sleep 1
  third=$(_make_backup "$instance_name")
  sleep 1
  newest=$(_make_backup "$instance_name")

  assert_not_null "$oldest" "the pinned backup should have been created"
  assert_not_null "$newest" "the newest backup should have been created"
  assert_equals 4 "$(find "$backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" \
    "four backups should be present before the sweep"

  "$MODULE" prune-backups "$instance_name" --keep=2 > /dev/null 2>&1
  assert_equals 0 "$?" "the prune should succeed"

  # Had the pin counted toward the window, it would have kept only ONE prunable
  # backup — the rotation eroding exactly as more of it was protected.
  assert_dir_exists "$backups/$oldest" "the pinned backup must survive"
  assert_dir_exists "$backups/$third" "the second-newest prunable backup is kept"
  assert_dir_exists "$backups/$newest" "the newest prunable backup is kept"
  assert_equals "false" "$([[ -d "$backups/$second" ]] && echo true || echo false)" \
    "the prunable backup outside the window is deleted"
}

function test_prune_holds_back_the_newest_pre_update_backup() {
  log_test_step "Testing the rollback point survives a prune and does not consume a keep slot"

  local instance_name="test-br-rollback-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  # Four backups, oldest first, one of them the archive an update took on its
  # way in. A --keep=2 sweep keeps the two newest of what is left once that one
  # is set aside, so the oldest is the only casualty.
  local oldest rollback third newest
  oldest=$(_make_backup "$instance_name")
  sleep 1
  rollback=$(_make_backup "$instance_name" --reason pre-update)
  sleep 1
  third=$(_make_backup "$instance_name")
  sleep 1
  newest=$(_make_backup "$instance_name")

  assert_not_null "$rollback" "the pre-update backup should have been created"

  "$MODULE" prune-backups "$instance_name" --keep=2 > /dev/null 2>&1
  assert_equals 0 "$?" "the prune should succeed"

  assert_dir_exists "$backups/$rollback" "the rollback point must survive"
  assert_dir_exists "$backups/$third" "the second-newest prunable backup is kept"
  assert_dir_exists "$backups/$newest" "the newest prunable backup is kept"
  assert_equals "false" "$([[ -d "$backups/$oldest" ]] && echo true || echo false)" \
    "the prunable backup outside the window is deleted"
}

function test_prune_holds_back_one_pre_update_backup_not_a_set() {
  log_test_step "Testing only the most recent pre-update backup is held back"

  local instance_name="test-br-rollback1-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  # Two updates' worth of rollback points. Only the newest is the one an
  # operator would roll back to, so the older one rotates like any other backup.
  local stale_rollback filler rollback newest
  stale_rollback=$(_make_backup "$instance_name" --reason pre-update)
  sleep 1
  filler=$(_make_backup "$instance_name")
  sleep 1
  rollback=$(_make_backup "$instance_name" --reason pre-update)
  sleep 1
  newest=$(_make_backup "$instance_name")

  assert_not_null "$filler" "the intervening backup should have been created"

  "$MODULE" prune-backups "$instance_name" --keep=2 > /dev/null 2>&1
  assert_equals 0 "$?" "the prune should succeed"

  assert_dir_exists "$backups/$rollback" "the most recent rollback point must survive"
  assert_dir_exists "$backups/$newest" "the newest prunable backup is kept"
  assert_dir_exists "$backups/$filler" "the second-newest prunable backup is kept"
  assert_equals "false" "$([[ -d "$backups/$stale_rollback" ]] && echo true || echo false)" \
    "the superseded rollback point rotates like any other backup"
}

function test_delete_still_removes_a_pinned_backup() {
  log_test_step "Testing pinned stops the rotation, never the operator"

  local instance_name="test-br-del-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")

  local backup_id
  backup_id=$(_make_backup "$instance_name" --retention pinned)
  assert_not_null "$backup_id" "a pinned backup should have been created"

  "$MODULE" delete-backup "$instance_name" "$backup_id" > /dev/null 2>&1
  assert_equals 0 "$?" "deleting a pinned backup by name should succeed"
  assert_equals "false" "$([[ -d "$backups/$backup_id" ]] && echo true || echo false)" \
    "a pinned backup named by an operator is removed like any other"
}

function test_a_reason_an_old_management_file_cannot_record_is_dropped_not_fatal() {
  log_test_step "Testing a stated reason still yields a backup when the instance cannot record one"

  local instance_name="test-br-oldreason-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")
  _blind_management_file "$instance_name"

  # A cadence runs unattended against instances nobody has regenerated. Refusing
  # would cost the backup to save the label, which is the wrong way round: the
  # manifest simply records no reason, and that reads back as unknown.
  "$MODULE" create-backup "$instance_name" --reason=scheduled > /dev/null 2>&1
  assert_equals 0 "$?" "a backup should still be taken"

  assert_equals 1 "$(find "$backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" \
    "exactly one backup should have been published"

  local manifest
  manifest=$(find "$backups" -mindepth 2 -maxdepth 2 -name manifest.json | head -n1)
  assert_not_null "$manifest" "the backup should carry a manifest"
  # The flag was dropped rather than forwarded to a file that could not act on
  # it. Against a genuinely old management file the manifest then holds no reason
  # at all, which reads back as unknown.
  assert_not_equals "scheduled" "$(jq -r '.reason // "null"' "$manifest" 2>/dev/null)" \
    "the stated reason must not be forwarded to a file that cannot record it"
}

function test_a_retention_an_old_management_file_cannot_honour_is_refused() {
  log_test_step "Testing a stated retention is refused rather than silently dropped"

  local instance_name="test-br-oldpin-$$"
  _new_instance "$instance_name"
  _provision_backup_instance "$instance_name"

  local backups
  backups=$(_backups_of "$instance_name")
  _blind_management_file "$instance_name"

  # Unlike a reason, this changes behaviour: a caller told the archive is
  # protected from rotation and handed a prunable one has been set up for exactly
  # the loss pinning exists to prevent.
  "$MODULE" create-backup "$instance_name" --retention=pinned > /dev/null 2>&1
  assert_not_equals 0 "$?" "a retention that cannot be honoured should be refused"

  assert_equals 0 "$(find "$backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" \
    "no backup should have been published"
}
