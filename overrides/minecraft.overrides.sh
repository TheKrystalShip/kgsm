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
  wget --timeout="$timeout" -qO - https://launchermeta.mojang.com/mc/game/version_manifest.json |
    jq -r '{latest: .latest.release} | .[]' |
    tr -d '"'
}

# INPUT:
# - $1: Version
#
# OUTPUT:
# - 0: Success
# - 1: Error
function _download() {
  local version="$1"
  local dest="$instance_temp_dir"
  local timeout="${instance_wget_timeout_seconds:-60}"

  # shellcheck disable=SC2155
  local release_url="$(
    wget --timeout="$timeout" -qO - https://launchermeta.mojang.com/mc/game/version_manifest.json |
      jq -r "{versions: .versions} | .[] | .[] | select(.id == \"$version\") | {url: .url} | .[]"
  )"

  if [[ -z "$release_url" ]]; then
    __print_error "Could not find the URL of the latest release, exiting"
    return 1
  fi

  # shellcheck disable=SC2155
  local release_server_jar_url="$(
    wget --timeout="$timeout" -qO - "$release_url" |
      jq -r '{url: .downloads.server.url} | .[]'
  )"

  if [[ -z "$release_server_jar_url" ]]; then
    __print_error "Could not find the URL of the JAR file"
    return 1
  fi

  local local_release_jar="$dest/minecraft_server.$version.jar"

  if [ ! -f "$local_release_jar" ]; then
    wget --timeout="$timeout" -qO "$local_release_jar" "$release_server_jar_url"
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

  if ! mv -f "$source"/*.jar "$dest"/release.jar; then
    __print_error "mv -f $source/* $dest/"
    return 1
  fi

  local eula_file=$dest/eula.txt

  if ! echo "eula=true" >"$eula_file"; then
    __print_warning "Failed to configure eula.txt file, continuing"
  fi

  return 0
}
