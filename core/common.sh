#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Module loader
if [[ -z "$KGSM_LOADER_LOADED" ]]; then
  # Provides nice wrappers for locating and loading other modules and files
  include_loader="$KGSM_ROOT/core/loader.sh"
  if [[ ! -f "$include_loader" ]]; then
    echo "${0##*/} ERROR: Failed to locate loader.sh" >&2
    echo "${0##*/} ERROR: File structure might be compromised" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$include_loader" || {
    echo -e "ERROR: Failed to load loader.sh core module" >&2
    exit 1
  }
fi

# Error codes and definitions
if [[ -z "$KGSM_ERRORS_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/errors.sh" || {
    echo -e "ERROR: Failed to load errors.sh core module" >&2
    exit 1
  }
fi

# From this point forward, we can use the error codes defined in errors.sh
if [[ -z "$KGSM_DELEGATOR_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/delegator.sh" || {
    echo -e "ERROR: Failed to load delegator.sh core module" >&2
    exit $EC_FAILED_SOURCE
  }
fi

# Events
if [[ -z "$KGSM_EVENTS_LIBRARY_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/events.sh" || {
    echo -e "ERROR: Failed to load events.sh core module" >&2
    exit $EC_FAILED_SOURCE
  }
fi

# System
if [[ -z "$KGSM_SYSTEM_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/system.sh" || {
    echo -e "ERROR: Failed to load system.sh core module" >&2
    exit $EC_FAILED_SOURCE
  }
fi

# User config.ini
if [[ -z "$KGSM_CONFIG_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/config.sh" || {
    echo -e "ERROR: Failed to load config.sh core module" >&2
    exit $EC_FAILED_SOURCE
  }
fi

# File logging
if [[ -z "$KGSM_LOGGING_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/logging.sh" || {
    echo -e "ERROR: Failed to load logging.sh core module" >&2
    exit $EC_FAILED_SOURCE
  }
fi

# Parser
if [[ -z "$KGSM_PARSER_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/parser.sh" || {
    echo -e "ERROR: Failed to load parser.sh core module" >&2
    exit $EC_FAILED_SOURCE
  }
fi

# Validation
if [[ -z "$KGSM_VALIDATION_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$CORE_SOURCE_DIR/validation.sh" || {
    echo -e "ERROR: Failed to load validation.sh core module" >&2
    exit $EC_FAILED_SOURCE
  }
fi

# Export this to check before loading this file again
export KGSM_COMMON_LOADED=1
