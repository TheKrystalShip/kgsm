#!/usr/bin/env bash
# Migration: 002 - Add [cgroup] section for cgroup v2 supervision
# From schema: 1 (sectioned)
# To schema: 2 (sectioned + [cgroup])
#
# Additive migration: introduces the [cgroup] section that configures native
# cgroup v2 process supervision (see `kgsm system setup-cgroups`). Existing
# values are untouched; only the new section and the schema version are added.

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

  # Idempotency: if the [cgroup] section already exists, ensure the version is
  # current and stop — re-running must be safe.
  if grep -q "^\[cgroup\]" "$config_file"; then
    __print_info "[cgroup] section already present, skipping migration"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v1 to v2 (adding [cgroup] section)..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v2.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v2.bak" "$config_file"
    return 1
  fi

  # Append the new [cgroup] section with defaults. A subsequent `config merge`
  # re-derives section ordering from config.default.ini, so trailing placement
  # here is fine.
  cat >> "$config_file" << 'EOF'

[cgroup]
# ENABLE CGROUP SUPERVISION
# Should KGSM supervise native game-server instances using cgroup v2?
# When enabled, each native instance is spawned into a kernel-tracked cgroup so
# that crash detection, whole-process-tree teardown, and accurate per-instance
# metrics work without systemd. The cgroup base must be prepared once with
# 'kgsm system setup-cgroups' (requires privilege).
#
# Default: true
enable_cgroups=true

# CGROUP MOUNT POINT
# Where is the cgroup v2 unified hierarchy mounted?
#
# Default: /sys/fs/cgroup
cgroup_mount_point=/sys/fs/cgroup

# CGROUP BASE NAME
# The name of KGSM's delegated cgroup base, created under the mount point.
#
# Default: kgsm.slice
cgroup_base_name=kgsm.slice

# CGROUP CONTROLLERS
# Which cgroup controllers should be enabled for KGSM's instances?
#
# Default: cpu memory io pids
cgroup_controllers=cpu memory io pids
EOF

  __print_success "Migration to schema v2 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v2.bak"
  return 0
}

# Set config_schema_version to 2 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=2/' "$config_file"
  else
    sed -i '1i config_schema_version=2' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
