#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086
# shellcheck disable=SC2254

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../lib/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Instance Management for Krystal Game Server Manager${END}

Manages game server instance lifecycle including creation, configuration, and monitoring.

${UNDERLINE}Usage:${END}
  $self [command] [arguments] [options]

${UNDERLINE}Commands:${END}
  create <blueprint>          Create a new instance from a blueprint
  remove <instance>           Remove an instance configuration
  list [blueprint]            List all instances or filter by blueprint
  info <instance>             Display instance configuration
  status <instance>           Show instance runtime status
  find <instance>             Get instance config file path
  generate-id <blueprint>     Generate unique instance identifier
  save <instance>             Send save command to instance
  input <instance> <command>  Send command to instance console
  regenerate <type>           Regenerate instance files
  help [command]              Show help information

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --fast                      Fast mode (skip version checks)
  -h, --help                  Show help and exit

${UNDERLINE}Examples:${END}
  $self create factorio --install-dir /opt --name factorio-01
  $self list
  $self list factorio
  $self list --json
  $self status factorio-01
  $self status factorio-01 --json --fast
  $self info factorio-01
  $self info factorio-01 --json
  $self find terraria-01
  $self save factorio-01
  $self input factorio-01 \"/say Hello players!\"
  $self regenerate management-script
  $self help create

${UNDERLINE}Notes:${END}
  • Instance names are auto-generated if not specified
  • Use --json for programmatic consumption
  • Status command shows process state, version, and resource usage
  • Regenerate updates instance files after KGSM updates
"
}

function usage_create() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Create Instance${END}

Create a new game server instance from a blueprint.

${UNDERLINE}Usage:${END}
  $self create <blueprint> [options]

${UNDERLINE}Arguments:${END}
  blueprint                   Blueprint name (with or without .bp extension)

${UNDERLINE}Options:${END}
  --install-dir <path>        Installation directory (required)
  --name <name>               Custom instance name (optional, auto-generated if not provided)
  --help                      Display this help information

${UNDERLINE}Description:${END}
Creates a new instance configuration file and sets up the instance structure.
If --name is not provided, a unique name will be auto-generated based on the
blueprint name. The installation directory must be specified and will contain
all instance data, saves, backups, and logs.

${UNDERLINE}Examples:${END}
  $self create factorio --install-dir /opt/gameservers
  $self create terraria --install-dir /home/user/servers --name terraria-main
  $self create minecraft.bp --install-dir /var/games
"
}

function usage_remove() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Remove Instance${END}

Remove an instance configuration file.

${UNDERLINE}Usage:${END}
  $self remove <instance>

${UNDERLINE}Arguments:${END}
  instance                    Instance name to remove

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Warning:${END}
This only removes the instance configuration file, not the actual server
files. Use the instance management script or directories module to remove
actual server data.

${UNDERLINE}Examples:${END}
  $self remove factorio-01
  $self remove terraria-main
"
}

function usage_list() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}List Instances${END}

List all instances or filter by blueprint.

${UNDERLINE}Usage:${END}
  $self list [blueprint] [options]

${UNDERLINE}Arguments:${END}
  blueprint                   Optional blueprint name to filter by

${UNDERLINE}Options:${END}
  --detailed                  Show detailed instance information
  --status                    Show runtime status for all instances
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self list
  $self list factorio
  $self list --detailed
  $self list --json
  $self list factorio --detailed --json
  $self list --status
"
}

function usage_info() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Instance Info${END}

Display instance configuration information.

${UNDERLINE}Usage:${END}
  $self info <instance> [options]

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Shows the raw instance configuration file or outputs it as JSON for
programmatic consumption.

${UNDERLINE}Examples:${END}
  $self info factorio-01
  $self info terraria-main --json
"
}

function usage_status() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Instance Status${END}

Show comprehensive runtime status for an instance.

${UNDERLINE}Usage:${END}
  $self status <instance> [options]

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --fast                      Fast mode (skip version checks)
  --help                      Display this help information

${UNDERLINE}Description:${END}
Displays runtime status including: active/inactive state, process info,
resource usage, version status, disk usage, backup count, and recent log
activity.

Fast mode skips version comparison for faster response times, ideal for
frequent monitoring or web APIs.

${UNDERLINE}Examples:${END}
  $self status factorio-01
  $self status terraria-main --json
  $self status minecraft-server --fast
  $self status factorio-01 --json --fast
"
}

function usage_find() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Find Instance${END}

Get the absolute path to an instance configuration file.

${UNDERLINE}Usage:${END}
  $self find <instance>

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self find factorio-01
  $self find terraria-main
"
}

function usage_generate_id() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Generate Instance ID${END}

Generate a unique instance identifier for a blueprint.

${UNDERLINE}Usage:${END}
  $self generate-id <blueprint>

${UNDERLINE}Arguments:${END}
  blueprint                   Blueprint name

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Generates a unique instance name based on the blueprint name. If no instance
with the blueprint name exists, returns the blueprint name. Otherwise, appends
a random numeric suffix.

${UNDERLINE}Examples:${END}
  $self generate-id factorio
  $self generate-id terraria.bp
"
}

function usage_save() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Save Instance${END}

Send a save command to a running instance.

${UNDERLINE}Usage:${END}
  $self save <instance>

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Issues a save command to the instance's running process using the
save_command defined in the blueprint.

${UNDERLINE}Examples:${END}
  $self save factorio-01
  $self save terraria-main
"
}

function usage_input() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Send Input to Instance${END}

Send a command to an instance's interactive console.

${UNDERLINE}Usage:${END}
  $self input <instance> <command>

${UNDERLINE}Arguments:${END}
  instance                    Instance name
  command                     Command to send to instance

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Sends a command directly to the instance's console and displays the last
10 log lines after execution.

${UNDERLINE}Examples:${END}
  $self input factorio-01 \"/say Hello world\"
  $self input terraria-main \"save-all\"
"
}

# Load required libraries
logic_instances=$(__find_logic_library instances.sh)
# shellcheck disable=SC1090
source "$logic_instances" || {
  __print_error "Failed to load instances logic library"
  exit $EC_FAILED_SOURCE
}

events_library=$(__find_library events.sh)
# shellcheck disable=SC1090
source "$events_library" || {
  __print_error "Failed to load events library"
  exit $EC_FAILED_SOURCE
}

function _print_info() {
  local instance=$1
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance")

  cat "$instance_config_file"
}

function _print_info_json() {
  local instance=$1
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance")

  # Parse INI file and convert to JSON
  {
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      # Skip comments and empty lines
      [[ "$key" =~ ^[[:space:]]*# || -z "$key" ]] && continue

      # Clean up whitespace and quotes
      key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')

      # Output tab-separated key-value pairs for jq processing
      printf '%s\t%s\n' "$key" "$value"
    done < <(grep -v '^[[:space:]]*$' "$instance_config_file" | grep -v '^[[:space:]]*#')
  } | jq -R 'split("\t") | {(.[0]): .[1]}' | jq -s 'add'
}

function _list_instances() {
  local blueprint=${1:-}
  local detailed=${2:-}

  shopt -s extglob nullglob

  local -a instances=()
  if [[ -z "$blueprint" ]]; then
    instances=("$INSTANCES_SOURCE_DIR"/**/*.ini)
  else
    # shellcheck disable=SC2034
    instances=("$INSTANCES_SOURCE_DIR/$blueprint"/*.ini)
  fi

  # Remove trailing directories from path, leave only filename
  for i in "${!instances[@]}"; do
    # instances["$i"]=$(basename "${instances[$i]}")
    local filename
    filename="$(basename "${instances[$i]}")"

    if [[ -z "$detailed" ]]; then
      echo "${filename%.ini}"
    else
      _print_info "$(basename "${instances[$i]}")"
    fi
  done
}

function _list_instances_json() {
  local blueprint=${1:-}
  local detailed=${2:-}

  shopt -s extglob nullglob

  local -a instances=()
  if [[ -z "$blueprint" ]]; then
    instances=("$INSTANCES_SOURCE_DIR"/**/*.ini)
  else
    # shellcheck disable=SC2034
    instances=("$INSTANCES_SOURCE_DIR/$blueprint"/*.ini)
  fi

  filenames=("${instances[@]##*/}")  # Remove paths
  filenames=("${filenames[@]%.ini}") # Remove extensions

  if [[ -z "$detailed" ]]; then
    jq -n --argjson instances_list "$(printf '%s\n' "${filenames[@]}" | jq -R . | jq -s .)" '$instances_list'
  else
    # Build a JSON object with instance contents
    jq -n --argjson instances_list \
      "$(for instance in "${filenames[@]}"; do
        # Get the content of an instance as JSON
        local content
        content=$(_print_info_json "${instance##*/}")
        # Skip instances with invalid content
        if [[ $? -ne 0 || -z "$content" ]]; then
          continue
        fi
        jq -n --arg key "${instance##*/}" --argjson value "$content" '{"key": $key, "value": $value}'
      done | jq -s 'from_entries')" '$instances_list'
  fi
}

function _list_instances_status() {
  local blueprint=${1:-}

  shopt -s extglob nullglob

  local -a instances=()
  if [[ -z "$blueprint" ]]; then
    instances=("$INSTANCES_SOURCE_DIR"/**/*.ini)
  else
    # shellcheck disable=SC2034
    instances=("$INSTANCES_SOURCE_DIR/$blueprint"/*.ini)
  fi

  # Remove trailing directories from path, leave only filename
  for i in "${!instances[@]}"; do
    local filename
    filename="$(basename "${instances[$i]}")"
    local instance_name="${filename%.ini}"

    echo "=== Instance: $instance_name ==="
    _get_instance_status "$instance_name"
    echo ""
  done
}

function _list_instances_status_json() {
  local blueprint=${1:-}

  shopt -s extglob nullglob

  local -a instances=()
  if [[ -z "$blueprint" ]]; then
    instances=("$INSTANCES_SOURCE_DIR"/**/*.ini)
  else
    # shellcheck disable=SC2034
    instances=("$INSTANCES_SOURCE_DIR/$blueprint"/*.ini)
  fi

  filenames=("${instances[@]##*/}")  # Remove paths
  filenames=("${filenames[@]%.ini}") # Remove extensions

  # Build a JSON object with instance status information
  jq -n --argjson instances_list \
    "$(for instance in "${filenames[@]}"; do
      # Get the status of an instance as JSON
      local status_content
      status_content=$(_get_instance_status_json "${instance##*/}")
      # Skip instances with invalid status content
      if [[ $? -ne 0 || -z "$status_content" ]]; then
        continue
      fi
      jq -n --arg key "${instance##*/}" --argjson value "$status_content" '{"key": $key, "value": $value}'
    done | jq -s 'from_entries')" '$instances_list'
}

# Function to check if management file supports --status command
function _check_management_file_status_support() {
  local management_file="$1"

  # Check if the management file exists and is executable
  if [[ ! -f "$management_file" ]] || [[ ! -x "$management_file" ]]; then
    return 1
  fi

  # Check if the management file supports --status by looking for it in help output
  if "$management_file" --help 2> /dev/null | grep -q -- "--status"; then
    return 0
  fi

  return 1
}

function _get_instance_status() {
  local instance=$1
  __source_instance "$instance"

  # Check if management file supports the new --status command
  # shellcheck disable=SC2154
  if _check_management_file_status_support "$instance_management_file"; then
    # Use the new unified status command from the management file
    local status_args=""
    if [[ -n "$json_format" ]]; then
      status_args="--json"
    fi
    if [[ -n "$fast_mode" ]]; then
      status_args="$status_args --fast"
    fi

    "$instance_management_file" --status $status_args
  else
    # Fallback for older management files that don't support --status
    __print_warning "Instance '$instance' uses an older management file that doesn't support the --status command."
    __print_warning "To enable faster status queries, regenerate the management file"

    # TODO: Implement fallback status gathering logic here
    # For now, just indicate the instance is not compatible
    if [[ -n "$json_format" ]]; then
      echo '{"error": "Management file does not support --status command", "instance": "'"$instance"'", "requires_regeneration": true}'
    else
      echo "Error: Management file does not support --status command"
      echo "Instance: $instance"
      echo "Action required: Regenerate management files"
    fi
  fi
}

function _get_instance_status_json() {
  local instance=$1
  __source_instance "$instance"

  # Check if management file supports the new --status command
  if _check_management_file_status_support "$instance_management_file"; then
    # Use the new unified status command from the management file
    local status_args="--json"
    if [[ -n "$fast_mode" ]]; then
      status_args="$status_args --fast"
    fi

    "$instance_management_file" --status $status_args
  else
    # Fallback for older management files that don't support --status
    __print_warning "Instance '$instance' uses an older management file that doesn't support the --status command."
    __print_warning "To enable faster status queries, regenerate the management file using:"
    __print_warning "  ./kgsm.sh --regenerate-management-files"

    # Return JSON error response
    echo '{"error": "Management file does not support --status command", "instance": "'"$instance"'", "requires_regeneration": true}'
  fi
}

# Command handler functions

function _cmd_create() {
  local blueprint=""
  local install_dir=""
  local instance_name=""

  # First positional argument is blueprint (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    blueprint="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-dir)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --install-dir" && exit $EC_MISSING_ARG
        install_dir="$1"
        shift
        ;;
      --name)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --name" && exit $EC_MISSING_ARG
        instance_name="$1"
        shift
        ;;
      --help)
        usage_create && exit 0
        ;;
      *)
        __print_error "Invalid option for create command: $1"
        __print_error "Use '$self create --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameters
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '$self create --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Create instance
  local created_instance
  created_instance=$(__logic_create_instance "$blueprint" "$install_dir" "$instance_name")
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_INSTANCE_CREATED)
      __print_success "Created instance: $created_instance"
      __dispatch_event_from_exit_code "$exit_code" "$created_instance" "$blueprint"
      exit 0
      ;;
    *)
      __print_error "Failed to create instance"
      exit $exit_code
      ;;
  esac
}

function _cmd_remove() {
  local instance=""

  # First positional argument is instance (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    instance="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_remove && exit 0
        ;;
      *)
        __print_error "Invalid option for remove command: $1"
        __print_error "Use '$self remove --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameter
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self remove --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Remove instance
  __logic_remove_instance "$instance"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_INSTANCE_REMOVED)
      __print_success "Removed instance: $instance"
      __dispatch_event_from_exit_code "$exit_code" "$instance"
      exit 0
      ;;
    *)
      __print_error "Failed to remove instance: $instance"
      exit $exit_code
      ;;
  esac
}

function _cmd_list() {
  local blueprint=""
  local detailed=""
  local status=""

  # Parse options and arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --detailed)
        detailed=1
        shift
        ;;
      --status)
        status=1
        shift
        ;;
      --help)
        usage_list && exit 0
        ;;
      -*)
        __print_error "Invalid option for list command: $1"
        __print_error "Use '$self list --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
      *)
        # Positional argument is blueprint filter
        blueprint="$1"
        shift
        ;;
    esac
  done

  # Execute based on mode
  if [[ -n "$status" ]]; then
    # Status listing
    if [[ -z "$json_format" ]]; then
      _list_instances_status "$blueprint"
      exit $?
    else
      _list_instances_status_json "$blueprint"
      exit $?
    fi
  else
    # Regular listing
    if [[ -z "$json_format" ]]; then
      _list_instances "$blueprint" "$detailed"
      exit $?
    else
      _list_instances_json "$blueprint" "$detailed"
      exit $?
    fi
  fi
}

function _cmd_info() {
  local instance=""

  # First positional argument is instance (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    instance="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_info && exit 0
        ;;
      *)
        __print_error "Invalid option for info command: $1"
        __print_error "Use '$self info --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameter
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self info --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$json_format" ]]; then
    _print_info "$instance"
  else
    _print_info_json "$instance"
  fi
  exit $?
}

function _cmd_status() {
  local instance=""

  # First positional argument is instance (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    instance="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_status && exit 0
        ;;
      *)
        __print_error "Invalid option for status command: $1"
        __print_error "Use '$self status --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameter
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self status --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$json_format" ]]; then
    _get_instance_status "$instance"
  else
    _get_instance_status_json "$instance"
  fi
  exit $?
}

function _cmd_find() {
  local instance=""

  # First positional argument is instance (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    instance="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_find && exit 0
        ;;
      *)
        __print_error "Invalid option for find command: $1"
        __print_error "Use '$self find --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameter
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self find --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  local instance_path
  instance_path=$(__find_instance_config "$instance")
  if [[ -z "$instance_path" ]]; then
    __print_error "Instance '$instance' not found"
    exit $EC_NOT_FOUND
  fi

  echo "$instance_path"
  exit 0
}

function _cmd_generate_id() {
  local blueprint=""

  # First positional argument is blueprint (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    blueprint="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_generate_id && exit 0
        ;;
      *)
        __print_error "Invalid option for generate-id command: $1"
        __print_error "Use '$self generate-id --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameter
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '$self generate-id --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # VALIDATION: Ensure blueprint exists and is valid before generating ID
  if ! validate_blueprint "$blueprint"; then
    __print_error "Blueprint '$blueprint' not found or invalid"
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  local blueprint_name
  blueprint_name="$(__extract_blueprint_name "$blueprint")"

  # Call logic function
  __logic_generate_unique_instance_name "$blueprint_name"
}

function _cmd_save() {
  local instance=""

  # First positional argument is instance (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    instance="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_save && exit 0
        ;;
      *)
        __print_error "Invalid option for save command: $1"
        __print_error "Use '$self save --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameter
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self save --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  "$instance_management_file" --save
}

function _cmd_input() {
  local instance=""
  local command=""

  # First positional argument is instance (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    instance="$1"
    shift
  fi

  # Second positional argument is command (required)
  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    command="$1"
    shift
  fi

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage_input && exit 0
        ;;
      *)
        __print_error "Invalid option for input command: $1"
        __print_error "Use '$self input --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
    esac
  done

  # Validate required parameters
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self input --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$command" ]]; then
    __print_error "Missing required argument: <command>"
    __print_error "Use '$self input --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  "$instance_management_file" --input "$command"
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    exit 0
  fi

  case "$command" in
    create)
      usage_create
      ;;
    remove)
      usage_remove
      ;;
    list)
      usage_list
      ;;
    info)
      usage_info
      ;;
    status)
      usage_status
      ;;
    find)
      usage_find
      ;;
    generate-id)
      usage_generate_id
      ;;
    save)
      usage_save
      ;;
    input)
      usage_input
      ;;
    *)
      __print_error "Unknown command: $command"
      __print_error "Use '$self help' for available commands"
      exit $EC_INVALID_ARG
      ;;
  esac

  exit 0
}

# Global flag extraction and main routing

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

# Extract --fast flag if present
# shellcheck disable=SC2199
if [[ $@ =~ "--fast" ]]; then
  fast_mode=1
  for a; do
    shift
    case $a in
      --fast) continue ;;
      *) set -- "$@" "$a" ;;
    esac
  done
fi

# Handle global help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_usage
  exit 0
fi

# Require at least one argument (command)
if [[ $# -eq 0 ]]; then
  show_usage
  exit 0
fi

# Parse command
command="$1"
shift

# Route to appropriate command handler
case "$command" in
  create)
    _cmd_create "$@"
    ;;
  remove)
    _cmd_remove "$@"
    ;;
  list)
    _cmd_list "$@"
    ;;
  info)
    _cmd_info "$@"
    ;;
  status)
    _cmd_status "$@"
    ;;
  find)
    _cmd_find "$@"
    ;;
  generate-id)
    _cmd_generate_id "$@"
    ;;
  save)
    _cmd_save "$@"
    ;;
  input)
    _cmd_input "$@"
    ;;
  help)
    _cmd_help "$@"
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$self help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac
