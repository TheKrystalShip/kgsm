# =============================================================================
# DOWNLOAD AND DEPLOYMENT
# =============================================================================

function _download() {
  local version=$1
  local dest=${2:-$instance_temp_dir}
  local timeout="${instance_wget_timeout_seconds:-60}"

  __print_info "Downloading..."

  local download_url="https://terraria.org/api/download/pc-dedicated-server/terraria-server-${version}.zip"
  local dest_file="${dest}/terraria-server-${version}.zip"

  if ! wget --timeout="$timeout" -qO "$dest_file" "$download_url"; then
    __print_error "wget --timeout=$timeout -qO $dest_file $download_url"
    return 1
  fi

  if ! unzip -q "$dest_file" -d "$dest"; then
    __print_error "unzip -q $dest_file -d $dest"
    return 1
  fi

  if ! rm "$dest_file"; then
    __print_error "rm $dest_file"
    return 1
  fi

  # Terraria extracts with the version name as the base folder; flatten it
  if ! mv "$dest"/"$version"/* "$dest"/; then
    __print_error "mv $dest/$version/* $dest/"
    return 1
  fi

  if ! rm -rf "${dest:?}"/"$version"; then
    __print_error "rm -rf $dest/$version"
    return 1
  fi

  # Terraria ships Windows/Mac/Linux subdirs; keep only Linux contents
  if ! mv "$dest"/Linux/* "$dest"/; then
    __print_error "mv $dest/Linux/* $dest/"
    return 1
  fi

  if ! rm -rf "${dest:?}"/Windows; then
    __print_error "rm -rf ${dest:?}/Windows"
    return 1
  fi

  if ! rm -rf "${dest:?}"/Mac; then
    __print_error "rm -rf ${dest:?}/Mac"
    return 1
  fi

  if ! rm -rf "${dest:?}"/Linux; then
    __print_error "rm -rf ${dest:?}/Linux"
    return 1
  fi

  __print_success "Download complete"
  return $EC_SUCCESS
}
