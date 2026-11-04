#!/usr/bin/env bash
#
# Terraria: the dedicated server comes from terraria.org, not from Steam.
#
# Hooks read the instance's values as instance_<snake_case> variables, write
# diagnostics to stderr and fail with a non-zero exit. Each runs in a subshell
# under set -e.
#
# shellcheck disable=SC2154,SC2329

# The newest dedicated-server archive's version number.
kgsm_hook_latest_version() {
  local name

  name="$(curl -fsSL --max-time "$instance_download_timeout_seconds" \
    https://terraria.org/api/get/dedicated-servers-names | jq -r '.[0] // empty')"
  name="${name#terraria-server-}"
  name="${name%%.*}"
  if [[ ! "$name" =~ ^[0-9]+$ ]]; then
    echo "terraria.org names no dedicated server version" >&2
    return 1
  fi

  echo "$name"
}

# <version> <dest_dir>: the archive unpacked, keeping only the Linux files.
kgsm_hook_download() {
  local version="$1" dest="$2"
  local archive="${dest}/terraria-server-${version}.zip"
  local root="${dest}/${version}"

  curl -fsSL --max-time "$instance_download_timeout_seconds" -o "$archive" \
    "https://terraria.org/api/download/pc-dedicated-server/terraria-server-${version}.zip"
  unzip -q "$archive" -d "$dest"
  rm -f "$archive"

  if [[ ! -d "${root}/Linux" ]]; then
    echo "The archive holds no Linux directory" >&2
    return 1
  fi

  cp -a "${root}/Linux/." "${dest}/"
  rm -rf "$root"
}

# <staging_dir> <install_dir>: moves the files in, which is cheaper than copying them.
kgsm_hook_deploy() {
  find "$1" -mindepth 1 -maxdepth 1 -exec mv -f -t "$2" {} +
}

# <install_dir>: the server binary is not executable as shipped.
kgsm_hook_post_deploy() {
  local -a binaries=("${1}"/TerrariaServer*)

  if [[ ! -e "${binaries[0]}" ]]; then
    echo "No TerrariaServer binary in ${1}" >&2
    return 1
  fi

  chmod +x "${binaries[@]}"
}
