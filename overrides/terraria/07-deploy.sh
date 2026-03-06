function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  __print_info "Deploying..."

  # Check if $source is empty
  if [[ -z "$(ls -A "$source")" ]]; then
    __print_error "$source is empty, nothing to deploy. Exiting"
    return $EC_ERROR
  fi

  if ! mv "$source"/* "$dest"/; then
    __print_error "mv $source/* $dest/"
    return $EC_ERROR
  fi

  if ! chmod +x "$dest"/TerrariaServer*; then
    __print_error "chmod +x $dest/TerrariaServer*"
    return $EC_ERROR
  fi

  if ! rm -rf "${source:?}"/*; then
    __print_error "rm -rf ${source:?}/*"
    return $EC_ERROR
  fi

  __print_success "Deploy complete"
  return $EC_SUCCESS
}
