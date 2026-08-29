#!/usr/bin/env bash

# KGSM Initial Library Seeding — Concurrency Unit Tests
#
# Test Type: UNIT
# Target: core/config.sh - __seed_initial_library
#
# A node starts several units at once, and each one's first kgsm call reaches the
# seeding path together. The registry is claimed before anything is written to it,
# so exactly one of them seeds and the rest find a registry that belongs to
# somebody. Without that claim they each appended a [default] section, the marker
# on the root kept only the last id, and the engine reported a library whose id
# matched no section — offline, on a host that had just been provisioned, refusing
# every install.

readonly TEST_NAME="library_seed_race"

# =============================================================================
# HELPERS
# =============================================================================

# One pristine engine home: no config, no registry, no marker.
function _fresh_home() {
  local home="${KGSM_TEST_SANDBOX}/seed_${RANDOM}_$$"
  rm -rf "$home"
  mkdir -p "$home"
  printf '%s' "$home"
}

# Run $2 first invocations against $1 at the same time and wait for all of them.
function _first_calls() {
  local home="$1" count="$2" i
  for ((i = 0; i < count; i++)); do
    (
      # The runner exports the *_LOADED guards so a sourced module is not re-read.
      # A child inheriting them skips the config bootstrap — and with it the
      # seeding under test — so this call is made as a genuinely first one.
      env -u KGSM_CONFIG_LOADED -u KGSM_PATHS_LOADED -u KGSM_BOOTSTRAP_LOADED \
          -u KGSM_COMMON_LOADED -u KGSM_LOADER_LOADED -u KGSM_TEST_MODE \
          HOME="$home" \
          XDG_DATA_HOME="${home}/.local/share" \
          XDG_CONFIG_HOME="${home}/.config" \
          "$KGSM_ROOT/kgsm.sh" --version > /dev/null 2>&1
    ) &
  done
  wait
}

function _registry_of() { printf '%s' "${1}/.local/share/kgsm/libraries.ini"; }
function _marker_of()   { printf '%s' "${1}/.local/share/kgsm/instances/.kgsm-library"; }

function _sections_in() { grep -c '^\[default\]$' "$1" 2> /dev/null || echo 0; }

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up initial-library seeding tests"

  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$KGSM_ROOT/kgsm.sh" "kgsm.sh should exist"
}

function test_a_single_first_invocation_seeds_one_library() {
  log_test_step "Testing one first invocation registers exactly one library"

  local home; home="$(_fresh_home)"
  _first_calls "$home" 1

  assert_file_exists "$(_registry_of "$home")" "The registry should exist after a first run"
  assert_equals 1 "$(_sections_in "$(_registry_of "$home")")" \
    "A first invocation should register exactly one library"
  assert_file_exists "$(_marker_of "$home")" "The library root should carry its marker"
}

function test_concurrent_first_invocations_seed_one_library() {
  log_test_step "Testing six simultaneous first invocations still register one library"

  local home; home="$(_fresh_home)"
  _first_calls "$home" 6

  assert_equals 1 "$(_sections_in "$(_registry_of "$home")")" \
    "Six units starting together should leave one [default] section, not six"
}

function test_the_registered_id_is_the_one_on_the_root() {
  log_test_step "Testing the registry and the marker agree after a concurrent start"

  local home; home="$(_fresh_home)"
  _first_calls "$home" 6

  local registered marked
  registered="$(grep -m1 '^id=' "$(_registry_of "$home")" 2> /dev/null | cut -d= -f2)"
  marked="$(grep -m1 '^id=' "$(_marker_of "$home")" 2> /dev/null | cut -d= -f2)"

  assert_not_null "$registered" "The registry should carry a library id"
  # The id the registry holds is what the engine compares the root's marker to.
  # Two seeders left these disagreeing, which is what "offline" was reporting.
  assert_equals "$marked" "$registered" \
    "The registered id should be the id written on the library root"
}

function test_the_seeded_library_is_reachable() {
  log_test_step "Testing the seeded library is online, not merely registered"

  local home; home="$(_fresh_home)"
  _first_calls "$home" 6

  local state
  state="$(env -u KGSM_CONFIG_LOADED -u KGSM_PATHS_LOADED -u KGSM_BOOTSTRAP_LOADED \
      -u KGSM_COMMON_LOADED -u KGSM_LOADER_LOADED -u KGSM_TEST_MODE \
      HOME="$home" XDG_DATA_HOME="${home}/.local/share" XDG_CONFIG_HOME="${home}/.config" \
      "$KGSM_ROOT/kgsm.sh" libraries list 2> /dev/null | awk 'NR > 1 { print $2; exit }')"

  # Registered is not reachable: a duplicate seed leaves a library listed and
  # permanently offline, and every install against it refuses.
  assert_equals "online" "$state" "The seeded library should be reachable"
}

function test_a_registry_that_exists_is_left_alone() {
  log_test_step "Testing an existing registry is never added to"

  local home; home="$(_fresh_home)"
  _first_calls "$home" 1

  local before after
  before="$(cat "$(_registry_of "$home")")"
  _first_calls "$home" 4
  after="$(cat "$(_registry_of "$home")")"

  assert_equals "$before" "$after" \
    "Later invocations should leave a registry that belongs to somebody untouched"
}
