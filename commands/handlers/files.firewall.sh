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

# The firewall edges KGSM itself applied during the current invocation, one event
# name per line, oldest first.
#
# It exists because the two layers cannot talk any other way here: a handler never
# emits (that is the command layer's job), the exit-code channel already carries
# the lifecycle verb's own event, and one verb can cross both edges — a restart
# closes the ports and opens them again. So the handlers record what they applied
# and the command layer drains the record and audits it.
#
# Only edges KGSM owns are recorded. When the resident supervisor performs the
# bring-up it opens the same rule as it spawns and emits its own event, so a
# recorded edge there would audit one start twice.
declare -g KGSM_FIREWALL_APPLIED_EDGES=""
export KGSM_FIREWALL_APPLIED_EDGES

# Starts a fresh record for one command. Call before the lifecycle verb runs.
function __firewall_edges_reset() {
  KGSM_FIREWALL_APPLIED_EDGES=""
}

export -f __firewall_edges_reset

# Appends one applied edge.
# Args: $1 = event name (instance-ports-opened | instance-ports-closed)
function __firewall_edges_record() {
  KGSM_FIREWALL_APPLIED_EDGES+="${1}"$'\n'
}

export -f __firewall_edges_record

# Enable firewall integration for an instance: mark it as one whose ports KGSM
# manages. It opens nothing. An instance's ports are open exactly while it is
# running, so the rule is written on the bring-up that follows and removed on the
# stop — the same lifetime as its UPnP mapping, and for the same reason: a
# stopped server has no business holding an open port on the host.
#
# That makes this toggle a statement of intent, which is what every other
# consumer reads it as: the supervisor asks the authority to open the ports of an
# instance carrying it, and skips one that does not.
#
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

  # The name is what the authority tags a rule with, so a config that cannot
  # name itself cannot be managed — refuse rather than record an intent nothing
  # could act on.
  local _instance_name
  _instance_name=$(__get_config_value "$instance_config_file" "name" 2> /dev/null)

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Record that firewall management is on for this instance. The authority owns
  # the host rule (tagged kgsm-<instance>), so firewall_rule_file — the path of
  # the old kgsm-rendered ufw profile — is no longer written.
  if ! __add_or_update_config "$instance_config_file" "enable_firewall_management" "true"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS_FIREWALL_ENABLED
}

export -f __logic_enable_firewall_integration

# Open an instance's ports for the run that is starting. An instance's ports are
# open exactly while it is running, so this is the bring-up half of that lifetime
# and __logic_ensure_firewall_closed is the teardown half.
#
# Two things make it a no-op rather than a failure: an instance whose operator
# turned firewall management off (that is an explicit "stop managing this", and
# a start must not undo it), and an instance that declares no ports.
#
# Best-effort by design: the caller starts the server whatever this returns. A
# firewall authority that is down is a reason to warn, not a reason to refuse to
# run a game server.
#
# For a NATIVE instance under the resident supervisor this is belt-and-braces:
# kgsm-watchdog opens the same rule as it spawns, and it is the only thing that
# can, for the bring-ups kgsm never sees (boot auto-start, crash-respawn). This
# path is what covers a container instance and a host with no watchdog. Both are
# idempotent, so the overlap costs one round trip.
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_FIREWALL_PORTS_OPENED when the authority confirmed the rule
#          (the caller audits this edge); EC_SUCCESS when there was nothing to do
#          — the instance opts out of firewall management, or declares no ports;
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

  # Only a confirmed apply reports the edge. The authority is declarative — asked
  # for a non-empty port set it writes exactly that set — so success here means the
  # rule is owned and the ports are open, which is the fact the audit event states.
  __firewall_ensure_open "$_instance_name" "${_token_arr[@]}"
  local _rc=$?
  [[ $_rc -eq $EC_SUCCESS ]] && return $EC_SUCCESS_FIREWALL_PORTS_OPENED
  return $_rc
}

export -f __logic_ensure_firewall_open

# Release an instance's ports on a deliberate stop — the teardown half of
# __logic_ensure_firewall_open. A stopped server holds no open port on the host.
#
# Removal is addressed by the instance's ownership tag rather than by its ports,
# so it cleans up correctly even for an instance whose declared ports changed
# while it was running.
#
# Distinct from __logic_disable_firewall_integration despite both removing the
# rule: that one is the operator saying "stop managing this instance's firewall"
# and flips the toggle off. This one leaves the toggle alone — the instance is
# still managed, it is simply not running.
#
# Best-effort, and NOT applied to a crash: only this deliberate-stop path calls
# it, because a crash is followed by a restart that still needs the ports, and a
# process dying is not a reason to tear down host state.
# Args: $1 = instance_config_file
# Returns: EC_SUCCESS_FIREWALL_PORTS_CLOSED when the authority confirmed the
#          removal (the caller audits this edge); EC_SUCCESS when the instance opts
#          out of firewall management; EC_FIREWALL_UNREACHABLE / EC_FIREWALL when
#          the authority could not confirm the removal; EC_INVALID_ARG /
#          EC_FILE_NOT_FOUND / EC_INVALID_CONFIG on a malformed request.
function __logic_ensure_firewall_closed() {
  local instance_config_file="$1"

  if [[ -z "$instance_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Exposes instance_name / instance_enable_firewall_management.
  # shellcheck disable=SC1090
  __source_instance "$instance_config_file" || return $EC_FAILED_SOURCE

  if [[ "${instance_enable_firewall_management:-}" != "true" ]]; then
    return $EC_SUCCESS
  fi

  local _instance_name="${instance_name:-}"
  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_CONFIG
  fi

  # Removal is idempotent, so success covers "removed" and "there was nothing left
  # to remove" alike. Both leave the instance holding no open port, which is what
  # the close event records.
  __firewall_remove "$_instance_name"
  local _rc=$?
  [[ $_rc -eq $EC_SUCCESS ]] && return $EC_SUCCESS_FIREWALL_PORTS_CLOSED
  return $_rc
}

export -f __logic_ensure_firewall_closed

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
