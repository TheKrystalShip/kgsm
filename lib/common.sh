#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Module loader
if [[ ! $KGSM_LOADER_LOADED ]]; then
  # Provides nice wrappers for locating and loading other modules and files
  include_loader="$(find "$KGSM_ROOT" -type f -name loader.sh -print -quit)"
  if [[ -z "$include_loader" ]]; then
    echo "${0##*/} ERROR: Failed to locate loader.sh" >&2
    echo "${0##*/} ERROR: File structure might be compromised" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$include_loader" || exit 1
fi

# Error codes and definitions
if [[ ! "$KGSM_ERRORS_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$(__find_library errors.sh)" || {
    echo -e "ERROR: Failed to load errors.sh library"
    exit 1
  }
fi

# Directories logic (provides __create_dir and __create_file utilities)
if [[ -z "$KGSM_LOGIC_DIRECTORIES_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$(__find_logic_library directories.sh)" || {
    echo -e "ERROR: Failed to load directories.sh logic library"
    exit $EC_FAILED_SOURCE
  }
fi

# User config.ini
if [[ ! "$KGSM_CONFIG_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$(__find_library config.sh)" || {
    echo -e "ERROR: Failed to load config.sh library"
    exit $EC_FAILED_SOURCE
  }
fi

# File logging
if [[ ! "$KGSM_LOGGING_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$(__find_library logging.sh)" || {
    echo -e "ERROR: Failed to load logging.sh library"
    exit $EC_FAILED_SOURCE
  }
fi

# Parser
if [[ -z "$KGSM_PARSER_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$(__find_library parser.sh)" || {
    echo -e "ERROR: Failed to load parser.sh library"
    exit $EC_FAILED_SOURCE
  }
fi

# Validation
if [[ -z "$KGSM_VALIDATION_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$(__find_library validation.sh)" || {
    echo -e "ERROR: Failed to load validation.sh library"
    exit $EC_FAILED_SOURCE
  }
fi

if [[ -z "$KGSM_EVENTS_LIBRARY_LOADED" ]]; then
  # shellcheck disable=SC1090
  source "$(__find_library events.sh)" || {
    echo -e "ERROR: Failed to load events.sh library"
    exit $EC_FAILED_SOURCE
  }
fi

# Export this to check before loading this file again
export KGSM_COMMON_LOADED=1
