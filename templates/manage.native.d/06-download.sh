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
    local steam_username steam_password
    steam_username="$(__get_steam_credential STEAM_USERNAME)"
    steam_password="$(__get_steam_credential STEAM_PASSWORD)"

    if [[ -z "$steam_username" ]]; then
      __print_error "'STEAM_USERNAME' is expected but it's not set"
      __print_error "Set it in the environment, or under [steam] in ${KGSM_CONFIG_FILE:-~/.config/kgsm/config.ini}"
      return $EC_ERROR
    fi

    # The password is optional. SteamCMD stores a refresh token after a login
    # that satisfies Steam Guard, and a username-only login spends that token,
    # which is what makes an unattended download possible on an account with
    # Steam Guard enabled. Supplying a password takes the password path even
    # when a token is stored, and that path replaces the stored token — so a
    # host that has been logged in once should leave the password unset.
    login_args="$steam_username"
    if [[ -n "$steam_password" ]]; then
      login_args="$steam_username $steam_password"
    fi
  fi

  # shellcheck disable=SC2086
  if ! steamcmd \
    +@sSteamCmdForcePlatformType "${instance_platform:-linux}" \
    +force_install_dir "${dest}" \
    +login ${login_args} \
    +app_update "${app_id}" ${instance_steamcmd_arguments:-} \
    validate \
    +quit; then
    __print_error "SteamCMD exited non-zero downloading app ${app_id}"
    return $EC_ERROR
  fi

  # SteamCMD reports success it did not achieve: a login that never completed,
  # or an account-gated app fetched anonymously, still exits 0, prints
  # "Success! App fully installed", and writes a manifest claiming StateFlags 4
  # with no depots in it. Content arriving on disk is the only signal that
  # distinguishes a real download, so check for it rather than trust the report.
  local _downloaded_file
  _downloaded_file=$(find "${dest}" -mindepth 1 -type f \
    -not -path "${dest}/steamapps/*" -print -quit 2>/dev/null)

  if [[ -z "$_downloaded_file" ]]; then
    __print_error "SteamCMD reported success but downloaded no game files"
    __print_error "Verify the Steam credentials, and that the account owns app ${app_id}"
    return $EC_ERROR
  fi

  __print_success "Download complete"
  return $EC_SUCCESS
}

