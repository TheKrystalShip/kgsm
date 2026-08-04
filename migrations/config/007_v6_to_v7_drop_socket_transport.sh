#!/usr/bin/env bash
# Migration: 007 - Drop the event socket transport
# From schema: 6 ([events] carries the journal keys alongside the socket keys)
# To schema: 7 ([events] carries the journal and webhook keys only)
#
# The journal is the event transport, and every consumer reads it. The socket
# fan-out delivered a second copy to a list of paths the engine had to be
# configured with — the coupling the journal exists to remove — so the module
# and both of its keys go together.
#
# enable_socket_events and event_socket_filenames are REMOVED rather than
# commented out: a dead switch left in the file invites an operator to set it
# and expect events to be delivered somewhere.
#
# The webhook transport is untouched. It is an optional outbound copy that
# never carried the consumer-registry problem.
#
# Idempotent: a config that no longer carries either key is only bumped.

# Disabling SC2086 globally
# shellcheck disable=SC2086

# Source bootstrap if available (for error codes and print functions)
if [[ -n "$KGSM_ROOT" ]] && [[ -f "$KGSM_ROOT/core/bootstrap.sh" ]]; then
  source "$KGSM_ROOT/core/bootstrap.sh"
else
  # Fallback print functions if bootstrap not available
  __print_info() { echo "INFO: $*"; }
  __print_error() { echo "ERROR: $*" >&2; }
  __print_success() { echo "SUCCESS: $*"; }
fi

function migrate() {
  local config_file="$1"

  if [[ -z "$config_file" ]]; then
    __print_error "Config file path must be provided"
    return 1
  fi

  if [[ ! -f "$config_file" ]]; then
    __print_error "Config file not found: $config_file"
    return 1
  fi

  if ! grep -qE '^[[:space:]]*(enable_socket_events|event_socket_filenames)=' "$config_file"; then
    __print_info "Socket transport keys already absent, nothing to change"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v6 to v7 (drop the socket transport)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v7.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  if ! __remove_socket_keys "$config_file"; then
    __print_error "Failed to remove the socket transport keys"
    mv "${config_file}.pre-migration-v7.bak" "$config_file"
    return 1
  fi

  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v7.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v7 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v7.bak"
  return 0
}

# Drop both socket keys and the comment blocks documenting them, mirroring 006's
# removal of enable_event_broadcasting: skip from a known header until the key
# line it documents, then fall back to a direct delete for a config whose layout
# was hand-edited away from the documented one.
function __remove_socket_keys() {
  local config_file="$1"

  local tmp
  tmp=$(mktemp) || return 1

  awk '
    /^[[:space:]]*#[[:space:]]*ENABLE SOCKET EVENTS[[:space:]]*$/ { skipping = 1; next }
    /^[[:space:]]*#[[:space:]]*EVENT SOCKET NAMES[[:space:]]*$/   { skipping = 1; next }
    skipping && /^[[:space:]]*#/ { next }
    skipping && /^[[:space:]]*(enable_socket_events|event_socket_filenames)=/ { skipping = 0; next }
    skipping && /^[[:space:]]*$/ { next }
    { skipping = 0; print }
  ' "$config_file" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }

  sed -i -E '/^[[:space:]]*(enable_socket_events|event_socket_filenames)=/d' "$tmp" || {
    rm -f "$tmp"
    return 1
  }

  mv "$tmp" "$config_file"
}

# Set config_schema_version to 7 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=7/' "$config_file"
  else
    sed -i '1i config_schema_version=7' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
