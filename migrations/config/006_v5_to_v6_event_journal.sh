#!/usr/bin/env bash
# Migration: 006 - Event journal replaces the socket fan-out
# From schema: 5 ([instance_defaults] carries backups_directory)
# To schema: 6 ([events] carries the journal keys, no broadcasting switch)
#
# KGSM appends events to a journal and knows nothing about who reads them, so
# the engine no longer holds a list of consumer sockets. This adds
# event_journal_dir and event_journal_retention_days, and removes
# enable_event_broadcasting: emission is unconditional because the journal is
# the audit record, and an audit trail that can be silently switched off is
# worse than none.
#
# enable_socket_events and event_socket_filenames are deliberately LEFT IN
# PLACE — the socket transport still runs alongside the journal, and its keys
# retire with it.
#
# Idempotent: a config that already carries the journal keys is only bumped.

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

  if grep -qE '^[[:space:]]*event_journal_dir=' "$config_file" &&
    ! grep -qE '^[[:space:]]*enable_event_broadcasting=' "$config_file"; then
    __print_info "Event journal keys already present, nothing to change"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v5 to v6 (event journal)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v6.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  if ! __add_journal_keys "$config_file"; then
    __print_error "Failed to add the event journal keys"
    mv "${config_file}.pre-migration-v6.bak" "$config_file"
    return 1
  fi

  if ! __remove_broadcasting_key "$config_file"; then
    __print_error "Failed to remove enable_event_broadcasting"
    mv "${config_file}.pre-migration-v6.bak" "$config_file"
    return 1
  fi

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v6.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v6 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v6.bak"
  return 0
}

# Append the documented journal keys to [events], creating the section when a
# config predates it. Appending to the end of the section is enough: the loader
# flattens keys per section, and order within a section carries no meaning.
function __add_journal_keys() {
  local config_file="$1"

  if grep -qE '^[[:space:]]*event_journal_dir=' "$config_file"; then
    return 0
  fi

  local block
  block=$(
    cat <<'EOF'

# EVENT JOURNAL DIRECTORY
# Where KGSM appends its event journal.
#
# The journal is KGSM's event transport and its audit record: one JSON line per
# event, in date-named segments (YYYY-MM-DD.ndjson) that sort chronologically.
# KGSM appends and knows nothing about who reads — consumers tail the segments
# at their own pace holding their own cursor, so adding or removing a consumer
# needs no change here.
#
# Emission is unconditional. There is deliberately no switch that turns the
# journal off: it is the audit record, and an audit trail that can be silently
# disabled is worse than no audit trail at all.
#
# Expected values:
#   An absolute path, or a path starting with ~ (expanded to $HOME)
#
# Default: /var/lib/kgsm/events
event_journal_dir=/var/lib/kgsm/events

# EVENT JOURNAL RETENTION
# How many days of journal segments to keep.
#
# `events journal prune` deletes segments older than this. Retention is
# time-based only and never consults a consumer — KGSM holds no knowledge of
# who reads the journal, which is the point of the design. A consumer absent
# longer than this window detects the gap and cold-starts.
#
# Keep this >= the retention of any index built from the journal (kgsm-monitor's
# event history), or rebuilding that index returns less than it held.
#
# Expected values:
#   A positive integer (days)
#
# Default: 90
event_journal_retention_days=90
EOF
  )

  if ! grep -q '^\[events\]' "$config_file"; then
    printf '\n[events]\n%s\n' "$block" >>"$config_file"
    return $?
  fi

  # Insert at the end of [events] — just before the next section header, or at
  # end-of-file when it is the last section.
  local next_section_line
  next_section_line=$(awk '
    /^\[events\]/ { found = 1; next }
    found && /^\[/ { print NR; exit }
  ' "$config_file")

  if [[ -z "$next_section_line" ]]; then
    printf '%s\n' "$block" >>"$config_file"
    return $?
  fi

  local tmp
  tmp=$(mktemp) || return 1
  {
    head -n "$((next_section_line - 1))" "$config_file"
    printf '%s\n' "$block"
    tail -n "+${next_section_line}" "$config_file"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }

  mv "$tmp" "$config_file"
}

# Drop enable_event_broadcasting and the comment block documenting it. The key
# is removed rather than commented out: leaving a dead switch in the file
# invites an operator to set it and expect events to stop.
function __remove_broadcasting_key() {
  local config_file="$1"

  if ! grep -qE '^[[:space:]]*enable_event_broadcasting=' "$config_file"; then
    return 0
  fi

  local tmp
  tmp=$(mktemp) || return 1

  # Drop the key line, then any "# ENABLE EVENT BROADCASTING" header and the
  # contiguous comment lines beneath it.
  awk '
    /^[[:space:]]*#[[:space:]]*ENABLE EVENT BROADCASTING[[:space:]]*$/ {
      skipping = 1
      next
    }
    skipping && /^[[:space:]]*#/ { next }
    skipping && /^[[:space:]]*enable_event_broadcasting=/ {
      skipping = 0
      next
    }
    skipping && /^[[:space:]]*$/ { next }
    { skipping = 0; print }
  ' "$config_file" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }

  # Belt and braces: remove the key wherever it survived a non-standard layout.
  sed -i '/^[[:space:]]*enable_event_broadcasting=/d' "$tmp" || {
    rm -f "$tmp"
    return 1
  }

  mv "$tmp" "$config_file"
}

# Set config_schema_version to 6 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=6/' "$config_file"
  else
    sed -i '1i config_schema_version=6' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
