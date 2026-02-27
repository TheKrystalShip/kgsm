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
# - emit subcommand (argument parsing, broadcasting disabled/enabled paths)
# - socket/webhook delegation
# - Invalid command/argument handling
#
# Does NOT duplicate:
# - Pure logic function tests (covered by test_events_logic.sh)
# - Event transport internals (events.socket.sh, events.webhook.sh)

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="events_commands"
readonly MODULE="$KGSM_ROOT/commands/events.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
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
  assert_contains "$output" "socket" \
    "help output should mention socket command"
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

function test_help_socket_subcommand() {
  log_test_step "Testing: help socket delegates to events.socket.sh help"

  assert_command_succeeds "$MODULE help socket" \
    "help socket should succeed"

  assert_command_output "$MODULE help socket" "Socket" \
    "help socket output should contain Socket"
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
# emit SUBCOMMAND TESTS (broadcasting disabled - default config)
# =============================================================================

function test_emit_help_flag() {
  log_test_step "Testing: emit --help shows emit help"

  # When broadcasting is disabled, emit checks config first and returns EC_SUCCESS.
  # We use 'help emit' to verify emit help is accessible.
  assert_command_succeeds "$MODULE help emit" \
    "help emit should succeed"

  local output
  output=$("$MODULE" help emit 2>&1)
  assert_contains "$output" "instance-created" \
    "emit help should list event types like instance-created"
}

function test_emit_broadcasting_disabled_succeeds() {
  log_test_step "Testing: emit exits successfully when broadcasting is disabled"

  # With default config (enable_event_broadcasting=false), emit always returns EC_SUCCESS
  assert_command_succeeds "$MODULE emit" \
    "emit should succeed when broadcasting is disabled (no-op)"
}

function test_emit_any_event_broadcasting_disabled_succeeds() {
  log_test_step "Testing: emit with any event name succeeds when broadcasting disabled"

  assert_command_succeeds "$MODULE emit instance-created myserver factorio" \
    "emit instance-created should succeed when broadcasting is disabled"

  assert_command_succeeds "$MODULE emit instance-started myserver systemd" \
    "emit instance-started should succeed when broadcasting is disabled"

  assert_command_succeeds "$MODULE emit instance-version-updated myserver 1.0.0 2.0.0" \
    "emit instance-version-updated should succeed when broadcasting is disabled"
}

function test_emit_invalid_event_broadcasting_disabled_succeeds() {
  log_test_step "Testing: emit with invalid event name also succeeds when broadcasting disabled"

  # Broadcasting disabled → early return EC_SUCCESS, no validation occurs
  assert_command_succeeds "$MODULE emit completely-invalid-event-type" \
    "emit with invalid event type should succeed when broadcasting is disabled (early exit)"
}

# =============================================================================
# emit SUBCOMMAND TESTS (broadcasting enabled)
#
# The module loads config from ${XDG_CONFIG_HOME:-~/.config}/kgsm/config.ini.
# The test framework exports KGSM_BOOTSTRAP_LOADED and other guards that prevent
# fresh config loading in subprocesses. We use a clean subshell that unsets
# those guards and sets XDG_CONFIG_HOME to a temp config with broadcasting enabled.
# =============================================================================

# Create a temp XDG config dir with broadcasting enabled.
# Echoes the temp dir path. Caller must remove it after use.
function _create_broadcasting_config() {
  local temp_dir
  temp_dir=$(mktemp -d)
  mkdir -p "$temp_dir/kgsm"

  cat > "$temp_dir/kgsm/config.ini" << 'EOF'
# Test config with event broadcasting enabled
[events]
enable_event_broadcasting=true
enable_socket_events=false
enable_webhook_events=false
EOF

  echo "$temp_dir"
}

# Run a command with broadcasting enabled, bypassing inherited module load guards.
# Usage: _emit_with_broadcasting <module> [args...]
# Returns: exit code of the module command
function _emit_with_broadcasting() {
  local module="$1"
  shift
  local args=("$@")

  local temp_xdg
  temp_xdg=$(_create_broadcasting_config)

  local exit_code=0
  local output
  output=$(
    # shellcheck disable=SC2030
    unset KGSM_BOOTSTRAP_LOADED KGSM_CONFIG_LOADED KGSM_COMMON_LOADED KGSM_PATHS_LOADED
    unset config_enable_event_broadcasting KGSM_EVENTS_LOADED KGSM_LOGGING_LOADED
    export XDG_CONFIG_HOME="$temp_xdg"
    "$module" emit "${args[@]}" 2>&1
  ) || exit_code=$?

  rm -rf "$temp_xdg"
  echo "$output"
  return $exit_code
}

function test_emit_enabled_no_event_type_fails() {
  log_test_step "Testing: emit with no event type fails when broadcasting enabled"

  _emit_with_broadcasting "$MODULE" >/dev/null 2>&1
  local exit_code=$?

  assert_not_equals "$exit_code" "0" \
    "emit with no event type should fail when broadcasting is enabled"
}

function test_emit_enabled_no_event_shows_usage() {
  log_test_step "Testing: emit with no event type shows usage when broadcasting enabled"

  local output
  output=$(_emit_with_broadcasting "$MODULE" 2>&1 || true)

  assert_contains "$output" "event-type" \
    "emit with no event type should show event-type in usage"
}

function test_emit_enabled_help_flag_shows_usage() {
  log_test_step "Testing: emit --help shows usage when broadcasting enabled"

  _emit_with_broadcasting "$MODULE" --help >/dev/null 2>&1
  local exit_code=$?

  assert_equals "$exit_code" "0" \
    "emit --help should succeed when broadcasting is enabled"

  local output
  output=$(_emit_with_broadcasting "$MODULE" --help 2>&1)

  assert_contains "$output" "event-type" \
    "emit --help should show event-type usage when broadcasting is enabled"
}

function test_emit_enabled_invalid_event_fails() {
  log_test_step "Testing: emit with invalid event type fails when broadcasting enabled"

  _emit_with_broadcasting "$MODULE" invalid-event-type-xyz >/dev/null 2>&1
  local exit_code=$?

  assert_not_equals "$exit_code" "0" \
    "emit with invalid event type should fail when broadcasting is enabled"
}

function test_emit_enabled_invalid_event_error_message() {
  log_test_step "Testing: emit with invalid event type shows error message when broadcasting enabled"

  local output
  output=$(_emit_with_broadcasting "$MODULE" invalid-event-xyz 2>&1 || true)

  assert_contains "$output" "Invalid event type" \
    "emit with invalid event type should show 'Invalid event type' error"
}

function test_emit_enabled_missing_params_fails() {
  log_test_step "Testing: emit with missing required parameters fails when broadcasting enabled"

  # instance-created requires: instance blueprint (2 params)
  _emit_with_broadcasting "$MODULE" instance-created >/dev/null 2>&1
  local exit_code=$?

  assert_not_equals "$exit_code" "0" \
    "emit instance-created with no params should fail when broadcasting is enabled"
}

function test_emit_enabled_missing_params_error_message() {
  log_test_step "Testing: emit with missing parameters shows error message when broadcasting enabled"

  local output
  output=$(_emit_with_broadcasting "$MODULE" instance-created 2>&1 || true)

  assert_contains "$output" "parameters" \
    "emit with missing params should show parameters error"
}

# =============================================================================
# socket DELEGATION TESTS
# =============================================================================

function test_socket_help_delegation() {
  log_test_step "Testing: socket help delegates to events.socket.sh"

  assert_command_succeeds "$MODULE socket help" \
    "socket help should succeed"

  assert_command_output "$MODULE socket help" "Socket" \
    "socket help output should contain Socket"
}

function test_socket_status_delegation() {
  log_test_step "Testing: socket status delegates to events.socket.sh"

  assert_command_succeeds "$MODULE socket status" \
    "socket status should succeed"
}

function test_socket_help_flag_delegation() {
  log_test_step "Testing: socket --help delegates to events.socket.sh"

  assert_command_succeeds "$MODULE socket --help" \
    "socket --help should succeed"
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

