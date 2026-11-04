#!/usr/bin/env bash
#
# Barotrauma: the server keeps its settings under the account's home.
#
# shellcheck disable=SC2154,SC2329

# <install_dir>: the directory the server expects under $HOME.
# https://barotraumagame.com/wiki/Hosting_a_Dedicated_Server#Linux_Dedicated_Server_Hosting
kgsm_hook_post_deploy() {
  if [[ -z "${HOME:-}" ]]; then
    echo "HOME is not set" >&2
    return 1
  fi

  mkdir -p "${HOME}/.local/share/Daedalic Entertainment GmbH/Barotrauma"
}
