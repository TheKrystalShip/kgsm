function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  __print_info "Deploying..."

  # Check if $source is empty
  if [[ -z "$(ls -A "$source")" ]]; then
    __print_error "$source is empty, nothing to deploy. Exiting"
    return $EC_ERROR
  fi

  if ! cp -r "$source"/* "$dest"; then
    __print_error "Failed copy contents from $source into $dest"
    return $EC_ERROR
  fi

  if ! rm -rf "${source:?}"/*; then
    __print_warning "Failed to clear $source, continuing..."
  fi

  # Factorio requires an existing save to start; create one if it doesn't exist
  if [[ ! -f "$instance_saves_dir/$instance_level_name" ]]; then
    cd "$instance_install_dir/bin/x64" || return 1
    if ! "$instance_executable_file" --create "$instance_saves_dir/$instance_level_name" &>/dev/null; then
      __print_error "Failed to create savefile $instance_level_name, server won't be able to start without it"
      return 1
    fi
  fi

  __print_success "Deploy complete"
  return $EC_SUCCESS
}
