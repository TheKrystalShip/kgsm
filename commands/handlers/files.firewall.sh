#!/usr/bin/env bash

# KGSM Pure Logic Layer - Firewall Integration Operations
#
# This module contains pure business logic functions for firewall integration
# operations, routed through the kgsm-firewall authority (backend-agnostic).
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - EC_SUCCESS_FIREWALL_ENABLED (215): firewall integration enabled successfully
# - EC_SUCCESS_FIREWALL_DISABLED (216): firewall integration disabled successfully
# - Standard error codes: EC_INVALID_ARG, EC_FILE_NOT_FOUND, EC_FIREWALL, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_FILES_FIREWALL_LOADED}" ]]; then
  return 0
fi

# Load common file logic functions
if [[ -z "${KGSM_LOGIC_FILES_COMMON_LOADED}" ]]; then
  # shellcheck source=files.common.sh
  source "$(__find_command_handler files.common.sh)" || return $EC_FAILED_SOURCE
fi

# Load the firewall-authority routing chokepoint (kgsm-firewall IPC client).
if [[ -z "${KGSM_LOGIC_FIREWALL_LOADED}" ]]; then
  # shellcheck source=firewall.sh
  source "$(__find_command_handler firewall.sh)" || return $EC_FAILED_SOURCE
fi

# Enable firewall integration for an instance by handing its ports to the
# kgsm-firewall authority (the host-firewall owner). kgsm no longer renders a
# ufw profile or shells `ufw` itself — the authority owns rule rendering and the
# backend, tagging rules `kgsm-<instance>`. Hard-fail (B): if the authority is
# unreachable the original EC_FIREWALL_UNREACHABLE propagates so the install
# aborts rather than silently proceeding.
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_FIREWALL_ENABLED on success, error code on failure
function __logic_enable_firewall_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Source the instance config to expose its name + UFW-format port spec
  # (instance_name / instance_ports).
  # shellcheck disable=SC1090
  __source_instance "$instance_config_file" || return $EC_FAILED_SOURCE

  local _instance_name="${instance_name:-}"
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Convert the UFW spec into the kgsm-firewall CLI's port tokens. An instance
  # with no ports has nothing to open: record the toggle and return without
  # bothering the authority (`ensure-open` requires >=1 port).
  local _tokens
  if ! _tokens=$(__firewall_ports_to_tokens "${instance_ports:-}"); then
    return $EC_ERROR
  fi

  if [[ -n "$_tokens" ]]; then
    local -a _token_arr
    read -ra _token_arr <<< "$_tokens"
    __firewall_ensure_open "$_instance_name" "${_token_arr[@]}"
    local _rc=$?
    if [[ $_rc -ne $EC_SUCCESS ]]; then
      return $_rc
    fi
  fi

  # Record that firewall management is on for this instance. The authority owns
  # the host rule now (tagged kgsm-<instance>), so firewall_rule_file — the path
  # of the old kgsm-rendered ufw profile — is no longer written.
  if ! __add_or_update_config "$instance_config_file" "enable_firewall_management" "true"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_FIREWALL_ENABLED
}

export -f __logic_enable_firewall_integration

# Re-assert an instance's firewall rule, for the bring-up path to call on every
# start. The rule the authority owns is host state KGSM does not hold a lock on
# — a `ufw reset`, a hand-edited ruleset or a reprovisioned host drops it while
# the instance config still says firewall management is on — and a game server
# whose ports are shut is unreachable with nothing in KGSM to say so. Asking the
# authority every time closes that window: `ensure-open` is idempotent, so the
# already-open case costs one round trip and changes nothing.
#
# Two things make it a no-op rather than a failure: an instance whose operator
# turned firewall management off (that is an explicit "stop managing this", and
# a start must not undo it), and an instance that declares no ports.
#
# Best-effort by design: the caller starts the server whatever this returns. A
# firewall authority that is down is a reason to warn, not a reason to refuse to
# run a game server — the opposite of the install path's hard-fail, where there
# is no server yet to keep off the air.
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS when the ports are open or the instance opts out;
#          EC_FIREWALL_UNREACHABLE / EC_FIREWALL when the authority could not
#          confirm them open; EC_INVALID_ARG / EC_FILE_NOT_FOUND /
#          EC_INVALID_CONFIG on a malformed request.
function __logic_ensure_firewall_open() {
  local instance_config_file="$1"

  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Exposes instance_name / instance_ports / instance_enable_firewall_management.
  # shellcheck disable=SC1090
  __source_instance "$instance_config_file" || return $EC_FAILED_SOURCE

  if [[ "${instance_enable_firewall_management:-}" != "true" ]]; then
    return $EC_SUCCESS
  fi

  local _instance_name="${instance_name:-}"
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  local _tokens
  if ! _tokens=$(__firewall_ports_to_tokens "${instance_ports:-}"); then
    return $EC_ERROR
  fi

  if [[ -z "$_tokens" ]]; then
    return $EC_SUCCESS
  fi

  local -a _token_arr
  read -ra _token_arr <<< "$_tokens"
  __firewall_ensure_open "$_instance_name" "${_token_arr[@]}"
}

export -f __logic_ensure_firewall_open

# Disable firewall integration for an instance by asking the kgsm-firewall
# authority to remove every rule it owns for it. Deliberately best-effort
# (mirrors the old `ufw delete ... || true`): an unreachable authority or a
# backend error must NOT wedge uninstall, so the instance is always flipped to
# firewall-disabled and the remove outcome is reported up for the command layer
# to warn-and-continue on. The §7g hard-fail is scoped to enable/install only.
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_FIREWALL_DISABLED on a clean removal; EC_FIREWALL_UNREACHABLE /
#          EC_FIREWALL (soft — config still flipped) when the authority could not
#          confirm removal; EC_FAILED_UPDATE_CONFIG only on a genuine failure.
function __logic_disable_firewall_integration() {
  local instance_config_file="$1"

  # Validate input
  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  local _instance_name
  _instance_name=$(__get_config_value "$instance_config_file" "name" 2>/dev/null)

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Ask the authority to remove its rules (idempotent — a no-op is success).
  __firewall_remove "$_instance_name"
  local _remove_rc=$?

  # Flip the instance to disabled regardless of the remove outcome: the user's
  # intent is "stop managing this instance's firewall", and a lingering host
  # rule (authority down) must not block uninstall.
  if ! __add_or_update_config "$instance_config_file" "enable_firewall_management" "false"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  # Surface a soft remove failure (EC_FIREWALL_UNREACHABLE / EC_FIREWALL) so the
  # command layer can warn-and-continue; a clean removal returns the success
  # event code.
  if [[ $_remove_rc -ne $EC_SUCCESS ]]; then
    return $_remove_rc
  fi

  return $EC_SUCCESS_FIREWALL_DISABLED
}

export -f __logic_disable_firewall_integration

# Mark module as loaded
declare -g KGSM_LOGIC_FILES_FIREWALL_LOADED=1
export KGSM_LOGIC_FILES_FIREWALL_LOADED
