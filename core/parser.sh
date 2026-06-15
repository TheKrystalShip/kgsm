#!/bin/bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_PARSER_LOADED:-}" ]]; then
  return 0
fi

# Parse a UFW-style port spec into canonical "<start> <end> <proto>" triples, one per
# line. This is the SINGLE source of truth for UFW-port parsing; every other port form
# (the structured JSON surface, the flat expanded list) derives from it. Range-preserving
# (a `start:end` stays one triple) and a proto-less entry expands to BOTH tcp and udp
# (UFW's implicit-both semantics). Pipe-separated entries. An empty spec echoes nothing
# and succeeds; a malformed entry returns EC_ERROR.
# Usage: __parse_ufw_port_spec <ufw_ports>
function __parse_ufw_port_spec() {
  local ufw_ports=$1
  [[ -z "$ufw_ports" ]] && return $EC_SUCCESS

  local -a ranges
  IFS='|' read -ra ranges <<<"$ufw_ports"

  local range
  for range in "${ranges[@]}"; do
    # Port range with protocol
    if [[ "$range" =~ ^([0-9]+):([0-9]+)/([a-z]+)$ ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    # Single port with protocol
    elif [[ "$range" =~ ^([0-9]+)/([a-z]+)$ ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    # Port range without protocol -> both tcp and udp
    elif [[ "$range" =~ ^([0-9]+):([0-9]+)$ ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} tcp"
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} udp"
    # Single port without protocol -> both tcp and udp
    elif [[ "$range" =~ ^([0-9]+)$ ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[1]} tcp"
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[1]} udp"
    # Nothing matches, definition is malformed
    else
      __print_error "Invalid port definition: $range"
      return $EC_ERROR
    fi
  done

  return $EC_SUCCESS
}

export -f __parse_ufw_port_spec

# Convert a UFW-style port spec to the canonical structured JSON array that machine
# consumers read off `instances info --json` (kgsm-lib Instance.Ports, kgsm-firewall,
# kgsm-api): [ { "start": <int>, "end": <int>, "protocol": "tcp|udp" }, ... ],
# range-preserving. An empty OR malformed spec yields "[]" (never an empty string, so the
# value is always valid JSON for `jq --argjson`).
# Usage: __ufw_ports_to_json <ufw_ports>
function __ufw_ports_to_json() {
  local ufw_ports=$1
  local triples
  if ! triples=$(__parse_ufw_port_spec "$ufw_ports") || [[ -z "$triples" ]]; then
    echo "[]"
    return $EC_SUCCESS
  fi

  echo "$triples" \
    | jq -R 'split(" ") | {start: (.[0] | tonumber), end: (.[1] | tonumber), protocol: .[2]}' \
    | jq -sc .
}

export -f __ufw_ports_to_json

# Expand a UFW-style port spec to the flat "port proto port proto ..." form (every port
# in a range listed individually) — what UPnP (`upnpc`) and the port-conflict scan need.
# Derived from __parse_ufw_port_spec so parsing lives in exactly one place. KGSM persists
# this (as a bash array) in an instance's `upnp_ports`, consumed by the non-watchdog
# fallback's embedded `_enable_upnp`; the watchdog expands the structured form itself.
# Usage: __parse_ufw_to_upnp_ports <ufw_ports>
function __parse_ufw_to_upnp_ports() {
  local ufw_ports=$1
  local triples
  triples=$(__parse_ufw_port_spec "$ufw_ports") || return $EC_ERROR

  local -a grouped_ports=()
  local start end proto port
  while read -r start end proto; do
    [[ -z "$start" ]] && continue
    for ((port = start; port <= end; port++)); do
      grouped_ports+=("$port" "$proto")
    done
  done <<<"$triples"

  echo "${grouped_ports[@]}"
  return $EC_SUCCESS
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
