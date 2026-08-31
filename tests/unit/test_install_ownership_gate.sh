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
# somebody else runs the engine: the install lands in a home the service account
# cannot enter, while the journal it must append to belongs to an account this
# one is not. The watchdog, the monitor and the API all read the service
# account's tree, so the instance exists for nobody.
#
# The journal is the check because it is the shared thing, and it is checked
# before anything is created — reaching the first event instead leaves a
# half-built instance on disk and reports a permission error about a file the
# operator never asked to write.

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
# at "$GATE_TEST_DIR/journal". Echoes the combined output; the caller reads the
# status from GATE_EXIT_CODE.
#
# A private XDG tree rather than the shared sandbox: the gate is decided by a
# config value, and a test that rewrote the sandbox's config would decide it for
# every other test in the file too.
function __install_with_journal() {
  local home="$GATE_TEST_DIR/xdg"
  mkdir -p "$home/.config" "$home/.local/share"

  # config_event_journal_dir is the variable the engine flattens that config key
  # into and exports, and __logic_journal_dir reads it — so setting it is how a
  # parent process hands the value down, not a way around the config. Writing
  # the key to a file instead would not reach this child: the engine marks a
  # completed load with KGSM_CONFIG_LOADED and exports its functions, so a kgsm
  # invoked from a process that has already sourced one skips the reload and
  # keeps the values it inherited.
  local output
  output="$(
    env XDG_CONFIG_HOME="$home/.config" \
      XDG_DATA_HOME="$home/.local/share" \
      config_event_journal_dir="$GATE_TEST_DIR/journal" \
      "$KGSM_ROOT/kgsm.sh" install terraria --id gateprobe 2>&1
  )"
  GATE_EXIT_CODE=$?

  printf '%s' "$output"
}

# =============================================================================
# THE GATE
# =============================================================================

function test_install_refuses_when_the_journal_is_not_writable() {
  log_test_step "Testing that an install is refused when the event journal cannot be written"

  mkdir -p "$GATE_TEST_DIR/journal"
  chmod 500 "$GATE_TEST_DIR/journal"

  local output
  output="$(__install_with_journal)"

  assert_not_equals 0 "$GATE_EXIT_CODE" \
    "An install that cannot record itself should be refused, not reported as success"
  assert_contains "$output" "not writable" \
    "The refusal should name the journal as what cannot be written"
}

function test_the_refusal_happens_before_anything_is_created() {
  log_test_step "Testing that the refused install leaves nothing on disk"

  mkdir -p "$GATE_TEST_DIR/journal"
  chmod 500 "$GATE_TEST_DIR/journal"

  __install_with_journal > /dev/null

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

  local output
  output="$(__install_with_journal)"

  # Only the refusal is asserted on. The install itself needs a network and a
  # registered library, and the status it ends on is whichever of those it runs
  # out of first — so the message is the part that belongs to the gate.
  assert_not_contains "$output" "not writable" \
    "A writable journal should not produce an ownership refusal"
  assert_not_contains "$output" "would be invisible" \
    "A writable journal should not produce the wrong-account refusal either"
}
