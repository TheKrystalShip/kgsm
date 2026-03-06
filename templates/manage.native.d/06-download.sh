# =============================================================================
# DOWNLOAD AND DEPLOYMENT
# =============================================================================

function _download() {
  local version=$1
  local dest=${2:-$instance_temp_dir}
  local app_id=${3:-$instance_steam_app_id}

  __print_info "Downloading..."

  # Warn users if they specify a version for Steam games
  if [[ -n "$version" ]] && [[ "$version" != "0" ]] && [[ "$version" != "latest" ]]; then
    __print_warning "Version parameter '$version' will be ignored for Steam games."
    __print_warning "Steam only supports downloading the latest version. For non-Steam games like Factorio or Minecraft, version selection may be supported."
  fi

  if [[ -z "$instance_steam_app_id" ]]; then
    __print_error "'instance_steam_app_id' is expected but it's not set"
    return $EC_ERROR
  fi

  if [[ -z "$instance_is_steam_account_required" ]]; then
    __print_error "'instance_is_steam_account_required' is expected but it's not set"
    return $EC_ERROR
  fi

  # Build login arguments based on authentication requirement
  local login_args="anonymous"
  if [[ "$instance_is_steam_account_required" == "true" ]]; then
    if [[ -z "$STEAM_USERNAME" ]]; then
      __print_error "'STEAM_USERNAME' is expected but it's not set"
      return $EC_ERROR
    fi

    if [[ -z "$STEAM_PASSWORD" ]]; then
      __print_error "'STEAM_PASSWORD' is expected but it's not set"
      return $EC_ERROR
    fi

    # Authenticated login: pass username and password as separate arguments
    login_args="$STEAM_USERNAME $STEAM_PASSWORD"
  fi

  # shellcheck disable=SC2086
  steamcmd \
    +@sSteamCmdForcePlatformType "${instance_platform:-linux}" \
    +force_install_dir "${dest}" \
    +login ${login_args} \
    +app_update "${app_id}" ${instance_steamcmd_arguments:-} \
    validate \
    +quit

  __print_success "Download complete"
  return $EC_SUCCESS
}

