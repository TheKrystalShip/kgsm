#!/usr/bin/env bash

if [[ -n "${KGSM_ERRORS_LOADED:-}" ]]; then
  return 0
fi

# Exit codes
declare -g -r EC_SUCCESS=0
export EC_SUCCESS

declare -g -r EC_ERROR=1
export EC_ERROR

declare -g -r EC_KGSM_ROOT=2
export EC_KGSM_ROOT

declare -g -r EC_FAILED_CONFIG=3
export EC_FAILED_CONFIG

declare -g -r EC_INVALID_CONFIG=4
export EC_INVALID_CONFIG

declare -g -r EC_FILE_NOT_FOUND=5
export EC_FILE_NOT_FOUND

declare -g -r EC_FAILED_SOURCE=6
export EC_FAILED_SOURCE

declare -g -r EC_MISSING_ARG=7
export EC_MISSING_ARG

declare -g -r EC_INVALID_ARG=8
export EC_INVALID_ARG

declare -g -r EC_FAILED_CD=9
export EC_FAILED_CD

declare -g -r EC_FAILED_CP=10
export EC_FAILED_CP

declare -g -r EC_FAILED_RM=11
export EC_FAILED_RM

declare -g -r EC_FAILED_TEMPLATE=12
export EC_FAILED_TEMPLATE

declare -g -r EC_FAILED_DOWNLOAD=13
export EC_FAILED_DOWNLOAD

declare -g -r EC_FAILED_DEPLOY=14
export EC_FAILED_DEPLOY

declare -g -r EC_FAILED_MKDIR=15
export EC_FAILED_MKDIR

declare -g -r EC_PERMISSION=16
export EC_PERMISSION

declare -g -r EC_FAILED_SED=17
export EC_FAILED_SED

# 18 retired: was EC_SYSTEMD (systemd is no longer a lifecycle manager).

declare -g -r EC_FIREWALL=19
export EC_FIREWALL

declare -g -r EC_MALFORMED_INSTANCE=20
export EC_MALFORMED_INSTANCE

declare -g -r EC_MISSING_DEPENDENCY=21
export EC_MISSING_DEPENDENCY

declare -g -r EC_FAILED_LN=22
export EC_FAILED_LN

declare -g -r EC_FAILED_UPDATE_CONFIG=23
export EC_FAILED_UPDATE_CONFIG

declare -g -r EC_KEY_NOT_FOUND=24
export EC_KEY_NOT_FOUND

declare -g -r EC_NOT_FOUND=25
export EC_NOT_FOUND

declare -g -r EC_FAILED_VERSION_SAVE=26
export EC_FAILED_VERSION_SAVE

declare -g -r EC_BLUEPRINT_NOT_FOUND=27
export EC_BLUEPRINT_NOT_FOUND

declare -g -r EC_INVALID_BLUEPRINT=28
export EC_INVALID_BLUEPRINT

declare -g -r EC_INVALID_INSTANCE=29
export EC_INVALID_INSTANCE

declare -g -r EC_FAILED_MV=30
export EC_FAILED_MV

declare -g -r EC_CANCELLED=31
export EC_CANCELLED

declare -g -r EC_FAILED_TOUCH=32
export EC_FAILED_TOUCH

declare -g -r EC_FAILURE=33
export EC_FAILURE

declare -g -r EC_MISSING_ARGS=34
export EC_MISSING_ARGS

declare -g -r EC_SKIP=35
export EC_SKIP

declare -g -r EC_TIMEOUT=36
export EC_TIMEOUT

declare -g -r EC_EVENT_TYPE_INVALID=37
export EC_EVENT_TYPE_INVALID

declare -g -r EC_EVENT_PARAMS_INVALID=38
export EC_EVENT_PARAMS_INVALID

declare -g -r EC_EVENT_TRANSPORT_FAILED=39
export EC_EVENT_TRANSPORT_FAILED

declare -g -r EC_EVENT_JSON_FAILED=40
export EC_EVENT_JSON_FAILED

declare -g -r EC_WATCHER_TIMEOUT=41
export EC_WATCHER_TIMEOUT

declare -g -r EC_WATCHER_NO_STRATEGY=42
export EC_WATCHER_NO_STRATEGY

declare -g -r EC_WATCHER_PATTERN_NOT_FOUND=43
export EC_WATCHER_PATTERN_NOT_FOUND

declare -g -r EC_WATCHER_PORT_NOT_ACTIVE=44
export EC_WATCHER_PORT_NOT_ACTIVE

declare -g -r EC_WATCHER_LOG_FILE_MISSING=45
export EC_WATCHER_LOG_FILE_MISSING

declare -g -r EC_DIRECTORY_NOT_FOUND=46
export EC_DIRECTORY_NOT_FOUND

declare -g -r EC_CGROUP=47
export EC_CGROUP

declare -g -r EC_CGROUP_UNSUPPORTED=48
export EC_CGROUP_UNSUPPORTED

# The kgsm-firewall authority (host-firewall owner) could not be reached: its
# socket is missing/refused or its binary is absent. Distinct from EC_FIREWALL (a
# reachable backend that rejected the rule) — this is the §7g hard-fail trigger:
# a firewall-enabled install aborts here rather than silently proceeding.
declare -g -r EC_FIREWALL_UNREACHABLE=49
export EC_FIREWALL_UNREACHABLE

declare -g -r EC_EVENT_JOURNAL_FAILED=50
export EC_EVENT_JOURNAL_FAILED

# Starting this instance would leave the node with less free memory than the
# configured floor. A refusal to protect the HOST, not a fault of the instance:
# nothing is wrong with it, there is simply no room right now. Distinct from
# EC_ERROR so a caller can tell "would not fit" from "tried and failed" — the
# watchdog defers a restart on this rather than counting it as a crash.
declare -g -r EC_INSUFFICIENT_MEMORY=51
export EC_INSUFFICIENT_MEMORY

# =============================================================================
# EVENT SUCCESS CODES (200-255 range)
# =============================================================================
# These codes indicate successful operations that should trigger events.
# They are used by pure logic functions to signal that specific events
# should be emitted by the orchestration layer.

# Directory management events
declare -g -r EC_SUCCESS_DIRECTORIES_CREATED=200
export EC_SUCCESS_DIRECTORIES_CREATED

declare -g -r EC_SUCCESS_DIRECTORIES_REMOVED=201
export EC_SUCCESS_DIRECTORIES_REMOVED

# File management events
declare -g -r EC_SUCCESS_FILES_CREATED=202
export EC_SUCCESS_FILES_CREATED

declare -g -r EC_SUCCESS_FILES_REMOVED=203
export EC_SUCCESS_FILES_REMOVED

# File component-specific events (204-209 reserved for files module)
declare -g -r EC_SUCCESS_CONFIG_INSTALLED=204
export EC_SUCCESS_CONFIG_INSTALLED

declare -g -r EC_SUCCESS_CONFIG_UNINSTALLED=205
export EC_SUCCESS_CONFIG_UNINSTALLED

declare -g -r EC_SUCCESS_MANAGEMENT_FILE_CREATED=206
export EC_SUCCESS_MANAGEMENT_FILE_CREATED

declare -g -r EC_SUCCESS_MANAGEMENT_FILE_REMOVED=207
export EC_SUCCESS_MANAGEMENT_FILE_REMOVED

# Boot auto-start enable/disable (watchdog desired-state), replacing the old
# systemd enable/disable success codes (same values, repurposed).
declare -g -r EC_SUCCESS_AUTOSTART_ENABLED=208
export EC_SUCCESS_AUTOSTART_ENABLED

declare -g -r EC_SUCCESS_AUTOSTART_DISABLED=209
export EC_SUCCESS_AUTOSTART_DISABLED

declare -g -r EC_SUCCESS_INSTANCE_CREATED=210
export EC_SUCCESS_INSTANCE_CREATED

declare -g -r EC_SUCCESS_INSTANCE_STARTED=211
export EC_SUCCESS_INSTANCE_STARTED

declare -g -r EC_SUCCESS_INSTANCE_STOPPED=212
export EC_SUCCESS_INSTANCE_STOPPED

declare -g -r EC_SUCCESS_INSTANCE_RESTARTED=213
export EC_SUCCESS_INSTANCE_RESTARTED

declare -g -r EC_SUCCESS_INSTANCE_REMOVED=214
export EC_SUCCESS_INSTANCE_REMOVED

# Additional file integration events (215-219)
declare -g -r EC_SUCCESS_FIREWALL_ENABLED=215
export EC_SUCCESS_FIREWALL_ENABLED

declare -g -r EC_SUCCESS_FIREWALL_DISABLED=216
export EC_SUCCESS_FIREWALL_DISABLED

declare -g -r EC_SUCCESS_SYMLINK_CREATED=217
export EC_SUCCESS_SYMLINK_CREATED

declare -g -r EC_SUCCESS_SYMLINK_REMOVED=218
export EC_SUCCESS_SYMLINK_REMOVED

# Deployment events (reserved for future use)
declare -g -r EC_SUCCESS_DEPLOYMENT_STARTED=220
export EC_SUCCESS_DEPLOYMENT_STARTED

declare -g -r EC_SUCCESS_DEPLOYMENT_FINISHED=221
export EC_SUCCESS_DEPLOYMENT_FINISHED

# Watcher events
declare -g -r EC_SUCCESS_INSTANCE_READY=222
export EC_SUCCESS_INSTANCE_READY

# Blueprint management events (moved from 256-259 to valid range)
declare -g -r EC_SUCCESS_BLUEPRINT_LISTED=223
export EC_SUCCESS_BLUEPRINT_LISTED

declare -g -r EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED=224
export EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED

declare -g -r EC_SUCCESS_BLUEPRINT_FOUND=225
export EC_SUCCESS_BLUEPRINT_FOUND

declare -g -r EC_SUCCESS_BLUEPRINT_VALIDATED=226
export EC_SUCCESS_BLUEPRINT_VALIDATED

# Host-firewall port lifetime. Distinct from EC_SUCCESS_FIREWALL_ENABLED/DISABLED
# above: those report the per-instance management TOGGLE moving, these report the
# rule itself being written or removed on a bring-up/teardown. Returned only when
# the kgsm-firewall authority confirmed the change — an instance that opted out or
# declares no ports returns EC_SUCCESS, so a caller can tell "nothing to do" from
# "the ports are now open" and audit only the latter.
declare -g -r EC_SUCCESS_FIREWALL_PORTS_OPENED=227
export EC_SUCCESS_FIREWALL_PORTS_OPENED

declare -g -r EC_SUCCESS_FIREWALL_PORTS_CLOSED=228
export EC_SUCCESS_FIREWALL_PORTS_CLOSED

# Backup events (reserved for future use)
declare -g -r EC_SUCCESS_BACKUP_CREATED=230
export EC_SUCCESS_BACKUP_CREATED

declare -g -r EC_SUCCESS_BACKUP_RESTORED=231
export EC_SUCCESS_BACKUP_RESTORED

# Configuration management events
declare -g -r EC_SUCCESS_CONFIG_SET=240
export EC_SUCCESS_CONFIG_SET

declare -g -r EC_SUCCESS_CONFIG_RESET=241
export EC_SUCCESS_CONFIG_RESET

declare -g -r EC_SUCCESS_CONFIG_VALIDATED=242
export EC_SUCCESS_CONFIG_VALIDATED

declare -g -r EC_SUCCESS_CONFIG_MERGED=243
export EC_SUCCESS_CONFIG_MERGED

declare -g -r EC_MIGRATION_FAILED=245
export EC_MIGRATION_FAILED

declare -g -r EC_MIGRATION_NOT_FOUND=246
export EC_MIGRATION_NOT_FOUND

declare -g -r EC_MISSING_CONFIG_KEY=247
export EC_MISSING_CONFIG_KEY

declare -g -r EC_INVALID_CONFIG_VALUE=248
export EC_INVALID_CONFIG_VALUE

declare -g -r EC_FAILED_BACKUP=249
export EC_FAILED_BACKUP

# System management events
declare -g -r EC_SUCCESS_SYSTEM_SHUTDOWN=250
export EC_SUCCESS_SYSTEM_SHUTDOWN

declare -g -r EC_SUCCESS_SYSTEM_RESTART=251
export EC_SUCCESS_SYSTEM_RESTART

declare -g -r EC_SUCCESS_SYSTEM_INFO_RETRIEVED=252
export EC_SUCCESS_SYSTEM_INFO_RETRIEVED

# Network management events
declare -g -r EC_SUCCESS_NETWORK_PORT_CHECKED=253
export EC_SUCCESS_NETWORK_PORT_CHECKED

declare -g -r EC_SUCCESS_NETWORK_PORT_FREE=254
export EC_SUCCESS_NETWORK_PORT_FREE

declare -g -r EC_SUCCESS_NETWORK_PORT_IN_USE=255
export EC_SUCCESS_NETWORK_PORT_IN_USE

declare -A EXIT_CODES=(
   [$EC_SUCCESS]="Operation successful"
   [$EC_ERROR]="General error"
   [$EC_KGSM_ROOT]="KGSM_ROOT not set"
   [$EC_FAILED_CONFIG]="Failed to load config.ini file"
   [$EC_INVALID_CONFIG]="Invalid configuration"
   [$EC_FILE_NOT_FOUND]="File not found"
   [$EC_FAILED_SOURCE]="Failed to source file"
   [$EC_MISSING_ARG]="Missing argument"
   [$EC_INVALID_ARG]="Invalid argument"
   [$EC_CANCELLED]="Operation cancelled"
   [$EC_FAILED_CD]="Failed to move into directory"
   [$EC_FAILED_CP]="Failed to copy"
   [$EC_FAILED_RM]="Failed to remove"
   [$EC_FAILED_TEMPLATE]="Failed to generate template"
   [$EC_FAILED_DOWNLOAD]="Failed to download"
   [$EC_FAILED_DEPLOY]="Failed to deploy"
   [$EC_FAILED_MKDIR]="Failed mkdir"
   [$EC_PERMISSION]="Permission issue"
   [$EC_FAILED_SED]="Error with 'sed' command"
   [$EC_FIREWALL]="Firewall backend operation failed"
   [$EC_MALFORMED_INSTANCE]="Malformed instance config file"
   [$EC_MISSING_DEPENDENCY]="Missing required dependency"
   [$EC_FAILED_LN]="Failed to create symlink"
   [$EC_FAILED_UPDATE_CONFIG]="Failed to update config file"
   [$EC_KEY_NOT_FOUND]="Configuration key not found"
   [$EC_NOT_FOUND]="Item not found"
   [$EC_FAILED_VERSION_SAVE]="Failed to save version"
   [$EC_BLUEPRINT_NOT_FOUND]="Blueprint not found"
   [$EC_INVALID_BLUEPRINT]="Invalid blueprint"
   [$EC_INVALID_INSTANCE]="Invalid instance"
   [$EC_FAILED_MV]="Failed to move file"
   [$EC_ERROR]="Error occurred"
   [$EC_FAILED_TOUCH]="Failed to create file"
   [$EC_FAILURE]="Operation failed"
   [$EC_MISSING_ARGS]="Missing arguments"
   [$EC_SKIP]="Operation skipped"
   [$EC_TIMEOUT]="Test timed out"
   [$EC_EVENT_TYPE_INVALID]="Invalid event type"
   [$EC_EVENT_PARAMS_INVALID]="Invalid event parameters"
   [$EC_EVENT_TRANSPORT_FAILED]="Event transport failed"
   [$EC_EVENT_JSON_FAILED]="Failed to generate event JSON payload"
   [$EC_EVENT_JOURNAL_FAILED]="Failed to append event to the journal"
   [$EC_WATCHER_TIMEOUT]="Watcher timed out waiting for instance readiness"
   [$EC_WATCHER_NO_STRATEGY]="No watcher strategy configured for instance"
   [$EC_WATCHER_PATTERN_NOT_FOUND]="Log pattern not found in instance configuration"
   [$EC_WATCHER_PORT_NOT_ACTIVE]="Port not active or not configured"
   [$EC_WATCHER_LOG_FILE_MISSING]="Log file not found for instance"
   [$EC_CGROUP]="Error with cgroup operation"
   [$EC_CGROUP_UNSUPPORTED]="cgroup v2 not available, not delegated, or kernel too old"
   [$EC_FIREWALL_UNREACHABLE]="kgsm-firewall authority not reachable"
   [$EC_INSUFFICIENT_MEMORY]="Not enough free memory to start this instance"
)

declare -g KGSM_ERRORS_LOADED=1
export KGSM_ERRORS_LOADED
