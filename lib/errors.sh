#!/usr/bin/env bash

# Exit codes
declare -g -r EC_OKAY=0
export EC_OKAY

declare -g -r EC_GENERAL=1
export EC_GENERAL

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

declare -g -r EC_SYSTEMD=18
export EC_SYSTEMD

declare -g -r EC_UFW=19
export EC_UFW

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

declare -g -r EC_ERROR=31
export EC_ERROR

declare -g -r EC_FAILED_TOUCH=32
export EC_FAILED_TOUCH

declare -g -r EC_FAILURE=33
export EC_FAILURE

declare -g -r EC_MISSING_ARGS=34
export EC_MISSING_ARGS

declare -g -r EC_SKIP=35
export EC_SKIP

declare -g -r EC_SUCCESS=36
export EC_SUCCESS

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

# File management events (reserved for future use)
declare -g -r EC_SUCCESS_FILES_CREATED=202
export EC_SUCCESS_FILES_CREATED

declare -g -r EC_SUCCESS_FILES_REMOVED=203
export EC_SUCCESS_FILES_REMOVED

# Instance lifecycle events (reserved for future use)
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

# Deployment events (reserved for future use)
declare -g -r EC_SUCCESS_DEPLOYMENT_STARTED=220
export EC_SUCCESS_DEPLOYMENT_STARTED

declare -g -r EC_SUCCESS_DEPLOYMENT_FINISHED=221
export EC_SUCCESS_DEPLOYMENT_FINISHED

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
# Network management events
declare -g -r EC_SUCCESS_NETWORK_PORT_CHECKED=253
export EC_SUCCESS_NETWORK_PORT_CHECKED

declare -g -r EC_SUCCESS_NETWORK_PORT_FREE=254
export EC_SUCCESS_NETWORK_PORT_FREE

declare -g -r EC_SUCCESS_NETWORK_PORT_IN_USE=255
export EC_SUCCESS_NETWORK_PORT_IN_USE

declare -A EXIT_CODES=(
  [$EC_OKAY]="No error"
  [$EC_GENERAL]="General error"
  [$EC_KGSM_ROOT]="KGSM_ROOT not set"
  [$EC_FAILED_CONFIG]="Failed to load config.ini file"
  [$EC_INVALID_CONFIG]="Invalid configuration"
  [$EC_FILE_NOT_FOUND]="File not found"
  [$EC_FAILED_SOURCE]="Failed to source file"
  [$EC_MISSING_ARG]="Missing argument"
  [$EC_INVALID_ARG]="Invalid argument"
  [$EC_FAILED_CD]="Failed to move into directory"
  [$EC_FAILED_CP]="Failed to copy"
  [$EC_FAILED_RM]="Failed to remove"
  [$EC_FAILED_TEMPLATE]="Failed to generate template"
  [$EC_FAILED_DOWNLOAD]="Failed to download"
  [$EC_FAILED_DEPLOY]="Failed to deploy"
  [$EC_FAILED_MKDIR]="Failed mkdir"
  [$EC_PERMISSION]="Permission issue"
  [$EC_FAILED_SED]="Error with 'sed' command"
  [$EC_SYSTEMD]="Error with 'systemctl' command"
  [$EC_UFW]="Error with 'ufw' command"
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
  [$EC_SUCCESS]="Operation successful"
)


export KGSM_ERRORS_LOADED=1
