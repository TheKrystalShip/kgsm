#!/usr/bin/env bash

# KGSM Autostart Routing Tests
#
# Test Type: UNIT
# Target: commands/handlers/watchdog.sh - boot auto-start (enable/disable) routing
#
# Covers the systemctl-style boot axis helpers added alongside the start/stop
# routing: the enable/disable HTTP-status -> kgsm exit-code mapping, the parsing
# of GET /enabled into a name set, and the is-enabled membership test. The control
# socket itself is not exercised; the single curl chokepoints (__watchdog_curl /
# __watchdog_enabled_body) are overridden in-process to inject canned responses,
# so no live daemon is required.

# Two intentional indirections the linter cannot see in this file:
#  - SC2034: config/env vars (KGSM_WATCHDOG_*, config_*) are read by the sourced
#    handler's functions inside command-substitution subshells, not here.
#  - SC2329: the curl seam overrides (__watchdog_curl, __watchdog_enabled_body) are
#    invoked indirectly via the autostart helpers.
# shellcheck disable=SC2034,SC2329

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="autostart_routing"
readonly HANDLER="$KGSM_ROOT/commands/handlers/watchdog.sh"

function setup_file() {
  log_test_step "Setting up autostart routing tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Watchdog handler should exist"

  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_function_exists "__watchdog_set_autostart" "__watchdog_set_autostart should be exported"
  assert_function_exists "__watchdog_enabled_names" "__watchdog_enabled_names should be exported"
  assert_function_exists "__watchdog_is_enabled" "__watchdog_is_enabled should be exported"

  assert_equals 208 "$EC_SUCCESS_AUTOSTART_ENABLED" "EC_SUCCESS_AUTOSTART_ENABLED should be 208"
  assert_equals 209 "$EC_SUCCESS_AUTOSTART_DISABLED" "EC_SUCCESS_AUTOSTART_DISABLED should be 209"

  log_test_step "Test environment validated"
}

# Re-source the handler fresh before each test so a per-test override of an
# overridable seam (e.g. __watchdog_curl) never leaks into the next test.
function setup() {
  unset KGSM_LOGIC_WATCHDOG_LOADED
  unset KGSM_WATCHDOG_SOCKET
  # shellcheck disable=SC1090
  source "$HANDLER"
}

# =============================================================================
# ENABLE/DISABLE DISPATCH -> EXIT-CODE MAPPING
# =============================================================================

function test_enable_200_is_enabled() {
  log_test_step "POST /enable 200 -> EC_SUCCESS_AUTOSTART_ENABLED"

  function __watchdog_curl() { echo "200"; return 0; }

  __watchdog_set_autostart enable "myinst"
  assert_equals "$EC_SUCCESS_AUTOSTART_ENABLED" "$?" \
    "200 should map to the enabled event code"
}

function test_disable_200_is_disabled() {
  log_test_step "POST /disable 200 -> EC_SUCCESS_AUTOSTART_DISABLED"

  function __watchdog_curl() { echo "200"; return 0; }

  __watchdog_set_autostart disable "myinst"
  assert_equals "$EC_SUCCESS_AUTOSTART_DISABLED" "$?" \
    "200 should map to the disabled event code"
}

function test_enable_409_out_of_scope_is_ec_error() {
  log_test_step "POST /enable 409 (out of scope / unknown) -> EC_ERROR"

  # Unlike start/stop, 409 here is a real failure (not idempotent success).
  function __watchdog_curl() { echo "409"; return 0; }

  __watchdog_set_autostart enable "myinst"
  assert_equals "$EC_ERROR" "$?" \
    "A 409 on enable must be an error, not a success"
}

function test_enable_connection_failure_is_ec_error() {
  log_test_step "curl connection failure -> EC_ERROR"

  function __watchdog_curl() { echo ""; return 7; }

  __watchdog_set_autostart enable "myinst"
  assert_equals "$EC_ERROR" "$?" "Connection failure should map to EC_ERROR"
}

function test_set_autostart_unknown_verb_is_invalid_arg() {
  log_test_step "Unknown verb -> EC_INVALID_ARG"

  __watchdog_set_autostart frobnicate "myinst"
  assert_equals "$EC_INVALID_ARG" "$?" "An unsupported verb should be rejected"
}

# =============================================================================
# GET /enabled -> name-set parsing
# =============================================================================

function test_enabled_names_parses_array() {
  log_test_step "GET /enabled [\"a\",\"b\"] -> one name per line"

  function __watchdog_enabled_body() { printf '%s' '["7dtd","factorio"]'; return 0; }

  local names
  names="$(__watchdog_enabled_names)"
  assert_equals "7dtd
factorio" "$names" "Should emit one unquoted name per line"
}

function test_enabled_names_empty_array() {
  log_test_step "GET /enabled [] -> no output"

  function __watchdog_enabled_body() { printf '%s' '[]'; return 0; }

  local names
  names="$(__watchdog_enabled_names)"
  assert_equals "" "$names" "An empty set should produce no names"
}

function test_enabled_names_unreachable_returns_2() {
  log_test_step "GET /enabled connection failure -> return 2"

  function __watchdog_enabled_body() { printf '%s' ''; return 2; }

  __watchdog_enabled_names > /dev/null
  assert_equals 2 "$?" "Unreachable daemon should propagate as 2"
}

# =============================================================================
# is-enabled -> membership
# =============================================================================

function test_is_enabled_true_when_in_set() {
  log_test_step "Name in the enabled set -> 0"

  function __watchdog_enabled_body() { printf '%s' '["7dtd","factorio"]'; return 0; }

  __watchdog_is_enabled "factorio"
  assert_equals 0 "$?" "A name in the set should report enabled"
}

function test_is_enabled_false_when_not_in_set() {
  log_test_step "Name not in the enabled set -> 1"

  function __watchdog_enabled_body() { printf '%s' '["7dtd"]'; return 0; }

  __watchdog_is_enabled "factorio"
  assert_equals 1 "$?" "A name absent from the set should report not-enabled"
}

function test_is_enabled_no_substring_false_match() {
  log_test_step "Membership is exact, not substring"

  # "7dtd" must not match "7dtd-test".
  function __watchdog_enabled_body() { printf '%s' '["7dtd-test"]'; return 0; }

  __watchdog_is_enabled "7dtd"
  assert_equals 1 "$?" "Exact-match only: a prefix must not count as enabled"
}

function test_is_enabled_unreachable_returns_2() {
  log_test_step "is-enabled with unreachable daemon -> 2"

  function __watchdog_enabled_body() { printf '%s' ''; return 2; }

  __watchdog_is_enabled "7dtd"
  assert_equals 2 "$?" "Unreachable daemon should map to unknown (2)"
}
