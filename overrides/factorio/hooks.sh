#!/usr/bin/env bash
#
# Factorio: the headless server comes from factorio.com, not from Steam.
#
# Hooks read the instance's values as instance_<snake_case> variables, write
# diagnostics to stderr and fail with a non-zero exit. Each runs in a subshell
# under set -e.
#
# shellcheck disable=SC2154,SC2329

# The stable headless release.
kgsm_hook_latest_version() {
  local version

  version="$(curl -fsSL --max-time "$instance_download_timeout_seconds" \
    https://factorio.com/api/latest-releases | jq -r '.stable.headless // empty')"
  if [[ -z "$version" ]]; then
    echo "factorio.com names no stable headless release" >&2
    return 1
  fi

  echo "$version"
}

# <version> <dest_dir>: the headless archive, unpacked without its top folder.
kgsm_hook_download() {
  local version="$1" dest="$2"
  local archive="${dest}/factorio_headless.tar.xz"

  curl -fsSL --max-time "$instance_download_timeout_seconds" -o "$archive" \
    "https://factorio.com/get-download/${version}/headless/linux64"
  tar -xf "$archive" --strip-components=1 -C "$dest"
  rm -f "$archive"
}

# <install_dir>: the server will not start without a save, so one is created
# when the level has none.
kgsm_hook_post_deploy() {
  local save="${instance_saves_dir}/${instance_level_name}"

  mkdir -p "$instance_saves_dir"
  if [[ -f "$save" || -f "${save}.zip" ]]; then
    return 0
  fi

  if ! (cd "$instance_launch_dir" && "$instance_executable_file" --create "$save" >/dev/null 2>&1); then
    echo "Failed to create the save ${instance_level_name}; the server cannot start without it" >&2
    return 1
  fi
}
