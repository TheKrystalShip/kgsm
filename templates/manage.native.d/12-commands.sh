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
  # No flags = interactive (detachable) mode
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
  _attach_to_instance
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
  local version=0

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

# An update replaces the installed game in place, so the state it is about to
# overwrite is captured first. The caller passes --run-state so that backup can
# record what it was taken against; see _create_backup for why the script cannot
# measure that itself.
function _update() {
  local run_state=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-state)
      run_state="${2:-}"
      shift 2
      ;;
    *) shift ;;
    esac
  done

  __print_info "Starting update..."

  # Deploying over a running game copies onto its own open executable and fails
  # partway with "Text file busy", leaving install/ half-replaced. _is_active is
  # the only probe this script has and it cannot see a watchdog-owned process,
  # which is why the state the caller resolved is consulted first — without it
  # this refusal never fires for a native instance.
  if [[ "$run_state" == "active" ]] || _is_active &>/dev/null; then
    __print_error "$self is currently running, please shut down before attempting to update"
    return $EC_ERROR
  fi

  # Get the latest version from remote
  local latest_version
  latest_version=$(_get_latest_version)

  if [[ -z "$latest_version" ]]; then
    __print_error "Failed to retrieve latest version, exiting"
    return $EC_ERROR
  fi

  # Compare versions and save the latest version if different
  local installed_version
  installed_version=$(_get_installed_version)

  if [[ "$latest_version" == "$installed_version" ]]; then
    __print_info "Local version is already up-to-date"
    return $EC_SUCCESS
  fi

  # Everything past this point overwrites the installed game, and for several
  # games the world lives inside install/ — so capture it while it is still
  # intact. A plain restart cannot lose data and takes no backup; only an update
  # does. A capture that fails abandons the update, because laying a new version
  # over an unprotected world is precisely what this guards against.
  local -a backup_args=()
  [[ -n "$run_state" ]] && backup_args+=(--run-state "$run_state")

  local backup_id
  backup_id="$(_create_backup "${backup_args[@]}" | tail -n1)"
  if [[ -z "$backup_id" ]] || [[ ! -d "${instance_backups_dir}/${backup_id}" ]]; then
    __print_error "Backup before update failed; leaving $instance_name on version $installed_version"
    return $EC_ERROR
  fi
  __print_success "Backup before update: $backup_id"

  # Download the latest version
  if ! _download "$latest_version"; then
    __print_error "Failed to download latest version $latest_version"
    return $EC_ERROR
  fi

  # Deploy the downloaded files
  if ! _deploy; then
    __print_error "Failed to deploy new files"
    return $EC_ERROR
  fi

  # Save the new version to file
  if ! _save_version "$latest_version"; then
    __print_error "Failed to save new version $latest_version to file"
    return $EC_ERROR
  fi

  __print_success "Update complete, new version: $latest_version"

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


