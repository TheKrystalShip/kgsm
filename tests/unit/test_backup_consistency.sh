#!/usr/bin/env bash

# KGSM Backup Consistency Tests
#
# Test Type: UNIT
# Target: templates/manage.*.d/08-backup.sh - _create_backup
#
# A backup records the state it was captured in (cold / flushed / hot, or no
# claim at all) and chooses what to capture from that same state. Both are
# measured per backup, so these tests drive the management file directly with an
# explicit --run-state rather than through the CLI, which resolves the state from
# the watchdog and cannot reach one in the sandbox.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="backup_consistency"
readonly MODULE="$KGSM_ROOT/commands/instances.sh"

TEST_INSTALL_DIR=""
_TEARDOWN_INSTANCES=()

# =============================================================================
# HELPERS
# =============================================================================

# Provision a created instance so its management file can actually build a
# backup: real install/saves subtrees under a working dir, a temp dir to stage
# in, and a backups dir to publish into. A freshly created test instance skips
# the directory step, so these keys are empty; 01-config sources every config
# line with last-wins semantics, so appending them takes effect at runtime.
#
# Args: $1 = instance, $2 = root, $3 = install content?, $4 = saves content?
function _provision_backup_instance() {
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
  } >> "$cfg"
}

# Set the save/stop command pair on an instance.
function _set_commands() {
  local instance_name="$1"
  local save_cmd="$2"
  local stop_cmd="$3"

  local cfg
  cfg=$("$MODULE" find "$instance_name" 2>/dev/null)
  [[ -f "$cfg" ]] || return 1

  {
    printf 'save_command="%s"\n' "$save_cmd"
    printf 'stop_command="%s"\n' "$stop_cmd"
  } >> "$cfg"
}

function _management_file_of() {
  local instance_name="$1"
  local cfg
  cfg=$("$MODULE" find "$instance_name" 2>/dev/null)
  [[ -f "$cfg" ]] || return 1
  grep -oP '^management_file="\K[^"]*' "$cfg" | tail -n1
}

# Run create-backup with an explicit run state and echo the new manifest.
function _backup_manifest() {
  local instance_name="$1"
  local run_state="$2"
  local root="$3"

  local mgmt backup_id
  mgmt=$(_management_file_of "$instance_name") || return 1
  backup_id=$("$mgmt" create-backup --run-state "$run_state" 2>/dev/null | tail -n1) || return 1
  [[ -n "$backup_id" ]] || return 1
  cat "$root/backups/$backup_id/manifest.json" 2>/dev/null
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
  log_test_step "Setting up backup consistency tests"

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

function test_stopped_instance_records_cold() {
  log_test_step "Testing a backup of a stopped instance records consistency=cold"

  local instance_name="test-bk-cold-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_backup_instance "$instance_name" "$root" yes yes
  assert_equals 0 "$?" "Instance should be provisioned"

  local manifest
  manifest=$(_backup_manifest "$instance_name" inactive "$root")
  assert_not_null "$manifest" "a backup should have been created"
  assert_equals "cold" "$(printf '%s' "$manifest" | jq -r '.consistency')" \
    "a stopped instance yields a cold backup"
}

function test_running_without_save_command_records_hot() {
  log_test_step "Testing a running instance with no save command records consistency=hot"

  local instance_name="test-bk-hot-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_backup_instance "$instance_name" "$root" yes yes
  _set_commands "$instance_name" "" "quit"

  local manifest
  manifest=$(_backup_manifest "$instance_name" active "$root")
  assert_not_null "$manifest" "a backup should have been created"
  # Nothing could be told to flush, so the archive may be torn and says so.
  assert_equals "hot" "$(printf '%s' "$manifest" | jq -r '.consistency')" \
    "a running instance with no save command yields a hot backup"
}

function test_save_command_equal_to_stop_command_is_not_a_flush() {
  log_test_step "Testing a save command identical to the stop command is refused as a flush"

  local instance_name="test-bk-exit-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_backup_instance "$instance_name" "$root" yes yes
  # Some blueprints declare both as "exit". Issuing it to flush would shut the
  # server down to back it up, so it is not a usable save command and the
  # backup must not claim it was flushed.
  _set_commands "$instance_name" "exit" "exit"

  local manifest
  manifest=$(_backup_manifest "$instance_name" active "$root")
  assert_not_null "$manifest" "a backup should have been created"
  assert_equals "hot" "$(printf '%s' "$manifest" | jq -r '.consistency')" \
    "a save command equal to the stop command yields hot, never flushed"
}

function test_indeterminate_run_state_claims_nothing() {
  log_test_step "Testing an unknown run state records no consistency rather than guessing"

  local instance_name="test-bk-unknown-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_backup_instance "$instance_name" "$root" yes yes

  local manifest
  manifest=$(_backup_manifest "$instance_name" unknown "$root")
  assert_not_null "$manifest" "a backup should still have been created"
  # Null, not "cold": an unreachable watchdog means the state was never
  # measured, and a fabricated cold would be read as a consistency guarantee.
  assert_equals "null" "$(printf '%s' "$manifest" | jq -r '.consistency')" \
    "an indeterminate run state records a null consistency"
}

function test_running_backup_captures_saves_only() {
  log_test_step "Testing a running backup captures saves/ alone when it has content"

  local instance_name="test-bk-saves-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_backup_instance "$instance_name" "$root" yes yes

  local manifest sources
  manifest=$(_backup_manifest "$instance_name" active "$root")
  assert_not_null "$manifest" "a backup should have been created"

  sources=$(printf '%s' "$manifest" | jq -r '.sources | join(",")')
  # install/ is re-downloadable and is the bulk of a game; skipping it is what
  # keeps a frequent cadence affordable.
  assert_equals "saves" "$sources" \
    "a running backup captures saves/ only"
}

function test_running_backup_falls_back_to_full_capture_when_saves_empty() {
  log_test_step "Testing a running backup captures everything when saves/ is empty"

  local instance_name="test-bk-nosaves-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_backup_instance "$instance_name" "$root" yes no

  local manifest sources
  manifest=$(_backup_manifest "$instance_name" active "$root")
  assert_not_null "$manifest" "a backup should have been created"

  sources=$(printf '%s' "$manifest" | jq -r '.sources | join(",")')
  # Several games keep their world inside install/. Capturing saves/ alone would
  # back up nothing of value, so the whole tree is taken instead.
  assert_equals "install" "$sources" \
    "an empty saves/ falls back to capturing install/"
}

function test_backup_with_nothing_to_capture_fails() {
  log_test_step "Testing a backup with no content to capture fails instead of reporting success"

  local instance_name="test-bk-empty-$$"
  _new_instance "$instance_name"
  assert_equals 0 "$?" "Instance should be created"

  local root="$TEST_INSTALL_DIR/${instance_name}-root"
  _provision_backup_instance "$instance_name" "$root" no no

  local mgmt
  mgmt=$(_management_file_of "$instance_name")
  assert_not_null "$mgmt" "the instance should have a management file"

  # A success that produced no backup would advance a scheduled run's "last
  # backup" and report protection that does not exist.
  "$mgmt" create-backup --run-state inactive > /dev/null 2>&1
  assert_not_equals 0 "$?" "a backup with nothing to capture should fail"

  local published
  published=$(find "$root/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
  assert_equals 0 "$published" "no backup should have been published"
}
