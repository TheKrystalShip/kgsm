
function _deploy() {
  # For Docker containers, deploying is a noop
  # since the container is already defined in the docker-compose.yml file
  __print_info "Deploying Docker container..."

  # Return success
  __print_success "Deploy complete"
  return $EC_SUCCESS
}

