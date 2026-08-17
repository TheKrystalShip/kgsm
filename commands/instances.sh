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
  kick <instance> <target>    Disconnect a player
  ban <instance> <target>     Disconnect a player and block them
  unban <instance> <target>   Lift a block
  config-get <instance> <key> Read a value from the instance config
  config-list <instance>      List every config key, value and whether it is settable
  config-set <instance> <key>=<value>
                              Set a runtime value in the instance config
  backups <instance>          List available backups
  create-backup <instance>    Create a backup (instance must be stopped)
  restore-backup <instance> <id>
                              Restore the backup with this id
  delete-backup <instance> <id>
                              Delete the backup with this id
  prune-backups <instance>    Prune old backups, keeping the N most recent
  update <instance>           Update to the latest version (must be stopped)
  check-update <instance> [--emit]  Check whether a newer version is available
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
  $self kick romestead 192.168.1.42
  $self ban romestead 192.168.1.42
  $self unban romestead 192.168.1.42
  $self config-get factorio-01 auto_update
  $self config-set factorio-01 auto_update=true
  $self config-set factorio-01 \"executable_arguments=--start-server saves/world.zip\"
  $self backups factorio-01
  $self create-backup factorio-01
  $self restore-backup factorio-01 factorio-01-20260731T142233Z-a3f9c1
  $self delete-backup factorio-01 factorio-01-20260731T142233Z-a3f9c1
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
  --port <port>               Override the blueprint's primary game port (optional)
  --help                      Display this help information

${UNDERLINE}Description:${END}
Creates a new instance configuration file and sets up the instance structure.
If --name is not provided, a unique name will be auto-generated based on the
blueprint name. The installation directory must be specified and will contain
all instance data, saves and logs. Backups are kept outside it.

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

function show_usage_moderation() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Player Moderation${END}

Disconnect a player from an instance, block them, or lift that block.

${UNDERLINE}Usage:${END}
  $self kick <instance> <target>
  $self ban <instance> <target>
  $self unban <instance> <target>

${UNDERLINE}Arguments:${END}
  instance                    Instance name
  target                      The player identity the game addresses

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Each action sends the game's own console command with <target> substituted in.
The blueprint declares which identity the game expects through the placeholder
in its template — {ip}, {name} or {id} — so read that placeholder to know what
to pass; \`blueprints info <name> --json\` reports all three templates.

A game that declares no command for an action is refused it. KGSM never
substitutes a different command in its place.

${UNDERLINE}Examples:${END}
  $self kick romestead 192.168.1.42
  $self ban romestead 192.168.1.42
  $self unban romestead 192.168.1.42
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

function show_usage_config_list() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}List Instance Config${END}

List every key in an instance's configuration, with its value and whether it
can be changed through config-set.

${UNDERLINE}Usage:${END}
  $self config-list <instance> [--json]

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --json                      Emit the entries as a JSON array
  --settable                  List only the keys config-set will accept
  --help                      Display this help information

${UNDERLINE}Description:${END}
The settable flag comes from the same rule config-set applies, so what this
reports as changeable is exactly what config-set will accept. Identity keys,
the paths KGSM manages, and the toggles with dedicated flows are reported as
not settable.

${UNDERLINE}Examples:${END}
  $self config-list factorio-01
  $self config-list factorio-01 --settable --json
"
}

function _cmd_config_list() {
  local instance=""
  local settable_only=0

  # --json is stripped by the module's global flag extraction before dispatch,
  # so it arrives as $json_format rather than as an argument.
  local emit_json="${json_format:-0}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_config_list
        return 0
        ;;
      --settable)
        settable_only=1
        ;;
      -*)
        __print_error "Invalid option for config-list command: $1"
        __print_error "Use '$self config-list --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        [[ -z "$instance" ]] && instance="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self config-list --help' for usage information"
    return $EC_MISSING_ARG
  fi

  local result
  result=$(__logic_list_instance_config "$instance")
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    __print_error "Could not read the configuration for '$instance'"
    return $exit_code
  fi

  local first=true
  [[ $emit_json -eq 1 ]] && echo "["

  local key settable value
  while IFS=$'\t' read -r key settable value; do
    [[ -z "$key" ]] && continue
    [[ $settable_only -eq 1 && "$settable" != "true" ]] && continue

    if [[ $emit_json -eq 1 ]]; then
      [[ "$first" == false ]] && echo ","
      first=false
      printf '  {"key": "%s", "settable": %s, "value": %s}' \
        "$key" "$settable" "$(jq -Rn --arg v "$value" '$v')"
    else
      if [[ "$settable" == "true" ]]; then
        printf '%s = %s\n' "$key" "$value"
      else
        printf '%s = %s  (managed by KGSM, not settable)\n' "$key" "$value"
      fi
    fi
  done <<<"$result"

  if [[ $emit_json -eq 1 ]]; then
    [[ "$first" == false ]] && echo ""
    echo "]"
  fi

  return 0
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

# Directory logic — the backup commands resolve the canonical out-of-tree backups
# path through __logic_resolve_backups_dir, the same function instance creation
# uses, so the two can never disagree about where an instance's backups live.
logic_directories=$(__find_command_handler directories.sh)
# shellcheck source=handlers/directories.sh
source "$logic_directories" || {
  __print_error "Failed to load directories logic library"
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
  # as a `cgroup_path` field. Path layout authority: core/cgroup.sh:__cgroup_path;
  # the computation is inlined here (a path join on config defaults) to eliminate
  # per-instance $(...) subshells on the fleet path. kgsm-monitor reads cgroup_path
  # to sample native cgroup counters directly, falling back to /proc when the
  # directory is absent. Emitted only for native instances; containers carry "".
  local _cg_mount="${config_cgroup_mount_point:-/sys/fs/cgroup}"
  local _cg_base="${config_cgroup_base_name:-kgsm.slice/kgsm-watchdog.service}"
  local cgroup_path="${_cg_mount}/${_cg_base}/${instance%.ini}"

  # Read ports directly from the already-found config file, avoiding a second
  # __find_instance_config call through __get_instance_config_value.
  local _ports_raw
  _ports_raw=$(grep -E "^ports[[:space:]]*=" "$instance_config_file" 2>/dev/null | head -n1 | cut -d'=' -f2-)
  _ports_raw="${_ports_raw#"${_ports_raw%%[![:space:]]*}"}"
  _ports_raw="${_ports_raw%"${_ports_raw##*[![:space:]]}"}"
  _ports_raw="${_ports_raw#\"}"
  _ports_raw="${_ports_raw%\"}"
  # __ufw_ports_to_json handles empty/malformed gracefully — always valid JSON.
  local ports_json
  ports_json=$(__ufw_ports_to_json "$_ports_raw")

  # Parse the INI config into a JSON object via a pure-bash loop (no per-line
  # $(echo | sed) subshells, no <(grep | grep) process substitution) feeding a
  # single jq call that merges all key-value pairs and attaches cgroup_path/ports.
  {
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      # Skip comments and blank/whitespace-only lines (pure bash, zero forks)
      [[ "$key" =~ ^[[:space:]]*$ || "$key" =~ ^[[:space:]]*# ]] && continue

      # Trim leading/trailing whitespace from key (pure bash, zero forks)
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"

      # Trim leading/trailing whitespace, strip surrounding double quotes
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      value="${value#\"}"
      value="${value%\"}"

      # Undo the escaping the value was written with. Inlined rather than a call
      # to __unescape_instance_config_value to keep this loop free of the
      # command substitution that helper's printf would cost on every key of
      # every instance — the two must stay in step.
      value="${value//\\\\/\\}"
      value="${value//\\\"/\"}"
      value="${value//\\\`/\`}"

      printf '%s\t%s\n' "$key" "$value"
    done < "$instance_config_file"
  } | jq -Rs --arg cg "$cgroup_path" --argjson ports "$ports_json" \
    '[split("\n")[] | select(length > 0) | split("\t") | {(.[0]): .[1]}]
     | add // {}
     | . + {cgroup_path: (if .runtime == "native" then $cg else "" end), ports: $ports}'
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
    # Simple array of instance names — separate top-level jq types fail when
    # stdin is empty, so guard with a HEAD check.
    printf '%s\n' "${instance_names[@]}" | jq -R . | jq -s .
  else
    # Build a JSON object with instance contents. The per-instance jq emits one
    # {"key":..., "value":...} object per instance; jq -s 'from_entries' merges
    # them into a single {name: {...}, ...} object.
    for instance in "${instance_names[@]}"; do
      local content
      content=$(_print_info_json "$instance")
      # Skip instances with invalid content
      if [[ $? -ne 0 || -z "$content" ]]; then
        continue
      fi
      jq -n --arg key "$instance" --argjson value "$content" '{"key": $key, "value": $value}'
    done | jq -s 'from_entries'
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

function _get_instance_status() {
  local instance=$1
  __source_instance "$instance"

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
}

function _get_instance_status_json() {
  local instance=$1
  __source_instance "$instance"

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
}

# Command handler functions

function _cmd_create() {
  local instance_name=""
  local blueprint=""
  local install_dir="$config_default_install_directory"
  local port=""

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
      --port)
        shift
        [[ -z "$1" ]] && __print_error "Missing argument for --port" && return $EC_MISSING_ARG
        if ! [[ "$1" =~ ^[0-9]+$ ]] || ((10#$1 < 1 || 10#$1 > 65535)); then
          __print_error "Invalid --port '$1' (expected 1-65535)"
          return $EC_INVALID_ARG
        fi
        port="$1"
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
  created_instance=$(__logic_create_instance "$blueprint" "$install_dir" "$instance_name" "$port")
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
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    # Audit the delivered command (instance + verbatim command). Emitted from the
    # command layer, not the management script (a standalone artifact without the
    # event helpers), and only on a successful send. Matches the config-set
    # convention.
    __emit_event instance-input-sent "$instance" "$command"
  fi

  exit $exit_code
}

# Shared implementation of kick/ban/unban. The three differ only in which
# blueprint-declared template the management script resolves, so the CLI layer
# carries one argument parser and passes the action through.
# Args: $1 = action (kick|ban|unban), $2.. = the user's arguments
function _cmd_moderation() {
  local action="$1"
  shift

  local instance=""
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_moderation
        return 0
        ;;
      *)
        break
        ;;
    esac
    shift
  done

  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    instance="$1"
    shift
  fi

  if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    target="$1"
    shift
  fi

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self $action --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$target" ]]; then
    __print_error "Missing required argument: <target>"
    __print_error "Use '$self $action --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"

  # A moderation command only means anything to a running game. A native
  # instance's FIFO outlives the process that read it, so a send into a stopped
  # instance is accepted by the kernel and delivered to nobody — reported as a
  # kick that never happened. The watchdog owns the process and is the only
  # thing that can answer, so the state is resolved here (the management script's
  # own probe reports every supervised instance stopped). A container probes
  # itself against docker and echoes nothing here.
  local run_state
  run_state="$(__resolve_run_state "$instance")"
  case "$run_state" in
    inactive)
      __print_error "Cannot $action on '$instance': the server is not running"
      exit $EC_ERROR
      ;;
    unknown)
      __print_error "Cannot $action on '$instance': the watchdog is unreachable"
      __print_error "Whether the server is running cannot be determined"
      exit $EC_ERROR
      ;;
  esac

  "$instance_management_file" "$action" "$target"
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    # Audited under its own event type, not as console input: the subject here
    # is a player, so a consumer asking "who was banned on this server" filters
    # on the type instead of pattern-matching command text — text a hand-typed
    # `instances input` could produce with no moderation intent behind it. The
    # resolved command rides along so the trail keeps the literal effect beside
    # its subject. Emitted from the command layer (the management script is a
    # standalone artifact without the event helpers) and only on a successful
    # send.
    local template_var="instance_${action}_command"
    local resolved="${!template_var}"
    resolved="${resolved//\{ip\}/$target}"
    resolved="${resolved//\{name\}/$target}"
    resolved="${resolved//\{id\}/$target}"

    local event_name
    case "$action" in
      kick) event_name="instance-player-kicked" ;;
      ban) event_name="instance-player-banned" ;;
      unban) event_name="instance-player-unbanned" ;;
    esac
    __emit_event "$event_name" "$instance" "$target" "$resolved"
  fi

  exit $exit_code
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
      __emit_event instance-config-changed "$instance" "$key"
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

List an instance's backups, newest first — one opaque backup id per line.

Each backup carries a manifest recording what it is: when it was taken, the
version it captured, its size, and which directories it holds. --json emits
those manifests instead of the bare ids.

${UNDERLINE}Usage:${END}
  $self backups <instance> [--json]

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --json                      Emit the full manifests as a JSON array
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self backups factorio-01
  $self backups factorio-01 --json
"
}

function show_usage_create_backup() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Create Instance Backup${END}

Create a backup of an instance's install and saves directories. The instance
must be stopped first. Prints the new backup's id.

Backups are stored outside the instance's working directory, so uninstalling
the instance leaves them intact.

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

Restore an instance from one of its backups. The backup is verified against its
recorded checksum, and the current files are backed up, before anything is
overwritten. Only the directories the backup captured are replaced.

${UNDERLINE}Usage:${END}
  $self restore-backup <instance> <id>

${UNDERLINE}Arguments:${END}
  instance                    Instance name
  id                          Backup id (see '$self backups <instance>')

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self restore-backup factorio-01 factorio-01-20260731T142233Z-a3f9c1
"
}

function show_usage_delete_backup() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Delete Instance Backup${END}

Delete one of an instance's backups by id. There is no undo: the backup and its
manifest are removed from the backups store.

Only an id the engine lists as a backup is accepted. A directory in the backups
store that carries no manifest is not a backup and is never deleted, which is
what keeps a half-built or foreign directory out of reach.

${UNDERLINE}Usage:${END}
  $self delete-backup <instance> <id>

${UNDERLINE}Arguments:${END}
  instance                    Instance name
  id                          Backup id (see '$self backups <instance>')

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self delete-backup factorio-01 factorio-01-20260731T142233Z-a3f9c1
"
}

function show_usage_prune_backups() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Prune Instance Backups${END}

Prune old backups for an instance, keeping the N most recent. Backups are
ordered by their recorded creation time (newest first); all beyond position N
are deleted. Directories in the backups store that are not backups (no
manifest) are left alone.
Safe to call on an empty or missing backups directory (exits 0 with no action).

${UNDERLINE}Usage:${END}
  $self prune-backups <instance> [--keep=N]

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --keep=N                    Number of most-recent backups to keep
                              (default: 5; minimum: 1)
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self prune-backups factorio-01 --keep=5
  $self prune-backups factorio-01 --keep=10
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
  $self check-update <instance> [--emit]

${UNDERLINE}Arguments:${END}
  instance                    Instance name

${UNDERLINE}Options:${END}
  --emit                      Record what the check found and emit
                              'instance_update_available' when the version has
                              not been reported before. Without it the check
                              records nothing and announces nothing.
  --help                      Display this help information

${UNDERLINE}Examples:${END}
  $self check-update factorio-01
  $self check-update factorio-01 --emit
"
}

# The management file's --help text, memoized per file for the life of the
# process. Both capability gates below read it, and a management file is a
# 60KB+ generated script, so executing it once per gate makes every gated
# command pay two full interpreter startups for one signal. The probe stays the
# authoritative one — the file is still executed, just not twice.
#
# The result is published in a global rather than echoed because a caller that
# reads it through a pipe or `$(...)` runs this in a subshell, where the cached
# value is discarded on return and every call re-executes the file. Callers must
# load, then read the global.
_management_help_file=""
_management_help_text=""

function _management_help_load() {
  local management_file="$1"
  if [[ "$management_file" != "$_management_help_file" ]]; then
    _management_help_file="$management_file"
    _management_help_text="$("$management_file" --help 2> /dev/null)"
  fi
}

# Whether an instance's management file exposes the newer dash-free ops commands
# (backups / create-backup / restore-backup / check-update). Older generated
# files predate them; the distinctive `check-update` token in --help marks
# support. `update` is intentionally NOT gated on this — it ships on every
# management file.
function _management_supports_ops() {
  local management_file="$1"
  [[ -f "$management_file" && -x "$management_file" ]] || return 1
  _management_help_load "$management_file"
  grep -q "check-update" <<< "$_management_help_text"
}

# Whether an instance's management file writes the manifest-based backup format.
# A file generated before that format still writes the old flat artifacts, which
# nothing in this version can list or restore — the distinctive `backups [--json]`
# token in --help marks support.
function _management_supports_backup_manifest() {
  local management_file="$1"
  [[ -f "$management_file" && -x "$management_file" ]] || return 1
  _management_help_load "$management_file"
  grep -q 'backups \[--json\]' <<< "$_management_help_text"
}

# Honest gate for the backup commands: refuse rather than let an old management
# file write a backup this version cannot read back. $1=instance, $2=management_file.
function _require_backup_manifest_support() {
  local instance="$1"
  local management_file="$2"
  if ! _management_supports_backup_manifest "$management_file"; then
    __print_error "Instance '$instance' uses a management file that predates the current backup format."
    __print_error "Its backups would not be listable or restorable by this version of KGSM."
    __print_error "Regenerate it with: kgsm files management create $instance"
    exit $EC_ERROR
  fi
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

# The backup ids currently on disk, one per line, sorted — the input to
# _emit_backups_created_since. Empty (not an error) when the instance has no
# backups directory yet, which is the normal state before its first backup.
function _list_backup_ids() {
  [[ -n "${instance_backups_dir:-}" ]] && [[ -d "${instance_backups_dir}" ]] || return 0
  find "${instance_backups_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2> /dev/null | sort
}

# Announce every backup that appeared during a run that took one of its own.
#
# An update captures the state it is about to overwrite and a restore captures
# the state it is about to replace — both from inside the management script,
# which has no way to emit an event. So those archives existed on disk with
# nothing to announce them: no audit row, and no reason for any surface to
# re-read its backup list. The pre-update archive is the rollback point for the
# riskiest operation KGSM performs, and it was the one nobody could see.
#
# The set of ids before the run is the only input; anything new afterwards is
# what the run created. Each one's version comes from its OWN manifest, never
# from the instance's current version file — a pre-update backup captures the
# version being replaced, and the file already says the new one by the time this
# runs.
#
# Args: $1 = instance name, $2 = the newline-separated ids present before the run
function _emit_backups_created_since() {
  local instance="$1"
  local before="$2"

  local id manifest version
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    manifest="${instance_backups_dir}/${id}/manifest.json"
    version=""
    [[ -f "$manifest" ]] && version="$(jq -r '.version // ""' "$manifest" 2> /dev/null)"
    __emit_event instance-backup-created "$instance" "$id" "$version"
  done < <(comm -13 <(printf '%s\n' "$before" | sed '/^$/d') <(_list_backup_ids))
}

# The command a management script is handed so it can report its own phases (see
# the --emit-cmd flag). It is passed in rather than baked into the script so the
# script stays standalone — given nothing it emits nothing — and so there is one
# place here that decides how an event is emitted.
function _event_emitter() {
  echo "$(__find_command events.sh) emit"
}

# Instances created before backups moved out of the working directory still
# carry backups_dir="<working_dir>/backups" in their config, where an uninstall
# would destroy the store along with the instance. Repoint any such instance at
# the canonical out-of-tree path, once, on the first backup command that touches
# it. Idempotent: an instance already pointing outside working_dir is untouched.
#
# The config file is the only thing rewritten. A container instance additionally
# has the old path baked into its generated docker-compose.yml as a bind mount,
# but backups are archived from host paths for both runtimes, so that mount is
# not on the backup path; it follows on the next compose regeneration.
function _repoint_backups_dir() {
  local instance="$1"

  # shellcheck disable=SC2154
  [[ -n "$instance_working_dir" ]] || return 0
  [[ "$instance_backups_dir" == "${instance_working_dir}/"* ]] || return 0

  local canonical
  canonical="$(__logic_resolve_backups_dir "$instance")" || {
    __print_warning "Could not resolve a backups directory for '$instance'" >&2
    return 0
  }

  # __source_instance keeps its config path local, so resolve it here.
  local config_file
  config_file="$(__find_instance_config "$instance")"
  if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
    __print_warning "Could not locate the config file for '$instance'" >&2
    return 0
  fi

  if ! __add_or_update_config "$config_file" "backups_dir" "\"$canonical\"" >/dev/null 2>&1; then
    __print_warning "Could not repoint the backups directory for '$instance'" >&2
    return 0
  fi

  mkdir -p "$canonical" 2>/dev/null

  __print_info "Backups for '$instance' now live in $canonical (outside the instance directory)" >&2
  export instance_backups_dir="$canonical"
  return 0
}

# Resolve the run state a backup will be recorded against, and echo it. Every
# command that makes the management file archive something calls this and passes
# the answer in with --run-state.
#
# The management file cannot determine this itself for a native instance: the
# watchdog owns the process and writes no pid file, so the script's own probe
# would report every supervised instance stopped. It is resolved here, where the
# watchdog is reachable. An unreachable watchdog yields "unknown", which is
# passed through rather than guessed — the manifest then records no consistency
# instead of a fabricated one. A container is left to probe itself, where docker
# is the authority, so this echoes nothing for one.
#
# Requires __source_instance to have run for $instance.
function __resolve_run_state() {
  local instance="$1"

  # shellcheck disable=SC2154
  [[ "$instance_runtime" == "native" ]] || return 0

  if ! __watchdog_available; then
    echo "unknown"
    return 0
  fi

  # The watchdog is the only thing that starts a native instance, and it
  # re-adopts live cgroups when it restarts. So a reachable daemon that does not
  # report an instance running is evidence it is not running — both "tracked,
  # stopped" and "not tracked at all" mean stopped. Only an unreachable daemon
  # leaves the answer genuinely unknown.
  case "$(__watchdog_active_value "$instance")" in
    true) echo "active" ;;
    *) echo "inactive" ;;
  esac
}

function _cmd_backups() {
  local instance=""
  # --json is lifted out of the argument list by the global flag extractor before
  # dispatch, so it arrives as $json_format rather than as an argument. The local
  # case below keeps the function correct if it is ever called directly.
  local json="false"
  [[ "${json_format:-0}" -eq 1 ]] && json="true"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_backups
        return 0
        ;;
      --json)
        json="true"
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
    if [[ "$json" == "true" ]]; then echo "[]"; fi
    exit 0
  fi

  _require_backup_manifest_support "$instance" "$instance_management_file"
  _repoint_backups_dir "$instance"

  local rc

  if [[ "$json" == "true" ]]; then
    # A JSON document must reach the caller byte-for-byte; the id normalization
    # below would mangle it.
    "$instance_management_file" backups --json 2> /dev/null
    exit $?
  fi

  # Normalize to one backup id per line. The management file's listing may be
  # space- or newline-separated (older files / overrides differ); consumers such
  # as kgsm-api parse one-per-line. Empty output = no backups (honest, never 0).
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
  _require_backup_manifest_support "$instance" "$instance_management_file"
  _repoint_backups_dir "$instance"

  local run_state
  run_state="$(__resolve_run_state "$instance")"

  # Archiving a world is minutes of work on a large one, and a scheduler runs
  # this with nobody watching — so the run is bracketed like the lifecycle verbs
  # rather than being announced only once it has finished. Finished is emitted on
  # every outcome: it says the run ENDED, while instance-backup-created says an
  # archive exists.
  __emit_event instance-backup-started "${instance}"

  # create-backup prints its progress lines and then the new backup's id as the
  # last line. Take the id from there rather than re-deriving "the newest entry
  # in the backups dir", which races with any concurrent backup.
  local output rc
  if [[ -n "$run_state" ]]; then
    output="$("$instance_management_file" create-backup --run-state "$run_state")"
  else
    output="$("$instance_management_file" create-backup)"
  fi
  rc=$?
  [[ -n "$output" ]] && printf '%s\n' "$output"

  if [[ $rc -eq 0 ]]; then
    local backup_id version
    backup_id="$(printf '%s' "$output" | tail -n1)"
    # shellcheck disable=SC2154
    version="$(cat "$instance_version_file" 2> /dev/null)"
    # Only announce a backup that exists. Emitting a progress line as a backup id
    # would fabricate an event, so the id is confirmed on disk first.
    if [[ -n "$backup_id" ]] && [[ -d "${instance_backups_dir}/${backup_id}" ]]; then
      __emit_event instance-backup-created "$instance" "$backup_id" "$version"
    fi
  fi

  # Emitted LAST, after the archive is announced, so a consumer that re-reads on
  # "the run ended" finds it already listed.
  __emit_event instance-backup-finished "${instance}"

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
  _require_backup_manifest_support "$instance" "$instance_management_file"
  _repoint_backups_dir "$instance"

  # Restoring overwrites the instance's current data, so the management file
  # backs that up first — and needs the run state to record what that safety
  # archive was taken against.
  local run_state
  run_state="$(__resolve_run_state "$instance")"

  # Longer than a backup and rather more consequential — a safety archive, a
  # checksum verification and then the instance's data replaced — so the run is
  # bracketed for the same reason a backup's is, and a surface can show the
  # instance as busy for the whole of it.
  __emit_event instance-restore-started "${instance}"

  # The safety archive of the current state is taken from inside the management
  # script, which cannot emit; recording what is on disk beforehand is what lets
  # it be announced afterwards (see _emit_backups_created_since).
  local backups_before
  backups_before="$(_list_backup_ids)"

  if [[ -n "$run_state" ]]; then
    "$instance_management_file" restore-backup "$backup" --run-state "$run_state"
  else
    "$instance_management_file" restore-backup "$backup"
  fi
  local rc=$?

  _emit_backups_created_since "$instance" "$backups_before"

  if [[ $rc -eq 0 ]]; then
    local version
    version="$(cat "$instance_version_file" 2> /dev/null)"
    __emit_event instance-backup-restored "$instance" "$backup" "$version"
  fi

  # Emitted LAST, after the outcome, like every other bracket.
  __emit_event instance-restore-finished "${instance}"

  exit $rc
}

function _cmd_delete_backup() {
  local instance=""
  local backup=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_delete_backup
        return 0
        ;;
      -*)
        __print_error "Invalid option for delete-backup command: $1"
        __print_error "Use '$self delete-backup --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$instance" ]]; then
          instance="$1"
        else
          backup="$1"
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$instance" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '$self delete-backup --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$backup" ]]; then
    __print_error "Missing required argument: <id>"
    __print_error "Use '$self delete-backup --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  __source_instance "$instance"
  _require_ops_support "$instance" "$instance_management_file"
  _require_backup_manifest_support "$instance" "$instance_management_file"
  _repoint_backups_dir "$instance"

  # shellcheck disable=SC2154
  if [[ -z "$instance_backups_dir" ]] || [[ ! -d "$instance_backups_dir" ]]; then
    __print_error "No backups directory for '$instance'"
    exit $EC_FILE_NOT_FOUND
  fi

  # The engine's own listing is the only authority on what is a backup: it
  # reports the directories carrying a readable manifest and nothing else. An id
  # absent from it is refused rather than resolved to a path and removed, which
  # is what stops a caller from deleting an arbitrary directory — including a
  # half-built backup still being staged — by naming it.
  local -a known
  mapfile -t known < <("$instance_management_file" backups 2> /dev/null |
    tr -s ' \t\n' '\n' | grep -v '^[[:space:]]*$')

  local found="false"
  local name
  for name in "${known[@]}"; do
    if [[ "$name" == "$backup" ]]; then
      found="true"
      break
    fi
  done

  if [[ "$found" != "true" ]]; then
    __print_error "No such backup for '$instance': $backup"
    __print_error "See '$self backups $instance' for this instance's backups"
    exit $EC_FILE_NOT_FOUND
  fi

  local target="${instance_backups_dir}/${backup}"
  if [[ ! -d "$target" ]]; then
    __print_error "Backup directory not found: $target"
    exit $EC_FILE_NOT_FOUND
  fi

  if ! rm -rf "${target:?}"; then
    __print_error "Failed to remove backup directory: $target"
    exit $EC_ERROR
  fi

  # Emitted from the command layer, on a confirmed removal only — matching the
  # create/restore convention.
  __emit_event instance-backup-deleted "$instance" "$backup"

  __print_success "Deleted backup: $backup"
  exit 0
}

function _cmd_prune_backups() {
  local instance=""
  local keep=5

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_prune_backups
        return 0
        ;;
      --keep=*)
        keep="${1#*=}"
        ;;
      -*)
        __print_error "Invalid option for prune-backups command: $1"
        __print_error "Use '$self prune-backups --help' for usage information"
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
    __print_error "Use '$self prune-backups --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if ! [[ "$keep" =~ ^[0-9]+$ ]] || [[ "$keep" -lt 1 ]]; then
    __print_error "--keep must be a positive integer (got: $keep)"
    exit $EC_INVALID_ARG
  fi

  __source_instance "$instance"
  _require_ops_support "$instance" "$instance_management_file"
  _require_backup_manifest_support "$instance" "$instance_management_file"
  _repoint_backups_dir "$instance"

  # shellcheck disable=SC2154
  if [[ -z "$instance_backups_dir" ]] || [[ ! -d "$instance_backups_dir" ]]; then
    __print_info "No backups directory for '$instance', nothing to prune"
    exit 0
  fi

  # Order by the engine's own listing (newest first, by each backup's recorded
  # creation time), skip the first $keep, delete the rest. Anything in the store
  # that the engine does not report is not a backup and is never deleted.
  local -a to_delete
  mapfile -t to_delete < <("$instance_management_file" backups 2> /dev/null |
    tr -s ' \t\n' '\n' | grep -v '^[[:space:]]*$' | tail -n +"$((keep + 1))")

  if [[ ${#to_delete[@]} -eq 0 ]]; then
    __print_info "Nothing to prune for '$instance' (≤$keep backups present)"
    exit 0
  fi

  local deleted=0
  local failed=0
  for name in "${to_delete[@]}"; do
    [[ -z "$name" ]] && continue
    local full_path="$instance_backups_dir/$name"
    if [[ -d "$full_path" ]]; then
      if rm -rf "$full_path"; then
        ((deleted++))
      else
        __print_error "Failed to remove backup directory: $full_path"
        ((failed++))
      fi
    elif [[ -f "$full_path" ]]; then
      if rm -f "$full_path"; then
        ((deleted++))
      else
        __print_error "Failed to remove backup file: $full_path"
        ((failed++))
      fi
    fi
  done

  # Emitted on what was actually removed, not what was attempted: a sweep that
  # deleted nothing (every removal failed) has nothing to record. A partial
  # sweep still emits — those backups are genuinely gone — and then exits with
  # the error, so the record and the exit code describe the same run.
  if [[ $deleted -gt 0 ]]; then
    __emit_event instance-backups-pruned "$instance" "$deleted" "$keep"
  fi

  __print_info "Pruned $deleted backup(s) for '$instance' (kept: $keep)"
  [[ $failed -gt 0 ]] && exit $EC_ERROR
  exit 0
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

  # An update overwrites the installed game, and the management file archives it
  # first. Point the backups directory outside the instance before that happens,
  # the same way the backup commands do, so a pre-update archive is not left
  # somewhere an uninstall would destroy it.
  _repoint_backups_dir "$instance"

  local run_state
  run_state="$(__resolve_run_state "$instance")"

  # `update` ships on every management file (no ops gate). Capture the version
  # before and after so we can emit instance-version-updated ONLY when it
  # actually changed — an already-current instance is a successful no-op and
  # must not produce a spurious event.
  local old_version new_version
  old_version="$(cat "$instance_version_file" 2> /dev/null)"

  # An update runs for as long as the game takes to download and deploy, and
  # nothing else tells a consumer that the instance is busy in the meantime —
  # the version event only lands at the end. These two bracket the whole run so
  # a surface can show the instance as updating while it happens, no matter
  # which entrypoint drove it. Finished is emitted on every outcome (including
  # a refusal or a failed download): it states that the run ENDED, not that it
  # succeeded — instance-version-updated is what says the version moved.
  __emit_event instance-update-started "${instance}"

  # An update captures the state it is about to overwrite, from inside the
  # management script, which has no way to emit. That archive is the rollback
  # point for the riskiest operation there is, and nothing announced it: no
  # audit row, and every surface's backup count stale until its next scan. The
  # ids present beforehand are recorded here so whatever appears during the run
  # can be announced afterwards, measured from disk rather than parsed out of
  # the script's output.
  local backups_before
  backups_before="$(_list_backup_ids)"

  # --emit-cmd lets the management script report its own phases (download,
  # deploy) with the same events an install emits for the same work. It is
  # passed rather than baked in so the script stays standalone — given nothing
  # it says nothing — and a management file generated before this existed
  # ignores the flag.
  if [[ -n "$run_state" ]]; then
    "$instance_management_file" update --run-state "$run_state" --emit-cmd "$(_event_emitter)"
  else
    "$instance_management_file" update --emit-cmd "$(_event_emitter)"
  fi
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    new_version="$(cat "$instance_version_file" 2> /dev/null)"
    if [[ -n "$new_version" && "$new_version" != "$old_version" ]]; then
      __emit_event instance-version-updated "$instance" "$old_version" "$new_version"
    fi
  else
    # The run ended and the version did not move, for a reason. The other way an
    # update leaves the version alone is finding nothing to do, and the bracket
    # cannot tell the two apart — so without this a refusal reads as a completed
    # update everywhere, including as a succeeded job on every surface.
    __emit_event instance-update-failed "${instance}"
  fi

  _emit_backups_created_since "$instance" "$backups_before"

  # Emitted LAST, after the outcome: a consumer that reads "the run ended" and
  # re-reads the instance must find the outcome already recorded rather than the
  # state it was in before. Same ordering as the stop and restart brackets.
  __emit_event instance-update-finished "${instance}"

  exit $rc
}

function _cmd_check_update() {
  local instance=""
  local emit=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_check_update
        return 0
        ;;
      --emit)
        emit=1
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

  if [[ $emit -eq 0 ]]; then
    "$instance_management_file" check-update
    exit $?
  fi

  _check_update_and_emit "$instance" "$instance_management_file"
  exit $?
}

# Run a real update check, record what it found, and announce a version that has
# not been announced before.
#
# The recorded version is what makes this idempotent: it is written only here, so
# a sweep that finds the same upstream version again is silent, and a check run
# by hand never consumes an announcement because it never writes.
function _check_update_and_emit() {
  local instance="$1"
  local management_file="$2"

  # One fetch. Everything below is a comparison against values already on disk.
  local latest
  if ! latest="$("$management_file" version --latest 2> /dev/null)" \
    || [[ -z "$latest" ]]; then
    __print_error "Could not determine the latest version for '$instance'"
    return $EC_ERROR
  fi

  local installed stored
  installed="$("$management_file" version 2> /dev/null)"
  stored="$("$management_file" version --stored-latest 2> /dev/null)"

  # Recorded before the event, so a failure to record cannot produce an
  # announcement this instance would then make again on the next sweep.
  if ! "$management_file" version --save-latest "$latest" > /dev/null 2>&1; then
    __print_error "Could not record the update check for '$instance'"
    return $EC_ERROR
  fi

  # An instance whose own version cannot be read has nothing to compare against,
  # and "newer than unknown" is not a fact. The fetched version is recorded above
  # either way — it is true, and it is what the next check compares against.
  if [[ -z "$installed" ]] || [[ "${installed,,}" == "unknown" ]]; then
    __print_warning "Instance '$instance' has no known installed version; not reporting an update"
    return $EC_SUCCESS
  fi

  if [[ "$latest" == "$installed" ]]; then
    __print_info "Already up to date (version ${installed})"
    return $EC_SUCCESS
  fi

  if [[ "$latest" == "$stored" ]]; then
    __print_info "Update to ${latest} was already reported for '$instance'"
    return $EC_SUCCESS
  fi

  __print_info "Update available for '$instance': ${installed} -> ${latest}"
  __emit_event instance-update-available "$instance" "$installed" "$latest"
  echo "$latest"
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
    kick | ban | unban)
      show_usage_moderation
      ;;
    config-get)
      show_usage_config_get
      ;;
    config-list)
      show_usage_config_list
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
    delete-backup)
      show_usage_delete_backup
      ;;
    prune-backups)
      show_usage_prune_backups
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
  kick | ban | unban)
    _cmd_moderation "$command" "$@"
    ;;
  config-get)
    _cmd_config_get "$@"
    ;;
  config-list)
    _cmd_config_list "$@"
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
  delete-backup)
    _cmd_delete_backup "$@"
    ;;
  prune-backups)
    _cmd_prune_backups "$@"
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
