#!/usr/bin/env bash

# KGSM Pure Logic Layer - Interactive Wizards
#
# This module contains pure business logic functions for interactive wizard workflows.
# These functions orchestrate multi-step processes like installation, modification,
# and backup restoration with minimal I/O - delegating display to the UI layer.
#
# Exit Code Conventions:
# - 0: Success
# - Standard error codes: EC_INVALID_ARG, EC_MISSING_ARG, etc.
# - Custom wizard codes: EC_WIZARD_CANCELLED, EC_WIZARD_NO_SELECTION

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Prevent multiple sourcing
if [[ -n "${KGSM_LOGIC_WIZARDS_LOADED:-}" ]]; then
  return 0
fi
export KGSM_LOGIC_WIZARDS_LOADED=true

# =============================================================================
# BLUEPRINT RETRIEVAL
# =============================================================================

# Get list of all available blueprints
#
# Output:
#   Prints blueprint names to stdout (one per line)
#
# Returns:
#   0 on success
#   Error code on failure
#
# Example:
#   mapfile -t blueprints < <(__logic_get_blueprints)
function __logic_get_blueprints() {
  local blueprints_logic
  blueprints_logic=$(__find_command_handler blueprints.sh) || return $EC_FAILED_SOURCE

  # shellcheck disable=SC1090
  source "$blueprints_logic" || return $EC_FAILED_SOURCE

  __logic_list_blueprints
  return $?
}
export -f __logic_get_blueprints

# =============================================================================
# INSTANCE RETRIEVAL
# =============================================================================

# Load instances logic library for __logic_get_instances function
# This is sourced here so that all wizard functions can access instance operations
instances_logic=$(__find_command_handler instances.sh)
# shellcheck disable=SC1090
source "$instances_logic" || {
  echo "Failed to load instances logic library" >&2
  return $EC_FAILED_SOURCE
}

# Note: __logic_get_instances() is now provided by commands/handlers/instances.sh
# No wrapper needed - use the function directly

# =============================================================================
# INSTALLATION WIZARD
# =============================================================================

# Execute server installation with provided parameters
#
# Args:
#   $1 - blueprint_name
#   $2 - install_directory
#   $3 - version (optional, empty for latest)
#   $4 - instance_name (optional, empty for default)
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   __logic_wizard_install "factorio" "/opt/servers" "1.1.87" "production"
function __logic_wizard_install() {
  local blueprint_name="$1"
  local install_dir="$2"
  local version="$3"
  local instance_name="$4"

  # Validate required parameters
  if [[ -z "$blueprint_name" ]]; then
    return $EC_MISSING_ARG
  fi

  if [[ -z "$install_dir" ]]; then
    return $EC_MISSING_ARG
  fi

  # Source the install logic
  local install_logic
  install_logic=$(__find_command install.sh) || return $EC_FAILED_SOURCE

  # Build command arguments
  local install_args=("$install_logic" "$blueprint_name" --install-dir "$install_dir")
  [[ -n "$version" ]] && install_args+=(--version "$version")
  [[ -n "$instance_name" ]] && install_args+=(--name "$instance_name")

  # Execute installation
  "${install_args[@]}" >/dev/null 2>&1
  return $?
}
export -f __logic_wizard_install

# =============================================================================
# MODIFICATION WIZARD
# =============================================================================

# Build modification options based on instance configuration
#
# Args:
#   $1 - instance_name
#
# Output:
#   Prints modification options to stdout in format:
#     option_text|command_args
#   One per line
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   mapfile -t options < <(__logic_get_modify_options "factorio-01")
#   # Returns lines like:
#   # Enable systemd service|--add systemd
#   # Disable firewall rules|--remove ufw
function __logic_get_modify_options() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  # Validate instance exists and load configuration
  local instance_config_file
  instance_config_file=$(validate_instance_name "$instance_name" 2>/dev/null)
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Source the instance configuration
  # shellcheck disable=SC1090
  source "$instance_config_file" || return $EC_FAILED_SOURCE

  # Build modification options based on current state
  if [[ "$instance_enable_systemd" == "true" ]]; then
    echo "Disable systemd service|--remove systemd"
  else
    echo "Enable systemd service|--add systemd"
  fi

  if [[ "$instance_enable_firewall_management" == "true" ]]; then
    echo "Disable firewall rules|--remove ufw"
  else
    echo "Enable firewall rules|--add ufw"
  fi

  if [[ "$instance_enable_command_shortcuts" == "true" ]]; then
    echo "Remove command shortcuts|--remove symlink"
  else
    echo "Create command shortcuts|--add symlink"
  fi

  if [[ "${instance_enable_port_forwarding:-false}" == "true" ]]; then
    echo "Disable UPnP port forwarding|--remove upnp"
  else
    echo "Enable UPnP port forwarding|--add upnp"
  fi

  return 0
}
export -f __logic_get_modify_options

# Execute instance modification
#
# Args:
#   $1 - instance_name
#   $2 - modification_command (e.g., "--add systemd", "--remove ufw")
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   __logic_wizard_modify "factorio-01" "--add systemd"
function __logic_wizard_modify() {
  local instance_name="$1"
  local modification_command="$2"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  if [[ -z "$modification_command" ]]; then
    return $EC_MISSING_ARG
  fi

  # Source the instances module
  local instances_module
  instances_module=$(__find_command instances.sh) || return $EC_FAILED_SOURCE

  # Execute modification
  # shellcheck disable=SC2086
  "$instances_module" "$instance_name" --modify $modification_command >/dev/null 2>&1
  return $?
}
export -f __logic_wizard_modify

# =============================================================================
# LIFECYCLE OPERATIONS
# =============================================================================

# Start an instance
#
# Args:
#   $1 - instance_name
#
# Returns:
#   Exit code from lifecycle operation
#
# Example:
#   __logic_wizard_start_instance "factorio-01"
function __logic_wizard_start_instance() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  local lifecycle_logic
  lifecycle_logic=$(__find_command_handler lifecycle.sh) || return $EC_FAILED_SOURCE

  # shellcheck disable=SC1090
  source "$lifecycle_logic" || return $EC_FAILED_SOURCE

  __logic_instance_start "$instance_name"
  return $?
}
export -f __logic_wizard_start_instance

# Stop an instance
#
# Args:
#   $1 - instance_name
#
# Returns:
#   Exit code from lifecycle operation
#
# Example:
#   __logic_wizard_stop_instance "factorio-01"
function __logic_wizard_stop_instance() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  local lifecycle_logic
  lifecycle_logic=$(__find_command_handler lifecycle.sh) || return $EC_FAILED_SOURCE

  # shellcheck disable=SC1090
  source "$lifecycle_logic" || return $EC_FAILED_SOURCE

  __logic_instance_stop "$instance_name"
  return $?
}
export -f __logic_wizard_stop_instance

# Restart an instance
#
# Args:
#   $1 - instance_name
#
# Returns:
#   Exit code from lifecycle operation
#
# Example:
#   __logic_wizard_restart_instance "factorio-01"
function __logic_wizard_restart_instance() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  local lifecycle_logic
  lifecycle_logic=$(__find_command_handler lifecycle.sh) || return $EC_FAILED_SOURCE

  # shellcheck disable=SC1090
  source "$lifecycle_logic" || return $EC_FAILED_SOURCE

  __logic_instance_restart "$instance_name"
  return $?
}
export -f __logic_wizard_restart_instance

# Get instance status
#
# Args:
#   $1 - instance_name
#   $2 - json_format (optional, "true" for JSON output)
#   $3 - fast_mode (optional, "true" to skip update check)
#
# Returns:
#   Exit code from lifecycle operation
#
# Example:
#   __logic_wizard_instance_status "factorio-01" "" "true"
function __logic_wizard_instance_status() {
  local instance_name="$1"
  local json_format="$2"
  local fast_mode="$3"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  local lifecycle_logic
  lifecycle_logic=$(__find_command_handler lifecycle.sh) || return $EC_FAILED_SOURCE

  # shellcheck disable=SC1090
  source "$lifecycle_logic" || return $EC_FAILED_SOURCE

  __logic_instance_status "$instance_name" "$json_format" "$fast_mode"
  return $?
}
export -f __logic_wizard_instance_status

# Get instance logs
#
# Args:
#   $1 - instance_name
#   $2 - follow_flag ("true" to follow logs)
#   $3 - line_count (number of lines to show)
#
# Returns:
#   Exit code from lifecycle operation
#
# Example:
#   __logic_wizard_instance_logs "factorio-01" "false" "50"
function __logic_wizard_instance_logs() {
  local instance_name="$1"
  local follow_flag="$2"
  local line_count="$3"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  local lifecycle_logic
  lifecycle_logic=$(__find_command_handler lifecycle.sh) || return $EC_FAILED_SOURCE

  # shellcheck disable=SC1090
  source "$lifecycle_logic" || return $EC_FAILED_SOURCE

  __logic_instance_logs "$instance_name" "$follow_flag" "$line_count"
  return $?
}
export -f __logic_wizard_instance_logs

# =============================================================================
# BACKUP OPERATIONS
# =============================================================================

# Get list of backups for an instance
#
# Args:
#   $1 - instance_name
#
# Output:
#   Prints backup names to stdout (one per line)
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   mapfile -t backups < <(__logic_get_instance_backups "factorio-01")
function __logic_get_instance_backups() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  # Validate instance and get configuration
  local instance_config_file
  instance_config_file=$(validate_instance_name "$instance_name" 2>/dev/null)
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    return $exit_code
  fi

  # Source the instance configuration
  # shellcheck disable=SC1090
  source "$instance_config_file" || return $EC_FAILED_SOURCE

  # Get backups using management file
  if [[ -z "$instance_management_file" ]] || [[ ! -f "$instance_management_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  "$instance_management_file" --list-backups 2>/dev/null
  return $?
}
export -f __logic_get_instance_backups

# Restore backup for an instance
#
# Args:
#   $1 - instance_name
#   $2 - backup_name
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   __logic_wizard_restore_backup "factorio-01" "backup-2025-01-15.tar.gz"
function __logic_wizard_restore_backup() {
  local instance_name="$1"
  local backup_name="$2"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  if [[ -z "$backup_name" ]]; then
    return $EC_MISSING_ARG
  fi

  # Source the instances module
  local instances_module
  instances_module=$(__find_command instances.sh) || return $EC_FAILED_SOURCE

  # Execute restore
  "$instances_module" "$instance_name" --restore-backup "$backup_name" >/dev/null 2>&1
  return $?
}
export -f __logic_wizard_restore_backup

# Create backup for an instance
#
# Args:
#   $1 - instance_name
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   __logic_wizard_create_backup "factorio-01"
function __logic_wizard_create_backup() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  # Source the instances module
  local instances_module
  instances_module=$(__find_command instances.sh) || return $EC_FAILED_SOURCE

  # Execute backup creation
  "$instances_module" "$instance_name" --create-backup >/dev/null 2>&1
  return $?
}
export -f __logic_wizard_create_backup

# Check for instance updates
#
# Args:
#   $1 - instance_name
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   __logic_wizard_check_update "factorio-01"
function __logic_wizard_check_update() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  # Source the instances module
  local instances_module
  instances_module=$(__find_command instances.sh) || return $EC_FAILED_SOURCE

  # Execute update check
  "$instances_module" "$instance_name" --check-update >/dev/null 2>&1
  return $?
}
export -f __logic_wizard_check_update

# Update an instance
#
# Args:
#   $1 - instance_name
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   __logic_wizard_update_instance "factorio-01"
function __logic_wizard_update_instance() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  # Source the instances module
  local instances_module
  instances_module=$(__find_command instances.sh) || return $EC_FAILED_SOURCE

  # Execute update
  "$instances_module" "$instance_name" --update >/dev/null 2>&1
  return $?
}
export -f __logic_wizard_update_instance

# Uninstall an instance
#
# Args:
#   $1 - instance_name
#
# Returns:
#   0 on success
#   Error codes on failure
#
# Example:
#   __logic_wizard_uninstall_instance "factorio-01"
function __logic_wizard_uninstall_instance() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return $EC_MISSING_ARG
  fi

  # Source the uninstall module
  local uninstall_module
  uninstall_module=$(__find_command uninstall.sh) || return $EC_FAILED_SOURCE

  # Execute uninstall
  "$uninstall_module" "$instance_name" >/dev/null 2>&1
  return $?
}
export -f __logic_wizard_uninstall_instance

# =============================================================================
# SYSTEM INFORMATION
# =============================================================================

# Get KGSM version
#
# Output:
#   Prints version string to stdout
#
# Returns:
#   0 on success
#
# Example:
#   version=$(__logic_get_kgsm_version)
function __logic_get_kgsm_version() {
  "$KGSM_ROOT/installer.sh" --version 2>/dev/null || echo "Unknown"
  return 0
}
export -f __logic_get_kgsm_version

# Get system overview (instance and blueprint counts)
#
# Output:
#   Prints data in format:
#     instances:N
#     blueprints:M
#
# Returns:
#   0 on success
#
# Example:
#   overview=$(__logic_get_system_overview)
function __logic_get_system_overview() {
  local instances_count=0
  local blueprints_count=0

  # Get instance count
  instances_count=$(__logic_get_instances 2>/dev/null | wc -l)

  # Get blueprint count
  blueprints_count=$(__logic_get_blueprints 2>/dev/null | wc -l)

  echo "instances:$instances_count"
  echo "blueprints:$blueprints_count"

  return 0
}
export -f __logic_get_system_overview
