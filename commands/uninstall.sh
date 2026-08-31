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

# Library logic. An uninstall deletes files, so whether the files are reachable
# at all decides whether there is an uninstall to do.
if [[ -z "${KGSM_LOGIC_LIBRARIES_LOADED:-}" ]]; then
  # shellcheck source=handlers/libraries.sh
  source "$(__find_command_handler libraries.sh)" || exit $EC_FAILED_SOURCE
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
  <instance>                  Instance id or display name to uninstall

${UNDERLINE}Options:${END}
  -h, --help                  Display this help information
  -y, --force, --yes          Skip the confirmation prompt (for non-interactive
                              callers; the destructive intent is confirmed already).
                              A running instance is stopped and removed in one step
                              instead of being refused. When the instance's library
                              is offline, this instead deregisters the instance and
                              leaves its files alone
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

  A running instance is refused: stop it first, or pass --force to stop and
  remove it in one step.

  An instance whose library is offline is refused: there are no files to
  remove while the disk is away, only the host's record of the instance.
  --force removes that record alone, leaving the tree on the disk.
"
}

# Forgets an instance whose library is not mounted, without touching a file.
#
# Nothing of the instance is reachable, so this is the whole of what can be
# done: the supervisor stops being told to look after it, and the registry entry
# — the last thing on this host that says the instance exists — is removed. Its
# working directory, saves and backups are all still there, on the disk that is
# away, and re-registering that library does not bring the instance back: this
# host has forgotten it, deliberately.
#
# Reads the globals a preceding __logic_instance_library_state call assigned.
# Args: $1 = instance name
function _deregister_offline_instance() {
  local instance="$1"

  __print_info "Deregistering '$instance' from library '${__instance_library_name_out}'"

  __emit_event server.uninstall.started "${instance}"

  # Best-effort, and it matters most here: an instance the daemon still holds
  # desired-state for is one it keeps trying to spawn out of a directory that is
  # not there.
  if __watchdog_available; then
    __watchdog_deregister "$instance" > /dev/null 2>&1 || true
  fi

  if ! directories.sh unlink-instance "$__instance_blueprint_out" "$instance" --force; then
    __print_error "Failed to remove the registry entry for '$instance'"
    __emit_event server.uninstall.failed "${instance}"
    return $EC_FAILED_RM
  fi

  __print_success "Instance '${instance}' deregistered"
  __print_info "Its files were left untouched at ${__instance_working_dir_out}"
  __print_info "Firewall rules and command shortcuts it recorded could not be read and were not removed"

  __emit_event server.uninstalled "${instance}"
  __emit_event server.uninstall.finished "${instance}"

  return 0
}

function _uninstall() {
  local instance=""
  local force=0
  local purge_backups=0
  # Every failure below is reported by its own status, captured before anything
  # else runs: a printer succeeds, so reading $? after one reports that the step
  # it was complaining about worked.
  local exit_code=0

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

  # Resolve a display name to the id once, here, so every step below acts on the
  # id: the library-state check, the watchdog stop, the file and directory
  # removal, and the events those emit. The watchdog and the registry key on the
  # id and would silently not recognise a label — a deregister that no-ops while
  # the files are deleted anyway strands a running server and poisons the event
  # journal with a name nothing else uses. An id resolves to itself; an argument
  # that matches nothing is left as it is for the not-found error below to name.
  instance="$(__resolve_instance_id "$instance")" || return $?

  # An uninstall is defined by the files it deletes, and while the library is
  # not mounted there are none to delete — only a registry entry that is the
  # host's last record of a server whose data is intact on a disk somewhere
  # else. Deleting that record is a separate, much smaller thing, so it is asked
  # for separately.
  __logic_instance_library_state "$instance" > /dev/null
  if [[ "$__instance_library_state_out" == "offline" ]]; then
    if [[ "$force" -ne 1 ]]; then
      __print_error "Instance '$instance' is in library '${__instance_library_name_out}', which is not reachable at ${__instance_library_path_out}"
      __print_error "Mount it to uninstall the instance, or pass --force to deregister it and leave its files on the disk"
      return $EC_LIBRARY_OFFLINE
    fi

    _deregister_offline_instance "$instance"
    return $?
  fi

  # Validate instance exists before proceeding and resolve blueprint name.
  # The failure code is taken with || so it survives: inside an `if ! cmd`
  # branch $? is the negated status, which is always 0. validate_instance_name
  # names what it could not find, so there is nothing to add here.
  local instance_config_file
  instance_config_file=$(validate_instance_name "$instance") || return $?

  # Extract blueprint name from config file path before any destructive operations
  # Path structure: $KGSM_INSTANCES_DIR/<blueprint>/<instance>/<instance>.config.ini
  local blueprint_name
  blueprint_name="$(basename "$(dirname "$(dirname "$instance_config_file")")")" || {
    exit_code=$?
    __print_error "Failed to determine blueprint name for instance '$instance'"
    return $exit_code
  }

  # Whether the game is up is sampled here, before anything is asked or removed,
  # for two reasons. Without --force a running instance is refused outright: a
  # server with people on it is stopped as its own deliberate act — where a
  # shutdown announcement belongs — not as a side effect of an uninstall. With
  # --force the uninstall stops it as part of deregistering below, so this value
  # also decides whether that stop is a real event to emit or a fabricated one.
  # The reading has to be taken before the deregister that kills it: afterwards
  # there is nothing left to ask.
  local was_running=0
  if __watchdog_available && [[ "$(__watchdog_active_value "$instance")" == "true" ]]; then
    was_running=1
  fi

  if [[ "$was_running" -eq 1 ]] && [[ "$force" -ne 1 ]]; then
    __print_error "Instance '$instance' is running"
    __print_error "Stop it first, then uninstall — or pass --force to stop and remove it in one step"
    return $EC_ERROR
  fi

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

  __emit_event server.uninstall.started "${instance}"

  # Deregister from the watchdog BEFORE any files are removed: the daemon stops the
  # instance as part of deregistering, and a graceful stop needs the instance's FIFO and
  # management script to still exist. Skipping this leaves the daemon supervising a server
  # whose files are gone — it restart-loops the missing install dir, and its state feeds a
  # permanent, unresolvable crash alert into every consumer of the daemon's instance list.
  #
  # An unreachable daemon is best-effort (a host without one must still be able to uninstall),
  # but an explicit refusal is fatal: it means the daemon could not stop the instance, so the
  # game is still running. Deleting a running server's files out from under it corrupts saves
  # and strands the process — abort and let the operator deal with it. This is the
  # --force path (a stopped instance never reaches it running); was_running was
  # sampled above, before the prompt, and decides whether the stop is a real
  # event or a fabricated one.
  if __watchdog_available; then
    __watchdog_deregister "$instance"
    case $? in
      0)
        # Deregistering stops the instance, and until now nothing said so: the
        # process was killed and every consumer went on reporting the server as
        # running for the whole of the file removal that follows, with no record
        # that anyone had been dropped from a live game. Unlike a restart this
        # run is not coming back, so what happened IS a stop and is emitted as
        # one. Only when it was measurably up — an already-stopped instance
        # being uninstalled must not produce a stop that never happened.
        if [[ "$was_running" -eq 1 ]]; then
          __emit_event server.stopped "${instance}"
        fi
        ;;
      2)
        __print_error "Instance '$instance' is still running; the watchdog could not stop it"
        __print_error "Uninstall aborted — stop it manually, then retry"
        __emit_event server.uninstall.failed "${instance}"
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
    __emit_event server.uninstall.failed "${instance}"
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

  __print_success "Instance '${instance}' uninstalled"

  __emit_event server.uninstalled "${instance}"

  # Emitted LAST, after server.uninstalled: a consumer that reads "the run
  # ended" and re-reads the roster must find the instance already gone rather
  # than still listed. Same ordering as every other bracket.
  __emit_event server.uninstall.finished "${instance}"

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
