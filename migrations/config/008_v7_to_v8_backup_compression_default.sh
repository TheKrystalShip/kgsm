#!/usr/bin/env bash
# Migration: 008 - Compress backups by default
# From schema: 7 (enable_backup_compression defaults to false)
# To schema: 8 (enable_backup_compression defaults to true)
#
# This migration RE-VALUES a key rather than adding or removing one, which makes
# it the exception among the migrations here — so the reasoning matters.
#
# A compressed backup is a single data.tar.gz with an sha256 digest recorded in
# its manifest. That digest is what _restore_backup verifies before it touches
# the instance, and the single artifact is what any consumer can hand over whole.
# An uncompressed backup is a data/ tree: there is no one digest to record (the
# manifest carries sha256: null), so a restore has nothing to verify against.
#
# An operator who wants uncompressed backups sets enable_backup_compression back
# to false; nothing re-applies this. Backups already on disk are untouched and
# stay restorable — the manifest records each backup's own `compressed` flag, so
# the two forms coexist and restore reads the flag rather than the config.
#
# Existing instances are NOT covered by this. Each instance baked
# compress_backups into its own .config.ini at creation time, and that copy is
# what its management script reads. Flip an existing instance with:
#   kgsm instances config-set <instance> compress_backups=true
#
# Idempotent: a config already carrying true is only bumped.

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

  # A config that never carried the key gets it from the merge against
  # config.default.ini, which now ships true — nothing to re-value here.
  if ! grep -qE '^[[:space:]]*enable_backup_compression=' "$config_file"; then
    __print_info "enable_backup_compression not present, nothing to re-value"
    __bump_schema_version "$config_file"
    return 0
  fi

  if grep -qE '^[[:space:]]*enable_backup_compression=[[:space:]]*true[[:space:]]*$' "$config_file"; then
    __print_info "Backup compression already enabled, nothing to change"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v7 to v8 (compress backups by default)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v8.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  if ! __enable_backup_compression "$config_file"; then
    __print_error "Failed to enable backup compression"
    mv "${config_file}.pre-migration-v8.bak" "$config_file"
    return 1
  fi

  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v8.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v8 complete"
  __print_info "Backups for existing instances stay uncompressed until each one is"
  __print_info "flipped: kgsm instances config-set <instance> compress_backups=true"
  __print_info "Backup saved as: ${config_file}.pre-migration-v8.bak"
  return 0
}

# Re-value the key and the "Default:" line documenting it, so the file does not
# claim a default it no longer has. Only the documented layout carries that
# comment; a hand-edited config just gets the key rewritten.
function __enable_backup_compression() {
  local config_file="$1"

  sed -i -E 's/^([[:space:]]*)enable_backup_compression=.*/\1enable_backup_compression=true/' \
    "$config_file" || return 1

  awk '
    /^[[:space:]]*#[[:space:]]*ENABLE BACKUP COMPRESSION[[:space:]]*$/ { in_block = 1 }
    in_block && /^[[:space:]]*enable_backup_compression=/ { in_block = 0 }
    in_block && /^[[:space:]]*#[[:space:]]*Default:[[:space:]]*false[[:space:]]*$/ {
      sub(/false[[:space:]]*$/, "true"); print; next
    }
    { print }
  ' "$config_file" >"${config_file}.tmp" || {
    rm -f "${config_file}.tmp"
    return 1
  }

  mv "${config_file}.tmp" "$config_file"
}

# Set config_schema_version to 8 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=8/' "$config_file"
  else
    sed -i '1i config_schema_version=8' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
