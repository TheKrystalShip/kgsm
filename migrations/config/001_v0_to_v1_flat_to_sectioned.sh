#!/usr/bin/env bash
# Migration: 001 - Convert flat config to sectioned format
# From schema: 0 (flat/no version)
# To schema: 1 (sectioned)
#
# This migration converts the flat key=value config format used in KGSM v2.x
# to the sectioned INI format introduced in KGSM v3.0.

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

  __print_info "Migrating config from flat (v0) to sectioned format (v1)..."

  # Create temporary file for new format
  local temp_file="${config_file}.migrating.$$"

  # Check if config already has schema version (already migrated)
  if grep -q "^config_schema_version=" "$config_file"; then
    local existing_version
    existing_version=$(grep "^config_schema_version=" "$config_file" | cut -d= -f2)
    if [[ "$existing_version" -ge 1 ]]; then
      __print_info "Config already at schema version $existing_version, skipping migration"
      return 0
    fi
  fi

  # Start building new config
  cat > "$temp_file" << 'EOF'
# ============================================================================
# KGSM - Krystal Game Server Manager
# Configuration File
# ============================================================================
#
# This is the main configuration file for the Krystal Game Server Manager.
# You can customize your KGSM installation by modifying the settings below.
#
# IMPORTANT NOTES:
#  - All settings can also be set as environment variables
#  - Uncommented values in this file override environment variables
#  - Use '#' for comments to maintain bash script compatibility
#  - All paths should be absolute unless otherwise specified
#
# ============================================================================

config_schema_version=1

[system]
EOF

  # Migrate system section keys
  __migrate_key "$config_file" "$temp_file" "update_channel" "main"
  __migrate_key "$config_file" "$temp_file" "auto_update_check" "false"
  __migrate_key "$config_file" "$temp_file" "wget_timeout_seconds" "60"
  __migrate_key "$config_file" "$temp_file" "enable_logging" "false"
  __migrate_key "$config_file" "$temp_file" "log_max_size_kb" "10240"

  cat >> "$temp_file" << 'EOF'

[steam]
EOF

  # Migrate steam section keys
  __migrate_key "$config_file" "$temp_file" "STEAM_USERNAME" ""
  __migrate_key "$config_file" "$temp_file" "STEAM_PASSWORD" ""

  cat >> "$temp_file" << 'EOF'

[services]
EOF

  # Migrate services section keys
  __migrate_key "$config_file" "$temp_file" "enable_systemd" "false"
  __migrate_key "$config_file" "$temp_file" "systemd_files_dir" "/etc/systemd/system"

  cat >> "$temp_file" << 'EOF'

[network]
EOF

  # Migrate network section keys
  __migrate_key "$config_file" "$temp_file" "enable_firewall_management" "false"
  __migrate_key "$config_file" "$temp_file" "firewall_rules_dir" "/etc/ufw/applications.d"
  __migrate_key "$config_file" "$temp_file" "enable_port_forwarding" "false"

  cat >> "$temp_file" << 'EOF'

[events]
EOF

  # Migrate events section keys
  __migrate_key "$config_file" "$temp_file" "enable_event_broadcasting" "false"
  __migrate_key "$config_file" "$temp_file" "event_socket_filenames" "kgsm.sock"
  __migrate_key "$config_file" "$temp_file" "enable_webhook_events" "false"
  __migrate_key "$config_file" "$temp_file" "webhook_urls" ""
  __migrate_key "$config_file" "$temp_file" "webhook_timeout_seconds" "10"
  __migrate_key "$config_file" "$temp_file" "webhook_retry_count" "2"
  __migrate_key "$config_file" "$temp_file" "webhook_secret" ""

  cat >> "$temp_file" << 'EOF'

[watchers]
EOF

  # Migrate watchers section keys
  __migrate_key "$config_file" "$temp_file" "enable_watcher" "false"
  __migrate_key "$config_file" "$temp_file" "watcher_global_timeout_seconds" "600"
  __migrate_key "$config_file" "$temp_file" "watcher_ports_check_interval_seconds" "5"

  cat >> "$temp_file" << 'EOF'

[instance_defaults]
EOF

  # Migrate instance_defaults section keys
  __migrate_key "$config_file" "$temp_file" "default_install_directory" ""
  __migrate_key "$config_file" "$temp_file" "instance_suffix_length" "2"
  __migrate_key "$config_file" "$temp_file" "enable_backup_compression" "false"
  __migrate_key "$config_file" "$temp_file" "instance_save_command_timeout_seconds" "5"
  __migrate_key "$config_file" "$temp_file" "instance_stop_command_timeout_seconds" "30"
  __migrate_key "$config_file" "$temp_file" "instance_auto_update_before_start" "false"

  cat >> "$temp_file" << 'EOF'

[accessibility]
EOF

  # Migrate accessibility section keys
  __migrate_key "$config_file" "$temp_file" "enable_command_shortcuts" "false"
  __migrate_key "$config_file" "$temp_file" "command_shortcuts_directory" "/usr/local/bin"

  # Atomic replace - create backup first
  if ! cp "$config_file" "${config_file}.pre-migration-v1.bak"; then
    __print_error "Failed to create backup before migration"
    rm -f "$temp_file"
    return 1
  fi

  if ! mv "$temp_file" "$config_file"; then
    __print_error "Failed to replace config file"
    # Restore from backup
    mv "${config_file}.pre-migration-v1.bak" "$config_file"
    return 1
  fi

  __print_success "Migration to schema v1 complete"
  __print_info "Backup saved as: ${config_file}.pre-migration-v1.bak"
  return 0
}

# Helper function to migrate a single key
function __migrate_key() {
  local source="$1"
  local dest="$2"
  local key="$3"
  local default_value="$4"

  # Try to extract value from source config
  local value
  value=$(grep "^${key}=" "$source" 2>/dev/null | cut -d= -f2- | head -1)

  # If key exists in source, use that value; otherwise use default
  if [[ -n "$value" ]] || grep -q "^${key}=" "$source" 2>/dev/null; then
    echo "${key}=${value}" >> "$dest"
  elif [[ -n "$default_value" ]]; then
    echo "${key}=${default_value}" >> "$dest"
  else
    echo "${key}=" >> "$dest"
  fi
}

# Execute migration if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  migrate "$@"
  exit $?
fi
