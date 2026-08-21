#!/usr/bin/env bash
# Migration: 009 - Add [resources] section for the memory gate
# From schema: 8
# To schema: 9 (sectioned + [resources])
#
# Additive migration: introduces the two keys that decide whether KGSM refuses to
# start an instance the node has no room for. Existing values are untouched; only
# the new section and the schema version are added.
#
# Both keys are read by kgsm AND by kgsm-watchdog. The CLI is not the only thing
# that starts instances — the watchdog starts them at boot and after a crash,
# never passing through kgsm — so this one file is what gives the host a single
# answer instead of two that can disagree.
#
# Without this migration the gate still runs: kgsm and the watchdog both fall back
# to the same coded defaults (on, 1024MB). What an operator loses is the ability to
# tune or disable it, and the documentation of what the keys mean.

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

  # Idempotency: if the [resources] section already exists, ensure the version is
  # current and stop — re-running must be safe.
  if grep -q "^\[resources\]" "$config_file"; then
    __print_info "[resources] section already present, skipping migration"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v8 to v9 (adding [resources] section)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v9.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v9.bak" "$config_file"
    return 1
  fi

  # Append the new [resources] section with defaults. A subsequent `config merge`
  # re-derives section ordering from config.default.ini, so trailing placement
  # here is fine.
  cat >> "$config_file" << 'EOF'

[resources]
# ENABLE THE MEMORY GATE
# Should KGSM refuse to start an instance the node does not have room for?
#
# A node driven into the OOM killer loses whichever process the kernel picks,
# which may be a different game server than the one that asked for the memory —
# or the watchdog supervising all of them. A refused start is the cheaper outcome.
#
# Read by BOTH kgsm and kgsm-watchdog, so turning it off here turns it off for
# the boot autostart and the crash-restart too.
#
# Default: true
enable_memory_gate=true

# MEMORY GATE HEADROOM
# How many megabytes must remain available AFTER an instance starts.
#
#   MemAvailable - required >= memory_gate_headroom_mb
#
# "required" is the instance's own memory_cap_mb when set, otherwise the
# blueprint's advisory metadata.min_ram_mb. With neither declared the check
# cannot run and the start proceeds — an undeclared figure is never invented.
#
# Default: 1024
memory_gate_headroom_mb=1024
EOF

  __print_success "Migration to schema v9 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v9.bak"
  return 0
}

# Set config_schema_version to 9 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=9/' "$config_file"
  else
    sed -i '1i config_schema_version=9' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
