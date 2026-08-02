#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# --- Debug flag handling ---
# Enables debug mode if --debug flag is present or if KGSM_DEBUG is set.
# This ensures that debug mode propagates to all sub-modules.
__kgsm_enable_debug() {
  declare -g PS4='+(\033[0;33m${BASH_SOURCE}:${LINENO}\033[0m): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  export PS4
  set -x
}

# If the debug flag is passed, export an environment variable to propagate it.
# shellcheck disable=SC2199
if [[ $@ =~ "--debug" ]]; then
  export KGSM_DEBUG=true
  declare -g KGSM_DEBUG=true
  # Remove the flag from the arguments to prevent parsing errors in modules.
  _new_args=()
  for _arg in "$@"; do
    if [[ "$_arg" != "--debug" ]]; then
      _new_args+=("$_arg")
    fi
  done
  set -- "${_new_args[@]}"
  unset _new_args _arg
fi

# Enable debug mode if the environment variable is set.
if [[ "${KGSM_DEBUG:-false}" == "true" ]]; then
  __kgsm_enable_debug
fi
unset -f __kgsm_enable_debug

# --- KGSM_ROOT setup ---
# Check for KGSM_ROOT. If it's not set, determine it from this script's location.
# This makes the library self-aware and keeps module logic clean.
if [[ -z "$KGSM_ROOT" ]]; then
  # This script (bootstrap.sh) is in .../core/. Its parent dir is KGSM_ROOT.
  _bootstrap_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _kgsm_root="$(cd "$_bootstrap_dir/.." && pwd)"
  export KGSM_ROOT="$_kgsm_root"
  declare -g KGSM_ROOT
  unset _bootstrap_dir _kgsm_root
fi

# --- KGSM version ---
# The single source of truth for the running version, managed by the package
# manager. It lives here rather than in kgsm.sh because KGSM is a
# multi-entrypoint CLI: a module under commands/ can be invoked directly, and
# anything that stamps a version (event payloads, the webhook User-Agent) must
# report the same value no matter which entrypoint reached it.
declare -g KGSM_VERSION="3.5.0-rc1"
export KGSM_VERSION

if [[ -n "${KGSM_BOOTSTRAP_LOADED:-}" ]]; then
  return 0
fi

# --- Load paths configuration ---
# shellcheck source=paths.sh
source "$KGSM_ROOT/core/paths.sh" || {
  echo "ERROR: Failed to load paths.sh" >&2
  exit 1
}

# --- Initialize user directories ---
__init_user_directories || {
  echo "ERROR: Failed to initialize user directories" >&2
  exit 1
}

# Load common.sh library.
# shellcheck source=common.sh
source "$KGSM_ROOT/core/common.sh" || {
  echo -e "ERROR: Failed to load common.sh library" >&2
  exit 1
}

declare -g KGSM_BOOTSTRAP_LOADED=1
export KGSM_BOOTSTRAP_LOADED
