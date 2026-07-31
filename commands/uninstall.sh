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

# Watchdog routing — an uninstalled instance must also be deregistered from the resident
# supervisor. Self-gates on the daemon's availability, so a host without one is unaffected.
if [[ -z "${KGSM_LOGIC_WATCHDOG_LOADED}" ]]; then
  # shellcheck source=handlers/watchdog.sh
  source "$(__find_command_handler watchdog.sh)" || exit $EC_FAILED_SOURCE
fi

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
  --purge-backups             Also delete the instance's backups. Without this,
                              backups are kept (they live outside the instance)

${UNDERLINE}Examples:${END}
  ${self} factorio-01
  ${self} factorio-01 --force
  ${self} factorio-01 --purge-backups
  ${self} my-server --help

${UNDERLINE}Warning:${END}
  This operation is irreversible. All instance data, configuration,
  and associated files will be permanently removed. Backups are kept
  unless --purge-backups is given.
"
}

function _uninstall() {
  local instance=""
  local force=0
  local purge_backups=0

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage
        return 0
        ;;
      --purge-backups)
        # Backups live outside the instance's working directory, so removing the
        # instance leaves them behind. This is the only way to delete them.
        purge_backups=1
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
  # The instance's backups live outside its working directory, so they survive the
  # uninstall unless --purge-backups is given. Resolve the store now, while the
  # instance config still exists, so both the prompt and the purge can name it.
  local backups_dir
  backups_dir="$(__get_config_value "$instance_config_file" "backups_dir" 2>/dev/null)"
  backups_dir="${backups_dir%\"}"
  backups_dir="${backups_dir#\"}"

  if [[ "$force" -ne 1 ]]; then
    __print_warning "This operation is destructive and irreversible."
    echo ""
    echo "The following will be permanently deleted:"
    echo "  - Installation files"
    echo "  - Server logs"
    echo "  - World saves"
    echo "  - All configuration files"
    echo "  - Associated system files (firewall rules, symlinks, etc.)"
    if [[ "$purge_backups" -eq 1 ]]; then
      echo "  - The instance's backups (--purge-backups)"
    elif [[ -n "$backups_dir" ]] && [[ -d "$backups_dir" ]]; then
      echo ""
      echo "Backups are KEPT in: $backups_dir"
      echo "Pass --purge-backups to delete them too."
    fi
    echo ""

    read -rp "Are you sure you want to uninstall instance '$instance'? (y/N): " confirmation

    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
      __print_info "Uninstall cancelled"
      return $EC_CANCELLED
    fi
  fi

  __print_info "Uninstalling instance '$instance'..."

  events.sh emit instance-uninstall-started "${instance}"

  # Deregister from the watchdog BEFORE any files are removed: the daemon stops the
  # instance as part of deregistering, and a graceful stop needs the instance's FIFO and
  # management script to still exist. Skipping this leaves the daemon supervising a server
  # whose files are gone — it restart-loops the missing install dir, and its state feeds a
  # permanent, unresolvable crash alert into every consumer of the daemon's instance list.
  #
  # An unreachable daemon is best-effort (a host without one must still be able to uninstall),
  # but an explicit refusal is fatal: it means the daemon could not stop the instance, so the
  # game is still running. Deleting a running server's files out from under it corrupts saves
  # and strands the process — abort and let the operator deal with it.
  if __watchdog_available; then
    __watchdog_deregister "$instance"
    case $? in
      0) ;;
      2)
        __print_error "Instance '$instance' is still running; the watchdog could not stop it"
        __print_error "Uninstall aborted — stop it manually, then retry"
        events.sh emit instance-uninstall-failed "${instance}"
        return $EC_ERROR
        ;;
      *)
        __print_warning "Could not reach the watchdog to deregister '$instance'; it may remain supervised"
        ;;
    esac
  fi

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

  # Purge the backups store last: everything above is recoverable from a backup,
  # so it must not be removed until the rest of the uninstall has succeeded.
  if [[ "$purge_backups" -eq 1 ]] && [[ -n "$backups_dir" ]] && [[ -d "$backups_dir" ]]; then
    if rm -rf "${backups_dir:?}"; then
      __print_info "Removed backups store $backups_dir"
    else
      __print_warning "Failed to remove backups store $backups_dir"
    fi
  elif [[ -n "$backups_dir" ]] && [[ -d "$backups_dir" ]]; then
    __print_info "Backups for '$instance' kept in $backups_dir"
  fi

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
