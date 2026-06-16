#!/usr/bin/env bash

# KGSM Pure Logic Layer - Firewall Authority Routing
#
# Routes host-firewall open/close operations to the resident kgsm-firewall
# authority — the ecosystem's single owner of host-firewall state (see
# ../../../headless-network-plan.md §7 and the kgsm-firewall repo). kgsm shells
# the authority's bundled CLI client (`kgsm-firewall ensure-open | remove`); the
# binary owns ALL socket/wire talk, so bash never parses a wire protocol — the
# mirror of how handlers/watchdog.sh routes lifecycle to kgsm-watchdog.
#
# No user-facing I/O of its own — results are exit codes only. The CLI binary's
# own stderr (e.g. "cannot reach the firewall authority …") is intentionally
# left to flow through: it is the explicit, self-explanatory message the
# hard-fail (B) install path is meant to surface. Its stdout (a success
# confirmation line) is suppressed — the command layer prints kgsm's own message.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_FIREWALL_LOADED}" ]]; then
  return 0
fi

# Default control socket — matches kgsm-firewall's KGSM_FIREWALL_SOCKET default.
# Guarded so re-sourcing the module never re-declares the readonly constant.
if [[ -z "${KGSM_FIREWALL_DEFAULT_SOCKET:-}" ]]; then
  declare -g -r KGSM_FIREWALL_DEFAULT_SOCKET="/run/kgsm-firewall/firewall.sock"
fi

# Resolves the kgsm-firewall control socket path.
# Order: explicit env override > config flag > built-in default.
# Returns: echoes the socket path, always 0.
function __firewall_socket_path() {
  if [[ -n "${KGSM_FIREWALL_SOCKET:-}" ]]; then
    echo "$KGSM_FIREWALL_SOCKET"
  elif [[ -n "${config_firewall_socket:-}" ]]; then
    echo "$config_firewall_socket"
  else
    echo "$KGSM_FIREWALL_DEFAULT_SOCKET"
  fi
}

export -f __firewall_socket_path

# Resolves the kgsm-firewall binary (its own bundled CLI client).
# Order: explicit env override > config flag > PATH lookup.
# Returns: echoes the binary path and 0 if found, non-zero if absent.
function __firewall_bin() {
  if [[ -n "${KGSM_FIREWALL_BIN:-}" ]]; then
    echo "$KGSM_FIREWALL_BIN"
    return 0
  fi
  if [[ -n "${config_firewall_bin:-}" ]]; then
    echo "$config_firewall_bin"
    return 0
  fi
  command -v kgsm-firewall 2> /dev/null
}

export -f __firewall_bin

# Is the kgsm-firewall authority reachable? True only when the binary resolves
# AND a `backend` probe returns success (exit 0) — i.e. the daemon answered. An
# absent binary, a missing/refused socket, or a non-zero probe all yield false.
# Returns: 0 if reachable, non-zero otherwise.
function __firewall_available() {
  local _bin
  _bin="$(__firewall_bin)" || return 1
  [[ -z "$_bin" ]] && return 1

  local _sock
  _sock="$(__firewall_socket_path)"
  KGSM_FIREWALL_SOCKET="$_sock" "$_bin" backend > /dev/null 2>&1
}

export -f __firewall_available

# Single invocation chokepoint: shells the CLI client with KGSM_FIREWALL_SOCKET
# set, then maps its exit-code contract (kgsm-firewall ExitCodes) to a kgsm EC:
#   0 Success      -> EC_SUCCESS              (applied / removed / noop)
#   3 Unreachable  -> EC_FIREWALL_UNREACHABLE (authority down — §7g hard-fail)
#   2/4/5          -> EC_FIREWALL                  (reachable, but unsuccessful)
# An absent binary is itself "unreachable" (the authority is unavailable).
# Args: $@ = verb + args (e.g. ensure-open <instance> <token>...)
# Returns: the mapped EC.
function __firewall_invoke() {
  local _bin
  if ! _bin="$(__firewall_bin)" || [[ -z "$_bin" ]]; then
    return $EC_FIREWALL_UNREACHABLE
  fi

  # A resolved-but-unrunnable binary (e.g. an explicit override pointing at a
  # missing path) is itself "authority unavailable", not a backend op failure.
  if ! command -v "$_bin" > /dev/null 2>&1; then
    return $EC_FIREWALL_UNREACHABLE
  fi

  local _sock
  _sock="$(__firewall_socket_path)"

  local _rc
  KGSM_FIREWALL_SOCKET="$_sock" "$_bin" "$@" > /dev/null
  _rc=$?

  case "$_rc" in
    0) return $EC_SUCCESS ;;
    3) return $EC_FIREWALL_UNREACHABLE ;;
    *) return $EC_FIREWALL ;;
  esac
}

export -f __firewall_invoke

# Asks the authority to ensure the given ports are open for an instance.
# Args: $1 = instance name, $2... = ufw-style port tokens
#       (port[/proto] | start:end/proto)
# Returns: the mapped EC from __firewall_invoke; EC_INVALID_ARG if misused.
function __firewall_ensure_open() {
  local _instance="$1"
  shift

  [[ -z "$_instance" ]] && return $EC_INVALID_ARG
  # The caller must skip empty-port instances: `ensure-open` requires >=1 port.
  [[ $# -eq 0 ]] && return $EC_INVALID_ARG

  __firewall_invoke ensure-open "$_instance" "$@"
}

export -f __firewall_ensure_open

# Asks the authority to remove every firewall rule it owns for an instance.
# Idempotent: a no-op (nothing owned) is a success.
# Args: $1 = instance name
# Returns: the mapped EC from __firewall_invoke; EC_INVALID_ARG if misused.
function __firewall_remove() {
  local _instance="$1"
  [[ -z "$_instance" ]] && return $EC_INVALID_ARG

  __firewall_invoke remove "$_instance"
}

export -f __firewall_remove

# Converts a UFW-style port spec ("34197/udp|27015:27020/tcp") into the
# space-separated `port[/proto]` token list the kgsm-firewall CLI accepts
# ("34197/udp 27015:27020/tcp"), via the single-source-of-truth parser. A
# proto-less entry expands to BOTH tcp and udp (matching ufw's implicit-both)
# and ranges are preserved. Echoes nothing for an empty spec.
# Args: $1 = ufw port spec
# Returns: EC_SUCCESS (tokens echoed), EC_ERROR on a malformed spec.
function __firewall_ports_to_tokens() {
  local _spec="$1"
  [[ -z "$_spec" ]] && return $EC_SUCCESS

  local _triples
  _triples="$(__parse_ufw_port_spec "$_spec")" || return $EC_ERROR

  local _start _end _proto
  local -a _tokens=()
  while read -r _start _end _proto; do
    [[ -z "$_start" ]] && continue
    if [[ "$_start" == "$_end" ]]; then
      _tokens+=("${_start}/${_proto}")
    else
      _tokens+=("${_start}:${_end}/${_proto}")
    fi
  done <<< "$_triples"

  echo "${_tokens[*]}"
  return $EC_SUCCESS
}

export -f __firewall_ports_to_tokens

# Mark module as loaded
declare -g KGSM_LOGIC_FIREWALL_LOADED=1
export KGSM_LOGIC_FIREWALL_LOADED
