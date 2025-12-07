#!/usr/bin/env bash

# Disabling SC2086 globally
# shellcheck disable=SC2086

# Params
if [ $# -eq 0 ]; then
  echo "${0##*/} ERROR: Sourcing error, blueprint name not specified" >&2 && exit $EC_MISSING_ARGS
fi

# Check for KGSM_ROOT env variable
if [ -z "$KGSM_ROOT" ]; then
  echo "${0##*/} WARNING: KGSM_ROOT not found, sourcing /etc/environment." >&2
  # shellcheck disable=SC1091
  source /etc/environment
  if [ -z "$KGSM_ROOT" ]; then
    echo "${0##*/} ERROR: KGSM_ROOT not found, exiting." >&2 && exit $EC_KGSM_ROOT
  else
    echo "${0##*/} INFO: KGSM_ROOT found in /etc/environment, consider rebooting the system" >&2
    if ! declare -p KGSM_ROOT | grep -q 'declare -x'; then export KGSM_ROOT; fi
  fi
fi

instance=$1

module_common="$(find "$KGSM_ROOT/lib" -type f -name common.sh -print -quit)"
[[ -z "$module_common" ]] && echo "${0##*/} ERROR: Could not find module common.sh" >&2 && exit $EC_FILE_NOT_FOUND

# shellcheck disable=SC1090
source "$module_common" || exit $EC_FAILED_SOURCE

instance_overrides_file=$(__find_override "$instance")

# Check if the overrides file exists
if [[ ! -f "$instance_overrides_file" ]]; then
  __print_info "No overrides file found for ${instance}, skipping."
  return 0
fi

# Import custom scripts if the game has any
if [[ -n "$instance_overrides_file" ]] && [[ -f "$instance_overrides_file" ]]; then
  # shellcheck disable=SC1090
  source "$instance_overrides_file" || exit $EC_FAILED_SOURCE
fi

export KGSM_OVERRIDES_LOADED=1
