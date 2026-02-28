#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Source logic library
logic_library=$(__find_command_handler blueprints.sh)
# shellcheck source=handlers/blueprints.sh
source "$logic_library" || {
  __print_error "Failed to load blueprints logic library"
  exit $EC_FAILED_SOURCE
}

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

function show_usage_list() {
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

function show_usage_info() {
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

function show_usage_find() {
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
  local blueprint_list
  local exit_code

  blueprint_list=$(__logic_list_container_blueprints "custom")
  exit_code=$?

  if [[ $exit_code -ne $EC_SUCCESS_BLUEPRINT_LISTED ]]; then
    return $exit_code
  fi

  if [[ -n "$blueprint_list" ]]; then
    if [[ -z "$json_format" ]]; then
      echo "$blueprint_list"
    else
      echo "$blueprint_list" | jq -R . | jq -s .
    fi
  fi

  return $exit_code
}

function _list_default_container_blueprints() {
  local blueprint_list
  local exit_code

  blueprint_list=$(__logic_list_container_blueprints "default")
  exit_code=$?

  if [[ $exit_code -ne $EC_SUCCESS_BLUEPRINT_LISTED ]]; then
    return $exit_code
  fi

  if [[ -n "$blueprint_list" ]]; then
    if [[ -z "$json_format" ]]; then
      echo "$blueprint_list"
    else
      echo "$blueprint_list" | jq -R . | jq -s .
    fi
  fi

  return $exit_code
}

function _list_container_blueprints() {
  local blueprint_list
  local exit_code

  blueprint_list=$(__logic_list_container_blueprints "all")
  exit_code=$?

  if [[ $exit_code -ne $EC_SUCCESS_BLUEPRINT_LISTED ]]; then
    return $exit_code
  fi

  if [[ -n "$blueprint_list" ]]; then
    if [[ -z "$json_format" ]]; then
      echo "$blueprint_list"
    else
      echo "$blueprint_list" | jq -R . | jq -s .
    fi
  fi

  return $exit_code
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
  local exit_code=$?

  if [[ $exit_code -ne $EC_SUCCESS_BLUEPRINT_FOUND ]]; then
    return $exit_code
  fi

  if [[ -z "$json_format" ]]; then
    cat "$blueprint_path"
    return $?
  fi

  # Get blueprint info from logic layer
  local info_data
  info_data=$(__logic_get_container_blueprint_info "$blueprint")
  exit_code=$?

  if [[ $exit_code -ne $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED ]]; then
    return $exit_code
  fi

  # Parse key=value data and convert to JSON
  local name="" ports=""

  while IFS='=' read -r key value; do
    case "$key" in
      name) name="$value" ;;
      ports) ports="$value" ;;
    esac
  done <<< "$info_data"

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
  __logic_find_container_blueprint "$@"
  return $?
}

# Command handlers

function _cmd_list() {
  local filter=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_list
        return 0
        ;;
      default | custom | detailed)
        filter="$1"
        shift
        ;;
      *)
        __print_error "Unknown argument for list command: $1"
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Execute based on filter
  local exit_code
  case "$filter" in
    default)
      _list_default_container_blueprints
      exit_code=$?
      ;;
    custom)
      _list_custom_container_blueprints
      exit_code=$?
      ;;
    detailed)
      _list_detailed_container_blueprints
      exit_code=$?
      ;;
    "")
      _list_container_blueprints
      exit_code=$?
      ;;
    *)
      __print_error "Invalid filter: $filter"
      return $EC_INVALID_ARG
      ;;
  esac

  # Interpret exit code
  case $exit_code in
    $EC_SUCCESS_BLUEPRINT_LISTED)
      __dispatch_event_from_exit_code $exit_code "system" "container" > /dev/null 2>&1
      return 0
      ;;
    *)
      return $exit_code
      ;;
  esac
}

function _cmd_info() {
  local blueprint=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_info
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        return $EC_INVALID_ARG
        ;;
      *)
        blueprint="$1"
        break
        ;;
    esac
    shift
  done

  # Validate required argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    show_usage_info
    exit $EC_MISSING_ARG
  fi

  # Call function and interpret exit code
  local exit_code
  _print_container_blueprint "$blueprint"
  exit_code=$?

  case $exit_code in
    0 | $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED)
      __dispatch_event_from_exit_code $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED "system" "$blueprint" > /dev/null 2>&1
      exit 0
      ;;
    $EC_BLUEPRINT_NOT_FOUND)
      __print_error "Container blueprint '$blueprint' not found"
      exit $EC_BLUEPRINT_NOT_FOUND
      ;;
    *)
      __print_error "Failed to retrieve blueprint information"
      exit $exit_code
      ;;
  esac
}

function _cmd_find() {
  local blueprint=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_find
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        return $EC_INVALID_ARG
        ;;
      *)
        blueprint="$1"
        break
        ;;
    esac
    shift
  done

  # Validate required argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    show_usage_find
    exit $EC_MISSING_ARG
  fi

  # Call logic function
  local exit_code
  local blueprint_path
  blueprint_path=$(__logic_find_container_blueprint "$blueprint")
  exit_code=$?

  # Interpret exit code
  case $exit_code in
    $EC_SUCCESS_BLUEPRINT_FOUND)
      echo "$blueprint_path"
      __dispatch_event_from_exit_code $exit_code "system" "$blueprint" > /dev/null 2>&1
      exit 0
      ;;
    $EC_BLUEPRINT_NOT_FOUND)
      __print_error "Container blueprint '$blueprint' not found"
      exit $EC_BLUEPRINT_NOT_FOUND
      ;;
    *)
      __print_error "Failed to find blueprint"
      exit $exit_code
      ;;
  esac
}

function _cmd_help() {
  if [[ -z "$1" ]]; then
    show_usage
    exit 0
  fi

  case "$1" in
    list)
      show_usage_list
      exit 0
      ;;
    info)
      show_usage_info
      exit 0
      ;;
    find)
      show_usage_find
      exit 0
      ;;
    *)
      __print_error "Unknown command: $1"
      show_usage
      exit $EC_INVALID_ARG
      ;;
  esac
}

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

# Parse command
command="${1:-}"
shift 2> /dev/null || true

case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  -h | --help | help)
    _cmd_help "$@"
    ;;
  list)
    _cmd_list "$@"
    ;;
  info)
    _cmd_info "$@"
    ;;
  find)
    _cmd_find "$@"
    ;;
  *)
    __print_error "Unknown command: $command"
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
