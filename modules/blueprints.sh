#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../lib/bootstrap.sh"

function usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Blueprint Management for Krystal Game Server Manager${END}

Provides tools to create, list, and manage game server blueprints - the templates used to create server instances.

${UNDERLINE}Usage:${END}
  $(basename "$0") [OPTIONS]

${UNDERLINE}General Options:${END}
  -h, --help                    Display this help information

${UNDERLINE}Blueprint Listing & Information:${END}
  --list                        Display all available blueprints
    --default                   Show only official default blueprints
    --custom                    Show only user-created custom blueprints
    --detailed --json           Output detailed blueprint information in JSON format
  --info <blueprint>            Display the contents of a specific blueprint file
    --json                      Format the output as JSON
  --find <blueprint>            Locate the absolute path to a blueprint file

${UNDERLINE}Blueprint Creation:${END}
  Blueprints should be created manually by copying and modifying the template file:
  $KGSM_ROOT/templates/blueprint.tp

${UNDERLINE}Examples:${END}
  $(basename "$0") --list
  $(basename "$0") --list --custom
  $(basename "$0") --list --default
"
}

if [[ "$#" -eq 0 ]]; then
  usage
  exit $EC_MISSING_ARG
fi

module_native="$(__find_module blueprints.native.sh)"
module_container="$(__find_module blueprints.container.sh)"

function _combine_blueprint_results() {
  local native_results
  native_results=$("$(__find_module blueprints.native.sh)" "$@")
  local native_exit=$?

  local container_results
  container_results=$("$(__find_module blueprints.container.sh)" "$@")
  local container_exit=$?

  # If both modules failed, return an error
  if [[ $native_exit -ne 0 && $container_exit -ne 0 ]]; then
    return $EC_NOT_FOUND
  fi

  # Output the combined results
  if [[ -n "$native_results" ]]; then
    echo "$native_results"
  fi

  if [[ -n "$container_results" ]]; then
    echo "$container_results"
  fi

  return 0
}

function _list_blueprints() {
  # Get blueprints from both native and container modules and combine them
  local native_cmd_args="--list"
  local container_cmd_args="--list"

  # Pass the json flag if set
  if [[ -n "$json_format" ]]; then
    native_cmd_args="$native_cmd_args --json"
    container_cmd_args="$container_cmd_args --json"
  fi

  local native_blueprints
  native_blueprints=$("$(__find_module blueprints.native.sh)" $native_cmd_args)
  local native_exit=$?

  local container_blueprints
  container_blueprints=$("$(__find_module blueprints.container.sh)" $container_cmd_args)
  local container_exit=$?

  # If JSON output is requested, combine the JSON objects
  if [[ -n "$json_format" ]]; then
    if [[ $native_exit -eq 0 && $container_exit -eq 0 && -n "$native_blueprints" && -n "$container_blueprints" ]]; then
      # Merge both JSON arrays, remove empty strings, and ensure unique entries
      jq -s 'add | map(select(length > 0)) | unique' <(echo "$native_blueprints") <(echo "$container_blueprints")
      return 0
    elif [[ $native_exit -eq 0 && -n "$native_blueprints" ]]; then
      # Filter out empty strings from native blueprints
      jq 'map(select(length > 0)) | unique' <(echo "$native_blueprints")
      return 0
    elif [[ $container_exit -eq 0 && -n "$container_blueprints" ]]; then
      # Filter out empty strings from container blueprints
      jq 'map(select(length > 0)) | unique' <(echo "$container_blueprints")
      return 0
    fi
    # If we got here, no valid JSON was returned
    echo "[]"
    return 0
  else
    # For non-JSON, combine and sort unique blueprints
    printf "%s\n%s\n" "$native_blueprints" "$container_blueprints" | grep -v '^$' | sort -u
    return 0
  fi
}

function _list_custom_blueprints() {
  # Get blueprints from both native and container modules and combine them
  local native_cmd_args="--list --custom"
  local container_cmd_args="--list --custom"

  # Pass the json flag if set
  if [[ -n "$json_format" ]]; then
    native_cmd_args="$native_cmd_args --json"
    container_cmd_args="$container_cmd_args --json"
  fi

  local native_blueprints
  native_blueprints=$("$(__find_module blueprints.native.sh)" $native_cmd_args)
  local native_exit=$?

  local container_blueprints
  container_blueprints=$("$(__find_module blueprints.container.sh)" $container_cmd_args)
  local container_exit=$?

  # If JSON output is requested, combine the JSON objects
  if [[ -n "$json_format" ]]; then
    if [[ $native_exit -eq 0 && $container_exit -eq 0 && -n "$native_blueprints" && -n "$container_blueprints" ]]; then
      # Merge both JSON arrays, remove empty strings, and ensure unique entries
      jq -s 'add | map(select(length > 0)) | unique' <(echo "$native_blueprints") <(echo "$container_blueprints")
      return 0
    elif [[ $native_exit -eq 0 && -n "$native_blueprints" ]]; then
      # Filter out empty strings from native blueprints
      jq 'map(select(length > 0)) | unique' <(echo "$native_blueprints")
      return 0
    elif [[ $container_exit -eq 0 && -n "$container_blueprints" ]]; then
      # Filter out empty strings from container blueprints
      jq 'map(select(length > 0)) | unique' <(echo "$container_blueprints")
      return 0
    fi
    # If we got here, no valid JSON was returned
    echo "[]"
    return 0
  else
    # For non-JSON, combine and sort unique blueprints
    printf "%s\n%s\n" "$native_blueprints" "$container_blueprints" | grep -v '^$' | sort -u
    return 0
  fi
}

function _list_default_blueprints() {
  # Get blueprints from both native and container modules and combine them
  local native_cmd_args="--list --default"
  local container_cmd_args="--list --default"

  # Pass the json flag if set
  if [[ -n "$json_format" ]]; then
    native_cmd_args="$native_cmd_args --json"
    container_cmd_args="$container_cmd_args --json"
  fi

  local native_blueprints
  native_blueprints=$("$(__find_module blueprints.native.sh)" $native_cmd_args)
  local native_exit=$?

  local container_blueprints
  container_blueprints=$("$(__find_module blueprints.container.sh)" $container_cmd_args)
  local container_exit=$?

  # If JSON output is requested, combine the JSON objects
  if [[ -n "$json_format" ]]; then
    if [[ $native_exit -eq 0 && $container_exit -eq 0 && -n "$native_blueprints" && -n "$container_blueprints" ]]; then
      # Merge both JSON arrays, remove empty strings, and ensure unique entries
      jq -s 'add | map(select(length > 0)) | unique' <(echo "$native_blueprints") <(echo "$container_blueprints")
      return 0
    elif [[ $native_exit -eq 0 && -n "$native_blueprints" ]]; then
      # Filter out empty strings from native blueprints
      jq 'map(select(length > 0)) | unique' <(echo "$native_blueprints")
      return 0
    elif [[ $container_exit -eq 0 && -n "$container_blueprints" ]]; then
      # Filter out empty strings from container blueprints
      jq 'map(select(length > 0)) | unique' <(echo "$container_blueprints")
      return 0
    fi
    # If we got here, no valid JSON was returned
    echo "[]"
    return 0
  else
    # For non-JSON, combine and sort unique blueprints
    printf "%s\n%s\n" "$native_blueprints" "$container_blueprints" | grep -v '^$' | sort -u
    return 0
  fi
}

function _list_detailed_blueprints() {
  # For detailed listings, we need to handle JSON format separately
  if [[ -n "$json_format" ]]; then
    local native_json
    native_json=$("$module_native" --list --detailed --json 2>/dev/null)
    local native_exit=$?

    local container_json
    container_json=$("$module_container" --list --detailed --json 2>/dev/null)
    local container_exit=$?

    # Combine the JSON results (this assumes the outputs are valid JSON objects)
    if [[ $native_exit -eq 0 && $container_exit -eq 0 && -n "$native_json" && -n "$container_json" ]]; then
      # Merge both JSON objects and filter out any empty key entries
      jq -s '.[0] * .[1] | with_entries(select(.key != ""))' <(echo "$native_json") <(echo "$container_json")
    elif [[ $native_exit -eq 0 && -n "$native_json" ]]; then
      # Filter out any empty key entries from native JSON
      jq 'with_entries(select(.key != ""))' <(echo "$native_json")
    elif [[ $container_exit -eq 0 && -n "$container_json" ]]; then
      # Filter out any empty key entries from container JSON
      jq 'with_entries(select(.key != ""))' <(echo "$container_json")
    else
      # Return empty object if no results
      echo "{}"
    fi
  else
    # If not JSON, just use the regular list function
    _list_blueprints
  fi
}

function _print_blueprint() {
  local blueprint="$1"

  # VALIDATION: Ensure blueprint exists and is valid before printing
  validate_blueprint "$blueprint"
  local validation_result=$?
  if [[ $validation_result -ne 0 ]]; then
    return $validation_result
  fi

  # Try to get the blueprint from the native module
  local blueprint_content
  blueprint_content=$("$(__find_module blueprints.native.sh)" --info "$blueprint" 2>/dev/null)
  local native_exit=$?

  if [[ $native_exit -eq 0 && -n "$blueprint_content" ]]; then
    echo "$blueprint_content"
    return 0
  fi

  # If not found in native module, try the container module
  blueprint_content=$("$(__find_module blueprints.container.sh)" --info "$blueprint" 2>/dev/null)
  local container_exit=$?

  if [[ $container_exit -eq 0 && -n "$blueprint_content" ]]; then
    echo "$blueprint_content"
    return 0
  fi

  return $EC_NOT_FOUND
}

function _find_blueprint() {
  local blueprint="$1"

  # VALIDATION: Ensure blueprint exists and is valid before finding path
  validate_blueprint "$blueprint"
  local validation_result=$?
  if [[ $validation_result -ne 0 ]]; then
    return $validation_result
  fi

  # If validation passed, get the blueprint path
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint")
  echo "$blueprint_path"
  return 0
}

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

while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --list)
    shift
    if [[ -z "$1" ]]; then
      _list_blueprints
      exit $?
    fi
    case "$1" in
    --default)
      _list_default_blueprints
      exit $?
      ;;
    --custom)
      _list_custom_blueprints
      exit $?
      ;;
    --detailed)
      _list_detailed_blueprints
      exit $?
      ;;
    *)
      __print_error "Invalid argument $1"
      exit $EC_INVALID_ARG
      ;;
    esac
    ;;
  --info)
    shift
    if [[ -z "$1" ]]; then
      __print_error "Missing argument <blueprint>"
      exit $EC_MISSING_ARG
    fi

    blueprint=$1
    _print_blueprint "$blueprint"
    exit $?
    ;;
  --find)
    shift
    if [[ -z "$1" ]]; then
      __print_error "Missing argument <blueprint>"
      exit $EC_MISSING_ARG
    fi

    blueprint=$1
    _find_blueprint "$blueprint"
    exit $?
    ;;
  *)
    __print_error "Invalid argument $1"
    exit $EC_INVALID_ARG
    ;;
  esac
  shift
done

exit $?
