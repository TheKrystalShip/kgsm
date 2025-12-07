#!/usr/bin/env bash

################################################################################
# Uncomment and use any of the following functions, they will be used to
# override the default function when generating a instance's management file
################################################################################
#
# Brief description of each:
#
# INPUT:
# - void
#
# OUTPUT:
# - echo "$version": Success
# - exit 1: Error
# _get_latest_version           Should always return the latest available
#                               version, or 1 in case there's any problem.
#
# INPUT:
# - $1: Version
#
# OUTPUT:
# - exit 0: Success
# - exit 1: Error
# _download                     In charge of downloading all the required files
#                               for the service, extract any zips, move, copy,
#                               rename, remove, etc. It should leave the $2
#                               with a fully working setup that can be called
#                               and executed as if it was a full install.
#
# INPUT:
# - void
#
# OUTPUT:
# - exit 0: Success
# - exit 1: Error
# _deploy                       Will move everything from $1 into $2 and do any
#                               cleanup that couldn't be done by func_download.
#
################################################################################
#
# Available global vars:
#
# instance_name
# instance_working_dir
# instance_install_dir
# instance_saves_dir
# instance_temp_dir
# instance_backups_dir
# instance_logs_dir
# instance_install_datetime
# instance_blueprint_file
# instance_level_name
# instance_ports
# instance_executable_file
# instance_executable_arguments
# instance_lifecycle_manager
# instance_management_file
#
# (Optional) instance_stop_command
# (Optional) instance_save_command
# (Optional) instance_pid_file
# (Optional) instance_ufw_file
# (Optional) instance_systemd_service_file
# (Optional) instance_systemd_socket_file
################################################################################

# INPUT:
# - void
#
# OUTPUT:
# - 0: Success (echo "$new_version")
# - 1: Error
function _get_latest_version() {
  local timeout="${instance_wget_timeout_seconds:-60}"
  wget --timeout="$timeout" -qO - 'https://factorio.com/api/latest-releases' |
    jq .stable.headless |
    tr -d '"'
}

# INPUT:
# - $1: Version
#
# OUTPUT:
# - 0: Success
# - 1: Error
function _download() {
  # shellcheck disable=SC2034
  local version=$1
  local dest=$instance_temp_dir

  # Download new version in $dest
  local download_url="https://factorio.com/get-download/${version}/headless/linux64"
  local dest_file="$dest/factorio_headless.tar.xz"
  local timeout="${instance_wget_timeout_seconds:-60}"

  # Download
  if ! wget --timeout="$timeout" -qO "$dest_file" "$download_url"; then
    __print_error "wget --timeout=$timeout -qO $dest_file $download_url"
    return 1
  fi

  # Extract
  if ! tar -xf "$dest_file" --strip-components=1 -C "$dest" >/dev/null 2>&1; then
    __print_error "tar -xf $dest_file --strip-components=1 -C $dest"
    return 1
  fi

  # Remove trailing file
  if ! rm "$dest_file"; then
    __print_error "rm $dest_file"
    return 1
  fi

  return 0
}

# INPUT:
# - Void
#
# OUTPUT:
# - 0: Success
# - 1: Error
function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  if ! cp -r "$source"/* "$dest"; then
    __print_error "Failed copy contents from $source into $dest"
    return 1
  fi

  if ! rm -rf "${source:?}"/*; then
    __print_warning "Failed to clear $source, continuing..."
  fi

  # Check if savefile exists, factorio needs to boot with an existing
  # save otherwise it fails to start. Create a savefile at this stage
  if [[ ! -f "$instance_saves_dir/$instance_level_name" ]]; then
    cd "$instance_install_dir/bin/x64" || return 1
    if ! "$instance_executable_file" --create "$instance_saves_dir/$instance_level_name" &>/dev/null; then
      __print_error "Failed to create savefile $instance_level_name, server won't be able to start without it"
      return 1
    fi
  fi

  return 0
}
