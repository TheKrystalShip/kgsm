#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Disabling SC2016:
# jq syntax uses single quotes intentionally for variable interpolation
# shellcheck disable=SC2016

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

declare -g -r EVENT_INSTANCE_RESTART_STARTED="instance_restart_started"
export EVENT_INSTANCE_RESTART_STARTED

declare -g -r EVENT_INSTANCE_RESTART_FINISHED="instance_restart_finished"
export EVENT_INSTANCE_RESTART_FINISHED

# The restart's own halves. A restart runs the stop and the start through the pure logic rather than
# the stop and start commands, so neither of those commands' facts is emitted for it: without this,
# the whole shutdown — and the boot after it — is a silence a consumer can only paper over, and an
# instance whose process is dead still reads as running. This says the old run has ended; the new one
# coming up is instance_restarted. A step inside one operation, not a standalone stop, which is why
# it is its own type: instance_stopped is the fact an operator stopped a server, and a restart is not
# that.
declare -g -r EVENT_INSTANCE_RESTART_STOPPED="instance_restart_stopped"
export EVENT_INSTANCE_RESTART_STOPPED

declare -g -r EVENT_INSTANCE_STOP_STARTED="instance_stop_started"
export EVENT_INSTANCE_STOP_STARTED

declare -g -r EVENT_INSTANCE_STOP_FINISHED="instance_stop_finished"
export EVENT_INSTANCE_STOP_FINISHED

declare -g -r EVENT_INSTANCE_UPDATE_STARTED="instance_update_started"
export EVENT_INSTANCE_UPDATE_STARTED

declare -g -r EVENT_INSTANCE_UPDATE_FINISHED="instance_update_finished"
export EVENT_INSTANCE_UPDATE_FINISHED

declare -g -r EVENT_INSTANCE_UPDATED="instance_updated"
export EVENT_INSTANCE_UPDATED

declare -g -r EVENT_INSTANCE_VERSION_UPDATED="instance_version_updated"
export EVENT_INSTANCE_VERSION_UPDATED

# A newer game build exists upstream and this instance is not on it. Emitted by
# `instances check-update --emit` on the transition only: the version an event
# was emitted for is recorded beside the instance, so a sweep that finds the same
# version again says nothing. The applied side is EVENT_INSTANCE_VERSION_UPDATED,
# which is what clears it.
declare -g -r EVENT_INSTANCE_UPDATE_AVAILABLE="instance_update_available"
export EVENT_INSTANCE_UPDATE_AVAILABLE

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

# Backup-removal audit events. A backup is data, and its removal is the one
# backup operation with no undo — so both paths that destroy one say so.
#
# They are separate types because they answer different questions. A delete is
# an operator naming one snapshot and removing it; a prune is retention policy
# running, deleting whatever fell outside the keep window. A reader asking "who
# threw away that backup" must not have to infer intent from a count, and a
# reader auditing retention must not have to filter out hand-deletes.
#
# instance_backup_deleted carries `source` — the backup id, the same parameter
# name the created/restored events use for it. instance_backups_pruned carries
# counts rather than ids: it is one event for the whole sweep, and the ids it
# removed are exactly the ones no longer listed. `deleted` is what was actually
# removed (never what was attempted) and `kept` is the retention window it ran
# with, so the pair reads as a complete statement of what the policy did.
declare -g -r EVENT_INSTANCE_BACKUP_DELETED="instance_backup_deleted"
export EVENT_INSTANCE_BACKUP_DELETED

declare -g -r EVENT_INSTANCE_BACKUPS_PRUNED="instance_backups_pruned"
export EVENT_INSTANCE_BACKUPS_PRUNED

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

# Host-firewall audit events. An instance's ports are open exactly while it runs,
# so these mark that lifetime: opened on the bring-up, closed on the deliberate
# stop, and closed again when an operator drops firewall management (`files
# firewall disable`, which uninstall runs). A crash emits neither — the restart
# that follows still needs the ports.
#
# Emitted by whichever component performed the transition, exactly once. The
# kgsm-watchdog owns the edge for the native instances it supervises — including
# the boot auto-starts and crash-respawns KGSM never sees — and emits its own;
# KGSM emits for the bring-ups and teardowns it performs itself, which is what
# covers a container instance and a host with no supervisor. The C# path (kgsm-api
# via kgsm-lib) emits the same types with EmitWithProvenance.
#
# The `ports` parameter carries the instance's UFW-format spec; the payload renders
# it as the canonical structured array. Only a confirmed open/close emits — a down
# authority warns and emits nothing (never a fabricated outcome).
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

# A forward the router dropped on its own, put back by the watchdog's periodic
# sweep while the instance kept running. Its own type rather than a second
# instance_upnp_opened because the two answer different questions: an open
# accompanies a bring-up, whereas this one says the mapping went missing with
# nothing on this host asking for it — the only evidence a reader gets that the
# router discards mappings it accepted, and how often. A router may report a
# lease as infinite and drop it anyway, so the sweep compares what the IGD
# actually holds against what the running instances need; `ports` carries the
# subset that was missing, not the instance's whole set.
declare -g -r EVENT_INSTANCE_UPNP_REASSERTED="instance_upnp_reasserted"
export EVENT_INSTANCE_UPNP_REASSERTED

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

# Player-moderation audit events. Emitted by the command layer when an operator
# removes a player, blocks them, or lifts that block, and only on a successful
# send. They are their own types rather than a console-input record because the
# subject is a PLAYER, not a command: a consumer filtering "who was banned on
# this server" must not have to pattern-match command text to find out, and the
# same text could be typed by hand through `instances input` with no moderation
# intent behind it.
#
# `target` is the identity token the operator supplied — whichever kind the
# game's blueprint template declared ({ip}, {name} or {id}). KGSM carries it
# verbatim and does not classify it: the blueprint is where that meaning is
# declared, and re-deriving it here would be a second, drifting answer.
# `command` is the resolved console command that was actually delivered, so the
# trail records the literal effect alongside its subject.
declare -g -r EVENT_INSTANCE_PLAYER_KICKED="instance_player_kicked"
export EVENT_INSTANCE_PLAYER_KICKED

declare -g -r EVENT_INSTANCE_PLAYER_BANNED="instance_player_banned"
export EVENT_INSTANCE_PLAYER_BANNED

declare -g -r EVENT_INSTANCE_PLAYER_UNBANNED="instance_player_unbanned"
export EVENT_INSTANCE_PLAYER_UNBANNED

# Instance config-change audit event. Emitted by the command layer when a
# `.config.ini` key is set via `instances config-set`. Carries the instance name
# and the changed key ONLY — NEVER the value: instance config holds secrets
# (RCON/admin passwords, tokens), so the value must never reach a transport, log,
# or downstream audit. The downstream record is "key X changed on instance Y",
# nothing more.
declare -g -r EVENT_INSTANCE_CONFIG_CHANGED="instance_config_changed"
export EVENT_INSTANCE_CONFIG_CHANGED

# Console-input audit event. Emitted by the command layer when an arbitrary
# console command is delivered to a running instance via `instances input`.
# Carries the instance name and the verbatim command text. Unlike
# instance_config_changed (key only), the FULL command is carried on purpose —
# the trail's value is recording exactly what an operator ran (console commands
# are admin-level: ban/kick/op/...). A command can therefore contain a secret
# (e.g. an RCON login); the surface is operator-gated upstream and a consumer
# that must redact does so at its own boundary.
declare -g -r EVENT_INSTANCE_INPUT_SENT="instance_input_sent"
export EVENT_INSTANCE_INPUT_SENT

# Blueprint file events. The ONLY events in the system that are not
# instance-scoped: their subject is a blueprint, so their Data carries
# `BlueprintName` where every other event carries `InstanceName`. They exist so
# no consumer holds a stale blueprint — kgsm-api's catalog cache and the
# assistant's blueprint cache both refresh off them, and the edit lands in event
# history.
#
# Emitted by kgsm-lib (which owns the file write) through
# EmitWithProvenance, exactly as the watchdog emits its lifecycle events. Actor
# and origin are threaded from the human who made the edit, NOT hardcoded to
# system — a browser edit must be attributable to the admin who made it.
#
# `tier` is where the file lives (only ever `user`: the shipped system directory
# is read-only, an rsync target that a write would lose on the next deploy).
# `overrides_system` distinguishes a brand-new custom blueprint from one that now
# shadows a shipped blueprint of the same name — the state the catalog badge and
# the audit row need. `runtime` is nullable: a blueprint can be saved in a state
# the parser cannot read a runtime out of, and an unknown runtime is reported as
# null rather than guessed.
#
# The file CONTENT is never carried. A blueprint can hold credentials
# (steamcmd arguments, server passwords in an embedded compose), and an event
# payload fans out to every transport — the record is "blueprint X changed",
# nothing more. A consumer that needs the content reads the file.
declare -g -r EVENT_BLUEPRINT_CREATED="blueprint_created"
export EVENT_BLUEPRINT_CREATED

declare -g -r EVENT_BLUEPRINT_UPDATED="blueprint_updated"
export EVENT_BLUEPRINT_UPDATED

# `reverted_to_system` is the counterpart of `overrides_system`: true when
# deleting the user file uncovers a shipped blueprint that takes over again,
# false when the blueprint is gone from the host entirely.
declare -g -r EVENT_BLUEPRINT_REMOVED="blueprint_removed"
export EVENT_BLUEPRINT_REMOVED

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
  ["$EVENT_INSTANCE_RESTART_STARTED"]="instance"
  ["$EVENT_INSTANCE_RESTART_FINISHED"]="instance"
  ["$EVENT_INSTANCE_RESTART_STOPPED"]="instance"
  ["$EVENT_INSTANCE_STOP_STARTED"]="instance"
  ["$EVENT_INSTANCE_STOP_FINISHED"]="instance"
  ["$EVENT_INSTANCE_UPDATE_STARTED"]="instance"
  ["$EVENT_INSTANCE_UPDATE_FINISHED"]="instance"
  ["$EVENT_INSTANCE_UPDATED"]="instance"
  ["$EVENT_INSTANCE_VERSION_UPDATED"]="instance old_version new_version"
  ["$EVENT_INSTANCE_UPDATE_AVAILABLE"]="instance current_version latest_version"
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
  # `source` is the backup id, as in the two events above. No version: the
  # deleted backup's manifest is gone with it, and re-reading the instance's
  # current version would record a fact about the instance, not the backup.
  ["$EVENT_INSTANCE_BACKUP_DELETED"]="instance source"
  ["$EVENT_INSTANCE_BACKUPS_PRUNED"]="instance deleted kept"
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
  ["$EVENT_INSTANCE_UPNP_REASSERTED"]="instance ports"
  # Only `instance` is required — player_id/player_name are nullable and
  # validated/rendered out-of-band (see _build_event_payload).
  ["$EVENT_INSTANCE_PLAYER_JOINED"]="instance"
  ["$EVENT_INSTANCE_PLAYER_LEFT"]="instance"
  ["$EVENT_INSTANCE_PLAYER_KICKED"]="instance target command"
  ["$EVENT_INSTANCE_PLAYER_BANNED"]="instance target command"
  ["$EVENT_INSTANCE_PLAYER_UNBANNED"]="instance target command"
  # `key` only — NEVER the value (instance config holds secrets). The matching
  # case arm in _build_event_payload renders Data { InstanceName, Key }.
  ["$EVENT_INSTANCE_CONFIG_CHANGED"]="instance key"
  # `command` is the verbatim console command. The matching case arm in
  # _build_event_payload renders Data { InstanceName, Command }.
  ["$EVENT_INSTANCE_INPUT_SENT"]="instance command"
  # Blueprint-scoped, not instance-scoped: the first param is a blueprint name
  # and renders as Data.BlueprintName. `runtime` is NOT in the spec because it
  # is nullable — it is read positionally and rendered as JSON null when the
  # emitter could not determine it (see _build_event_payload).
  ["$EVENT_BLUEPRINT_CREATED"]="blueprint tier overrides_system"
  ["$EVENT_BLUEPRINT_UPDATED"]="blueprint tier overrides_system"
  ["$EVENT_BLUEPRINT_REMOVED"]="blueprint tier reverted_to_system"
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

# Build JSON event payload
# Args: $1 = event_type, $2... = parameters
# Returns: echoes JSON payload or returns error code
function __logic_build_event_payload() {
  local event_type="$1"
  shift
  local params=("$@")

  # Get required parameters specification
  local required_params=(${EVENT_CONFIGS[$event_type]})
  local param_names=()

  # Build parameter arrays for jq
  for i in "${!required_params[@]}"; do
    local param_name="${required_params[$i]}"
    local param_value="${params[$i]:-}"

    param_names+=("--arg" "$param_name" "$param_value")
  done

  # Resolve the actor (who triggered this event) for audit/correlation downstream.
  # KGSM is a stateless, multi-entrypoint CLI: it cannot itself know the semantic
  # principal, so the caller (bot/assistant/watchdog) supplies it via KGSM_EVENT_ACTOR.
  # For a bare CLI invocation that sets nothing, fall back to the OS user — an honest
  # "who ran this", never a fabricated identity.
  local actor="${KGSM_EVENT_ACTOR:-}"
  if [[ -z "$actor" ]]; then
    actor="${SUDO_USER:-${USER:-}}"
  fi
  if [[ -z "$actor" ]]; then
    actor="$(id -un 2>/dev/null || echo "system")"
  fi

  # Resolve the origin: the surface that drove this event
  # (ui|assistant|discord|system|api), the companion to the actor for downstream
  # audit/correlation. The caller (bot/assistant/watchdog/API) supplies it via
  # KGSM_EVENT_ORIGIN. Unlike the actor there is NO honest fallback — a bare CLI
  # invocation has no product surface — so an unset origin stays empty and is
  # emitted as JSON null below, never a fabricated surface.
  local origin="${KGSM_EVENT_ORIGIN:-}"

  # Generate JSON payload.
  #
  # The timestamp carries milliseconds. One appender gets ordering for free from
  # the file it writes, but the journal is read merged with every other
  # producer's, and second granularity orders arbitrarily inside each second —
  # which is exactly where causally adjacent events sit (a start and the port
  # opening that follows it land within one second routinely). `%3N` is GNU date;
  # KGSM is Linux-only, so that is a dependency it already has.
  local jq_args=("${param_names[@]}"
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
    --arg actor "$actor"
    --arg origin "$origin"
    --arg hostname "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "${HOSTNAME:-localhost}")"
    --arg producer_version "$KGSM_VERSION")

  # Build data object based on event type
  local data_object=""
  case "$event_type" in
    "$EVENT_INSTANCE_CREATED" | "$EVENT_INSTANCE_INSTALLATION_STARTED" | "$EVENT_INSTANCE_INSTALLATION_FINISHED" | "$EVENT_INSTANCE_INSTALLED")
      data_object='{
        InstanceName: $instance,
        Blueprint: $blueprint
      }'
      ;;
    "$EVENT_INSTANCE_VERSION_UPDATED")
      data_object='{
        InstanceName: $instance,
        OldVersion: $old_version,
        NewVersion: $new_version
      }'
      ;;
    "$EVENT_INSTANCE_UPDATE_AVAILABLE")
      data_object='{
        InstanceName: $instance,
        CurrentVersion: $current_version,
        LatestVersion: $latest_version
      }'
      ;;
    "$EVENT_INSTANCE_BACKUP_CREATED" | "$EVENT_INSTANCE_BACKUP_RESTORED")
      data_object='{
        InstanceName: $instance,
        Source: $source,
        Version: $version
      }'
      ;;
    "$EVENT_INSTANCE_BACKUP_DELETED")
      # `$source` binds because `source` is the 2nd EVENT_CONFIGS param name.
      data_object='{
        InstanceName: $instance,
        Source: $source
      }'
      ;;
    "$EVENT_INSTANCE_BACKUPS_PRUNED")
      # Counts, not ids — one event covers the whole sweep. Rendered as JSON
      # numbers rather than the strings --arg would produce, so a consumer can
      # sum them without re-parsing. Both are always supplied by the emitter
      # (a prune that removed nothing emits nothing at all), so neither is
      # null-coalesced.
      jq_args+=(--argjson deleted_n "${params[1]:-0}"
        --argjson kept_n "${params[2]:-0}")
      data_object='{
        InstanceName: $instance,
        Deleted: $deleted_n,
        Kept: $kept_n
      }'
      ;;
    "$EVENT_INSTANCE_STARTED" | "$EVENT_INSTANCE_STOPPED" | "$EVENT_INSTANCE_RESTARTED")
      data_object='{
        InstanceName: $instance
      }'
      ;;
    "$EVENT_INSTANCE_CONFIG_CHANGED")
      # Key only — the value is deliberately never carried (instance config holds
      # secrets like RCON/admin passwords). `$key` binds because `key` is the 2nd
      # EVENT_CONFIGS param name (rendered via --arg in the loop above).
      data_object='{
        InstanceName: $instance,
        Key: $key
      }'
      ;;
    "$EVENT_INSTANCE_INPUT_SENT")
      # The verbatim console command. Carried in full on purpose (unlike the
      # config-changed key-only rule) so the audit records exactly what was run.
      # `$command` binds because `command` is the 2nd EVENT_CONFIGS param name.
      data_object='{
        InstanceName: $instance,
        Command: $command
      }'
      ;;
    "$EVENT_INSTANCE_PLAYER_KICKED" | "$EVENT_INSTANCE_PLAYER_BANNED" | "$EVENT_INSTANCE_PLAYER_UNBANNED")
      # The moderated player and the command that carried it out. `$target` and
      # `$command` bind because `target`/`command` are the 2nd and 3rd
      # EVENT_CONFIGS param names. Both are required, so neither is
      # null-coalesced — the event type distinguishes kick from ban from unban.
      data_object='{
        InstanceName: $instance,
        Target: $target,
        Command: $command
      }'
      ;;
    "$EVENT_INSTANCE_CRASHED" | "$EVENT_INSTANCE_FAILED")
      data_object='{
        InstanceName: $instance,
        ExitCode: $exit_code,
        Restarts: $restarts
      }'
      ;;
    "$EVENT_INSTANCE_PORTS_OPENED" | "$EVENT_INSTANCE_PORTS_CLOSED" | "$EVENT_INSTANCE_UPNP_OPENED" | "$EVENT_INSTANCE_UPNP_CLOSED" | "$EVENT_INSTANCE_UPNP_REASSERTED")
      # The `ports` param is the UFW-format spec; surface it as the canonical
      # structured array [{start,end,protocol}] — the same shape `instances
      # info --json` emits — never the opaque UFW string. Converted here and
      # passed via --argjson (the one non-string Data field in this builder).
      # Shared by the firewall (instance_ports_*) and UPnP (instance_upnp_*)
      # events — all carry the same structured Ports payload; the event TYPE
      # distinguishes router NAT forward from host ufw rule downstream, and a
      # re-assert from a bring-up open.
      local ports_json
      ports_json="$(__ufw_ports_to_json "${params[1]:-}")" || ports_json="[]"
      jq_args+=(--argjson ports_json "$ports_json")
      data_object='{
        InstanceName: $instance,
        Ports: $ports_json
      }'
      ;;
    "$EVENT_INSTANCE_PLAYER_JOINED")
      # player_id/player_name/player_addr are NULLABLE and are NOT in the
      # EVENT_CONFIGS spec (only `instance` is required), so they are read
      # positionally here rather than through param_names. An absent/empty
      # value renders as JSON null — the same honest-null rule used for
      # Origin — never an empty string posing as a real id/name/addr. The
      # at-least-one-non-null guarantee belongs to the emitting shim, not to
      # KGSM (a faithful emitter). session_key is the watchdog's per-session
      # correlation token and is ALWAYS a non-empty string — never
      # null-coalesced like the others.
      jq_args+=(--arg player_id "${params[1]:-}"
        --arg player_name "${params[2]:-}"
        --arg player_addr "${params[3]:-}"
        --arg session_key "${params[4]:-}")
      data_object='{
        InstanceName: $instance,
        PlayerId: ($player_id | if . == "" then null else . end),
        PlayerName: ($player_name | if . == "" then null else . end),
        PlayerAddr: ($player_addr | if . == "" then null else . end),
        SessionKey: $session_key
      }'
      ;;
    "$EVENT_INSTANCE_PLAYER_LEFT")
      # Same nullable/positional rules as the joined case above, plus `reason`
      # (left-only): the disconnect reason the game logged, honest-null when
      # the game's quit path doesn't log one.
      jq_args+=(--arg player_id "${params[1]:-}"
        --arg player_name "${params[2]:-}"
        --arg player_addr "${params[3]:-}"
        --arg session_key "${params[4]:-}"
        --arg reason "${params[5]:-}")
      data_object='{
        InstanceName: $instance,
        PlayerId: ($player_id | if . == "" then null else . end),
        PlayerName: ($player_name | if . == "" then null else . end),
        PlayerAddr: ($player_addr | if . == "" then null else . end),
        SessionKey: $session_key,
        Reason: ($reason | if . == "" then null else . end)
      }'
      ;;
    "$EVENT_BLUEPRINT_CREATED" | "$EVENT_BLUEPRINT_UPDATED")
      # The only Data shape keyed on a blueprint instead of an instance: the
      # subject is a file in the blueprint catalog, and no instance is involved.
      # `$blueprint`/`$tier`/`$overrides_system` bind from the EVENT_CONFIGS
      # spec; `runtime` is read positionally because it is nullable — a
      # blueprint can be saved in a state the parser cannot read a runtime out
      # of, and an unknown runtime renders as JSON null rather than a guess.
      # OverridesSystem is a real JSON boolean, not the string "true": anything
      # other than true/false is a value the emitter could not determine, so it
      # renders null on the same honest-null rule.
      jq_args+=(--arg runtime "${params[3]:-}")
      data_object='{
        BlueprintName: $blueprint,
        Tier: $tier,
        OverridesSystem: ($overrides_system | if . == "true" then true elif . == "false" then false else null end),
        Runtime: ($runtime | if . == "" then null else . end)
      }'
      ;;
    "$EVENT_BLUEPRINT_REMOVED")
      # No Runtime: the file is gone, so its runtime is no longer a fact this
      # event can state. RevertedToSystem follows the same boolean/honest-null
      # rule as OverridesSystem above — true when deleting the user file
      # uncovers a shipped blueprint that takes over, false when the blueprint
      # leaves the host entirely.
      data_object='{
        BlueprintName: $blueprint,
        Tier: $tier,
        RevertedToSystem: ($reverted_to_system | if . == "true" then true elif . == "false" then false else null end)
      }'
      ;;
    *)
      data_object='{
        InstanceName: $instance
      }'
      ;;
  esac

  local payload
  # -c keeps the payload on ONE line: the journal is newline-delimited JSON and
  # every consumer's cursor is a byte offset into it, so a pretty-printed
  # payload would break the one-event-per-line contract readers depend on.
  if ! payload=$(jq -c -n "${jq_args[@]}" "{
    V: 1,
    EventType: \"$event_type\",
    Data: $data_object,
    Timestamp: \$timestamp,
    Actor: \$actor,
    Origin: (\$origin | if . == \"\" then null else . end),
    Hostname: \$hostname,
    ProducerVersion: \$producer_version
  }"); then
    return $EC_EVENT_JSON_FAILED
  fi

  echo "$payload"
  return $EC_SUCCESS
}

export -f __logic_build_event_payload
# ---------------------------------------------------------------------------
# Journal
#
# The event journal is the durable transport: KGSM appends one JSON line per
# event to a date-named segment and knows nothing about who reads it.
# Consumers tail the segments at their own pace holding their own cursor, so
# adding or removing a consumer needs no engine configuration.
#
# Emission is unconditional. The journal is the audit record, so there is no
# switch that turns it off — a silently disabled audit trail is indisputably
# worse than a noisy one.
# ---------------------------------------------------------------------------

# Default journal directory when config supplies none.
declare -g -r KGSM_DEFAULT_EVENT_JOURNAL_DIR="/var/lib/kgsm/events"
export KGSM_DEFAULT_EVENT_JOURNAL_DIR

# Resolves the journal directory.
# Returns: EC_SUCCESS and echoes the directory path, always.
function __logic_journal_dir() {
  # shellcheck disable=SC2154
  if [[ -n "${config_event_journal_dir:-}" ]]; then
    echo "${config_event_journal_dir/#\~/$HOME}"
  else
    echo "$KGSM_DEFAULT_EVENT_JOURNAL_DIR"
  fi

  return $EC_SUCCESS
}

export -f __logic_journal_dir

# Resolves the path of the segment the current UTC day writes to.
# Segments are date-named so rotation needs no writer coordination and
# filenames sort lexically in chronological order.
# Returns: EC_SUCCESS and echoes the segment path, always.
function __logic_journal_segment() {
  local _dir
  _dir="$(__logic_journal_dir)"

  echo "${_dir}/$(date -u +%Y-%m-%d).ndjson"
  return $EC_SUCCESS
}

export -f __logic_journal_segment

# Appends one event payload to the journal.
#
# The payload is written as a single line by a single printf: O_APPEND makes
# one sub-PIPE_BUF write atomic, so concurrent KGSM invocations interleave
# whole lines and never partial ones. No locking is needed or wanted.
#
# A payload spanning multiple lines would break the one-event-per-line
# contract every consumer's cursor depends on, so it is rejected rather than
# written malformed — never emit data a reader cannot trust.
#
# Args: $1 = payload (single-line JSON string)
# Returns: EC_SUCCESS, EC_MISSING_ARG, or EC_EVENT_JOURNAL_FAILED
function __logic_journal_append() {
  local payload="$1"

  if [[ -z "$payload" ]]; then
    return $EC_MISSING_ARG
  fi

  if [[ "$payload" == *$'\n'* ]]; then
    return $EC_EVENT_JOURNAL_FAILED
  fi

  local _dir
  _dir="$(__logic_journal_dir)"

  if [[ ! -d "$_dir" ]] && ! mkdir -p "$_dir" 2>/dev/null; then
    return $EC_EVENT_JOURNAL_FAILED
  fi

  local _segment
  _segment="$(__logic_journal_segment)"

  if ! printf '%s\n' "$payload" >> "$_segment" 2>/dev/null; then
    return $EC_EVENT_JOURNAL_FAILED
  fi

  return $EC_SUCCESS
}

export -f __logic_journal_append

# Emits one event: validate, build the payload, append it to the journal, then
# hand the same payload to any optional transport that is switched on.
#
# The journal append is the emission — its failure is the function's failure.
# Optional transports are best-effort by design: a webhook endpoint being down
# is that endpoint's problem, never a reason to fail the operation that emitted
# the event.
#
# This is the single emit implementation. `events.sh emit` and the exit-code
# dispatch in core/events.sh both route here, so the wire format has exactly
# one definition.
#
# Args: $1 = event_name (dash- or underscore-separated), $2... = parameters
# Returns: EC_SUCCESS, or the failing stage's code
function __logic_emit_event() {
  local event_name="$1"
  shift
  local params=("$@")

  if [[ -z "$event_name" ]]; then
    return $EC_MISSING_ARG
  fi

  local event_type
  if ! event_type=$(__logic_event_name_to_type "$event_name"); then
    return $EC_EVENT_TYPE_INVALID
  fi

  if ! __logic_validate_event_params "$event_type" "${params[@]}"; then
    return $EC_EVENT_PARAMS_INVALID
  fi

  local payload
  if ! payload=$(__logic_build_event_payload "$event_type" "${params[@]}"); then
    return $EC_EVENT_JSON_FAILED
  fi

  if ! __logic_journal_append "$payload"; then
    return $EC_EVENT_JOURNAL_FAILED
  fi

  # shellcheck disable=SC2154
  if [[ "${config_enable_webhook_events:-false}" == "true" ]]; then
    events.webhook.sh emit "$payload" &
  fi

  wait

  return $EC_SUCCESS
}

export -f __logic_emit_event

# Mark module as loaded
declare -g KGSM_LOGIC_EVENTS_LOADED=1
export KGSM_LOGIC_EVENTS_LOADED
