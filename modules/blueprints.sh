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

  echo -e "${UNDERLINE}Blueprint Management for Krystal Game Server Manager${END}

Manages game server blueprints - the templates used to create server instances.

${UNDERLINE}Usage:${END}
  $self [command] [arguments] [options]

${UNDERLINE}Commands:${END}
  list [filter]               List available blueprints
  info <blueprint>            Display blueprint contents
  find <blueprint>            Get blueprint file path
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
  $self info terraria --json
  $self find minecraft
  $self help list

${UNDERLINE}Notes:${END}
  • Blueprints define server configuration templates
  • Use 'default' filter to show official blueprints
  • Use 'custom' filter to show user-created blueprints
  • Create new blueprints by copying templates/blueprint.tp
  • Both native and container blueprints are supported
"
}

function usage_list() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}List Blueprints${END}

List all available game server blueprints with optional filtering.

${UNDERLINE}Usage:${END}
  $self list [filter] [options]

${UNDERLINE}Filters:${END}
  (none)                      List all blueprints
  default                     Show only official default blueprints
  custom                      Show only user-created custom blueprints
  detailed                    Show detailed information for each blueprint

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Lists available blueprints from both native and container directories.
Default blueprints are provided by KGSM, while custom blueprints are
user-created. The detailed filter shows additional metadata for each blueprint.

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

  echo -e "${UNDERLINE}Blueprint Info${END}

Display the contents of a specific blueprint file.

${UNDERLINE}Usage:${END}
  $self info <blueprint> [options]

${UNDERLINE}Arguments:${END}
  blueprint                   Name of the blueprint to display

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Displays the complete contents of a blueprint file, including all
configuration parameters. The blueprint name can refer to either a
native (.bp) or container (docker-compose.yml) blueprint.

${UNDERLINE}Examples:${END}
  $self info factorio
  $self info terraria --json
  $self info minecraft
"
}

function usage_find() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Find Blueprint${END}

Locate the absolute path to a blueprint file.

${UNDERLINE}Usage:${END}
  $self find <blueprint>

${UNDERLINE}Arguments:${END}
  blueprint                   Name of the blueprint to find

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Returns the absolute file path to the specified blueprint. This is
useful for scripting and debugging. The command validates that the
blueprint exists and is valid before returning the path.

${UNDERLINE}Examples:${END}
  $self find factorio
  $self find terraria
  path=\$($self find minecraft)
"
}

# Source logic library
logic_library=$(__find_logic_library blueprints.sh)
# shellcheck disable=SC1090
source "$logic_library" || {
  __print_error "Failed to load blueprints logic library"
  exit $EC_FAILED_SOURCE
}

# Module references
module_native="$(__find_module blueprints.native.sh)"
module_container="$(__find_module blueprints.container.sh)"

# Command handler functions
function _cmd_list() {
  local filter=""
  local json_opt=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        usage_list
        return 0
        ;;
      --json)
        json_opt="--json"
        shift
        ;;
      default | custom | detailed)
        filter="$1"
        shift
        ;;
      *)
        __print_error "Invalid argument: $1"
        __print_error "Use '$self list --help' for usage information"
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Build command args for native and container modules
  local cmd_args="list"

  if [[ -n "$filter" ]]; then
    cmd_args="$cmd_args $filter"
  fi

  if [[ -n "$json_opt" ]]; then
    cmd_args="$cmd_args --json"
  fi

  # Get results from both modules
  local native_result
  native_result=$("$module_native" $cmd_args 2>/dev/null)
  local native_exit=$?

  local container_result
  container_result=$("$module_container" $cmd_args 2>/dev/null)
  local container_exit=$?

  # Combine results based on format
  if [[ -n "$json_opt" ]]; then
    # JSON format - merge arrays or objects
    if [[ "$filter" == "detailed" ]]; then
      # Detailed returns objects, not arrays
      if [[ $native_exit -eq 0 && $container_exit -eq 0 && -n "$native_result" && -n "$container_result" ]]; then
        jq -s '.[0] * .[1] | with_entries(select(.key != ""))' <(echo "$native_result") <(echo "$container_result")
      elif [[ $native_exit -eq 0 && -n "$native_result" ]]; then
        jq 'with_entries(select(.key != ""))' <(echo "$native_result")
      elif [[ $container_exit -eq 0 && -n "$container_result" ]]; then
        jq 'with_entries(select(.key != ""))' <(echo "$container_result")
      else
        echo "{}"
      fi
    else
      # Regular list returns arrays
      if [[ $native_exit -eq 0 && $container_exit -eq 0 && -n "$native_result" && -n "$container_result" ]]; then
        jq -s 'add | map(select(length > 0)) | unique' <(echo "$native_result") <(echo "$container_result")
      elif [[ $native_exit -eq 0 && -n "$native_result" ]]; then
        jq 'map(select(length > 0)) | unique' <(echo "$native_result")
      elif [[ $container_exit -eq 0 && -n "$container_result" ]]; then
        jq 'map(select(length > 0)) | unique' <(echo "$container_result")
      else
        echo "[]"
      fi
    fi
  else
    # Text format - combine and sort
    if [[ $native_exit -eq 0 || $container_exit -eq 0 ]]; then
      printf "%s\n%s\n" "$native_result" "$container_result" | grep -v '^$' | sort -u
    fi
  fi

  # Return success if at least one module succeeded
  if [[ $native_exit -eq 0 || $container_exit -eq 0 ]]; then
    return 0
  fi

  return $EC_NOT_FOUND
}

function _cmd_info() {
  local blueprint=""
  local json_opt=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        usage_info
        return 0
        ;;
      --json)
        json_opt="--json"
        shift
        ;;
      -*)
        __print_error "Invalid option: $1"
        __print_error "Use '$self info --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$blueprint" ]]; then
          blueprint="$1"
          shift
        else
          __print_error "Too many arguments"
          __print_error "Use '$self info --help' for usage information"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
  done

  # Validate blueprint argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '$self info --help' for usage information"
    return $EC_MISSING_ARG
  fi

  # Validate blueprint exists
  validate_blueprint "$blueprint"
  local validation_result=$?
  if [[ $validation_result -ne 0 ]]; then
    return $validation_result
  fi

  # Try native module first
  local cmd_args="info $blueprint"
  if [[ -n "$json_opt" ]]; then
    cmd_args="$cmd_args --json"
  fi

  local result
  result=$("$module_native" $cmd_args 2>/dev/null)
  local exit_code=$?

  if [[ $exit_code -eq 0 && -n "$result" ]]; then
    echo "$result"
    return 0
  fi

  # Try container module
  result=$("$module_container" $cmd_args 2>/dev/null)
  exit_code=$?

  if [[ $exit_code -eq 0 && -n "$result" ]]; then
    echo "$result"
    return 0
  fi

  __print_error "Blueprint not found: $blueprint"
  return $EC_BLUEPRINT_NOT_FOUND
}

function _cmd_find() {
  local blueprint=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        usage_find
        return 0
        ;;
      -*)
        __print_error "Invalid option: $1"
        __print_error "Use '$self find --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$blueprint" ]]; then
          blueprint="$1"
          shift
        else
          __print_error "Too many arguments"
          __print_error "Use '$self find --help' for usage information"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
  done

  # Validate blueprint argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '$self find --help' for usage information"
    return $EC_MISSING_ARG
  fi

  # Validate blueprint exists
  validate_blueprint "$blueprint"
  local validation_result=$?
  if [[ $validation_result -ne 0 ]]; then
    return $validation_result
  fi

  # Get blueprint path
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint")
  echo "$blueprint_path"
  return 0
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return 0
  fi

  case "$command" in
    list)
      usage_list
      ;;
    info)
      usage_info
      ;;
    find)
      usage_find
      ;;
    *)
      __print_error "Unknown command: $command"
      __print_error "Use '$self help' for available commands"
      return $EC_INVALID_ARG
      ;;
  esac

  return 0
}

# Check for no arguments
if [[ "$#" -eq 0 ]]; then
  show_usage
  exit 0
fi

# Handle legacy dash-style arguments for backward compatibility
# This supports the old `--list`, `--info`, `--find` syntax
if [[ "$1" == --* ]]; then
  case "$1" in
    --help | -h)
      show_usage
      exit 0
      ;;
    --list)
      shift
      _cmd_list "$@"
      exit $?
      ;;
    --info)
      shift
      _cmd_info "$@"
      exit $?
      ;;
    --find)
      shift
      _cmd_find "$@"
      exit $?
      ;;
    *)
      __print_error "Unknown option: $1"
      __print_error "Use '$self help' for available commands"
      exit $EC_INVALID_ARG
      ;;
  esac
fi

# Main command parsing (modern style)
command="$1"
shift

case "$command" in
  list)
    _cmd_list "$@"
    exit $?
    ;;
  info)
    _cmd_info "$@"
    exit $?
    ;;
  find)
    _cmd_find "$@"
    exit $?
    ;;
  help | -h | --help)
    _cmd_help "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$self help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac

# Mark module as loaded
export KGSM_MODULE_BLUEPRINTS_LOADED=1
