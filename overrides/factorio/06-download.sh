# =============================================================================
# DOWNLOAD AND DEPLOYMENT
# =============================================================================

function _download() {
  # shellcheck disable=SC2034
  local version=$1
  local dest=${2:-$instance_temp_dir}

  __print_info "Downloading..."

  local download_url="https://factorio.com/get-download/${version}/headless/linux64"
  local dest_file="$dest/factorio_headless.tar.xz"
  local timeout="${instance_wget_timeout_seconds:-60}"

  if ! wget --timeout="$timeout" -qO "$dest_file" "$download_url"; then
    __print_error "wget --timeout=$timeout -qO $dest_file $download_url"
    return 1
  fi

  if ! tar -xf "$dest_file" --strip-components=1 -C "$dest" >/dev/null 2>&1; then
    __print_error "tar -xf $dest_file --strip-components=1 -C $dest"
    return 1
  fi

  if ! rm "$dest_file"; then
    __print_error "rm $dest_file"
    return 1
  fi

  __print_success "Download complete"
  return $EC_SUCCESS
}
