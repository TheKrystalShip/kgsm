#!/usr/bin/env bash
# Migration: 004 - Point the cgroup base at the watchdog's delegated service cgroup
# From schema: 3 (sectioned + [cgroup], no [services])
# To schema: 4 (cgroup_base_name = the delegated kgsm.slice/kgsm-watchdog.service)
#
# kgsm-watchdog now runs under systemd cgroup DELEGATION (PLAN Increment 8): systemd
# places it in kgsm.slice with Delegate=yes and hands it the
# kgsm.slice/kgsm-watchdog.service subtree, under which it creates each per-instance
# cgroup. The daemon manages that subtree below the service cgroup precisely because
# systemd reconciles a slice's OWN cgroup.subtree_control on every `daemon-reload`
# (which stripped the controllers off the old kgsm.slice/<inst> siblings and made
# per-server memory metrics read 0). kgsm derives the per-instance cgroup path it
# surfaces to kgsm-monitor (`cgroup_path`) from cgroup_base_name, so it must match the
# watchdog's delegated base or the monitor samples the wrong directory.
#
# This rewrites the OLD default (cgroup_base_name=kgsm.slice) to the delegated base.
# A value the operator has customised away from the old default is left untouched
# (they own the coupling). Idempotent: re-running only ensures the schema is current.

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

# The old default base, and the new delegated base it is rewritten to.
readonly OLD_BASE="kgsm.slice"
readonly NEW_BASE="kgsm.slice/kgsm-watchdog.service"

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

  # Idempotency / no-op cases: already delegated, key absent, or operator-customised.
  local current
  current="$(grep -E '^cgroup_base_name=' "$config_file" | tail -n1 | cut -d= -f2-)"

  if [[ -z "$current" ]]; then
    __print_info "cgroup_base_name not present, nothing to rewrite"
    __bump_schema_version "$config_file"
    return 0
  fi

  if [[ "$current" == "$NEW_BASE" ]]; then
    __print_info "cgroup_base_name already delegated ($NEW_BASE), skipping rewrite"
    __bump_schema_version "$config_file"
    return 0
  fi

  if [[ "$current" != "$OLD_BASE" ]]; then
    __print_info "cgroup_base_name is customised ($current); leaving it untouched"
    __bump_schema_version "$config_file"
    return 0
  fi

  __print_info "Migrating config from v3 to v4 (cgroup_base_name: ${OLD_BASE} -> ${NEW_BASE})..."

  # Backup before mutating
  if ! cp "$config_file" "${config_file}.pre-migration-v4.bak"; then
    __print_error "Failed to create backup before migration"
    return 1
  fi

  # Rewrite the base. Use '|' as the sed delimiter since the value contains '/'.
  if ! sed -i "s|^cgroup_base_name=.*|cgroup_base_name=${NEW_BASE}|" "$config_file"; then
    __print_error "Failed to rewrite cgroup_base_name"
    mv "${config_file}.pre-migration-v4.bak" "$config_file"
    return 1
  fi

  # Bump the schema version in place
  if ! __bump_schema_version "$config_file"; then
    __print_error "Failed to update schema version"
    mv "${config_file}.pre-migration-v4.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v4 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v4.bak"
  return 0
}

# Set config_schema_version to 4 (idempotent)
function __bump_schema_version() {
  local config_file="$1"

  if grep -q "^config_schema_version=" "$config_file"; then
    sed -i 's/^config_schema_version=.*/config_schema_version=4/' "$config_file"
  else
    sed -i '1i config_schema_version=4' "$config_file"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
