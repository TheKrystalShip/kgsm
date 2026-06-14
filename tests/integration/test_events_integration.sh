#!/usr/bin/env bash

# KGSM Events Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/events.sh, commands/events.socket.sh,
#         and commands/events.webhook.sh
#
# Integration points tested:
# - events.sh status aggregates output from both socket and webhook transports
# - events.sh delegates socket/webhook sub-commands to the transport modules
# - events.sh test command routes to the correct transport
# - events.sh emit with broadcasting disabled always succeeds
# - events.sh emit with broadcasting enabled validates event type
# - events.sh emit with valid event + no transports fails at delivery
# - Socket transport enable/disable cycle reflects in config and status
# - Webhook transport enable/disable cycle reflects in config and status
# - events.socket.sh emit is graceful when no socket file exists
# - events.webhook.sh emit fails when no URLs are configured
# - events.sh test all fails when no transports are enabled

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="events_integration"
readonly EVENTS_MODULE="$KGSM_ROOT/commands/events.sh"
readonly SOCKET_MODULE="$KGSM_ROOT/commands/events.socket.sh"
readonly WEBHOOK_MODULE="$KGSM_ROOT/commands/events.webhook.sh"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Config variables are loaded once via bootstrap and exported to the environment.
# Subprocess commands inherit these exported variables (KGSM_BOOTSTRAP_LOADED is
# set, so bootstrap skips config re-load and uses the inherited config_* values).
# We can therefore control subprocess behavior by exporting config_* variables.

function _enable_broadcasting() {
  export config_enable_event_broadcasting="true"
}

function _disable_broadcasting() {
  export config_enable_event_broadcasting="false"
}

function _enable_socket_events() {
  export config_enable_socket_events="true"
}

function _disable_socket_events() {
  export config_enable_socket_events="false"
}

function _enable_webhook_events() {
  export config_enable_webhook_events="true"
}

function _disable_webhook_events() {
  export config_enable_webhook_events="false"
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up events integration tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_not_null "$KGSM_TEST_SANDBOX" "KGSM_TEST_SANDBOX should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"

  assert_file_exists "$EVENTS_MODULE" "events.sh module should exist"
  assert_file_executable "$EVENTS_MODULE" "events.sh module should be executable"

  assert_file_exists "$SOCKET_MODULE" "events.socket.sh module should exist"
  assert_file_executable "$SOCKET_MODULE" "events.socket.sh module should be executable"

  assert_file_exists "$WEBHOOK_MODULE" "events.webhook.sh module should exist"
  assert_file_executable "$WEBHOOK_MODULE" "events.webhook.sh module should be executable"

  assert_file_exists "$KGSM_ROOT/config.ini" "config.ini should exist in sandbox"

  log_test_step "Events integration test environment validated"
}

# =============================================================================
# TEST 1: events.sh status aggregates both transport outputs
# events.sh status must invoke both events.socket.sh status and
# events.webhook.sh status, producing a combined output.
# =============================================================================

function test_status_aggregates_both_transports() {
  log_test_step "Testing: events.sh status aggregates socket and webhook transport status"

  assert_command_succeeds "$EVENTS_MODULE status" \
    "events.sh status should succeed"

  local output
  output=$("$EVENTS_MODULE" status 2>&1)

  assert_contains "$output" "Unix Domain Socket" \
    "events.sh status should include Unix Domain Socket transport section"

  assert_contains "$output" "Webhook" \
    "events.sh status should include Webhook transport section"
}

# =============================================================================
# TEST 2: events.sh delegates 'socket status' to events.socket.sh
# Both commands should produce the same core content.
# =============================================================================

function test_socket_delegation_status() {
  log_test_step "Testing: events.sh socket status delegates to events.socket.sh status"

  local events_output
  events_output=$("$EVENTS_MODULE" socket status 2>&1)
  local events_exit=$?

  local socket_output
  socket_output=$("$SOCKET_MODULE" status 2>&1)
  local socket_exit=$?

  assert_equals 0 "$events_exit" "events.sh socket status should succeed"
  assert_equals 0 "$socket_exit" "events.socket.sh status should succeed"

  # Both outputs should contain the same section header
  assert_contains "$events_output" "Unix Domain Socket" \
    "events.sh socket status should show socket section header"

  assert_contains "$socket_output" "Unix Domain Socket" \
    "events.socket.sh status should show socket section header"

  # Both should reflect the same enabled/disabled state
  assert_contains "$events_output" "Disabled" \
    "events.sh socket status should show Disabled by default"

  assert_contains "$socket_output" "Disabled" \
    "events.socket.sh status should show Disabled by default"
}

# =============================================================================
# TEST 3: events.sh delegates 'webhook status' to events.webhook.sh
# Both commands should produce the same core content.
# =============================================================================

function test_webhook_delegation_status() {
  log_test_step "Testing: events.sh webhook status delegates to events.webhook.sh status"

  local events_output
  events_output=$("$EVENTS_MODULE" webhook status 2>&1)
  local events_exit=$?

  local webhook_output
  webhook_output=$("$WEBHOOK_MODULE" status 2>&1)
  local webhook_exit=$?

  assert_equals 0 "$events_exit" "events.sh webhook status should succeed"
  assert_equals 0 "$webhook_exit" "events.webhook.sh status should succeed"

  # Both outputs should contain the webhook section header
  assert_contains "$events_output" "Webhook" \
    "events.sh webhook status should show Webhook section header"

  assert_contains "$webhook_output" "Webhook" \
    "events.webhook.sh status should show Webhook section header"

  # Both should reflect disabled by default
  assert_contains "$events_output" "Disabled" \
    "events.sh webhook status should show Disabled by default"

  assert_contains "$webhook_output" "Disabled" \
    "events.webhook.sh status should show Disabled by default"
}

# =============================================================================
# TEST 4: events.sh test all fails when no transports are enabled
# When both socket and webhook transports are disabled, 'test all' must fail.
# =============================================================================

function test_test_all_fails_with_no_transports() {
  log_test_step "Testing: events.sh test all fails when no transports are enabled"

  # Ensure both transports are disabled (default state in sandbox)
  _disable_broadcasting
  _disable_socket_events
  _disable_webhook_events

  assert_command_fails "$EVENTS_MODULE test all" \
    "events.sh test all should fail when no transports are enabled"

  local output
  output=$("$EVENTS_MODULE" test all 2>&1 || true)

  assert_contains "$output" "No event transports are enabled" \
    "Should report that no transports are enabled"
}

# =============================================================================
# TEST 5: events.sh test with invalid transport fails
# An unknown transport name must be rejected.
# =============================================================================

function test_test_invalid_transport_fails() {
  log_test_step "Testing: events.sh test with invalid transport fails"

  assert_command_fails "$EVENTS_MODULE test bogus_transport_xyz" \
    "events.sh test with invalid transport should fail"

  local output
  output=$("$EVENTS_MODULE" test bogus_transport_xyz 2>&1 || true)

  assert_contains "$output" "Unknown transport" \
    "Should report unknown transport"
}

# =============================================================================
# TEST 6: events.sh test without transport argument fails
# Missing argument must produce an error.
# =============================================================================

function test_test_missing_transport_fails() {
  log_test_step "Testing: events.sh test without transport argument fails"

  assert_command_fails "$EVENTS_MODULE test" \
    "events.sh test without argument should fail"

  local output
  output=$("$EVENTS_MODULE" test 2>&1 || true)

  assert_contains "$output" "Transport argument required" \
    "Should report that transport argument is required"
}

# =============================================================================
# TEST 7: events.sh emit with broadcasting disabled always succeeds
# When config_enable_event_broadcasting=false, emit exits 0 unconditionally.
# =============================================================================

function test_emit_with_broadcasting_disabled_returns_success() {
  log_test_step "Testing: events.sh emit returns success when broadcasting is disabled"

  _disable_broadcasting

  assert_command_succeeds "$EVENTS_MODULE emit instance-created test-server factorio" \
    "emit should succeed when broadcasting is disabled"

  # Even with invalid event name, should succeed (disabled = early return)
  assert_command_succeeds "$EVENTS_MODULE emit completely-invalid-event-xyz" \
    "emit with invalid event should succeed when broadcasting is disabled"
}

# =============================================================================
# TEST 8: events.sh emit without arguments fails when broadcasting is enabled
# When broadcasting is enabled, missing event type must be rejected.
# When disabled, emit returns EC_SUCCESS immediately (even with no args).
# =============================================================================

function test_emit_no_arguments_fails() {
  log_test_step "Testing: events.sh emit with no arguments fails when broadcasting is enabled"

  _enable_broadcasting
  _disable_socket_events
  _disable_webhook_events

  assert_command_fails "$EVENTS_MODULE emit" \
    "events.sh emit without arguments should fail when broadcasting is enabled"

  _disable_broadcasting
}

# =============================================================================
# TEST 9: events.sh emit invalid event type when broadcasting enabled fails
# When broadcasting is enabled, invalid event names must be rejected.
# =============================================================================

function test_emit_invalid_event_when_enabled_fails() {
  log_test_step "Testing: events.sh emit with invalid event type fails when broadcasting is enabled"

  _enable_broadcasting

  assert_command_fails "$EVENTS_MODULE emit completely-invalid-event-xyz" \
    "emit with invalid event type should fail when broadcasting is enabled"

  local output
  output=$("$EVENTS_MODULE" emit completely-invalid-event-xyz 2>&1 || true)

  assert_contains "$output" "Invalid event type" \
    "Should report invalid event type"

  _disable_broadcasting
}

# =============================================================================
# TEST 10: events.sh emit valid event when broadcasting enabled but no transports
# When enabled and event is valid but no transports are configured, delivery fails.
# =============================================================================

function test_emit_valid_event_no_transports_fails() {
  log_test_step "Testing: events.sh emit valid event fails when no transports are configured"

  _enable_broadcasting
  _disable_socket_events
  _disable_webhook_events

  assert_command_fails "$EVENTS_MODULE emit instance-created test-server factorio" \
    "emit should fail when no transports are configured"

  _disable_broadcasting
}

# =============================================================================
# TEST 11: events.socket.sh emit is graceful when no socket file exists
# When no socket file exists, emit returns 0 (sends to nothing, no error).
# =============================================================================

function test_socket_emit_graceful_with_no_socket_file() {
  log_test_step "Testing: events.socket.sh emit is graceful when no socket file exists"

  # Ensure socket file doesn't exist
  local socket_file="$KGSM_ROOT/kgsm.sock"
  rm -f "$socket_file"
  assert_file_not_exists "$socket_file" "Socket file should not exist before test"

  local test_payload
  test_payload='{"EventType":"test_event","Data":{"InstanceName":"test"},"Timestamp":"2024-01-01T00:00:00Z"}'

  assert_command_succeeds "$SOCKET_MODULE emit '$test_payload'" \
    "events.socket.sh emit should succeed gracefully when no socket file exists"
}

# =============================================================================
# TEST 12: events.webhook.sh emit fails when no URLs are configured
# Webhook emit must fail if no URLs are set.
# =============================================================================

function test_webhook_emit_fails_with_no_urls() {
  log_test_step "Testing: events.webhook.sh emit fails when no webhook URLs configured"

  local test_payload
  test_payload='{"EventType":"test_event","Data":{"InstanceName":"test"},"Timestamp":"2024-01-01T00:00:00Z"}'

  assert_command_fails "$WEBHOOK_MODULE emit '$test_payload'" \
    "events.webhook.sh emit should fail when no webhook URLs are configured"

  local output
  output=$("$WEBHOOK_MODULE" emit "$test_payload" 2>&1 || true)

  assert_contains "$output" "Webhook URLs not configured" \
    "Should report that webhook URLs are not configured"
}

# =============================================================================
# TEST 13: events.socket.sh status shows disabled by default
# Default config has socket transport disabled.
# =============================================================================

function test_socket_status_shows_disabled_by_default() {
  log_test_step "Testing: events.socket.sh status shows Disabled in default config"

  assert_command_succeeds "$SOCKET_MODULE status" \
    "events.socket.sh status should always succeed"

  local output
  output=$("$SOCKET_MODULE" status 2>&1)

  assert_contains "$output" "Disabled" \
    "Socket status should show Disabled in default config"
}

# =============================================================================
# TEST 14: events.webhook.sh status shows disabled by default
# Default config has webhook transport disabled.
# =============================================================================

function test_webhook_status_shows_disabled_by_default() {
  log_test_step "Testing: events.webhook.sh status shows Disabled in default config"

  assert_command_succeeds "$WEBHOOK_MODULE status" \
    "events.webhook.sh status should always succeed"

  local output
  output=$("$WEBHOOK_MODULE" status 2>&1)

  assert_contains "$output" "Disabled" \
    "Webhook status should show Disabled in default config"
}

# =============================================================================
# TEST 15: events.socket.sh disable command shows the disabling message
# Disable returns EC_SUCCESS_CONFIG_SET (240), not 0.
# Verify via output inspection.
# =============================================================================

function test_socket_disable_command() {
  log_test_step "Testing: events.socket.sh disable command shows disabling message"

  local output
  output=$("$SOCKET_MODULE" disable 2>&1 || true)

  assert_contains "$output" "Disabling Unix Domain Socket" \
    "disable output should mention 'Disabling Unix Domain Socket'"
}

# =============================================================================
# TEST 16: events.webhook.sh disable command shows the disabling message
# Disable returns EC_SUCCESS_CONFIG_SET (240), not 0.
# Verify via output inspection.
# =============================================================================

function test_webhook_disable_command() {
  log_test_step "Testing: events.webhook.sh disable command shows disabling message"

  local output
  output=$("$WEBHOOK_MODULE" disable 2>&1 || true)

  assert_contains "$output" "Disabling HTTP webhook" \
    "disable output should mention 'Disabling HTTP webhook'"
}

# =============================================================================
# TEST 17: events.socket.sh enable/disable cycle (requires socat)
# If socat is available: enable and disable produce the expected output messages.
# Note: enable/disable return EC_SUCCESS_CONFIG_SET (240) not 0, so we use
# output inspection with '|| true' rather than assert_command_succeeds.
# =============================================================================

function test_socket_enable_disable_cycle() {
  log_test_step "Testing: events.socket.sh enable/disable cycle"

  if ! command -v socat > /dev/null 2>&1; then
    skip_test "socat not available - skipping socket enable/disable cycle test"
    return
  fi

  # Enable socket transport - verify output message
  local enable_output
  enable_output=$("$SOCKET_MODULE" enable 2>&1 || true)

  assert_contains "$enable_output" "Enabling Unix Domain Socket" \
    "enable output should mention 'Enabling Unix Domain Socket'"

  # Disable socket transport - verify output message
  local disable_output
  disable_output=$("$SOCKET_MODULE" disable 2>&1 || true)

  assert_contains "$disable_output" "Disabling Unix Domain Socket" \
    "disable output should mention 'Disabling Unix Domain Socket'"
}

# =============================================================================
# TEST 18: events.webhook.sh enable/disable cycle (requires wget)
# If wget is available: enable and disable produce the expected output messages.
# Note: enable/disable return EC_SUCCESS_CONFIG_SET (240) not 0, so we use
# output inspection with '|| true' rather than assert_command_succeeds.
# =============================================================================

function test_webhook_enable_disable_cycle() {
  log_test_step "Testing: events.webhook.sh enable/disable cycle"

  if ! command -v wget > /dev/null 2>&1; then
    skip_test "wget not available - skipping webhook enable/disable cycle test"
    return
  fi

  # Enable webhook transport - verify output message
  local enable_output
  enable_output=$("$WEBHOOK_MODULE" enable 2>&1 || true)

  assert_contains "$enable_output" "Enabling HTTP webhook" \
    "enable output should mention 'Enabling HTTP webhook'"

  # Disable webhook transport - verify output message
  local disable_output
  disable_output=$("$WEBHOOK_MODULE" disable 2>&1 || true)

  assert_contains "$disable_output" "Disabling HTTP webhook" \
    "disable output should mention 'Disabling HTTP webhook'"
}

# =============================================================================
# TEST 19: events.sh socket help delegates to events.socket.sh help
# The help for the socket subcommand should come from the transport module.
# =============================================================================

function test_events_socket_help_delegation() {
  log_test_step "Testing: events.sh socket help delegates to events.socket.sh help"

  local events_output
  events_output=$("$EVENTS_MODULE" socket help 2>&1)
  local events_exit=$?

  local socket_output
  socket_output=$("$SOCKET_MODULE" help 2>&1)

  assert_equals 0 "$events_exit" "events.sh socket help should succeed"

  assert_contains "$events_output" "enable" \
    "events.sh socket help should mention enable command"

  assert_contains "$events_output" "disable" \
    "events.sh socket help should mention disable command"

  assert_contains "$socket_output" "enable" \
    "events.socket.sh help should mention enable command"
}

# =============================================================================
# TEST 20: events.sh webhook help delegates to events.webhook.sh help
# The help for the webhook subcommand should come from the transport module.
# =============================================================================

function test_events_webhook_help_delegation() {
  log_test_step "Testing: events.sh webhook help delegates to events.webhook.sh help"

  local events_output
  events_output=$("$EVENTS_MODULE" webhook help 2>&1)
  local events_exit=$?

  local webhook_output
  webhook_output=$("$WEBHOOK_MODULE" help 2>&1)

  assert_equals 0 "$events_exit" "events.sh webhook help should succeed"

  assert_contains "$events_output" "configure" \
    "events.sh webhook help should mention configure command"

  assert_contains "$events_output" "enable" \
    "events.sh webhook help should mention enable command"

  assert_contains "$webhook_output" "configure" \
    "events.webhook.sh help should mention configure command"
}

# =============================================================================
# TEST 21: events.sh test socket routes to socket test (disabled path)
# When socket transport is disabled, the socket test must fail with
# the appropriate message.
# =============================================================================

function test_test_socket_routes_to_socket_module() {
  log_test_step "Testing: events.sh test socket routes to events.socket.sh test"

  _disable_broadcasting

  assert_command_fails "$EVENTS_MODULE test socket" \
    "events.sh test socket should fail when socket transport is disabled"

  local output
  output=$("$EVENTS_MODULE" test socket 2>&1 || true)

  assert_contains "$output" "not enabled" \
    "Should report that socket transport is not enabled"
}

# =============================================================================
# TEST 22: events.sh test webhook routes to webhook test (disabled path)
# When webhook transport is disabled, the webhook test must fail.
# =============================================================================

function test_test_webhook_routes_to_webhook_module() {
  log_test_step "Testing: events.sh test webhook routes to events.webhook.sh test"

  _disable_webhook_events

  assert_command_fails "$EVENTS_MODULE test webhook" \
    "events.sh test webhook should fail when webhook transport is disabled"

  local output
  output=$("$EVENTS_MODULE" test webhook 2>&1 || true)

  assert_contains "$output" "not enabled" \
    "Should report that webhook transport is not enabled"
}

# =============================================================================
# TEST 23: events.socket.sh socket file location is within KGSM_ROOT
# The socket file should be located inside the KGSM root directory.
# =============================================================================

function test_socket_file_path_within_kgsm_root() {
  log_test_step "Testing: socket file path is within KGSM_ROOT"

  local output
  output=$("$SOCKET_MODULE" status 2>&1)

  assert_contains "$output" "$KGSM_ROOT" \
    "Socket status should show socket file path within KGSM_ROOT"
}

# =============================================================================
# TEST 24: emitted event payload carries the Actor field (audit enrichment)
# A real event emitted over the socket transport must include a top-level
# Actor field, and KGSM_EVENT_ACTOR must override the OS-user default. Captures
# the actual _build_event_payload output via a one-shot socat listener.
# =============================================================================

function test_emit_payload_includes_actor() {
  log_test_step "Testing: emitted payload includes Actor and honors KGSM_EVENT_ACTOR"

  if ! command -v socat > /dev/null 2>&1; then
    skip_test "socat not available - skipping payload capture test"
    return
  fi

  # Deterministic socket path (don't depend on sandbox config defaults).
  export config_event_socket_filenames=""
  export config_event_socket_filename="kgsm.sock"
  local socket_file="$KGSM_ROOT/kgsm.sock"
  local capture="$KGSM_TEST_SANDBOX/actor-capture.json"
  rm -f "$socket_file" "$capture"

  # One-shot listener: accept a single connection, copy its bytes to the file.
  socat -u UNIX-LISTEN:"$socket_file",reuseaddr OPEN:"$capture",creat,trunc &
  local listener_pid=$!

  # Bounded wait for the socket node to exist (listen() has run by then, so a
  # connect from emit queues in the backlog — no accept race on Unix sockets).
  local i=0
  while [[ ! -S "$socket_file" && $i -lt 50 ]]; do
    sleep 0.1
    i=$((i + 1))
  done
  # A Unix socket is type -S, not a regular file (-f), so assert_file_exists
  # would wrongly fail here — assert the socket node via assert_true instead.
  local sock_ready="false"
  [[ -S "$socket_file" ]] && sock_ready="true"
  assert_true "$sock_ready" "socat listener should create the socket node"

  _enable_broadcasting
  _enable_socket_events

  # Emit a real lifecycle event with an explicit actor supplied via the env var.
  KGSM_EVENT_ACTOR="discord:tester" "$EVENTS_MODULE" emit instance-started actor-test-server > /dev/null 2>&1 || true

  # Bounded wait for the captured payload to land.
  i=0
  while [[ ! -s "$capture" && $i -lt 50 ]]; do
    sleep 0.1
    i=$((i + 1))
  done

  # Tear down the listener and restore transport config before asserting.
  kill "$listener_pid" 2> /dev/null || true
  wait "$listener_pid" 2> /dev/null || true
  _disable_socket_events
  _disable_broadcasting
  rm -f "$socket_file"

  local payload
  payload=$(cat "$capture" 2> /dev/null)

  assert_not_null "$payload" "Captured event payload should not be empty"
  assert_contains "$payload" '"Actor"' \
    "Emitted payload should include a top-level Actor field"

  local actor
  actor=$(echo "$payload" | jq -r '.Actor' 2> /dev/null)
  assert_equals "discord:tester" "$actor" \
    "Actor should reflect the supplied KGSM_EVENT_ACTOR value"

  # Timestamp is also part of the audit enrichment contract.
  local timestamp
  timestamp=$(echo "$payload" | jq -r '.Timestamp' 2> /dev/null)
  assert_not_null "$timestamp" "Emitted payload should include a Timestamp"
}

