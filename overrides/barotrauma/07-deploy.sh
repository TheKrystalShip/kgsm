function _deploy() {
  local source="$instance_temp_dir"
  local dest="$instance_install_dir"

  __print_info "Deploying..."

  # Check if $source is empty
  if [[ -z "$(ls -A "$source")" ]]; then
    __print_error "$source is empty, nothing to deploy. Exiting"
    return $EC_ERROR
  fi

  if ! cp -r "$source"/* "$dest"; then
    __print_error "Failed to copy $source into $dest"
    return $EC_ERROR
  fi

  if ! rm -rf "${source:?}"/*; then
    __print_error "Failed to clear $source"
    return $EC_ERROR
  fi

  # Ensure HOME is set to the user's home directory
  if [[ -z "$HOME" ]]; then
    __print_error "HOME environment variable is not set"
    return $EC_ERROR
  fi

  # https://barotraumagame.com/wiki/Hosting_a_Dedicated_Server#Linux_Dedicated_Server_Hosting
  local config_dir="${HOME}/.local/share/Daedalic Entertainment GmbH/Barotrauma"

  if ! mkdir -p "${config_dir}"; then
    __print_error "Failed to create required directory: ${config_dir}"
    return $EC_ERROR
  fi

  __print_success "Deploy complete"
  return $EC_SUCCESS
}
