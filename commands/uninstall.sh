#!/usr/bin/env bash

# KGSM Uninstall Module
#
# Orchestrates the removal of a game server instance across multiple modules
# (files, directories, instances). This module handles the complete uninstallation
# workflow ensuring all instance components are properly removed.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# =============================================================================
# HELP / USAGE FUNCTIONS
# =============================================================================

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Uninstall Module for Krystal Game Server Manager${END}

Remove a game server instance and all associated files.

${UNDERLINE}Usage:${END}
  ${self} <instance> [options]

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name to uninstall

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  ${self} factorio-01
  ${self} my-server --help

${UNDERLINE}Warning:${END}
  This operation is irreversible. All instance data, configuration,
  and associated files will be permanently removed.
"
}

function _uninstall() {
  local instance=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
        break
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    show_usage
    return $EC_MISSING_ARG
  fi

  # Validate instance exists before proceeding and resolve blueprint name
  local instance_config_file
  if ! instance_config_file=$(validate_instance_name "$instance"); then
    __print_error "Instance '$instance' not found"
    return $EC_INSTANCE_NOT_FOUND
  fi

  # Extract blueprint name from config file path before any destructive operations
  # Path structure: $KGSM_INSTANCES_DIR/<blueprint>/<instance>/<instance>.config.ini
  local blueprint_name
  blueprint_name="$(basename "$(dirname "$(dirname "$instance_config_file")")")" || {
    __print_error "Failed to determine blueprint name for instance '$instance'"
    return $EC_GENERAL
  }

  # Warning message about destructive operation
  __print_warning "This operation is destructive and irreversible."
  echo ""
  echo "The following will be permanently deleted:"
  echo "  - Installation files"
  echo "  - Server logs"
  echo "  - World saves and backups"
  echo "  - All configuration files"
  echo "  - Associated system files (firewall rules, symlinks, etc.)"
  echo ""

  # Confirmation prompt
  read -rp "Are you sure you want to uninstall instance '$instance'? (y/N): " confirmation

  if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    __print_info "Uninstall cancelled"
    return 0
  fi

  __print_info "Uninstalling instance '$instance'..."

  events.sh emit instance-uninstall-started "${instance}"

  # Remove instance files (firewall, symlinks, etc.)
  files.sh remove "$instance" || {
    __print_warning "Failed to remove some instance files"
    # Continue with uninstall even if file removal fails
  }

  # Remove directory structure
  directories.sh remove "$instance" || {
    exit_code=$?
    __print_error "Failed to remove instance directories"
    events.sh emit instance-uninstall-failed "${instance}"
    return $exit_code
  }

  # Remove KGSM's reference to the instance (symlink in instances directory)
  directories.sh unlink-instance "$blueprint_name" "$instance" || {
    exit_code=$?
    __print_error "Failed to unlink instance directories (may be already unlinked)"
    return $exit_code
  }

  events.sh emit instance-uninstall-finished "${instance}"

  __print_success "Instance '${instance}' uninstalled"

  events.sh emit instance-uninstalled "${instance}"

  return 0
}

# Parse command
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h | --help | help)
      show_usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
  shift
done

# Execute uninstallation
_uninstall "$@"
exit $?
