#!/usr/bin/env bash

# KGSM Diagnostic Stream Separation Unit Tests
#
# Test Type: UNIT
# Target: core/logging.sh — which stream a diagnostic is written to
#
# stdout carries the value a command returns; stderr carries everything said
# about producing it. A module that yields data — an instance id, a path, a
# version, a listing — echoes it to stdout, and its caller reads it with $(...),
# which captures stdout and nothing else.
#
# Sharing that stream makes a diagnostic indistinguishable from the value. A
# warning printed while an instance id is being generated is captured as part of
# the id, and the caller then builds a working directory, a registry symlink and
# a config file name out of a multi-line string — so a journal that could not be
# written turns into a corrupted on-disk layout, several steps away from
# anything that mentions the journal.
#
# The separation is what makes a diagnostic safe to emit from anywhere,
# including from inside a command substitution.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="diagnostic_stream_separation"
readonly LOGGING_MODULE="$KGSM_ROOT/core/logging.sh"

function setup_file() {
  log_test_step "Setting up diagnostic stream separation tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$LOGGING_MODULE" "logging module should exist"

  log_test_step "Environment validated"
}

# Runs one print helper with logging sourced, and echoes what each stream got as
# "<stdout>|<stderr>". File logging is pointed at the scratch directory so the
# test never appends to the host's real log.
function __streams_for() {
  local helper="$1"

  local out err
  out="$(
    bash -c "
      export KGSM_ROOT='$KGSM_ROOT'
      export LOGS_SOURCE_DIR='$STREAM_TEST_DIR'
      export KGSM_LOG_FILE='$STREAM_TEST_DIR/kgsm.log'
      source '$LOGGING_MODULE' >/dev/null 2>&1
      $helper 'stream probe' 2>'$STREAM_TEST_DIR/stderr'
    "
  )"
  err="$(cat "$STREAM_TEST_DIR/stderr" 2> /dev/null)"

  printf '%s|%s' "$out" "$err"
}

function setup() {
  STREAM_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kgsm-stream-test-XXXXXX")"
  export STREAM_TEST_DIR
}

function teardown() {
  [[ -n "${STREAM_TEST_DIR:-}" && -d "$STREAM_TEST_DIR" ]] &&
    rm -rf "$STREAM_TEST_DIR"
  return 0
}

# =============================================================================
# THE INVARIANT
# =============================================================================

function test_every_diagnostic_helper_writes_to_stderr() {
  log_test_step "Testing that every print helper writes to stderr, not stdout"

  # Warning is the one that caused the corrupted install, but the rule is the
  # same for all of them: none of these is ever the value of a command
  # substitution, so none of them belongs on stdout.
  local helper streams stdout_part stderr_part
  for helper in __print_error __print_warning __print_info __print_success; do
    streams="$(__streams_for "$helper")"
    stdout_part="${streams%%|*}"
    stderr_part="${streams#*|}"

    assert_equals "" "$stdout_part" \
      "$helper should write nothing to stdout — stdout is the command's return value"
    assert_contains "$stderr_part" "stream probe" \
      "$helper should write its message to stderr"
  done
}

function test_a_diagnostic_does_not_reach_a_command_substitution() {
  log_test_step "Testing that a diagnostic printed beside a value is not captured with it"

  # The bug end to end, in miniature: a function that warns and then echoes an
  # id. What the caller captures must be the id alone, on one line — never the
  # warning, and never the two joined.
  local captured
  captured="$(
    bash -c "
      export KGSM_ROOT='$KGSM_ROOT'
      export LOGS_SOURCE_DIR='$STREAM_TEST_DIR'
      export KGSM_LOG_FILE='$STREAM_TEST_DIR/kgsm.log'
      source '$LOGGING_MODULE' >/dev/null 2>&1
      generate() { __print_warning 'the journal could not be written'; echo 'terraria-01'; }
      value=\"\$(generate 2>/dev/null)\"
      printf '%s' \"\$value\"
    "
  )"

  assert_equals "terraria-01" "$captured" \
    "A command substitution should capture the value alone, with no diagnostic in it"
}

function test_a_captured_value_stays_a_single_line() {
  log_test_step "Testing that a captured value carries no embedded newline"

  # The specific corruption: the id became "terraria\n[WARNING] ...", and every
  # path built from it inherited the break. One line is the property that makes
  # it usable as a path component.
  local line_count
  line_count="$(
    bash -c "
      export KGSM_ROOT='$KGSM_ROOT'
      export LOGS_SOURCE_DIR='$STREAM_TEST_DIR'
      export KGSM_LOG_FILE='$STREAM_TEST_DIR/kgsm.log'
      source '$LOGGING_MODULE' >/dev/null 2>&1
      generate() { __print_warning 'noise'; echo 'terraria-01'; }
      generate 2>/dev/null
    " | wc -l
  )"

  assert_equals "1" "$line_count" \
    "A value-producing function should put exactly one line on stdout"
}
