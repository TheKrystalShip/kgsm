# =============================================================================
# DOWNLOAD AND DEPLOYMENT
# =============================================================================

function _download() {
  local version="${1:-latest}"

  __print_info "Downloading Docker image version ${version}..."

  # For container-based instances, downloading means pulling the images
  # defined in the compose file
  # This will pull all images defined in the docker-compose.yml file
  # Run in the working directory where docker-compose.yml is located
  if ! (cd "$instance_working_dir" && docker compose -f "$instance_compose_file" pull); then
    __print_error "Failed to pull Docker images"
    return $EC_ERROR
  fi

  __print_success "Download complete"
  return $EC_SUCCESS
}
