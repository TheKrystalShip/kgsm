# =============================================================================
# VERSION MANAGEMENT
# =============================================================================

function _get_installed_version() {
  # shellcheck disable=SC2154
  # $instance_version_file is set dynamically from the config file
  # check "__source_instance_config"
  cat "$instance_version_file" 2>/dev/null || echo "unknown"
}

function _get_latest_version() {
  local timeout="${instance_wget_timeout_seconds:-60}"
  wget --timeout="$timeout" -qO - https://launchermeta.mojang.com/mc/game/version_manifest.json |
    jq -r '{latest: .latest.release} | .[]' |
    tr -d '"'
}

function _compare_versions() {
  local installed_version
  installed_version=$(_get_installed_version)

  local latest_version
  latest_version=$(_get_latest_version)

  if [[ -z "$latest_version" ]]; then
    __print_error "No version information was returned from remote"
    return $EC_ERROR
  fi

  if [[ "$latest_version" == "$installed_version" ]]; then
    __print_info "Local version is the same as remote version"
    return $EC_ERROR
  fi

  echo "$latest_version"
  return $EC_SUCCESS
}

function _save_version() {
  local version=$1

  __print_info "Saving version ${version}..."

  echo "$version" >"$instance_version_file"

  __print_success "Version saved"
  return $EC_SUCCESS
}
