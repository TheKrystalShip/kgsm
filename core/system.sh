#!/usr/bin/env bash

# This script is in charge of doing system tasks for the other modules.
# Things like directories existence, file permissions, and other system-related tasks.
# It is loaded by the main script and should not be run directly.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_SYSTEM_LOADED:-}" ]]; then
  return 0
fi

function __create_dir() {
  local dir="$1"
  local permissions="${2:-755}" # Default to 755 if no permissions are specified

  if [[ -z "$dir" ]]; then
    __print_error "No directory specified for creation."
    return $EC_INVALID_ARG
  fi

  # If directory already exists, there's nothing to do
  if [[ -d "$dir" ]]; then
    return 0
  fi

  # Create the directory with appropriate permissions
  mkdir -p "$dir" || {
    __print_error "Failed to create directory '$dir'."
    return $EC_FAILED_MKDIR
  }

  # Set permissions to 755
  chmod $permissions "$dir" || {
    __print_error "Failed to set permissions for '$dir'."
    return $EC_PERMISSION
  }
}

export -f __create_dir

function __source() {
  local file="$1"
  if [[ -z "$file" ]]; then
    __print_error "No file specified for sourcing."
    return $EC_INVALID_ARG
  fi

  # Check if the file is readable
  if [[ ! -r "$file" ]]; then
    __print_error "File '$file' is not readable."
    return $EC_PERMISSION
  fi

  # Check if the file exists
  if [[ ! -f "$file" ]]; then
    __print_error "File '$file' does not exist."
    return $EC_FILE_NOT_FOUND
  fi

  # Source the file
  # shellcheck disable=SC1090
  source "$file" || {
    __print_error "Failed to source file '$file'."
    return $EC_FAILED_SOURCE
  }
}

export -f __source

# Function to create a file with specific permissions
function __create_file() {
  local file="$1"
  local permissions="${2:-644}" # Default to 644 if no permissions are specified

  if [[ -z "$file" ]]; then
    __print_error "No file specified for creation."
    return $EC_INVALID_ARG
  fi

  # If file already exists, there's nothing to do
  if [[ -f "$file" ]]; then
    return 0
  fi

  # Create the file with appropriate permissions
  touch "$file" || {
    __print_error "Failed to create file '$file'."
    return $EC_FAILED_TOUCH
  }

  # Set permissions to 644
  chmod $permissions "$file" || {
    __print_error "Failed to set permissions for '$file'."
    return $EC_PERMISSION
  }
}

export -f __create_file

# Refuses a command run by an account whose instance registry this host's
# services do not read.
#
# The engine derives its entire world from the invoking account: instances,
# blueprints, the library registry and the config all hang off that account's
# XDG paths. The event journal does not — it is one host-wide directory every
# producer appends to and every consumer tails, and its OWNER is the account
# this host's units run as. A unit running as that account enumerates its
# registry and no other, so any other account reads and writes a registry that
# is not the host's: a listing comes back empty, a lookup reports an instance
# missing, an install lands where nothing will ever see it — each exiting 0 or
# failing on a name that plainly exists. Permissions cannot bridge two different
# directories, which is why ownership is the property read and writability is
# not: write granted on the journal by ACL lets events through while the
# registry stays the wrong one.
#
# Absent journal directory is not a failure: a host that has never emitted an
# event, and a sandbox pointing event_journal_dir somewhere temporary, both
# arrive here legitimately.
#
# Args: $@ = the command line as invoked, quoted back in the suggested fix
# Returns: 0, or EC_PERMISSION
function __assert_registry_account() {
  # The journal dir is resolved by the events handler, which is otherwise loaded
  # lazily on the first emit — later than this check, which runs before any
  # command reads or creates anything.
  if ! declare -F __logic_journal_dir > /dev/null; then
    # shellcheck disable=SC1090
    source "$(__find_command_handler events.sh)" || return 0
  fi

  local journal_dir
  journal_dir="$(__logic_journal_dir)" || return 0

  [[ -d "$journal_dir" ]] || return 0

  local owner me
  owner="$(stat -c '%U' "$journal_dir" 2> /dev/null)" || owner=""
  me="$(id -un)"

  [[ -z "$owner" ]] || [[ "$owner" == "$me" ]] && return 0

  local invocation
  invocation="$(printf ' %q' "$@")"

  __print_error "The event journal at ${journal_dir} belongs to '${owner}', and this command is running as '${me}'"
  __print_error "This host's KGSM services run as '${owner}' and use that account's instances — '${me}' has a separate registry that none of them read"
  __print_error "Run the engine as that account: sudo -u ${owner} -H kgsm${invocation}"

  return $EC_PERMISSION
}

export -f __assert_registry_account

declare -g KGSM_SYSTEM_LOADED=1
export KGSM_SYSTEM_LOADED
