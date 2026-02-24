#!/usr/bin/env bash

# KGSM Events Webhook Commands Tests
#
# Test Type: UNIT
# Target: commands/events.webhook.sh CLI interface
#
# Tests the command-level interface for the events.webhook.sh module:
# - Help system (--help, -h, help command, subcommand help)
# - No arguments behavior
# - status command (always succeeds)
# - enable command (wget available; warns about unconfigured URLs)
# - disable command
# - configure --help (skips interactive configure wizard)
# - test command when webhook transport is disabled / URLs not configured
# - emit command argument validation
# - Invalid/unknown command handling
#
# NOTE: The interactive 'configure' command is NOT tested directly since it
# requires stdin input. Only 'configure --help' is tested.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="events_webhook_commands"
readonly MODULE="$KGSM_ROOT/commands/events.webhook.sh"

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_test() {
  log_test_step "Setting up events.webhook.sh command tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "events.webhook.sh command module should exist"
  assert_file_executable "$MODULE" "events.webhook.sh command module should be executable"

  log_test_step "Events webhook command test environment validated"
}

# =============================================================================
# help / usage TESTS
# =============================================================================

function test_help_no_args() {
  log_test_step "Testing: no arguments shows usage and exits non-zero"

  assert_command_fails "$MODULE" \
    "No arguments should fail"

  assert_command_output "$MODULE 2>&1 || true" "Usage" \
    "No arguments should show Usage"
}

function test_help_flag() {
  log_test_step "Testing: --help flag shows usage and succeeds"

  assert_command_succeeds "$MODULE --help" \
    "--help should succeed"

  assert_command_output "$MODULE --help" "Usage" \
    "--help output should contain Usage"
}

function test_help_h_flag() {
  log_test_step "Testing: -h flag shows usage and succeeds"

  assert_command_succeeds "$MODULE -h" \
    "-h should succeed"

  assert_command_output "$MODULE -h" "Usage" \
    "-h output should contain Usage"
}

function test_help_command() {
  log_test_step "Testing: help command shows usage and succeeds"

  assert_command_succeeds "$MODULE help" \
    "help command should succeed"

  assert_command_output "$MODULE help" "Commands" \
    "help output should contain Commands section"
}

function test_help_lists_commands() {
  log_test_step "Testing: help output lists all webhook transport commands"

  local output
  output=$("$MODULE" help 2>&1)

  assert_contains "$output" "enable" \
    "help output should mention enable command"
  assert_contains "$output" "disable" \
    "help output should mention disable command"
  assert_contains "$output" "configure" \
    "help output should mention configure command"
  assert_contains "$output" "test" \
    "help output should mention test command"
  assert_contains "$output" "status" \
    "help output should mention status command"
  assert_contains "$output" "emit" \
    "help output should mention emit command"
}

function test_help_mentions_wget() {
  log_test_step "Testing: help output mentions wget dependency"

  local output
  output=$("$MODULE" help 2>&1)

  assert_contains "$output" "wget" \
    "help output should mention wget as required dependency"
}

function test_help_enable_subcommand() {
  log_test_step "Testing: help enable shows enable-specific help"

  assert_command_succeeds "$MODULE help enable" \
    "help enable should succeed"

  assert_command_output "$MODULE help enable" "Enable" \
    "help enable output should contain Enable"
}

function test_help_disable_subcommand() {
  log_test_step "Testing: help disable shows disable-specific help"

  assert_command_succeeds "$MODULE help disable" \
    "help disable should succeed"

  assert_command_output "$MODULE help disable" "Disable" \
    "help disable output should contain Disable"
}

function test_help_configure_subcommand() {
  log_test_step "Testing: help configure shows configure-specific help"

  assert_command_succeeds "$MODULE help configure" \
    "help configure should succeed"

  assert_command_output "$MODULE help configure" "Configure" \
    "help configure output should contain Configure"
}

function test_help_test_subcommand() {
  log_test_step "Testing: help test shows test-specific help"

  assert_command_succeeds "$MODULE help test" \
    "help test should succeed"

  assert_command_output "$MODULE help test" "Test" \
    "help test output should contain Test"
}

function test_help_status_subcommand() {
  log_test_step "Testing: help status shows status-specific help"

  assert_command_succeeds "$MODULE help status" \
    "help status should succeed"

  assert_command_output "$MODULE help status" "Status" \
    "help status output should contain Status"
}

function test_help_unknown_subcommand_fails() {
  log_test_step "Testing: help with unknown subcommand fails"

  assert_command_fails "$MODULE help nonexistent_command_xyz" \
    "help with unknown subcommand should fail"
}

function test_help_unknown_subcommand_error_message() {
  log_test_step "Testing: help with unknown subcommand shows error"

  assert_command_output "$MODULE help nonexistent_command_xyz 2>&1 || true" "Unknown command" \
    "help with unknown subcommand should show 'Unknown command' error"
}

# =============================================================================
# status TESTS
# =============================================================================

function test_status_succeeds() {
  log_test_step "Testing: status command always succeeds"

  assert_command_succeeds "$MODULE status" \
    "status should succeed regardless of configuration"
}

function test_status_shows_transport_header() {
  log_test_step "Testing: status output shows webhook transport header"

  assert_command_output "$MODULE status" "HTTP Webhook" \
    "status output should contain 'HTTP Webhook' header"
}

function test_status_shows_configuration_section() {
  log_test_step "Testing: status output shows Configuration section"

  assert_command_output "$MODULE status" "Configuration" \
    "status output should contain Configuration section"
}

function test_status_shows_dependencies_section() {
  log_test_step "Testing: status output shows Dependencies section"

  assert_command_output "$MODULE status" "Dependencies" \
    "status output should contain Dependencies section"
}

function test_status_shows_enabled_or_disabled() {
  log_test_step "Testing: status output shows Enabled or Disabled state"

  local output
  output=$("$MODULE" status 2>&1)

  # Status must show either Enabled or Disabled
  local has_status=false
  if [[ "$output" == *"Enabled"* ]] || [[ "$output" == *"Disabled"* ]]; then
    has_status=true
  fi

  assert_true "$has_status" \
    "status output should show either Enabled or Disabled state"
}

function test_status_shows_timeout_setting() {
  log_test_step "Testing: status output shows timeout setting"

  assert_command_output "$MODULE status" "Timeout" \
    "status output should show Timeout setting"
}

function test_status_help_flag() {
  log_test_step "Testing: help status succeeds and shows description"

  assert_command_succeeds "$MODULE help status" \
    "help status should succeed"

  assert_command_output "$MODULE help status" "Displays" \
    "status help should describe what it displays"
}

# =============================================================================
# enable TESTS
# =============================================================================

function test_enable_help_flag() {
  log_test_step "Testing: enable --help shows enable help and succeeds"

  assert_command_succeeds "$MODULE enable --help" \
    "enable --help should succeed"

  assert_command_output "$MODULE enable --help" "Enable" \
    "enable --help output should contain Enable"
}

function test_enable_with_wget_succeeds() {
  log_test_step "Testing: enable shows enabling message when wget is available"

  # wget is available in the test environment
  if ! command -v wget >/dev/null 2>&1; then
    skip_test "wget not available - skipping enable output test"
    return
  fi

  # enable returns EC_SUCCESS_CONFIG_SET (240) on success, not 0.
  # Verify by checking output contains the enabling message.
  assert_command_output "$MODULE enable 2>&1 || true" "Enabling HTTP webhook" \
    "enable output should show 'Enabling HTTP webhook' message"
}

function test_enable_warns_no_urls() {
  log_test_step "Testing: enable warns when no webhook URLs are configured"

  if ! command -v wget >/dev/null 2>&1; then
    skip_test "wget not available - skipping URL warning test"
    return
  fi

  assert_command_output "$MODULE enable 2>&1 || true" "No webhook URLs configured" \
    "enable should warn 'No webhook URLs configured' when none are set"
}

function test_enable_shows_success_message() {
  log_test_step "Testing: enable shows configure hint when no URLs set"

  if ! command -v wget >/dev/null 2>&1; then
    skip_test "wget not available - skipping enable configure hint test"
    return
  fi

  assert_command_output "$MODULE enable 2>&1 || true" "configure" \
    "enable output should suggest running configure to set up endpoints"
}

# =============================================================================
# disable TESTS
# =============================================================================

function test_disable_help_flag() {
  log_test_step "Testing: disable --help shows disable help and succeeds"

  assert_command_succeeds "$MODULE disable --help" \
    "disable --help should succeed"

  assert_command_output "$MODULE disable --help" "Disable" \
    "disable --help output should contain Disable"
}

function test_disable_succeeds() {
  log_test_step "Testing: disable command shows disabling message"

  # disable returns EC_SUCCESS_CONFIG_SET (240), not 0.
  # Verify by checking output contains the disabling message.
  assert_command_output "$MODULE disable 2>&1 || true" "Disabling HTTP webhook" \
    "disable output should show 'Disabling HTTP webhook' message"
}

function test_disable_shows_success_message() {
  log_test_step "Testing: disable command shows transport type in output"

  assert_command_output "$MODULE disable 2>&1 || true" "event transport" \
    "disable output should mention 'event transport'"
}

# =============================================================================
# configure TESTS (--help only; interactive wizard not automated)
# =============================================================================

function test_configure_help_flag() {
  log_test_step "Testing: configure --help shows configure help and succeeds"

  assert_command_succeeds "$MODULE configure --help" \
    "configure --help should succeed"

  assert_command_output "$MODULE configure --help" "Configure" \
    "configure --help output should contain Configure"
}

function test_configure_help_mentions_urls() {
  log_test_step "Testing: configure help mentions webhook URL configuration"

  assert_command_output "$MODULE configure --help" "URLs" \
    "configure --help should mention webhook URLs"
}

function test_configure_help_mentions_timeout() {
  log_test_step "Testing: configure help mentions timeout configuration"

  assert_command_output "$MODULE configure --help" "timeout" \
    "configure --help should mention timeout setting"
}

# =============================================================================
# test SUBCOMMAND TESTS
# =============================================================================

# Helper: Run a command with webhook enabled and no URLs configured.
# Uses an isolated temporary XDG config to avoid shared state issues.
# Usage: _run_with_webhook_enabled_no_urls <module> [args...]
# Returns: exit code of the command
function _run_with_webhook_enabled_no_urls() {
  local module="$1"
  shift
  local args=("$@")

  local temp_xdg
  temp_xdg=$(mktemp -d)
  mkdir -p "$temp_xdg/kgsm"

  # Minimal config: webhook enabled, no URLs set
  cat > "$temp_xdg/kgsm/config.ini" << 'EOF'
[events]
enable_webhook_events=true
webhook_urls=
EOF

  local exit_code=0
  local output
  output=$(
    # shellcheck disable=SC2030
    unset KGSM_BOOTSTRAP_LOADED KGSM_CONFIG_LOADED KGSM_COMMON_LOADED KGSM_PATHS_LOADED
    export XDG_CONFIG_HOME="$temp_xdg"
    "$module" "${args[@]}" 2>&1
  ) || exit_code=$?

  rm -rf "$temp_xdg"
  echo "$output"
  return $exit_code
}

function test_test_help_flag() {
  log_test_step "Testing: test --help shows test help and succeeds"

  assert_command_succeeds "$MODULE test --help" \
    "test --help should succeed"

  assert_command_output "$MODULE test --help" "Test" \
    "test --help output should contain Test"
}

function test_test_when_disabled_fails() {
  log_test_step "Testing: test command fails when webhook transport is disabled"

  # Ensure webhook transport is disabled (default state in sandbox)
  "$MODULE" disable >/dev/null 2>&1 || true

  assert_command_fails "$MODULE test" \
    "test should fail when webhook transport is disabled"
}

function test_test_when_disabled_shows_error() {
  log_test_step "Testing: test command shows error message when disabled"

  "$MODULE" disable >/dev/null 2>&1 || true

  assert_command_output "$MODULE test 2>&1 || true" "Webhook transport" \
    "test should show 'Webhook transport' error when webhook transport is disabled"
}

function test_test_when_enabled_but_no_urls_fails() {
  log_test_step "Testing: test command fails when enabled but no URLs configured"

  if ! command -v wget >/dev/null 2>&1; then
    skip_test "wget not available - skipping no-URLs test"
    return
  fi

  # Use isolated config to avoid shared state issues
  _run_with_webhook_enabled_no_urls "$MODULE" test >/dev/null 2>&1
  local exit_code=$?

  assert_not_equals "$exit_code" "0" \
    "test should fail when no webhook URLs are configured"
}

function test_test_when_enabled_but_no_urls_error_message() {
  log_test_step "Testing: test command shows URL error when enabled but no URLs set"

  if ! command -v wget >/dev/null 2>&1; then
    skip_test "wget not available - skipping no-URLs error message test"
    return
  fi

  # Use isolated config to avoid shared state issues
  local output
  output=$(_run_with_webhook_enabled_no_urls "$MODULE" test 2>&1 || true)

  assert_contains "$output" "No webhook URLs" \
    "test should show 'No webhook URLs' error when no webhook URLs are configured"
}

# =============================================================================
# emit TESTS
# =============================================================================

function test_emit_no_payload_fails() {
  log_test_step "Testing: emit with no payload fails"

  assert_command_fails "$MODULE emit" \
    "emit with no payload should fail"
}

function test_emit_no_payload_error_message() {
  log_test_step "Testing: emit with no payload shows error message"

  assert_command_output "$MODULE emit 2>&1 || true" "payload" \
    "emit with no payload should mention payload in error"
}

# =============================================================================
# UNKNOWN COMMAND TESTS
# =============================================================================

function test_unknown_command_fails() {
  log_test_step "Testing: unknown command fails with non-zero exit code"

  assert_command_fails "$MODULE unknown_command_xyz" \
    "Unknown command should fail"
}

function test_unknown_command_error_message() {
  log_test_step "Testing: unknown command shows error message"

  assert_command_output "$MODULE unknown_command_xyz 2>&1 || true" "Unknown command" \
    "Unknown command should show 'Unknown command' error"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

function main() {
  log_test_step "Starting events.webhook.sh command tests"

  setup_test

  # Help / usage tests
  test_help_no_args
  test_help_flag
  test_help_h_flag
  test_help_command
  test_help_lists_commands
  test_help_mentions_wget
  test_help_enable_subcommand
  test_help_disable_subcommand
  test_help_configure_subcommand
  test_help_test_subcommand
  test_help_status_subcommand
  test_help_unknown_subcommand_fails
  test_help_unknown_subcommand_error_message

  # status tests
  test_status_succeeds
  test_status_shows_transport_header
  test_status_shows_configuration_section
  test_status_shows_dependencies_section
  test_status_shows_enabled_or_disabled
  test_status_shows_timeout_setting
  test_status_help_flag

  # enable tests
  test_enable_help_flag
  test_enable_with_wget_succeeds
  test_enable_warns_no_urls
  test_enable_shows_success_message

  # disable tests
  test_disable_help_flag
  test_disable_succeeds
  test_disable_shows_success_message

  # configure tests (--help only)
  test_configure_help_flag
  test_configure_help_mentions_urls
  test_configure_help_mentions_timeout

  # test subcommand tests
  test_test_help_flag
  test_test_when_disabled_fails
  test_test_when_disabled_shows_error
  test_test_when_enabled_but_no_urls_fails
  test_test_when_enabled_but_no_urls_error_message

  # emit tests
  test_emit_no_payload_fails
  test_emit_no_payload_error_message

  # unknown command tests
  test_unknown_command_fails
  test_unknown_command_error_message

  log_test_step "Events webhook command tests completed"

  if print_assert_summary "$TEST_NAME"; then
    pass_test "All events.webhook.sh command tests passed"
  else
    fail_test "Some events.webhook.sh command tests failed"
  fi
}

main "$@"
