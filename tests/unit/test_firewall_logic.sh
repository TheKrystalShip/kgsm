#!/usr/bin/env bash

# KGSM Firewall Authority Routing Logic Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/firewall.sh
#
# Tests the kgsm-firewall IPC chokepoint (the bash side of Inc 3's cutover):
# - __firewall_ports_to_tokens()  : UFW spec -> CLI port tokens
# - __firewall_bin()              : binary resolution precedence
# - __firewall_invoke() mapping   : CLI exit-code contract -> kgsm EC
# - __firewall_ensure_open() / __firewall_remove() : arg validation + argv
#
# No real kgsm-firewall daemon is needed: a stub binary (a real collaborator,
# like the watchdog tests stand one up) is injected via KGSM_FIREWALL_BIN and
# returns canned exit codes / records its argv. "No mocking, real code" holds.

# =============================================================================
# TEST SETUP
# =============================================================================

# shellcheck disable=SC2034
readonly TEST_NAME="firewall_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/firewall.sh"

# Path to the injected stub binary (created in setup_file).
FW_STUB=""

# Creates the kgsm-firewall stub binary. It records its argv to $STUB_ARGS_FILE
# (when set) and exits with $STUB_EXIT (default 0) — both read from the env, so
# tests must export them.
function __make_fw_stub() {
  local path="$1"
  cat > "$path" << 'STUB'
#!/usr/bin/env bash
[[ -n "${STUB_ARGS_FILE:-}" ]] && printf '%s\n' "$*" >> "$STUB_ARGS_FILE"
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$path"
}

function setup_file() {
  log_test_step "Setting up firewall logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Firewall handler file should exist"

  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "$KGSM_LOGIC_FIREWALL_LOADED" "Firewall handler should be loaded"
  assert_not_null "$EC_FIREWALL_UNREACHABLE" "EC_FIREWALL_UNREACHABLE should be defined"
  assert_not_null "$EC_FIREWALL" "EC_FIREWALL should be defined"

  assert_function_exists "__firewall_socket_path" "__firewall_socket_path should be exported"
  assert_function_exists "__firewall_bin" "__firewall_bin should be exported"
  assert_function_exists "__firewall_invoke" "__firewall_invoke should be exported"
  assert_function_exists "__firewall_ensure_open" "__firewall_ensure_open should be exported"
  assert_function_exists "__firewall_remove" "__firewall_remove should be exported"
  assert_function_exists "__firewall_ports_to_tokens" "__firewall_ports_to_tokens should be exported"

  FW_STUB="${KGSM_TEST_SANDBOX:-/tmp}/kgsm-firewall-stub-$$"
  __make_fw_stub "$FW_STUB"
  assert_file_executable "$FW_STUB" "Stub kgsm-firewall binary should be executable"
}

# =============================================================================
# __firewall_ports_to_tokens() — UFW spec -> CLI port tokens
# =============================================================================

function test_tokens_single_port_with_proto() {
  log_test_step "Token conversion: single port with protocol"
  local out
  out=$(__firewall_ports_to_tokens "34197/udp")
  assert_equals "34197/udp" "$out" "A single port/proto should pass through unchanged"
}

function test_tokens_range_with_proto() {
  log_test_step "Token conversion: range preserved"
  local out
  out=$(__firewall_ports_to_tokens "27015:27020/tcp")
  assert_equals "27015:27020/tcp" "$out" "A port range should be preserved as start:end/proto"
}

function test_tokens_protoless_expands_both() {
  log_test_step "Token conversion: proto-less port expands to tcp + udp"
  local out
  out=$(__firewall_ports_to_tokens "7777")
  assert_equals "7777/tcp 7777/udp" "$out" \
    "A proto-less port should expand to BOTH tcp and udp (ufw implicit-both)"
}

function test_tokens_multi_pipe_separated() {
  log_test_step "Token conversion: pipe-separated multi-entry spec"
  local out
  out=$(__firewall_ports_to_tokens "34197/udp|27015:27020/tcp")
  assert_equals "34197/udp 27015:27020/tcp" "$out" \
    "Pipe-separated entries should become space-separated tokens"
}

function test_tokens_empty_spec_yields_nothing() {
  log_test_step "Token conversion: empty spec"
  local out
  out=$(__firewall_ports_to_tokens "")
  assert_equals "" "$out" "An empty spec should echo nothing"
}

function test_tokens_malformed_returns_error() {
  log_test_step "Token conversion: malformed spec"
  __firewall_ports_to_tokens "not-a-port" > /dev/null 2>&1
  local rc=$?
  assert_equals "$EC_ERROR" "$rc" "A malformed spec should return EC_ERROR"
}

# =============================================================================
# __firewall_bin() — resolution precedence
# =============================================================================

function test_bin_env_override_wins() {
  log_test_step "Binary resolution: KGSM_FIREWALL_BIN env override wins"
  local out
  out=$(KGSM_FIREWALL_BIN="/opt/custom/kgsm-firewall" __firewall_bin)
  assert_equals "/opt/custom/kgsm-firewall" "$out" \
    "KGSM_FIREWALL_BIN should take precedence"
}

function test_bin_config_used_when_env_absent() {
  log_test_step "Binary resolution: config_firewall_bin used when env unset"
  local out
  out=$(KGSM_FIREWALL_BIN="" config_firewall_bin="/etc/kgsm/fw" __firewall_bin)
  assert_equals "/etc/kgsm/fw" "$out" \
    "config_firewall_bin should be used when the env override is absent"
}

function test_bin_absent_returns_nonzero() {
  log_test_step "Binary resolution: nothing on PATH returns non-zero"
  # Neither override set, and a name that is not installed.
  local rc
  KGSM_FIREWALL_BIN="" config_firewall_bin="" PATH="/nonexistent-dir" __firewall_bin > /dev/null 2>&1
  rc=$?
  assert_not_equals "0" "$rc" "An unresolvable binary should return non-zero"
}

# =============================================================================
# __firewall_invoke() — CLI exit-code contract -> kgsm EC
# =============================================================================

function test_invoke_success_maps_ec_success() {
  log_test_step "Exit-code mapping: 0 -> EC_SUCCESS"
  STUB_EXIT=0 KGSM_FIREWALL_BIN="$FW_STUB" __firewall_invoke backend
  local rc=$?
  assert_equals "$EC_SUCCESS" "$rc" "CLI exit 0 should map to EC_SUCCESS"
}

function test_invoke_unreachable_maps_ec_firewall_unreachable() {
  log_test_step "Exit-code mapping: 3 (unreachable) -> EC_FIREWALL_UNREACHABLE"
  STUB_EXIT=3 KGSM_FIREWALL_BIN="$FW_STUB" __firewall_invoke backend
  local rc=$?
  assert_equals "$EC_FIREWALL_UNREACHABLE" "$rc" \
    "CLI exit 3 should map to EC_FIREWALL_UNREACHABLE (the hard-fail trigger)"
}

function test_invoke_unsupported_maps_ec_firewall() {
  log_test_step "Exit-code mapping: 4 (unsupported) -> EC_FIREWALL"
  STUB_EXIT=4 KGSM_FIREWALL_BIN="$FW_STUB" __firewall_invoke backend
  local rc=$?
  assert_equals "$EC_FIREWALL" "$rc" "CLI exit 4 should map to EC_FIREWALL"
}

function test_invoke_opfailed_maps_ec_firewall() {
  log_test_step "Exit-code mapping: 5 (op-failed) -> EC_FIREWALL"
  STUB_EXIT=5 KGSM_FIREWALL_BIN="$FW_STUB" __firewall_invoke backend
  local rc=$?
  assert_equals "$EC_FIREWALL" "$rc" "CLI exit 5 should map to EC_FIREWALL"
}

function test_invoke_missing_binary_maps_unreachable() {
  log_test_step "Exit-code mapping: a bogus binary path -> EC_FIREWALL_UNREACHABLE"
  KGSM_FIREWALL_BIN="/nonexistent/kgsm-firewall" __firewall_invoke backend > /dev/null 2>&1
  local rc=$?
  assert_equals "$EC_FIREWALL_UNREACHABLE" "$rc" \
    "A resolved-but-unrunnable binary is 'authority unavailable', not an op failure"
}

# =============================================================================
# __firewall_ensure_open() / __firewall_remove() — validation + argv
# =============================================================================

function test_ensure_open_empty_instance_rejected() {
  log_test_step "ensure_open: empty instance -> EC_INVALID_ARG"
  KGSM_FIREWALL_BIN="$FW_STUB" __firewall_ensure_open "" "34197/udp"
  local rc=$?
  assert_equals "$EC_INVALID_ARG" "$rc" "An empty instance name should be rejected"
}

function test_ensure_open_no_ports_rejected() {
  log_test_step "ensure_open: no port tokens -> EC_INVALID_ARG"
  KGSM_FIREWALL_BIN="$FW_STUB" __firewall_ensure_open "myserver"
  local rc=$?
  assert_equals "$EC_INVALID_ARG" "$rc" \
    "ensure-open with no ports should be rejected (caller must skip empty-port instances)"
}

function test_ensure_open_passes_verb_and_tokens() {
  log_test_step "ensure_open: argv carries 'ensure-open <instance> <tokens>'"
  local args_file
  args_file=$(mktemp)

  STUB_EXIT=0 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __firewall_ensure_open "myserver" "34197/udp" "27015:27020/tcp"
  local rc=$?

  assert_equals "$EC_SUCCESS" "$rc" "A successful ensure-open should map to EC_SUCCESS"
  assert_file_contains "$args_file" "ensure-open myserver 34197/udp 27015:27020/tcp" \
    "The CLI should receive the verb, instance, and canonical port tokens"

  rm -f "$args_file"
}

function test_remove_empty_instance_rejected() {
  log_test_step "remove: empty instance -> EC_INVALID_ARG"
  KGSM_FIREWALL_BIN="$FW_STUB" __firewall_remove ""
  local rc=$?
  assert_equals "$EC_INVALID_ARG" "$rc" "An empty instance name should be rejected"
}

function test_remove_passes_verb_and_instance() {
  log_test_step "remove: argv carries 'remove <instance>'"
  local args_file
  args_file=$(mktemp)

  STUB_EXIT=0 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __firewall_remove "myserver"
  local rc=$?

  assert_equals "$EC_SUCCESS" "$rc" "A successful remove should map to EC_SUCCESS"
  assert_file_contains "$args_file" "remove myserver" \
    "The CLI should receive the remove verb and instance name"

  rm -f "$args_file"
}
