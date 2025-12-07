#!/bin/bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

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
      return $EC_GENERAL
    fi
  done

  echo "${grouped_ports[@]}"
}

export -f __parse_ufw_to_upnp_ports

function __parse_docker_compose_to_ufw_ports() {
  local blueprint_abs_path="$1"
  local ufw_ports=()

  # Extract port definitions from the docker-compose file
  # We're looking for lines like:      - "9876:9876/udp"
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue

    # Look for port definitions
    if [[ "$line" =~ [[:space:]]*-[[:space:]]*\"?([0-9]+):([0-9]+)/(tcp|udp)\"? ]]; then
      # Extract host port and protocol
      local host_port="${BASH_REMATCH[1]}"
      local protocol="${BASH_REMATCH[3]}"
      ufw_ports+=("${host_port}/${protocol}")
    fi
  done <"$blueprint_abs_path"

  # Join all port definitions with pipe symbol for UFW format
  if [[ ${#ufw_ports[@]} -gt 0 ]]; then
    echo "$(
      IFS='|'
      echo "${ufw_ports[*]}"
    )"
  else
    echo ""
  fi
}

export -f __parse_docker_compose_to_ufw_ports

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

  # Remove common extensions (.bp, .docker-compose.yml, .yaml)
  blueprint_name="${blueprint_name%.bp}"
  blueprint_name="${blueprint_name%.docker-compose.yml}"
  blueprint_name="${blueprint_name%.docker-compose.yaml}"
  blueprint_name="${blueprint_name%.yaml}"
  blueprint_name="${blueprint_name%.yml}"

  # Return the clean blueprint name
  echo "$blueprint_name"
}

export -f __extract_blueprint_name

export KGSM_PARSER_LOADED=1
