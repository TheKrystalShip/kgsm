#!/usr/bin/env bash
#
# Minecraft: the server jar comes from Mojang's launcher metadata.
#
# Hooks read the instance's values as instance_<snake_case> variables, write
# diagnostics to stderr and fail with a non-zero exit. Each runs in a subshell
# under set -e.
#
# shellcheck disable=SC2154,SC2329

# The latest release.
kgsm_hook_latest_version() {
  local version

  version="$(curl -fsSL --max-time "$instance_download_timeout_seconds" \
    https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r '.latest.release // empty')"
  if [[ -z "$version" ]]; then
    echo "Mojang's version manifest names no latest release" >&2
    return 1
  fi

  echo "$version"
}

# <version> <dest_dir>: the server jar of that release.
kgsm_hook_download() {
  local version="$1" dest="$2" manifest release_url jar_url

  manifest="$(curl -fsSL --max-time "$instance_download_timeout_seconds" \
    https://launchermeta.mojang.com/mc/game/version_manifest.json)"
  release_url="$(jq -r --arg version "$version" 'first(.versions[] | select(.id == $version) | .url) // empty' <<<"$manifest")"
  if [[ -z "$release_url" ]]; then
    echo "Could not find the release ${version} in Mojang's version manifest" >&2
    return 1
  fi

  jar_url="$(curl -fsSL --max-time "$instance_download_timeout_seconds" "$release_url" |
    jq -r '.downloads.server.url // empty')"
  if [[ -z "$jar_url" ]]; then
    echo "Release ${version} names no server jar" >&2
    return 1
  fi

  curl -fsSL --connect-timeout "$instance_download_timeout_seconds" \
    --speed-limit 1 --speed-time "$instance_download_timeout_seconds" \
    -o "${dest}/minecraft_server.${version}.jar" "$jar_url"
}

# <staging_dir> <install_dir>: the one jar, under the name the launch arguments use.
kgsm_hook_deploy() {
  local staging="$1" install="$2" jar

  jar="$(find "$staging" -maxdepth 1 -name '*.jar' -print -quit)"
  if [[ -z "$jar" ]]; then
    echo "The download holds no server jar" >&2
    return 1
  fi

  mv -f "$jar" "${install}/release.jar"
}

# <install_dir>: the server starts only once its EULA is accepted.
kgsm_hook_post_deploy() {
  echo "eula=true" >"${1}/eula.txt"
}
