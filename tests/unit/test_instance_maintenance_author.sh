#!/usr/bin/env bash

# KGSM Maintenance Window Author Unit Tests
#
# Test Type: UNIT
# Target: maintenance_windows_author, the account that wrote an instance's
# windows. A window runs only while its author may do what it does, so what is
# exercised here is that the author is written with the windows and nowhere
# else: named by --author, cleared by any write that names nobody, and never
# settable on its own.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instance_maintenance_author"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"

AUTHOR_TEST_DIR=""
AUTHOR_TEST_SEQ=0
CREATED_ID=""
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up maintenance window author tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"
}

function setup() {
  # Counted, not drawn: a library is named after its directory, and two tests
  # handed one directory would collide registering it.
  AUTHOR_TEST_SEQ=$((AUTHOR_TEST_SEQ + 1))
  AUTHOR_TEST_DIR="${KGSM_TEST_SANDBOX}/author_${AUTHOR_TEST_SEQ}_$$"
  mkdir -p "$AUTHOR_TEST_DIR"
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" "$AUTHOR_TEST_DIR" 2> /dev/null || true
  done

  "$KGSM_ROOT/kgsm.sh" libraries remove "$(__test_library_name "$AUTHOR_TEST_DIR")" \
    --force > /dev/null 2>&1 || true

  rm -rf "$AUTHOR_TEST_DIR"
}

function _fixture_failed() {
  assert_not_null "" "Test fixture: $1"
}

# Creates an instance through the command layer and records it for teardown.
# The id is left in CREATED_ID: a command substitution would run this in a
# subshell, and the teardown list would die with it.
function _create() {
  CREATED_ID=""

  local _library
  _library="$(__ensure_test_library "$AUTHOR_TEST_DIR")" || {
    _fixture_failed "registering a library at $AUTHOR_TEST_DIR"
    return 1
  }

  local _resolved_id
  _resolved_id="$("$INSTANCES_MODULE" generate-id factorio 2> /dev/null)" || {
    _fixture_failed "settling an id"
    return 1
  }

  setup_instance_prereqs "factorio" "$_resolved_id" "$AUTHOR_TEST_DIR" || {
    _fixture_failed "preparing the working directory for '$_resolved_id'"
    return 1
  }

  "$INSTANCES_MODULE" create factorio --library "$_library" --id "$_resolved_id" > /dev/null 2>&1 || {
    _fixture_failed "creating instance '$_resolved_id'"
    return 1
  }

  _TEARDOWN_INSTANCES+=("factorio:$_resolved_id")
  CREATED_ID="$_resolved_id"
  return 0
}

# The author an instance's info reports, or "" for none.
function _author_of() {
  "$INSTANCES_MODULE" info "$1" --json 2> /dev/null | jq -r '.maintenance_windows_author // ""'
}

function _windows_of() {
  "$INSTANCES_MODULE" info "$1" --json 2> /dev/null | jq -r '.maintenance_windows // ""'
}

# =============================================================================
# TEST: the author travels with the windows
# =============================================================================

function test_windows_written_with_an_author_record_it() {
  log_test_step "Testing --author is recorded beside the windows"

  _create || return
  assert_command_succeeds \
    "'$INSTANCES_MODULE' config-set '$CREATED_ID' 'maintenance_windows=daily@05:00/backup' --author usr_alice" \
    "Writing windows with an author should succeed"

  assert_equals "daily@05:00/backup" "$(_windows_of "$CREATED_ID")" "The windows should be written"
  assert_equals "usr_alice" "$(_author_of "$CREATED_ID")" "The author should be recorded"
}

function test_windows_written_without_an_author_have_none() {
  log_test_step "Testing a write naming nobody clears the author"

  _create || return
  "$INSTANCES_MODULE" config-set "$CREATED_ID" 'maintenance_windows=daily@05:00/backup' --author usr_alice \
    > /dev/null 2>&1
  assert_command_succeeds \
    "'$INSTANCES_MODULE' config-set '$CREATED_ID' 'maintenance_windows=weekly.sun@04:00/restart'" \
    "Writing windows without an author should succeed"

  assert_equals "weekly.sun@04:00/restart" "$(_windows_of "$CREATED_ID")" "The new windows should be written"
  assert_equals "" "$(_author_of "$CREATED_ID")" \
    "Windows nobody named themselves for should have no author, never the previous writer"
}

function test_a_refused_windows_write_keeps_the_author_it_had() {
  log_test_step "Testing a windows value the engine refuses changes nothing"

  _create || return
  "$INSTANCES_MODULE" config-set "$CREATED_ID" 'maintenance_windows=daily@05:00/backup' --author usr_alice \
    > /dev/null 2>&1
  "$INSTANCES_MODULE" config-set "$CREATED_ID" 'maintenance_windows=whenever/backup' --author usr_bob \
    > /dev/null 2>&1
  local exit_code=$?

  assert_not_equals "0" "$exit_code" "A malformed window list should be refused"
  assert_equals "daily@05:00/backup" "$(_windows_of "$CREATED_ID")" "The windows should be untouched"
  assert_equals "usr_alice" "$(_author_of "$CREATED_ID")" "The author should be untouched"
}

# =============================================================================
# TEST: the author is never set on its own
# =============================================================================

function test_the_author_cannot_be_set_directly() {
  log_test_step "Testing config-set refuses the author key"

  _create || return
  "$INSTANCES_MODULE" config-set "$CREATED_ID" 'maintenance_windows_author=usr_mallory' > /dev/null 2>&1
  local exit_code=$?

  assert_not_equals "0" "$exit_code" "Setting maintenance_windows_author should be refused"
  assert_equals "" "$(_author_of "$CREATED_ID")" "No author should have been written"
}

function test_an_author_goes_with_the_windows_key_alone() {
  log_test_step "Testing --author with another key is refused"

  _create || return
  "$INSTANCES_MODULE" config-set "$CREATED_ID" 'auto_update=true' --author usr_alice > /dev/null 2>&1
  local exit_code=$?

  assert_not_equals "0" "$exit_code" "--author with a key other than maintenance_windows should be refused"
}

function test_an_author_must_be_an_account_id() {
  log_test_step "Testing an author that is not an account id is refused"

  _create || return
  "$INSTANCES_MODULE" config-set "$CREATED_ID" 'maintenance_windows=daily@05:00/backup' \
    --author 'usr_alice"; rm -rf /' > /dev/null 2>&1
  local exit_code=$?

  assert_not_equals "0" "$exit_code" "An author carrying anything but an id's characters should be refused"
  assert_equals "" "$(_author_of "$CREATED_ID")" "No author should have been written"
}
