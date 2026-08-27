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

# Guard against multiple sourcing.
#
# The flag is exported and EVENT_CONFIGS cannot be: bash exports strings, never
# associative arrays. So a CHILD process inherits "already loaded" without the
# table that claim refers to, and every event type it tries to emit is rejected
# as invalid — silently, because the emitters are best-effort. That is one
# process deep in a chain: the first module to load the handler emits fine and
# anything it shells out to does not, which is why an event emitted from a
# delegated module (`files.sh remove`, a management script reporting its own
# phases) stopped appearing without anything looking broken.
#
# The table's presence is therefore the real test of whether this module is
# loaded; the flag alone only says some process once loaded it. Re-sourcing in a
# child is safe — the readonly constants arrive there as ordinary inherited
# variables, since readonly does not survive an exec.
if [[ -n "${KGSM_LOGIC_EVENTS_LOADED:-}" ]] && [[ "${#EVENT_CONFIGS[@]}" -gt 0 ]]; then
  return 0
fi

# Event type constants
declare -g -r EVENT_INSTANCE_CREATED="server.install.created"
export EVENT_INSTANCE_CREATED

declare -g -r EVENT_INSTANCE_DIRECTORIES_CREATED="server.install.directories_created"
export EVENT_INSTANCE_DIRECTORIES_CREATED

declare -g -r EVENT_INSTANCE_FILES_CREATED="server.install.files_created"
export EVENT_INSTANCE_FILES_CREATED

declare -g -r EVENT_INSTANCE_DOWNLOAD_STARTED="server.download.started"
export EVENT_INSTANCE_DOWNLOAD_STARTED

declare -g -r EVENT_INSTANCE_DOWNLOAD_FINISHED="server.download.finished"
export EVENT_INSTANCE_DOWNLOAD_FINISHED

declare -g -r EVENT_INSTANCE_DOWNLOAD_FAILED="server.download.failed"
export EVENT_INSTANCE_DOWNLOAD_FAILED

declare -g -r EVENT_INSTANCE_DOWNLOADED="server.download.completed"
export EVENT_INSTANCE_DOWNLOADED

declare -g -r EVENT_INSTANCE_DEPLOY_STARTED="server.deploy.started"
export EVENT_INSTANCE_DEPLOY_STARTED

declare -g -r EVENT_INSTANCE_DEPLOY_FINISHED="server.deploy.finished"
export EVENT_INSTANCE_DEPLOY_FINISHED

declare -g -r EVENT_INSTANCE_DEPLOY_FAILED="server.deploy.failed"
export EVENT_INSTANCE_DEPLOY_FAILED

declare -g -r EVENT_INSTANCE_DEPLOYED="server.deploy.completed"
export EVENT_INSTANCE_DEPLOYED

declare -g -r EVENT_INSTANCE_RESTART_STARTED="server.restart.started"
export EVENT_INSTANCE_RESTART_STARTED

declare -g -r EVENT_INSTANCE_RESTART_FINISHED="server.restart.finished"
export EVENT_INSTANCE_RESTART_FINISHED

# The restart's own halves. A restart runs the stop and the start through the pure logic rather than
# the stop and start commands, so neither of those commands' facts is emitted for it: without this,
# the whole shutdown — and the boot after it — is a silence a consumer can only paper over, and an
# instance whose process is dead still reads as running. This says the old run has ended; the new one
# coming up is server.restarted. A step inside one operation, not a standalone stop, which is why
# it is its own type: server.stopped is the fact an operator stopped a server, and a restart is not
# that.
declare -g -r EVENT_INSTANCE_RESTART_STOPPED="server.restart.stopped"
export EVENT_INSTANCE_RESTART_STOPPED

declare -g -r EVENT_INSTANCE_STOP_STARTED="server.stop.started"
export EVENT_INSTANCE_STOP_STARTED

declare -g -r EVENT_INSTANCE_STOP_FINISHED="server.stop.finished"
export EVENT_INSTANCE_STOP_FINISHED

declare -g -r EVENT_INSTANCE_UPDATE_STARTED="server.update.started"
export EVENT_INSTANCE_UPDATE_STARTED

declare -g -r EVENT_INSTANCE_UPDATE_FINISHED="server.update.finished"
export EVENT_INSTANCE_UPDATE_FINISHED

# The outcome an update run has when the version did not move and that is NOT the good news. An
# update ends without a version change in two ways — it found nothing to do, or it could not do it —
# and the bracket cannot tell them apart, so a consumer settling the run on it reports a refusal as a
# completed update. This is the fact that separates them.
declare -g -r EVENT_INSTANCE_UPDATE_FAILED="server.update.failed"
export EVENT_INSTANCE_UPDATE_FAILED

declare -g -r EVENT_INSTANCE_UPDATED="server.update.completed"
export EVENT_INSTANCE_UPDATED

declare -g -r EVENT_INSTANCE_VERSION_UPDATED="server.updated"
export EVENT_INSTANCE_VERSION_UPDATED

# A newer game build exists upstream and this instance is not on it. Emitted by
# `instances check-update --emit` on the transition only: the version an event
# was emitted for is recorded beside the instance, so a sweep that finds the same
# version again says nothing. The applied side is EVENT_INSTANCE_VERSION_UPDATED,
# which is what clears it.
declare -g -r EVENT_INSTANCE_UPDATE_AVAILABLE="server.update.available"
export EVENT_INSTANCE_UPDATE_AVAILABLE

declare -g -r EVENT_INSTANCE_INSTALLATION_STARTED="server.install.started"
export EVENT_INSTANCE_INSTALLATION_STARTED

declare -g -r EVENT_INSTANCE_INSTALLATION_FINISHED="server.install.finished"
export EVENT_INSTANCE_INSTALLATION_FINISHED

declare -g -r EVENT_INSTANCE_INSTALLED="server.installed"
export EVENT_INSTANCE_INSTALLED

# An instance's files now live in a different library. Carries the library it
# came from and the one it is in, because a reader that learns only the
# destination cannot tell which disk just got its space back — and draining a
# disk before it is unplugged is the whole reason the verb exists.
declare -g -r EVENT_INSTANCE_MOVED="server.moved"
export EVENT_INSTANCE_MOVED

declare -g -r EVENT_INSTANCE_STARTED="server.started"
export EVENT_INSTANCE_STARTED

declare -g -r EVENT_INSTANCE_STOPPED="server.stopped"
export EVENT_INSTANCE_STOPPED

declare -g -r EVENT_INSTANCE_RESTARTED="server.restarted"
export EVENT_INSTANCE_RESTARTED

# Autonomous supervisor (kgsm-watchdog) lifecycle events. Emitted by the daemon
# (via kgsm-lib EmitWithProvenance, stamped actor=system/origin=system), never from
# a kgsm exit-code dispatch — the watchdog is the only component that observes a
# crash. server.crashed: a desired-running process died and is being auto-restarted.
# server.crash.exhausted: the supervisor exhausted its restart retries and gave up.
declare -g -r EVENT_INSTANCE_CRASHED="server.crashed"
export EVENT_INSTANCE_CRASHED

declare -g -r EVENT_INSTANCE_FAILED="server.crash.exhausted"
export EVENT_INSTANCE_FAILED

declare -g -r EVENT_INSTANCE_READY="server.ready"
export EVENT_INSTANCE_READY

# Both backup verbs run for as long as the archiving takes — minutes on a large world — and a
# scheduler drives them with nobody watching. These bracket each run so a surface can show the
# instance as busy while it happens, the same way the lifecycle verbs are bracketed. Finished is
# emitted on every outcome: it says the run ENDED, while backup.created says an archive
# exists.
declare -g -r EVENT_INSTANCE_BACKUP_STARTED="backup.started"
export EVENT_INSTANCE_BACKUP_STARTED

declare -g -r EVENT_INSTANCE_BACKUP_FINISHED="backup.finished"
export EVENT_INSTANCE_BACKUP_FINISHED

declare -g -r EVENT_INSTANCE_RESTORE_STARTED="backup.restore.started"
export EVENT_INSTANCE_RESTORE_STARTED

declare -g -r EVENT_INSTANCE_RESTORE_FINISHED="backup.restore.finished"
export EVENT_INSTANCE_RESTORE_FINISHED

declare -g -r EVENT_INSTANCE_BACKUP_CREATED="backup.created"
export EVENT_INSTANCE_BACKUP_CREATED

declare -g -r EVENT_INSTANCE_BACKUP_RESTORED="backup.restored"
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
# backup.deleted carries `source` — the backup id, the same parameter
# name the created/restored events use for it. backup.pruned carries
# counts rather than ids: it is one event for the whole sweep, and the ids it
# removed are exactly the ones no longer listed. `deleted` is what was actually
# removed (never what was attempted) and `kept` is the retention window it ran
# with, so the pair reads as a complete statement of what the policy did.
declare -g -r EVENT_INSTANCE_BACKUP_DELETED="backup.deleted"
export EVENT_INSTANCE_BACKUP_DELETED

declare -g -r EVENT_INSTANCE_BACKUPS_PRUNED="backup.pruned"
export EVENT_INSTANCE_BACKUPS_PRUNED

# Retention is a policy an operator revises, so both directions are recorded.
# Pinning takes a backup out of the rotation's reach and unpinning hands it back
# — the second is the one that can lose data later, and a store that keeps
# growing is answered by knowing who released what.
declare -g -r EVENT_INSTANCE_BACKUP_PINNED="backup.pinned"
export EVENT_INSTANCE_BACKUP_PINNED

declare -g -r EVENT_INSTANCE_BACKUP_UNPINNED="backup.unpinned"
export EVENT_INSTANCE_BACKUP_UNPINNED

declare -g -r EVENT_INSTANCE_FILES_REMOVED="server.uninstall.files_removed"
export EVENT_INSTANCE_FILES_REMOVED

declare -g -r EVENT_INSTANCE_DIRECTORIES_REMOVED="server.uninstall.directories_removed"
export EVENT_INSTANCE_DIRECTORIES_REMOVED

declare -g -r EVENT_INSTANCE_REMOVED="server.uninstall.removed"
export EVENT_INSTANCE_REMOVED

declare -g -r EVENT_INSTANCE_UNINSTALL_STARTED="server.uninstall.started"
export EVENT_INSTANCE_UNINSTALL_STARTED

declare -g -r EVENT_INSTANCE_UNINSTALL_FINISHED="server.uninstall.finished"
export EVENT_INSTANCE_UNINSTALL_FINISHED

declare -g -r EVENT_INSTANCE_UNINSTALL_FAILED="server.uninstall.failed"
export EVENT_INSTANCE_UNINSTALL_FAILED

declare -g -r EVENT_INSTANCE_UNINSTALLED="server.uninstalled"
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
declare -g -r EVENT_INSTANCE_PORTS_OPENED="network.ports.opened"
export EVENT_INSTANCE_PORTS_OPENED

declare -g -r EVENT_INSTANCE_PORTS_CLOSED="network.ports.closed"
export EVENT_INSTANCE_PORTS_CLOSED

# UPnP port-forwarding audit events. Emitted by the kgsm-watchdog (the resident
# supervisor owns UPnP because it is process-lifetime state) when it opens/closes
# an instance's port mappings on the local router (IGD) via upnpc — origin=system,
# actor=system, an autonomous daemon action. DISTINCT from the firewall
# network.ports.* events above: a router NAT forward is a different fact from a
# host ufw rule (a host can have one without the other), so they carry separate
# event types and separate downstream audit actions. The `ports` parameter is the
# UFW-format spec; the payload renders it as the canonical structured array (same
# as the firewall events). Only a confirmed upnpc-exit-0 transition emits — never
# a fabricated outcome.
declare -g -r EVENT_INSTANCE_UPNP_OPENED="network.upnp.opened"
export EVENT_INSTANCE_UPNP_OPENED

declare -g -r EVENT_INSTANCE_UPNP_CLOSED="network.upnp.closed"
export EVENT_INSTANCE_UPNP_CLOSED

# A forward the router dropped on its own, put back by the watchdog's periodic
# sweep while the instance kept running. Its own type rather than a second
# network.upnp.opened because the two answer different questions: an open
# accompanies a bring-up, whereas this one says the mapping went missing with
# nothing on this host asking for it — the only evidence a reader gets that the
# router discards mappings it accepted, and how often. A router may report a
# lease as infinite and drop it anyway, so the sweep compares what the IGD
# actually holds against what the running instances need; `ports` carries the
# subset that was missing, not the instance's whole set.
declare -g -r EVENT_INSTANCE_UPNP_REASSERTED="network.upnp.reasserted"
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
declare -g -r EVENT_INSTANCE_PLAYER_JOINED="player.joined"
export EVENT_INSTANCE_PLAYER_JOINED

declare -g -r EVENT_INSTANCE_PLAYER_LEFT="player.left"
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
declare -g -r EVENT_INSTANCE_PLAYER_KICKED="player.kicked"
export EVENT_INSTANCE_PLAYER_KICKED

declare -g -r EVENT_INSTANCE_PLAYER_BANNED="player.banned"
export EVENT_INSTANCE_PLAYER_BANNED

declare -g -r EVENT_INSTANCE_PLAYER_UNBANNED="player.unbanned"
export EVENT_INSTANCE_PLAYER_UNBANNED

# Instance config-change audit event. Emitted by the command layer when a
# `.config.ini` key is set via `instances config-set`. Carries the instance name
# and the changed key ONLY — NEVER the value: instance config holds secrets
# (RCON/admin passwords, tokens), so the value must never reach a transport, log,
# or downstream audit. The downstream record is "key X changed on instance Y",
# nothing more.
declare -g -r EVENT_INSTANCE_CONFIG_CHANGED="config.changed"
export EVENT_INSTANCE_CONFIG_CHANGED

# Instance display-name event. Emitted alongside config.changed when the
# `display_name` key is set, by `instances rename` or by `instances config-set`.
#
# Its subject is still the instance, so `InstanceName` carries the ID exactly as
# every other instance event does — the ID is what a consumer keys on, and it is
# unchanged by a rename. The two labels ride along in full: a display name is the
# one value in the instance config that exists to be shown, so the key-only rule
# config.changed follows would leave this event unable to say what it is
# about, and every surface reading it would have to go back to the engine to
# learn the label it was just told had changed.
declare -g -r EVENT_INSTANCE_DISPLAY_NAME_CHANGED="server.renamed"
export EVENT_INSTANCE_DISPLAY_NAME_CHANGED

# Console-input audit event. Emitted by the command layer when an arbitrary
# console command is delivered to a running instance via `instances input`.
# Carries the instance name and the verbatim command text. Unlike
# config.changed (key only), the FULL command is carried on purpose —
# the trail's value is recording exactly what an operator ran (console commands
# are admin-level: ban/kick/op/...). A command can therefore contain a secret
# (e.g. an RCON login); the surface is operator-gated upstream and a consumer
# that must redact does so at its own boundary.
declare -g -r EVENT_INSTANCE_INPUT_SENT="console.input.sent"
export EVENT_INSTANCE_INPUT_SENT

# Announcement audit event. Emitted by the command layer when a broadcast is
# delivered to a running instance via `instances announce`. Carries the instance
# name, the message as it was given, and the resolved console command the game
# received. Both are kept: the message is what a person wrote and what every
# surface should show, while the resolved form is the literal effect and the only
# record of which template produced it.
#
# Separate from console.input.sent, whose subject is an operator running an
# arbitrary console command. An announcement's subject is the players, so a
# consumer asking "what were people told on this server" filters on the type
# instead of pattern-matching command text.
declare -g -r EVENT_INSTANCE_ANNOUNCEMENT_SENT="announcement.sent"
export EVENT_INSTANCE_ANNOUNCEMENT_SENT

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
declare -g -r EVENT_BLUEPRINT_CREATED="blueprint.created"
export EVENT_BLUEPRINT_CREATED

declare -g -r EVENT_BLUEPRINT_UPDATED="blueprint.updated"
export EVENT_BLUEPRINT_UPDATED

# `reverted_to_system` is the counterpart of `overrides_system`: true when
# deleting the user file uncovers a shipped blueprint that takes over again,
# false when the blueprint is gone from the host entirely.
declare -g -r EVENT_BLUEPRINT_REMOVED="blueprint.removed"
export EVENT_BLUEPRINT_REMOVED

# Library registry events. Their subject is a placement root — a named disk
# instances live on — so their Data carries `LibraryName` and `Path`, the way
# the blueprint events carry `BlueprintName`, and no instance is involved.
#
# They exist so a surface can keep its picture of where this host can place
# instances without polling the registry: an added library is somewhere new to
# install, and a removed one is a choice that has to disappear from an install
# form before someone picks it.
#
# `path` is the canonical root that was registered. It is carried because the
# name alone is not enough to act on — a removal takes the name out of the
# registry, and a reader that only learns the name cannot say which disk left.
# No capacity or online figure rides along: both are measurements that are only
# true at the moment they are taken, and `libraries list` is where they are
# taken.
declare -g -r EVENT_LIBRARY_ADDED="library.added"
export EVENT_LIBRARY_ADDED

declare -g -r EVENT_LIBRARY_REMOVED="library.removed"
export EVENT_LIBRARY_REMOVED

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
  ["$EVENT_INSTANCE_UPDATE_FAILED"]="instance"
  ["$EVENT_INSTANCE_UPDATED"]="instance"
  ["$EVENT_INSTANCE_VERSION_UPDATED"]="instance old_version new_version"
  ["$EVENT_INSTANCE_UPDATE_AVAILABLE"]="instance current_version latest_version"
  ["$EVENT_INSTANCE_INSTALLATION_STARTED"]="instance blueprint"
  ["$EVENT_INSTANCE_INSTALLATION_FINISHED"]="instance blueprint"
  # `library` is the name of the library the install landed in. Required: the
  # placement is resolved before a single directory is created, so an installer
  # always knows it, and an audit row that cannot say which disk a server went
  # onto is the row a multi-disk host needs most.
  ["$EVENT_INSTANCE_INSTALLED"]="instance blueprint library"
  # `from_library`/`to_library` are library names, and the instance is still the
  # same instance — only its files went anywhere.
  ["$EVENT_INSTANCE_MOVED"]="instance from_library to_library"
  ["$EVENT_INSTANCE_STARTED"]="instance"
  ["$EVENT_INSTANCE_STOPPED"]="instance"
  ["$EVENT_INSTANCE_RESTARTED"]="instance"
  ["$EVENT_INSTANCE_CRASHED"]="instance exit_code restarts"
  ["$EVENT_INSTANCE_FAILED"]="instance exit_code restarts"
  ["$EVENT_INSTANCE_READY"]="instance"
  ["$EVENT_INSTANCE_BACKUP_STARTED"]="instance"
  ["$EVENT_INSTANCE_BACKUP_FINISHED"]="instance"
  ["$EVENT_INSTANCE_RESTORE_STARTED"]="instance"
  ["$EVENT_INSTANCE_RESTORE_FINISHED"]="instance"
  ["$EVENT_INSTANCE_BACKUP_CREATED"]="instance source version"
  ["$EVENT_INSTANCE_BACKUP_RESTORED"]="instance source version"
  # `source` is the backup id, as in the two events above. No version: the
  # deleted backup's manifest is gone with it, and re-reading the instance's
  # current version would record a fact about the instance, not the backup.
  ["$EVENT_INSTANCE_BACKUP_DELETED"]="instance source"
  # `pinned` is how many the sweep skipped because they were pinned. Reported
  # alongside what it deleted so the pair states what the policy actually did:
  # without it, a sweep that removed nothing because everything was protected is
  # indistinguishable from one that found nothing to remove.
  ["$EVENT_INSTANCE_BACKUPS_PRUNED"]="instance deleted kept pinned"
  # `source` is the backup id, as in every other single-backup event.
  ["$EVENT_INSTANCE_BACKUP_PINNED"]="instance source"
  ["$EVENT_INSTANCE_BACKUP_UNPINNED"]="instance source"
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
  # Both labels are required, and an emitter that has neither has nothing to
  # report: an instance with no display name set reads as its id, which is the
  # value that goes here rather than an empty string.
  ["$EVENT_INSTANCE_DISPLAY_NAME_CHANGED"]="instance old_display_name new_display_name"
  # `command` is the verbatim console command. The matching case arm in
  # _build_event_payload renders Data { InstanceName, Command }.
  ["$EVENT_INSTANCE_INPUT_SENT"]="instance command"
  # `message` is what a person wrote; `command` is the resolved console command
  # the game received. Both are required — the message is what every surface
  # shows, and the resolved form is the only record of which template produced
  # it. The matching case arm in _build_event_payload renders
  # Data { InstanceName, Message, Command }.
  ["$EVENT_INSTANCE_ANNOUNCEMENT_SENT"]="instance message command"
  # Blueprint-scoped, not instance-scoped: the first param is a blueprint name
  # and renders as Data.BlueprintName. `runtime` is NOT in the spec because it
  # is nullable — it is read positionally and rendered as JSON null when the
  # emitter could not determine it (see _build_event_payload).
  ["$EVENT_BLUEPRINT_CREATED"]="blueprint tier overrides_system"
  ["$EVENT_BLUEPRINT_UPDATED"]="blueprint tier overrides_system"
  ["$EVENT_BLUEPRINT_REMOVED"]="blueprint tier reverted_to_system"
  # Library-scoped, not instance-scoped: the first param is a library name and
  # renders as Data.LibraryName.
  ["$EVENT_LIBRARY_ADDED"]="name path"
  ["$EVENT_LIBRARY_REMOVED"]="name path"
)

# How much each event matters and how it went, as "<severity> <outcome>".
#
# Severity is `info`, `warn` or `danger`; outcome is `success`, `failure` or
# `neutral`. They are separate axes: a backup created and a config key set are
# both routine and differ only in how they went, while an uninstall that
# succeeded is still the loudest thing on the feed.
#
# This is the engine's own judgement and nothing downstream second-guesses it.
# The values ride on every line, so a reader never holds a table of its own —
# which is what lets a surface render an event it has never heard of.
declare -g -A EVENT_GRADES=(
  ["$EVENT_INSTANCE_CREATED"]="info neutral"
  ["$EVENT_INSTANCE_DIRECTORIES_CREATED"]="info neutral"
  ["$EVENT_INSTANCE_FILES_CREATED"]="info neutral"
  ["$EVENT_INSTANCE_DOWNLOAD_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_DOWNLOAD_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_DOWNLOAD_FAILED"]="danger failure"
  ["$EVENT_INSTANCE_DOWNLOADED"]="info neutral"
  ["$EVENT_INSTANCE_DEPLOY_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_DEPLOY_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_DEPLOY_FAILED"]="danger failure"
  ["$EVENT_INSTANCE_DEPLOYED"]="info neutral"
  ["$EVENT_INSTANCE_RESTART_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_RESTART_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_RESTART_STOPPED"]="info neutral"
  ["$EVENT_INSTANCE_STOP_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_STOP_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_UPDATE_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_UPDATE_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_UPDATE_FAILED"]="danger failure"
  ["$EVENT_INSTANCE_UPDATED"]="info neutral"
  ["$EVENT_INSTANCE_VERSION_UPDATED"]="info success"
  ["$EVENT_INSTANCE_UPDATE_AVAILABLE"]="info neutral"
  ["$EVENT_INSTANCE_INSTALLATION_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_INSTALLATION_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_INSTALLED"]="info success"
  ["$EVENT_INSTANCE_MOVED"]="info neutral"
  ["$EVENT_INSTANCE_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_STOPPED"]="warn neutral"
  ["$EVENT_INSTANCE_RESTARTED"]="info neutral"
  ["$EVENT_INSTANCE_CRASHED"]="warn failure"
  ["$EVENT_INSTANCE_FAILED"]="danger failure"
  ["$EVENT_INSTANCE_READY"]="info success"
  ["$EVENT_INSTANCE_BACKUP_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_BACKUP_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_RESTORE_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_RESTORE_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_BACKUP_CREATED"]="info success"
  ["$EVENT_INSTANCE_BACKUP_RESTORED"]="warn success"
  ["$EVENT_INSTANCE_BACKUP_DELETED"]="warn neutral"
  ["$EVENT_INSTANCE_BACKUPS_PRUNED"]="info neutral"
  ["$EVENT_INSTANCE_BACKUP_PINNED"]="info neutral"
  ["$EVENT_INSTANCE_BACKUP_UNPINNED"]="warn neutral"
  ["$EVENT_INSTANCE_FILES_REMOVED"]="info neutral"
  ["$EVENT_INSTANCE_DIRECTORIES_REMOVED"]="info neutral"
  ["$EVENT_INSTANCE_REMOVED"]="info neutral"
  ["$EVENT_INSTANCE_UNINSTALL_STARTED"]="info neutral"
  ["$EVENT_INSTANCE_UNINSTALL_FINISHED"]="info neutral"
  ["$EVENT_INSTANCE_UNINSTALL_FAILED"]="danger failure"
  ["$EVENT_INSTANCE_UNINSTALLED"]="danger success"
  ["$EVENT_INSTANCE_PORTS_OPENED"]="info neutral"
  ["$EVENT_INSTANCE_PORTS_CLOSED"]="warn neutral"
  ["$EVENT_INSTANCE_UPNP_OPENED"]="info neutral"
  ["$EVENT_INSTANCE_UPNP_CLOSED"]="warn neutral"
  ["$EVENT_INSTANCE_UPNP_REASSERTED"]="warn neutral"
  ["$EVENT_INSTANCE_PLAYER_JOINED"]="info neutral"
  ["$EVENT_INSTANCE_PLAYER_LEFT"]="info neutral"
  ["$EVENT_INSTANCE_PLAYER_KICKED"]="warn neutral"
  ["$EVENT_INSTANCE_PLAYER_BANNED"]="danger neutral"
  ["$EVENT_INSTANCE_PLAYER_UNBANNED"]="info neutral"
  ["$EVENT_INSTANCE_CONFIG_CHANGED"]="info neutral"
  ["$EVENT_INSTANCE_DISPLAY_NAME_CHANGED"]="info neutral"
  ["$EVENT_INSTANCE_INPUT_SENT"]="info neutral"
  ["$EVENT_INSTANCE_ANNOUNCEMENT_SENT"]="info neutral"
  ["$EVENT_BLUEPRINT_CREATED"]="info neutral"
  ["$EVENT_BLUEPRINT_UPDATED"]="info neutral"
  ["$EVENT_BLUEPRINT_REMOVED"]="info neutral"
  ["$EVENT_LIBRARY_ADDED"]="info neutral"
  ["$EVENT_LIBRARY_REMOVED"]="info neutral"
)

# Validates that an event type is supported
# Args: $1 = event_type (e.g., "server.installed")
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

  # Get required parameters. The spec is a space-separated list of parameter
  # names, so it is split on whitespace and never glob-expanded.
  local required_params=()
  read -ra required_params <<< "${EVENT_CONFIGS[$event_type]}"

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

# Build JSON event payload
# Args: $1 = event_type, $2... = parameters
# Returns: echoes JSON payload or returns error code
# Mints the id that names one journal line (conformance §2·m).
#
# UUIDv7: 48 bits of unix milliseconds, then the version nibble, the variant
# bits and randomness. Time-ordered, so an id sorts the way the journal does —
# which is the property that rules out uuidgen's v4.
#
# Built from builtins alone and returned in a variable rather than on stdout:
# a $(...) substitution is a fork, and this runs on every event the engine
# emits. Measured at ~20us against the ~930us the `date` call below already
# costs, so the field is effectively free.
#
# EPOCHREALTIME is bash 5.0 and SRANDOM is 5.1. Where either is missing the id
# is left EMPTY and the envelope carries null — absent is a spelling every
# reader already handles (§2·e), and a v4 fallback would satisfy "is a uuid"
# while quietly breaking the ordering the format was chosen for.
function __event_id() {
  __event_id_out=""

  [[ -n "${EPOCHREALTIME:-}" && -n "${SRANDOM:-}" ]] || return 0

  local _now=${EPOCHREALTIME/./}
  local _ms=$((_now / 1000))

  printf -v __event_id_out '%08x-%04x-7%03x-%04x-%012x' \
    $(((_ms >> 16) & 0xFFFFFFFF)) \
    $((_ms & 0xFFFF)) \
    $((SRANDOM & 0xFFF)) \
    $((0x8000 | (SRANDOM & 0x3FFF))) \
    $((((SRANDOM & 0xFFFFFF) << 24) | (SRANDOM & 0xFFFFFF)))
}

export -f __event_id

# The one line of prose an event carries.
#
# Written here, at the moment the event happens, because the sentence is content
# and content is the producer's: three surfaces that own no pixels read it
# straight through (Discord announcements, Web Push, the assistant), and a feed
# that composed its own wording would have to hold a table with one arm per
# event — the arm that is missing for every event nobody has added yet.
#
# It names things as they are called right now. The instance id the emitter
# passed is what goes in, never a label looked up somewhere else: a line written
# today still says what the server was called today after somebody renames it.
#
# Phase events carry none. The `*_started`/`*_finished` brackets exist so a
# surface can show work in flight, and prose nothing reads is prose nobody
# maintains.
#
# Where a value the sentence needs is missing, the sentence keeps a subject —
# the literal `instance`, `blueprint`, `(unnamed)` or `a player` — so a summary
# never trails off with nothing after the verb.
#
# Returned in a variable rather than on stdout: a $(...) substitution is a fork,
# and this runs on every event the engine emits.
#
# Args: $1 = event_type, $2... = parameters
# Sets: __logic_event_summary_out
function __logic_event_summary() {
  local event_type="$1"
  shift
  local params=("$@")

  __logic_event_summary_out=""

  # The instance id, or the word that stands in its place. Every instance-scoped
  # sentence below reads it, and each of the three other subjects has a
  # stand-in of its own inside the arm that needs it.
  local _instance="${params[0]:-}"
  _instance="${_instance:-instance}"

  case "$event_type" in
    "$EVENT_INSTANCE_STARTED")
      __logic_event_summary_out="started $_instance"
      ;;
    "$EVENT_INSTANCE_READY")
      __logic_event_summary_out="finished loading $_instance"
      ;;
    "$EVENT_INSTANCE_STOPPED")
      __logic_event_summary_out="stopped $_instance"
      ;;
    "$EVENT_INSTANCE_RESTARTED")
      __logic_event_summary_out="restarted $_instance"
      ;;
    "$EVENT_INSTANCE_INSTALLED")
      __logic_event_summary_out="installed $_instance"
      ;;
    "$EVENT_INSTANCE_UNINSTALLED")
      __logic_event_summary_out="uninstalled $_instance"
      ;;
    "$EVENT_INSTANCE_UNINSTALL_FAILED")
      __logic_event_summary_out="could not uninstall $_instance"
      ;;
    "$EVENT_INSTANCE_MOVED")
      __logic_event_summary_out="moved $_instance"
      ;;
    "$EVENT_INSTANCE_VERSION_UPDATED")
      __logic_event_summary_out="updated $_instance"
      ;;
    "$EVENT_INSTANCE_UPDATE_FAILED")
      __logic_event_summary_out="could not update $_instance"
      ;;
    "$EVENT_INSTANCE_UPDATE_AVAILABLE")
      __logic_event_summary_out="update available for $_instance"
      ;;
    "$EVENT_INSTANCE_DOWNLOAD_FAILED")
      __logic_event_summary_out="could not download files for $_instance"
      ;;
    "$EVENT_INSTANCE_DEPLOY_FAILED")
      __logic_event_summary_out="could not deploy files for $_instance"
      ;;
    "$EVENT_INSTANCE_CRASHED")
      __logic_event_summary_out="$_instance crashed — auto-restarting"
      ;;
    "$EVENT_INSTANCE_FAILED")
      # The restart count is a tail rather than a clause of its own: a
      # supervisor that gave up without ever retrying has nothing to count, and
      # "after 0 restart(s)" would report a number where there is no number.
      local _tail=""
      [[ -z "${params[2]:-}" ]] || _tail=" after ${params[2]} restart(s)"
      __logic_event_summary_out="$_instance crashed — supervisor gave up${_tail}"
      ;;
    "$EVENT_INSTANCE_BACKUP_CREATED")
      __logic_event_summary_out="backed up $_instance"
      ;;
    "$EVENT_INSTANCE_BACKUP_RESTORED")
      __logic_event_summary_out="restored backup for $_instance"
      ;;
    "$EVENT_INSTANCE_BACKUP_DELETED")
      __logic_event_summary_out="deleted a backup for $_instance"
      ;;
    "$EVENT_INSTANCE_BACKUPS_PRUNED")
      __logic_event_summary_out="pruned backups for $_instance"
      ;;
    "$EVENT_INSTANCE_BACKUP_PINNED")
      __logic_event_summary_out="pinned a backup for $_instance"
      ;;
    "$EVENT_INSTANCE_BACKUP_UNPINNED")
      __logic_event_summary_out="unpinned a backup for $_instance"
      ;;
    "$EVENT_INSTANCE_PORTS_OPENED")
      __logic_event_summary_out="opened firewall ports for $_instance"
      ;;
    "$EVENT_INSTANCE_PORTS_CLOSED")
      __logic_event_summary_out="closed firewall ports for $_instance"
      ;;
    "$EVENT_INSTANCE_UPNP_OPENED")
      __logic_event_summary_out="forwarded UPnP ports for $_instance"
      ;;
    "$EVENT_INSTANCE_UPNP_CLOSED")
      __logic_event_summary_out="removed UPnP ports for $_instance"
      ;;
    "$EVENT_INSTANCE_UPNP_REASSERTED")
      __logic_event_summary_out="restored dropped UPnP ports for $_instance"
      ;;
    "$EVENT_INSTANCE_PLAYER_JOINED" | "$EVENT_INSTANCE_PLAYER_LEFT")
      # The name if the source gave one, the id if that is all it has: both are
      # nullable and a source may carry either. Neither is fabricated from the
      # other, so a source that gave nothing gets the stand-in.
      local _who="${params[2]:-}"
      [[ -n "$_who" ]] || _who="${params[1]:-}"
      _who="${_who:-a player}"

      local _presence="joined"
      [[ "$event_type" != "$EVENT_INSTANCE_PLAYER_LEFT" ]] || _presence="left"
      __logic_event_summary_out="$_who $_presence $_instance"
      ;;
    "$EVENT_INSTANCE_PLAYER_KICKED" | "$EVENT_INSTANCE_PLAYER_BANNED" | "$EVENT_INSTANCE_PLAYER_UNBANNED")
      # `target` is the identity token the operator supplied, carried verbatim:
      # which kind of token it is was declared by the blueprint, and classifying
      # it here would be a second answer to that.
      local _target="${params[1]:-}"
      _target="${_target:-a player}"

      local _moderation="kicked"
      case "$event_type" in
        "$EVENT_INSTANCE_PLAYER_BANNED") _moderation="banned" ;;
        "$EVENT_INSTANCE_PLAYER_UNBANNED") _moderation="unbanned" ;;
      esac
      __logic_event_summary_out="$_moderation $_target on $_instance"
      ;;
    "$EVENT_INSTANCE_DISPLAY_NAME_CHANGED")
      # An emptied label reads as the id, which is what a reader of the config
      # gets and therefore what the sentence says on either end.
      local _from="${params[1]:-}"
      _from="${_from:-$_instance}"
      local _to="${params[2]:-}"
      _to="${_to:-$_instance}"
      __logic_event_summary_out="renamed $_instance from '$_from' to '$_to'"
      ;;
    "$EVENT_INSTANCE_CONFIG_CHANGED")
      # The key, never the value — instance config holds rcon and admin
      # passwords, and a summary fans out to every transport the payload does.
      local _key="${params[1]:-}"
      if [[ -z "$_key" ]]; then
        __logic_event_summary_out="config changed for $_instance"
      else
        __logic_event_summary_out="set config '$_key' for $_instance"
      fi
      ;;
    "$EVENT_INSTANCE_INPUT_SENT")
      # A console command is arbitrary text an operator typed, so the sentence
      # takes a bounded slice of it. The payload keeps the command whole; this
      # is the line a feed prints in a row of its own.
      local _command="${params[1]:-}"
      if [[ -z "$_command" ]]; then
        __logic_event_summary_out="sent a console command to $_instance"
      else
        local _shown="$_command"
        [[ ${#_command} -le 80 ]] || _shown="${_command:0:79}…"
        __logic_event_summary_out="ran '$_shown' on $_instance"
      fi
      ;;
    "$EVENT_INSTANCE_ANNOUNCEMENT_SENT")
      # What a person wrote, bounded the same way console input is, for the same
      # reason: it is prose somebody typed and a row has one line to give it.
      local _message="${params[1]:-}"
      if [[ -z "$_message" ]]; then
        __logic_event_summary_out="announced to $_instance"
      else
        local _shown="$_message"
        [[ ${#_message} -le 80 ]] || _shown="${_message:0:79}…"
        __logic_event_summary_out="announced '$_shown' on $_instance"
      fi
      ;;
    "$EVENT_BLUEPRINT_CREATED")
      # Overriding a shipped blueprint and writing a brand-new one are two
      # different pieces of news, so they get two different verbs.
      local _blueprint="${params[0]:-}"
      _blueprint="${_blueprint:-blueprint}"
      if [[ "${params[2]:-}" == "true" ]]; then
        __logic_event_summary_out="overrode blueprint $_blueprint"
      else
        __logic_event_summary_out="created blueprint $_blueprint"
      fi
      ;;
    "$EVENT_BLUEPRINT_UPDATED")
      local _blueprint="${params[0]:-}"
      _blueprint="${_blueprint:-blueprint}"
      __logic_event_summary_out="edited blueprint $_blueprint"
      ;;
    "$EVENT_BLUEPRINT_REMOVED")
      # Three outcomes, because deleting a user file can uncover a shipped
      # blueprint that takes over, remove the blueprint from the host entirely,
      # or land somewhere the emitter could not determine.
      local _blueprint="${params[0]:-}"
      _blueprint="${_blueprint:-blueprint}"
      case "${params[2]:-}" in
        true)
          __logic_event_summary_out="reverted blueprint $_blueprint to the shipped version"
          ;;
        false)
          __logic_event_summary_out="removed blueprint $_blueprint"
          ;;
        *)
          __logic_event_summary_out="removed the local copy of blueprint $_blueprint"
          ;;
      esac
      ;;
    "$EVENT_LIBRARY_ADDED")
      local _library="${params[0]:-}"
      _library="${_library:-(unnamed)}"
      __logic_event_summary_out="registered library $_library"
      ;;
    "$EVENT_LIBRARY_REMOVED")
      local _library="${params[0]:-}"
      _library="${_library:-(unnamed)}"
      __logic_event_summary_out="deregistered library $_library — its files are untouched"
      ;;
  esac

  return $EC_SUCCESS
}

export -f __logic_event_summary

function __logic_build_event_payload() {
  local event_type="$1"
  shift
  local params=("$@")

  # Get required parameters specification. The spec is a space-separated list
  # of parameter names, so it is split on whitespace and never glob-expanded.
  local required_params=()
  read -ra required_params <<< "${EVENT_CONFIGS[$event_type]}"
  local param_names=()

  # Build parameter arrays for jq
  for i in "${!required_params[@]}"; do
    local param_name="${required_params[$i]}"
    local param_value="${params[$i]:-}"

    param_names+=("--arg" "$param_name" "$param_value")
  done

  # Resolve the actor (who triggered this event) for audit/correlation downstream.
  # KGSM is a stateless, multi-entrypoint CLI: it cannot itself know the semantic
  # principal, so the caller (bot/assistant/watchdog/API) supplies it via
  # KGSM_EVENT_ACTOR. An invocation that sets nothing has no actor, and the field is
  # emitted as JSON null: the OS user owns the process, it does not ask for the
  # action, and writing one where the other belongs puts the wrong name on an audit
  # record. Unknown is the honest answer and the only one available here.
  #
  # A supplied actor must be `provider:name` — the form every reader parses back
  # (KgsmActor). A malformed value is dropped to null and reported through
  # __logic_emit_actor_warning_out rather than written through: it would attribute
  # the action to something no reader can resolve. The event itself still records,
  # for the same reason the journal failure below only warns — the operation already
  # happened, and losing the record of a completed action is the worse outcome.
  local actor="${KGSM_EVENT_ACTOR:-}"
  __logic_emit_actor_warning_out=""
  if [[ -n "$actor" ]] && ! __logic_actor_is_wellformed "$actor"; then
    __logic_emit_actor_warning_out="$actor"
    actor=""
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
  local __event_id_out
  __event_id

  # How much this event matters, how it went, and the one line of prose that
  # says so. All three ride on the wire so a reader needs no table of its own;
  # an event with nothing to say in prose (a phase bracket) carries no summary
  # rather than an empty one, because an empty string is a third state on top of
  # "known" and "unknown" that no reader handles.
  local _severity="" _outcome=""
  read -r _severity _outcome <<< "${EVENT_GRADES[$event_type]:-}"

  local __logic_event_summary_out
  __logic_event_summary "$event_type" "${params[@]}"

  local jq_args=("${param_names[@]}"
    --arg event_id "$__event_id_out"
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
    --arg severity "$_severity"
    --arg outcome "$_outcome"
    --arg summary "$__logic_event_summary_out"
    --arg actor "$actor"
    --arg origin "$origin"
    --arg hostname "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "${HOSTNAME:-localhost}")"
    --arg producer_version "$KGSM_VERSION")

  # Build data object based on event type
  local data_object=""
  case "$event_type" in
    "$EVENT_INSTANCE_CREATED" | "$EVENT_INSTANCE_INSTALLATION_STARTED" | "$EVENT_INSTANCE_INSTALLATION_FINISHED")
      data_object='{
        InstanceName: $instance,
        Blueprint: $blueprint
      }'
      ;;
    "$EVENT_INSTANCE_INSTALLED")
      # The one installation event that also says where the files landed. The
      # bracket around the run states what is being installed; this states what
      # exists now, and on a host with several disks that includes which one.
      data_object='{
        InstanceName: $instance,
        Blueprint: $blueprint,
        Library: $library
      }'
      ;;
    "$EVENT_INSTANCE_MOVED")
      # `$from_library`/`$to_library` bind from the EVENT_CONFIGS spec. Both are
      # required, so neither is null-coalesced: an instance the registry places
      # in no library reports "unregistered", which is a measurement, not an
      # absence.
      data_object='{
        InstanceName: $instance,
        FromLibrary: $from_library,
        ToLibrary: $to_library
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
    "$EVENT_INSTANCE_BACKUP_DELETED" | "$EVENT_INSTANCE_BACKUP_PINNED" | "$EVENT_INSTANCE_BACKUP_UNPINNED")
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
        --argjson kept_n "${params[2]:-0}"
        --argjson pinned_n "${params[3]:-0}")
      data_object='{
        InstanceName: $instance,
        Deleted: $deleted_n,
        Kept: $kept_n,
        Pinned: $pinned_n
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
    "$EVENT_INSTANCE_DISPLAY_NAME_CHANGED")
      # `$old_display_name`/`$new_display_name` bind because those are the 2nd
      # and 3rd EVENT_CONFIGS param names. InstanceName is the ID, unchanged by
      # the rename — it is what the consumer updating a label looks the label up
      # by.
      data_object='{
        InstanceName: $instance,
        OldDisplayName: $old_display_name,
        NewDisplayName: $new_display_name
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
    "$EVENT_INSTANCE_ANNOUNCEMENT_SENT")
      # What was said, and what was sent to say it. `$message` and `$command`
      # bind because `message`/`command` are the 2nd and 3rd EVENT_CONFIGS param
      # names. A surface reads Message; Command answers which template resolved
      # it, which is what makes a broadcast that reached nobody diagnosable.
      data_object='{
        InstanceName: $instance,
        Message: $message,
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
      # Shared by the firewall (network.ports.*) and UPnP (network.upnp.*)
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
    "$EVENT_LIBRARY_ADDED" | "$EVENT_LIBRARY_REMOVED")
      # Keyed on a library rather than an instance: the subject is a placement
      # root. `$name`/`$path` bind from the EVENT_CONFIGS spec. Both are always
      # known to the emitter — a library has no identity without them — so
      # neither is null-coalesced.
      data_object='{
        LibraryName: $name,
        Path: $path
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
    V: 2,
    Id: (\$event_id | if . == \"\" then null else . end),
    EventType: \"$event_type\",
    Severity: (\$severity | if . == \"\" then null else . end),
    Outcome: (\$outcome | if . == \"\" then null else . end),
    Summary: (\$summary | if . == \"\" then null else . end),
    Data: $data_object,
    Timestamp: \$timestamp,
    Actor: (\$actor | if . == \"\" then null else . end),
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

# Whether an actor string is the `provider:name` form every reader parses back
# into a structured actor (see KgsmActor in kgsm-auth).
#
# The provider half is a lowercase token and the name half is anything non-empty:
# names carry spaces, dots and colons of their own, and only the FIRST colon
# separates. Requiring a provider is what stops a bare OS username — which names a
# process owner, not a principal — from being written as though it were one.
#
# The set of live providers is configuration, not code (a host wires its own via
# KgsmAuth__Providers__<name>), so the engine checks the shape and leaves naming a
# provider it has never heard of to the reader, which keeps it rather than coercing
# it into one it knows.
#
# Args: $1 = candidate actor string
# Returns: EC_SUCCESS when well-formed, EC_INVALID_ARG otherwise
function __logic_actor_is_wellformed() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9._-]*:.+$ ]] || return $EC_INVALID_ARG
  return $EC_SUCCESS
}

export -f __logic_actor_is_wellformed

# Set by __logic_emit_event to the actor it refused, so the caller in
# core/events.sh can report it. This module does no user-facing I/O of its own.
declare -g __logic_emit_actor_warning_out=""

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
# Args: $1 = event_type (the dotted name), $2... = parameters
# Returns: EC_SUCCESS, or the failing stage's code
function __logic_emit_event() {
  local event_type="$1"
  shift
  local params=("$@")

  if [[ -z "$event_type" ]]; then
    return $EC_MISSING_ARG
  fi

  if ! __logic_validate_event_type "$event_type"; then
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
