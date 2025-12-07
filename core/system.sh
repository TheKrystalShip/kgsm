#!/usr/bin/env bash

# This script is in charge of doing system tasks for the other modules.
# Things like directories existence, file permissions, and other system-related tasks.
# It is loaded by the main script and should not be run directly.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

function __create_dir() {
  local dir="$1"
  local permissions="${2:-755}" # Default to 755 if no permissions are specified

  if [[ -z "$dir" ]]; then
    __print_error "No directory specified for creation."
    exit $EC_INVALID_ARG
  fi

  # If directory already exists, there's nothing to do
  if [[ -d "$dir" ]]; then
    return 0
  fi

  # Create the directory with appropriate permissions
  mkdir -p "$dir" || {
    __print_error "Failed to create directory '$dir'."
    exit $EC_FAILED_MKDIR
  }

  # Set permissions to 755
  chmod $permissions "$dir" || {
    __print_error "Failed to set permissions for '$dir'."
    exit $EC_PERMISSION
  }
}

export -f __create_dir

function __source() {
  local file="$1"
  if [[ -z "$file" ]]; then
    __print_error "No file specified for sourcing."
    exit $EC_INVALID_ARG
  fi

  # Check if the file is readable
  if [[ ! -r "$file" ]]; then
    __print_error "File '$file' is not readable."
    exit $EC_PERMISSION
  fi

  # Check if the file exists
  if [[ ! -f "$file" ]]; then
    __print_error "File '$file' does not exist."
    exit $EC_FILE_NOT_FOUND
  fi

  # Source the file
  # shellcheck disable=SC1090
  source "$file" || {
    __print_error "Failed to source file '$file'."
    exit $EC_FAILED_SOURCE
  }
}

export -f __source

# Function to create a file with specific permissions
function __create_file() {
  local file="$1"
  local permissions="${2:-644}" # Default to 644 if no permissions are specified

  if [[ -z "$file" ]]; then
    __print_error "No file specified for creation."
    exit $EC_INVALID_ARG
  fi

  # If file already exists, there's nothing to do
  if [[ -f "$file" ]]; then
    return 0
  fi

  # Create the file with appropriate permissions
  touch "$file" || {
    __print_error "Failed to create file '$file'."
    exit $EC_FAILED_TOUCH
  }

  # Set permissions to 644
  chmod $permissions "$file" || {
    __print_error "Failed to set permissions for '$file'."
    exit $EC_PERMISSION
  }
}

export -f __create_file

export KGSM_SYSTEM_LOADED=1
