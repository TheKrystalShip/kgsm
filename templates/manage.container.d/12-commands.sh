# =============================================================================
# COMMAND HANDLERS
# =============================================================================

function _cmd_start() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_start
      return $EC_SUCCESS
      ;;
    -d | --detached)
      _start_background
      return $?
      ;;
    -*)
      __print_error "Invalid option: $1"
      return $EC_INVALID_ARG
      ;;
    *)
      __print_error "Invalid argument: $1"
      return $EC_INVALID_ARG
      ;;
    esac
    shift
  done
  # No flags = interactive mode
  _start
}

function _cmd_stop() {
  local no_save=0
  local no_graceful=0

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_stop
      return $EC_SUCCESS
      ;;
    --no-save) no_save=1 ;;
    --no-graceful) no_graceful=1 ;;
    -*)
      __print_error "Invalid option: $1"
      return $EC_INVALID_ARG
      ;;
    *)
      __print_error "Invalid argument: $1"
      return $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  _timed_stop "$no_save" "$no_graceful"
}

function _cmd_restart() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_restart
      return $EC_SUCCESS
      ;;
    *)
      __print_error "Invalid argument: $1"
      return $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  _timed_stop 0 0 || return $?
  _start_background
}

function _cmd_attach() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_attach
      return $EC_SUCCESS
      ;;
    *)
      __print_error "Invalid argument: $1"
      return $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  if ! _is_active &>/dev/null; then
    __print_error "Server is not running"
    return $EC_ERROR
  fi
  (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" exec "${instance_name}" /bin/sh)
}

function _cmd_kill() {
  _kill_all_processes
}

function _cmd_save() {
  _send_save_command
}

function _cmd_input() {
  if [[ -z "${1:-}" ]]; then
    __print_error "Missing argument: <command>"
    return $EC_MISSING_ARG
  fi
  _send_input "$1"
}

function _cmd_kick() {
  _send_moderation_command "${instance_kick_command}" "${1:-}" "kick"
}

function _cmd_ban() {
  _send_moderation_command "${instance_ban_command}" "${1:-}" "ban"
}

function _cmd_unban() {
  _send_moderation_command "${instance_unban_command}" "${1:-}" "unban"
}

function _cmd_is_active() {
  _is_active
}

function _cmd_status() {
  local json_format=""
  local fast_mode=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_status
      return $EC_SUCCESS
      ;;
    --json) json_format="1" ;;
    --fast) fast_mode="1" ;;
    -*)
      __print_error "Invalid option: $1"
      return $EC_INVALID_ARG
      ;;
    *)
      __print_error "Invalid argument: $1"
      return $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  _get_status "$json_format" "$fast_mode"
}

function _cmd_logs() {
  local follow="false"
  local line_count=10

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_logs
      return $EC_SUCCESS
      ;;
    -f | --follow) follow="true" ;;
    -n | --tail | --lines)
      shift
      if [[ -z "${1:-}" ]] || [[ ! "$1" =~ ^[0-9]+$ ]]; then
        __print_error "Missing or invalid number for --tail"
        return $EC_INVALID_ARG
      fi
      line_count="$1"
      ;;
    -*)
      __print_error "Invalid option: $1"
      return $EC_INVALID_ARG
      ;;
    *)
      __print_error "Invalid argument: $1"
      return $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  _print_logs "$follow" "$line_count"
}

function _cmd_version() {
  if [[ "$#" -eq 0 ]]; then
    _get_installed_version
    return $?
  fi

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_version
      return $EC_SUCCESS
      ;;
    --compare)
      _compare_versions
      return $?
      ;;
    --latest)
      _get_latest_version
      return $?
      ;;
    --save)
      shift
      if [[ -z "${1:-}" ]]; then
        __print_error "Missing argument: <version>"
        return $EC_MISSING_ARG
      fi
      _save_version "$1"
      return $?
      ;;
    --stored-latest)
      _get_stored_latest_version
      return $?
      ;;
    --stored-checked-at)
      _get_stored_latest_checked_at
      return $?
      ;;
    --save-latest)
      shift
      if [[ -z "${1:-}" ]]; then
        __print_error "Missing argument: <version>"
        return $EC_MISSING_ARG
      fi
      _save_latest_version "$1"
      return $?
      ;;
    -*)
      __print_error "Invalid option: $1"
      return $EC_INVALID_ARG
      ;;
    *)
      __print_error "Invalid argument: $1"
      return $EC_INVALID_ARG
      ;;
    esac
    shift
  done
}

function _cmd_download() {
  local version=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help | help)
      show_usage_download
      return $EC_SUCCESS
      ;;
    -*)
      __print_error "Invalid option: $1"
      return $EC_INVALID_ARG
      ;;
    *) version="$1" ;;
    esac
    shift
  done

  __print_info "Starting download process..."
  if ! _download "$version"; then
    __print_error "Download process failed"
    return $EC_ERROR
  fi
  __print_success "Download process completed successfully"
}

function _cmd_deploy() {
  __print_info "Starting deployment process..."
  if ! _deploy; then
    __print_error "Deployment process failed"
    return $EC_ERROR
  fi
  __print_success "Deployment process completed successfully"
}

# An update recreates the container from a freshly pulled image, so the state it
# is about to replace is captured first. The caller passes --run-state so that
# backup can record what it was taken against.
function _update() {
  local run_state=""
  local -a emit_cmd=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-state)
      run_state="${2:-}"
      shift 2
      ;;
    --emit-cmd)
      # The command the caller wants this script's phases reported through, as
      # words. This script emits nothing on its own — it has no journal and is
      # meant to run standalone — so a caller that wants the same download and
      # deploy events an install produces hands one in. Given nothing, silent.
      read -r -a emit_cmd <<< "${2:-}"
      shift 2
      ;;
    *) shift ;;
    esac
  done

  # Report one phase, if the caller asked for phases at all. INSTANCE_NAME is the
  # script's own identity (derived from its directory); the lowercase instance_*
  # variables come from the config file, which does not carry the name — passing
  # one of those emits an event about "" that the emitter rejects, silently.
  function _emit_phase() {
    [[ ${#emit_cmd[@]} -gt 0 ]] || return 0
    local _out
    if ! _out="$("${emit_cmd[@]}" "$1" "$INSTANCE_NAME" 2>&1)"; then
      # Never fatal — the update is the job here and a phase nobody could record
      # must not fail it. But never silent either: a reporting path that fails
      # quietly is indistinguishable from one that was never wired up.
      __print_warning "Could not report phase $1: ${_out:-no detail}"
    fi
  }

  __print_info "Updating Docker container..."

  # Capture the current state before the recreate can replace it. A plain restart
  # cannot lose data and takes no backup; only an update does. A capture that
  # fails abandons the update, because laying a new image over an unprotected
  # world is precisely what this guards against.
  local -a backup_args=()
  [[ -n "$run_state" ]] && backup_args+=(--run-state "$run_state")

  local backup_id
  backup_id="$(_create_backup "${backup_args[@]}" | tail -n1)"
  if [[ -z "$backup_id" ]] || [[ ! -d "${instance_backups_dir}/${backup_id}" ]]; then
    __print_error "Backup before update failed; not updating $instance_name"
    return $EC_ERROR
  fi
  __print_success "Backup before update: $backup_id"

  # For container instances, updating means:
  # 1. Pull the latest images defined in the docker-compose file
  # 2. Recreate the containers with the latest images

  # Pull the latest images - run in the working directory. Reported with the same
  # events an install emits for the same work: pulling images IS this runtime's
  # download, and a surface showing "Updating…" with no further word for the
  # whole of it is the reason these are here. Reporting only, never a new
  # decision — the outcome of the pull governs exactly what it did before.
  _emit_phase instance-download-started
  if (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" pull); then
    _emit_phase instance-download-finished
  else
    _emit_phase instance-download-failed
  fi

  # If the container is running, stop it and recreate
  _emit_phase instance-deploy-started
  local deployed=1
  if _is_active &>/dev/null; then
    (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" up -d --force-recreate) || deployed=0
  else
    # Just recreate without starting
    (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" up -d) || deployed=0
    (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" down) || deployed=0
  fi
  if [[ $deployed -eq 1 ]]; then
    _emit_phase instance-deploy-finished
  else
    _emit_phase instance-deploy-failed
  fi

  # Record what was actually pulled — the digest of the images now on this host,
  # read back from Docker rather than assumed. A tag is not a version: writing
  # "latest" here made every later comparison meaningless, because the recorded
  # value never changed no matter what was running.
  local pulled_version
  if pulled_version=$(_get_local_version); then
    _save_version "$pulled_version"
  else
    # Nothing readable to record. Leaving the file empty makes the status
    # surface report this instance as unchecked, which is true, instead of
    # leaving a stale digest that would read as a completed update.
    __print_warning "Could not read the digest of the pulled images; recording no version"
    : >"$instance_version_file"
  fi

  __print_success "Update complete"
  return $EC_SUCCESS
}

function _cmd_update() {
  _update "$@"
}

function _cmd_backup() {
  local subcommand="${1:-}"
  shift 2>/dev/null || true

  case "$subcommand" in
  -h | --help | help)
    show_usage_backup
    return $EC_SUCCESS
    ;;
  create) _create_backup ;;
  restore)
    if [[ -z "${1:-}" ]]; then
      __print_error "Missing argument: <backup>"
      return $EC_MISSING_ARG
    fi
    _restore_backup "$1"
    ;;
  list) _list_backups ;;
  "")
    __print_error "Missing subcommand for backup"
    __print_error "Use '$self help backup' for usage information"
    return $EC_MISSING_ARG
    ;;
  *)
    __print_error "Unknown backup subcommand: $subcommand"
    return $EC_INVALID_ARG
    ;;
  esac
}

# -----------------------------------------------------------------------------
# Tier-1 ops: flat, dash-free command aliases that mirror the top-level kgsm CLI
# (`kgsm instances backups|create-backup|restore-backup|check-update <name>`).
# The top-level CLI forwards each subcommand verbatim to this script, so the
# names match exactly. They delegate to the existing (overridable) backup and
# version helpers — no logic is duplicated here.
# -----------------------------------------------------------------------------

function _cmd_backups() {
  # --json emits the full manifests; the default emits ids only, one per line.
  if [[ "${1:-}" == "--json" ]]; then
    _backup_manifest_json
    return $?
  fi

  _list_backups
}

function _cmd_create_backup() {
  _create_backup "$@"
}

function _cmd_restore_backup() {
  if [[ -z "${1:-}" ]]; then
    __print_error "Missing argument: <source>"
    return $EC_MISSING_ARG
  fi
  local backup="$1"
  shift
  _restore_backup "$backup" "$@"
}

function _cmd_check_update() {
  # Compare the installed version against the latest available one, using the
  # (per-game overridable) version helpers. Honest contract:
  #   - update available -> print the latest version to stdout, return success
  #   - already current  -> print nothing to stdout, return success
  #   - cannot determine -> return an error (never a fabricated answer)
  local installed latest
  installed="$(_get_installed_version)"
  latest="$(_get_latest_version)" || return $EC_ERROR

  if [[ -z "$latest" ]]; then
    __print_error "Could not determine the latest version"
    return $EC_ERROR
  fi

  # Status lines go to stderr; stdout carries only the machine-readable result
  # (the latest version when an update is available, nothing otherwise).
  if [[ "$installed" == "$latest" ]]; then
    __print_info "Already up to date (version ${installed})" >&2
    return $EC_SUCCESS
  fi

  __print_info "Update available: ${installed} -> ${latest}" >&2
  echo "$latest"
  return $EC_SUCCESS
}


