#!/usr/bin/env bash
# Migration: 011 - Instance clock work is one maintenance-window list
# From schema: 10 ([instance_defaults] carries default_library)
# To schema: 11 ([instance_defaults] carries instance_maintenance_windows)
#
# A maintenance window is one appointment plus the ordered tasks it runs, written
# <schedule>/<tasks> and joined with ';'. `instance_maintenance_windows` seeds a
# newly created instance's own list; empty means no maintenance, which is the
# default a host keeps until somebody asks for some.
#
# The two announcement keys are named for the window they belong to, and an
# operator's own wording is carried across on the rename rather than reset to the
# shipped default.
#
# Idempotent: a config that already carries the key is only bumped to v11, and a
# rename whose target is already in place is left alone.

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

  if grep -qE '^[[:space:]]*instance_maintenance_windows=' "$config_file"; then
    __print_info "instance_maintenance_windows already present, nothing to add"
    __rename_announcement_keys "$config_file"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v10 to v11 (maintenance windows)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v11.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  if ! __add_maintenance_windows "$config_file"; then
    __print_error "Failed to add instance_maintenance_windows"
    mv "${config_file}.pre-migration-v11.bak" "$config_file"
    return 1
  fi

  if ! __rename_announcement_keys "$config_file"; then
    __print_error "Failed to rename the announcement keys"
    mv "${config_file}.pre-migration-v11.bak" "$config_file"
    return 1
  fi

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v11.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v11 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v11.bak"
  return 0
}

# Append the documented key to [instance_defaults], creating the section when a
# config predates it. Appending to the end of the section is enough: the loader
# flattens keys per section, and order within a section carries no meaning.
function __add_maintenance_windows() {
  local config_file="$1"

  local block
  block=$(
    cat <<'EOF'

# MAINTENANCE WINDOWS
# What should a new instance do on a clock?
# A ';'-joined list of windows, each written <schedule>/<tasks> — a schedule is
# either an appointment (daily@HH:MM, weekly.<sun..sat>@HH:MM,
# monthly.<1-31>@HH:MM, read in the instance's timezone) or an interval
# (<n>m|h|d, 10m to 30d, aligned to the epoch), and the tasks are backup, update
# and restart, which always run in that order.
#
# Enforced by the kgsm-scheduler leaf; inert on hosts without it. Edit an
# existing instance with `kgsm instances config-set <instance>
# maintenance_windows=...`.
#
# Expected values:
#   A window list, e.g. daily@05:00/backup;weekly.sun@04:00/backup,update,restart
#
# Default: Empty (no maintenance)
instance_maintenance_windows=
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

# Point the two announcement keys at their current names, keeping whatever
# wording the operator had against them. A key whose new name is already in the
# file is left where it is, so running this twice changes nothing.
function __rename_announcement_keys() {
  local config_file="$1"

  local -a pairs=(
    "instance_announce_restart_message:instance_announce_maintenance_message"
    "instance_announce_restart_cancelled_message:instance_announce_maintenance_cancelled_message"
  )

  local pair old new
  for pair in "${pairs[@]}"; do
    old="${pair%%:*}"
    new="${pair##*:}"

    if grep -qE "^[[:space:]]*${new}=" "$config_file"; then
      continue
    fi

    if ! grep -qE "^[[:space:]]*${old}=" "$config_file"; then
      continue
    fi

    if ! sed -i "s/^\([[:space:]]*\)${old}=/\1${new}=/" "$config_file"; then
      return 1
    fi
  done

  # The comment above them names the thing they announce.
  sed -i 's/^# Announcement lead times before a scheduled restart, comma-separated minutes$/# Announcement lead times before a maintenance window, comma-separated minutes/' "$config_file"

  return 0
}

# Set config_schema_version to 11 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=11/' "$config_file"
  else
    sed -i '1i config_schema_version=11' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
