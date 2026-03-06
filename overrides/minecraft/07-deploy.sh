function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  __print_info "Deploying..."

  # Check if $source is empty
  if [[ -z "$(ls -A "$source")" ]]; then
    __print_error "$source is empty, nothing to deploy. Exiting"
    return $EC_ERROR
  fi

  if ! mv -f "$source"/*.jar "$dest"/release.jar; then
    __print_error "mv -f $source/* $dest/"
    return $EC_ERROR
  fi

  local eula_file=$dest/eula.txt

  if ! echo "eula=true" >"$eula_file"; then
    __print_warning "Failed to configure eula.txt file, continuing"
  fi

  __print_success "Deploy complete"
  return $EC_SUCCESS
}
