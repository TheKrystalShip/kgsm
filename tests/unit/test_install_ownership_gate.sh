#!/usr/bin/env bash

# KGSM Install Ownership Gate Unit Tests
#
# Test Type: UNIT
# Target: commands/install.sh - the gate refusing an install this account cannot record
#
# The engine derives its whole world from the invoking account: instances,
# blueprints, the library registry and the config all hang off that account's
# XDG paths. The event journal does not — it is one host-wide directory every
# producer appends to and every consumer tails.
#
# On a host whose units run as a service account, those two facts disagree when
# somebody else runs the engine: the instance is recorded in the invoking
# account's registry, while the watchdog, the monitor and the API enumerate the
# service account's. The instance exists for nobody.
#
# The journal is the check because it is the shared thing, and its OWNER is the
# property read — that is which account's registry this host's services
# enumerate. Writability answers a different question and gets this one wrong:
# write granted without ownership lets the events through while the instance
# stays somewhere nothing reads. It is checked before anything is created,
# because reaching the first event instead leaves a half-built instance on disk
# and reports a permission error about a file the operator never asked to write.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="install_ownership_gate"
readonly MODULE="$KGSM_ROOT/commands/install.sh"

function setup_file() {
  log_test_step "Setting up install ownership gate tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "install.sh module should exist"

  log_test_step "Environment validated"
}

function setup() {
  GATE_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kgsm-gate-test-XXXXXX")"
  export GATE_TEST_DIR
}

function teardown() {
  # The journal directory is made unwritable during the test, and a read-only
  # directory cannot have its contents removed.
  [[ -n "${GATE_TEST_DIR:-}" && -d "$GATE_TEST_DIR" ]] && {
    chmod -R u+w "$GATE_TEST_DIR" 2> /dev/null
    rm -rf "$GATE_TEST_DIR"
  }
  return 0
}

# Runs an install against an XDG tree of its own, with the event journal pointed
# at $1, defaulting to "$GATE_TEST_DIR/journal".
#
# Leaves the combined output in GATE_OUTPUT and RETURNS the install's status, so
# a caller reads it with $?. Deliberately not echoed for capture: `out="$(helper)"`
# would run the function in a subshell, where an exit code assigned to a global
# is discarded and the caller reads an empty string — which compares equal to
# nothing and makes a status assertion pass without testing anything.
#
# A private XDG tree rather than the shared sandbox: the gate is decided by a
# config value, and a test that rewrote the sandbox's config would decide it for
# every other test in the file too.
function __install_with_journal() {
  local journal="${1:-$GATE_TEST_DIR/journal}"
  local home="$GATE_TEST_DIR/xdg"
  mkdir -p "$home/.config" "$home/.local/share"

  # config_event_journal_dir is the variable the engine flattens that config key
  # into and exports, and __logic_journal_dir reads it — so setting it is how a
  # parent process hands the value down, not a way around the config. Writing
  # the key to a file instead would not reach this child: the engine marks a
  # completed load with KGSM_CONFIG_LOADED and exports its functions, so a kgsm
  # invoked from a process that has already sourced one skips the reload and
  # keeps the values it inherited.
  GATE_OUTPUT="$(
    env XDG_CONFIG_HOME="$home/.config" \
      XDG_DATA_HOME="$home/.local/share" \
      config_event_journal_dir="$journal" \
      "$KGSM_ROOT/kgsm.sh" install terraria --id gateprobe 2>&1
  )"
  return $?
}

# =============================================================================
# THE GATE
# =============================================================================

function test_install_refuses_when_the_journal_is_not_writable() {
  log_test_step "Testing that an install is refused when the event journal cannot be written"

  mkdir -p "$GATE_TEST_DIR/journal"
  chmod 500 "$GATE_TEST_DIR/journal"

  local exit_code
  __install_with_journal
  exit_code=$?

  assert_equals "$EC_PERMISSION" "$exit_code" \
    "An install that cannot record itself should be refused, not reported as success"
  assert_contains "$GATE_OUTPUT" "not writable" \
    "The refusal should name the journal as what cannot be written"
}

function test_install_refuses_a_journal_owned_by_another_account_even_when_writable() {
  log_test_step "Testing that another account's journal is refused even when this one can write it"

  # The case that defeats a writability test. Granting write without
  # transferring ownership — an ACL is the narrowest way to do it, and so the
  # one a careful operator reaches for — lets the events through while the
  # instance stays in a registry the owning account's units never enumerate. A
  # gate that asked only "can I write this" would pass here and go silent,
  # which is the failure it exists to replace.
  #
  # /tmp is the fixture because it holds the shape on any Linux host without
  # needing privilege to build: owned by another account, writable by everyone.
  local owner
  owner="$(stat -c '%U' /tmp 2> /dev/null)"

  assert_not_equals "$(id -un)" "$owner" \
    "/tmp should be owned by another account for this test to mean anything"
  local writable="false"
  [[ -w /tmp ]] && writable="true"
  assert_equals "true" "$writable" \
    "/tmp should be writable here, so writability alone cannot be what refuses"

  local exit_code
  __install_with_journal /tmp
  exit_code=$?

  assert_equals "$EC_PERMISSION" "$exit_code" \
    "An install should be refused when the journal belongs to another account, however writable it is"
  assert_contains "$GATE_OUTPUT" "belongs to '${owner}'" \
    "The refusal should name the account whose registry this host's services enumerate"
}

function test_the_refusal_happens_before_anything_is_created() {
  log_test_step "Testing that the refused install leaves nothing on disk"

  mkdir -p "$GATE_TEST_DIR/journal"
  chmod 500 "$GATE_TEST_DIR/journal"

  __install_with_journal

  # A gate that ran after the working directory, the symlink or the config would
  # leave a half-built instance behind for the operator to find and clean up.
  # Both trees are checked: the engine exports its resolved paths, so a child
  # inherits KGSM_INSTANCES_DIR from whoever launched it and may write there
  # rather than under the XDG directories this test hands down.
  assert_dir_not_exists "$GATE_TEST_DIR/xdg/.local/share/kgsm/instances/terraria/gateprobe" \
    "A refused install should create no instance directory in the tree it was pointed at"
  assert_dir_not_exists "${KGSM_INSTANCES_DIR}/terraria/gateprobe" \
    "A refused install should create no instance directory in the inherited tree either"
}

function test_a_writable_journal_does_not_refuse() {
  log_test_step "Testing that an install proceeds when the journal is writable"

  mkdir -p "$GATE_TEST_DIR/journal"

  __install_with_journal

  # Only the refusal is asserted on. The install itself needs a network and a
  # registered library, and the status it ends on is whichever of those it runs
  # out of first — so the message is the part that belongs to the gate.
  assert_not_contains "$GATE_OUTPUT" "not writable" \
    "A writable journal should not produce an ownership refusal"
  assert_not_contains "$GATE_OUTPUT" "is recorded in a different registry" \
    "A writable journal should not produce the wrong-account refusal either"
}
