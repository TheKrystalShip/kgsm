#!/usr/bin/env bash

# KGSM Files UFW Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/files.ufw.sh
#
# Tests the two logic functions after the Inc 3 cutover — kgsm no longer renders
# a ufw profile or shells `ufw` itself; it hands ports to the kgsm-firewall
# authority via the handlers/firewall.sh chokepoint:
# - __logic_enable_ufw_integration()
# - __logic_disable_ufw_integration()
#
# A stub kgsm-firewall binary (a real collaborator, injected via
# KGSM_FIREWALL_BIN) returns canned exit codes so the cutover's behaviour is
# exercised without a live daemon — covering the exit-code mapping, the
# asymmetric hard-fail (enable aborts on unreachable; disable warns + continues),
# the empty-ports skip, and the config updates.

# =============================================================================
# TEST SETUP
# =============================================================================

# shellcheck disable=SC2034
readonly TEST_NAME="files_ufw_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.ufw.sh"

# Path to the injected stub binary (created in setup_file).
FW_STUB=""

# Creates the kgsm-firewall stub binary. Records its argv to $STUB_ARGS_FILE
# (when set) and exits with $STUB_EXIT (default 0) — both read from the env.
function __make_fw_stub() {
  local path="$1"
  cat > "$path" << 'STUB'
#!/usr/bin/env bash
[[ -n "${STUB_ARGS_FILE:-}" ]] && printf '%s\n' "$*" >> "$STUB_ARGS_FILE"
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$path"
}

# Writes a minimal native instance config with a name and a UFW-format port spec.
# Args: $1 = output_path, $2 = instance_name, $3 = ufw port spec (may be empty)
function __write_instance_config() {
  local output_path="$1"
  local instance_name="$2"
  local ports="${3:-}"

  cat > "$output_path" << EOF
name=${instance_name}
runtime=native
ports=${ports}
EOF
}

# =============================================================================
# SETUP
# =============================================================================

function setup_file() {
  log_test_step "Setting up files.ufw logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "UFW handler file should exist"

  # Sourcing files.ufw.sh pulls in files.common.sh AND handlers/firewall.sh.
  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "$KGSM_LOGIC_FILES_UFW_LOADED" "UFW handler should be loaded"
  assert_not_null "$KGSM_LOGIC_FIREWALL_LOADED" "Firewall routing handler should be loaded"

  assert_not_null "$EC_INVALID_ARG"          "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND"       "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_CONFIG"       "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FIREWALL_UNREACHABLE" "EC_FIREWALL_UNREACHABLE should be defined"
  assert_not_null "$EC_UFW"                  "EC_UFW should be defined"
  assert_not_null "$EC_SUCCESS_UFW_ENABLED"  "EC_SUCCESS_UFW_ENABLED should be defined"
  assert_not_null "$EC_SUCCESS_UFW_DISABLED" "EC_SUCCESS_UFW_DISABLED should be defined"

  assert_function_exists "__logic_enable_ufw_integration"  "enable logic should be exported"
  assert_function_exists "__logic_disable_ufw_integration" "disable logic should be exported"

  FW_STUB="${KGSM_TEST_SANDBOX:-/tmp}/kgsm-firewall-ufw-stub-$$"
  __make_fw_stub "$FW_STUB"
  assert_file_executable "$FW_STUB" "Stub kgsm-firewall binary should be executable"
}

# =============================================================================
# __logic_enable_ufw_integration() — input validation
# =============================================================================

function test_enable_empty_arg() {
  log_test_step "enable: empty argument -> EC_INVALID_ARG"
  __logic_enable_ufw_integration "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Empty config path should return EC_INVALID_ARG"
}

function test_enable_file_not_found() {
  log_test_step "enable: missing config file -> EC_FILE_NOT_FOUND"
  __logic_enable_ufw_integration "/nonexistent/instance.ini" 2> /dev/null
  assert_equals "$EC_FILE_NOT_FOUND" "$?" "Missing config should return EC_FILE_NOT_FOUND"
}

function test_enable_missing_name() {
  log_test_step "enable: config without 'name' -> EC_INVALID_CONFIG"
  unset instance_name instance_ports

  local cfg
  cfg=$(mktemp)
  printf 'runtime=native\nports=7777/tcp\n' > "$cfg"

  KGSM_FIREWALL_BIN="$FW_STUB" __logic_enable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?
  rm -f "$cfg"

  assert_equals "$EC_INVALID_CONFIG" "$rc" "Missing 'name' should return EC_INVALID_CONFIG"
}

# =============================================================================
# __logic_enable_ufw_integration() — authority routing
# =============================================================================

function test_enable_success_calls_authority_and_updates_config() {
  log_test_step "enable: authority OK -> EC_SUCCESS_UFW_ENABLED + config on + ensure-open argv"
  unset instance_name instance_ports

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_ok_$$" "34197/udp|27015:27020/tcp"

  STUB_EXIT=0 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_enable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_UFW_ENABLED" "$rc" "A clean enable should return EC_SUCCESS_UFW_ENABLED"
  assert_file_contains "$cfg" "enable_firewall_management=true" \
    "Config should record firewall management as enabled"
  assert_file_contains "$args_file" "ensure-open ufw_ok_$$ 34197/udp 27015:27020/tcp" \
    "The authority should receive ensure-open with the canonical port tokens"

  rm -f "$cfg" "$args_file"
}

function test_enable_hard_fail_when_authority_unreachable() {
  log_test_step "enable: authority unreachable -> EC_FIREWALL_UNREACHABLE, config NOT enabled"
  unset instance_name instance_ports

  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_unreach_$$" "34197/udp"

  STUB_EXIT=3 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_enable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_FIREWALL_UNREACHABLE" "$rc" \
    "An unreachable authority must hard-fail the enable (§7g)"

  local content
  content=$(cat "$cfg")
  assert_not_contains "$content" "enable_firewall_management=true" \
    "A hard-failed enable must NOT mark the instance firewall-enabled"

  rm -f "$cfg"
}

function test_enable_op_failed_maps_ufw() {
  log_test_step "enable: backend op-failed -> EC_UFW"
  unset instance_name instance_ports

  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_opfail_$$" "34197/udp"

  STUB_EXIT=5 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_enable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?
  rm -f "$cfg"

  assert_equals "$EC_UFW" "$rc" "A reachable-but-failed apply should map to EC_UFW"
}

function test_enable_empty_ports_skips_authority() {
  log_test_step "enable: no ports -> authority NOT called, still EC_SUCCESS_UFW_ENABLED"
  unset instance_name instance_ports

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_noports_$$" ""

  # STUB_EXIT=3 would hard-fail IF the authority were called — proving the skip.
  STUB_EXIT=3 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_enable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_UFW_ENABLED" "$rc" \
    "An instance with no ports has nothing to open and should succeed"
  assert_file_contains "$cfg" "enable_firewall_management=true" \
    "The firewall toggle should still be recorded"

  local called
  called=$(cat "$args_file" 2> /dev/null)
  assert_null "$called" "The authority must NOT be invoked for a port-less instance"

  rm -f "$cfg" "$args_file"
}

# =============================================================================
# __logic_disable_ufw_integration() — input validation
# =============================================================================

function test_disable_empty_arg() {
  log_test_step "disable: empty argument -> EC_INVALID_ARG"
  __logic_disable_ufw_integration "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Empty config path should return EC_INVALID_ARG"
}

function test_disable_file_not_found() {
  log_test_step "disable: missing config file -> EC_FILE_NOT_FOUND"
  __logic_disable_ufw_integration "/nonexistent/instance.ini" 2> /dev/null
  assert_equals "$EC_FILE_NOT_FOUND" "$?" "Missing config should return EC_FILE_NOT_FOUND"
}

function test_disable_missing_name() {
  log_test_step "disable: config without 'name' -> EC_INVALID_CONFIG"
  local cfg
  cfg=$(mktemp)
  printf 'runtime=native\n' > "$cfg"

  KGSM_FIREWALL_BIN="$FW_STUB" __logic_disable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?
  rm -f "$cfg"

  assert_equals "$EC_INVALID_CONFIG" "$rc" "Missing 'name' should return EC_INVALID_CONFIG"
}

# =============================================================================
# __logic_disable_ufw_integration() — authority routing (best-effort)
# =============================================================================

function test_disable_success_flips_config_and_calls_remove() {
  log_test_step "disable: authority OK -> EC_SUCCESS_UFW_DISABLED + config off + remove argv"
  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_dis_ok_$$" "34197/udp"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=0 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_disable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_UFW_DISABLED" "$rc" "A clean removal should return EC_SUCCESS_UFW_DISABLED"
  assert_file_contains "$cfg" "enable_firewall_management=false" \
    "Config should record firewall management as disabled"
  assert_file_contains "$args_file" "remove ufw_dis_ok_$$" \
    "The authority should receive a remove for the instance"

  rm -f "$cfg" "$args_file"
}

function test_disable_unreachable_is_soft_but_flips_config() {
  log_test_step "disable: authority unreachable -> soft EC_FIREWALL_UNREACHABLE, config still off"
  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_dis_unreach_$$" "34197/udp"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=3 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_disable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_FIREWALL_UNREACHABLE" "$rc" \
    "Disable must surface the unreachable outcome (the command layer warns + continues)"
  assert_file_contains "$cfg" "enable_firewall_management=false" \
    "Disable must still flip the toggle so uninstall is never wedged"

  rm -f "$cfg"
}

function test_disable_op_failed_is_soft_but_flips_config() {
  log_test_step "disable: backend op-failed -> soft EC_UFW, config still off"
  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_dis_opfail_$$" "34197/udp"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=5 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_disable_ufw_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_UFW" "$rc" "A backend remove failure should surface as EC_UFW (soft)"
  assert_file_contains "$cfg" "enable_firewall_management=false" \
    "Disable must still flip the toggle even on a backend error"

  rm -f "$cfg"
}
