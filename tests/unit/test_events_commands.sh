#!/usr/bin/env bash

# KGSM Events Commands Unit Tests
#
# Test Type: UNIT
# Target: commands/events.sh CLI interface
#
# Tests the command-level interface for the events.sh module:
# - Help system (--help, help command, subcommand help)
# - No arguments behavior
# - status subcommand
# - test subcommand (argument parsing)
# - emit subcommand (argument parsing, journal append, diagnostics)
# - webhook delegation
# - Invalid command/argument handling
#
# Does NOT duplicate:
# - Pure logic function tests (covered by test_events_logic.sh)
# - Event transport internals (events.webhook.sh)

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="events_commands"
readonly MODULE="$KGSM_ROOT/commands/events.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

# The newest segment in a journal directory. Segment names are dates, so ordinal
# order is chronological and the newest file is the one an emit just appended
# to — true whether or not the UTC day turned over mid-emit, which a computed
# name would get wrong.
#
# Args: $1 = journal directory
function _newest_journal_segment() {
  find "$1" -maxdepth 1 -type f -name '*.ndjson' 2> /dev/null | sort | tail -1
}

# Every event the journal holds, counted across all its segments so the total is
# unaffected by which segment a line landed in.
#
# Args: $1 = journal directory
function _journal_line_count() {
  find "$1" -maxdepth 1 -type f -name '*.ndjson' -exec cat {} + 2> /dev/null | wc -l
}

function setup_file() {
  log_test_step "Setting up events command tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "events.sh command module should exist"
  assert_file_executable "$MODULE" "events.sh command module should be executable"

  log_test_step "Events command test environment validated"
}

# =============================================================================
# help / usage TESTS
# =============================================================================

function test_help_no_args() {
  log_test_step "Testing: no arguments shows usage and exits non-zero"

  assert_command_fails "$MODULE" \
    "No arguments should fail"

  assert_command_output "$MODULE 2>&1 || true" "Usage" \
    "No arguments should show usage"
}

function test_help_flag() {
  log_test_step "Testing: --help flag shows usage and succeeds"

  assert_command_succeeds "$MODULE --help" \
    "--help should succeed"

  assert_command_output "$MODULE --help" "Usage" \
    "--help output should contain Usage"
}

function test_help_command() {
  log_test_step "Testing: help command shows usage and succeeds"

  assert_command_succeeds "$MODULE help" \
    "help command should succeed"

  assert_command_output "$MODULE help" "Commands" \
    "help output should contain Commands section"
}

function test_help_h_flag() {
  log_test_step "Testing: -h flag shows usage and succeeds"

  assert_command_succeeds "$MODULE -h" \
    "-h should succeed"

  assert_command_output "$MODULE -h" "Usage" \
    "-h output should contain Usage"
}

function test_help_lists_subcommands() {
  log_test_step "Testing: help output lists all subcommands"

  local output
  output=$("$MODULE" help 2>&1)

  assert_contains "$output" "status" \
    "help output should mention status command"
  assert_contains "$output" "test" \
    "help output should mention test command"
  assert_contains "$output" "emit" \
    "help output should mention emit command"
  assert_contains "$output" "webhook" \
    "help output should mention webhook command"
}

function test_help_status_subcommand() {
  log_test_step "Testing: help status shows status-specific help"

  assert_command_succeeds "$MODULE help status" \
    "help status should succeed"

  assert_command_output "$MODULE help status" "status" \
    "help status output should contain status"
}

function test_help_test_subcommand() {
  log_test_step "Testing: help test shows test-specific help"

  assert_command_succeeds "$MODULE help test" \
    "help test should succeed"

  assert_command_output "$MODULE help test" "transport" \
    "help test output should contain transport"
}

function test_help_emit_subcommand() {
  log_test_step "Testing: help emit shows emit-specific help"

  assert_command_succeeds "$MODULE help emit" \
    "help emit should succeed"

  assert_command_output "$MODULE help emit" "event-type" \
    "help emit output should contain event-type"
}

function test_help_webhook_subcommand() {
  log_test_step "Testing: help webhook delegates to events.webhook.sh help"

  assert_command_succeeds "$MODULE help webhook" \
    "help webhook should succeed"

  assert_command_output "$MODULE help webhook" "Webhook" \
    "help webhook output should contain Webhook"
}

function test_help_invalid_subcommand() {
  log_test_step "Testing: help with unknown subcommand fails"

  assert_command_fails "$MODULE help nonexistent_command_xyz" \
    "help with unknown subcommand should fail"
}

# =============================================================================
# status TESTS
# =============================================================================

function test_status_succeeds() {
  log_test_step "Testing: status command succeeds"

  assert_command_succeeds "$MODULE status" \
    "status should succeed"
}

function test_status_output_format() {
  log_test_step "Testing: status output shows event system status header"

  assert_command_output "$MODULE status" "KGSM Event System Status" \
    "status output should contain status header"
}

function test_status_help_flag() {
  log_test_step "Testing: status --help shows status help"

  # status delegates directly, does not have --help routing; status subcommand help via 'help status'
  assert_command_succeeds "$MODULE help status" \
    "help status should succeed"
}

# =============================================================================
# test SUBCOMMAND TESTS
# =============================================================================

function test_test_no_args_fails() {
  log_test_step "Testing: test with no arguments fails with missing arg"

  assert_command_fails "$MODULE test" \
    "test with no arguments should fail"
}

function test_test_no_args_shows_usage() {
  log_test_step "Testing: test with no arguments shows usage help"

  assert_command_output "$MODULE test 2>&1 || true" "transport" \
    "test with no arguments should show transport usage"
}

function test_test_help_flag() {
  log_test_step "Testing: test --help shows test help and succeeds"

  assert_command_succeeds "$MODULE test --help" \
    "test --help should succeed"

  assert_command_output "$MODULE test --help" "transport" \
    "test --help output should contain transport"
}

function test_test_help_command() {
  log_test_step "Testing: test help shows test help and succeeds"

  assert_command_succeeds "$MODULE test help" \
    "test help should succeed"
}

function test_test_all_no_transports_fails() {
  log_test_step "Testing: test all with no transports enabled fails"

  # With default config (all transports disabled), 'test all' should fail
  assert_command_fails "$MODULE test all" \
    "test all with no enabled transports should fail"
}

function test_test_all_no_transports_shows_error() {
  log_test_step "Testing: test all with no transports enabled shows error message"

  assert_command_output "$MODULE test all 2>&1 || true" "transport" \
    "test all with no transports should show transport-related error"
}

function test_test_invalid_transport_fails() {
  log_test_step "Testing: test with invalid transport name fails"

  assert_command_fails "$MODULE test invalid_transport_xyz" \
    "test with invalid transport should fail"
}

function test_test_invalid_transport_error_message() {
  log_test_step "Testing: test with invalid transport shows error message"

  assert_command_output "$MODULE test invalid_transport_xyz 2>&1 || true" "Unknown transport" \
    "test with invalid transport should show 'Unknown transport' error"
}

# =============================================================================
# emit SUBCOMMAND TESTS
#
# Emission is unconditional: there is no switch that turns the journal off, so
# emit always validates and always writes. Every case below asserts a real
# outcome rather than a config-gated early return.
# =============================================================================

function test_emit_help_flag() {
  log_test_step "Testing: emit --help shows emit help"

  assert_command_succeeds "$MODULE help emit" \
    "help emit should succeed"

  local output
  output=$("$MODULE" help emit 2>&1)
  assert_contains "$output" "server.install.created" \
    "emit help should list event types like server.install.created"
}

function test_emit_without_arguments_fails() {
  log_test_step "Testing: emit without an event type fails"

  assert_command_fails "$MODULE emit" \
    "emit should fail when no event type is given"
}

function test_emit_valid_events_succeed() {
  log_test_step "Testing: emit succeeds for valid event types"

  assert_command_succeeds "$MODULE emit server.install.created myserver factorio" \
    "emit server.install.created should succeed"

  assert_command_succeeds "$MODULE emit server.started myserver" \
    "emit server.started should succeed"

  assert_command_succeeds "$MODULE emit server.updated myserver 1.0.0 2.0.0" \
    "emit server.updated should succeed"
}

function test_emit_invalid_event_type_fails() {
  log_test_step "Testing: emit with an invalid event name fails"

  assert_command_fails "$MODULE emit completely-invalid-event-type" \
    "emit with an invalid event type should fail"
}

function test_emit_appends_one_line_to_the_journal() {
  log_test_step "Testing: emit appends exactly one JSON line to the journal"

  local journal_dir="${KGSM_ROOT}/events"

  # Counted over every segment, and the segment itself is found afterwards by
  # asking the directory. Both keep the arithmetic right when the UTC day turns
  # over during the emit and the line lands in a segment named tomorrow, which a
  # count against one computed name would read as no line appended at all.
  local before after
  before=$(_journal_line_count "$journal_dir")

  assert_command_succeeds "$MODULE emit server.stopped journaltest" \
    "emit should succeed"

  local segment
  segment=$(_newest_journal_segment "$journal_dir")
  assert_not_null "$segment" \
    "the journal segment should exist after emitting"

  after=$(_journal_line_count "$journal_dir")
  assert_equals "$((before + 1))" "$after" \
    "emit should append exactly one line to the journal"

  # One event per line is the contract every consumer's cursor depends on, so
  # the last line must be complete, parseable JSON on its own.
  local last_line
  last_line=$(tail -n 1 "$segment")
  assert_contains "$last_line" '"EventType":"server.stopped"' \
    "the appended line should carry the emitted event type"
  assert_contains "$last_line" '"InstanceName":"journaltest"' \
    "the appended line should carry the instance name"

  if command -v jq > /dev/null 2>&1; then
    assert_command_succeeds "printf '%s' '$last_line' | jq -e ." \
      "the appended line should be valid standalone JSON"
  fi
}

# =============================================================================
# emit DIAGNOSTICS TESTS
#
# Emission is unconditional, so these call the module directly — there is no
# config state to force on first. They assert the operator-facing message for
# each way an emit can be rejected, which the exit-code tests above do not.
# =============================================================================

function test_emit_no_event_type_shows_usage() {
  log_test_step "Testing: emit with no event type shows usage"

  local output
  output=$("$MODULE" emit 2>&1 || true)

  assert_contains "$output" "event-type" \
    "emit with no event type should show event-type in usage"
}

function test_emit_help_flag_shows_usage() {
  log_test_step "Testing: emit --help shows usage"

  assert_command_succeeds "$MODULE emit --help" \
    "emit --help should succeed"

  local output
  output=$("$MODULE" emit --help 2>&1)

  assert_contains "$output" "event-type" \
    "emit --help should show event-type usage"
}

function test_emit_invalid_event_error_message() {
  log_test_step "Testing: emit with an invalid event type explains why"

  local output
  output=$("$MODULE" emit invalid-event-xyz 2>&1 || true)

  assert_contains "$output" "Invalid event type" \
    "emit with an invalid event type should show 'Invalid event type'"
}

function test_emit_missing_params_fails() {
  log_test_step "Testing: emit with missing required parameters fails"

  # server.install.created requires: instance blueprint (2 params)
  assert_command_fails "$MODULE emit server.install.created" \
    "emit server.install.created with no params should fail"
}

function test_emit_missing_params_error_message() {
  log_test_step "Testing: emit with missing parameters explains why"

  local output
  output=$("$MODULE" emit server.install.created 2>&1 || true)

  assert_contains "$output" "parameters" \
    "emit with missing params should show a parameters error"
}

# =============================================================================
# webhook DELEGATION TESTS
# =============================================================================

function test_webhook_help_delegation() {
  log_test_step "Testing: webhook help delegates to events.webhook.sh"

  assert_command_succeeds "$MODULE webhook help" \
    "webhook help should succeed"

  assert_command_output "$MODULE webhook help" "Webhook" \
    "webhook help output should contain Webhook"
}

function test_webhook_status_delegation() {
  log_test_step "Testing: webhook status delegates to events.webhook.sh"

  assert_command_succeeds "$MODULE webhook status" \
    "webhook status should succeed"
}

function test_webhook_help_flag_delegation() {
  log_test_step "Testing: webhook --help delegates to events.webhook.sh"

  assert_command_succeeds "$MODULE webhook --help" \
    "webhook --help should succeed"
}

# =============================================================================
# UNKNOWN COMMAND TESTS
# =============================================================================

function test_unknown_command_fails() {
  log_test_step "Testing: unknown command fails"

  assert_command_fails "$MODULE unknown_command_xyz" \
    "Unknown command should fail"
}

function test_unknown_command_error_message() {
  log_test_step "Testing: unknown command shows error message"

  assert_command_output "$MODULE unknown_command_xyz 2>&1 || true" "Unknown command" \
    "Unknown command should show 'Unknown command' error"
}

