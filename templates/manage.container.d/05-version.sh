# =============================================================================
# VERSION MANAGEMENT
# =============================================================================

function _get_installed_version() {
  if [[ -f "$instance_version_file" ]]; then
    cat "$instance_version_file"
  else
    echo "latest"
  fi
}

function _get_latest_version() {
  # For containers, we can use the Docker image tag or digest
  # This example uses the 'latest' tag, but could be modified to check for
  # updated images using Docker Hub API or other methods
  echo "latest"
}

function _compare_versions() {
  # For Docker containers, comparing versions is less relevant
  # since we're working with images and not actual game files
  # We can pull the latest image and check if it's different
  echo "latest"
  return $EC_SUCCESS # Return 0 to indicate update is available
}

function _save_version() {
  local version=$1

  __print_info "Saving version ${version}..."

  echo "$version" >"$instance_version_file"

  __print_success "Version saved"
  return $EC_SUCCESS
}

