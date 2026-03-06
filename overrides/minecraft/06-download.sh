# =============================================================================
# DOWNLOAD AND DEPLOYMENT
# =============================================================================

function _download() {
  local version="$1"
  local dest=${2:-$instance_temp_dir}
  local timeout="${instance_wget_timeout_seconds:-60}"

  __print_info "Downloading..."

  # shellcheck disable=SC2155
  local release_url="$(
    wget --timeout="$timeout" -qO - https://launchermeta.mojang.com/mc/game/version_manifest.json |
      jq -r "{versions: .versions} | .[] | .[] | select(.id == \"$version\") | {url: .url} | .[]"
  )"

  if [[ -z "$release_url" ]]; then
    __print_error "Could not find the URL of the latest release, exiting"
    return 1
  fi

  # shellcheck disable=SC2155
  local release_server_jar_url="$(
    wget --timeout="$timeout" -qO - "$release_url" |
      jq -r '{url: .downloads.server.url} | .[]'
  )"

  if [[ -z "$release_server_jar_url" ]]; then
    __print_error "Could not find the URL of the JAR file"
    return 1
  fi

  local local_release_jar="$dest/minecraft_server.$version.jar"

  if [ ! -f "$local_release_jar" ]; then
    wget --timeout="$timeout" -qO "$local_release_jar" "$release_server_jar_url"
  fi

  __print_success "Download complete"
  return $EC_SUCCESS
}
