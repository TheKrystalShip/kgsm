#!/usr/bin/env bash

# KGSM Pure Logic Layer - Watchdog Routing
#
# Routes native (standalone) lifecycle operations to the resident kgsm-watchdog
# daemon when it is present and ready. The daemon owns the cgroup-v2 spawn and
# crash-restart (see ../../docs/specs/cgroup-supervision-plan.md and the
# kgsm-watchdog repo); when it is absent or unreachable these helpers report
# "not available" so the caller transparently falls back to the direct
# management-script path. No user-facing I/O — results are exit codes only.
#
# Transport mirrors the daemon's control protocol: HTTP/1.1 over a unix socket
# (curl --unix-socket). The socket's filesystem perms are the security boundary.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_WATCHDOG_LOADED}" ]]; then
  return 0
fi

# Default control socket — matches kgsm-watchdog's KGSM_WATCHDOG_SOCKET default.
# Guarded so re-sourcing the module never re-declares the readonly constant.
if [[ -z "${KGSM_WATCHDOG_DEFAULT_SOCKET:-}" ]]; then
  declare -g -r KGSM_WATCHDOG_DEFAULT_SOCKET="/run/kgsm-watchdog/control.sock"
fi

# Resolves the watchdog control socket path.
# Order: explicit env override > config flag > built-in default.
# Returns: echoes the socket path, always 0.
function __watchdog_socket_path() {
  if [[ -n "${KGSM_WATCHDOG_SOCKET:-}" ]]; then
    echo "$KGSM_WATCHDOG_SOCKET"
  elif [[ -n "${config_watchdog_socket:-}" ]]; then
    echo "$config_watchdog_socket"
  else
    echo "$KGSM_WATCHDOG_DEFAULT_SOCKET"
  fi
}

export -f __watchdog_socket_path

# Single curl chokepoint for code-only requests against the control socket.
# Echoes the HTTP status code to stdout and returns curl's own exit code
# (non-zero = could not connect). Kept as one function so the routing logic has
# a single, overridable seam.
# Args: $1 = HTTP method, $2 = path (no leading slash), $3 = max-time seconds (default 60)
# Returns: curl exit code (0 = connected); echoes the 3-digit HTTP status
function __watchdog_curl() {
  local _method="$1"
  local _path="$2"
  local _max_time="${3:-60}"

  local _sock
  _sock="$(__watchdog_socket_path)"

  curl -s -o /dev/null -w '%{http_code}' \
    --max-time "$_max_time" \
    -X "$_method" \
    --unix-socket "$_sock" \
    "http://localhost/$_path" 2> /dev/null
}

export -f __watchdog_curl

# Is the watchdog present AND ready to supervise?
# True only when: routing is not disabled, curl exists, the socket is a live
# unix-domain socket, and GET /health returns 200. A stale socket file (daemon
# dead) yields a connection failure, not a hang (curl --max-time), so the caller
# falls back to the direct path.
# Returns: 0 if the watchdog is usable, non-zero otherwise
function __watchdog_available() {
  # Explicit opt-out lets an operator force the legacy direct-spawn path.
  [[ "${KGSM_WATCHDOG_DISABLE:-}" == "true" ]] && return 1
  # Forward-compatible config flag (defaults to enabled when the key is absent).
  [[ "${config_enable_watchdog:-true}" == "true" ]] || return 1

  command -v curl > /dev/null 2>&1 || return 1

  local _sock
  _sock="$(__watchdog_socket_path)"
  [[ -S "$_sock" ]] || return 1

  local _code
  _code="$(__watchdog_curl GET health 2)" || return 1
  [[ "$_code" == "200" ]]
}

export -f __watchdog_available

# Routes a start/stop verb to the watchdog and maps the HTTP result to a kgsm
# exit code mirroring the direct path's contract:
#   200 -> success event code (started/stopped)
#   409 -> already in the desired state; treated as idempotent success
#   connection failure / other status -> EC_ERROR. Availability was already
#     confirmed by the caller, so a failure here is a real error: do NOT silently
#     re-spawn via the direct path (that risks a double start).
# Args: $1 = verb (start|stop), $2 = instance name
# Returns: EC_SUCCESS_INSTANCE_STARTED / EC_SUCCESS_INSTANCE_STOPPED, or an error code
function __watchdog_dispatch_lifecycle() {
  local _verb="$1"
  local _name="${2%.ini}"

  local _path
  local _success_ec
  local _timeout
  case "$_verb" in
    start)
      _path="start/$_name"
      _success_ec=$EC_SUCCESS_INSTANCE_STARTED
      _timeout=60
      ;;
    stop)
      _path="stop/$_name"
      _success_ec=$EC_SUCCESS_INSTANCE_STOPPED
      _timeout=120
      ;;
    *)
      return $EC_INVALID_ARG
      ;;
  esac

  local _code
  local _rc
  _code="$(__watchdog_curl POST "$_path" "$_timeout")"
  _rc=$?

  if [[ $_rc -ne 0 ]]; then
    return $EC_ERROR
  fi

  case "$_code" in
    200) return $_success_ec ;;
    409) return $_success_ec ;;
    *) return $EC_ERROR ;;
  esac
}

export -f __watchdog_dispatch_lifecycle

# Fetches GET /status/<name>. Echoes the JSON response body; returns 0 only on
# HTTP 200, non-zero on 404 / connection failure / any other status. Separate
# from __watchdog_curl because liveness needs the body, not just the code.
# Args: $1 = instance name
# Returns: 0 on HTTP 200 (body echoed), non-zero otherwise
function __watchdog_status_body() {
  local _name="${1%.ini}"

  local _sock
  _sock="$(__watchdog_socket_path)"

  local _resp
  local _code
  _resp="$(curl -s -w $'\n%{http_code}' --max-time 5 \
    --unix-socket "$_sock" \
    "http://localhost/status/$_name" 2> /dev/null)" || return 2

  _code="${_resp##*$'\n'}"
  printf '%s' "${_resp%$'\n'*}"

  [[ "$_code" == "200" ]] && return 0
  return 1
}

export -f __watchdog_status_body

# Queries the watchdog for an instance's liveness via /status.
# Returns:
#   0 - active   (tracked and cgroup populated)
#   1 - inactive (tracked but not populated: stopped / restart-pending)
#   2 - unknown  (not tracked by the watchdog, or a connection error) — the
#       caller should fall through to the direct PID-based check.
# Args: $1 = instance name
function __watchdog_is_active() {
  local _name="${1%.ini}"

  local _body
  local _rc
  _body="$(__watchdog_status_body "$_name")"
  _rc=$?
  [[ $_rc -ne 0 ]] && return 2

  # System.Text.Json emits compact, camelCase output; strip any stray whitespace
  # to keep the substring match robust.
  local _compact="${_body//[[:space:]]/}"
  [[ "$_compact" == *'"populated":true'* ]] && return 0
  return 1
}

export -f __watchdog_is_active

# Does the watchdog currently track this instance? Used to decide whether stop
# should be routed to the daemon. A "not tracked" result means the instance is not
# under supervision — typically an orphan started via the direct path before the
# daemon existed. Routing its stop to the daemon would be wrong: the daemon only
# sees its own cgroups, so it would report "not running" (HTTP 200) while the orphan
# kept running, and a subsequent restart would double-spawn. So an untracked
# instance falls through to the direct (PID-file) stop instead.
# Args: $1 = instance name
# Returns: 0 if the watchdog tracks it (route to the daemon), non-zero otherwise
function __watchdog_tracks() {
  __watchdog_is_active "$1"
  local _rc=$?
  [[ $_rc -eq 0 || $_rc -eq 1 ]]
}

export -f __watchdog_tracks

# Resolves the watchdog's authoritative run-state for an instance as a value (for
# callers that need to overlay it onto status output, not branch on an exit code).
# Native instances are cgroup-spawned by the daemon with no PID file, so a
# management script's own PID-based check reads a running, watchdog-supervised
# instance as inactive; the daemon is the source of truth. Echoes:
#   "true"  - tracked and the cgroup is populated (running)
#   "false" - tracked but not populated (stopped / restart-pending)
#   ""      - not the watchdog's to answer (daemon absent, or instance untracked:
#             an orphan or a container) -> the caller keeps the management
#             script's own value unchanged.
# Args: $1 = instance name
function __watchdog_active_value() {
  local _name="$1"

  # Gate on availability first: a fast socket-exists check avoids a per-instance
  # curl timeout on the fleet path when the daemon is absent.
  if ! __watchdog_available; then
    printf ''
    return 0
  fi

  __watchdog_is_active "$_name"
  case $? in
    0) printf 'true' ;;
    1) printf 'false' ;;
    *) printf '' ;; # untracked / unknown -> caller keeps the mgmt-script value
  esac
}

export -f __watchdog_active_value

# Overlays an authoritative run-state onto a management script's status output so
# the reported state can never diverge from is-active. The management script
# derives liveness from its PID file, which the watchdog never writes for the
# instances it cgroup-spawns; this rewrites the run-state in that output to the
# value the daemon reports, making `status` consult the SAME authority as
# is-active. An empty active value means "not the watchdog's to answer" (see
# __watchdog_active_value): the output is passed through untouched, so there is
# zero change for orphans, containers, or a daemon-down host. Pure (no socket I/O)
# so the reconciliation is unit-testable with a canned active value.
# Args: $1 = json_format (non-empty = JSON output), $2 = active (true|false|""),
#       $3 = raw status output from the management script
# Outputs: the (possibly overlaid) status output
function __overlay_status_active() {
  local _json_format="$1"
  local _active="$2"
  local _raw="$3"

  # No authoritative value -> leave the management script's output as-is.
  if [[ -z "$_active" ]]; then
    printf '%s' "$_raw"
    return 0
  fi

  if [[ -n "$_json_format" ]]; then
    # Rewrite only the boolean status field; every other field is preserved. If
    # jq fails (unexpected output), emit the raw value rather than nothing — the
    # un-overlaid truth beats an empty reply.
    local _out
    if _out=$(printf '%s' "$_raw" | jq --argjson active "$_active" '.status = $active' 2> /dev/null) \
      && [[ -n "$_out" ]]; then
      printf '%s' "$_out"
    else
      printf '%s' "$_raw"
    fi
  else
    # Human-readable form: the template prints exactly one line beginning with
    # "Status:" — either "Status: ✓ Active" or "Status: ✗ Inactive". Rewrite it.
    local _line="Status: ✗ Inactive"
    [[ "$_active" == "true" ]] && _line="Status: ✓ Active"
    printf '%s' "$_raw" | sed "s/^Status:.*/$_line/"
  fi
}

export -f __overlay_status_active

# ---- boot auto-start (enable/disable) ------------------------------------------------------------
# The systemctl-style boot axis, orthogonal to start/stop. These drive the daemon's persisted
# desired-state set (POST /enable, /disable; GET /enabled). Only meaningful WITH the watchdog —
# there is no other boot-auto-start mechanism — so the caller should gate on __watchdog_available.

# Routes enable/disable to the watchdog and maps the HTTP result to a kgsm exit code.
#   200 -> success event code (enabled/disabled)
#   connection failure / other status (e.g. 409 out-of-scope/unknown) -> EC_ERROR.
# Args: $1 = verb (enable|disable), $2 = instance name
# Returns: EC_SUCCESS_AUTOSTART_ENABLED / EC_SUCCESS_AUTOSTART_DISABLED, or an error code
function __watchdog_set_autostart() {
  local _verb="$1"
  local _name="${2%.ini}"

  local _path
  local _success_ec
  case "$_verb" in
    enable)
      _path="enable/$_name"
      _success_ec=$EC_SUCCESS_AUTOSTART_ENABLED
      ;;
    disable)
      _path="disable/$_name"
      _success_ec=$EC_SUCCESS_AUTOSTART_DISABLED
      ;;
    *)
      return $EC_INVALID_ARG
      ;;
  esac

  local _code
  local _rc
  _code="$(__watchdog_curl POST "$_path" 10)"
  _rc=$?

  if [[ $_rc -ne 0 ]]; then
    return $EC_ERROR
  fi

  [[ "$_code" == "200" ]] && return $_success_ec
  return $EC_ERROR
}

export -f __watchdog_set_autostart

# Fetches GET /enabled. Echoes the JSON array body; returns 0 only on HTTP 200, non-zero on
# connection failure / any other status. Separate from __watchdog_curl because the set needs the body.
# Returns: 0 on HTTP 200 (body echoed), 1 on other status, 2 on connection failure
function __watchdog_enabled_body() {
  local _sock
  _sock="$(__watchdog_socket_path)"

  local _resp
  local _code
  _resp="$(curl -s -w $'\n%{http_code}' --max-time 5 \
    --unix-socket "$_sock" \
    "http://localhost/enabled" 2> /dev/null)" || return 2

  _code="${_resp##*$'\n'}"
  printf '%s' "${_resp%$'\n'*}"

  [[ "$_code" == "200" ]] && return 0
  return 1
}

export -f __watchdog_enabled_body

# Echoes the enabled instance names, one per line (nothing if the set is empty or unreachable).
# Returns: 0 on success, 2 if the daemon is unreachable.
function __watchdog_enabled_names() {
  local _body
  local _rc
  _body="$(__watchdog_enabled_body)"
  _rc=$?
  [[ $_rc -eq 2 ]] && return 2

  # Compact JSON array of strings: ["a","b"] -> one quoted token per line, unquoted.
  echo "$_body" | grep -oE '"[^"]*"' | sed 's/^"//; s/"$//'
  return 0
}

export -f __watchdog_enabled_names

# Is <name> in the enabled set?
# Returns: 0 enabled, 1 not enabled, 2 daemon unreachable.
# Args: $1 = instance name
function __watchdog_is_enabled() {
  local _name="${1%.ini}"

  local _names
  local _rc
  _names="$(__watchdog_enabled_names)"
  _rc=$?
  [[ $_rc -eq 2 ]] && return 2

  grep -qxF "$_name" <<< "$_names" && return 0
  return 1
}

export -f __watchdog_is_enabled

# Mark module as loaded
declare -g KGSM_LOGIC_WATCHDOG_LOADED=1
export KGSM_LOGIC_WATCHDOG_LOADED
