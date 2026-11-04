#!/usr/bin/env bash
#
# Veloren: the server comes from Veloren's own download service.
#
# Hooks read the instance's values as instance_<snake_case> variables, write
# diagnostics to stderr and fail with a non-zero exit. Each runs in a subshell
# under set -e.
#
# shellcheck disable=SC2154,SC2329

# Veloren exposes no versioned API; "weekly" is a fixed name that always
# resolves to the latest weekly build.
kgsm_hook_latest_version() {
  echo "weekly"
}

# <version> <dest_dir>: the weekly build.
kgsm_hook_download() {
  local dest="$2"

  curl -fsSL --connect-timeout "$instance_download_timeout_seconds" \
    --speed-limit 1 --speed-time "$instance_download_timeout_seconds" -o "${dest}/weekly" \
    https://download.veloren.net/latest/linux/x86_64/weekly
  unzip -q "${dest}/weekly" -d "$dest"
  rm -f "${dest}/weekly"
}
