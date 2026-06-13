#!/usr/bin/env bash
# Migration: 003 - Remove the [services] section (systemd integration retired)
# From schema: 2 (sectioned + [cgroup])
# To schema: 3 (sectioned + [cgroup], no [services])
#
# Removal migration: systemd is no longer a KGSM instance lifecycle manager (the
# kgsm-watchdog daemon supervises native instances and owns boot auto-start), so
# the [services] section and its keys (enable_systemd, systemd_files_dir) are
# obsolete. This strips the section in place. Idempotent: re-running on a config
# that already lacks [services] only ensures the schema version is current.

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

  # Idempotency: if there is no [services] section, just ensure the version is
  # current and stop — re-running must be safe.
  if ! grep -q "^\[services\]" "$config_file"; then
    __print_info "[services] section already absent, skipping removal"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v2 to v3 (removing [services] section)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v3.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  # Delete the [services] section: every line from its header up to (but not
  # including) the next "[section]" header, or to EOF if it is the last section.
  local tmp="${config_file}.migration-v3.tmp"
  if ! awk '
    /^\[services\]/ { in_section = 1; next }
    in_section && /^\[/ { in_section = 0 }
    !in_section { print }
  ' "$config_file" > "$tmp"; then
    __print_error "Failed to rewrite config without [services]"
    rm -f "$tmp"
    mv "${config_file}.pre-migration-v3.bak" "$config_file"
    return 1
  fi
  mv "$tmp" "$config_file"

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v3.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v3 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v3.bak"
  return 0
}

# Set config_schema_version to 3 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=3/' "$config_file"
  else
    sed -i '1i config_schema_version=3' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
