#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086
# shellcheck disable=SC2254

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

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
  config-get <instance> <key> Read a value from the instance config
  config-set <instance> <key>=<value>
                              Set a runtime value in the instance config
  backups <instance>          List available backups
  create-backup <instance>    Create a backup (instance must be stopped)
  restore-backup <instance> <source>
                              Restore a named backup
  update <instance>           Update to the latest version (must be stopped)
  check-update <instance>     Check whether a newer version is available
  version <instance> [--installed|--latest]
                              Show the installed or latest version
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
  $self config-get factorio-01 auto_update
  $self config-set factorio-01 auto_update=true
  $self config-set factorio-01 \"executable_arguments=--start-server saves/world.zip\"
  $self backups factorio-01
  $self create-backup factorio-01
  $self restore-backup factorio-01 factorio-01-1234-2026-06-21T10:00:00.backup
  $self update factorio-01
  $self check-update factorio-01
  $self version factorio-01 --latest
  $self help create

${UNDERLINE}Notes:${END}
  • Instance names are auto-generated if not specified
  • Use --json for programmatic consumption
  • Status command shows process state, version, and resource usage
  • Regenerate updates instance files after KGSM updates
"
}

function show_usage_create() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Create Instance${END}

Create a new game server instance from a blueprint.

${UNDERLINE}Usage:${END}
  $self create <blueprint> [options]

${UNDERLINE}Arguments:${END}
  blueprint                   Blueprint name (with or without the .bp.yaml extension)

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
  $self create minecraft.bp.yaml --install-dir /var/games
"
}

function show_usage_remove() {
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

function show_usage_list() {
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

function show_usage_info() {
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

function show_usage_status() {
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

function show_usage_find() {
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

function show_usage_generate_id() {
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
  $self generate-id terraria.bp.yaml
"
}

function show_usage_save() {
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

function show_usage_input() {
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

function show_usage_config_get() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Get Instance Config Value${END}

Read a single value from an instance's configuration file.

${UNDERLINE}Usage:${END}
  $self config-get <instance> <key>

${UNDERLINE}Arguments:${END}
  instance                    Instance name
  key                         Configuration key to read

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Prints the value for <key> from the instance's .config.ini. Any key may be
read. Prints an empty line if the key is not present.

${UNDERLINE}Examples:${END}
  $self config-get factorio-01 auto_update
  $self config-get factorio-01 executable_arguments
"
}

function show_usage_config_set() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Set Instance Config Value${END}

Set a single runtime value in an instance's configuration file.

${UNDERLINE}Usage:${END}
  $self config-set <instance> <key>=<value>

${UNDERLINE}Arguments:${END}
  instance                    Instance name
  key=value                   Assignment; split on the first '=' so the value
                              may itself contain '=', spaces, or a leading '-'
                              (quote the whole token in your shell)

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Updates an existing key (or adds it if absent) and writes it back as
key=\"value\". Only plain runtime values are settable — auto_update,
executable_arguments, level_name, stop_command, save_command, the
*_timeout_seconds values, startup_success_regex, and similar.

Identity and path keys (name, runtime, every *_dir/*_file, …) are managed by
KGSM and are refused. The integration toggles (enable_firewall_management,
enable_command_shortcuts) are also refused — use the
dedicated flow instead:
  $self files firewall enable|disable <instance>
  $self files symlink  enable|disable <instance>

${UNDERLINE}Examples:${END}
  $self config-set factorio-01 auto_update=true
  $self config-set factorio-01 \"executable_arguments=--start-server saves/world.zip\"
  $self config-set factorio-01 stop_command_timeout_seconds=30
"
}

# Load required libraries
logic_instances=$(__find_command_handler instances.sh)
# shellcheck source=handlers/instances.sh
source "$logic_instances" || {
  __print_error "Failed to load instances logic library"
  exit $EC_FAILED_SOURCE
}

events_library=$(__find_core_module events.sh)
# shellcheck source=../core/events.sh
source "$events_library" || {
  __print_error "Failed to load events library"
  exit $EC_FAILED_SOURCE
}

# Watchdog reconciliation helpers — the fleet status path reads run-state from
# the management script, which is blind to the daemon's cgroup-spawned instances;
# __watchdog_active_value / __overlay_status_active overlay the authoritative state.
watchdog_handler=$(__find_command_handler watchdog.sh)
# shellcheck source=handlers/watchdog.sh
source "$watchdog_handler" || {
  __print_error "Failed to load watchdog logic library"
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

  # Derive the per-instance native cgroup path (e.g. kgsm.slice/<name>) and surface it
  # as a `cgroup_path` field. This is runtime-determined state, not stored config:
  # kgsm-watchdog (re)creates this exact directory on every native start, and
  # core/cgroup.sh:__cgroup_path is the single source of the layout — so it is derived
  # here rather than persisted (covers pre-existing instances, never goes stale if the
  # cgroup base is reconfigured). kgsm-monitor reads it to sample native cgroup counters
  # directly, falling back to the /proc tree when the directory is absent (cgroups
  # disabled, or the instance not yet placed in its cgroup). Emitted only for native
  # instances; containers carry "" (Docker owns their cgroup).
  local cgroup_path
  cgroup_path="$(__cgroup_path "$instance" 2>/dev/null)" || cgroup_path=""

  # Render the UFW-style `ports` spec into the canonical structured array
  # ([{start,end,protocol}], range-preserving) — the single machine-readable port format
  # on this surface. It REPLACES the opaque `ports` string below.
  local ports_json
  ports_json=$(__ufw_ports_to_json "$(__get_instance_config_value "$instance" ports)")

  # Parse INI file and convert to JSON, then attach cgroup_path keyed on the instance's
  # own runtime field (native -> derived path, anything else -> ""), override `ports` with
  # the structured array.
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
  } | jq -R 'split("\t") | {(.[0]): .[1]}' | jq -s 'add' \
    | jq --arg cg "$cgroup_path" --argjson ports "$ports_json" \
        '. + {cgroup_path: (if .runtime == "native" then $cg else "" end), ports: $ports}'
}

function _list_instances() {
  local blueprint=${1:-}
  local detailed=${2:-}

  # Get instance names from logic library
  local -a instance_names
  mapfile -t instance_names < <(__logic_get_instances "$blueprint")

  # Display instances
  for instance_name in "${instance_names[@]}"; do
    if [[ -z "$detailed" ]]; then
      echo "$instance_name"
    else
      _print_info "$instance_name"
    fi
  done
}

function _list_instances_json() {
  local blueprint=${1:-}
  local detailed=${2:-}

  # Get instance names from logic library
  local -a instance_names
  mapfile -t instance_names < <(__logic_get_instances "$blueprint")

  if [[ -z "$detailed" ]]; then
    # Simple array of instance names
    printf '%s\n' "${instance_names[@]}" | jq -R . | jq -s .
  else
    # Build a JSON object with instance contents
    jq -n --argjson instances_list \
      "$(for instance in "${instance_names[@]}"; do
        # Get the content of an instance as JSON
        local content
        content=$(_print_info_json "$instance")
        # Skip instances with invalid content
        if [[ $? -ne 0 || -z "$content" ]]; then
          continue
        fi
        jq -n --arg key "$instance" --argjson value "$content" '{"key": $key, "value": $value}'
      done | jq -s 'from_entries')" '$instances_list'
  fi
}

function _list_instances_status() {
  local blueprint=${1:-}

  # Get instance names from logic library
  local -a instance_names
  mapfile -t instance_names < <(__logic_get_instances "$blueprint")

  # Display status for each instance
  for instance_name in "${instance_names[@]}"; do
    echo "=== Instance: $instance_name ==="
    _get_instance_status "$instance_name"
    echo ""
  done
}

function _list_instances_status_json() {
  local blueprint=${1:-}

  # Get instance names from logic library
  local -a instance_names
  mapfile -t instance_names < <(__logic_get_instances "$blueprint")

  # Build a JSON object with instance status information
  jq -n --argjson instances_list \
    "$(for instance in "${instance_names[@]}"; do
      # Get the status of an instance as JSON
      local status_content
      status_content=$(_get_instance_status_json "$instance")
      # Skip instances with invalid status content
      if [[ $? -ne 0 || -z "$status_content" ]]; then
        continue
      fi
      jq -n --arg key "$instance" --argjson value "$status_content" '{"key": $key, "value": $value}'
    done | jq -s 'from_entries')" '$instances_list'
}

# Function to check if management file supports --status command
function _check_management_file_status_support() {
  local management_file="$1"

  # Check if the management file exists and is executable
  if [[ ! -f "$management_file" ]] || [[ ! -x "$management_file" ]]; then
    return 1
  fi

  # Check if the management file supports status by looking for it in help output
  if "$management_file" --help 2> /dev/null | grep -q "status"; then
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

    local _raw _active _pid
    _raw=$("$instance_management_file" status $status_args)
    _active=$(__watchdog_active_value "$instance")
    _pid=$(__watchdog_pid_value "$instance")
    _raw=$(__overlay_status_active "$json_format" "$_active" "$_raw")
    __overlay_process_pid "$json_format" "$_pid" "$_raw"
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

    local _raw _active _pid
    _raw=$("$instance_management_file" status $status_args)
    _active=$(__watchdog_active_value "$instance")
    _pid=$(__watchdog_pid_value "$instance")
    _raw=$(__overlay_status_active "1" "$_active" "$_raw")
    __overlay_process_pid "1" "$_pid" "$_raw"
  else
    # Fallback for older management files that don't support --status
    __print_warning "Instance '$instance' uses an older management file that doesn't support the --status command."
    __print_warning "To enable faster status queries, regenerate the management file using:"

    # Return JSON error response
    echo '{"error": "Management file does not support --status command", "instance": "'"$instance"'", "requires_regeneration": true}'
  fi
}

# Command handler functions

function _cmd_create() {
  local instance_name=""
  local blueprint=""
  local install_dir="$config_default_install_directory"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_create
        return 0
        ;;
      --install-dir)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --install-dir" && return $EC_MISSING_ARG
        install_dir="$1"
        ;;
      --name)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --name" && return $EC_MISSING_ARG
        instance_name="$1"
        ;;
      -*)
        __print_error "Invalid option for create command: $1"
        __print_error "Use '$self create --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        blueprint="$1"
        ;;
    esac
    shift
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
      echo "$created_instance"
      __dispatch_event_from_exit_code "$exit_code" "$created_instance" "$blueprint"
      exit 0
      ;;
    *)
      __print_error "Failed to create instance ($exit_code)"
      exit $exit_code
      ;;
  esac
}

function _cmd_remove() {
  local instance=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_remove
        return 0
        ;;
      -*)
        __print_error "Invalid option for remove command: $1"
        __print_error "Use '$self remove --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
        break
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
      -h | --help | help)
        show_usage_list
        return 0
        ;;
      --detailed)
        detailed=1
        ;;
      --status)
        status=1
        ;;
      -*)
        __print_error "Invalid option for list command: $1"
        __print_error "Use '$self list --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        # Positional argument is blueprint filter
        blueprint="$1"
        ;;
    esac
    shift
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_info
        return 0
        ;;
      -*)
        __print_error "Invalid option for info command: $1"
        __print_error "Use '$self info --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        # Positional argument is instance
        instance="$1"
        ;;
    esac
    shift
  done

  # Validate required parameter
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self info --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # The instance must exist. Fail loudly with the dedicated not-found code rather
  # than rendering a skeletal/empty object for a missing instance, so a consumer
  # (e.g. kgsm-lib) can tell "no such instance" apart from real data. Mirrors the
  # not-found contract in core/loader.sh.
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance")
  if [[ -z "$instance_config_file" ]]; then
    __print_error "Instance config file for '$instance' not found."
    exit $EC_FILE_NOT_FOUND
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_status && exit 0
        ;;
      -*)
        __print_error "Invalid option for status command: $1"
        __print_error "Use '$self status --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        # Positional argument is instance
        instance="$1"
        ;;
    esac
    shift
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_find
        return 0
        ;;
      -*)
        __print_error "Invalid option for find command: $1"
        __print_error "Use '$self find --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        # Positional argument is instance
        instance="$1"
        ;;
    esac
    shift
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
  local custom_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_generate_id
        return 0
        ;;
      --name)
        shift
        if [[ -z "$1" ]]; then
          __print_error "Missing argument for --name"
          return $EC_MISSING_ARG
        fi
        custom_name="$1"
        ;;
      -*)
        __print_error "Invalid option for generate-id command: $1"
        __print_error "Use '$self generate-id --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        # Positional argument is blueprint
        blueprint="$1"
        ;;
    esac
    shift
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

  # If custom name provided, validate it's unique and return it
  if [[ -n "$custom_name" ]]; then
    if __logic_instance_config_exists "$custom_name" "$blueprint_name"; then
      __print_error "Instance '$custom_name' already exists for blueprint '$blueprint_name'"
      return $EC_INVALID_INSTANCE
    fi
    echo "$custom_name"
    return 0
  fi

  # Otherwise, generate unique name
  __logic_generate_unique_instance_name "$blueprint_name"
}

function _cmd_save() {
  local instance=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_save
        return 0
        ;;
      *)
        # Positional argument is instance
        instance="$1"
        ;;
    esac
    shift
  done

  # Validate required parameter
  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self save --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  "$instance_management_file" save
}

function _cmd_input() {
  local instance=""
  local command=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_input
        return 0
        ;;
      *)
        break
        ;;
    esac
    shift
  done

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
  "$instance_management_file" input "$command"
}

function _cmd_config_get() {
  local instance=""
  local key=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_config_get
        return 0
        ;;
      -*)
        __print_error "Invalid option for config-get command: $1"
        __print_error "Use '$self config-get --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$instance" ]]; then
          instance="$1"
        elif [[ -z "$key" ]]; then
          key="$1"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self config-get --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$key" ]]; then
    __print_error "Missing required argument: <key>"
    __print_error "Use '$self config-get --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Resolve the instance up front so a missing instance is a clean error
  # rather than an empty value.
  local config_file
  config_file="$(__find_instance_config "$instance")"
  if [[ -z "$config_file" ]]; then
    __print_error "Instance '$instance' not found"
    exit $EC_FILE_NOT_FOUND
  fi

  __get_instance_config_value "$instance" "$key"
  exit $?
}

function _cmd_config_set() {
  local instance=""
  local assignment=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_config_set
        return 0
        ;;
      -*)
        __print_error "Invalid option for config-set command: $1"
        __print_error "Use '$self config-set --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        # First positional is the instance; the second is the whole key=value
        # token (a leading '-' inside the value never reaches here because the
        # token starts with the key).
        if [[ -z "$instance" ]]; then
          instance="$1"
        elif [[ -z "$assignment" ]]; then
          assignment="$1"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self config-set --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$assignment" ]]; then
    __print_error "Missing required argument: <key>=<value>"
    __print_error "Use '$self config-set --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ "$assignment" != *=* ]]; then
    __print_error "Invalid argument '$assignment': expected <key>=<value>"
    __print_error "Use '$self config-set --help' for usage information"
    exit $EC_INVALID_ARG
  fi

  # Split on the FIRST '=' only, so the value may itself contain '='.
  local key="${assignment%%=*}"
  local value="${assignment#*=}"

  __set_instance_config_value "$instance" "$key" "$value"
  local exit_code=$?

  case $exit_code in
    0)
      # Audit the change (instance + key only — never the value: instance config
      # holds secrets). Emitted from the command layer, not the handler, so internal
      # default-writes stay event-free (matches the create/backup convention).
      # `events.sh emit` no-ops when broadcasting is off.
      events.sh emit instance-config-changed "$instance" "$key"
      __print_success "Set '$key' on instance '$instance'"
      exit 0
      ;;
    $EC_FILE_NOT_FOUND)
      __print_error "Instance '$instance' not found"
      exit $exit_code
      ;;
    $EC_INVALID_ARG)
      if __is_protected_instance_config_key "$key"; then
        __print_error "'$key' is a protected key and cannot be set with config-set"
        case "$key" in
          enable_firewall_management)
            __print_error "Use: $self files firewall enable|disable $instance"
            ;;
          enable_command_shortcuts)
            __print_error "Use: $self files symlink enable|disable $instance"
            ;;
          *)
            __print_error "Identity and path keys are managed by KGSM and must not be edited directly"
            ;;
        esac
      else
        __print_error "Invalid key '$key' (must match ^[a-zA-Z_][a-zA-Z0-9_]*\$)"
      fi
      exit $exit_code
      ;;
    *)
      __print_error "Failed to set '$key' on instance '$instance' ($exit_code)"
      exit $exit_code
      ;;
  esac
}

# =============================================================================
# Tier-1 ops: backups / create-backup / restore-backup / update / check-update
# =============================================================================
#
# Each forwards verbatim to the per-instance management file, which accepts the
# same dash-free command names (see templates/manage.*.d). On a successful
# mutation the command layer emits the matching event — the management file
# stays event-free, mirroring the install/uninstall convention — so downstream
# audit consumers (e.g. kgsm-api) observe it. `update` exists on every
# management file; the backup/check-update commands are newer, so
# _management_supports_ops gates them with an honest "regenerate" message
# rather than leaking a raw "Unknown command" from an older management file.

function show_usage_backups() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}List Instance Backups${END}

List the available backups for an instance, one name per line.

${UNDERLINE}Usage:${END}
  $self backups <instance>

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self backups factorio-01
"
}

function show_usage_create_backup() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Create Instance Backup${END}

Create a backup of an instance's current server files. The instance must be
stopped first.

${UNDERLINE}Usage:${END}
  $self create-backup <instance>

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self create-backup factorio-01
"
}

function show_usage_restore_backup() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Restore Instance Backup${END}

Restore an instance from a named backup. The current files are backed up first.

${UNDERLINE}Usage:${END}
  $self restore-backup <instance> <source>

${UNDERLINE}Arguments:${END}
  instance                    Instance name
  source                      Backup name (see '$self backups <instance>')

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self restore-backup factorio-01 factorio-01-1234-2026-06-21T10:00:00.backup
"
}

function show_usage_update() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Update Instance${END}

Update an instance to the latest available version. The instance must be
stopped first. A no-op when already current.

${UNDERLINE}Usage:${END}
  $self update <instance>

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self update factorio-01
"
}

function show_usage_check_update() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Check For Instance Update${END}

Check whether a newer version is available without applying it. Prints the
latest version to stdout when an update is available; nothing when current.

${UNDERLINE}Usage:${END}
  $self check-update <instance>

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self check-update factorio-01
"
}

# Whether an instance's management file exposes the newer dash-free ops commands
# (backups / create-backup / restore-backup / check-update). Older generated
# files predate them; the distinctive `check-update` token in --help marks
# support. `update` is intentionally NOT gated on this — it ships on every
# management file.
function _management_supports_ops() {
  local management_file="$1"
  [[ -f "$management_file" && -x "$management_file" ]] || return 1
  "$management_file" --help 2> /dev/null | grep -q "check-update"
}

# Honest gate: exit with a regenerate hint when the management file is too old
# to support the requested ops command. $1=instance, $2=management_file.
function _require_ops_support() {
  local instance="$1"
  local management_file="$2"
  if ! _management_supports_ops "$management_file"; then
    __print_error "Instance '$instance' uses an older management file that does not support this operation."
    __print_error "Regenerate it with: kgsm files management create $instance"
    exit $EC_ERROR
  fi
}

function _cmd_backups() {
  local instance=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_backups
        return 0
        ;;
      -*)
        __print_error "Invalid option for backups command: $1"
        __print_error "Use '$self backups --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self backups --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  _require_ops_support "$instance" "$instance_management_file"

  # A malformed instance with no resolved backups dir has no snapshots to list.
  # Never forward in that state: the management file's _list_backups would glob a
  # bare "/" and fabricate entries. Emit nothing (honest empty) instead — never a
  # made-up listing.
  # shellcheck disable=SC2154
  if [[ -z "$instance_backups_dir" ]]; then
    # Warning to stderr only — stdout is the machine-parsed listing (kgsm-api),
    # and __print_warning routes to stdout by convention, so redirect it.
    __print_warning "Instance '$instance' has no configured backups directory; reporting no backups" >&2
    exit 0
  fi

  # Normalize to one backup name per line. The management file's listing may be
  # space- or newline-separated (older files / overrides differ); consumers such
  # as kgsm-api parse one-per-line. Empty output = no backups (honest, never 0).
  local rc
  "$instance_management_file" backups 2> /dev/null | tr -s ' \t\n' '\n' | grep -v '^[[:space:]]*$'
  rc=${PIPESTATUS[0]}
  exit $rc
}

function _cmd_create_backup() {
  local instance=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_create_backup
        return 0
        ;;
      -*)
        __print_error "Invalid option for create-backup command: $1"
        __print_error "Use '$self create-backup --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self create-backup --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  _require_ops_support "$instance" "$instance_management_file"

  "$instance_management_file" create-backup
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    # Derive the created snapshot (newest entry in the backups dir) and the
    # version it captured, for the event payload — the same "latest backup"
    # heuristic _restore_backup uses internally.
    local backup_file version
    # instance_backups_dir / instance_version_file are set by __source_instance.
    # shellcheck disable=SC2012,SC2154
    backup_file="$(ls -t "$instance_backups_dir" 2> /dev/null | head -n1)"
    # shellcheck disable=SC2154
    version="$(cat "$instance_version_file" 2> /dev/null)"
    if [[ -n "$backup_file" ]]; then
      events.sh emit instance-backup-created "$instance" "$backup_file" "$version"
    fi
  fi

  exit $rc
}

function _cmd_restore_backup() {
  local instance=""
  local backup=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_restore_backup
        return 0
        ;;
      -*)
        __print_error "Invalid option for restore-backup command: $1"
        __print_error "Use '$self restore-backup --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$instance" ]]; then
          instance="$1"
        elif [[ -z "$backup" ]]; then
          backup="$1"
        else
          __print_error "Unexpected argument: $1"
          __print_error "Use '$self restore-backup --help' for usage information"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self restore-backup --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$backup" ]]; then
    __print_error "Missing required argument: <source>"
    __print_error "Use '$self restore-backup --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  _require_ops_support "$instance" "$instance_management_file"

  "$instance_management_file" restore-backup "$backup"
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    local version
    version="$(cat "$instance_version_file" 2> /dev/null)"
    events.sh emit instance-backup-restored "$instance" "$backup" "$version"
  fi

  exit $rc
}

function _cmd_update() {
  local instance=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_update
        return 0
        ;;
      -*)
        __print_error "Invalid option for update command: $1"
        __print_error "Use '$self update --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self update --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"

  # `update` ships on every management file (no ops gate). Capture the version
  # before and after so we can emit instance-version-updated ONLY when it
  # actually changed — an already-current instance is a successful no-op and
  # must not produce a spurious event.
  local old_version new_version
  old_version="$(cat "$instance_version_file" 2> /dev/null)"

  "$instance_management_file" update
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    new_version="$(cat "$instance_version_file" 2> /dev/null)"
    if [[ -n "$new_version" && "$new_version" != "$old_version" ]]; then
      events.sh emit instance-version-updated "$instance" "$old_version" "$new_version"
    fi
  fi

  exit $rc
}

function _cmd_check_update() {
  local instance=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_check_update
        return 0
        ;;
      -*)
        __print_error "Invalid option for check-update command: $1"
        __print_error "Use '$self check-update --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self check-update --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  _require_ops_support "$instance" "$instance_management_file"

  "$instance_management_file" check-update
  exit $?
}

function show_usage_version() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Instance Version${END}

Print version information for an instance. With no flag (or --installed) prints
the installed version; with --latest queries the latest available version. To
ask whether a newer version exists, use '$self check-update <instance>'.

${UNDERLINE}Usage:${END}
  $self version <instance> [--installed | --latest]

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --installed                 Print the installed version (default)
  --latest                    Print the latest available version
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self version factorio-01
  $self version factorio-01 --installed
  $self version factorio-01 --latest
"
}

function _cmd_version() {
  local instance=""
  local mode="installed"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_version
        return 0
        ;;
      --installed)
        mode="installed"
        ;;
      --latest)
        mode="latest"
        ;;
      -*)
        __print_error "Invalid option for version command: $1"
        __print_error "Use '$self version --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        instance="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self version --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"

  # Read-only version query forwarded to the per-instance management file. The
  # installed version is the management file's bare `version` (present on every
  # management file — no regeneration/capability gate needed); --latest forwards
  # the flag. No event (read-only).
  case "$mode" in
    latest)
      "$instance_management_file" version --latest
      ;;
    *)
      "$instance_management_file" version
      ;;
  esac
  exit $?
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    exit 0
  fi

  case "$command" in
    create)
      show_usage_create
      ;;
    remove)
      show_usage_remove
      ;;
    list)
      show_usage_list
      ;;
    info)
      show_usage_info
      ;;
    status)
      show_usage_status
      ;;
    find)
      show_usage_find
      ;;
    generate-id)
      show_usage_generate_id
      ;;
    save)
      show_usage_save
      ;;
    input)
      show_usage_input
      ;;
    config-get)
      show_usage_config_get
      ;;
    config-set)
      show_usage_config_set
      ;;
    backups)
      show_usage_backups
      ;;
    create-backup)
      show_usage_create_backup
      ;;
    restore-backup)
      show_usage_restore_backup
      ;;
    update)
      show_usage_update
      ;;
    check-update)
      show_usage_check_update
      ;;
    version)
      show_usage_version
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
  config-get)
    _cmd_config_get "$@"
    ;;
  config-set)
    _cmd_config_set "$@"
    ;;
  backups)
    _cmd_backups "$@"
    ;;
  create-backup)
    _cmd_create_backup "$@"
    ;;
  restore-backup)
    _cmd_restore_backup "$@"
    ;;
  update)
    _cmd_update "$@"
    ;;
  check-update)
    _cmd_check_update "$@"
    ;;
  version)
    _cmd_version "$@"
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$self help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac
