# =============================================================================
# DOWNLOAD AND DEPLOYMENT
# =============================================================================

function _download() {
  # https://download.veloren.net/latest/linux/x86_64/weekly
  local version=$1
  local dest=${2:-$instance_temp_dir}
  local timeout="${instance_wget_timeout_seconds:-60}"

  __print_info "Downloading..."

  local download_url="https://download.veloren.net/latest/linux/x86_64/weekly"

  if ! wget --timeout="$timeout" -P "$dest" "$download_url"; then
    __print_error "wget --timeout=$timeout -P $dest $download_url"
    return 1
  fi

  if ! unzip "$dest"/weekly -d "$dest"; then
    __print_error "unzip $dest/weekly -d $dest"
    return 1
  fi

  if ! rm "$dest"/weekly; then
    __print_error "rm $dest/weekly"
    return 1
  fi

  __print_success "Download complete"
  return $EC_SUCCESS
}
