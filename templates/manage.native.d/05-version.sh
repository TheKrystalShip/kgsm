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
  # Build login arguments based on authentication requirement
  local login_args="anonymous"
  if [[ "$instance_is_steam_account_required" == "true" ]]; then
    local steam_username steam_password
    steam_username="$(__get_steam_credential STEAM_USERNAME)"
    steam_password="$(__get_steam_credential STEAM_PASSWORD)"

    if [[ -z "$steam_username" ]]; then
      __print_error "STEAM_USERNAME is expected but it's not set"
      __print_error "Set it in the environment, or under [steam] in ${KGSM_CONFIG_FILE:-~/.config/kgsm/config.ini}"
      return $EC_ERROR
    fi

    # The password is optional; a username-only login spends the refresh token
    # SteamCMD stored at the last login that satisfied Steam Guard. See
    # _download for why supplying one costs that token.
    login_args="$steam_username"
    if [[ -n "$steam_password" ]]; then
      login_args="$steam_username $steam_password"
    fi
  fi

  local latest_version
  latest_version=$(
    steamcmd \
      +login $login_args \
      +app_info_update 1 \
      +app_info_print $instance_steam_app_id \
      +quit |
      tr '\n' ' ' |
      grep --color=NEVER \
        -Po '"branches"\s*{\s*"public"\s*{\s*"buildid"\s*"\K(\d*)'
  )

  if [[ -z "$latest_version" ]]; then
    __print_error "Failed to retrieve latest version, got empty response from SteamCMD"
    return $EC_ERROR
  fi

  echo "$latest_version"
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
