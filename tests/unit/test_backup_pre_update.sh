#!/usr/bin/env bash

# KGSM Pre-Update Backup Tests
#
# Test Type: UNIT
# Target: templates/manage.*.d/12-commands.sh - _update
#         templates/manage.*.d/08-backup.sh  - _restore_backup
#
# An update replaces the installed game in place, so it archives what it is
# about to overwrite first and abandons the update if that archive cannot be
# made. A restart is not an update and takes no backup; neither does an update
# that finds the instance already current.
#
# _update's version lookup and download are the only parts that reach the
# network, so they are replaced in the generated management file (see
# _stub_update_path) and everything else runs for real.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="backup_pre_update"
readonly MODULE="$KGSM_ROOT/commands/instances.sh"

TEST_INSTALL_DIR=""
_TEARDOWN_INSTANCES=()

# =============================================================================
# HELPERS
# =============================================================================

# Provision a created instance so its management file can build a backup: real
# install/saves subtrees under a working dir, a temp dir to stage in, a backups
# dir to publish into, and an installed version to update away from. 01-config
# sources every config line with last-wins semantics, so appending takes effect.
#
# Args: $1 = instance, $2 = root, $3 = install content?, $4 = saves content?
function _provision_instance() {
  local instance_name="$1"
  local root="$2"
  local with_install="$3"
  local with_saves="$4"

  local cfg
  cfg=$("$MODULE" find "$instance_name" 2>/dev/null)
  [[ -f "$cfg" ]] || return 1

  mkdir -p "$root/install" "$root/saves" "$root/temp" "$root/backups" || return 1
  [[ "$with_install" == "yes" ]] && echo "game binary" > "$root/install/server.bin"
  [[ "$with_saves" == "yes" ]] && echo "the world" > "$root/saves/world.dat"

  echo "1.0.0" > "$root/version.txt"

  {
    printf 'working_dir="%s"\n' "$root"
    printf 'install_dir="%s"\n' "$root/install"
    printf 'saves_dir="%s"\n' "$root/saves"
    printf 'temp_dir="%s"\n' "$root/temp"
    printf 'backups_dir="%s"\n' "$root/backups"
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

# Replace the two steps of _update that reach the network. The management file
# is one assembled script whose dispatch runs last, so definitions inserted just
# above it win over the module ones — _update's own logic still runs verbatim.
# _download and _deploy append to a marker file so a test can tell whether the
# update actually got past the backup.
#
# Args: $1 = instance, $2 = version to report as latest, $3 = marker file
function _stub_update_path() {
  local instance_name="$1"
  local latest="$2"
  local marker="$3"

  local mgmt
  mgmt=$(_management_file_of "$instance_name") || return 1
  [[ -f "$mgmt" ]] || return 1

  local stub
  stub=$(
    cat << EOF
function _get_latest_version() { echo "${latest}"; }
function _download() { echo "download" >> "${marker}"; return 0; }
function _deploy() { echo "deploy" >> "${marker}"; return 0; }
EOF
  )

  local tmp="${mgmt}.stubbed"
  awk -v stub="$stub" -v anchor='command="${1:-}"' '
    !inserted && index($0, anchor) == 1 { print stub; inserted = 1 }
    { print }
  ' "$mgmt" > "$tmp" || return 1

  mv "$tmp" "$mgmt" && chmod +x "$mgmt"
}

# Echo the number of published backups under an instance root.
function _backup_count() {
  local root="$1"
  find "$root/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l
}

# Echo the manifest of the only published backup under an instance root.
function _only_manifest() {
  local root="$1"
  local dir
  dir=$(find "$root/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)
  [[ -n "$dir" ]] || return 1
  cat "$dir/manifest.json" 2>/dev/null
}

function _new_instance() {
  local instance_name="$1"
  create_test_instance "factorio" "$instance_name" "$TEST_INSTALL_DIR" > /dev/null 2>&1 || return 1
  _TEARDOWN_INSTANCES+=("factorio:$instance_name")
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up pre-update backup tests"

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

function test_update_backs_up_before_applying() {
  log_test_step "Testing an update archives the instance before overwriting it"

  local instance_name="test-pu-applies-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_instance "$instance_name" "$root" yes yes
  assert_equals 0 "$?" "Instance should be provisioned"

  local marker="$root/update-steps"
  _stub_update_path "$instance_name" "2.0.0" "$marker"
  assert_equals 0 "$?" "The update path should be stubbed"

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  "$mgmt" update --run-state inactive > /dev/null 2>&1
  assert_equals 0 "$?" "the update should succeed"

  assert_equals 1 "$(_backup_count "$root")" \
    "the update should publish exactly one backup"
  assert_equals "2.0.0" "$(cat "$root/version.txt" 2>/dev/null)" \
    "the update should have been applied"
}

function test_pre_update_backup_records_the_state_it_was_given() {
  log_test_step "Testing the pre-update backup records the run state passed to update"

  local instance_name="test-pu-state-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_instance "$instance_name" "$root" yes yes

  local marker="$root/update-steps"
  _stub_update_path "$instance_name" "2.0.0" "$marker"

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  # A native instance's run state is resolved by the command layer and handed
  # down; the management file must carry it into the backup rather than fall
  # back to its own probe, which cannot see a watchdog-owned process. An
  # unreachable watchdog leaves the state unmeasured, and that has to reach the
  # manifest intact.
  "$mgmt" update --run-state unknown > /dev/null 2>&1
  assert_equals 0 "$?" "the update should succeed"

  local manifest
  manifest=$(_only_manifest "$root")
  assert_not_null "$manifest" "a backup should have been created"
  assert_equals "null" "$(printf '%s' "$manifest" | jq -r '.consistency')" \
    "the pre-update backup records the run state it was given"
}

function test_pre_update_backup_is_identifiable_as_one() {
  log_test_step "Testing the pre-update archive records that an update took it"

  local instance_name="test-pu-reason-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_instance "$instance_name" "$root" yes yes

  local marker="$root/update-steps"
  _stub_update_path "$instance_name" "2.0.0" "$marker"

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  "$mgmt" update --run-state inactive > /dev/null 2>&1
  assert_equals 0 "$?" "the update should succeed"

  local manifest
  manifest=$(_only_manifest "$root")
  assert_not_null "$manifest" "a backup should have been created"
  # This is the rollback point for the riskiest thing the engine does, and the
  # reason is the only thing on disk that identifies it: the id is opaque, and
  # recency cannot tell it from a capture of the state the update went on to
  # break.
  assert_equals "pre-update" "$(printf '%s' "$manifest" | jq -r '.reason')" \
    "the pre-update archive says an update took it"
  assert_equals "prunable" "$(printf '%s' "$manifest" | jq -r '.retention')" \
    "a pre-update archive is prunable; keeping one is the operator's call"
}

function test_update_refuses_a_running_instance() {
  log_test_step "Testing an update refuses an instance the caller reports running"

  local instance_name="test-pu-running-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_instance "$instance_name" "$root" yes yes

  local marker="$root/update-steps"
  _stub_update_path "$instance_name" "2.0.0" "$marker"

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  # Deploying over a running game copies onto its own open executable and fails
  # partway, leaving install/ half-replaced. _is_active cannot see a
  # watchdog-owned process, so the caller's answer is what makes this fire.
  "$mgmt" update --run-state active > /dev/null 2>&1
  assert_not_equals 0 "$?" "an update of a running instance should be refused"

  assert_equals 0 "$(_backup_count "$root")" \
    "a refused update should take no backup"
  assert_equals "false" "$([[ -f "$marker" ]] && echo true || echo false)" \
    "a refused update should not download or deploy"
}

function test_update_of_a_current_instance_takes_no_backup() {
  log_test_step "Testing an already-current instance is not backed up"

  local instance_name="test-pu-current-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_instance "$instance_name" "$root" yes yes

  local marker="$root/update-steps"
  # Latest matches what is installed, so there is nothing to overwrite.
  _stub_update_path "$instance_name" "1.0.0" "$marker"

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  "$mgmt" update --run-state inactive > /dev/null 2>&1
  assert_equals 0 "$?" "an already-current update is a successful no-op"

  # A backup per no-op update would churn retention and evict real history.
  assert_equals 0 "$(_backup_count "$root")" \
    "no backup should be taken when no update is applied"
}

function test_failed_backup_abandons_the_update() {
  log_test_step "Testing an update is abandoned when it cannot back up first"

  local instance_name="test-pu-abort-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  # Nothing to capture, so the backup fails.
  _provision_instance "$instance_name" "$root" no no

  local marker="$root/update-steps"
  _stub_update_path "$instance_name" "2.0.0" "$marker"

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  "$mgmt" update --run-state inactive > /dev/null 2>&1
  assert_not_equals 0 "$?" "the update should fail when the backup fails"

  # Laying a new version over an unprotected world is the outcome the
  # pre-update backup exists to prevent, so nothing may be downloaded either.
  assert_equals "false" "$([[ -f "$marker" ]] && echo true || echo false)" \
    "neither download nor deploy should have run"
  assert_equals "1.0.0" "$(cat "$root/version.txt" 2>/dev/null)" \
    "the installed version should be untouched"
}

function test_restore_safety_backup_records_the_state_it_was_given() {
  log_test_step "Testing the safety backup a restore takes records the given run state"

  local instance_name="test-pu-restore-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_instance "$instance_name" "$root" yes yes

  local mgmt backup_id
  mgmt=$(_management_file_of "$instance_name")
  backup_id=$("$mgmt" create-backup --run-state inactive 2>/dev/null | tail -n1)
  assert_not_null "$backup_id" "a backup should exist to restore from"

  # A restore overwrites the current data, so it archives that first. That
  # archive is subject to the same honesty rule as any other: an unmeasured
  # run state must record no consistency rather than a fabricated cold.
  "$mgmt" restore-backup "$backup_id" --run-state unknown > /dev/null 2>&1
  assert_equals 0 "$?" "the restore should succeed"

  local safety_dir
  safety_dir=$(find "$root/backups" -mindepth 1 -maxdepth 1 -type d \
    ! -name "$backup_id" 2>/dev/null | head -n1)
  assert_not_null "$safety_dir" "the restore should have taken a safety backup"
  assert_equals "null" "$(jq -r '.consistency' "$safety_dir/manifest.json" 2>/dev/null)" \
    "the safety backup records the run state it was given"
}
