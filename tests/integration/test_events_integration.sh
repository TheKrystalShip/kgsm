#!/usr/bin/env bash

# KGSM Events Integration Tests
#
# Test Type: INTEGRATION
# Target: Interaction between commands/events.sh and commands/events.webhook.sh
#
# Integration points tested:
# - events.sh delegates the webhook sub-command to the transport module
# - events.sh test command routes to the correct transport
# - events.sh emit validates the event type unconditionally
# - events.sh emit appends to the journal, unconditionally
# - the emitted payload's shape, read back off the journal it was written to
# - Webhook transport enable/disable cycle reflects in config and status
# - events.webhook.sh emit fails when no URLs are configured
# - events.sh test all fails when no optional transport is enabled

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="events_integration"
readonly EVENTS_MODULE="$KGSM_ROOT/commands/events.sh"
readonly WEBHOOK_MODULE="$KGSM_ROOT/commands/events.webhook.sh"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Config variables are loaded once via bootstrap and exported to the environment.
# Subprocess commands inherit these exported variables (KGSM_BOOTSTRAP_LOADED is
# set, so bootstrap skips config re-load and uses the inherited config_* values).
# We can therefore control subprocess behavior by exporting config_* variables.

# The segment the last emit landed in, found by asking the directory instead of
# by naming a date. Segment names are dates, so ordinal order is chronological
# and the newest file is the one an emit just appended to — which holds whether
# or not the UTC day turned over between the emit and this lookup, where a
# computed name would fall on the wrong side of midnight.
function _newest_journal_segment() {
  local journal_dir="${config_event_journal_dir:-$KGSM_TEST_SANDBOX/events}"
  find "$journal_dir" -maxdepth 1 -type f -name '*.ndjson' 2> /dev/null | sort | tail -1
}

# The journal is where an emitted event actually lands, so payload-shape tests read
# it back from there. The sandbox redirects event_journal_dir into itself, so this
# never touches the host's real journal.
function _last_journal_event() {
  local segment
  segment=$(_newest_journal_segment)
  [[ -n "$segment" ]] && tail -n 1 "$segment"
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

  assert_file_exists "$WEBHOOK_MODULE" "events.webhook.sh module should exist"
  assert_file_executable "$WEBHOOK_MODULE" "events.webhook.sh module should be executable"

  assert_file_exists "$KGSM_ROOT/config.ini" "config.ini should exist in sandbox"

  log_test_step "Events integration test environment validated"
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
# TEST 4: events.sh test all fails when no optional transport is enabled
# The journal is unconditional and has nothing to test; with the webhook off,
# 'test all' has no transport to exercise and must fail.
# =============================================================================

function test_test_all_fails_with_no_transports() {
  log_test_step "Testing: events.sh test all fails when no optional transport is enabled"

  # Sandbox default: the webhook is off.
  _disable_webhook_events

  assert_command_fails "$EVENTS_MODULE test all" \
    "events.sh test all should fail when no transports are enabled"

  local output
  output=$("$EVENTS_MODULE" test all 2>&1 || true)

  assert_contains "$output" "No optional event transports are enabled" \
    "Should report that no optional transports are enabled"
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
# TEST 7: events.sh emit always validates
# Emission is unconditional, so there is no configuration under which an
# invalid event name is accepted.
# =============================================================================

function test_emit_always_validates_the_event_name() {
  log_test_step "Testing: events.sh emit validates the event name unconditionally"

  assert_command_succeeds "$EVENTS_MODULE emit instance-created test-server factorio" \
    "emit should succeed for a valid event"

  assert_command_fails "$EVENTS_MODULE emit completely-invalid-event-xyz" \
    "emit should fail for an invalid event name"
}

# =============================================================================
# TEST 8: events.sh emit without arguments fails
# A missing event type is always rejected.
# =============================================================================

function test_emit_no_arguments_fails() {
  log_test_step "Testing: events.sh emit with no arguments fails"

  _disable_webhook_events

  assert_command_fails "$EVENTS_MODULE emit" \
    "events.sh emit without arguments should fail"

}

# =============================================================================
# TEST 9: events.sh emit with an invalid event type fails
# Invalid event names are always rejected.
# =============================================================================

function test_emit_invalid_event_when_enabled_fails() {
  log_test_step "Testing: events.sh emit with an invalid event type fails"


  assert_command_fails "$EVENTS_MODULE emit completely-invalid-event-xyz" \
    "emit with an invalid event type should fail"

  local output
  output=$("$EVENTS_MODULE" emit completely-invalid-event-xyz 2>&1 || true)

  assert_contains "$output" "Invalid event type" \
    "Should report invalid event type"

}

# =============================================================================
# TEST 10: events.sh emit succeeds with no optional transport configured
# The journal is the transport, so a valid event is always delivered. Socket
# and webhook are additive: switching both off removes nothing load-bearing.
# =============================================================================

function test_emit_valid_event_succeeds_without_optional_transports() {
  log_test_step "Testing: events.sh emit succeeds when only the journal receives it"

  _disable_webhook_events

  assert_command_succeeds "$EVENTS_MODULE emit instance-created test-server factorio" \
    "emit should succeed when the journal is the only transport"

  local segment
  segment=$(_newest_journal_segment)
  assert_not_null "$segment" \
    "the journal segment should exist after emitting"
  assert_file_contains "$segment" '"EventType":"instance_created"' \
    "the journal should carry the emitted event"
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
# TEST 24: emitted event payload carries the Actor field (audit enrichment)
# A real emitted event must carry a top-level Actor field, and KGSM_EVENT_ACTOR
# must override the OS-user default. Read back off the journal the emit wrote to,
# so this pins the actual _build_event_payload output rather than the template.
# =============================================================================

function test_emit_payload_includes_actor() {
  log_test_step "Testing: emitted payload includes Actor and honors KGSM_EVENT_ACTOR"

  # Emit a real lifecycle event with an explicit actor supplied via the env var.
  KGSM_EVENT_ACTOR="discord:tester" "$EVENTS_MODULE" emit instance-started actor-test-server > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)

  assert_not_null "$payload" "Journaled event payload should not be empty"
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

  # Origin is the companion provenance field (which surface drove the event). It was
  # NOT supplied on this emit, so it must serialize as JSON null — an undeclared
  # surface is never fabricated, unlike the actor's honest OS-user fallback.
  assert_contains "$payload" '"Origin"' \
    "Emitted payload should include a top-level Origin field"
  local origin
  origin=$(echo "$payload" | jq -r '.Origin' 2> /dev/null)
  assert_equals "null" "$origin" \
    "Origin must be null when KGSM_EVENT_ORIGIN is unset (never fabricated)"
}

# =============================================================================
# TEST 25: emitted event payload honors KGSM_EVENT_ORIGIN (provenance override)
# The companion to TEST 24: when a caller supplies a driving surface via
# KGSM_EVENT_ORIGIN, the emitted payload's top-level Origin must reflect it.
# =============================================================================

function test_emit_payload_honors_event_origin() {
  log_test_step "Testing: emitted payload honors KGSM_EVENT_ORIGIN"

  # Emit with both provenance fields supplied via env vars.
  KGSM_EVENT_ACTOR="discord:tester" KGSM_EVENT_ORIGIN="assistant" \
    "$EVENTS_MODULE" emit instance-started origin-test-server > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)

  assert_not_null "$payload" "Journaled event payload should not be empty"

  local origin
  origin=$(echo "$payload" | jq -r '.Origin' 2> /dev/null)
  assert_equals "assistant" "$origin" \
    "Origin should reflect the supplied KGSM_EVENT_ORIGIN value"
}

# =============================================================================
# TEST 26: watchdog crash event payload — structured fields + system provenance
# The autonomous supervisor event instance_crashed carries the structured
# ExitCode/Restarts Data fields, and when the watchdog stamps
# KGSM_EVENT_ACTOR/ORIGIN=system the payload reflects actor=system / origin=system.
# Exercises the EVENT_CONFIGS param-spec -> jq-var mapping AND the env -> payload
# provenance derivation end-to-end (not just the jq template), reading the actual
# _build_event_payload output back off the journal.
# =============================================================================

function test_emit_crashed_payload_carries_fields_and_system_provenance() {
  log_test_step "Testing: instance_crashed payload carries ExitCode/Restarts + system provenance"

  # Emit the crash event exactly as the watchdog does: the autonomous producer names
  # itself as `system:<producer>` and the surface is `system`, with the instance, exit
  # code, and restart-attempt count as the three positional params.
  KGSM_EVENT_ACTOR="system:watchdog" KGSM_EVENT_ORIGIN="system" \
    "$EVENTS_MODULE" emit instance-crashed crash-test-server 139 2 > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  # Event type round-trips to the underscore wire form.
  local event_type
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  assert_equals "instance_crashed" "$event_type" \
    "EventType should be instance_crashed"

  # The structured Data fields: the EVENT_CONFIGS 'instance exit_code restarts' spec
  # maps positionally to jq $instance/$exit_code/$restarts -> Data
  # InstanceName/ExitCode/Restarts.
  local instance exit_code restarts
  instance=$(echo "$payload" | jq -r '.Data.InstanceName' 2> /dev/null)
  exit_code=$(echo "$payload" | jq -r '.Data.ExitCode' 2> /dev/null)
  restarts=$(echo "$payload" | jq -r '.Data.Restarts' 2> /dev/null)
  assert_equals "crash-test-server" "$instance" \
    "Data.InstanceName should carry the instance"
  assert_equals "139" "$exit_code" "Data.ExitCode should carry the exit code"
  assert_equals "2" "$restarts" "Data.Restarts should carry the restart count"

  # Provenance: the env -> payload derivation must carry the producer's own stamp
  # through (the one the watchdog applies via EmitWithProvenance).
  local actor origin
  actor=$(echo "$payload" | jq -r '.Actor' 2> /dev/null)
  origin=$(echo "$payload" | jq -r '.Origin' 2> /dev/null)
  assert_equals "system:watchdog" "$actor" "Actor should reflect KGSM_EVENT_ACTOR"
  assert_equals "system" "$origin" "Origin should reflect KGSM_EVENT_ORIGIN=system"
}

function test_emit_ports_opened_payload_carries_structured_ports() {
  log_test_step "Testing: instance_ports_opened payload carries structured [{start,end,protocol}] ports"

  # Emit exactly as the firewall command layer does: the instance, then the
  # UFW-format port spec as the single 'ports' positional param.
  "$EVENTS_MODULE" emit instance-ports-opened ports-test-server '34197/udp|27015:27020/tcp' \
    > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type instance
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  instance=$(echo "$payload" | jq -r '.Data.InstanceName' 2> /dev/null)
  assert_equals "instance_ports_opened" "$event_type" \
    "EventType should be instance_ports_opened"
  assert_equals "ports-test-server" "$instance" \
    "Data.InstanceName should carry the instance"

  # Ports must be the canonical STRUCTURED array, range-preserving — never the
  # opaque UFW string. This is the one non-string Data field built via --argjson.
  local ports_type ports_len
  ports_type=$(echo "$payload" | jq -r '.Data.Ports | type' 2> /dev/null)
  ports_len=$(echo "$payload" | jq -r '.Data.Ports | length' 2> /dev/null)
  assert_equals "array" "$ports_type" "Data.Ports should be a JSON array, not a string"
  assert_equals "2" "$ports_len" "Data.Ports should carry both entries"

  local p0 p1
  p0=$(echo "$payload" | jq -c '.Data.Ports[0]' 2> /dev/null)
  p1=$(echo "$payload" | jq -c '.Data.Ports[1]' 2> /dev/null)
  assert_equals '{"start":34197,"end":34197,"protocol":"udp"}' "$p0" \
    "First entry should be the single udp port"
  assert_equals '{"start":27015,"end":27020,"protocol":"tcp"}' "$p1" \
    "Second entry should preserve the tcp range"
}

# =============================================================================
# TEST: instance_player_joined renders id AND name when both are supplied.
# Reads the real _build_event_payload output back off the journal to prove the
# PlayerId/PlayerName Data shape (the keys this repo DEFINES — only the param
# names were frozen in the contract, not the Data keys).
# =============================================================================

function test_emit_player_joined_payload_carries_id_and_name() {
  log_test_step "Testing: instance_player_joined payload carries PlayerId and PlayerName"

  # Emit exactly as the watchdog forwarder does: instance, player_id, player_name
  # as the three positional params (the latter two are NOT in EVENT_CONFIGS).
  "$EVENTS_MODULE" emit instance-player-joined player-test-server \
    "76561198000000000" "Alice" > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type instance player_id player_name
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  instance=$(echo "$payload" | jq -r '.Data.InstanceName' 2> /dev/null)
  player_id=$(echo "$payload" | jq -r '.Data.PlayerId' 2> /dev/null)
  player_name=$(echo "$payload" | jq -r '.Data.PlayerName' 2> /dev/null)

  assert_equals "instance_player_joined" "$event_type" \
    "EventType should be instance_player_joined"
  assert_equals "player-test-server" "$instance" \
    "Data.InstanceName should carry the instance"
  assert_equals "76561198000000000" "$player_id" \
    "Data.PlayerId should carry the supplied id"
  assert_equals "Alice" "$player_name" \
    "Data.PlayerName should carry the supplied name"
}

# =============================================================================
# TEST: the HONEST-NULL behaviour — the whole point of the nullable contract.
# A left event with only a name (no id) must render Data.PlayerId as JSON null,
# NOT an empty string masquerading as a real id. Asserts both the jq `type` is
# `null` and that the value is not "".
# =============================================================================

function test_emit_player_left_payload_renders_missing_id_as_json_null() {
  log_test_step "Testing: instance_player_left renders an absent player_id as JSON null"

  # Only a name is known: pass an EMPTY player_id positional, then the name. The
  # empty id must surface as JSON null, never the string "".
  "$EVENTS_MODULE" emit instance-player-left player-test-server \
    "" "Bob" > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type player_name id_type player_name_type
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  player_name=$(echo "$payload" | jq -r '.Data.PlayerName' 2> /dev/null)
  # `type` distinguishes a real JSON null from the string "" — the whole point.
  id_type=$(echo "$payload" | jq -r '.Data.PlayerId | type' 2> /dev/null)
  player_name_type=$(echo "$payload" | jq -r '.Data.PlayerName | type' 2> /dev/null)

  assert_equals "instance_player_left" "$event_type" \
    "EventType should be instance_player_left"
  assert_equals "null" "$id_type" \
    "Data.PlayerId should be JSON null when no id is supplied (not an empty string)"
  assert_equals "string" "$player_name_type" \
    "Data.PlayerName should remain a JSON string when supplied"
  assert_equals "Bob" "$player_name" \
    "Data.PlayerName should carry the supplied name"
}

# =============================================================================
# TEST: instance_player_joined renders PlayerAddr as JSON null when absent and
# always carries the SessionKey. Mirrors a Steam-relay-style game (Valheim):
# no real network address, correlation rides an opaque session token instead.
# =============================================================================

function test_emit_player_joined_payload_carries_addr_and_session_key() {
  log_test_step "Testing: instance_player_joined payload renders PlayerAddr null and carries SessionKey"

  # No real network address (empty addr positional), only an opaque session
  # token. Params: instance, player_id, player_name, player_addr, session_key.
  "$EVENTS_MODULE" emit instance-player-joined player-test-server \
    "" "Carol" "" "651023867:1" > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local addr_type session_key
  addr_type=$(echo "$payload" | jq -r '.Data.PlayerAddr | type' 2> /dev/null)
  session_key=$(echo "$payload" | jq -r '.Data.SessionKey' 2> /dev/null)

  assert_equals "null" "$addr_type" \
    "Data.PlayerAddr should be JSON null when no addr is supplied (not an empty string)"
  assert_equals "651023867:1" "$session_key" \
    "Data.SessionKey should carry the supplied session key (never null-coalesced)"
}

# =============================================================================
# TEST: instance_player_left carries a real Reason when the game logs one
# (e.g. Core Keeper's "App_Min"), and renders it as JSON null when absent —
# the same honest-null rule as PlayerId/PlayerName/PlayerAddr.
# =============================================================================

function test_emit_player_left_payload_carries_reason() {
  log_test_step "Testing: instance_player_left payload carries a real Reason"

  # Params: instance, player_id, player_name, player_addr, session_key, reason.
  "$EVENTS_MODULE" emit instance-player-left player-test-server \
    "" "" "" "userid:3801603394" "App_Min" > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local reason
  reason=$(echo "$payload" | jq -r '.Data.Reason' 2> /dev/null)

  assert_equals "App_Min" "$reason" \
    "Data.Reason should carry the supplied disconnect reason"
}

function test_emit_player_left_payload_renders_missing_reason_as_json_null() {
  log_test_step "Testing: instance_player_left renders an absent Reason as JSON null"

  # Reason positional (6th) left empty — the game's quit path logged nothing.
  "$EVENTS_MODULE" emit instance-player-left player-test-server \
    "" "Bob" "" "sess-key-1" "" > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local reason_type
  reason_type=$(echo "$payload" | jq -r '.Data.Reason | type' 2> /dev/null)

  assert_equals "null" "$reason_type" \
    "Data.Reason should be JSON null when no reason is supplied (not an empty string)"
}

# =============================================================================
# TEST: instance_config_changed carries the Key but NEVER the value.
# This is the entire reason the event is key-only: instance config holds secrets
# (RCON/admin passwords, tokens), so the value must never reach a transport. We
# emit with a sentinel secret value and prove (a) Data.Key carries the key, and
# (b) the captured payload contains NEITHER the sentinel value NOR a `Value`
# Data field — pinning the security property directly, not just "carries Key".
# =============================================================================

function test_emit_config_changed_payload_carries_key_never_value() {
  log_test_step "Testing: instance_config_changed payload carries Key but never the value"

  # Emit exactly as the config-set command layer does: instance, then the key.
  # The event interface itself takes ONLY instance + key — there is no value
  # parameter at all, so the value structurally cannot enter the payload. The
  # `has("Value") == false` assertion below pins that the Data contract is
  # key-only. (The end-to-end "a secret config value never leaks" property is
  # proven by the live `config-set <key>=<secret>` path, where the value actually
  # exists — that path is outside this transport-level test.)
  "$EVENTS_MODULE" emit instance-config-changed config-test-server rcon_password \
    > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type instance key
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  instance=$(echo "$payload" | jq -r '.Data.InstanceName' 2> /dev/null)
  key=$(echo "$payload" | jq -r '.Data.Key' 2> /dev/null)

  assert_equals "instance_config_changed" "$event_type" \
    "EventType should be instance_config_changed"
  assert_equals "config-test-server" "$instance" \
    "Data.InstanceName should carry the instance"
  assert_equals "rcon_password" "$key" \
    "Data.Key should carry the changed key"

  # The security property: the Data object must carry NO `Value` field — the value
  # is never part of the event contract (instance config holds secrets like
  # RCON/admin passwords).
  local has_value
  has_value=$(echo "$payload" | jq -r '.Data | has("Value")' 2> /dev/null)
  assert_equals "false" "$has_value" \
    "Data must NOT contain a Value field (instance config holds secrets)"
}


# =============================================================================
# BLUEPRINT EVENT PAYLOAD — blueprint-scoped Data, real booleans, honest nulls
# =============================================================================
# The blueprint events are the only ones whose Data is keyed on BlueprintName
# instead of InstanceName, and the only ones carrying real JSON booleans. Both
# properties live in the _build_event_payload jq template, so they are proven
# here against the actual payload read back off the journal, not by inspecting
# the template. Also pins the two contracts the downstream audit row depends on: a
# human's actor/origin survives the emit (a browser edit must not be attributed
# to a service account), and the file CONTENT never appears in the payload.
# =============================================================================

function test_emit_blueprint_updated_payload_is_blueprint_scoped() {
  log_test_step "Testing: blueprint_updated payload keys Data on BlueprintName with real booleans"

  # Emit exactly as kgsm-lib does for a browser edit: the human's identity is
  # threaded through, NOT the hardcoded system stamp the watchdog uses.
  KGSM_EVENT_ACTOR="discord:123456789" KGSM_EVENT_ORIGIN="ui" \
    "$EVENTS_MODULE" emit blueprint-updated terraria user true native > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type name tier runtime
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  name=$(echo "$payload" | jq -r '.Data.BlueprintName' 2> /dev/null)
  tier=$(echo "$payload" | jq -r '.Data.Tier' 2> /dev/null)
  runtime=$(echo "$payload" | jq -r '.Data.Runtime' 2> /dev/null)

  assert_equals "blueprint_updated" "$event_type" \
    "EventType should be blueprint_updated"
  assert_equals "terraria" "$name" \
    "Data.BlueprintName should carry the blueprint name"
  assert_equals "user" "$tier" \
    "Data.Tier should carry the tier (only ever 'user')"
  assert_equals "native" "$runtime" \
    "Data.Runtime should carry the runtime when known"

  # Not instance-scoped: an InstanceName key here would be a fabricated subject,
  # and would make the event join against the wrong entity downstream.
  local has_instance
  has_instance=$(echo "$payload" | jq -r '.Data | has("InstanceName")' 2> /dev/null)
  assert_equals "false" "$has_instance" \
    "Data must NOT contain an InstanceName field (blueprint events are not instance-scoped)"

  # OverridesSystem must be a real JSON boolean, not the string "true" — the
  # catalog badge and the audit row both branch on it.
  local overrides overrides_type
  overrides=$(echo "$payload" | jq -r '.Data.OverridesSystem' 2> /dev/null)
  overrides_type=$(echo "$payload" | jq -r '.Data.OverridesSystem | type' 2> /dev/null)
  assert_equals "boolean" "$overrides_type" \
    "Data.OverridesSystem should be a JSON boolean, not a string"
  assert_equals "true" "$overrides" \
    "Data.OverridesSystem should be true when the blueprint shadows a shipped one"

  # The human's provenance survives: without this the audit row would attribute
  # an admin's browser edit to whatever OS user the service runs as.
  local actor origin
  actor=$(echo "$payload" | jq -r '.Actor' 2> /dev/null)
  origin=$(echo "$payload" | jq -r '.Origin' 2> /dev/null)
  assert_equals "discord:123456789" "$actor" \
    "Actor should carry the human principal, not a service account"
  assert_equals "ui" "$origin" "Origin should reflect the driving surface"

  # The blueprint CONTENT is never carried: a blueprint can hold credentials and
  # the payload fans out to every enabled transport.
  local has_content
  has_content=$(echo "$payload" | jq -r '.Data | has("Content")' 2> /dev/null)
  assert_equals "false" "$has_content" \
    "Data must NOT contain the blueprint content (it can hold credentials)"

  # Every payload stamps the running version. Asserted here because this test
  # reaches the emit through the module directly rather than through kgsm.sh:
  # the version has to resolve the same way for every entrypoint, so a value
  # that only appears on the kgsm.sh path is a broken contract, not a detail.
  local producer_version
  producer_version=$(echo "$payload" | jq -r '.ProducerVersion' 2> /dev/null)
  # KGSM_VERSION is exported by core/bootstrap.sh, which the runner sources.
  # shellcheck disable=SC2153
  assert_equals "$KGSM_VERSION" "$producer_version" \
    "ProducerVersion should carry the running version regardless of entrypoint"
  assert_not_equals "unknown" "$producer_version" \
    "ProducerVersion must never fall back to 'unknown'"
}

# =============================================================================
# BLUEPRINT REMOVAL PAYLOAD — RevertedToSystem, and an unknown runtime as null
# =============================================================================
# Proves the honest-null rule on the blueprint events: `false` renders as the
# boolean false (not a string, and not dropped), and a runtime the emitter could
# not determine renders as JSON null rather than an empty string posing as a
# real runtime.
# =============================================================================

function test_emit_blueprint_removed_payload_renders_false_and_null_honestly() {
  log_test_step "Testing: blueprint_removed carries boolean false; unknown runtime renders as null"

  # A custom blueprint with no shipped counterpart: deleting it removes the
  # blueprint from the host entirely, so nothing is reverted to.
  KGSM_EVENT_ACTOR="discord:123456789" KGSM_EVENT_ORIGIN="ui" \
    "$EVENTS_MODULE" emit blueprint-removed mycustomgame user false > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type name reverted reverted_type
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  name=$(echo "$payload" | jq -r '.Data.BlueprintName' 2> /dev/null)
  reverted=$(echo "$payload" | jq -r '.Data.RevertedToSystem' 2> /dev/null)
  reverted_type=$(echo "$payload" | jq -r '.Data.RevertedToSystem | type' 2> /dev/null)

  assert_equals "blueprint_removed" "$event_type" \
    "EventType should be blueprint_removed"
  assert_equals "mycustomgame" "$name" \
    "Data.BlueprintName should carry the blueprint name"
  assert_equals "boolean" "$reverted_type" \
    "Data.RevertedToSystem should be a JSON boolean, not a string"
  assert_equals "false" "$reverted" \
    "Data.RevertedToSystem should be false when nothing is left to revert to"

  # A removal cannot state the runtime of a file that no longer exists.
  local has_runtime
  has_runtime=$(echo "$payload" | jq -r '.Data | has("Runtime")' 2> /dev/null)
  assert_equals "false" "$has_runtime" \
    "blueprint_removed must NOT carry a Runtime (the file is gone)"
}

function test_emit_blueprint_created_payload_renders_unknown_runtime_as_null() {
  log_test_step "Testing: blueprint_created renders an omitted runtime as JSON null"

  # Runtime omitted: the emitter could not read one out of the file. KGSM must
  # report that as unknown, never guess a default.
  "$EVENTS_MODULE" emit blueprint-created mycustomgame user false > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type runtime_type overrides
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  runtime_type=$(echo "$payload" | jq -r '.Data.Runtime | type' 2> /dev/null)
  overrides=$(echo "$payload" | jq -r '.Data.OverridesSystem' 2> /dev/null)

  assert_equals "blueprint_created" "$event_type" \
    "EventType should be blueprint_created"
  assert_equals "null" "$runtime_type" \
    "Data.Runtime should be JSON null when the runtime is unknown, never a guessed default"
  assert_equals "false" "$overrides" \
    "Data.OverridesSystem should be false for a brand-new custom blueprint"
}

function test_emit_backup_deleted_payload_carries_the_backup_id() {
  log_test_step "Testing: instance_backup_deleted payload carries the backup id as Source"

  # Emitted exactly as the delete-backup command layer does: instance, then the
  # backup id. `Source` is the id here, the same field the created/restored
  # events carry it in.
  "$EVENTS_MODULE" emit instance-backup-deleted backup-test-server \
    backup-test-server-20260731T142233Z-a3f9c1 > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type instance source
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  instance=$(echo "$payload" | jq -r '.Data.InstanceName' 2> /dev/null)
  source=$(echo "$payload" | jq -r '.Data.Source' 2> /dev/null)

  assert_equals "instance_backup_deleted" "$event_type" \
    "EventType should be instance_backup_deleted"
  assert_equals "backup-test-server" "$instance" \
    "Data.InstanceName should carry the instance"
  assert_equals "backup-test-server-20260731T142233Z-a3f9c1" "$source" \
    "Data.Source should carry the deleted backup's id"

  # No Version: the deleted backup's manifest is gone with it, and reading the
  # instance's current version would record a fact about the instance, not the
  # backup.
  local has_version
  has_version=$(echo "$payload" | jq -r '.Data | has("Version")' 2> /dev/null)
  assert_equals "false" "$has_version" \
    "Data must NOT contain a Version field (the deleted manifest is gone)"
}

function test_emit_backups_pruned_payload_carries_numeric_counts() {
  log_test_step "Testing: instance_backups_pruned payload carries Deleted/Kept/Pinned as JSON numbers"

  "$EVENTS_MODULE" emit instance-backups-pruned backup-test-server 3 5 2 \
    > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  local event_type instance deleted kept pinned
  event_type=$(echo "$payload" | jq -r '.EventType' 2> /dev/null)
  instance=$(echo "$payload" | jq -r '.Data.InstanceName' 2> /dev/null)
  deleted=$(echo "$payload" | jq -r '.Data.Deleted' 2> /dev/null)
  kept=$(echo "$payload" | jq -r '.Data.Kept' 2> /dev/null)
  pinned=$(echo "$payload" | jq -r '.Data.Pinned' 2> /dev/null)

  assert_equals "instance_backups_pruned" "$event_type" \
    "EventType should be instance_backups_pruned"
  assert_equals "backup-test-server" "$instance" \
    "Data.InstanceName should carry the instance"
  assert_equals "3" "$deleted" "Data.Deleted should carry what was removed"
  assert_equals "5" "$kept" "Data.Kept should carry the retention window"
  # What the sweep protected. Without it, a sweep that removed nothing because
  # every backup was pinned reads exactly like one that found nothing to remove.
  assert_equals "2" "$pinned" "Data.Pinned should carry what the sweep skipped"

  # Counts must be JSON numbers, not strings: a consumer sums them without
  # re-parsing, and kgsm-lib deserializes them into int fields.
  local deleted_type kept_type pinned_type
  deleted_type=$(echo "$payload" | jq -r '.Data.Deleted | type' 2> /dev/null)
  kept_type=$(echo "$payload" | jq -r '.Data.Kept | type' 2> /dev/null)
  pinned_type=$(echo "$payload" | jq -r '.Data.Pinned | type' 2> /dev/null)
  assert_equals "number" "$deleted_type" "Data.Deleted must be a JSON number"
  assert_equals "number" "$kept_type" "Data.Kept must be a JSON number"
  assert_equals "number" "$pinned_type" "Data.Pinned must be a JSON number"

  # A prune reports the sweep, not the ids — one event covers all of them.
  local has_source
  has_source=$(echo "$payload" | jq -r '.Data | has("Source")' 2> /dev/null)
  assert_equals "false" "$has_source" \
    "Data must NOT contain a Source field (a prune is a sweep, not one backup)"
}

# =============================================================================
# TEST: the emitted envelope is v1 — schema version, millisecond timestamp and
# the producer's own version.
#
# Read back off the journal the emit actually wrote to, so this pins
# __logic_build_event_payload's output rather than a template. The envelope is a
# cross-producer contract now: every component that writes a journal writes this
# shape, and a reader merging several of them depends on all three fields.
# =============================================================================

function test_emit_payload_is_a_v1_envelope() {
  log_test_step "Testing: emitted payload carries V, ms timestamp and ProducerVersion"

  "$EVENTS_MODULE" emit instance-started envelope-test-server > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  # V must be a JSON number, not a string: a reader compares it numerically to
  # decide how to read the rest of the line.
  local schema_version schema_type
  schema_version=$(echo "$payload" | jq -r '.V' 2> /dev/null)
  schema_type=$(echo "$payload" | jq -r '.V | type' 2> /dev/null)
  assert_equals "1" "$schema_version" "Envelope should declare schema version 1"
  assert_equals "number" "$schema_type" "V must be a JSON number"

  # Milliseconds are load-bearing: the journal is read merged with every other
  # producer's, and second granularity orders arbitrarily inside each second —
  # exactly where causally adjacent events sit.
  local timestamp
  timestamp=$(echo "$payload" | jq -r '.Timestamp' 2> /dev/null)
  assert_not_null "$timestamp" "Emitted payload should include a Timestamp"
  if [[ ! "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]; then
    fail_test "Timestamp '$timestamp' should be ISO 8601 UTC with milliseconds"
  fi

  # ProducerVersion names whoever emitted the event. KGSMVersion was its v0
  # spelling and must be gone, or a reader would see both and have to guess which
  # one to trust.
  local producer_version
  producer_version=$(echo "$payload" | jq -r '.ProducerVersion' 2> /dev/null)
  assert_not_null "$producer_version" \
    "Emitted payload should include ProducerVersion"
  assert_not_equals "null" "$producer_version" \
    "ProducerVersion should carry the running KGSM version"

  local has_kgsm_version
  has_kgsm_version=$(echo "$payload" | jq -r 'has("KGSMVersion")' 2> /dev/null)
  assert_equals "false" "$has_kgsm_version" \
    "The envelope must NOT carry the v0 KGSMVersion field alongside ProducerVersion"

  # The correlation fields are reserved and KGSM populates none of them. A writer
  # emitting an empty OpId would set a precedent by accident.
  local has_op_id has_run_id has_during
  has_op_id=$(echo "$payload" | jq -r 'has("OpId")' 2> /dev/null)
  has_run_id=$(echo "$payload" | jq -r 'has("RunId")' 2> /dev/null)
  has_during=$(echo "$payload" | jq -r 'has("During")' 2> /dev/null)
  assert_equals "false" "$has_op_id" "OpId is reserved and must be absent"
  assert_equals "false" "$has_run_id" "RunId is reserved and must be absent"
  assert_equals "false" "$has_during" "During is reserved and must be absent"

  # Still one whole line: every consumer's cursor is a byte offset into the
  # journal, so the envelope must never span lines.
  local line_count
  line_count=$(echo "$payload" | wc -l)
  assert_equals "1" "$line_count" "The envelope must be a single line"
}

# =============================================================================
# TEST 31: the envelope spells "not known" the way every other producer does
#
# The journal is read merged across five producers, so a reader meets these
# fields written by four C# writers and by this one. The contract permits a
# nullable field to be omitted OR written as null and treats the two
# identically — but it defines no third state, and an empty string is one: a
# reader checking for null does not find it, and renders a blank where it meant
# to render nothing.
# =============================================================================

function test_emit_envelope_never_writes_an_empty_string() {
  log_test_step "Testing: envelope provenance fields are a value or null, never empty"

  # Neither actor nor origin supplied — the case where an empty value would be
  # easiest to produce by accident.
  env -u KGSM_EVENT_ACTOR -u KGSM_EVENT_ORIGIN \
    "$EVENTS_MODULE" emit instance-started envelope-empty-test > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "Journaled event payload should not be empty"

  # Nobody supplied an actor, and the engine has no way to learn one: it is a
  # stateless CLI, and the OS user it runs as owns the process rather than asking
  # for the action. Null is what "not known" is spelled as — never an empty string,
  # and never a name borrowed from somewhere it does not mean.
  local actor_type
  actor_type=$(echo "$payload" | jq -r '.Actor | type' 2> /dev/null)
  assert_equals "null" "$actor_type" \
    "Actor must be null when no principal was supplied, never a borrowed OS username"

  # Origin genuinely has no honest fallback, so null is correct here. What must
  # never appear is the empty string.
  local origin_type
  origin_type=$(echo "$payload" | jq -r '.Origin | type' 2> /dev/null)
  if [[ "$origin_type" == "string" ]]; then
    local origin
    origin=$(echo "$payload" | jq -r '.Origin' 2> /dev/null)
    assert_not_equals "" "$origin" \
      "Origin must be null or a surface, never an empty string"
  else
    assert_equals "null" "$origin_type" \
      "Origin must be null when no surface drove the event"
  fi

  # Hostname lets a journal be read on its own. A reader that knows where it got a
  # line from trusts that over this field, but it is still always written.
  local hostname
  hostname=$(echo "$payload" | jq -r '.Hostname' 2> /dev/null)
  assert_not_null "$hostname" "Emitted payload should include a Hostname"
  assert_not_equals "null" "$hostname" "Hostname must not be null"
  assert_not_equals "" "$hostname" "Hostname must not be an empty string"
}

# =============================================================================
# TEST 32: an emit missing a required parameter writes nothing at all
#
# This is what keeps an empty payload field unreachable. Validation refuses the
# emit before the envelope is built, so a missing parameter never reaches the
# journal as an empty string, which is the third state TEST 31 guards against.
# =============================================================================

function test_emit_with_a_missing_parameter_writes_nothing() {
  log_test_step "Testing: an emit missing a required parameter appends no line"

  local journal_dir="${config_event_journal_dir:-$KGSM_TEST_SANDBOX/events}"
  local before after
  before=$(cat "$journal_dir"/*.ndjson 2> /dev/null | wc -l)

  # instance-started requires an instance name.
  "$EVENTS_MODULE" emit instance-started > /dev/null 2>&1 || true

  after=$(cat "$journal_dir"/*.ndjson 2> /dev/null | wc -l)
  assert_equals "$before" "$after" \
    "A refused emit must append nothing: a partial event is worse than none"
}

# =============================================================================
# TEST 33: retention ages a segment by its NAME, not its mtime
#
# The rule every producer's writer applies, so a merged page ages uniformly. A
# segment named 2026-05-01 holds that day's events whatever a filesystem thinks;
# an mtime is when the file was last written to, which a restore, a copy or a
# backup tool moves without any event having moved.
# =============================================================================

function test_journal_prune_ages_a_segment_by_its_name() {
  log_test_step "Testing: prune reads the segment name and keeps the boundary day"

  local journal_dir="${config_event_journal_dir:-$KGSM_TEST_SANDBOX/events}"
  mkdir -p "$journal_dir"

  # Prune derives its cutoff from the window it is configured with, so the two
  # segment names are derived from the same knob rather than restating a default
  # that only the command owns.
  local days="${config_event_journal_retention_days:-90}"

  # The names and prune's cutoff have to describe the same UTC day. A day that
  # turns over between them moves the cutoff one day past the names already on
  # disk, which is a fact about when the suite ran rather than about the code.
  # An attempt that straddles a turnover is therefore thrown away and redone on
  # the new day instead of asserted on: a day turns over once, and the body
  # takes milliseconds, so the redo cannot meet a second one.
  local anchor cutoff older
  while :; do
    anchor=$(date -u +%F)
    cutoff=$(date -u -d "$days days ago" +%F)
    older=$(date -u -d "$((days + 1)) days ago" +%F)

    printf '{"V":1}\n' > "$journal_dir/$older.ndjson"
    printf '{"V":1}\n' > "$journal_dir/$cutoff.ndjson"

    # Old by name, brand new by mtime: under an mtime rule this survives, which
    # is exactly the divergence being pinned.
    touch "$journal_dir/$older.ndjson"

    # Not a segment. The directory belongs to this producer, which is a reason to
    # be careful with it rather than a licence to delete whatever is in it.
    printf 'x\n' > "$journal_dir/notes.txt"

    "$KGSM_ROOT/commands/events.journal.sh" prune > /dev/null 2>&1 || true

    if [[ "$(date -u +%F)" == "$anchor" ]]; then
      break
    fi

    rm -f "$journal_dir/$older.ndjson" "$journal_dir/$cutoff.ndjson"
  done

  assert_file_not_exists "$journal_dir/$older.ndjson" \
    "A segment named past the window must be pruned despite a fresh mtime"
  assert_file_exists "$journal_dir/$cutoff.ndjson" \
    "A segment dated exactly on the boundary must be kept"
  assert_file_exists "$journal_dir/notes.txt" \
    "A file that is not a dated segment must be left alone"
}

function test_emit_envelope_carries_a_uuid7_id() {
  log_test_step "Testing: emitted envelope carries its own UUIDv7 id"

  "$EVENTS_MODULE" emit instance-started id-test-server > /dev/null 2>&1 || true

  local payload id
  payload=$(_last_journal_event)
  id=$(echo "$payload" | jq -r '.Id' 2> /dev/null)

  assert_not_null "$id" "Envelope should carry an Id"
  assert_not_equals "null" "$id" "Id should be minted, not null, on a bash that has the builtins"

  # The version nibble and the variant bits, not merely "looks like a uuid": a v4
  # satisfies the loose check and loses the time ordering the format was chosen for.
  if [[ ! "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
    fail_test "Id '$id' is not a UUIDv7"
  else
    pass_test "Id is a well-formed UUIDv7"
  fi
}

function test_emit_gives_two_identical_events_different_ids() {
  log_test_step "Testing: two identical events get different ids"

  # The reason the id is minted and never derived from the line. Two identical
  # events in the same second are two events; a digest folds them into one, which
  # is the defect the engine's own index has.
  "$EVENTS_MODULE" emit instance-started dupe-id-server > /dev/null 2>&1 || true
  local first
  first=$(_last_journal_event | jq -r '.Id' 2> /dev/null)

  "$EVENTS_MODULE" emit instance-started dupe-id-server > /dev/null 2>&1 || true
  local second
  second=$(_last_journal_event | jq -r '.Id' 2> /dev/null)

  assert_not_null "$first" "First event should carry an Id"
  assert_not_equals "$first" "$second" "Two identical events must not share an id"
}

function test_emit_ids_sort_the_way_the_journal_does() {
  log_test_step "Testing: ids are time-ordered, so lexical order matches write order"

  "$EVENTS_MODULE" emit instance-started order-a > /dev/null 2>&1 || true
  local first
  first=$(_last_journal_event | jq -r '.Id' 2> /dev/null)

  "$EVENTS_MODULE" emit instance-started order-b > /dev/null 2>&1 || true
  local second
  second=$(_last_journal_event | jq -r '.Id' 2> /dev/null)

  # The whole reason for v7 over v4. A reader merging producers can range-scan.
  if [[ "$first" < "$second" ]]; then
    pass_test "The later id sorts after the earlier one"
  else
    fail_test "Ids are not time-ordered: '$first' should sort before '$second'"
  fi
}

# =============================================================================
# TEST 32: a malformed actor is refused rather than written through
#
# The actor a caller supplies is the one thing about an event the engine cannot
# check against anything it holds — so the shape is all there is to check, and a
# value that no reader can split into a provider and a name gets dropped. The
# event itself still records: the operation it describes already happened, and an
# unattributed record of a real action beats no record at all.
# =============================================================================

function test_emit_refuses_a_malformed_actor_and_still_records() {
  log_test_step "Testing: a bare-name actor is dropped to null and the event still records"

  KGSM_EVENT_ACTOR="heisen" \
    "$EVENTS_MODULE" emit instance-started malformed-actor-test > /dev/null 2>&1 || true

  local payload
  payload=$(_last_journal_event)
  assert_not_null "$payload" "The event must still be journaled"

  local instance
  instance=$(echo "$payload" | jq -r '.Data.InstanceName' 2> /dev/null)
  assert_equals "malformed-actor-test" "$instance" \
    "The journaled event should be the one just emitted"

  local actor_type
  actor_type=$(echo "$payload" | jq -r '.Actor | type' 2> /dev/null)
  assert_equals "null" "$actor_type" \
    "An OS username supplied as an actor must be dropped, not written through"
}

function test_emit_keeps_an_actor_whose_provider_the_engine_does_not_know() {
  log_test_step "Testing: an unrecognised provider is kept, not coerced"

  # Which providers a host has is its own configuration; the engine holds no list
  # and must not invent one. A well-formed actor from a provider it has never met
  # is carried through for the reader to resolve.
  KGSM_EVENT_ACTOR="github:octocat" \
    "$EVENTS_MODULE" emit instance-started unknown-provider-test > /dev/null 2>&1 || true

  local payload actor
  payload=$(_last_journal_event)
  actor=$(echo "$payload" | jq -r '.Actor' 2> /dev/null)
  assert_equals "github:octocat" "$actor" \
    "An actor from an unknown provider should be carried through unchanged"
}
