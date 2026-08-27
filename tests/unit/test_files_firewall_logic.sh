#!/usr/bin/env bash

# KGSM Files Firewall Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/files.firewall.sh
#
# Tests the two logic functions after the Inc 3 cutover — kgsm no longer renders
# a ufw profile or shells `ufw` itself; it hands ports to the kgsm-firewall
# authority via the handlers/firewall.sh chokepoint:
# - __logic_enable_firewall_integration()
# - __logic_disable_firewall_integration()
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
readonly TEST_NAME="files_firewall_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/files.firewall.sh"

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
  log_test_step "Setting up files.firewall logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "firewall handler file should exist"

  # Sourcing files.firewall.sh pulls in files.common.sh AND handlers/firewall.sh.
  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "$KGSM_LOGIC_FILES_FIREWALL_LOADED" "firewall handler should be loaded"
  assert_not_null "$KGSM_LOGIC_FIREWALL_LOADED" "Firewall routing handler should be loaded"

  assert_not_null "$EC_INVALID_ARG"          "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_FILE_NOT_FOUND"       "EC_FILE_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_CONFIG"       "EC_INVALID_CONFIG should be defined"
  assert_not_null "$EC_FIREWALL_UNREACHABLE" "EC_FIREWALL_UNREACHABLE should be defined"
  assert_not_null "$EC_FIREWALL"                  "EC_FIREWALL should be defined"
  assert_not_null "$EC_SUCCESS_FIREWALL_ENABLED"  "EC_SUCCESS_FIREWALL_ENABLED should be defined"
  assert_not_null "$EC_SUCCESS_FIREWALL_DISABLED" "EC_SUCCESS_FIREWALL_DISABLED should be defined"

  assert_function_exists "__logic_enable_firewall_integration"  "enable logic should be exported"
  assert_function_exists "__logic_disable_firewall_integration" "disable logic should be exported"

  FW_STUB="${KGSM_TEST_SANDBOX:-/tmp}/kgsm-firewall-ufw-stub-$$"
  __make_fw_stub "$FW_STUB"
  assert_file_executable "$FW_STUB" "Stub kgsm-firewall binary should be executable"
}

# =============================================================================
# __logic_enable_firewall_integration() — input validation
# =============================================================================

function test_enable_empty_arg() {
  log_test_step "enable: empty argument -> EC_INVALID_ARG"
  __logic_enable_firewall_integration "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Empty config path should return EC_INVALID_ARG"
}

function test_enable_file_not_found() {
  log_test_step "enable: missing config file -> EC_FILE_NOT_FOUND"
  __logic_enable_firewall_integration "/nonexistent/instance.ini" 2> /dev/null
  assert_equals "$EC_FILE_NOT_FOUND" "$?" "Missing config should return EC_FILE_NOT_FOUND"
}

function test_enable_missing_name() {
  log_test_step "enable: config without 'name' -> EC_INVALID_CONFIG"
  unset instance_name instance_ports

  local cfg
  cfg=$(mktemp)
  printf 'runtime=native\nports=7777/tcp\n' > "$cfg"

  KGSM_FIREWALL_BIN="$FW_STUB" __logic_enable_firewall_integration "$cfg" 2> /dev/null
  local rc=$?
  rm -f "$cfg"

  assert_equals "$EC_INVALID_CONFIG" "$rc" "Missing 'name' should return EC_INVALID_CONFIG"
}

# =============================================================================
# __logic_enable_firewall_integration() — authority routing
# =============================================================================

function test_enable_records_the_toggle_without_opening_anything() {
  log_test_step "enable: records the toggle, authority NOT called"
  unset instance_name instance_ports

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_ok_$$" "34197/udp|27015:27020/tcp"

  # STUB_EXIT=3 would surface IF the authority were called — proving the skip.
  STUB_EXIT=3 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_enable_firewall_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_FIREWALL_ENABLED" "$rc" "A clean enable should return EC_SUCCESS_FIREWALL_ENABLED"
  assert_file_contains "$cfg" "enable_firewall_management=true" \
    "Config should record firewall management as enabled"

  local called
  called=$(cat "$args_file" 2> /dev/null)
  assert_null "$called" \
    "Enable states intent only — the ports open on the start that follows, not here"

  rm -f "$cfg" "$args_file"
}

function test_enable_succeeds_while_the_authority_is_down() {
  log_test_step "enable: authority unreachable -> still enabled (nothing is asked of it)"
  unset instance_name instance_ports

  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_unreach_$$" "34197/udp"

  # No binary at all: the harshest form of "authority down".
  KGSM_FIREWALL_BIN="/nonexistent/kgsm-firewall" \
    __logic_enable_firewall_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_FIREWALL_ENABLED" "$rc" \
    "Marking an instance managed does not depend on the authority being up"
  assert_file_contains "$cfg" "enable_firewall_management=true" \
    "The toggle should be recorded regardless of the authority"

  rm -f "$cfg"
}

# =============================================================================
# __logic_disable_firewall_integration() — input validation
# =============================================================================

function test_disable_empty_arg() {
  log_test_step "disable: empty argument -> EC_INVALID_ARG"
  __logic_disable_firewall_integration "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Empty config path should return EC_INVALID_ARG"
}

function test_disable_file_not_found() {
  log_test_step "disable: missing config file -> EC_FILE_NOT_FOUND"
  __logic_disable_firewall_integration "/nonexistent/instance.ini" 2> /dev/null
  assert_equals "$EC_FILE_NOT_FOUND" "$?" "Missing config should return EC_FILE_NOT_FOUND"
}

function test_disable_missing_name() {
  log_test_step "disable: config without 'name' -> EC_INVALID_CONFIG"
  local cfg
  cfg=$(mktemp)
  printf 'runtime=native\n' > "$cfg"

  KGSM_FIREWALL_BIN="$FW_STUB" __logic_disable_firewall_integration "$cfg" 2> /dev/null
  local rc=$?
  rm -f "$cfg"

  assert_equals "$EC_INVALID_CONFIG" "$rc" "Missing 'name' should return EC_INVALID_CONFIG"
}

# =============================================================================
# __logic_disable_firewall_integration() — authority routing (best-effort)
# =============================================================================

function test_disable_success_flips_config_and_calls_remove() {
  log_test_step "disable: authority OK -> EC_SUCCESS_FIREWALL_DISABLED + config off + remove argv"
  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_dis_ok_$$" "34197/udp"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=0 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_disable_firewall_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_FIREWALL_DISABLED" "$rc" "A clean removal should return EC_SUCCESS_FIREWALL_DISABLED"
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
    __logic_disable_firewall_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_FIREWALL_UNREACHABLE" "$rc" \
    "Disable must surface the unreachable outcome (the command layer warns + continues)"
  assert_file_contains "$cfg" "enable_firewall_management=false" \
    "Disable must still flip the toggle so uninstall is never wedged"

  rm -f "$cfg"
}

function test_disable_op_failed_is_soft_but_flips_config() {
  log_test_step "disable: backend op-failed -> soft EC_FIREWALL, config still off"
  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_dis_opfail_$$" "34197/udp"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=5 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_disable_firewall_integration "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_FIREWALL" "$rc" "A backend remove failure should surface as EC_FIREWALL (soft)"
  assert_file_contains "$cfg" "enable_firewall_management=false" \
    "Disable must still flip the toggle even on a backend error"

  rm -f "$cfg"
}

# =============================================================================
# __logic_ensure_firewall_open() — the start-path reconcile
# =============================================================================

function test_ensure_open_empty_arg() {
  log_test_step "ensure-open: empty argument -> EC_INVALID_ARG"
  __logic_ensure_firewall_open "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Empty config path should return EC_INVALID_ARG"
}

function test_ensure_open_file_not_found() {
  log_test_step "ensure-open: missing config file -> EC_FILE_NOT_FOUND"
  __logic_ensure_firewall_open "/nonexistent/instance.ini" 2> /dev/null
  assert_equals "$EC_FILE_NOT_FOUND" "$?" "Missing config should return EC_FILE_NOT_FOUND"
}

function test_ensure_open_reasserts_the_rule_with_the_canonical_tokens() {
  log_test_step "ensure-open: management on -> ensure-open argv, PORTS_OPENED"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_ensure_$$" "25565"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=0 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_open "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_FIREWALL_PORTS_OPENED" "$rc" \
    "A confirmed rule should report the edge, so the caller can audit it"
  # A proto-less spec opens both protocols, the way ufw reads it.
  assert_file_contains "$args_file" "ensure-open ufw_ensure_$$ 25565/tcp 25565/udp" \
    "The authority should receive ensure-open with the canonical port tokens"

  rm -f "$cfg" "$args_file"
}

function test_ensure_open_respects_an_instance_with_management_off() {
  log_test_step "ensure-open: management off -> authority NOT called, EC_SUCCESS"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_ensure_off_$$" "25565/tcp"
  echo "enable_firewall_management=false" >> "$cfg"

  # STUB_EXIT=3 would surface IF the authority were called — proving the skip.
  STUB_EXIT=3 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_open "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS" "$rc" "An opted-out instance is a no-op, not a failure"

  local called
  called=$(cat "$args_file" 2> /dev/null)
  assert_null "$called" "A start must not re-open ports the operator turned off"

  rm -f "$cfg" "$args_file"
}

function test_ensure_open_empty_ports_skips_authority() {
  log_test_step "ensure-open: no ports -> authority NOT called, EC_SUCCESS"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_ensure_noports_$$" ""
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=3 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_open "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS" "$rc" "An instance with no ports has nothing to open"

  local called
  called=$(cat "$args_file" 2> /dev/null)
  assert_null "$called" "The authority must NOT be invoked for a port-less instance"

  rm -f "$cfg" "$args_file"
}

function test_ensure_open_surfaces_an_unreachable_authority() {
  log_test_step "ensure-open: authority unreachable -> EC_FIREWALL_UNREACHABLE"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_ensure_unreach_$$" "25565/tcp"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=3 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_open "$cfg" 2> /dev/null
  local rc=$?
  rm -f "$cfg"

  # Reported, not fatal — the start path warns and brings the server up anyway.
  assert_equals "$EC_FIREWALL_UNREACHABLE" "$rc" \
    "An unreachable authority should be reported to the caller"
}

# =============================================================================
# __logic_ensure_firewall_closed() — the stop-path release
# =============================================================================

function test_ensure_closed_releases_the_rule_by_ownership_tag() {
  log_test_step "ensure-closed: management on -> remove argv, PORTS_CLOSED"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_close_$$" "25565"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=0 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_closed "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS_FIREWALL_PORTS_CLOSED" "$rc" \
    "A confirmed release should report the edge, so the caller can audit it"
  # Addressed by name, not by ports — so it still cleans up after a port change.
  assert_file_contains "$args_file" "remove ufw_close_$$" \
    "The authority should be asked to remove the instance's rules by ownership tag"

  rm -f "$cfg" "$args_file"
}

function test_ensure_closed_leaves_the_toggle_alone() {
  log_test_step "ensure-closed: a stop does not un-manage the instance"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_close_toggle_$$" "25565"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=0 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_closed "$cfg" 2> /dev/null

  # The difference from `files firewall disable`: the instance is still managed,
  # it is simply not running, so the next start opens its ports again.
  assert_file_contains "$cfg" "enable_firewall_management=true" \
    "A stop must not flip the instance to unmanaged"

  rm -f "$cfg"
}

function test_ensure_closed_respects_an_instance_with_management_off() {
  log_test_step "ensure-closed: management off -> authority NOT called, EC_SUCCESS"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg args_file
  cfg=$(mktemp)
  args_file=$(mktemp)
  __write_instance_config "$cfg" "ufw_close_off_$$" "25565"
  echo "enable_firewall_management=false" >> "$cfg"

  STUB_EXIT=3 STUB_ARGS_FILE="$args_file" KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_closed "$cfg" 2> /dev/null
  local rc=$?

  assert_equals "$EC_SUCCESS" "$rc" "An unmanaged instance is a no-op, not a failure"

  local called
  called=$(cat "$args_file" 2> /dev/null)
  assert_null "$called" "An unmanaged instance's rules are not KGSM's to remove"

  rm -f "$cfg" "$args_file"
}

function test_ensure_closed_surfaces_an_unreachable_authority() {
  log_test_step "ensure-closed: authority unreachable -> EC_FIREWALL_UNREACHABLE"
  unset instance_name instance_ports instance_enable_firewall_management

  local cfg
  cfg=$(mktemp)
  __write_instance_config "$cfg" "ufw_close_unreach_$$" "25565"
  echo "enable_firewall_management=true" >> "$cfg"

  STUB_EXIT=3 KGSM_FIREWALL_BIN="$FW_STUB" \
    __logic_ensure_firewall_closed "$cfg" 2> /dev/null
  local rc=$?
  rm -f "$cfg"

  # Reported, not fatal — a stop that cannot reach the authority still stopped.
  assert_equals "$EC_FIREWALL_UNREACHABLE" "$rc" \
    "An unreachable authority should be reported to the caller"
}

# =============================================================================
# The applied/no-op distinction the audit trail rests on
# =============================================================================

function test_applied_edges_are_distinguishable_from_a_no_op() {
  log_test_step "the ports codes are distinct from EC_SUCCESS, so a no-op is not audited"

  # The caller emits network.ports.opened/closed on these codes and nothing on
  # EC_SUCCESS. Collapsing them would make every start of an opted-out or port-less
  # instance claim ports it never opened — a fabricated rule in the audit trail.
  assert_not_equals "$EC_SUCCESS" "$EC_SUCCESS_FIREWALL_PORTS_OPENED" \
    "A confirmed open must not share a code with 'there was nothing to open'"
  assert_not_equals "$EC_SUCCESS" "$EC_SUCCESS_FIREWALL_PORTS_CLOSED" \
    "A confirmed close must not share a code with 'there was nothing to close'"
  assert_not_equals "$EC_SUCCESS_FIREWALL_PORTS_OPENED" "$EC_SUCCESS_FIREWALL_PORTS_CLOSED" \
    "The two edges must be distinguishable from each other"

  # Success-with-event codes live in 200-255; bash truncates anything above to a
  # single byte, which would land back on an error code.
  local _code
  for _code in "$EC_SUCCESS_FIREWALL_PORTS_OPENED" "$EC_SUCCESS_FIREWALL_PORTS_CLOSED"; do
    local _in_range="false"
    [[ $_code -ge 200 && $_code -le 255 ]] && _in_range="true"
    assert_true "$_in_range" \
      "Code $_code must sit in the 200-255 success-with-event range"
  done
}
