#!/usr/bin/env bash
# Migration: 005 - Add the backups_directory key to [instance_defaults]
# From schema: 4 (cgroup_base_name = the delegated kgsm.slice/kgsm-watchdog.service)
# To schema: 5 ([instance_defaults] carries backups_directory)
#
# Instance backups live outside every instance's working directory, in a per-instance
# subdirectory of one root, so that uninstalling an instance cannot destroy its
# backups. `backups_directory` overrides that root; empty means the XDG default
# ($XDG_DATA_HOME/kgsm/backups). This adds the key, left empty, so the operator can
# see and set it.
#
# Idempotent: a config that already carries the key is only bumped to v5.

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

  if grep -qE '^[[:space:]]*backups_directory=' "$config_file"; then
    __print_info "backups_directory already present, nothing to add"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v4 to v5 (adding backups_directory)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v5.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  if ! __add_backups_directory "$config_file"; then
    __print_error "Failed to add backups_directory"
    mv "${config_file}.pre-migration-v5.bak" "$config_file"
    return 1
  fi

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v5.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v5 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v5.bak"
  return 0
}

# Append the documented key to [instance_defaults], creating the section when a
# config predates it. Appending to the end of the section is enough: the loader
# flattens keys per section, and order within a section carries no meaning.
function __add_backups_directory() {
  local config_file="$1"

  local block
  block=$(
    cat <<'EOF'

# BACKUPS DIRECTORY
# Where should KGSM keep instance backups?
# Backups are stored outside every instance's working directory, in a
# per-instance subdirectory of this root, so that uninstalling an instance
# never destroys its backups. Point this at another filesystem or a mounted
# volume to keep backups off the disk that holds the game servers.
#
# Expected values:
#   Absolute path to a writable directory (leave empty for the default)
#
# Default: Empty ($XDG_DATA_HOME/kgsm/backups, i.e. ~/.local/share/kgsm/backups)
backups_directory=
EOF
  )

  if ! grep -q '^\[instance_defaults\]' "$config_file"; then
    printf '\n[instance_defaults]\n%s\n' "$block" >>"$config_file"
    return $?
  fi

  # Insert at the end of [instance_defaults] — just before the next section
  # header, or at end-of-file when it is the last section.
  local next_section_line
  next_section_line=$(awk '
    /^\[instance_defaults\]/ { found = 1; next }
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

# Set config_schema_version to 5 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=5/' "$config_file"
  else
    sed -i '1i config_schema_version=5' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
