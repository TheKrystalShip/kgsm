#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# KGSM Events Logic Library
#
# This module provides pure logic functions for event validation and management.
# No user-facing I/O (no __print_* functions).
# Returns meaningful exit codes for all operations.

# Guard against multiple sourcing
if [[ -n "${KGSM_LOGIC_EVENTS_LOADED:-}" ]]; then
  return 0
fi

# Event type constants
declare -g -r EVENT_INSTANCE_CREATED="instance_created"
export EVENT_INSTANCE_CREATED

declare -g -r EVENT_INSTANCE_DIRECTORIES_CREATED="instance_directories_created"
export EVENT_INSTANCE_DIRECTORIES_CREATED

declare -g -r EVENT_INSTANCE_FILES_CREATED="instance_files_created"
export EVENT_INSTANCE_FILES_CREATED

declare -g -r EVENT_INSTANCE_DOWNLOAD_STARTED="instance_download_started"
export EVENT_INSTANCE_DOWNLOAD_STARTED

declare -g -r EVENT_INSTANCE_DOWNLOAD_FINISHED="instance_download_finished"
export EVENT_INSTANCE_DOWNLOAD_FINISHED

declare -g -r EVENT_INSTANCE_DOWNLOAD_FAILED="instance_download_failed"
export EVENT_INSTANCE_DOWNLOAD_FAILED

declare -g -r EVENT_INSTANCE_DOWNLOADED="instance_downloaded"
export EVENT_INSTANCE_DOWNLOADED

declare -g -r EVENT_INSTANCE_DEPLOY_STARTED="instance_deploy_started"
export EVENT_INSTANCE_DEPLOY_STARTED

declare -g -r EVENT_INSTANCE_DEPLOY_FINISHED="instance_deploy_finished"
export EVENT_INSTANCE_DEPLOY_FINISHED

declare -g -r EVENT_INSTANCE_DEPLOY_FAILED="instance_deploy_failed"
export EVENT_INSTANCE_DEPLOY_FAILED

declare -g -r EVENT_INSTANCE_DEPLOYED="instance_deployed"
export EVENT_INSTANCE_DEPLOYED

declare -g -r EVENT_INSTANCE_UPDATE_STARTED="instance_update_started"
export EVENT_INSTANCE_UPDATE_STARTED

declare -g -r EVENT_INSTANCE_UPDATE_FINISHED="instance_update_finished"
export EVENT_INSTANCE_UPDATE_FINISHED

declare -g -r EVENT_INSTANCE_UPDATED="instance_updated"
export EVENT_INSTANCE_UPDATED

declare -g -r EVENT_INSTANCE_VERSION_UPDATED="instance_version_updated"
export EVENT_INSTANCE_VERSION_UPDATED

declare -g -r EVENT_INSTANCE_INSTALLATION_STARTED="instance_installation_started"
export EVENT_INSTANCE_INSTALLATION_STARTED

declare -g -r EVENT_INSTANCE_INSTALLATION_FINISHED="instance_installation_finished"
export EVENT_INSTANCE_INSTALLATION_FINISHED

declare -g -r EVENT_INSTANCE_INSTALLED="instance_installed"
export EVENT_INSTANCE_INSTALLED

declare -g -r EVENT_INSTANCE_STARTED="instance_started"
export EVENT_INSTANCE_STARTED

declare -g -r EVENT_INSTANCE_STOPPED="instance_stopped"
export EVENT_INSTANCE_STOPPED

declare -g -r EVENT_INSTANCE_RESTARTED="instance_restarted"
export EVENT_INSTANCE_RESTARTED

# Autonomous supervisor (kgsm-watchdog) lifecycle events. Emitted by the daemon
# (via kgsm-lib EmitWithProvenance, stamped actor=system/origin=system), never from
# a kgsm exit-code dispatch — the watchdog is the only component that observes a
# crash. instance_crashed: a desired-running process died and is being auto-restarted.
# instance_failed: the supervisor exhausted its restart retries and gave up.
declare -g -r EVENT_INSTANCE_CRASHED="instance_crashed"
export EVENT_INSTANCE_CRASHED

declare -g -r EVENT_INSTANCE_FAILED="instance_failed"
export EVENT_INSTANCE_FAILED

declare -g -r EVENT_INSTANCE_READY="instance_ready"
export EVENT_INSTANCE_READY

declare -g -r EVENT_INSTANCE_BACKUP_CREATED="instance_backup_created"
export EVENT_INSTANCE_BACKUP_CREATED

declare -g -r EVENT_INSTANCE_BACKUP_RESTORED="instance_backup_restored"
export EVENT_INSTANCE_BACKUP_RESTORED

declare -g -r EVENT_INSTANCE_FILES_REMOVED="instance_files_removed"
export EVENT_INSTANCE_FILES_REMOVED

declare -g -r EVENT_INSTANCE_DIRECTORIES_REMOVED="instance_directories_removed"
export EVENT_INSTANCE_DIRECTORIES_REMOVED

declare -g -r EVENT_INSTANCE_REMOVED="instance_removed"
export EVENT_INSTANCE_REMOVED

declare -g -r EVENT_INSTANCE_UNINSTALL_STARTED="instance_uninstall_started"
export EVENT_INSTANCE_UNINSTALL_STARTED

declare -g -r EVENT_INSTANCE_UNINSTALL_FINISHED="instance_uninstall_finished"
export EVENT_INSTANCE_UNINSTALL_FINISHED

declare -g -r EVENT_INSTANCE_UNINSTALL_FAILED="instance_uninstall_failed"
export EVENT_INSTANCE_UNINSTALL_FAILED

declare -g -r EVENT_INSTANCE_UNINSTALLED="instance_uninstalled"
export EVENT_INSTANCE_UNINSTALLED

# Host-firewall audit events. Emitted when kgsm asks the kgsm-firewall authority
# to open/close an instance's ports (firewall enable/disable, and install/
# uninstall). The `ports` parameter carries the instance's UFW-format spec; the
# payload renders it as the canonical structured array. Only a confirmed
# open/close emits — a down authority warns and emits nothing (never a
# fabricated outcome). The C# path (kgsm-api via kgsm-lib) emits the same types
# with EmitWithProvenance once it consumes them.
declare -g -r EVENT_INSTANCE_PORTS_OPENED="instance_ports_opened"
export EVENT_INSTANCE_PORTS_OPENED

declare -g -r EVENT_INSTANCE_PORTS_CLOSED="instance_ports_closed"
export EVENT_INSTANCE_PORTS_CLOSED

# UPnP port-forwarding audit events. Emitted by the kgsm-watchdog (the resident
# supervisor owns UPnP because it is process-lifetime state) when it opens/closes
# an instance's port mappings on the local router (IGD) via upnpc — origin=system,
# actor=system, an autonomous daemon action. DISTINCT from the firewall
# instance_ports_* events above: a router NAT forward is a different fact from a
# host ufw rule (a host can have one without the other), so they carry separate
# event types and separate downstream audit actions. The `ports` parameter is the
# UFW-format spec; the payload renders it as the canonical structured array (same
# as the firewall events). Only a confirmed upnpc-exit-0 transition emits — never
# a fabricated outcome.
declare -g -r EVENT_INSTANCE_UPNP_OPENED="instance_upnp_opened"
export EVENT_INSTANCE_UPNP_OPENED

declare -g -r EVENT_INSTANCE_UPNP_CLOSED="instance_upnp_closed"
export EVENT_INSTANCE_UPNP_CLOSED

# Player-presence events. Emitted on behalf of a running game server when a
# player joins or leaves. For our container images these are forwarded by the
# kgsm-watchdog, which tails the in-container event channel and re-emits via
# kgsm-lib (origin=system, actor=null — an autonomous observation). Only the
# `instance` param is required in EVENT_CONFIGS: `player_id` and `player_name`
# are NULLABLE (a source may give only one) and are handled out-of-band in
# _build_event_payload, where an empty value renders as JSON null — never an
# empty string masquerading as a real value. KGSM never fabricates the missing
# half (the at-least-one-non-null guarantee is the emitting shim's job).
declare -g -r EVENT_INSTANCE_PLAYER_JOINED="instance_player_joined"
export EVENT_INSTANCE_PLAYER_JOINED

declare -g -r EVENT_INSTANCE_PLAYER_LEFT="instance_player_left"
export EVENT_INSTANCE_PLAYER_LEFT

# Instance config-change audit event. Emitted by the command layer when a
# `.config.ini` key is set via `instances config-set`. Carries the instance name
# and the changed key ONLY — NEVER the value: instance config holds secrets
# (RCON/admin passwords, tokens), so the value must never reach a transport, log,
# or downstream audit. The downstream record is "key X changed on instance Y",
# nothing more.
declare -g -r EVENT_INSTANCE_CONFIG_CHANGED="instance_config_changed"
export EVENT_INSTANCE_CONFIG_CHANGED

# Event parameter specifications
declare -g -A EVENT_CONFIGS=(
  ["$EVENT_INSTANCE_CREATED"]="instance blueprint"
  ["$EVENT_INSTANCE_DIRECTORIES_CREATED"]="instance"
  ["$EVENT_INSTANCE_FILES_CREATED"]="instance"
  ["$EVENT_INSTANCE_DOWNLOAD_STARTED"]="instance"
  ["$EVENT_INSTANCE_DOWNLOAD_FINISHED"]="instance"
  ["$EVENT_INSTANCE_DOWNLOAD_FAILED"]="instance"
  ["$EVENT_INSTANCE_DOWNLOADED"]="instance"
  ["$EVENT_INSTANCE_DEPLOY_STARTED"]="instance"
  ["$EVENT_INSTANCE_DEPLOY_FINISHED"]="instance"
  ["$EVENT_INSTANCE_DEPLOY_FAILED"]="instance"
  ["$EVENT_INSTANCE_DEPLOYED"]="instance"
  ["$EVENT_INSTANCE_UPDATE_STARTED"]="instance"
  ["$EVENT_INSTANCE_UPDATE_FINISHED"]="instance"
  ["$EVENT_INSTANCE_UPDATED"]="instance"
  ["$EVENT_INSTANCE_VERSION_UPDATED"]="instance old_version new_version"
  ["$EVENT_INSTANCE_INSTALLATION_STARTED"]="instance blueprint"
  ["$EVENT_INSTANCE_INSTALLATION_FINISHED"]="instance blueprint"
  ["$EVENT_INSTANCE_INSTALLED"]="instance blueprint"
  ["$EVENT_INSTANCE_STARTED"]="instance"
  ["$EVENT_INSTANCE_STOPPED"]="instance"
  ["$EVENT_INSTANCE_RESTARTED"]="instance"
  ["$EVENT_INSTANCE_CRASHED"]="instance exit_code restarts"
  ["$EVENT_INSTANCE_FAILED"]="instance exit_code restarts"
  ["$EVENT_INSTANCE_READY"]="instance"
  ["$EVENT_INSTANCE_BACKUP_CREATED"]="instance source version"
  ["$EVENT_INSTANCE_BACKUP_RESTORED"]="instance source version"
  ["$EVENT_INSTANCE_FILES_REMOVED"]="instance"
  ["$EVENT_INSTANCE_DIRECTORIES_REMOVED"]="instance"
  ["$EVENT_INSTANCE_REMOVED"]="instance"
  ["$EVENT_INSTANCE_UNINSTALL_STARTED"]="instance"
  ["$EVENT_INSTANCE_UNINSTALL_FINISHED"]="instance"
  ["$EVENT_INSTANCE_UNINSTALL_FAILED"]="instance"
  ["$EVENT_INSTANCE_UNINSTALLED"]="instance"
  ["$EVENT_INSTANCE_PORTS_OPENED"]="instance ports"
  ["$EVENT_INSTANCE_PORTS_CLOSED"]="instance ports"
  ["$EVENT_INSTANCE_UPNP_OPENED"]="instance ports"
  ["$EVENT_INSTANCE_UPNP_CLOSED"]="instance ports"
  # Only `instance` is required — player_id/player_name are nullable and
  # validated/rendered out-of-band (see _build_event_payload).
  ["$EVENT_INSTANCE_PLAYER_JOINED"]="instance"
  ["$EVENT_INSTANCE_PLAYER_LEFT"]="instance"
  # `key` only — NEVER the value (instance config holds secrets). The matching
  # case arm in _build_event_payload renders Data { InstanceName, Key }.
  ["$EVENT_INSTANCE_CONFIG_CHANGED"]="instance key"
)

# Validates that an event type is supported
# Args: $1 = event_type (e.g., "instance_created")
# Returns: EC_SUCCESS if valid, EC_EVENT_TYPE_INVALID if not
function __logic_validate_event_type() {
  local event_type="$1"

  if [[ -z "$event_type" ]]; then
    return $EC_EVENT_TYPE_INVALID
  fi

  # Check if event type exists in configuration
  if [[ -z "${EVENT_CONFIGS[$event_type]}" ]]; then
    return $EC_EVENT_TYPE_INVALID
  fi

  return $EC_SUCCESS
}

export -f __logic_validate_event_type

# Validates event parameters match the required specification
# Args: $1 = event_type, $2... = parameters
# Returns: EC_SUCCESS if valid, EC_EVENT_PARAMS_INVALID if not
function __logic_validate_event_params() {
  local event_type="$1"
  shift
  local params=("$@")

  # Validate event type first
  if ! __logic_validate_event_type "$event_type"; then
    return $EC_EVENT_TYPE_INVALID
  fi

  # Get required parameters
  local required_params=(${EVENT_CONFIGS[$event_type]})

  # Validate parameter count
  if [[ ${#params[@]} -lt ${#required_params[@]} ]]; then
    return $EC_EVENT_PARAMS_INVALID
  fi

  # Validate each required parameter is non-empty
  for i in "${!required_params[@]}"; do
    local param_value="${params[$i]}"
    if [[ -z "$param_value" ]]; then
      return $EC_EVENT_PARAMS_INVALID
    fi
  done

  return $EC_SUCCESS
}

export -f __logic_validate_event_params

# Returns the parameter specification for an event type
# Args: $1 = event_type
# Returns: EC_SUCCESS and echoes param spec (space-separated), or EC_EVENT_TYPE_INVALID
function __logic_get_event_param_spec() {
  local event_type="$1"

  # Validate event type first
  if ! __logic_validate_event_type "$event_type"; then
    return $EC_EVENT_TYPE_INVALID
  fi

  echo "${EVENT_CONFIGS[$event_type]}"
  return $EC_SUCCESS
}

export -f __logic_get_event_param_spec

# Converts dash-separated event name to underscore constant
# Args: $1 = event_name (e.g., "instance-created")
# Returns: EC_SUCCESS and echoes constant name (e.g., "instance_created"), or EC_EVENT_TYPE_INVALID
function __logic_event_name_to_type() {
  local event_name="$1"

  if [[ -z "$event_name" ]]; then
    return $EC_EVENT_TYPE_INVALID
  fi

  # Convert dashes to underscores
  local event_type="${event_name//-/_}"

  # Validate the resulting type exists
  if ! __logic_validate_event_type "$event_type"; then
    return $EC_EVENT_TYPE_INVALID
  fi

  echo "$event_type"
  return $EC_SUCCESS
}

export -f __logic_event_name_to_type

# Mark module as loaded
declare -g KGSM_LOGIC_EVENTS_LOADED=1
export KGSM_LOGIC_EVENTS_LOADED
