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
  -y, --force, --yes          Skip the confirmation prompt (for non-interactive
                              callers; the destructive intent is confirmed already)

${UNDERLINE}Examples:${END}
  ${self} factorio-01
  ${self} factorio-01 --force
  ${self} my-server --help

${UNDERLINE}Warning:${END}
  This operation is irreversible. All instance data, configuration,
  and associated files will be permanently removed.
"
}

function _uninstall() {
  local instance=""
  local force=0

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage
        return 0
        ;;
      --force | -y | --yes)
        # Skip the interactive confirmation — for non-interactive callers (kgsm-lib,
        # the API, the TUI wizard which already confirms). The destructive intent is
        # confirmed by the caller, not a TTY prompt.
        force=1
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
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

  # Warning + confirmation prompt — skipped when --force is given (a non-interactive
  # caller has already confirmed the destructive intent). A declined prompt returns a
  # non-zero EC_CANCELLED, never 0: a silent success on cancellation would let a
  # non-interactive caller (no TTY, no --force) believe the instance was removed.
  if [[ "$force" -ne 1 ]]; then
    __print_warning "This operation is destructive and irreversible."
    echo ""
    echo "The following will be permanently deleted:"
    echo "  - Installation files"
    echo "  - Server logs"
    echo "  - World saves and backups"
    echo "  - All configuration files"
    echo "  - Associated system files (firewall rules, symlinks, etc.)"
    echo ""

    read -rp "Are you sure you want to uninstall instance '$instance'? (y/N): " confirmation

    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
      __print_info "Uninstall cancelled"
      return $EC_CANCELLED
    fi
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
