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
  wget --timeout="$timeout" -qO - 'https://terraria.org/api/get/dedicated-servers-names' |
    jq .[0] |
    cut -d '-' -f3 |
    cut -d '.' -f1
}

# INPUT:
# - $1: Version
#
# OUTPUT:
# - 0: Success
# - 1: Error
function _download() {
  local version=$1
  local dest=$instance_temp_dir

  # If no version is given, get the latest
  if [ -z "$version" ]; then
    version=$(func_get_latest_version)
  fi

  local download_url="https://terraria.org/api/download/pc-dedicated-server/terraria-server-${version}.zip"
  local dest_file="${dest}/terraria-server-${version}.zip"
  local timeout="${instance_wget_timeout_seconds:-60}"

  # Download zip file in $dest
  if ! wget --timeout="$timeout" -qO "$dest_file" "$download_url"; then
    __print_error "wget --timeout=$timeout -qO $dest_file $download_url"
    return 1
  fi

  # Extract zipped contents in the same $dest
  if ! unzip -q "$dest_file" -d "$dest"; then
    __print_error "unzip -q $dest_file -d $dest"
    return 1
  fi

  # Remove zip file
  if ! rm "$dest_file"; then
    __print_error "rm $dest_file"
    return 1
  fi

  # Terraria extracts with the version name as the base folder, we don't want that
  if ! mv "$dest"/"$version"/* "$dest"/; then
    __print_error "mv $dest/$version/* $dest/"
    return 1
  fi

  # Remove trailing empty folder
  if ! rm -rf "${dest:?}"/"$version"; then
    __print_error "rm -rf $dest/$version"
    return 1
  fi

  # Terraria server comes in 3 subfolders for Windows, Mac & Linux
  # Only want the contents of the Linux folder, so move all of that outside
  if ! mv "$dest"/Linux/* "$dest"/; then
    __print_error "mv $dest/Linux/* $dest/"
    return 1
  fi

  # Remove the Windows dir
  if ! rm -rf "${dest:?}"/Windows; then
    __print_error "rm -rf ${dest:?}/Windows"
    return 1
  fi

  # Remove the Mac dir
  if ! rm -rf "${dest:?}"/Mac; then
    __print_error "rm -rf ${dest:?}/Mac"
    return 1
  fi

  # Remove the empty Linux dir
  if ! rm -rf "${dest:?}"/Linux; then
    __print_error "rm -rf ${dest:?}/Linux"
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

  # Just move everything from the source dir to dest
  if ! mv "$source"/* "$dest"/; then
    __print_error "mv $source/* $dest/"
    return 1
  fi

  if ! chmod +x "$dest"/TerrariaServer*; then
    __print_error "chmod +x $dest/TerrariaServer*"
    return 1
  fi

  # Remove everything else left behind in $source
  if ! rm -rf "${source:?}"/*; then
    __print_error "rm -rf ${source:?}/*"
    return 1
  fi

  return 0
}
