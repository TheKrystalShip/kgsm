#!/usr/bin/env bash

# KGSM Watchdog Routing Tests
#
# Test Type: UNIT
# Target: commands/handlers/watchdog.sh - native lifecycle -> watchdog routing
#
# Covers the pure routing logic: socket-path resolution, availability gating
# (the regression guard that keeps the direct path in use when the daemon is
# absent), and the HTTP-status -> kgsm exit-code mapping for start/stop and
# is-active. The control socket itself is not exercised; the single curl
# chokepoints (__watchdog_curl / __watchdog_status_body) are overridden in-process
# to inject canned responses, so no live daemon is required.

# Two intentional indirections the linter cannot see in this file:
#  - SC2034: config/env vars (KGSM_WATCHDOG_*, config_*) are read by the sourced
#    handler's functions inside command-substitution subshells, not here.
#  - SC2329: the curl/status seam overrides (__watchdog_curl,
#    __watchdog_status_body) are invoked indirectly via the dispatch helpers.
# shellcheck disable=SC2034,SC2329

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="watchdog_routing"
readonly HANDLER="$KGSM_ROOT/commands/handlers/watchdog.sh"

function setup_file() {
  log_test_step "Setting up watchdog routing tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_dir_exists "$KGSM_ROOT" "KGSM root directory should exist"
  assert_file_exists "$HANDLER" "Watchdog handler should exist"

  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_function_exists "__watchdog_socket_path" "__watchdog_socket_path should be exported"
  assert_function_exists "__watchdog_available" "__watchdog_available should be exported"
  assert_function_exists "__watchdog_dispatch_lifecycle" "__watchdog_dispatch_lifecycle should be exported"
  assert_function_exists "__watchdog_is_active" "__watchdog_is_active should be exported"
  assert_function_exists "__watchdog_active_value" "__watchdog_active_value should be exported"
  assert_function_exists "__overlay_status_active" "__overlay_status_active should be exported"
  assert_function_exists "__watchdog_pid_value" "__watchdog_pid_value should be exported"
  assert_function_exists "__overlay_process_pid" "__overlay_process_pid should be exported"

  assert_equals 211 "$EC_SUCCESS_INSTANCE_STARTED" "EC_SUCCESS_INSTANCE_STARTED should be 211"
  assert_equals 212 "$EC_SUCCESS_INSTANCE_STOPPED" "EC_SUCCESS_INSTANCE_STOPPED should be 212"
  assert_equals 51 "$EC_INSUFFICIENT_MEMORY" "EC_INSUFFICIENT_MEMORY should be 51"

  log_test_step "Test environment validated"
}

# Re-source the handler fresh before each test so a per-test override of an
# overridable seam (e.g. __watchdog_curl) never leaks into the next test.
function setup() {
  unset KGSM_LOGIC_WATCHDOG_LOADED
  unset KGSM_WATCHDOG_SOCKET
  unset KGSM_WATCHDOG_DISABLE
  unset config_watchdog_socket
  unset config_enable_watchdog
  # shellcheck disable=SC1090
  source "$HANDLER"
}

# =============================================================================
# SOCKET PATH RESOLUTION
# =============================================================================

function test_socket_path_default() {
  log_test_step "Socket path falls back to the built-in default"

  local path
  path=$(__watchdog_socket_path)

  assert_equals "/run/kgsm-watchdog/control.sock" "$path" \
    "Should return the default control socket path"
}

function test_socket_path_env_override() {
  log_test_step "KGSM_WATCHDOG_SOCKET overrides the default"

  KGSM_WATCHDOG_SOCKET="/tmp/custom-wd.sock"
  local path
  path=$(__watchdog_socket_path)

  assert_equals "/tmp/custom-wd.sock" "$path" \
    "Env override should win"
}

function test_socket_path_config_fallback() {
  log_test_step "config_watchdog_socket is used when no env override is set"

  config_watchdog_socket="/run/alt/wd.sock"
  local path
  path=$(__watchdog_socket_path)

  assert_equals "/run/alt/wd.sock" "$path" \
    "Config value should be used when env is unset"
}

# =============================================================================
# AVAILABILITY GATING (regression guard for the direct-path fallback)
# =============================================================================

function test_unavailable_when_socket_absent() {
  log_test_step "Watchdog is unavailable when the socket does not exist"

  KGSM_WATCHDOG_SOCKET="/tmp/definitely-not-a-socket-$$-xyz.sock"

  __watchdog_available
  assert_not_equals 0 "$?" "Absent socket -> not available -> direct path is used"
}

function test_unavailable_when_disabled() {
  log_test_step "KGSM_WATCHDOG_DISABLE forces the legacy direct path"

  KGSM_WATCHDOG_DISABLE="true"
  # Even pretend the readiness probe would succeed; the opt-out must win first.
  function __watchdog_curl() { echo "200"; return 0; }

  __watchdog_available
  assert_not_equals 0 "$?" "Explicit disable -> not available"
}

function test_unavailable_when_config_disabled() {
  log_test_step "config_enable_watchdog=false disables routing"

  config_enable_watchdog="false"
  function __watchdog_curl() { echo "200"; return 0; }

  __watchdog_available
  assert_not_equals 0 "$?" "Config disable -> not available"
}

# =============================================================================
# START/STOP DISPATCH -> EXIT-CODE MAPPING
# =============================================================================

function test_dispatch_start_200_is_started() {
  log_test_step "POST /start 200 -> EC_SUCCESS_INSTANCE_STARTED"

  function __watchdog_curl() { echo "200"; return 0; }

  __watchdog_dispatch_lifecycle start "myinst"
  assert_equals "$EC_SUCCESS_INSTANCE_STARTED" "$?" \
    "200 should map to the started event code"
}

function test_dispatch_start_409_is_ec_error() {
  log_test_step "POST /start 409 (real failure, e.g. unknown instance) -> EC_ERROR"

  # The daemon returns 409 (ok:false) for a GENUINE failure — e.g. "unknown
  # instance (kgsm-lib returned no info)" or a failed spawn — NOT for "already in
  # the desired state" (a real idempotent no-op like "already running" returns 200
  # ok:true). Mapping 409 to success made kgsm report a successful start AND emit a
  # fabricated instance_started event when the start had actually failed. 409 must
  # surface as an error so the failure is honest, not masked.
  function __watchdog_curl() { echo "409"; return 0; }

  __watchdog_dispatch_lifecycle start "myinst"
  assert_equals "$EC_ERROR" "$?" \
    "409 is a real daemon failure and must map to EC_ERROR, never success"
}

function test_dispatch_start_507_is_insufficient_memory() {
  log_test_step "POST /start 507 -> EC_INSUFFICIENT_MEMORY"

  # The daemon refuses a start the node has no room for with 507, and that must reach
  # the caller as the SAME code this CLI's own gate returns — one rule for both, rather
  # than a capacity refusal arriving as a generic error. A refusal is not a failure:
  # nothing was attempted and nothing is wrong with the instance, so EC_ERROR would
  # invite a retry that gets the identical answer and read as a fault in the server.
  function __watchdog_curl() { echo "507"; return 0; }

  __watchdog_dispatch_lifecycle start "myinst" 2> /dev/null
  assert_equals "$EC_INSUFFICIENT_MEMORY" "$?" \
    "507 should map to the insufficient-memory code, not to a generic error"
}

# The path the last dispatched request asked for. Recorded through a FILE, not a variable:
# __watchdog_curl is called inside a command substitution, so anything the stub assigns dies
# with that subshell.
function __recorded_request_path() { cat "${_REQUEST_PATH_FILE:-/dev/null}" 2> /dev/null; }

# A curl seam that answers 200 and records the path it was asked for. The status is a literal
# because the stub body is evaluated when it RUNS, long after this function's locals are gone.
function __record_requests() {
  [[ -n "${_REQUEST_PATH_FILE:-}" ]] && rm -f "$_REQUEST_PATH_FILE"
  _REQUEST_PATH_FILE="$(mktemp)"
  function __watchdog_curl() { printf '%s' "$2" > "$_REQUEST_PATH_FILE"; echo "200"; return 0; }
}

function test_dispatch_start_force_is_carried_to_the_daemon() {
  log_test_step "start --force -> POST /start/<name>?force=true"

  # The override has to reach the daemon or it overrides nothing for a native instance:
  # the daemon runs the same arithmetic with the instances already starting subtracted as
  # well, so it refuses everything this CLI's own gate would and more. The URL is the only
  # channel this transport has — no body goes out, only a status comes back.
  __record_requests

  __watchdog_dispatch_lifecycle start "myinst" "true"
  assert_equals "$EC_SUCCESS_INSTANCE_STARTED" "$?" "A forced start still maps 200 to the started code"
  assert_equals "start/myinst?force=true" "$(__recorded_request_path)" \
    "The force flag should ride the request path"
}

function test_dispatch_start_without_force_asks_for_no_override() {
  log_test_step "start (no force) -> POST /start/<name>, no query"

  # The protection is what a caller gets by not asking for it, so anything other than an
  # explicit "true" must leave the path bare.
  __record_requests

  __watchdog_dispatch_lifecycle start "myinst"
  assert_equals "start/myinst" "$(__recorded_request_path)" "An unforced start should carry no query flag"

  __watchdog_dispatch_lifecycle start "myinst" "false"
  assert_equals "start/myinst" "$(__recorded_request_path)" "force=false should carry no query flag"
}

function test_dispatch_stop_never_carries_force() {
  log_test_step "stop ignores force — there is no capacity check on a stop"

  __record_requests

  __watchdog_dispatch_lifecycle stop "myinst" "true"
  assert_equals "stop/myinst" "$(__recorded_request_path)" "A stop has nothing to override"
}

function test_dispatch_stop_200_is_stopped() {
  log_test_step "POST /stop 200 -> EC_SUCCESS_INSTANCE_STOPPED"

  function __watchdog_curl() { echo "200"; return 0; }

  __watchdog_dispatch_lifecycle stop "myinst"
  assert_equals "$EC_SUCCESS_INSTANCE_STOPPED" "$?" \
    "200 should map to the stopped event code"
}

function test_dispatch_server_error_is_ec_error() {
  log_test_step "5xx -> EC_ERROR"

  function __watchdog_curl() { echo "500"; return 0; }

  __watchdog_dispatch_lifecycle start "myinst"
  assert_equals "$EC_ERROR" "$?" "A 5xx response should be an error"
}

function test_dispatch_connection_failure_is_ec_error() {
  log_test_step "curl connection failure -> EC_ERROR (no silent fallback)"

  # Non-zero return models a connection failure mid-call. Availability was
  # already confirmed by the caller, so this must surface as an error rather
  # than silently re-spawning via the direct path.
  function __watchdog_curl() { echo ""; return 7; }

  __watchdog_dispatch_lifecycle start "myinst"
  assert_equals "$EC_ERROR" "$?" "Connection failure should map to EC_ERROR"
}

function test_dispatch_unknown_verb_is_invalid_arg() {
  log_test_step "Unknown verb -> EC_INVALID_ARG"

  __watchdog_dispatch_lifecycle frobnicate "myinst"
  assert_equals "$EC_INVALID_ARG" "$?" "An unsupported verb should be rejected"
}

# =============================================================================
# IS-ACTIVE -> liveness mapping
# =============================================================================

function test_is_active_populated_true() {
  log_test_step "/status populated:true -> active (0)"

  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","desired":"running","populated":true,"phase":"running"}'
    return 0
  }

  __watchdog_is_active "myinst"
  assert_equals 0 "$?" "populated:true should report active"
}

function test_is_active_populated_false() {
  log_test_step "/status populated:false -> inactive (1)"

  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","desired":"stopped","populated":false,"phase":"stopped"}'
    return 0
  }

  __watchdog_is_active "myinst"
  assert_equals 1 "$?" "populated:false should report inactive"
}

function test_is_active_not_tracked_is_unknown() {
  log_test_step "/status 404 (not tracked) -> unknown (2), caller falls through"

  function __watchdog_status_body() { printf '%s' ''; return 1; }

  __watchdog_is_active "myinst"
  assert_equals 2 "$?" "Not-tracked should map to unknown so the caller falls through"
}

# =============================================================================
# __watchdog_tracks -> stop-routing decision (orphan-safety guard)
# =============================================================================

function test_tracks_true_when_running() {
  log_test_step "Tracked + populated -> tracks (route stop to daemon)"

  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","populated":true,"phase":"running"}'
    return 0
  }

  __watchdog_tracks "myinst"
  assert_equals 0 "$?" "A populated tracked instance is owned by the daemon"
}

function test_tracks_true_when_tracked_but_stopped() {
  log_test_step "Tracked + not populated -> still tracks (route stop to daemon)"

  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","populated":false,"phase":"restart-pending"}'
    return 0
  }

  __watchdog_tracks "myinst"
  assert_equals 0 "$?" "A tracked-but-unpopulated instance is still daemon-owned"
}

function test_tracks_false_when_not_tracked() {
  log_test_step "Not tracked (404) -> does not track (stop falls through to direct path)"

  # This is the orphan case: an instance started via the direct path before the
  # daemon existed. Stop must NOT be routed to the daemon (it would falsely report
  # success while the orphan kept running).
  function __watchdog_status_body() { printf '%s' ''; return 1; }

  __watchdog_tracks "myinst"
  assert_not_equals 0 "$?" "An untracked orphan must fall through to the direct stop"
}

# =============================================================================
# RUN-STATE VALUE (__watchdog_active_value) -> overlay input
# =============================================================================

function test_active_value_true_when_populated() {
  log_test_step "__watchdog_active_value -> 'true' when the daemon reports populated"

  function __watchdog_available() { return 0; }
  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","populated":true,"phase":"running"}'
    return 0
  }

  assert_equals "true" "$(__watchdog_active_value myinst)" \
    "A populated tracked instance resolves to true"
}

function test_active_value_false_when_not_populated() {
  log_test_step "__watchdog_active_value -> 'false' when tracked but not populated"

  function __watchdog_available() { return 0; }
  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","populated":false,"phase":"stopped"}'
    return 0
  }

  assert_equals "false" "$(__watchdog_active_value myinst)" \
    "A tracked-but-unpopulated instance resolves to false"
}

function test_active_value_empty_when_untracked() {
  log_test_step "__watchdog_active_value -> '' when the daemon does not track it"

  function __watchdog_available() { return 0; }
  function __watchdog_status_body() { printf '%s' ''; return 1; } # 404 -> unknown

  assert_equals "" "$(__watchdog_active_value myinst)" \
    "An untracked instance yields no value so the caller keeps the mgmt value"
}

function test_active_value_empty_when_daemon_absent() {
  log_test_step "__watchdog_active_value -> '' when the daemon is unavailable"

  # No curl is attempted: availability is the gate, so the absent-daemon case
  # short-circuits (and avoids a per-instance timeout on the fleet path).
  function __watchdog_available() { return 1; }

  assert_equals "" "$(__watchdog_active_value myinst)" \
    "A daemon-down host yields no value"
}

# =============================================================================
# STATUS OVERLAY (__overlay_status_active) -> status<->is-active reconciliation
# =============================================================================
#
# Fixture: a management script's status for a running, watchdog-spawned native
# instance reads status:false (it has no PID file) while the daemon reports it
# active. The overlay is the pure transform that reconciles the two — no socket.

readonly STATUS_JSON_FALSE='{"instance_name":"myinst","status":false,"process":{"pid":null,"status":null,"start_time":null},"version":{"current":"1"}}'

function test_overlay_json_running_overrides_false() {
  log_test_step "Overlay rewrites status:false -> true for a running watchdog instance"

  local out
  out=$(__overlay_status_active "json" "true" "$STATUS_JSON_FALSE")

  assert_equals "true" "$(printf '%s' "$out" | jq -c '.status')" \
    "The status field is overlaid to true"
  assert_equals '"myinst"' "$(printf '%s' "$out" | jq -c '.instance_name')" \
    "Other fields are preserved"
}

function test_overlay_json_passthrough_when_empty() {
  log_test_step "Overlay leaves output untouched when there is no authoritative value"

  local out
  out=$(__overlay_status_active "json" "" "$STATUS_JSON_FALSE")

  assert_equals "false" "$(printf '%s' "$out" | jq -c '.status')" \
    "Empty active value preserves the mgmt-script value (orphan / container / daemon down)"
}

function test_overlay_json_false_stays_false() {
  log_test_step "Overlay of false keeps a stopped instance false (no false-positive)"

  local out
  out=$(__overlay_status_active "json" "false" "$STATUS_JSON_FALSE")

  assert_equals "false" "$(printf '%s' "$out" | jq -c '.status')" \
    "An inactive daemon state stays false"
}

function test_overlay_json_falls_back_on_bad_input() {
  log_test_step "Overlay emits the raw value rather than nothing if jq cannot parse it"

  local raw="not valid json"
  local out
  out=$(__overlay_status_active "json" "true" "$raw")

  assert_equals "$raw" "$out" \
    "Unparseable input is passed through (the un-overlaid truth beats an empty reply)"
}

function test_overlay_text_inactive_to_active() {
  log_test_step "Overlay rewrites the human-readable Status line to Active"

  local raw="=== Instance Status: myinst ===
Status: ✗ Inactive
Version: 1"
  local out
  out=$(__overlay_status_active "" "true" "$raw")

  assert_contains "$out" "Status: ✓ Active" "The Status line is rewritten to Active"
  assert_not_contains "$out" "Inactive" "The stale Inactive line is gone"
}

function test_overlay_text_passthrough_when_empty() {
  log_test_step "Overlay leaves text untouched when there is no authoritative value"

  local raw="=== Instance Status: myinst ===
Status: ✗ Inactive
Version: 1"
  local out
  out=$(__overlay_status_active "" "" "$raw")

  assert_contains "$out" "Status: ✗ Inactive" "Empty active value preserves the mgmt text"
}

# =============================================================================
# PID ENRICHMENT (__watchdog_pid_value / __overlay_process_pid)
# =============================================================================
#
# The daemon's /status body carries the real PID of the process it cgroup-spawned,
# which the management script (no PID file) reports as null. These fill it in.

function test_pid_value_when_populated() {
  log_test_step "__watchdog_pid_value -> the daemon's PID for a running instance"

  function __watchdog_available() { return 0; }
  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","populated":true,"pid":1560010,"phase":"running"}'
    return 0
  }

  assert_equals "1560010" "$(__watchdog_pid_value myinst)" \
    "A populated instance surfaces the daemon's PID"
}

function test_pid_value_empty_when_not_populated() {
  log_test_step "__watchdog_pid_value -> '' for a tracked-but-stopped instance (no stale PID)"

  function __watchdog_available() { return 0; }
  function __watchdog_status_body() {
    printf '%s' '{"name":"myinst","populated":false,"pid":null,"phase":"stopped"}'
    return 0
  }

  assert_equals "" "$(__watchdog_pid_value myinst)" \
    "A non-populated instance surfaces no PID (a stale PID would be a fabrication)"
}

function test_pid_value_empty_when_untracked() {
  log_test_step "__watchdog_pid_value -> '' when the daemon does not track it"

  function __watchdog_available() { return 0; }
  function __watchdog_status_body() { printf '%s' ''; return 1; } # 404

  assert_equals "" "$(__watchdog_pid_value myinst)" \
    "An untracked instance surfaces no PID"
}

function test_pid_value_empty_when_daemon_absent() {
  log_test_step "__watchdog_pid_value -> '' when the daemon is unavailable"

  function __watchdog_available() { return 1; }

  assert_equals "" "$(__watchdog_pid_value myinst)" \
    "A daemon-down host surfaces no PID"
}

function test_overlay_pid_fills_null_process_pid() {
  log_test_step "Overlay fills process.pid from the daemon when status JSON has null"

  local out
  out=$(__overlay_process_pid "json" "1560010" "$STATUS_JSON_FALSE")

  assert_equals "1560010" "$(printf '%s' "$out" | jq -c '.process.pid')" \
    "process.pid is filled from the watchdog"
  assert_equals "false" "$(printf '%s' "$out" | jq -c '.status')" \
    "Only process.pid is touched; the status field is left to the other overlay"
}

function test_overlay_pid_passthrough_when_empty() {
  log_test_step "Overlay leaves process.pid null when there is no PID"

  local out
  out=$(__overlay_process_pid "json" "" "$STATUS_JSON_FALSE")

  assert_equals "null" "$(printf '%s' "$out" | jq -c '.process.pid')" \
    "Empty PID preserves the management script's null"
}

function test_overlay_pid_ignores_nonnumeric() {
  log_test_step "Overlay rejects a non-numeric PID (defensive — no jq injection)"

  local out
  out=$(__overlay_process_pid "json" "; rm -rf /" "$STATUS_JSON_FALSE")

  assert_equals "$STATUS_JSON_FALSE" "$out" \
    "A non-numeric PID passes the output through untouched"
}

function test_overlay_pid_text_is_passthrough() {
  log_test_step "Overlay does not touch human-readable output (JSON only)"

  local raw="=== Instance Status: myinst ===
Status: ✓ Active"
  local out
  out=$(__overlay_process_pid "" "1560010" "$raw")

  assert_equals "$raw" "$out" "Text form is left as-is"
}
