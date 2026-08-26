#!/usr/bin/env bash

# KGSM Pure Logic Layer - Instance Management
#
# This module contains pure business logic functions for instance operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - 200-299: Success with event emission
# - Standard error codes: EC_INVALID_ARG, EC_BLUEPRINT_NOT_FOUND, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_INSTANCES_LOADED}" ]]; then
  return 0
fi

# Load library logic. Placement is expressed in libraries: an instance is
# created inside a library root, and the layout below it is that module's to
# state rather than a path this one spells out for itself.
if [[ -z "${KGSM_LOGIC_LIBRARIES_LOADED:-}" ]]; then
  # shellcheck source=libraries.sh
  source "$(__find_command_handler libraries.sh)" || return $EC_FAILED_SOURCE
fi

# Generate a unique instance name for a blueprint
# Args: $1 = blueprint_name
# Returns: Echoes unique instance name, returns 0 on success
function __logic_generate_unique_instance_name() {
  local blueprint_name="$1"

  # Validate input
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # If no instance with the same name as the blueprint exists, use blueprint name
  if [[ ! -f "$KGSM_INSTANCES_DIR/${blueprint_name}/${blueprint_name}/${blueprint_name}.config.ini" ]]; then
    echo "$blueprint_name"
    return 0
  fi

  # Generate unique name with random suffix
  local _instance_name
  while :; do
    _instance_name=$(tr -dc 0-9 </dev/urandom | head -c "${config_instance_suffix_length:-2}")
    _instance_name="${blueprint_name}-${_instance_name}"

    if [[ ! -f "$KGSM_INSTANCES_DIR/$blueprint_name/${_instance_name}/${_instance_name}.config.ini" ]]; then
      echo "$_instance_name"
      return 0
    fi
  done
}

export -f __logic_generate_unique_instance_name

# Check if an instance config file exists
# Args: $1 = _instance_name, $2 = blueprint_name
# Returns: 0 if exists, 1 if not
function __logic_instance_config_exists() {
  local _instance_name="$1"
  local blueprint_name="$2"

  if [[ -z "$_instance_name" || -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -f "${KGSM_INSTANCES_DIR}/${blueprint_name}/${_instance_name}/${_instance_name}.config.ini" ]]; then
    return 0
  fi

  return 1
}

export -f __logic_instance_config_exists

# Create an instance config file
# Args: $1 = _instance_name, $2 = blueprint_name
# Returns: Echoes config file path, returns 0 on success or error code
function __logic_create_instance_config_file() {
  local _instance_name="$1"
  local blueprint_name="$2"

  if [[ -z "$_instance_name" || -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # The instance directory at $KGSM_INSTANCES_DIR/$blueprint_name/$instance_name
  # should already exist as a symlink to the actual working directory
  local instance_dir_path="${KGSM_INSTANCES_DIR}/${blueprint_name}/${_instance_name}"

  # Verify the instance directory exists (either as directory or symlink)
  if [[ ! -e "$instance_dir_path" ]]; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  # Create instance config file inside the instance directory
  # (which resolves through symlink to the actual working directory)
  local instance_config_file="${instance_dir_path}/${_instance_name}.config.ini"
  if ! __create_file "$instance_config_file" >/dev/null 2>&1; then
    return $EC_FAILED_TOUCH
  fi

  echo "$instance_config_file"
  return 0
}

export -f __logic_create_instance_config_file

# Create base instance configuration
# Args: $1 = instance_config_file, $2 = _instance_name, $3 = blueprint_abs_path, $4 = install_dir
# Returns: 0 on success, error code on failure
# Override the primary game port in a UFW-style port spec.
# Args: $1 = port spec (e.g. "34197", "7777/tcp|7777/udp", "27015:27016/udp")
#       $2 = new primary port (numeric)
# Echoes the rewritten spec. The "primary" port is the start of the FIRST
# pipe-separated mapping; every field across the spec equal to that primary
# value (a start or a single-port end) is replaced with the new port. This
# handles the common shapes exactly — a lone port, and a tcp+udp pair sharing
# one port (e.g. terraria 7777/tcp|7777/udp → N/tcp|N/udp) — while preserving
# protocols, ranges, and any genuinely-distinct secondary ports untouched.
# An empty spec yields just the new port.
function __override_primary_port() {
  local spec="$1"
  local new_port="$2"

  if [[ -z "$spec" ]]; then
    printf '%s' "$new_port"
    return 0
  fi

  local primary="" out="" seg first=1
  local _segs
  IFS='|' read -ra _segs <<<"$spec"
  for seg in "${_segs[@]}"; do
    local proto="" range="$seg" start end=""
    if [[ "$seg" == */* ]]; then
      proto="/${seg#*/}"
      range="${seg%%/*}"
    fi
    start="${range%%:*}"
    [[ "$range" == *:* ]] && end="${range#*:}"

    if [[ $first -eq 1 ]]; then
      primary="$start"
      first=0
    fi
    [[ "$start" == "$primary" ]] && start="$new_port"
    [[ -n "$end" && "$end" == "$primary" ]] && end="$new_port"

    local rebuilt="$start"
    [[ -n "$end" ]] && rebuilt="${start}:${end}"
    rebuilt="${rebuilt}${proto}"
    [[ -n "$out" ]] && out="${out}|"
    out="${out}${rebuilt}"
  done
  printf '%s' "$out"
}

export -f __override_primary_port

# Reduce a display name to the single line of text it is meant to be.
#
# Control characters are dropped, which the escape helper would do anyway, and
# the surrounding whitespace with them: a label is read, not parsed, so one made
# only of spaces is a server with no visible name rather than a server named
# something. Emptied here, it reads as the instance's id, which is the honest
# answer and the one every other reader already gives for a label that was never
# set. This matches what a C# caller's label is normalized to before it ever
# reaches the CLI, so the same input stores the same value whichever surface
# typed it.
#
# A dollar sign is removed outright. Every other free-text value in the config
# keeps its dollars live on purpose — executable_arguments carries
# $instance_level_name and the like, expanded when the management script sources
# the file — so the escape helper leaves $ unescaped. A display name is opaque
# decoration that no reader should ever expand, but it lands in the same
# key="value" form and is read by the surfaces that source the config
# (the log and port watchers, the interactive wizard). A label of $(command) or
# ${var} would run or expand there. It cannot template anything and nothing is
# owed the character, so it is dropped rather than escaped: the value that
# reaches disk holds no dollar for any reader to act on.
#
# Args: $1 = the label as it was supplied
# Returns: 0, echoing the label as it will be stored
function __normalize_instance_display_name() {
  local _value
  _value="$(__sanitize_instance_config_value "$1")"
  _value="${_value//\$/}"
  _value="${_value#"${_value%%[![:space:]]*}"}"
  _value="${_value%"${_value##*[![:space:]]}"}"
  printf '%s' "$_value"
}

export -f __normalize_instance_display_name

function __logic_create_base_instance() {
  local instance_config_file="$1"
  local _instance_name="$2"
  local blueprint_abs_path="$3"
  local library_dir="$4"
  local override_port="${5:-}"
  local display_name="${6:-}"

  if [[ -z "$instance_config_file" || -z "$_instance_name" || -z "$blueprint_abs_path" || -z "$library_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  # Read the unified blueprint (yq-backed). Populates blueprint_* for both
  # runtimes, including blueprint_runtime and — for containers — the UFW
  # blueprint_ports derived from the embedded compose.
  if ! __source_blueprint "$blueprint_abs_path" >/dev/null 2>&1; then
    return $EC_FAILED_SOURCE
  fi

  # Set instance variables. The id is exported under both spellings: this
  # function's own parameter, and the instance_* name the template expands, which
  # every other value in the config is also written from.
  export _instance_name=$_instance_name
  export instance_name=$_instance_name
  export instance_blueprint_file=$blueprint_abs_path

  # The label human-facing surfaces render. Escaped for the key="value" form the
  # template writes and the source that reads it back, like every other free-text
  # value here — a label containing a quote would otherwise close the string
  # early and make the whole config unsourceable. An instance created without one
  # is shown by its id, which is what the id being the nicest thing to type is
  # for.
  export instance_display_name
  display_name="$(__normalize_instance_display_name "$display_name")"
  instance_display_name="$(
    __escape_instance_config_value "${display_name:-$_instance_name}"
  )"

  local instance_blueprint_name
  instance_blueprint_name="$(__extract_blueprint_name "$blueprint_abs_path")"

  # The library root is recorded so that nothing downstream has to recover it by
  # stripping components off a path. Instances placed before libraries existed
  # sit flat directly under their root; both layouts live in one library at no
  # cost, because every path an instance uses is stored absolute.
  export instance_library_dir="${library_dir%/}"

  local instance_namespace_dir
  instance_namespace_dir="$(__library_instances_subdir "$instance_library_dir")" || return $EC_INVALID_ARG
  export instance_working_dir="${instance_namespace_dir}/${instance_blueprint_name}/${_instance_name}"

  # shellcheck disable=SC2155
  export instance_install_datetime="$(date +"%Y-%m-%dT%H:%M:%S")"
  export instance_version_file="${instance_working_dir}/.${_instance_name}.version"
  export instance_latest_version_file="${instance_working_dir}/.${_instance_name}.latest"
  export instance_manage_file="${instance_working_dir}/${_instance_name}.manage.sh"
  export instance_auto_update_before_start="${config_instance_auto_update_before_start:-false}"

  # Process management files
  export instance_pid_file="${instance_working_dir}/.${_instance_name}.pid"
  export instance_socket_file="${instance_working_dir}/.${_instance_name}.sock"
  export instance_log_file="${instance_working_dir}/${_instance_name}.log"

  # Player-presence event channel: a DIRECTORY bind-mounted to /run/kgsm in the
  # container. The in-container detection shim writes /run/kgsm/events.ndjson
  # inside it and the kgsm-watchdog tails that file. A directory (not a single
  # file) mount is required: a single-file mount pins the host inode for the
  # mount's lifetime, so the shim could never surface a fresh inode on restart
  # (the watchdog keys on inode change), and Docker would auto-create a missing
  # host file path as a root-owned directory. The dir itself is created at
  # instance creation (see __logic_create_directories) so it carries correct
  # ownership before the container starts.
  export instance_events_dir="${instance_working_dir}/events"

  # Player-presence detection patterns, forwarded to the container shim across
  # the env boundary base64-encoded (raw regex through compose-YAML→shell→shim
  # mangles $/quotes/backslashes/<>). An empty/unset blueprint pattern yields an
  # empty string here → that detection is disabled in the shim (honest unknown).
  export instance_player_joined_regex_b64
  instance_player_joined_regex_b64=$(
    printf '%s' "${blueprint_player_joined_regex:-}" | base64 -w0
  )
  export instance_player_left_regex_b64
  instance_player_left_regex_b64=$(
    printf '%s' "${blueprint_player_left_regex:-}" | base64 -w0
  )

  # Raw (un-encoded) player-presence patterns, materialized into the instance
  # config (templates/instance.tp) so the kgsm-watchdog reads them off
  # `instances info --json` to detect presence on a NATIVE instance's log (the
  # .NET-regex analog of the container shim's matching). The container path uses
  # the base64 env form above; this is the native delivery channel. Empty when
  # the blueprint sets none → native detection disabled (honest unknown).
  # Escaped for the key="value" form the template writes and the source that
  # reads it back: a pattern matching a quoted name (Necesse) would otherwise
  # close the string early and make the config unsourceable.
  export instance_player_joined_regex
  instance_player_joined_regex=$(
    __escape_instance_config_value "${blueprint_player_joined_regex:-}"
  )
  export instance_player_left_regex
  instance_player_left_regex=$(
    __escape_instance_config_value "${blueprint_player_left_regex:-}"
  )

  # RCON connection parameters, materialized into the instance config so the
  # kgsm-watchdog can poll the game server for connected players when log-based
  # leave detection is unavailable. Empty rcon_port = no RCON detection.
  export instance_rcon_port="${blueprint_rcon_port:-}"
  export instance_rcon_password="${blueprint_rcon_password:-}"
  export instance_rcon_poll_interval_seconds="${blueprint_rcon_poll_interval_seconds:-10}"
  export instance_rcon_players_command="${blueprint_rcon_players_command:-}"
  export instance_rcon_players_regex="${blueprint_rcon_players_regex:-}"

  export instance_startup_success_regex="${blueprint_startup_success_regex:-}"

  # UPnP port-forwarding gate (per-instance, materialized into the instance config).
  # The resident supervisor (kgsm-watchdog) reads this off `instances info --json`
  # and, when true, opens/closes the instance's ports on the router via upnpc on
  # bring-up/stop. Seeded from the host default (config_enable_port_forwarding,
  # default false = inert); toggle per-instance later with `instances config-set`.
  # Distinct from enable_firewall_management (router NAT forward vs. host ufw rule).
  export instance_enable_port_forwarding="${config_enable_port_forwarding:-false}"

  export instance_install_subdir
  instance_install_subdir="${blueprint_executable_subdirectory:-}"

  export instance_launch_dir="${instance_working_dir}/install"
  if [[ -n "$instance_install_subdir" ]]; then
    instance_launch_dir="${instance_launch_dir}/${instance_install_subdir}"
  fi

  # Ports default to the blueprint's declared spec; an explicit --port from the
  # install/create caller overrides the primary game port (see
  # __override_primary_port) while preserving protocols and secondary ports.
  export instance_ports="${blueprint_ports:-}"
  if [[ -n "$override_port" ]]; then
    instance_ports="$(__override_primary_port "$instance_ports" "$override_port")"
  fi
  export instance_stop_command="${blueprint_stop_command:-}"
  export instance_save_command="${blueprint_save_command:-}"

  # Player-moderation templates, carried through verbatim. Empty means the game
  # declares no such command; the management script refuses that action rather
  # than sending a different one in its place.
  export instance_kick_command="${blueprint_kick_command:-}"
  export instance_ban_command="${blueprint_ban_command:-}"
  export instance_unban_command="${blueprint_unban_command:-}"

  # Broadcast template, carried through verbatim. Empty means the game declares
  # no broadcast command and the announcement is refused.
  export instance_broadcast_command="${blueprint_broadcast_command:-}"
  export instance_platform="${blueprint_platform:-linux}"
  export instance_level_name="${blueprint_level_name:-default}"
  export instance_steam_app_id="${blueprint_steam_app_id:-0}"
  export instance_client_steam_app_id="${blueprint_client_steam_app_id:-0}"
  export instance_steamcmd_arguments="${blueprint_steamcmd_arguments:-}"
  export instance_is_steam_account_required="${blueprint_is_steam_account_required:-false}"

  # Announcement defaults, host-wide unless the instance overrides them later. Empty
  # lead times mean a new instance announces nothing until somebody asks it to.
  #
  # The message defaults are held in variables rather than written inline as
  # ${x:-default}. A {token} inside that form is mangled by the parameter expansion
  # itself — "{minutes} min" comes back out as "{minutes min}" — so any default
  # carrying a placeholder has to reach the expansion as a value, not as literal text.
  local _default_announce_message='Server restart in {minutes} min'
  local _default_announce_cancelled='Server restart cancelled'
  export instance_announce_lead_minutes="${config_instance_announce_lead_minutes:-}"
  export instance_announce_restart_message="${config_instance_announce_restart_message:-$_default_announce_message}"
  export instance_announce_restart_cancelled_message="${config_instance_announce_restart_cancelled_message:-$_default_announce_cancelled}"

  export instance_save_command_timeout_seconds="${config_instance_save_command_timeout_seconds:-5}"
  export instance_stop_command_timeout_seconds="${config_instance_stop_command_timeout_seconds:-30}"
  export instance_compress_backups="${config_enable_backup_compression:-true}"

  local instance_executable_file

  # The executable file needs "./" appended to it if it's not a global bin
  # like java, python, wine64, etc.
  case "${blueprint_executable_file:-}" in
  java | python | wine64 | wine32 | wine | mono | mono64 | mono-wine | mono-wine64 | mono-wine32 | mono-wine-wine64 | mono-wine-wine32 | mono-wine-wine)
    instance_executable_file="${blueprint_executable_file}"
    ;;
  *)
    instance_executable_file="./${blueprint_executable_file}"
    ;;
  esac
  export instance_executable_file
  export instance_executable_arguments="${blueprint_executable_arguments:-}"

  # Some variables need to be extracted and parsed from the blueprint file
  # but because of the way container based blueprints are set up, we need
  # different logic for native and container instances.

  # Runtime is now an explicit blueprint field, not inferred from the extension.
  # blueprint_ports already holds the correct UFW spec for both runtimes (the
  # native `ports` field, or the compose-derived ports for containers).
  if [[ "${blueprint_runtime:-}" == "native" ]]; then

    instance_runtime="native"
    instance_compose_file=""

  elif [[ "${blueprint_runtime:-}" == "container" ]]; then

    instance_runtime="container"
    instance_compose_file="${instance_working_dir}/${_instance_name}.docker-compose.yml"

  else
    return $EC_INVALID_BLUEPRINT
  fi

  export instance_runtime
  export instance_compose_file

  # Get template
  local instance_config_file_template
  if ! instance_config_file_template=$(__find_template instance.tp); then
    return $EC_FILE_NOT_FOUND
  fi

  # Strip control characters from every value the template is about to
  # interpolate. The config is a line-oriented list of key="value" pairs, and its
  # text readers separate a key from its value on a tab and one pair from the
  # next on a newline — so a value carrying either is not one value. A tab
  # truncates it for the readers that split on one while the rest return it
  # whole; a newline ends the line, and everything past it parses as further
  # keys, which is enough to make an instance report an id that is not its own.
  # Blueprint scalars are free text authored by hand, and they reach the template
  # exactly as written.
  #
  # The strip goes at the render rather than on each field because the render is
  # what turns a value into a line, the same way __escape_instance_config_value
  # is that point for the setter. One rule at each of the config's two write
  # paths is what keeps the file's two reader classes — the surfaces that source
  # it and the ones that parse it as text — answering with the same bytes.
  local _template_value
  for _template_value in "${!instance_@}"; do
    printf -v "$_template_value" '%s' \
      "$(__sanitize_instance_config_value "${!_template_value}")"
  done

  # Generate config from template
  if ! eval "cat <<EOF
$(<"$instance_config_file_template")
EOF
" >"$instance_config_file" 2>/dev/null; then
    return $EC_FAILED_TEMPLATE
  fi

  return 0
}

export -f __logic_create_base_instance

# Create a complete instance
# Args: $1 = blueprint, $2 = library_dir (absolute library root),
#       $3 = identifier (optional — the instance id; generated when empty),
#       $4 = override_port (optional — overrides the blueprint's primary port),
#       $5 = display_name (optional — defaults to the id)
# Returns: Echoes _instance_name on success (EC_SUCCESS_INSTANCE_CREATED), error code on failure
function __logic_create_instance() {
  local blueprint=$1
  local library_dir=${2%/}
  local identifier=${3:-}
  local override_port=${4:-}
  local display_name=${5:-}

  # Validate blueprint
  if ! validate_blueprint "$blueprint" >/dev/null 2>&1; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Validate the library root
  if [[ -z "$library_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  if ! validate_directory_exists "$library_dir" "library directory" >/dev/null 2>&1; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  if ! validate_directory_writable "$library_dir" "library directory" >/dev/null 2>&1; then
    return $EC_PERMISSION
  fi

  # The namespace directory instances are placed under. Created on first
  # placement so a freshly registered library holds only its marker until
  # something is actually put in it.
  local instances_dir
  instances_dir="$(__library_instances_subdir "$library_dir")" || return $EC_INVALID_ARG
  if ! __create_dir "$instances_dir" >/dev/null 2>&1; then
    return $EC_FAILED_MKDIR
  fi

  # Get blueprint path
  local blueprint_abs_path
  if ! blueprint_abs_path="$(__find_blueprint "$blueprint")"; then
    return $EC_FILE_NOT_FOUND
  fi

  # Extract blueprint name
  local blueprint_name
  blueprint_name="$(__extract_blueprint_name "$blueprint_abs_path")"

  # Generate or validate the instance id
  local _instance_name
  if [[ -z "$identifier" ]]; then
    _instance_name="$(__logic_generate_unique_instance_name "$blueprint_name")"
  else
    _instance_name="$identifier"
    # A caller-supplied id is always checked, both for shape and for being free.
    if ! validate_instance_id_format "$_instance_name" > /dev/null 2>&1; then
      return $EC_INVALID_ARG
    fi
    if __logic_instance_config_exists "$_instance_name" "$blueprint_name"; then
      return $EC_INVALID_INSTANCE
    fi
  fi

  # Create instance config file
  local instance_config_file
  instance_config_file="$(__logic_create_instance_config_file "$_instance_name" "$blueprint_name")"
  exit_code=$?

  if [[ $exit_code -ne 0 || -z "$instance_config_file" ]]; then
    return $exit_code
  fi

  # Create base instance configuration. The failure code is taken with || so it
  # survives: inside an `if ! cmd` branch $? is the negated status, always 0.
  __logic_create_base_instance "$instance_config_file" "$_instance_name" "$blueprint_abs_path" "$library_dir" "$override_port" "$display_name" || return $?

  # Success - echo instance name for caller
  echo "$_instance_name"
  return $EC_SUCCESS_INSTANCE_CREATED
}

export -f __logic_create_instance

# Remove an instance configuration
#
# Args: $1 = _instance_name, $2 = force ("true" to remove a registry entry whose
#       library is offline)
# Outputs: the __instance_library_*_out globals, so that a caller refused with
#          EC_LIBRARY_OFFLINE can name the library and where it is expected
# Returns: EC_SUCCESS_INSTANCE_REMOVED on success, error code on failure
function __logic_remove_instance() {
  local instance=$1
  local force="${2:-false}"

  if [[ -z "$instance" ]]; then
    return $EC_INVALID_ARG
  fi

  # Located from the registry rather than from the instance's config, because an
  # instance placed in a library that is not mounted has no readable config and
  # the entry protecting it has to be findable before it can be protected.
  local instance_symlink_dir
  if ! instance_symlink_dir="$(__logic_instance_symlink "$instance")"; then
    # An instance outside the standard layout still resolves by search.
    local instance_config_file
    if ! instance_config_file=$(__find_instance_config "$instance"); then
      return $EC_NOT_FOUND
    fi
    instance_symlink_dir="$(dirname "$instance_config_file")"
  fi

  # Verify it's actually a symlink
  if [[ ! -L "$instance_symlink_dir" ]]; then
    return $EC_INVALID_INSTANCE
  fi

  # A dangling registry symlink is what an unmounted library leaves behind, and
  # it is also what an already-removed instance leaves behind. The library, not
  # the link, tells the two apart: removing the entry for a disk that is merely
  # absent is the one way this loses an instance the disk still holds, and the
  # files it would be forgetting are the ones nothing here can see.
  # Called without a command substitution so its globals survive into the caller,
  # which is where the refusal is worded.
  __logic_instance_library_state "$instance" > /dev/null

  if [[ "$force" != "true" ]] && [[ "$__instance_library_state_out" == "offline" ]]; then
    return $EC_LIBRARY_OFFLINE
  fi

  # Extract blueprint name from symlink path
  local blueprint_name
  blueprint_name="$(basename "$(dirname "$instance_symlink_dir")")"

  # Remove the directory symlink
  if ! rm "$instance_symlink_dir" 2>/dev/null; then
    return $EC_FAILED_RM
  fi

  # Remove blueprint directory if empty
  # The directory will be a symlink, expect to be broken after removing the
  # instance, so check if it's a symlink or empty directory before removing.
  local instances_dir="${KGSM_INSTANCES_DIR}/${blueprint_name}"

  # Broken symlink means safe to remove
  if [[ ! -e "$instances_dir" ]]; then
    rm "$instances_dir" 2>/dev/null || true
  # If it's a directory, only remove if empty
  elif [[ -d "$instances_dir" && -z "$(ls -A "$instances_dir")" ]]; then
    rmdir "$instances_dir" 2>/dev/null || true
  fi

  return $EC_SUCCESS_INSTANCE_REMOVED
}

export -f __logic_remove_instance

# Get list of instance names (optionally filtered by blueprint)
# Args: $1 = blueprint_name (optional)
# Returns: Echoes newline-separated list of instance names, returns 0
function __logic_get_instances() {
  local blueprint=${1:-}

  shopt -s extglob nullglob

  # The patterns carry no trailing slash. A trailing slash restricts the match to
  # directories and resolves the symlink to decide, which drops every instance
  # whose library is not mounted — the registry entry is still there, the link is
  # merely dangling, and an instance that vanishes from the roster when a disk is
  # unplugged reads to every consumer as one that was uninstalled. The -L test
  # below is what keeps a stray regular file out.
  local -a instance_dirs=()
  if [[ -z "$blueprint" ]]; then
    # Find all instance symlinks at depth 2 (blueprint/instance)
    instance_dirs=("$KGSM_INSTANCES_DIR"/*/*)
  else
    instance_dirs=("$KGSM_INSTANCES_DIR/$blueprint"/*)
  fi

  # Extract just the instance names (basename of the symlink)
  for instance_dir in "${instance_dirs[@]}"; do
    if [[ -L "$instance_dir" ]]; then
      basename "$instance_dir"
    fi
  done

  return 0
}

export -f __logic_get_instances

# Get list of instance config file paths (optionally filtered by blueprint)
# Args: $1 = blueprint_name (optional)
# Returns: Echoes newline-separated list of instance config paths, returns 0
function __logic_get_instance_paths() {
  local blueprint=${1:-}

  shopt -s extglob nullglob

  # Matched without a trailing slash, for the reason __logic_get_instances gives.
  # The config-file test below still drops an instance whose library is not
  # mounted, which is correct here: this function promises paths that can be
  # read, and there is no readable config behind a dangling link.
  local -a instance_dirs=()
  if [[ -z "$blueprint" ]]; then
    instance_dirs=("$KGSM_INSTANCES_DIR"/*/*)
  else
    instance_dirs=("$KGSM_INSTANCES_DIR/$blueprint"/*)
  fi

  # Echo full paths to config files inside symlinked directories
  for instance_dir in "${instance_dirs[@]}"; do
    # Check if it's a symlink (skip regular directories)
    if [[ -L "$instance_dir" ]]; then
      local instance_name
      instance_name="$(basename "$instance_dir")"
      local config_file="${instance_dir}/${instance_name}.config.ini"
      # Only output if config file exists
      if [[ -f "$config_file" ]]; then
        echo "$config_file"
      fi
    fi
  done

  return 0
}

export -f __logic_get_instance_paths

# Determine whether a key is unsafe to set through the instance config setter.
# Args: $1 = key
# Returns: 0 if the key is protected (must not be set), 1 otherwise.
#
  # Three classes are refused:
  #   - identity/structural keys, where a raw edit corrupts the instance;
  #   - the filesystem paths KGSM owns and manages (every *_dir / *_file, plus
  #     executable_subdirectory);
  #   - the side-effecting toggles, which have dedicated enable/disable flows
  #     (`kgsm files <firewall|symlink> enable|disable <instance>`) — writing the
  #     flag alone would desync KGSM from the actual firewall/symlink state.
  # Everything else (auto_update, display_name, executable_arguments, level_name,
  # stop_command, the *_timeout_seconds values, startup_success_regex, …) is a
  # plain runtime value that KGSM simply re-reads, and is therefore settable.
  # display_name in particular is deliberately absent from the identity class
  # above: `name` is the identity, and the label beside it exists precisely so
  # that it can be changed.
  function __is_protected_instance_config_key() {
    local key="$1"

    case "$key" in
      name | blueprint_file | runtime | platform | install_datetime | \
        is_steam_account_required | steam_app_id | \
        client_steam_app_id | ports)
        return 0
        ;;
      *_dir | *_file | executable_subdirectory)
        return 0
        ;;
      enable_firewall_management | enable_command_shortcuts)
        return 0
        ;;
    esac

    return 1
  }

export -f __is_protected_instance_config_key

# List every key in an instance's config alongside whether it can be changed
# through `instances config-set`.
#
# Emits one "key<TAB>settable<TAB>value" line per key, settable being "true" or
# "false". The judgement comes from __is_protected_instance_config_key — the
# same function the setter itself calls — so what a reader is told is settable
# and what the setter will accept cannot drift apart.
#
# Args:
#   $1 - instance name
# Returns:
#   0 on success
#   EC_INVALID_ARG when no instance was named
#   EC_FILE_NOT_FOUND when the instance has no config file
function __logic_list_instance_config() {
  local _instance_name="$1"

  if [[ -z "$_instance_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local instance_config_file
  instance_config_file=$(__find_instance_config "$_instance_name")

  if [[ -z "$instance_config_file" || ! -f "$instance_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  local line key value settable
  while IFS= read -r line; do
    # Only key=value lines; comments and blanks carry no setting.
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*= ]] || continue

    key="${line%%=*}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${line#*=}"

    # Same unwrapping the management script's own source would do, so the value
    # reported is the value the server runs with.
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    value="$(__unescape_instance_config_value "$value")"

    if __is_protected_instance_config_key "$key"; then
      settable="false"
    else
      settable="true"
    fi

    printf '%s\t%s\t%s\n' "$key" "$settable" "$value"
  done <"$instance_config_file"

  return 0
}

export -f __logic_list_instance_config

# Set a single key=value in an instance's .config.ini.
# Args: $1 = instance_name, $2 = key, $3 = value (may be the empty string)
# Returns: 0 on success (no event), EC_* on failure.
#
# The value is written as key="value" (quoted) to match the format KGSM's own
# parsers expect (__source_with_prefix / the management script's
# __source_instance_config), and is handed to awk through the environment rather
# than via -v so that backslashes and other escapes in the value — e.g. a
# startup_success_regex — are written verbatim instead of being interpreted by
# awk's -v assignment processing.
function __set_instance_config_value() {
  local _instance_name="$1"
  local key="$2"
  local value="$3"

  if [[ -z "$_instance_name" || -z "$key" ]]; then
    return $EC_INVALID_ARG
  fi

  # The key must be a valid identifier. The management script refuses to source
  # a config containing any other key shape, so writing one would brick the
  # instance — reject it up front.
  if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    return $EC_INVALID_ARG
  fi

  # Refuse keys that are unsafe to set directly.
  if __is_protected_instance_config_key "$key"; then
    return $EC_INVALID_ARG
  fi

  # A label carries its own rule about what a stored value is, and it is applied
  # here rather than at the CLI so that every caller of the setter gets it.
  if [[ "$key" == "display_name" ]]; then
    value="$(__normalize_instance_display_name "$value")"
  fi

  local config_file
  config_file="$(__find_instance_config "$_instance_name")"
  if [[ -z "$config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # The instance directory is a symlink to the working dir; resolve it so the
  # write lands on the real file and the temp file shares its filesystem.
  local target_file="$config_file"
  if [[ -L "$config_file" ]]; then
    target_file="$(readlink -f "$config_file")"
  fi

  # Write to a temp file in the SAME directory so the final mv is an atomic,
  # same-filesystem rename, and copy the original's permissions onto it (mktemp
  # creates 0600, which would otherwise regress the config's mode).
  local tmp_file
  tmp_file="$(mktemp "${target_file}.XXXXXX")" || return $EC_FAILED_TOUCH
  chmod --reference="$target_file" "$tmp_file" 2>/dev/null || true

  # Escape for the key="value" form this writes and the source that reads it
  # back, so a value containing a quote cannot brick the config.
  local escaped_value
  escaped_value="$(__escape_instance_config_value "$value")"

  if ! KGSM_CONFIG_SET_VALUE="$escaped_value" awk -v key="$key" '
    BEGIN { value = ENVIRON["KGSM_CONFIG_SET_VALUE"]; found = 0 }
    $0 ~ ("^" key "[ \t]*=") {
      print key "=\"" value "\""
      found = 1
      next
    }
    { print }
    END { if (!found) print key "=\"" value "\"" }
  ' "$target_file" > "$tmp_file"; then
    rm -f "$tmp_file"
    return $EC_FAILED_SED
  fi

  if ! mv "$tmp_file" "$target_file"; then
    rm -f "$tmp_file"
    return $EC_FAILED_MV
  fi

  return 0
}

export -f __set_instance_config_value

# =============================================================================
# MOVING AN INSTANCE BETWEEN LIBRARIES
# =============================================================================

# Echoes the working directory an instance would occupy in a library.
#
# The layout below a library root is that module's to state, and the blueprint
# comes from the registry rather than from the instance's config: the registry
# directory an instance's symlink sits in IS its blueprint, and the move keeps
# the entry where it already is.
#
# Args: $1 = library root, $2 = blueprint name, $3 = instance name
# Returns: EC_SUCCESS or EC_INVALID_ARG
function __logic_instance_target_working_dir() {
  local _library_dir="${1%/}"
  local _blueprint="$2"
  local _instance="$3"

  if [[ -z "$_library_dir" ]] || [[ -z "$_blueprint" ]] || [[ -z "$_instance" ]]; then
    return $EC_INVALID_ARG
  fi

  local _instances_dir
  _instances_dir="$(__library_instances_subdir "$_library_dir")" || return $EC_INVALID_ARG

  echo "${_instances_dir}/${_blueprint}/${_instance}"
  return $EC_SUCCESS
}

export -f __logic_instance_target_working_dir

# Echoes every path key in an instance config whose value sits inside a
# directory, one `key<TAB>value` pair per line.
#
# The keys are enumerated rather than listed: every path an instance holds is
# derived from its working directory at creation, so a move has to rewrite
# whatever is actually there — including a key added after this function was
# written. The containment test is what keeps the enumeration honest in the
# other direction: backups_dir deliberately lives outside the working directory,
# blueprint_file points into the KGSM installation, and command_shortcut_file
# points at a directory on the user's PATH. None of those move with the
# instance, and none of them match.
#
# Args: $1 = instance config file, $2 = the directory to test against
# Returns: EC_SUCCESS, EC_INVALID_ARG, or EC_FILE_NOT_FOUND
function __logic_instance_path_keys_under() {
  local _config_file="$1"
  local _prefix="${2%/}"

  if [[ -z "$_config_file" ]] || [[ -z "$_prefix" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  local _line _key _value
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    [[ "$_line" =~ ^[[:space:]]*# ]] && continue
    [[ "$_line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)= ]] || continue

    _key="${BASH_REMATCH[1]}"
    case "$_key" in
      *_dir | *_file) ;;
      *) continue ;;
    esac

    _value="${_line#*=}"
    _value="${_value#\"}"
    _value="${_value%\"}"

    [[ -z "$_value" ]] && continue

    if [[ "$_value" == "$_prefix" ]] || [[ "$_value" == "$_prefix"/* ]]; then
      printf '%s\t%s\n' "$_key" "$_value"
    fi
  done < "$_config_file"

  return $EC_SUCCESS
}

export -f __logic_instance_path_keys_under

# Rewrites an instance config so every path it holds inside one working
# directory points at another, and records the library the new one sits in.
#
# The config that is rewritten is the one at the new location, named by its full
# path rather than by instance name: the registry still points at the old copy
# while this runs, and resolving the instance by name would edit the tree the
# move has not committed to yet.
#
# Args: $1 = instance config file at the new location, $2 = old working
#       directory, $3 = new working directory, $4 = new library root
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_FILE_NOT_FOUND,
#          EC_FAILED_UPDATE_CONFIG
function __logic_instance_rewrite_paths() {
  local _config_file="$1"
  local _old="${2%/}"
  local _new="${3%/}"
  local _library_dir="${4%/}"

  if [[ -z "$_config_file" ]] || [[ -z "$_old" ]] || [[ -z "$_new" ]] ||
    [[ -z "$_library_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Collected before anything is written: the enumeration reads the same file
  # the rewrite edits, and a reader walking a file that is being rewritten under
  # it has no defined result.
  local -a _pairs=()
  mapfile -t _pairs < <(__logic_instance_path_keys_under "$_config_file" "$_old")

  local _pair _key _value _suffix
  for _pair in "${_pairs[@]}"; do
    [[ -z "$_pair" ]] && continue
    _key="${_pair%%$'\t'*}"
    _value="${_pair#*$'\t'}"

    _suffix="${_value#"$_old"}"

    if ! __add_or_update_config "$_config_file" "$_key" "\"${_new}${_suffix}\"" \
      > /dev/null 2>&1; then
      return $EC_FAILED_UPDATE_CONFIG
    fi
  done

  # library_dir is not under the working directory, so the enumeration above
  # never sees it. It is the one key a move changes on its own terms.
  if ! __add_or_update_config "$_config_file" "library_dir" "\"$_library_dir\"" \
    > /dev/null 2>&1; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS
}

export -f __logic_instance_rewrite_paths

# Echoes the size of a directory tree in whole megabytes.
#
# Measured with du rather than taken from the blueprint's base_disk_mb: what a
# game needs to be installed and what one instance of it has grown to are
# different numbers, and only the second one is about to be copied.
#
# Args: $1 = directory
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_DIRECTORY_NOT_FOUND, or EC_ERROR when
#          du reported something this cannot read
function __logic_instance_tree_size_mb() {
  local _dir="$1"

  if [[ -z "$_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -d "$_dir" ]]; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  local _out
  _out="$(du -s -m "$_dir" 2> /dev/null | cut -f1)"

  if [[ ! "$_out" =~ ^[0-9]+$ ]]; then
    return $EC_ERROR
  fi

  echo "$_out"
  return $EC_SUCCESS
}

export -f __logic_instance_tree_size_mb

# Copies an instance's tree to another location.
#
# rsync with --delete rather than cp, because the copy has to be resumable: a
# move that fails before the registry points at the new tree leaves the source
# authoritative, and the partial copy at the target is then whatever the run got
# through. Re-running has to converge on an exact replica, which is what
# --delete makes true — a plain copy over the remains of an interrupted one
# leaves files the source no longer has.
#
# Args: $1 = source directory, $2 = target directory
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_DIRECTORY_NOT_FOUND,
#          EC_MISSING_DEPENDENCY, EC_FAILED_MKDIR, or EC_FAILED_CP
function __logic_instance_copy_tree() {
  local _source="${1%/}"
  local _target="${2%/}"

  if [[ -z "$_source" ]] || [[ -z "$_target" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -d "$_source" ]]; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  if ! command -v rsync > /dev/null 2>&1; then
    return $EC_MISSING_DEPENDENCY
  fi

  if ! __create_dir "$_target" > /dev/null 2>&1; then
    return $EC_FAILED_MKDIR
  fi

  if ! rsync -a --delete "${_source}/" "${_target}/" > /dev/null 2>&1; then
    return $EC_FAILED_CP
  fi

  return $EC_SUCCESS
}

export -f __logic_instance_copy_tree

# Reports whether an instance has ever been started.
#
# The signal is its log file: both runtimes write one on the way up and rotate
# it into logs_dir on the next start, so either the live file or one rotated
# copy exists for an instance that has run, and neither exists for one that has
# not. Measured on disk rather than inferred from anything the instance
# declares.
#
# Args: $1 = log file, $2 = logs directory
# Returns: 0 when the instance has been started, 1 when nothing says it has
function __logic_instance_has_run() {
  local _log_file="$1"
  local _logs_dir="${2%/}"

  if [[ -n "$_log_file" ]] && [[ -e "$_log_file" ]]; then
    return 0
  fi

  if [[ -n "$_logs_dir" ]] && [[ -d "$_logs_dir" ]] &&
    [[ -n "$(ls -A "$_logs_dir" 2> /dev/null)" ]]; then
    return 0
  fi

  return 1
}

export -f __logic_instance_has_run

# Mark module as loaded
declare -g KGSM_LOGIC_INSTANCES_LOADED=1
export KGSM_LOGIC_INSTANCES_LOADED
