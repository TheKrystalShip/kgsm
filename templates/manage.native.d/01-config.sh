# =============================================================================
# CONFIGURATION AND INITIALIZATION
# =============================================================================

# Color output support
COLOR_RED="" COLOR_GREEN="" COLOR_ORANGE="" COLOR_BLUE="" COLOR_END=""
if test -t 1 && command -v tput >/dev/null 2>&1; then
  if [[ "$(tput colors 2>/dev/null)" -gt 8 ]] 2>/dev/null; then
    COLOR_RED="\033[0;31m"
    COLOR_GREEN="\033[0;32m"
    COLOR_ORANGE="\033[0;33m"
    COLOR_BLUE="\033[0;34m"
    COLOR_END="\033[0m"
  fi
fi

function __print_success() {
  echo -e "[${COLOR_GREEN}SUCCESS${COLOR_END}] ${BASH_SOURCE[-1]##*/}:${BASH_LINENO[0]} $1"
}

function __print_info() {
  echo -e "[${COLOR_BLUE}INFO${COLOR_END}] ${BASH_SOURCE[-1]##*/}:${BASH_LINENO[0]} $1"
}

function __print_error() {
  echo -e "[${COLOR_RED}ERROR${COLOR_END}] ${BASH_SOURCE[-1]##*/}:${BASH_LINENO[0]} $1" >&2
}

function __print_warning() {
  echo -e "[${COLOR_ORANGE}WARNING${COLOR_END}] ${BASH_SOURCE[-1]##*/}:${BASH_LINENO[0]} $1" >&2
}

# Local exit code constants (mirrors core/errors.sh for standalone use)
readonly EC_SUCCESS=0
readonly EC_ERROR=1
readonly EC_MISSING_ARG=7
readonly EC_INVALID_ARG=8

# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Security function to validate configuration keys
# Prevents code injection through malicious config files by ensuring

# only safe variable names can be exported to the environment
function __validate_config_key() {
  local key="$1"

  # Allow only alphanumeric characters and underscores
  # Key must start with letter or underscore
  # This prevents injection of special shell variables or commands
  if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    return $EC_SUCCESS
  else
    return $EC_ERROR
  fi
}

# Function to source the instance configuration file
function __source_instance_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Instance configuration file not found: $config_file"
    exit $EC_ERROR
  fi

  # Source the configuration file and prefix all variables with "instance_"
  # Added security validation to prevent code injection attacks
  while IFS='=' read -r key value || [ -n "$key" ]; do
    # Skip comments and empty lines
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue

    # Remove leading/trailing whitespace
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    # Security check: Validate key name to prevent code injection
    if ! __validate_config_key "$key"; then
      echo "ERROR: Invalid configuration key '$key' in $config_file"
      echo "Configuration keys must contain only alphanumeric characters and underscores,"
      echo "and must start with a letter or underscore."
      exit $EC_ERROR
    fi

    # Remove quotes from value
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"

    # Check if the key already starts with "instance_"
    if [[ "$key" =~ ^instance_ ]]; then
      # If it already has the prefix, export it as is
      export "${key}=${value}"
    else
      # Otherwise, add the "instance_" prefix
      export "instance_${key}=${value}"
    fi
  done <"$config_file"
}

# Resolve a Steam credential by name (STEAM_USERNAME / STEAM_PASSWORD).
# The process environment is authoritative; the [steam] section of the KGSM
# config file is the fallback, so callers that carry no shell environment
# (the watchdog, systemd units, cron) can still authenticate. Echoes the
# value, or nothing when neither source provides one.
function __get_steam_credential() {
  local key="$1"
  local value="${!key}"

  if [[ -n "$value" ]]; then
    echo "$value"
    return $EC_SUCCESS
  fi

  local kgsm_config_file
  kgsm_config_file="${KGSM_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/kgsm/config.ini}"

  if [[ ! -f "$kgsm_config_file" ]]; then
    return $EC_SUCCESS
  fi

  # Anchored to the line start so commented-out keys never match
  value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$kgsm_config_file" 2>/dev/null |
    head -n1 | cut -d= -f2-)

  # Trim surrounding whitespace, then strip a single layer of quotes
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"

  echo "$value"
  return $EC_SUCCESS
}

# Source the instance configuration file
INSTANCE_NAME="$(basename "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/${INSTANCE_NAME}.config.ini"

if [[ ! -f "$CONFIG_FILE" ]]; then
  __print_error "Configuration file not found: $CONFIG_FILE"
  exit $EC_ERROR
fi

__source_instance_config "$CONFIG_FILE"

# Where the last upstream version this instance checked for is recorded. Derived
# rather than required, so an instance whose config predates the key works with
# no migration — the path is a function of the instance, not a choice.
: "${instance_latest_version_file:=${instance_working_dir}/.${INSTANCE_NAME}.latest}"
export instance_latest_version_file

# =============================================================================
# UPDATE-CHECK STATE
#
# The last upstream version an update check found, and the moment it was
# fetched. Two lines, because a value read back off disk and the moment it was
# really fetched are different facts, and a surface that prints the first has to
# be able to say how old it is.
#
# Only 'check-update --emit' writes this, which is what makes it double as the
# record of what has already been announced: a version already recorded here is
# one this instance has reported, so it is not reported again.
#
# These live in this module — structural, never overridden — rather than beside
# the version helpers in 05-version.sh, which IS overridable. There is nothing
# game-specific about reading and writing a file, and an override module must
# reproduce every function of the default it replaces: putting them there would
# mean four existing game overrides silently lacked them.
# =============================================================================

# The recorded upstream version, or nothing when no check has ever run.
function _get_stored_latest_version() {
  [[ -s "$instance_latest_version_file" ]] || return $EC_SUCCESS
  head -n1 "$instance_latest_version_file"
}

# When that version was fetched (ISO-8601 UTC), or nothing. Never a substitute
# moment: a recorded version with no recorded time reads as unknown, because
# stamping "now" onto a value that came off disk would claim a fetch that did
# not happen.
function _get_stored_latest_checked_at() {
  [[ -s "$instance_latest_version_file" ]] || return $EC_SUCCESS
  sed -n '2p' "$instance_latest_version_file"
}

# Record an upstream version as of now. The timestamp is the moment of THIS
# call, so it is only ever written by a path that has just completed a real
# fetch.
function _save_latest_version() {
  local version="$1"

  if [[ -z "$version" ]]; then
    __print_error "Refusing to record an empty upstream version"
    return $EC_INVALID_ARG
  fi

  printf '%s\n%s\n' "$version" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    >"$instance_latest_version_file"
}


self=$(basename "$0")

set -o pipefail

