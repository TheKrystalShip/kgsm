#!/usr/bin/env bash

# KGSM Pure Logic Layer - Instance transfer
#
# Moving a stopped instance to another machine is an export on the source and an
# import on the target. This module holds both halves: the lock that keeps the
# source stopped, the manifest that describes the instance, the parts that carry
# its bytes, and the staged import that rebuilds it. A transfer is a cross-host
# `kgsm instances move`, so everything the move already does (path rewriting,
# management and compose regeneration, the start-once proof) is reused from the
# instances handler rather than restated here.
#
# These functions have no user-facing I/O. They return exit codes and report
# anything a person should read through globals:
#   __transfer_error_out     one line saying what failed
#   __transfer_refusals      the check's refusals, "exit_code<TAB>code<TAB>detail"
# Bytes that are the point of a verb (a part's stream) go to stdout untouched, so
# nothing here may print to it.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086,SC2154,SC2254

if [[ -n "${KGSM_LOGIC_TRANSFER_LOADED:-}" ]]; then
  return 0
fi

if [[ -z "${KGSM_LOGIC_INSTANCES_LOADED:-}" ]]; then
  # shellcheck source=instances.sh
  source "$(__find_command_handler instances.sh)" || return $EC_FAILED_SOURCE
fi

if [[ -z "${KGSM_LOGIC_WATCHDOG_LOADED:-}" ]]; then
  # shellcheck source=watchdog.sh
  source "$(__find_command_handler watchdog.sh)" || return $EC_FAILED_SOURCE
fi

if [[ -z "${KGSM_LOGIC_DIRECTORIES_LOADED:-}" ]]; then
  # shellcheck source=directories.sh
  source "$(__find_command_handler directories.sh)" || return $EC_FAILED_SOURCE
fi

if [[ -z "${KGSM_LOGIC_FILES_MANAGEMENT_LOADED:-}" ]]; then
  # shellcheck source=files.management.sh
  source "$(__find_command_handler files.management.sh)" || return $EC_FAILED_SOURCE
fi

if [[ -z "${KGSM_LOGIC_FILES_SYMLINK_LOADED:-}" ]]; then
  # shellcheck source=files.symlink.sh
  source "$(__find_command_handler files.symlink.sh)" || return $EC_FAILED_SOURCE
fi

if [[ -z "${KGSM_LOGIC_BLUEPRINTS_LOADED:-}" ]]; then
  # shellcheck source=blueprints.sh
  source "$(__find_command_handler blueprints.sh)" || return $EC_FAILED_SOURCE
fi

declare -g __transfer_error_out=""
declare -g __transfer_finish_json=""
declare -g __transfer_import_id_out=""
declare -ga __transfer_refusals=()

# The directory below a library root where staged imports live.
readonly TRANSFER_STAGING_DIRNAME=".kgsm-import"

# =============================================================================
# SMALL READERS
# =============================================================================

# Echoes the value of a key in an instance config file, unwrapped and unescaped
# the way the management script sees it after sourcing.
#
# Args: $1 = config file, $2 = key
function __transfer_cfg() {
  local _value
  _value="$(grep -E "^$2[[:space:]]*=" "$1" 2> /dev/null | head -n1 | cut -d'=' -f2-)"
  _value="${_value#"${_value%%[![:space:]]*}"}"
  _value="${_value%"${_value##*[![:space:]]}"}"
  _value="${_value#\"}"
  _value="${_value%\"}"
  _value="$(__unescape_instance_config_value "$_value")"
  printf '%s' "$_value"
}

export -f __transfer_cfg

# A lock token is written into a sourced file, so it is held to a safe alphabet.
function __transfer_token_valid() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_.:@-]{1,128}$ ]]
}

export -f __transfer_token_valid

# Sets a key in a config file that is not registered yet, addressed by path.
# The value is escaped for the key="value" form.
#
# Args: $1 = config file, $2 = key, $3 = value
function __transfer_cfg_set() {
  local _escaped
  _escaped="$(__escape_instance_config_value "$3")"
  __add_or_update_config "$1" "$2" "\"${_escaped//\\/\\\\}\"" > /dev/null 2>&1
}

export -f __transfer_cfg_set

# Removes keys from a config file addressed by path.
#
# Args: $1 = config file, then one or more keys
function __transfer_cfg_drop() {
  local _file="$1"
  shift
  local _key
  for _key in "$@"; do
    sed -i "/^${_key}[[:space:]]*=/d" "$_file" || return $EC_FAILED_SED
  done
  return $EC_SUCCESS
}

export -f __transfer_cfg_drop

# Backslash-escapes the characters a sed or tar-transform pattern reads as
# syntax, so a path is matched literally.
function __transfer_regex_escape() {
  printf '%s' "$1" | sed -e 's/[][\.*^$|/]/\\&/g'
}

export -f __transfer_regex_escape

# Sums the bytes of regular files and counts the non-directory entries under
# some directories; a path that is a file counts as one. Directory sizes are
# left out on purpose: they are a property of the filesystem, so the same tree
# measures differently on two hosts.
#
# Args: directories (absent ones count for nothing)
# Outputs: "<bytes> <files>"
function __transfer_measure_dirs() {
  local _bytes=0 _files=0 _dir _out _b _n

  for _dir in "$@"; do
    if [[ -f "$_dir" ]]; then
      _bytes=$((_bytes + $(stat -c %s "$_dir")))
      _files=$((_files + 1))
      continue
    fi
    [[ -d "$_dir" ]] || continue
    _out="$(find -P "${_dir%/}/" ! -type d ! -type s -printf '%y %s\n' 2> /dev/null |
      awk '{ n++; if ($1 == "f") b += $2 } END { print b + 0, n + 0 }')"
    read -r _b _n <<< "$_out"
    _bytes=$((_bytes + ${_b:-0}))
    _files=$((_files + ${_n:-0}))
  done

  echo "$_bytes $_files"
}

export -f __transfer_measure_dirs

# =============================================================================
# THE LOCK
# =============================================================================

# Reports whether a resident watchdog is expected on this host: routing is not
# switched off and its control socket exists.
function __transfer_watchdog_expected() {
  [[ "${KGSM_WATCHDOG_DISABLE:-}" == "true" ]] && return 1
  [[ "${config_enable_watchdog:-true}" == "true" ]] || return 1
  [[ -S "$(__watchdog_socket_path)" ]]
}

export -f __transfer_watchdog_expected

# Echoes whether an instance is enabled for boot autostart: `true` or `false`.
#
# The watchdog's desired state is the only autostart there is. A host that runs
# no watchdog has no autostart, so the honest answer there is `false`. A host
# whose watchdog socket exists but does not answer has an answer that cannot be
# read, and that is an error rather than a guess.
#
# Args: $1 = instance
# Returns: EC_SUCCESS, or EC_ERROR when the flag cannot be read
function __transfer_autostart_flag() {
  local _instance="$1"

  if __watchdog_available; then
    __watchdog_is_enabled "$_instance"
    case $? in
      0) echo "true" ;;
      1) echo "false" ;;
      *) return $EC_ERROR ;;
    esac
    return $EC_SUCCESS
  fi

  if __transfer_watchdog_expected; then
    return $EC_ERROR
  fi

  echo "false"
  return $EC_SUCCESS
}

export -f __transfer_autostart_flag

# Takes the transfer lock on an instance, or confirms it already holds this
# token. Taking it records the autostart flag the instance had and switches
# boot autostart off, which is all it takes to keep the watchdog from starting
# the instance.
#
# Args: $1 = instance, $2 = token
# Returns: EC_SUCCESS, EC_INSTANCE_LOCKED (another token holds it),
#          EC_INVALID_ARG, EC_NOT_FOUND, EC_ERROR
function __logic_transfer_lock_take() {
  local _instance="$1"
  local _token="$2"

  __transfer_token_valid "$_token" || return $EC_INVALID_ARG

  __find_instance_config "$_instance" > /dev/null 2>&1 || return $EC_NOT_FOUND

  local _holder
  _holder="$(__instance_lock_holder "$_instance")"
  if [[ -n "$_holder" ]]; then
    [[ "$_holder" == "$_token" ]] && return $EC_SUCCESS
    return $EC_INSTANCE_LOCKED
  fi

  local _flag
  _flag="$(__transfer_autostart_flag "$_instance")" || return $EC_ERROR

  # Both keys are written before autostart is touched, so a lock that is
  # interrupted part-way is a lock that can be released and restored.
  __write_instance_config_value "$_instance" transfer_lock_autostart "$_flag" ||
    return $EC_FAILED_UPDATE_CONFIG
  if ! __write_instance_config_value "$_instance" transfer_lock "$_token"; then
    __drop_instance_config_keys "$_instance" transfer_lock_autostart
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if [[ "$_flag" == "true" ]]; then
    __watchdog_set_autostart disable "$_instance"
    if [[ $? -ne $EC_SUCCESS_AUTOSTART_DISABLED ]]; then
      __drop_instance_config_keys "$_instance" transfer_lock transfer_lock_autostart
      return $EC_ERROR
    fi
  fi

  return $EC_SUCCESS
}

export -f __logic_transfer_lock_take

# Releases an instance's transfer lock and restores the autostart flag it found.
# Releasing an instance that is not locked succeeds.
#
# Args: $1 = instance, $2 = token (ignored when force), $3 = force (true|false)
# Returns: EC_SUCCESS, EC_INSTANCE_LOCKED (another token holds it), EC_ERROR
function __logic_transfer_lock_release() {
  local _instance="$1"
  local _token="${2:-}"
  local _force="${3:-false}"

  local _holder
  _holder="$(__instance_lock_holder "$_instance")"
  [[ -n "$_holder" ]] || return $EC_SUCCESS

  if [[ "$_force" != "true" ]] && [[ "$_holder" != "$_token" ]]; then
    return $EC_INSTANCE_LOCKED
  fi

  local _config_file _flag
  _config_file="$(__find_instance_config "$_instance" 2> /dev/null)" || return $EC_NOT_FOUND
  _flag="$(__transfer_cfg "$_config_file" transfer_lock_autostart)"

  if [[ "$_flag" == "true" ]]; then
    __watchdog_set_autostart enable "$_instance"
    [[ $? -eq $EC_SUCCESS_AUTOSTART_ENABLED ]] || return $EC_ERROR
  fi

  __drop_instance_config_keys "$_instance" transfer_lock transfer_lock_autostart ||
    return $EC_FAILED_UPDATE_CONFIG
  return $EC_SUCCESS
}

export -f __logic_transfer_lock_release

# =============================================================================
# THE SOURCE: MANIFEST AND PARTS
# =============================================================================

# Echoes the members of an instance's tree part, one `name<TAB>path` per line:
# the working directory, the backups when they live outside it, and for a custom
# blueprint its file and its overrides.
#
# Args: $1 = instance config file
function __transfer_tree_members() {
  local _config_file="$1"

  local _wd _backups _bp_file
  _wd="$(__transfer_cfg "$_config_file" working_dir)"
  _backups="$(__transfer_cfg "$_config_file" backups_dir)"
  _bp_file="$(__transfer_cfg "$_config_file" blueprint_file)"

  printf 'instance\t%s\n' "${_wd%/}"

  if [[ -n "$_backups" ]] && [[ -d "$_backups" ]] &&
    [[ "$_backups" != "$_wd" && "$_backups" != "$_wd"/* ]]; then
    printf 'backups\t%s\n' "${_backups%/}"
  fi

  if [[ "$_bp_file" == "${KGSM_USER_BLUEPRINTS_DIR}/"* ]] && [[ -f "$_bp_file" ]]; then
    printf 'blueprint/%s\t%s\n' "$(basename "$_bp_file")" "$_bp_file"

    local _yaml_name
    _yaml_name="$(__bp_yaml_field "$_bp_file" '.name')"
    if [[ -n "$_yaml_name" ]] && [[ -d "${KGSM_USER_OVERRIDES_DIR}/${_yaml_name}" ]]; then
      printf 'overrides/%s\t%s\n' "$_yaml_name" "${KGSM_USER_OVERRIDES_DIR}/${_yaml_name}"
    fi
  fi
}

export -f __transfer_tree_members

# Echoes the container image references an instance's compose file resolves to,
# sorted and unique, one per line. Empty for a native instance.
#
# Args: $1 = instance config file
# Returns: EC_SUCCESS, or EC_ERROR when compose cannot resolve the file
function __transfer_instance_images() {
  local _config_file="$1"

  [[ "$(__transfer_cfg "$_config_file" runtime)" == "container" ]] || return $EC_SUCCESS

  local _wd _compose _images
  _wd="$(__transfer_cfg "$_config_file" working_dir)"
  _compose="$(__transfer_cfg "$_config_file" compose_file)"

  _images="$(cd "$_wd" 2> /dev/null &&
    docker compose -f "$_compose" config --images 2> /dev/null)" || return $EC_ERROR
  [[ -n "$_images" ]] || return $EC_ERROR

  printf '%s\n' "$_images" | sort -u
}

export -f __transfer_instance_images

# Echoes an instance's manifest as JSON.
#
# Args: $1 = instance
# Returns: EC_SUCCESS, EC_NOT_FOUND, EC_LIBRARY_OFFLINE, EC_ERROR (autostart
#          unreadable, images not resolvable)
function __logic_transfer_manifest() {
  local _instance="$1"

  __logic_instance_library_state "$_instance" > /dev/null || return $EC_NOT_FOUND
  [[ "$__instance_library_state_out" != "offline" ]] || return $EC_LIBRARY_OFFLINE

  local _config_file
  _config_file="$(__find_instance_config "$_instance" 2> /dev/null)" || return $EC_NOT_FOUND

  local _blueprint="$__instance_blueprint_out"
  local _library="$__instance_library_name_out"
  [[ -n "$_library" ]] || _library="unregistered"

  local _runtime _display_name _wd _bp_file _log_file _logs_dir _ports
  _runtime="$(__transfer_cfg "$_config_file" runtime)"
  _display_name="$(__transfer_cfg "$_config_file" display_name)"
  _wd="$(__transfer_cfg "$_config_file" working_dir)"
  _bp_file="$(__transfer_cfg "$_config_file" blueprint_file)"
  _log_file="$(__transfer_cfg "$_config_file" log_file)"
  _logs_dir="$(__transfer_cfg "$_config_file" logs_dir)"
  _ports="$(__ufw_ports_to_json "$(__transfer_cfg "$_config_file" ports)")"
  [[ "$_display_name" != "$_instance" ]] || _display_name=""

  # The flag as found before the lock disabled it: the lock records it, and an
  # instance that is not locked reports its live flag.
  local _autostart
  if [[ -n "$(__instance_lock_holder "$_instance")" ]]; then
    _autostart="$(__transfer_cfg "$_config_file" transfer_lock_autostart)"
  else
    _autostart="$(__transfer_autostart_flag "$_instance")" || return $EC_ERROR
  fi

  local _has_run=false
  __logic_instance_has_run "$_log_file" "$_logs_dir" && _has_run=true

  local _custom=false _sha=""
  [[ "$_bp_file" == "${KGSM_USER_BLUEPRINTS_DIR}/"* ]] && _custom=true
  [[ -f "$_bp_file" ]] && _sha="$(sha256sum "$_bp_file" | cut -d' ' -f1)"

  local _requirements
  _requirements="$(__logic_blueprint_requirement_ids "$_bp_file" | jq -Rn '[inputs]')"

  local -a _dirs=()
  local _name _path
  while IFS=$'\t' read -r _name _path; do
    [[ -n "$_name" ]] && _dirs+=("$_path")
  done < <(__transfer_tree_members "$_config_file")

  local _bytes _files
  read -r _bytes _files < <(__transfer_measure_dirs "${_dirs[@]}")

  local -a _parts=()
  _parts+=("$(jq -nc --argjson bytes "$_bytes" --argjson files "$_files" \
    '{id: "tree", bytes: $bytes, files: $files}')")

  local _images _ref _image_id _size _n=0
  _images="$(__transfer_instance_images "$_config_file")" || return $EC_ERROR
  while IFS= read -r _ref; do
    [[ -n "$_ref" ]] || continue
    _n=$((_n + 1))
    _image_id="$(docker image inspect --format '{{.Id}}' "$_ref" 2> /dev/null)" ||
      return $EC_NOT_FOUND
    _size="$(docker image inspect --format '{{.Size}}' "$_ref" 2> /dev/null)" ||
      return $EC_NOT_FOUND
    _parts+=("$(jq -nc --arg id "image-${_n}" --arg ref "$_ref" \
      --arg image_id "$_image_id" --argjson bytes "$_size" \
      '{id: $id, ref: $ref, image_id: $image_id, bytes: $bytes}')")
  done <<< "$_images"

  jq -n \
    --arg engine "$KGSM_VERSION" --arg id "$_instance" \
    --arg blueprint "$_blueprint" --arg runtime "$_runtime" \
    --arg display_name "$_display_name" --arg autostart "$_autostart" \
    --arg has_run "$_has_run" --arg library "$_library" --arg wd "${_wd%/}" \
    --argjson ports "$_ports" --arg custom "$_custom" --arg sha "$_sha" \
    --argjson requirements "$_requirements" \
    --argjson parts "$(printf '%s\n' "${_parts[@]}" | jq -sc .)" \
    '{
      format: 1,
      engine_version: $engine,
      instance: {
        id: $id,
        blueprint: $blueprint,
        runtime: $runtime,
        display_name: (if $display_name == "" then null else $display_name end),
        autostart: ($autostart == "true"),
        has_run: ($has_run == "true"),
        library: $library,
        working_dir: $wd,
        ports: $ports
      },
      blueprint: {name: $blueprint, custom: ($custom == "true"), sha256: $sha},
      requirements: $requirements,
      parts: $parts
    }'
}

export -f __logic_transfer_manifest

# Writes one part of an instance to stdout. The caller holds the lock.
#
# The tree is a POSIX tar of `instance/`, `backups/` and, for a custom
# blueprint, `blueprint/` and `overrides/`. An image is what `docker save`
# writes. Neither is buffered or staged: the bytes leave as they are read.
#
# Args: $1 = instance, $2 = part id, $3 = lock token
# Returns: EC_SUCCESS, EC_INSTANCE_LOCKED, EC_NOT_FOUND (unknown part), EC_ERROR
function __logic_transfer_export_part() {
  local _instance="$1"
  local _part="$2"
  local _token="$3"

  local _holder
  _holder="$(__instance_lock_holder "$_instance")"
  if [[ -z "$_holder" ]] || [[ "$_holder" != "$_token" ]]; then
    return $EC_INSTANCE_LOCKED
  fi

  local _config_file
  _config_file="$(__find_instance_config "$_instance" 2> /dev/null)" || return $EC_NOT_FOUND

  if [[ "$_part" == "tree" ]]; then
    local -a _args=(--format=posix --numeric-owner -C /)
    local -a _names=()
    local _name _path _rel _dest
    while IFS=$'\t' read -r _name _path; do
      [[ -n "$_name" ]] || continue
      _rel="${_path#/}"
      _dest="$_name"
      _args+=(--transform "flags=rh;s|^$(__transfer_regex_escape "$_rel")|${_dest}|")
      _names+=("$_rel")
    done < <(__transfer_tree_members "$_config_file")

    tar "${_args[@]}" -cf - -- "${_names[@]}" || return $EC_ERROR
    return $EC_SUCCESS
  fi

  if [[ "$_part" =~ ^image-([0-9]+)$ ]]; then
    local _index="${BASH_REMATCH[1]}"
    local _images _ref
    _images="$(__transfer_instance_images "$_config_file")" || return $EC_ERROR
    _ref="$(sed -n "${_index}p" <<< "$_images")"
    [[ -n "$_ref" ]] && [[ "$_index" -gt 0 ]] || return $EC_NOT_FOUND

    docker save "$_ref" || return $EC_ERROR
    return $EC_SUCCESS
  fi

  return $EC_NOT_FOUND
}

export -f __logic_transfer_export_part

# Echoes the image ids an instance's other siblings do not use, so removing the
# instance can remove the images nobody else runs. One `ref` per line.
#
# Args: $1 = instance
function __transfer_unshared_images() {
  local _instance="$1"

  local _config_file
  _config_file="$(__find_instance_config "$_instance" 2> /dev/null)" || return 0

  local _mine
  _mine="$(__transfer_instance_images "$_config_file")" || return 0
  [[ -n "$_mine" ]] || return 0

  local _others="" _link _name _cfg
  for _link in "$KGSM_INSTANCES_DIR"/*/*; do
    [[ -L "$_link" ]] || continue
    _name="$(basename "$_link")"
    [[ "$_name" != "$_instance" ]] || continue
    _cfg="${_link}/${_name}.config.ini"
    [[ -f "$_cfg" ]] || continue
    _others+="$(__transfer_instance_images "$_cfg" 2> /dev/null)"$'\n'
  done

  local _ref
  while IFS= read -r _ref; do
    [[ -n "$_ref" ]] || continue
    grep -qxF "$_ref" <<< "$_others" || echo "$_ref"
  done <<< "$_mine"
}

export -f __transfer_unshared_images

# Commits an export: removes the instance as an uninstall does, together with
# its backups and the images no other instance uses.
#
# Args: $1 = instance, $2 = lock token
# Returns: EC_SUCCESS, EC_INSTANCE_LOCKED, EC_INSTANCE_RUNNING, or the
#          uninstall's own code
function __logic_transfer_export_commit() {
  local _instance="$1"
  local _token="$2"

  local _holder
  _holder="$(__instance_lock_holder "$_instance")"
  if [[ -z "$_holder" ]] || [[ "$_holder" != "$_token" ]]; then
    return $EC_INSTANCE_LOCKED
  fi

  if lifecycle.sh is-active "$_instance" > /dev/null 2>&1; then
    return $EC_INSTANCE_RUNNING
  fi

  local _images
  _images="$(__transfer_unshared_images "$_instance")"

  uninstall.sh --force --purge-backups --lock "$_token" "$_instance"
  local _rc=$?
  [[ $_rc -eq 0 ]] || return $_rc

  local _ref
  while IFS= read -r _ref; do
    [[ -n "$_ref" ]] && docker rmi "$_ref" > /dev/null 2>&1
  done <<< "$_images"

  return $EC_SUCCESS
}

export -f __logic_transfer_export_commit

# =============================================================================
# THE TARGET: CHECK
# =============================================================================

declare -g __transfer_library_out=""
declare -g __transfer_library_dir_out=""
declare -g __transfer_blueprint_out=""
declare -g __transfer_blueprint_action_out=""

# Appends a refusal to the check's list.
#
# Args: $1 = exit code, $2 = refusal code, $3 = detail
function __transfer_refuse() {
  __transfer_refusals+=("$(printf '%s\t%s\t%s' "$1" "$2" "$3")")
}

export -f __transfer_refuse

# Rewrites the top-level `name:` of a blueprint, adding or removing a suffix.
# The name is what overrides bind to, so a travelling copy that is installed
# under another name binds to overrides installed under that name.
#
# Args: $1 = source file, $2 = destination file, $3 = add|strip, $4 = suffix
function __transfer_render_blueprint() {
  awk -v mode="$3" -v suf="-$4" '
    !done && /^name:[ \t]*/ {
      line = $0
      sub(/^name:[ \t]*/, "", line)
      q = ""
      if (substr(line, 1, 1) == "\"" || substr(line, 1, 1) == "\047") {
        q = substr(line, 1, 1)
        line = substr(line, 2)
      }
      if (q != "") {
        idx = index(line, q)
        val = substr(line, 1, idx - 1)
        rest = substr(line, idx + 1)
      } else {
        match(line, /^[^ \t#]+/)
        val = substr(line, 1, RLENGTH)
        rest = substr(line, RLENGTH + 1)
      }
      if (mode == "add") {
        val = val suf
      } else if (length(val) >= length(suf) &&
                 substr(val, length(val) - length(suf) + 1) == suf) {
        val = substr(val, 1, length(val) - length(suf))
      }
      print "name: " q val q rest
      done = 1
      next
    }
    { print }
  ' "$1" > "$2"
}

export -f __transfer_render_blueprint

# Decides what the arriving blueprint becomes on this host and records it:
# `use` (the host holds it), `install` (it travels in the tree part) or
# `install-suffixed` (it travels, under another name).
#
# A default blueprint must already be here. A custom one that is absent is
# installed; one that is present with the same content is used; one that is
# present with other content is installed as <name>-<suffix>.
#
# Args: $1 = manifest file, $2 = suffix (may be empty)
# Sets: __transfer_blueprint_out, __transfer_blueprint_action_out
function __transfer_resolve_blueprint() {
  local _manifest="$1"
  local _suffix="$2"

  local _name _custom _sha
  _name="$(jq -r '.blueprint.name' "$_manifest")"
  _custom="$(jq -r '.blueprint.custom' "$_manifest")"
  _sha="$(jq -r '.blueprint.sha256' "$_manifest")"

  __transfer_blueprint_out="$_name"
  __transfer_blueprint_action_out=""

  local _existing
  if ! _existing="$(__find_blueprint "$_name" 2> /dev/null)"; then
    if [[ "$_custom" == "true" ]]; then
      __transfer_blueprint_action_out="install"
    else
      __transfer_refuse $EC_BLUEPRINT_NOT_FOUND blueprint_missing \
        "Blueprint '$_name' is not on this host"
    fi
    return 0
  fi

  if [[ "$_custom" != "true" ]] ||
    [[ "$(sha256sum "$_existing" | cut -d' ' -f1)" == "$_sha" ]]; then
    __transfer_blueprint_action_out="use"
    return 0
  fi

  if [[ -z "$_suffix" ]]; then
    __transfer_refuse $EC_INVALID_BLUEPRINT blueprint_collision \
      "Blueprint '$_name' exists here with different content; pass --blueprint-suffix"
    return 0
  fi

  if [[ ! "$_suffix" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    __transfer_refuse $EC_INVALID_ARG invalid_suffix \
      "Blueprint suffix '$_suffix' is not a lowercase name"
    return 0
  fi

  local _suffixed="${_name}-${_suffix}"
  __transfer_blueprint_out="$_suffixed"

  local _held
  if ! _held="$(__find_blueprint "$_suffixed" 2> /dev/null)"; then
    __transfer_blueprint_action_out="install-suffixed"
    return 0
  fi

  # The copy already here was made by an earlier transfer when stripping the
  # suffix gives back what travels.
  local _probe
  _probe="$(mktemp "${TMPDIR:-/tmp}/kgsm-bp.XXXXXX")" || return 0
  __transfer_render_blueprint "$_held" "$_probe" strip "$_suffix"
  if [[ "$(sha256sum "$_probe" | cut -d' ' -f1)" == "$_sha" ]]; then
    __transfer_blueprint_action_out="use"
  else
    __transfer_refuse $EC_INVALID_BLUEPRINT blueprint_collision \
      "Blueprint '$_suffixed' exists here with different content"
  fi
  rm -f "$_probe"
  return 0
}

export -f __transfer_resolve_blueprint

# Appends a refusal for every manifest port that overlaps a port another
# instance on this host declares, on the same protocol.
#
# Args: $1 = manifest file
function __transfer_check_ports() {
  local _manifest="$1"

  local -a _incoming=()
  mapfile -t _incoming < <(jq -r '.instance.ports[] | "\(.start) \(.end) \(.protocol)"' "$_manifest")
  [[ ${#_incoming[@]} -gt 0 ]] || return 0

  local _link _name _cfg _triples _s _e _p _is _ie _ip _row
  for _link in "$KGSM_INSTANCES_DIR"/*/*; do
    [[ -L "$_link" ]] || continue
    _name="$(basename "$_link")"
    _cfg="${_link}/${_name}.config.ini"
    [[ -f "$_cfg" ]] || continue

    _triples="$(__parse_ufw_port_spec "$(__transfer_cfg "$_cfg" ports)" 2> /dev/null)"
    while read -r _s _e _p; do
      [[ -n "$_s" ]] || continue
      for _row in "${_incoming[@]}"; do
        read -r _is _ie _ip <<< "$_row"
        [[ "$_ip" == "$_p" ]] || continue
        if [[ $_is -le $_e && $_s -le $_ie ]]; then
          __transfer_refuse $EC_PORT_CONFLICT port_conflict \
            "Port ${_is}-${_ie}/${_ip} overlaps ${_s}-${_e}/${_p} of '${_name}'"
        fi
      done
    done <<< "$_triples"
  done
}

export -f __transfer_check_ports

# The preflight: every reason this host would refuse the manifest, all of them
# listed, nothing written.
#
# Args: $1 = manifest file, $2 = library name (empty: the placement default),
#       $3 = blueprint suffix (may be empty)
# Sets: __transfer_refusals, __transfer_library_out, __transfer_library_dir_out,
#       __transfer_blueprint_out, __transfer_blueprint_action_out
# Returns: EC_SUCCESS, or the exit code of the first refusal
function __logic_transfer_check() {
  local _manifest="$1"
  local _library_arg="${2:-}"
  local _suffix="${3:-}"

  __transfer_refusals=()
  __transfer_library_out=""
  __transfer_library_dir_out=""
  __transfer_blueprint_out=""
  __transfer_blueprint_action_out=""

  if ! jq -e '.format == 1 and (.instance.id | type == "string") and
      (.blueprint.name | type == "string") and (.parts | type == "array")' \
    "$_manifest" > /dev/null 2>&1; then
    __transfer_refuse $EC_INVALID_ARG invalid_manifest "The manifest is not a format 1 manifest"
    return $EC_INVALID_ARG
  fi

  # Library: the one asked for, the configured default, or the sole one.
  local _resolved _rc
  __logic_library_resolve_placement "$_library_arg" > /dev/null
  _rc=$?
  _resolved="$__library_resolve_name_out"
  case $_rc in
    $EC_SUCCESS)
      __transfer_library_out="$_resolved"
      __transfer_library_dir_out="$(__logic_library_path "$_resolved")"
      if ! __logic_library_is_online "$_resolved"; then
        __transfer_refuse $EC_LIBRARY_OFFLINE library_offline \
          "Library '$_resolved' is not reachable at $__transfer_library_dir_out"
        __transfer_library_dir_out=""
      elif __library_overlaps_registry "$__transfer_library_dir_out"; then
        __transfer_refuse $EC_LIBRARY_OVERLAPS_REGISTRY library_overlaps_registry \
          "Library '$_resolved' places servers inside the instance registry"
        __transfer_library_dir_out=""
      fi
      ;;
    $EC_MISSING_ARG)
      __transfer_refuse $EC_LIBRARY_NOT_FOUND library_not_found \
        "Several libraries are registered and none was chosen"
      ;;
    *)
      __transfer_refuse $EC_LIBRARY_NOT_FOUND library_not_found \
        "No library named '${__library_resolve_name_out:-$_library_arg}' is registered"
      ;;
  esac

  local _theirs
  _theirs="$(jq -r '.engine_version' "$_manifest")"
  if [[ "$_theirs" != "$KGSM_VERSION" ]]; then
    __transfer_refuse $EC_ENGINE_VERSION_MISMATCH engine_version_mismatch \
      "The source runs engine ${_theirs} and this host runs ${KGSM_VERSION}"
  fi

  local _req
  while IFS= read -r _req; do
    [[ -n "$_req" ]] || continue
    __logic_blueprint_requirement_present "$_req" ||
      __transfer_refuse $EC_REQUIREMENT_MISSING requirement_missing \
        "This host lacks ${_req}"
  done < <(jq -r '.requirements[]' "$_manifest")

  __transfer_resolve_blueprint "$_manifest" "$_suffix"

  # The tree lands in the library, an image in the container runtime's root.
  local _tree_bytes _image_bytes
  _tree_bytes="$(jq -r '[.parts[] | select(.id == "tree") | .bytes] | add // 0' "$_manifest")"
  _image_bytes="$(jq -r '[.parts[] | select(.id != "tree") | .bytes] | add // 0' "$_manifest")"

  if [[ -n "$__transfer_library_dir_out" ]]; then
    local _margin="${config_install_free_space_margin_mb:-1024}"
    [[ "$_margin" =~ ^[0-9]+$ ]] || _margin=1024
    local _need_mb=$(((_tree_bytes + 1024 * 1024 - 1) / 1024 / 1024))

    __logic_library_space_check "$__transfer_library_dir_out" "$_need_mb" "$_margin"
    if [[ $? -eq $EC_INSUFFICIENT_DISK ]]; then
      __transfer_refuse $EC_INSUFFICIENT_DISK insufficient_disk \
        "Library '${__transfer_library_out}' has $((__library_space_free_out / 1024 / 1024))MB free and the instance needs ${_need_mb}MB plus a ${_margin}MB margin"
    fi
  fi

  if [[ "$_image_bytes" -gt 0 ]] && command -v docker > /dev/null 2>&1; then
    local _docker_root _free _total
    _docker_root="$(docker info --format '{{.DockerRootDir}}' 2> /dev/null)"
    if [[ -n "$_docker_root" ]] && [[ -d "$_docker_root" || -d "$(dirname "$_docker_root")" ]]; then
      read -r _free _total < <(__logic_library_capacity "$_docker_root" 2> /dev/null ||
        __logic_library_capacity "$(dirname "$_docker_root")" 2> /dev/null)
      if [[ "${_free:-}" =~ ^[0-9]+$ ]] && [[ "$_free" -lt "$_image_bytes" ]]; then
        __transfer_refuse $EC_INSUFFICIENT_DISK insufficient_disk \
          "The container runtime has $((_free / 1024 / 1024))MB free and the images need $((_image_bytes / 1024 / 1024))MB"
      fi
    fi
  fi

  __transfer_check_ports "$_manifest"

  [[ ${#__transfer_refusals[@]} -eq 0 ]] && return $EC_SUCCESS
  return "${__transfer_refusals[0]%%$'\t'*}"
}

export -f __logic_transfer_check

# Echoes the check's outcome as JSON.
function __logic_transfer_verdict_json() {
  local _refusals_json="[]"
  if [[ ${#__transfer_refusals[@]} -gt 0 ]]; then
    _refusals_json="$(printf '%s\n' "${__transfer_refusals[@]}" |
      jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") |
        {exit_code: (.[0] | tonumber), code: .[1], detail: .[2]})')"
  fi

  jq -nc --argjson refusals "$_refusals_json" --arg library "$__transfer_library_out" \
    --arg blueprint "$__transfer_blueprint_out" \
    '{ok: ($refusals | length == 0), refusals: $refusals,
      library: (if $library == "" then null else $library end),
      blueprint: (if $blueprint == "" then null else $blueprint end)}'
}

export -f __logic_transfer_verdict_json

# =============================================================================
# THE TARGET: STAGED IMPORTS
# =============================================================================

# Echoes the staging directory of an import.
#
# Args: $1 = import id
# Returns: EC_SUCCESS, or EC_IMPORT_NOT_FOUND
function __transfer_stage_dir() {
  local _id="$1"

  [[ "$_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return $EC_IMPORT_NOT_FOUND

  local _library _root
  while IFS= read -r _library; do
    [[ -n "$_library" ]] || continue
    _root="$(__logic_library_path "$_library")" || continue
    if [[ -d "${_root}/${TRANSFER_STAGING_DIRNAME}/${_id}" ]]; then
      echo "${_root}/${TRANSFER_STAGING_DIRNAME}/${_id}"
      return $EC_SUCCESS
    fi
  done < <(__logic_library_list)

  return $EC_IMPORT_NOT_FOUND
}

export -f __transfer_stage_dir

# Creates a staged import from a manifest, after the check passes.
#
# Args: $1 = manifest file, $2 = library, $3 = blueprint suffix
# Sets: __transfer_import_id_out
# Returns: EC_SUCCESS or the check's first refusal code
function __logic_transfer_import_begin() {
  local _manifest="$1"
  local _library_arg="${2:-}"
  local _suffix="${3:-}"

  __logic_transfer_check "$_manifest" "$_library_arg" "$_suffix" || return $?

  local _id
  _id="imp-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  local _stage="${__transfer_library_dir_out}/${TRANSFER_STAGING_DIRNAME}/${_id}"

  mkdir -p "${_stage}/parts" "${_stage}/tree" || return $EC_FAILED_MKDIR
  cp "$_manifest" "${_stage}/manifest.json" || return $EC_FAILED_CP

  jq -n --arg id "$_id" --arg library "$__transfer_library_out" \
    --arg suffix "$_suffix" --arg began "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{import_id: $id, library: $library, blueprint_suffix: $suffix, began: $began}' \
    > "${_stage}/meta.json" || return $EC_FAILED_TOUCH

  # Which images the host already held, so an abort removes only what this
  # import brought.
  : > "${_stage}/images.state"
  local _part_id _image_id _state
  while IFS=$'\t' read -r _part_id _image_id; do
    [[ -n "$_part_id" ]] || continue
    if docker image inspect "$_image_id" > /dev/null 2>&1; then
      _state="present"
    else
      _state="absent"
    fi
    printf '%s\t%s\t%s\n' "$_part_id" "$_image_id" "$_state" >> "${_stage}/images.state"
  done < <(jq -r '.parts[] | select(.id != "tree") | "\(.id)\t\(.image_id)"' "$_manifest")

  __transfer_import_id_out="$_id"
  return $EC_SUCCESS
}

export -f __logic_transfer_import_begin

# Reads one part from stdin into a staged import.
#
# Args: $1 = import id, $2 = part id
# Returns: EC_SUCCESS, EC_IMPORT_NOT_FOUND, EC_NOT_FOUND (the manifest lists no
#          such part), EC_TRANSFER_INTEGRITY
function __logic_transfer_import_part() {
  local _id="$1"
  local _part="$2"

  local _stage
  _stage="$(__transfer_stage_dir "$_id")" || return $EC_IMPORT_NOT_FOUND

  jq -e --arg part "$_part" '.parts[] | select(.id == $part)' \
    "${_stage}/manifest.json" > /dev/null 2>&1 || return $EC_NOT_FOUND

  rm -f "${_stage}/parts/${_part}.done"

  if [[ "$_part" == "tree" ]]; then
    # A restarted part begins from nothing.
    rm -rf "${_stage}/tree"
    mkdir -p "${_stage}/tree" || return $EC_FAILED_MKDIR
    if ! tar -C "${_stage}/tree" -xpf - --no-same-owner; then
      __transfer_error_out="The tree stream could not be extracted"
      return $EC_TRANSFER_INTEGRITY
    fi
    touch "${_stage}/parts/${_part}.done"
    return $EC_SUCCESS
  fi

  local _ref _expected
  _ref="$(jq -r --arg part "$_part" '.parts[] | select(.id == $part) | .ref' "${_stage}/manifest.json")"
  _expected="$(jq -r --arg part "$_part" '.parts[] | select(.id == $part) | .image_id' "${_stage}/manifest.json")"

  if ! docker load > /dev/null; then
    __transfer_error_out="The image stream could not be loaded"
    return $EC_TRANSFER_INTEGRITY
  fi

  local _actual
  _actual="$(docker image inspect --format '{{.Id}}' "$_ref" 2> /dev/null)"
  if [[ "$_actual" != "$_expected" ]]; then
    __transfer_error_out="Image ${_ref} loaded as ${_actual:-nothing}, the manifest says ${_expected}"
    return $EC_TRANSFER_INTEGRITY
  fi

  touch "${_stage}/parts/${_part}.done"
  return $EC_SUCCESS
}

export -f __logic_transfer_import_part

# Removes a staged import and every image it loaded that the host did not hold
# before it began. An unknown id succeeds.
#
# Args: $1 = import id
function __logic_transfer_import_abort() {
  local _id="$1"

  local _stage
  _stage="$(__transfer_stage_dir "$_id")" || return $EC_SUCCESS

  local _part_id _image_id _state
  if [[ -f "${_stage}/images.state" ]]; then
    while IFS=$'\t' read -r _part_id _image_id _state; do
      [[ "$_state" == "absent" ]] || continue
      [[ -e "${_stage}/parts/${_part_id}.done" ]] || continue
      docker rmi "$_image_id" > /dev/null 2>&1
    done < "${_stage}/images.state"
  fi

  rm -rf "${_stage:?}" || return $EC_FAILED_RM
  rmdir "$(dirname "$_stage")" 2> /dev/null
  return $EC_SUCCESS
}

export -f __logic_transfer_import_abort

# Echoes every staged import as JSON.
function __logic_transfer_import_list() {
  local _library _root _stage _rows=()

  while IFS= read -r _library; do
    [[ -n "$_library" ]] || continue
    _root="$(__logic_library_path "$_library")" || continue
    for _stage in "${_root}/${TRANSFER_STAGING_DIRNAME}"/*/; do
      [[ -f "${_stage}manifest.json" && -f "${_stage}meta.json" ]] || continue
      _rows+=("$(jq -nc --slurpfile manifest "${_stage}manifest.json" \
        --slurpfile meta "${_stage}meta.json" \
        '{import_id: $meta[0].import_id, library: $meta[0].library,
          instance: $manifest[0].instance.id,
          blueprint: $manifest[0].blueprint.name, began: $meta[0].began}')")
    done
  done < <(__logic_library_list)

  if [[ ${#_rows[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${_rows[@]}" | jq -sc .
  fi
  return $EC_SUCCESS
}

export -f __logic_transfer_import_list

# =============================================================================
# THE TARGET: FINISH
# =============================================================================

# What a finish has done so far, in the order it did it, so a failure can put
# the host back.
declare -g __tf_symlink=""
declare -g __tf_blueprint_name=""
declare -g __tf_new_wd=""
declare -g __tf_stage_instance=""
declare -g __tf_config=""
declare -g __tf_firewall=""
declare -g __tf_shortcut=""
declare -g __tf_backups_dir=""
declare -g __tf_installed_blueprint=""
declare -g __tf_installed_overrides=""

# Undoes a failed finish. The staged tree is put back where the import found it,
# so what remains is for `import abort` to remove.
#
# Args: $1 = new instance id
function __transfer_finish_unwind() {
  local _new="$1"

  if [[ -n "$__tf_symlink" ]]; then
    lifecycle.sh stop "$_new" > /dev/null 2>&1
    __watchdog_available && __watchdog_deregister "$_new" > /dev/null 2>&1
  fi
  [[ -n "$__tf_shortcut" ]] && __logic_disable_symlink_integration "$__tf_config" > /dev/null 2>&1
  [[ -n "$__tf_firewall" ]] && files.firewall.sh disable "$_new" > /dev/null 2>&1
  if [[ -n "$__tf_symlink" ]]; then
    rm -f "$__tf_symlink"
    rmdir "$(dirname "$__tf_symlink")" 2> /dev/null
  fi
  [[ -n "$__tf_backups_dir" ]] && rm -rf "${__tf_backups_dir:?}"
  if [[ -n "$__tf_new_wd" ]] && [[ -d "$__tf_new_wd" ]]; then
    mv -T "$__tf_new_wd" "$__tf_stage_instance" > /dev/null 2>&1
    rmdir "$(dirname "$__tf_new_wd")" 2> /dev/null
  fi
  [[ -n "$__tf_installed_blueprint" ]] && rm -f "$__tf_installed_blueprint"
  [[ -n "$__tf_installed_overrides" ]] && rm -rf "${__tf_installed_overrides:?}"
  return 0
}

export -f __transfer_finish_unwind

# Builds the instance from a staged import.
#
# The verbs it composes are the move's own: the paths are rewritten with
# __logic_instance_rewrite_paths, the management file and compose file are
# regenerated from the rewritten config, the registry is pointed at the new
# tree, and the instance is started once and stopped again. What a transfer adds
# is the fresh id, the blueprint that travels, the backups, and the settings that
# belong to the host it lands on.
#
# Args: $1 = import id
# Outputs: JSON `{"instance", "blueprint", "library"}`
# Returns: EC_SUCCESS, EC_IMPORT_NOT_FOUND, EC_TRANSFER_INTEGRITY, the check's
#          code when the host no longer accepts the instance, the start-once
#          failure's code, or another EC_*. A failure leaves the staged import.
function __logic_transfer_import_finish() {
  local _id="$1"

  __transfer_error_out=""
  __tf_symlink="" __tf_blueprint_name="" __tf_new_wd="" __tf_stage_instance=""
  __tf_config="" __tf_firewall="" __tf_shortcut="" __tf_backups_dir=""
  __tf_installed_blueprint="" __tf_installed_overrides=""

  local _stage
  _stage="$(__transfer_stage_dir "$_id")" || return $EC_IMPORT_NOT_FOUND

  local _manifest="${_stage}/manifest.json"
  local _tree="${_stage}/tree"
  local _suffix _library _library_dir
  _suffix="$(jq -r '.blueprint_suffix' "${_stage}/meta.json")"
  _library="$(jq -r '.library' "${_stage}/meta.json")"
  _library_dir="$(__logic_library_path "$_library")" || return $EC_LIBRARY_NOT_FOUND

  # Everything the manifest lists has arrived, and the tree is the size it said.
  local _part_id
  while IFS= read -r _part_id; do
    if [[ ! -e "${_stage}/parts/${_part_id}.done" ]]; then
      __transfer_error_out="Part ${_part_id} has not arrived"
      return $EC_TRANSFER_INTEGRITY
    fi
  done < <(jq -r '.parts[].id' "$_manifest")

  local _want_bytes _want_files _got_bytes _got_files
  _want_bytes="$(jq -r '.parts[] | select(.id == "tree") | .bytes' "$_manifest")"
  _want_files="$(jq -r '.parts[] | select(.id == "tree") | .files' "$_manifest")"
  read -r _got_bytes _got_files < <(__transfer_measure_dirs \
    "${_tree}/instance" "${_tree}/backups" "${_tree}/blueprint" "${_tree}/overrides")
  if [[ "$_got_bytes" != "$_want_bytes" ]] || [[ "$_got_files" != "$_want_files" ]]; then
    __transfer_error_out="The tree holds ${_got_files} files and ${_got_bytes} bytes; the manifest says ${_want_files} and ${_want_bytes}"
    return $EC_TRANSFER_INTEGRITY
  fi

  local _old _old_wd _display_name _has_run _autostart
  _old="$(jq -r '.instance.id' "$_manifest")"
  _old_wd="$(jq -r '.instance.working_dir' "$_manifest")"
  _display_name="$(jq -r '.instance.display_name // ""' "$_manifest")"
  _has_run="$(jq -r '.instance.has_run' "$_manifest")"
  _autostart="$(jq -r '.instance.autostart' "$_manifest")"

  if [[ ! -f "${_tree}/instance/${_old}.config.ini" ]]; then
    __transfer_error_out="The tree carries no config for ${_old}"
    return $EC_TRANSFER_INTEGRITY
  fi

  # The host may have changed since the begin: the blueprint and the ports are
  # decided again, with nothing written yet.
  __transfer_refusals=()
  __transfer_resolve_blueprint "$_manifest" "$_suffix"
  __transfer_check_ports "$_manifest"
  if [[ ${#__transfer_refusals[@]} -gt 0 ]]; then
    local _row="${__transfer_refusals[0]}"
    __transfer_error_out="$(cut -f3 <<< "$_row")"
    return "${_row%%$'\t'*}"
  fi

  local _bp="$__transfer_blueprint_out"
  local _action="$__transfer_blueprint_action_out"
  local _bp_name
  _bp_name="$(jq -r '.blueprint.name' "$_manifest")"

  local _bp_target="${KGSM_USER_BLUEPRINTS_DIR}/${_bp}.bp.yaml"
  local _rc

  if [[ "$_action" == "install" ]] || [[ "$_action" == "install-suffixed" ]]; then
    local _bp_src="${_tree}/blueprint/${_bp_name}.bp.yaml"
    local _yaml_name
    _yaml_name="$(__bp_yaml_field "$_bp_src" '.name')"
    mkdir -p "$KGSM_USER_BLUEPRINTS_DIR" "$KGSM_USER_OVERRIDES_DIR" || return $EC_FAILED_MKDIR

    if [[ "$_action" == "install" ]]; then
      cp -p "$_bp_src" "$_bp_target" || return $EC_FAILED_CP
    else
      __transfer_render_blueprint "$_bp_src" "$_bp_target" add "$_suffix" || return $EC_FAILED_CP
    fi
    __tf_installed_blueprint="$_bp_target"

    local _ov_dest="${KGSM_USER_OVERRIDES_DIR}/${_yaml_name}"
    [[ "$_action" == "install-suffixed" ]] && _ov_dest="${_ov_dest}-${_suffix}"
    if [[ -d "${_tree}/overrides/${_yaml_name}" ]] && [[ ! -e "$_ov_dest" ]]; then
      cp -a "${_tree}/overrides/${_yaml_name}" "$_ov_dest" || {
        __transfer_finish_unwind ""
        return $EC_FAILED_CP
      }
      __tf_installed_overrides="$_ov_dest"
    fi
  fi

  local _bp_file
  _bp_file="$(__find_blueprint "$_bp")" || {
    __transfer_finish_unwind ""
    return $EC_BLUEPRINT_NOT_FOUND
  }

  # A fresh id, as a fresh install would be given.
  local _new
  _new="$(__logic_generate_unique_instance_name "$_bp")" || {
    __transfer_finish_unwind ""
    return $EC_ERROR
  }

  local _new_wd
  _new_wd="$(__logic_instance_target_working_dir "$_library_dir" "$_bp" "$_new")" || {
    __transfer_finish_unwind ""
    return $EC_ERROR
  }
  if [[ -e "$_new_wd" ]]; then
    __transfer_finish_unwind ""
    __transfer_error_out="${_new_wd} already exists"
    return $EC_ERROR
  fi

  mkdir -p "$(dirname "$_new_wd")" || {
    __transfer_finish_unwind ""
    return $EC_FAILED_MKDIR
  }
  __tf_stage_instance="${_tree}/instance"
  __logic_instance_rename_tree "$__tf_stage_instance" "$_new_wd" || {
    rmdir "$(dirname "$_new_wd")" 2> /dev/null
    __transfer_finish_unwind ""
    return $EC_FAILED_MV
  }
  __tf_new_wd="$_new_wd"

  local _config="${_new_wd}/${_new}.config.ini"
  __tf_config="$_config"
  # The minted id can equal the source's, and mv refuses a file onto itself.
  if [[ "$_old" != "$_new" ]]; then
    mv "${_new_wd}/${_old}.config.ini" "$_config" || {
      __transfer_finish_unwind "$_new"
      return $EC_FAILED_MV
    }
  fi

  # Paths first, so the files that carry the old id in their names can be found
  # at the new working directory and renamed to carry the new one.
  __logic_instance_rewrite_paths "$_config" "$_old_wd" "$_new_wd" "$_library_dir" || {
    __transfer_finish_unwind "$_new"
    return $EC_FAILED_UPDATE_CONFIG
  }

  # The files whose names carry the id are renamed to carry the new one, and the
  # config follows them.
  local _key _path _base _renamed
  for _key in management_file compose_file version_file latest_version_file \
    pid_file socket_file log_file; do
    _path="$(__transfer_cfg "$_config" "$_key")"
    [[ -n "$_path" ]] || continue
    _base="$(basename "$_path")"
    _renamed="${_base/"$_old"/"$_new"}"
    [[ "$_renamed" != "$_base" ]] || continue
    if [[ -e "$_path" ]]; then
      mv "$_path" "$(dirname "$_path")/${_renamed}" || {
        __transfer_finish_unwind "$_new"
        return $EC_FAILED_MV
      }
    fi
    __transfer_cfg_set "$_config" "$_key" "$(dirname "$_path")/${_renamed}"
  done
  rm -f "$(__transfer_cfg "$_config" pid_file)" "$(__transfer_cfg "$_config" socket_file)"

  local _backups_dir
  _backups_dir="$(__logic_resolve_backups_dir "$_new")" || {
    __transfer_finish_unwind "$_new"
    return $EC_INVALID_CONFIG
  }

  [[ -z "$_display_name" ]] && _display_name="$_new"

  if ! {
    __transfer_cfg_set "$_config" name "$_new" &&
      __transfer_cfg_set "$_config" display_name "$_display_name" &&
      __transfer_cfg_set "$_config" install_nonce "$(__new_install_nonce)" &&
      __transfer_cfg_set "$_config" blueprint_file "$_bp_file" &&
      __transfer_cfg_set "$_config" backups_dir "$_backups_dir" &&
      __transfer_cfg_set "$_config" enable_firewall_management "false" &&
      __transfer_cfg_set "$_config" enable_command_shortcuts "false" &&
      __transfer_cfg_set "$_config" command_shortcut_file "" &&
      __transfer_cfg_set "$_config" enable_port_forwarding "${config_enable_port_forwarding:-false}" &&
      __transfer_cfg_drop "$_config" transfer_lock transfer_lock_autostart firewall_rule_file
  }; then
    __transfer_finish_unwind "$_new"
    return $EC_FAILED_UPDATE_CONFIG
  fi

  __logic_create_management_file "$_config"
  if [[ $? -ne $EC_SUCCESS_MANAGEMENT_FILE_CREATED ]]; then
    __transfer_finish_unwind "$_new"
    __transfer_error_out="The management file could not be regenerated"
    return $EC_FAILED_TEMPLATE
  fi

  # The commit of the move: from here the host looks for the instance here.
  __logic_create_instance_symlink "$_bp" "$_new" "$_new_wd" || {
    __transfer_finish_unwind "$_new"
    return $EC_FAILED_LN
  }
  __tf_symlink="${KGSM_INSTANCES_DIR}/${_bp}/${_new}"

  # Integrations follow the host's own settings, not the source's.
  if [[ "${config_enable_firewall_management:-}" == "true" ]]; then
    files.firewall.sh enable "$_new" > /dev/null 2>&1
    _rc=$?
    __tf_firewall="1"
    if [[ $_rc -ne 0 ]]; then
      __transfer_finish_unwind "$_new"
      return $_rc
    fi
  fi
  if [[ "${config_enable_command_shortcuts:-}" == "true" ]]; then
    files.symlink.sh enable "$_new" > /dev/null 2>&1 && __tf_shortcut="1"
  fi

  if [[ "$_has_run" == "true" ]]; then
    __logic_instance_start_once "$_new"
    _rc=$?
    if [[ $_rc -ne 0 ]]; then
      __transfer_finish_unwind "$_new"
      __transfer_error_out="Instance did not start from ${_new_wd}"
      return $_rc
    fi
  fi

  if [[ -d "${_tree}/backups" ]]; then
    mkdir -p "$_backups_dir" || {
      __transfer_finish_unwind "$_new"
      return $EC_FAILED_MKDIR
    }
    __tf_backups_dir="$_backups_dir"
    if ! cp -a "${_tree}/backups/." "${_backups_dir}/"; then
      __transfer_finish_unwind "$_new"
      return $EC_FAILED_CP
    fi
  fi

  if [[ "$_autostart" == "true" ]]; then
    __watchdog_set_autostart enable "$_new"
    if [[ $? -ne $EC_SUCCESS_AUTOSTART_ENABLED ]]; then
      __transfer_finish_unwind "$_new"
      __transfer_error_out="Boot autostart could not be set on ${_new}"
      return $EC_ERROR
    fi
  fi

  # Done: what was staged has been used, and the images it loaded stay.
  rm -rf "${_stage:?}"
  rmdir "$(dirname "$_stage")" 2> /dev/null

  __transfer_finish_json="$(jq -nc --arg instance "$_new" --arg blueprint "$_bp" \
    --arg library "$_library" '{instance: $instance, blueprint: $blueprint, library: $library}')"
  return $EC_SUCCESS
}

export -f __logic_transfer_import_finish

declare -g KGSM_LOGIC_TRANSFER_LOADED=1
export KGSM_LOGIC_TRANSFER_LOADED
