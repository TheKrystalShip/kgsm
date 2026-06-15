#!/usr/bin/env bash

# KGSM Files UFW Command CLI Tests
#
# Test Type: UNIT
# Target: commands/files.ufw.sh - CLI interface and argument handling
#
# Tests the CLI interface of files.ufw.sh including help system,
# error handling for missing/invalid args, and behavior on valid instances.
#
# Note: Tests that require UFW installed or root access are either
# skipped or test only up to the point of the external dependency.
# The disable path on an unconfigured instance succeeds without UFW.

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="files_ufw_commands"
readonly MODULE="$KGSM_ROOT/commands/files.ufw.sh"

TEST_INSTALL_DIR=""

# Path to the injected stub kgsm-firewall binary (created in setup_file). Subprocess
# invocations of $MODULE pass KGSM_FIREWALL_BIN=$FW_STUB + STUB_EXIT to exercise the
# command layer's exit-code handling without a live authority.
FW_STUB=""

# Creates the kgsm-firewall stub binary: exits with $STUB_EXIT (default 0).
function __make_fw_stub() {
  local path="$1"
  cat > "$path" << 'STUB'
#!/usr/bin/env bash
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$path"
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

function setup_file() {
  log_test_step "Setting up files.ufw commands tests"

  TEST_INSTALL_DIR="$KGSM_ROOT/test-installs"
  mkdir -p "$TEST_INSTALL_DIR"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$MODULE" "files.ufw.sh module should exist"
  assert_file_executable "$MODULE" "files.ufw.sh should be executable"

  FW_STUB="${KGSM_TEST_SANDBOX:-/tmp}/kgsm-firewall-cmd-stub-$$"
  __make_fw_stub "$FW_STUB"
  assert_file_executable "$FW_STUB" "Stub kgsm-firewall binary should be executable"

  log_test_step "Test environment validated"
}

# =============================================================================
# HELP SYSTEM TESTS
# =============================================================================

function test_help_top_level() {
  log_test_step "Testing top-level help output"

  local output
  output=$("$MODULE" help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help command should succeed"
  assert_contains "$output" "enable" "Help should mention enable command"
  assert_contains "$output" "disable" "Help should mention disable command"
  assert_contains "$output" "UFW" "Help should mention UFW"
}

function test_help_flag() {
  log_test_step "Testing --help flag output"

  local output
  output=$("$MODULE" --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "--help flag should succeed"
  assert_contains "$output" "enable" "Help output should contain enable"
}

function test_help_enable_command() {
  log_test_step "Testing help for enable command"

  local output
  output=$("$MODULE" help enable 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help enable should succeed"
  assert_contains "$output" "Enable" "Should show enable command help"
}

function test_help_disable_command() {
  log_test_step "Testing help for disable command"

  local output
  output=$("$MODULE" help disable 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "help disable should succeed"
  assert_contains "$output" "Disable" "Should show disable command help"
}

function test_help_unknown_command() {
  log_test_step "Testing help for unknown command returns error"

  assert_command_fails "$MODULE help nonexistent_cmd_xyz" \
    "help for unknown command should fail"
}

# =============================================================================
# MISSING ARGUMENT TESTS
# =============================================================================

function test_enable_missing_instance() {
  log_test_step "Testing enable with missing instance argument"

  assert_command_fails "$MODULE enable" \
    "enable with no instance should fail"

  local output
  output=$("$MODULE" enable 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

function test_disable_missing_instance() {
  log_test_step "Testing disable with missing instance argument"

  assert_command_fails "$MODULE disable" \
    "disable with no instance should fail"

  local output
  output=$("$MODULE" disable 2>&1 || true)
  assert_contains "$output" "Missing required argument" "Should show missing arg error"
}

# =============================================================================
# INVALID INSTANCE TESTS
# =============================================================================

function test_enable_invalid_instance() {
  log_test_step "Testing enable with invalid instance name"

  assert_command_fails "$MODULE enable nonexistent_instance_xyz_12345" \
    "enable with invalid instance should fail"

  local output
  output=$("$MODULE" enable nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" "Should show instance not found error"
}

function test_disable_invalid_instance() {
  log_test_step "Testing disable with invalid instance name"

  assert_command_fails "$MODULE disable nonexistent_instance_xyz_12345" \
    "disable with invalid instance should fail"

  local output
  output=$("$MODULE" disable nonexistent_instance_xyz_12345 2>&1 || true)
  assert_contains "$output" "not found" "Should show instance not found error"
}

# =============================================================================
# INVALID OPTIONS TESTS
# =============================================================================

function test_enable_invalid_option() {
  log_test_step "Testing enable with invalid option"

  assert_command_fails "$MODULE enable --unknown-flag" \
    "enable with unknown flag should fail"

  local output
  output=$("$MODULE" enable --unknown-flag 2>&1 || true)
  assert_contains "$output" "Unknown option" "Should show unknown option error"
}

function test_disable_invalid_option() {
  log_test_step "Testing disable with invalid option"

  assert_command_fails "$MODULE disable --unknown-flag" \
    "disable with unknown flag should fail"

  local output
  output=$("$MODULE" disable --unknown-flag 2>&1 || true)
  assert_contains "$output" "Unknown option" "Should show unknown option error"
}

function test_unknown_command() {
  log_test_step "Testing unknown top-level command"

  assert_command_fails "$MODULE notacommand" \
    "unknown command should fail"

  local output
  output=$("$MODULE" notacommand 2>&1 || true)
  assert_contains "$output" "Unknown command" "Should show unknown command error"
}

function test_no_command() {
  log_test_step "Testing module with no command shows usage"

  local output
  output=$("$MODULE" 2>&1 || true)

  assert_contains "$output" "enable" "No-command output should mention enable"
}

# =============================================================================
# COMMAND-SPECIFIC HELP FLAGS
# =============================================================================

function test_enable_help_flag() {
  log_test_step "Testing enable --help flag"

  local output
  output=$("$MODULE" enable --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "enable --help should succeed"
  assert_contains "$output" "Enable" "Should show enable help"
}

function test_disable_help_flag() {
  log_test_step "Testing disable --help flag"

  local output
  output=$("$MODULE" disable --help 2>&1)
  local exit_code=$?

  assert_equals 0 "$exit_code" "disable --help should succeed"
  assert_contains "$output" "Disable" "Should show disable help"
}

# =============================================================================
# VALID INSTANCE BEHAVIOR TESTS
# =============================================================================

# The command layer is where Inc 3's two headline behaviors actually live — the
# asymmetric hard-fail and the audit emit. These drive the real `files.ufw.sh`
# command as a subprocess against an injected stub authority (a real factorio
# instance, so `ports="34197/udp"` is read from a realistically-quoted config).

function test_enable_succeeds_when_authority_ok() {
  log_test_step "enable: authority OK (stub exit 0) -> success + config enabled"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)
  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output exit_code
  output=$(KGSM_FIREWALL_BIN="$FW_STUB" STUB_EXIT=0 "$MODULE" enable "$instance_name" 2>&1)
  exit_code=$?

  assert_equals 0 "$exit_code" "enable should succeed when the authority accepts the rule"
  assert_contains "$output" "enabled successfully" "Should report the firewall integration enabled"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_enable_hard_fails_when_authority_unreachable() {
  log_test_step "enable: authority unreachable (stub exit 3) -> hard-fail (non-zero) + explicit message"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)
  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output exit_code
  output=$(KGSM_FIREWALL_BIN="$FW_STUB" STUB_EXIT=3 "$MODULE" enable "$instance_name" 2>&1)
  exit_code=$?

  # §7g hard-fail: a firewall-enabled enable must NOT silently proceed when the
  # authority is down.
  assert_not_equals 0 "$exit_code" "enable must hard-fail when the authority is unreachable"
  assert_contains "$output" "not reachable" "Should surface the explicit authority-unreachable message"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_disable_continues_when_authority_unreachable() {
  log_test_step "disable: authority unreachable (stub exit 3) -> warns but EXITS 0 (never wedge uninstall)"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)
  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output exit_code
  output=$(KGSM_FIREWALL_BIN="$FW_STUB" STUB_EXIT=3 "$MODULE" disable "$instance_name" 2>&1)
  exit_code=$?

  # The load-bearing asymmetry: disable is best-effort, so a down authority must
  # return 0 — a non-zero here would wedge `kgsm uninstall` (files.sh disable || return).
  assert_equals 0 "$exit_code" "disable must exit 0 even when the authority is unreachable"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

function test_disable_succeeds_when_authority_ok() {
  log_test_step "disable: authority OK (stub exit 0) -> success"

  local blueprint="factorio"
  local instance_name
  instance_name=$(create_test_instance "$blueprint" "$(generate_test_id)" "$TEST_INSTALL_DIR" 2>/dev/null)
  if [[ -z "$instance_name" ]]; then
    skip_test "Instance creation failed - skipping test"
    return
  fi

  local output exit_code
  output=$(KGSM_FIREWALL_BIN="$FW_STUB" STUB_EXIT=0 "$MODULE" disable "$instance_name" 2>&1)
  exit_code=$?

  assert_equals 0 "$exit_code" "disable on a reachable authority should succeed"

  remove_test_instance "$blueprint" "$instance_name" "$TEST_INSTALL_DIR"
}

