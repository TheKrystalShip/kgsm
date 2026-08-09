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

self=$(basename "$0")

set -o pipefail

