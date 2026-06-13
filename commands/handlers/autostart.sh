#!/usr/bin/env bash

# KGSM Pure Logic Layer - Boot Auto-start (enable/disable)
#
# Controls whether an instance is auto-started on boot, modeled on systemctl's
# enable/disable. This is the boot axis, INDEPENDENT of the runtime start/stop
# axis: enabling does not start the instance, disabling does not stop it.
#
# Auto-start is owned by the resident kgsm-watchdog daemon (its persisted
# desired-state set, restored on boot). It is the only boot-auto-start mechanism,
# so every verb here requires the daemon to be present and ready — callers gate on
# __watchdog_available and surface a clear message when it is not. No user-facing
# I/O — results are exit codes only.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_AUTOSTART_LOADED}" ]]; then
  return 0
fi

# Watchdog routing helpers (__watchdog_available, __watchdog_set_autostart,
# __watchdog_is_enabled, __watchdog_enabled_names).
if [[ -z "${KGSM_LOGIC_WATCHDOG_LOADED}" ]]; then
  # shellcheck source=watchdog.sh
  source "$(__find_command_handler watchdog.sh)" || return $EC_FAILED_SOURCE
fi

# Enable boot auto-start for an instance.
# Args: $1 = instance name
# Returns: EC_SUCCESS_AUTOSTART_ENABLED on success, error code on failure
function __logic_autostart_enable() {
  local _instance_name="$1"

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # The instance must exist (parity with `systemctl enable` refusing an unknown
  # unit) — fail with a clear local error before bothering the daemon.
  validate_instance_name "$_instance_name" > /dev/null 2>&1 || return $EC_INVALID_INSTANCE

  __watchdog_set_autostart enable "$_instance_name"
}

export -f __logic_autostart_enable

# Disable boot auto-start for an instance. Unlike enable, this does NOT require the
# instance to still exist — disabling is also how you prune a stale/removed entry.
# Args: $1 = instance name
# Returns: EC_SUCCESS_AUTOSTART_DISABLED on success, error code on failure
function __logic_autostart_disable() {
  local _instance_name="$1"

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  __watchdog_set_autostart disable "$_instance_name"
}

export -f __logic_autostart_disable

# Is an instance enabled for boot auto-start?
# Args: $1 = instance name
# Returns: 0 enabled, 1 not enabled, 2 daemon unreachable, EC_INVALID_ARG on bad args
function __logic_autostart_is_enabled() {
  local _instance_name="$1"

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  __watchdog_is_enabled "$_instance_name"
}

export -f __logic_autostart_is_enabled

# Echoes the names of all enabled (boot auto-start) instances, one per line.
# Returns: 0 on success, 2 if the daemon is unreachable.
function __logic_autostart_list() {
  __watchdog_enabled_names
}

export -f __logic_autostart_list

# Mark module as loaded
declare -g KGSM_LOGIC_AUTOSTART_LOADED=1
export KGSM_LOGIC_AUTOSTART_LOADED
