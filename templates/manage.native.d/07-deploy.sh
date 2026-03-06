function _deploy() {
  local source=$instance_temp_dir
  local dest=$instance_install_dir

  __print_info "Deploying..."

  # Check if $source is empty
  if [[ -z "$(ls -A "$source")" ]]; then
    __print_error "$source is empty, nothing to deploy. Exiting"
    return $EC_ERROR
  fi

  # Copy everything from $source into $dest
  if ! cp -rf "$source"/* "$dest"; then
    __print_error "Failed to copy contents from $source into $dest"
    return $EC_ERROR
  fi

  if ! rm -rf "${source:?}"/*; then
    __print_error "Failed to clear $source"
    return $EC_ERROR
  fi

  __print_success "Deploy complete"
  return $EC_SUCCESS
}

