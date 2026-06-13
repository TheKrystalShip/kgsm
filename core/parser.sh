#!/bin/bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_PARSER_LOADED:-}" ]]; then
  return 0
fi

function __parse_ufw_to_upnp_ports() {
  local ufw_ports=$1
  local grouped_ports=()

  # Split the input into individual port ranges
  IFS='|' read -ra ranges <<<"$ufw_ports"

  for range in "${ranges[@]}"; do

    # Port range with protocol specified
    if [[ "$range" =~ ^([0-9]+):([0-9]+)/([a-z]+)$ ]]; then
      local start_port="${BASH_REMATCH[1]}"
      local end_port="${BASH_REMATCH[2]}"
      local protocol="${BASH_REMATCH[3]}"

      for port in $(seq "$start_port" "$end_port"); do
        grouped_ports+=("$port" "$protocol")
      done

    # Single port with protocol specified
    elif [[ "$range" =~ ^([0-9]+)/([a-z]+)$ ]]; then
      local port="${BASH_REMATCH[1]}"
      local protocol="${BASH_REMATCH[2]}"

      grouped_ports+=("$port" "$protocol")

    # Port range without protocol (assume both TCP and UDP)
    elif [[ "$range" =~ ^([0-9]+):([0-9]+)$ ]]; then
      local start_port="${BASH_REMATCH[1]}"
      local end_port="${BASH_REMATCH[2]}"

      for port in $(seq "$start_port" "$end_port"); do
        for protocol in tcp udp; do
          grouped_ports+=("$port" "$protocol")
        done
      done

    # Single port without protocol (assume both TCP and UDP)
    elif [[ "$range" =~ ^([0-9]+)$ ]]; then
      local port="${BASH_REMATCH[1]}"

      grouped_ports+=("$port" "tcp" "$port" "udp")

    # Nothing mathes, definition might be wrongly formatted
    else
      __print_error "Invalid port definition: $range"
      return $EC_ERROR
    fi
  done

  echo "${grouped_ports[@]}"
}

export -f __parse_ufw_to_upnp_ports

# Derive a UFW port spec from a unified container blueprint's embedded compose.
# Reads `.container.compose` (a literal block scalar) and converts each
# short-form `host:container/proto` mapping to `host/proto`, pipe-joined for UFW.
# Returns an empty string if there are no ports.
# Usage: __derive_ufw_ports_from_compose <blueprint_abs_path>
function __derive_ufw_ports_from_compose() {
  local blueprint_abs_path="$1"

  yq '.container.compose' "$blueprint_abs_path" 2>/dev/null \
    | yq -r '[.services.*.ports[]? | sub(":.*/", "/")] | join("|")' 2>/dev/null
}

export -f __derive_ufw_ports_from_compose

function __extract_blueprint_name() {
  local input="$1"
  local blueprint_name

  # Check if input is absolute path
  if [[ "$input" == /* ]]; then
    # Get the filename without the path
    blueprint_name=$(basename "$input")
  else
    # Input is already a filename
    blueprint_name="$input"
  fi

  # Strip the unified `.bp.yaml` extension as a single unit FIRST (sequential
  # single-suffix stripping would otherwise leave a trailing `.bp`). The legacy
  # `.bp` suffix is tolerated for any lingering pre-cutover reference.
  blueprint_name="${blueprint_name%.bp.yaml}"
  blueprint_name="${blueprint_name%.bp}"

  # Return the clean blueprint name
  echo "$blueprint_name"
}

export -f __extract_blueprint_name

declare -g KGSM_PARSER_LOADED=1
export KGSM_PARSER_LOADED
