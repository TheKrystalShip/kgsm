#!/usr/bin/env bash

# KGSM Instance Install Nonce Unit Tests
#
# Test Type: UNIT
# Target: the nonce that tells two installs under one name apart. A grant of
# access names an instance by its node, its name and this nonce, so what is
# exercised here is that every instance carries one, that it never changes for
# the instance's life, that a second install under the same name gets a
# different one, and that server.uninstalled says which install went.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="instance_install_nonce"
readonly INSTANCES_MODULE="$KGSM_ROOT/commands/instances.sh"
readonly EVENTS_MODULE="$KGSM_ROOT/commands/events.sh"

NONCE_TEST_DIR=""
NONCE_TEST_SEQ=0
CREATED_ID=""
_TEARDOWN_INSTANCES=()

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up instance install nonce tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_executable "$INSTANCES_MODULE" "instances.sh should be executable"

  log_test_step "Test environment validated"
}

function setup() {
  # Counted, not drawn: a library is named after its directory, and two tests
  # handed one directory would collide registering it.
  NONCE_TEST_SEQ=$((NONCE_TEST_SEQ + 1))
  NONCE_TEST_DIR="${KGSM_TEST_SANDBOX}/nonce_${NONCE_TEST_SEQ}_$$"
  mkdir -p "$NONCE_TEST_DIR"
  _TEARDOWN_INSTANCES=()
}

function teardown() {
  local entry bp name
  for entry in "${_TEARDOWN_INSTANCES[@]}"; do
    bp="${entry%%:*}"
    name="${entry#*:}"
    remove_test_instance "$bp" "$name" "$NONCE_TEST_DIR" 2> /dev/null || true
  done

  "$KGSM_ROOT/kgsm.sh" libraries remove "$(__test_library_name "$NONCE_TEST_DIR")" \
    --force > /dev/null 2>&1 || true

  rm -rf "$NONCE_TEST_DIR"
}

function _fixture_failed() {
  assert_not_null "" "Test fixture: $1"
}

# Creates an instance through the command layer and records it for teardown.
# The id is left in CREATED_ID: a command substitution would run this in a
# subshell, and the teardown list would die with it.
#
# Args: $1 = id ("" to let KGSM generate one)
function _create() {
  local _id="$1"

  CREATED_ID=""

  local _library
  _library="$(__ensure_test_library "$NONCE_TEST_DIR")" || {
    _fixture_failed "registering a library at $NONCE_TEST_DIR"
    return 1
  }

  local -a _generate_args=(factorio)
  [[ -n "$_id" ]] && _generate_args+=(--id "$_id")

  local _resolved_id
  _resolved_id="$("$INSTANCES_MODULE" generate-id "${_generate_args[@]}" 2> /dev/null)" || {
    _fixture_failed "settling the id for '${_id:-<generated>}'"
    return 1
  }

  setup_instance_prereqs "factorio" "$_resolved_id" "$NONCE_TEST_DIR" || {
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

# The nonce an instance's info reports.
function _nonce_of() {
  "$INSTANCES_MODULE" info "$1" --json 2> /dev/null | jq -r '.install_nonce // ""'
}

function _journal_segment() {
  local journal_dir="${config_event_journal_dir:-$KGSM_TEST_SANDBOX/events}"
  find "$journal_dir" -maxdepth 1 -type f -name '*.ndjson' 2> /dev/null | sort | tail -1
}

# Every journal line written since the caller took its mark.
# Args: $1 = segment path (may be empty), $2 = line count at the mark
function _journal_since() {
  local segment="$1"
  local mark="$2"

  local current
  current="$(_journal_segment)"
  [[ -n "$current" ]] || return 0

  if [[ "$current" != "$segment" ]]; then
    cat "$current"
    return 0
  fi

  tail -n "+$((mark + 1))" "$current"
}

# =============================================================================
# TEST: every install carries its own
# =============================================================================

function test_a_created_instance_carries_a_nonce() {
  log_test_step "Testing an instance is created with a nonce"

  _create "" || return
  local nonce
  nonce="$(_nonce_of "$CREATED_ID")"

  assert_matches "$nonce" '^[0-9a-f]{16}$' "The nonce should be 16 hex digits"
}

function test_the_nonce_does_not_change_between_reads() {
  log_test_step "Testing the nonce is stable"

  _create "" || return
  local first second
  first="$(_nonce_of "$CREATED_ID")"
  second="$(_nonce_of "$CREATED_ID")"

  assert_equals "$first" "$second" "Reading an instance twice should report one nonce"
}

function test_two_instances_carry_different_nonces() {
  log_test_step "Testing two installs are told apart"

  _create "" || return
  local first="$CREATED_ID"
  _create "" || return
  local second="$CREATED_ID"

  assert_not_equals "$(_nonce_of "$first")" "$(_nonce_of "$second")" \
    "Two installs should not share a nonce"
}

function test_a_reinstall_under_the_same_name_gets_a_new_nonce() {
  log_test_step "Testing a reinstall under one name is a different install"

  _create "factorio-again" || return
  local before
  before="$(_nonce_of "$CREATED_ID")"

  remove_test_instance factorio "$CREATED_ID" "$NONCE_TEST_DIR" > /dev/null 2>&1
  _TEARDOWN_INSTANCES=()

  _create "factorio-again" || return
  local after
  after="$(_nonce_of "$CREATED_ID")"

  assert_equals "factorio-again" "$CREATED_ID" "The reinstall should take the same name"
  assert_not_equals "$before" "$after" "The reinstall should carry a new nonce"
}

function test_the_nonce_cannot_be_set() {
  log_test_step "Testing config-set refuses the nonce"

  _create "" || return
  local before
  before="$(_nonce_of "$CREATED_ID")"

  "$INSTANCES_MODULE" config-set "$CREATED_ID" install_nonce 0000000000000000 > /dev/null 2>&1
  local exit_code=$?

  assert_not_equals "0" "$exit_code" "Setting install_nonce should be refused"
  assert_equals "$before" "$(_nonce_of "$CREATED_ID")" "The nonce should be untouched"
}

# =============================================================================
# TEST: an instance installed before nonces existed
# =============================================================================

function test_an_instance_without_one_gets_one_on_first_read_and_keeps_it() {
  log_test_step "Testing a nonce is stamped onto an instance that has none"

  _create "" || return
  local config
  config="$(__find_instance_config "$CREATED_ID")"
  sed -i '/^install_nonce=/d' "$config"
  assert_command_fails "grep -q '^install_nonce=' '$config'" "The fixture should have removed the key"

  local stamped
  stamped="$(_nonce_of "$CREATED_ID")"

  assert_matches "$stamped" '^[0-9a-f]{16}$' "Reading the instance should stamp a nonce"
  assert_equals "$stamped" "$(_nonce_of "$CREATED_ID")" "The stamped nonce should be kept"
  assert_command_succeeds "bash -n '$config'" "The stamped config should still be sourceable"
}

# =============================================================================
# TEST: server.uninstalled says which install went
# =============================================================================

function test_uninstalling_names_the_nonce_of_the_install_that_went() {
  log_test_step "Testing server.uninstalled carries the install nonce"

  _create "" || return
  local id="$CREATED_ID"
  local nonce
  nonce="$(_nonce_of "$id")"

  local segment mark
  segment="$(_journal_segment)"
  mark=0
  [[ -n "$segment" ]] && mark="$(wc -l < "$segment")"

  KGSM_WATCHDOG_DISABLE=true "$KGSM_ROOT/kgsm.sh" uninstall "$id" --force > /dev/null 2>&1
  _TEARDOWN_INSTANCES=()

  local uninstalled
  uninstalled="$(_journal_since "$segment" "$mark" \
    | jq -c 'select(.EventType == "server.uninstalled")' | tail -n 1)"

  assert_not_null "$uninstalled" "Uninstalling should emit server.uninstalled"
  assert_equals "$id" "$(jq -r '.Data.InstanceName' <<< "$uninstalled")" "The event should name the instance"
  assert_equals "$nonce" "$(jq -r '.Data.InstallNonce' <<< "$uninstalled")" \
    "The event should carry the nonce of the install that was removed"
}

function test_an_uninstall_with_no_nonce_to_give_writes_null() {
  log_test_step "Testing a nonce nothing could read is null, never blank"

  local segment mark
  segment="$(_journal_segment)"
  mark=0
  [[ -n "$segment" ]] && mark="$(wc -l < "$segment")"

  "$EVENTS_MODULE" emit server.uninstalled nonce-less-instance > /dev/null 2>&1

  local uninstalled
  uninstalled="$(_journal_since "$segment" "$mark" \
    | jq -c 'select(.EventType == "server.uninstalled")' | tail -n 1)"

  assert_not_null "$uninstalled" "The event should be recorded"
  assert_equals "null" "$(jq -c '.Data.InstallNonce' <<< "$uninstalled")" \
    "An absent nonce should be a real null"
}
