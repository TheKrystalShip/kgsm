#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../lib/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Container Blueprint Management for Krystal Game Server Manager${END}

Manages containerized game server blueprints (docker-compose.yml files) - templates for Docker-based server deployments.

${UNDERLINE}Usage:${END}
  $self [command] [arguments] [options]

${UNDERLINE}Commands:${END}
  list [filter]               List available container blueprints
  info <blueprint>            Display container blueprint contents
  find <blueprint>            Get container blueprint file path
  help [command]              Show help information

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  -h, --help                  Show help and exit

${UNDERLINE}Examples:${END}
  $self list
  $self list default
  $self list custom
  $self list detailed
  $self list --json
  $self info factorio
  $self find terraria

${UNDERLINE}Notes:${END}
  • Container blueprints define Docker-based server configurations
  • Use 'default' filter to show official blueprints
  • Use 'custom' filter to show user-created blueprints
  • Blueprint files have .docker-compose.yml extension
"
}

function usage_list() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}List Container Blueprints${END}

List all available container game server blueprints with optional filtering.

${UNDERLINE}Usage:${END}
  $self list [filter] [options]

${UNDERLINE}Filters:${END}
  (none)                      List all container blueprints
  default                     Show only official default blueprints
  custom                      Show only user-created custom blueprints
  detailed                    Show detailed information for each blueprint

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self list
  $self list default
  $self list custom --json
  $self list detailed
"
}

function usage_info() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Container Blueprint Info${END}

Display the contents of a specific container blueprint file.

${UNDERLINE}Usage:${END}
  $self info <blueprint> [options]

${UNDERLINE}Arguments:${END}
  blueprint                   Name of the blueprint to display

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self info factorio
  $self info terraria --json
"
}

function usage_find() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Find Container Blueprint${END}

Locate the absolute path to a container blueprint file.

${UNDERLINE}Usage:${END}
  $self find <blueprint>

${UNDERLINE}Arguments:${END}
  blueprint                   Name of the blueprint to find

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self find factorio
  $self find minecraft
"
}

function _list_custom_container_blueprints() {
  shopt -s extglob nullglob

  local -a custom_bps=("$BLUEPRINTS_CUSTOM_CONTAINER_SOURCE_DIR"/*)
  custom_bps=("${custom_bps[@]#"$BLUEPRINTS_CUSTOM_CONTAINER_SOURCE_DIR/"}")

  # Strip file extensions (.docker-compose.yml)
  local -a stripped_bps=()

  # Only process if there are actually files found
  if [[ ${#custom_bps[@]} -gt 0 ]]; then
    for bp in "${custom_bps[@]}"; do
      local base_name
      base_name="${bp%.docker-compose.yml}"

      # Only add non-empty blueprint names
      if [[ -n "$base_name" ]]; then
        stripped_bps+=("$base_name")
      fi
    done
  fi

  if [[ -z "$json_format" ]]; then
    printf "%s\n" "${stripped_bps[@]}"
  else
    jq -n --argjson blueprints "$(printf '%s\n' "${stripped_bps[@]}" | jq -R . | jq -s .)" '$blueprints'
  fi
}

function _list_default_container_blueprints() {
  shopt -s extglob nullglob

  local -a default_bps=("$BLUEPRINTS_DEFAULT_CONTAINER_SOURCE_DIR"/*)
  default_bps=("${default_bps[@]#"$BLUEPRINTS_DEFAULT_CONTAINER_SOURCE_DIR/"}")

  # Strip file extensions (.docker-compose.yml)
  local -a stripped_bps=()

  # Only process if there are actually files found
  if [[ ${#default_bps[@]} -gt 0 ]]; then
    for bp in "${default_bps[@]}"; do
      local base_name
      base_name="${bp%.docker-compose.yml}"

      # Only add non-empty blueprint names
      if [[ -n "$base_name" ]]; then
        stripped_bps+=("$base_name")
      fi
    done
  fi

  if [[ -z "$json_format" ]]; then
    printf "%s\n" "${stripped_bps[@]}"
  else
    jq -n --argjson blueprints "$(printf '%s\n' "${stripped_bps[@]}" | jq -R . | jq -s .)" '$blueprints'
  fi
}

function _list_container_blueprints() {
  local previous_json_format=$json_format
  unset json_format

  # Combine both default and custom blueprints
  declare -a blueprint_list
  mapfile -t blueprint_list < <(_list_custom_container_blueprints; _list_default_container_blueprints)

  json_format=$previous_json_format

  # Remove duplicates and sort
  readarray -t blueprint_list < <(printf "%s\n" "${blueprint_list[@]}" | sort -du)

  if [[ -z "$json_format" ]]; then
    printf "%s\n" "${blueprint_list[@]}"
    return 0
  fi

  # Print contents as a JSON array of blueprint names
  jq -n --argjson blueprints "$(printf '%s\n' "${blueprint_list[@]}" | jq -R . | jq -s .)" '$blueprints'
}

function _list_detailed_container_blueprints() {
  local previous_json_format=$json_format
  unset json_format

  declare -a blueprint_list
  mapfile -t blueprint_list < <(_list_container_blueprints)

  json_format=$previous_json_format

  if [[ -z "$json_format" ]]; then
    printf "%s\n" "${blueprint_list[@]}"
    return 0
  fi

  # Build a JSON object with blueprint contents
  jq -n --argjson blueprints \
    "$(for blueprint in "${blueprint_list[@]}"; do
      # Skip empty blueprint names
      if [[ -z "$blueprint" ]]; then
        continue
      fi

      # Get the content of the blueprint as JSON
      local content
      content=$(_print_container_blueprint "$blueprint")
      # Skip blueprints with invalid content
      if [[ $? -ne 0 || -z "$content" ]]; then
        continue
      fi
      jq -n --arg key "$blueprint" --argjson value "$content" '{"key": $key, "value": $value}'
    done | jq -s 'from_entries')" '$blueprints'
}

function _print_container_blueprint() {
  local blueprint=$1

  local blueprint_path
  blueprint_path=$(__find_container_blueprint "$blueprint")

  if [[ -z "$json_format" ]]; then
    cat "$blueprint_path"
    return $?
  fi

  # For container blueprints, extract structured data from docker-compose.yml
  local name ports

  # Extract the blueprint name
  name="$blueprint"

  # Use the parser function to extract ports from docker-compose.yml
  ports=$(__parse_docker_compose_to_ufw_ports "$blueprint_path")

  # Return the same structure as native blueprints for consistency
  jq -n \
    --arg name "$name" \
    --arg ports "$ports" \
    '{
      Name: $name,
      Ports: $ports,
      BlueprintType: "Container",
      SteamAppId: "",
      IsSteamAccountRequired: "",
      ExecutableFile: "",
      LevelName: "",
      ExecutableSubdirectory: "",
      ExecutableArguments: "",
      StopCommand: "",
      SaveCommand: ""
    }'
}

function __find_container_blueprint() {
  local blueprint="$1"

  # If the blueprint has a .docker-compose.yml extension, remove it
  [[ "$blueprint" == *.docker-compose.yml ]] && blueprint="${blueprint%.docker-compose.yml}"

  # First check custom blueprints
  local bp_path="$BLUEPRINTS_CUSTOM_CONTAINER_SOURCE_DIR/$blueprint.docker-compose.yml"
  [[ -f "$bp_path" ]] && echo "$bp_path" && return 0

  # Then check default blueprints
  bp_path="$BLUEPRINTS_DEFAULT_CONTAINER_SOURCE_DIR/$blueprint.docker-compose.yml"
  [[ -f "$bp_path" ]] && echo "$bp_path" && return 0

  return $EC_NOT_FOUND
}

# Command handlers

function _cmd_list() {
  local filter=""
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      default|custom|detailed)
        filter="$1"
        shift
        ;;
      --help)
        usage_list
        exit 0
        ;;
      *)
        __print_error "Unknown argument for list command: $1"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Execute based on filter
  case "$filter" in
    default)
      _list_default_container_blueprints
      exit $?
      ;;
    custom)
      _list_custom_container_blueprints
      exit $?
      ;;
    detailed)
      _list_detailed_container_blueprints
      exit $?
      ;;
    "")
      _list_container_blueprints
      exit $?
      ;;
    *)
      __print_error "Invalid filter: $filter"
      exit $EC_INVALID_ARG
      ;;
  esac
}

function _cmd_info() {
  local blueprint=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_info
        exit 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        exit $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$blueprint" ]]; then
          blueprint="$1"
        else
          __print_error "Too many arguments"
          exit $EC_INVALID_ARG
        fi
        shift
        ;;
    esac
  done

  # Validate required argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    usage_info
    exit $EC_MISSING_ARG
  fi

  _print_container_blueprint "$blueprint"
  exit $?
}

function _cmd_find() {
  local blueprint=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_find
        exit 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        exit $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$blueprint" ]]; then
          blueprint="$1"
        else
          __print_error "Too many arguments"
          exit $EC_INVALID_ARG
        fi
        shift
        ;;
    esac
  done

  # Validate required argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    usage_find
    exit $EC_MISSING_ARG
  fi

  blueprint_path=$(__find_container_blueprint "$blueprint")
  if [[ -z "$blueprint_path" ]]; then
    __print_error "Container blueprint '$blueprint' not found"
    exit $EC_NOT_FOUND
  fi

  echo "$blueprint_path"
  exit 0
}

function _cmd_help() {
  if [[ -z "$1" ]]; then
    show_usage
    exit 0
  fi

  case "$1" in
    list)
      usage_list
      exit 0
      ;;
    info)
      usage_info
      exit 0
      ;;
    find)
      usage_find
      exit 0
      ;;
    *)
      __print_error "Unknown command: $1"
      show_usage
      exit $EC_INVALID_ARG
      ;;
  esac
}

# Main entry point

# Check for no arguments
if [[ $# -eq 0 ]]; then
  show_usage
  exit $EC_MISSING_ARG
fi

# Extract --json flag if present
# shellcheck disable=SC2199
if [[ $@ =~ "--json" ]]; then
  json_format=1
  for a; do
    shift
    case $a in
    --json) continue ;;
    *) set -- "$@" "$a" ;;
    esac
  done
fi

# Handle global flags
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_usage
  exit 0
fi

# Parse command
command="$1"
shift

case "$command" in
  list)
    _cmd_list "$@"
    ;;
  info)
    _cmd_info "$@"
    ;;
  find)
    _cmd_find "$@"
    ;;
  help)
    _cmd_help "$@"
    ;;
  *)
    __print_error "Unknown command: $command"
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac

exit $?
