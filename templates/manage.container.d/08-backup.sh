# =============================================================================
# BACKUP MANAGEMENT
# =============================================================================

function _create_backup() {
  __print_info "Creating backup..."

  # Check if install directory exists
  if [[ ! -d "${instance_install_dir}" ]]; then
    __print_error "Install directory ${instance_install_dir} does not exist"
    return $EC_ERROR
  fi

  # Check for content inside the install directory before attempting to
  # create a backup. If empty, skip
  if [ -z "$(ls -A "${instance_install_dir}")" ]; then
    # Source directory is empty, nothing to back up
    __print_warning "${instance_install_dir} is empty, skipping backup"
    return $EC_SUCCESS
  fi

  # Check instance running state before attempting to create backup
  if _is_active &>/dev/null; then
    __print_error "$self is currently running, please shut down before attempting to create a backup"
    return $EC_ERROR
  fi

  # Ensure backup directory exists
  if [[ ! -d "${instance_backups_dir}" ]]; then
    mkdir -p "${instance_backups_dir}" || {
      __print_error "Failed to create backup directory ${instance_backups_dir}"
      return $EC_ERROR
    }
  fi

  # Format current datetime for backup filename
  local datetime
  datetime="$(date +"%Y-%m-%dT%H:%M:%S")"
  local installed_version
  installed_version=$(_get_installed_version)
  local output="${instance_backups_dir}/${instance_name}-${installed_version:-unknown}-${datetime}.backup"

  if [[ "$instance_compress_backups" == "true" ]]; then
    output="${output}.tar.gz"

    if ! touch "$output"; then
      __print_error "Failed to create $output"
      return $EC_ERROR
    fi

    cd "$instance_install_dir" || return $EC_ERROR

    if ! tar -czf "$output" .; then
      __print_error "Failed to compress $output"
      return $EC_ERROR
    fi
  else
    # Create backup folder if it doesn't exist
    if [ ! -d "$output" ]; then
      if ! mkdir -p "$output"; then
        __print_error "Error creating backup folder $output"
        return $EC_ERROR
      fi
    fi

    # Copy everything from the install directory into a backup folder
    if ! cp -r "$instance_install_dir"/* "$output"/; then
      __print_error "Failed to create backup $output"
      rm -rf "${output:?}"
      return $EC_ERROR
    fi
  fi

  __print_success "Backup created"
  return $EC_SUCCESS
}

function _restore_backup() {
  local source="$instance_backups_dir/$1"
  local backup_version

  __print_info "Restoring ${source}..."

  if [[ ! -f "$source" ]] && [[ ! -d "$source" ]]; then
    __print_error "Could not find backup $source"
    return $EC_ERROR
  fi

  # Get version number from $source with robust parsing and fallback
  local backup_filename="${source#"$instance_backups_dir/"}"
  local backup_version="unknown"

  # Try to parse version from filename format: instance-version-datetime.backup
  if [[ "$backup_filename" =~ ^[^-]+-([^-]+)-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.backup ]]; then
    # Extract version from regex match
    backup_version="${BASH_REMATCH[1]}"
    __print_info "Parsed version from backup filename: $backup_version"
  else
    # Fallback: try the original array-based parsing with bounds checking
    IFS='-' read -ra backup_name <<<"$backup_filename"
    if [[ ${#backup_name[@]} -ge 3 ]] && [[ -n "${backup_name[2]}" ]]; then
      backup_version="${backup_name[2]}"
      __print_info "Parsed version using array method: $backup_version"
    else
      # Final fallback: try to extract any version-like pattern from filename
      if [[ "$backup_filename" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        backup_version="${BASH_REMATCH[1]}"
        __print_info "Extracted version pattern from filename: $backup_version"
      else
        __print_warning "Could not parse version from backup filename, using 'unknown'"
        backup_version="unknown"
      fi
    fi
    unset IFS
  fi

  if [ -n "$(ls -A "$instance_install_dir")" ]; then
    # $instance_install_dir is not empty, create new backup before proceeding

    __print_warning "Current installation directory is not empty, creating a backup first..."

    # Create backup and verify it succeeded
    if ! _create_backup; then
      __print_error "Failed to create backup before restore. Aborting to prevent data loss."
      return $EC_ERROR
    fi

    # Verify backup was actually created and is accessible
    local latest_backup
    latest_backup=$(ls -t "$instance_backups_dir" | head -1 2>/dev/null)
    if [[ -z "$latest_backup" ]] || [[ ! -e "$instance_backups_dir/$latest_backup" ]]; then
      __print_error "Backup creation appeared to succeed but backup file is not accessible. Aborting to prevent data loss."
      return $EC_ERROR
    fi

    __print_info "Backup created successfully: $latest_backup"

    # Now safe to proceed with destructive operations
    if ! rm -rf "${instance_install_dir:?}"/*; then
      __print_error "Failed to clear $instance_install_dir, exiting"
      return $EC_ERROR
    fi
  fi

  if [[ "$source" == *.gz ]]; then
    cd "$instance_install_dir" || return $EC_ERROR

    if ! tar -xzf "$source" .; then
      __print_error "Failed to restore $source"
      return $EC_ERROR
    fi
  else
    # $instance_install_dir is empty/user confirmed continue, move the backup into it
    if ! cp -r "$source"/* "$instance_install_dir"/; then
      __print_error "Failed to restore backup $source"
      return $EC_ERROR
    fi
  fi

  # Update instance version file with $backup_version
  _save_version "$backup_version" || {
    __print_error "Failed to save restored version $backup_version to file."
    return $EC_ERROR
  }

  __print_success "Restore complete"
  return $EC_SUCCESS
}

function _list_backups() {
  shopt -s extglob nullglob

  # Create array with contents of the backup dir
  backups_array=("$instance_backups_dir"/*)
  # remove leading $instance_backups_dir:
  backups_array=("${backups_array[@]#"$instance_backups_dir/"}")

  echo "${backups_array[@]}"
}

