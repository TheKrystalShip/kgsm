#!/usr/bin/env bash

# KGSM Pure Logic Layer - Library Management
#
# A library is a named root that game server instances are placed in. The set of
# them is the registry at $KGSM_DATA_DIR/libraries.ini, one INI section per
# library, and every library root carries a `.kgsm-library` marker naming the
# same identity. Two records rather than one because they answer different
# questions: the registry is what this host knows, the marker is what the disk
# itself says — and an unmounted disk leaves an empty directory behind, so only
# the marker can tell a mounted library from its mount point.
#
# These functions have no user-facing I/O and communicate results only via exit
# codes; the ones that answer a question echo the answer.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - 232: Library added (emit library.added)
# - 233: Library removed (emit library.removed)
# - Standard error codes: EC_LIBRARY_NOT_FOUND, EC_LIBRARY_EXISTS,
#   EC_LIBRARY_IN_USE, EC_INVALID_ARG, EC_PERMISSION, etc.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -n "${KGSM_LOGIC_LIBRARIES_LOADED:-}" ]]; then
  return 0
fi

# The file every library root is identified by.
declare -g -r KGSM_LIBRARY_MARKER_FILENAME=".kgsm-library"
export KGSM_LIBRARY_MARKER_FILENAME

# =============================================================================
# REGISTRY
# =============================================================================

# Echoes the registry path. The file is created by the first `add`, so every
# reader treats its absence as "no libraries registered".
function __library_registry_file() {
  echo "${KGSM_DATA_DIR}/libraries.ini"
  return $EC_SUCCESS
}

export -f __library_registry_file

# Echoes every registered library name, one per line, in registry order.
function __library_registry_names() {
  local _registry _line
  _registry="$(__library_registry_file)"

  if [[ ! -f "$_registry" ]]; then
    return $EC_SUCCESS
  fi

  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" =~ ^\[([^]]+)\]$ ]]; then
      echo "${BASH_REMATCH[1]}"
    fi
  done < "$_registry"

  return $EC_SUCCESS
}

export -f __library_registry_names

# Fills the array named by $1 with every registered library name.
#
# The names are collected before they are looked at. A search that reads them
# from a process substitution and returns on the first match leaves the writer
# holding a closed pipe, and its next `echo` prints `write error: Broken pipe`
# onto the caller's stderr — two stray lines ahead of every refusal that
# searches the registry twice. Reading the whole list first is what removes the
# early exit that causes it.
#
# Args: $1 = the name of an array to fill
# Returns: EC_SUCCESS, or EC_INVALID_ARG when no array was named
function __library_registry_name_list() {
  local -n __library_names_ref="$1" 2> /dev/null || return $EC_INVALID_ARG

  local -a _raw=()
  mapfile -t _raw < <(__library_registry_names)

  # mapfile keeps a trailing empty line as an element; a blank name is not a
  # library and must not be counted as one.
  __library_names_ref=()
  local _name
  for _name in "${_raw[@]}"; do
    [[ -n "$_name" ]] && __library_names_ref+=("$_name")
  done

  return $EC_SUCCESS
}

export -f __library_registry_name_list

# Echoes one field of one library.
# Args: $1 = library name, $2 = field name (id|path)
# Returns: EC_SUCCESS, EC_INVALID_ARG, or EC_LIBRARY_NOT_FOUND
function __library_registry_field() {
  local _name="$1"
  local _field="$2"

  if [[ -z "$_name" ]] || [[ -z "$_field" ]]; then
    return $EC_INVALID_ARG
  fi

  local _registry _line _in_section=0
  _registry="$(__library_registry_file)"

  if [[ ! -f "$_registry" ]]; then
    return $EC_LIBRARY_NOT_FOUND
  fi

  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" =~ ^\[([^]]+)\]$ ]]; then
      if [[ "${BASH_REMATCH[1]}" == "$_name" ]]; then
        _in_section=1
      else
        _in_section=0
      fi
      continue
    fi

    # Matched as a literal prefix rather than a regex: the field name reaches
    # this function from callers, and a regex would give a value like `id.path`
    # a meaning it does not have.
    if [[ $_in_section -eq 1 ]] && [[ "$_line" == "${_field}="* ]]; then
      echo "${_line#*=}"
      return $EC_SUCCESS
    fi
  done < "$_registry"

  return $EC_LIBRARY_NOT_FOUND
}

export -f __library_registry_field

# Appends one library to the registry.
# Args: $1 = name, $2 = id, $3 = path
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_FAILED_TOUCH, EC_FAILED_UPDATE_CONFIG
function __library_registry_append() {
  local _name="$1"
  local _id="$2"
  local _path="$3"

  if [[ -z "$_name" ]] || [[ -z "$_id" ]] || [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  local _registry
  _registry="$(__library_registry_file)"

  if [[ ! -f "$_registry" ]] && ! __create_file "$_registry" > /dev/null 2>&1; then
    return $EC_FAILED_TOUCH
  fi

  if ! printf '[%s]\nid=%s\npath=%s\n\n' "$_name" "$_id" "$_path" >> "$_registry" 2> /dev/null; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS
}

export -f __library_registry_append

# Removes one library's section from the registry, with the blank line that
# closes it — a section is written as a block and is removed as one.
# Args: $1 = name
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_LIBRARY_NOT_FOUND, EC_FAILED_UPDATE_CONFIG
function __library_registry_delete() {
  local _name="$1"

  if [[ -z "$_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local _registry
  _registry="$(__library_registry_file)"

  if [[ ! -f "$_registry" ]]; then
    return $EC_LIBRARY_NOT_FOUND
  fi

  local _tmp
  _tmp="$(mktemp)" || return $EC_FAILED_TOUCH

  local _line _skip=0
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" =~ ^\[([^]]+)\]$ ]]; then
      if [[ "${BASH_REMATCH[1]}" == "$_name" ]]; then
        _skip=1
      else
        _skip=0
      fi
    fi

    if [[ $_skip -eq 1 ]]; then
      continue
    fi

    printf '%s\n' "$_line"
  done < "$_registry" > "$_tmp" 2> /dev/null || {
    rm -f "$_tmp"
    return $EC_FAILED_UPDATE_CONFIG
  }

  if ! mv "$_tmp" "$_registry" 2> /dev/null; then
    rm -f "$_tmp"
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS
}

export -f __library_registry_delete

# Rewrites one library's section header.
# Args: $1 = current name, $2 = new name
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_LIBRARY_NOT_FOUND, EC_FAILED_UPDATE_CONFIG
function __library_registry_rename() {
  local _old="$1"
  local _new="$2"

  if [[ -z "$_old" ]] || [[ -z "$_new" ]]; then
    return $EC_INVALID_ARG
  fi

  local _registry
  _registry="$(__library_registry_file)"

  if [[ ! -f "$_registry" ]]; then
    return $EC_LIBRARY_NOT_FOUND
  fi

  local _tmp
  _tmp="$(mktemp)" || return $EC_FAILED_TOUCH

  local _line
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" =~ ^\[([^]]+)\]$ ]] && [[ "${BASH_REMATCH[1]}" == "$_old" ]]; then
      printf '[%s]\n' "$_new"
      continue
    fi
    printf '%s\n' "$_line"
  done < "$_registry" > "$_tmp" 2> /dev/null || {
    rm -f "$_tmp"
    return $EC_FAILED_UPDATE_CONFIG
  }

  if ! mv "$_tmp" "$_registry" 2> /dev/null; then
    rm -f "$_tmp"
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS
}

export -f __library_registry_rename

# Echoes the name of the library registered at a path, if any.
# Args: $1 = canonical path
# Returns: EC_SUCCESS when found, EC_NOT_FOUND otherwise
function __library_by_path() {
  local _path="${1%/}"

  if [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  local -a _names=()
  __library_registry_name_list _names

  local _name _registered
  for _name in "${_names[@]}"; do
    _registered="$(__library_registry_field "$_name" path)" || continue
    if [[ "${_registered%/}" == "$_path" ]]; then
      echo "$_name"
      return $EC_SUCCESS
    fi
  done

  return $EC_NOT_FOUND
}

export -f __library_by_path

# Echoes the name of the library holding an id, if any.
# Args: $1 = library id
# Returns: EC_SUCCESS when found, EC_NOT_FOUND otherwise
function __library_by_id() {
  local _id="$1"

  if [[ -z "$_id" ]]; then
    return $EC_INVALID_ARG
  fi

  local -a _names=()
  __library_registry_name_list _names

  local _name _registered
  for _name in "${_names[@]}"; do
    _registered="$(__library_registry_field "$_name" id)" || continue
    if [[ "$_registered" == "$_id" ]]; then
      echo "$_name"
      return $EC_SUCCESS
    fi
  done

  return $EC_NOT_FOUND
}

export -f __library_by_id

# =============================================================================
# MARKER
# =============================================================================

# Echoes the marker path for a library root.
# Args: $1 = library root
function __library_marker_file() {
  local _path="${1%/}"

  if [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  echo "${_path}/${KGSM_LIBRARY_MARKER_FILENAME}"
  return $EC_SUCCESS
}

export -f __library_marker_file

# Echoes one field of a library root's marker.
# Args: $1 = library root, $2 = field name (id|name)
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_FILE_NOT_FOUND, EC_KEY_NOT_FOUND
function __library_marker_read() {
  local _path="$1"
  local _field="$2"

  if [[ -z "$_path" ]] || [[ -z "$_field" ]]; then
    return $EC_INVALID_ARG
  fi

  local _marker
  _marker="$(__library_marker_file "$_path")" || return $EC_INVALID_ARG

  if [[ ! -f "$_marker" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  local _line
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    if [[ "$_line" == "${_field}="* ]]; then
      echo "${_line#*=}"
      return $EC_SUCCESS
    fi
  done < "$_marker"

  return $EC_KEY_NOT_FOUND
}

export -f __library_marker_read

# Writes a library root's marker.
# Args: $1 = library root, $2 = id, $3 = name
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_FAILED_TOUCH
function __library_marker_write() {
  local _path="$1"
  local _id="$2"
  local _name="$3"

  if [[ -z "$_path" ]] || [[ -z "$_id" ]] || [[ -z "$_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local _marker
  _marker="$(__library_marker_file "$_path")" || return $EC_INVALID_ARG

  if ! printf 'id=%s\nname=%s\n' "$_id" "$_name" > "$_marker" 2> /dev/null; then
    return $EC_FAILED_TOUCH
  fi

  return $EC_SUCCESS
}

export -f __library_marker_write

# Removes a library root's marker. Absent is success — the state asked for.
# Args: $1 = library root
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_FAILED_RM
function __library_marker_remove() {
  local _path="$1"

  if [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  local _marker
  _marker="$(__library_marker_file "$_path")" || return $EC_INVALID_ARG

  if [[ ! -f "$_marker" ]]; then
    return $EC_SUCCESS
  fi

  if ! rm -f "$_marker" 2> /dev/null; then
    return $EC_FAILED_RM
  fi

  return $EC_SUCCESS
}

export -f __library_marker_remove

# Echoes 16 hexadecimal characters from the kernel's random source. The id is
# generated once and travels with the disk in its marker, so it must not be
# derived from anything about the host that wrote it.
# Returns: EC_SUCCESS, or EC_ERROR when the read came up short
function __library_generate_id() {
  local _id
  _id="$(od -An -tx1 -N8 /dev/urandom 2> /dev/null | tr -d ' \n')"

  if [[ ${#_id} -ne 16 ]]; then
    return $EC_ERROR
  fi

  echo "$_id"
  return $EC_SUCCESS
}

export -f __library_generate_id

# =============================================================================
# QUERIES
# =============================================================================

# Validates a library name.
#
# The name is the registry's section header and the marker's name field, so it
# is restricted to lowercase letters, digits and dashes: that needs no quoting
# wherever it is read back, cannot be mistaken for a path, and cannot open with
# a dash and read as an option.
# Args: $1 = candidate name
# Returns: EC_SUCCESS or EC_INVALID_ARG
function __logic_validate_library_name() {
  local _name="$1"

  if [[ -z "$_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! "$_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    return $EC_INVALID_ARG
  fi

  return $EC_SUCCESS
}

export -f __logic_validate_library_name

# Reports whether a library is registered.
# Args: $1 = library name
# Returns: EC_SUCCESS when registered, EC_LIBRARY_NOT_FOUND otherwise
function __logic_library_exists() {
  local _name="$1"

  if [[ -z "$_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local -a _names=()
  __library_registry_name_list _names

  local _registered
  for _registered in "${_names[@]}"; do
    if [[ "$_registered" == "$_name" ]]; then
      return $EC_SUCCESS
    fi
  done

  return $EC_LIBRARY_NOT_FOUND
}

export -f __logic_library_exists

# Echoes every registered library name, one per line.
function __logic_library_list() {
  __library_registry_names
  return $EC_SUCCESS
}

export -f __logic_library_list

# Echoes a library's registered root.
# Args: $1 = library name
# Returns: EC_SUCCESS or EC_LIBRARY_NOT_FOUND
function __logic_library_path() {
  __library_registry_field "$1" path
}

export -f __logic_library_path

# Echoes a library's id.
# Args: $1 = library name
# Returns: EC_SUCCESS or EC_LIBRARY_NOT_FOUND
function __logic_library_id() {
  __library_registry_field "$1" id
}

export -f __logic_library_id

# Reports whether a library is reachable right now.
#
# Online means the registered root exists AND carries a marker whose id is the
# registered one. The directory alone is not enough: an unmounted disk leaves an
# empty directory at its mount point, and treating that as the library would put
# instances on the root filesystem. Measured per call — nothing is cached.
#
# Args: $1 = library name
# Returns: 0 when online, 1 when offline, EC_LIBRARY_NOT_FOUND when unregistered
function __logic_library_is_online() {
  local _name="$1"

  local _path _id _marker_id
  _path="$(__library_registry_field "$_name" path)" || return $EC_LIBRARY_NOT_FOUND
  _id="$(__library_registry_field "$_name" id)" || return $EC_LIBRARY_NOT_FOUND

  if [[ ! -d "$_path" ]]; then
    return 1
  fi

  _marker_id="$(__library_marker_read "$_path" id)" || return 1

  if [[ "$_marker_id" != "$_id" ]]; then
    return 1
  fi

  return 0
}

export -f __logic_library_is_online

# Echoes the free and total bytes of the filesystem holding a path, separated by
# a space.
#
# `df -P` is the portable output format: one line per filesystem regardless of
# how long the device name is, which is what makes the fields readable by
# position. `-k` fixes the unit at 1K blocks so the arithmetic needs no guess
# about df's block size.
#
# Args: $1 = path
# Returns: EC_SUCCESS, EC_INVALID_ARG, EC_DIRECTORY_NOT_FOUND, or EC_ERROR when
#          df reported something this cannot read
function __logic_library_capacity() {
  local _path="$1"

  if [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -d "$_path" ]]; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  local _line
  _line="$(df -P -k "$_path" 2> /dev/null | tail -n 1)"

  if [[ -z "$_line" ]]; then
    return $EC_ERROR
  fi

  local -a _fields=()
  read -ra _fields <<< "$_line"

  # Fields: filesystem, 1K-blocks, used, available, capacity, mount point.
  if [[ ! "${_fields[1]:-}" =~ ^[0-9]+$ ]] || [[ ! "${_fields[3]:-}" =~ ^[0-9]+$ ]]; then
    return $EC_ERROR
  fi

  echo "$((_fields[3] * 1024)) $((_fields[1] * 1024))"
  return $EC_SUCCESS
}

export -f __logic_library_capacity

# Echoes the working directory of every registered instance, one per line.
#
# The symlink's target is read rather than followed: a library that is not
# mounted leaves a broken symlink behind, and its instances have to stay
# countable for the refusals that protect them.
function __library_instance_working_dirs() {
  (
    shopt -s nullglob
    local _dir
    for _dir in "$KGSM_INSTANCES_DIR"/*/*; do
      if [[ -L "$_dir" ]]; then
        readlink "$_dir"
      fi
    done
  )

  return $EC_SUCCESS
}

export -f __library_instance_working_dirs

# Echoes the name of the library a working directory sits in.
#
# The match is the longest registered path that prefixes the directory, so a
# library nested inside another resolves to the inner one. An instance that no
# registered library contains is reported as such by the caller, never assigned
# to the nearest one.
#
# Args: $1 = working directory
# Returns: EC_SUCCESS, EC_INVALID_ARG, or EC_NOT_FOUND
function __logic_library_for_working_dir() {
  local _working_dir="${1%/}"

  if [[ -z "$_working_dir" ]]; then
    return $EC_INVALID_ARG
  fi

  local -a _names=()
  __library_registry_name_list _names

  local _name _path _best="" _best_length=0
  for _name in "${_names[@]}"; do
    _path="$(__library_registry_field "$_name" path)" || continue
    _path="${_path%/}"
    [[ -z "$_path" ]] && continue

    if [[ "$_working_dir" == "$_path"/* ]] && [[ ${#_path} -gt $_best_length ]]; then
      _best="$_name"
      _best_length=${#_path}
    fi
  done

  if [[ -z "$_best" ]]; then
    return $EC_NOT_FOUND
  fi

  echo "$_best"
  return $EC_SUCCESS
}

export -f __logic_library_for_working_dir

# Echoes the names of the instances placed in a library, one per line.
# Args: $1 = library name
# Returns: EC_SUCCESS or EC_LIBRARY_NOT_FOUND
function __logic_library_instances() {
  local _name="$1"

  if ! __logic_library_exists "$_name"; then
    return $EC_LIBRARY_NOT_FOUND
  fi

  (
    shopt -s nullglob
    local _dir _target _resolved
    for _dir in "$KGSM_INSTANCES_DIR"/*/*; do
      [[ -L "$_dir" ]] || continue
      _target="$(readlink "$_dir")"
      [[ -z "$_target" ]] && continue
      _resolved="$(__logic_library_for_working_dir "$_target")" || continue
      if [[ "$_resolved" == "$_name" ]]; then
        basename "$_dir"
      fi
    done
  )

  return $EC_SUCCESS
}

export -f __logic_library_instances

# Echoes the registry symlink of an instance, found without following it.
#
# The registry layout is $KGSM_INSTANCES_DIR/<blueprint>/<instance>, and only
# the blueprint is unknown, so one glob resolves it. The test is -L and not -e
# on purpose: a library that is not mounted leaves the link dangling, and an
# instance nothing can find is an instance nothing can refuse to destroy.
#
# Args: $1 = instance name
# Returns: EC_SUCCESS, EC_INVALID_ARG, or EC_NOT_FOUND
function __logic_instance_symlink() {
  local _instance="$1"

  if [[ -z "$_instance" ]]; then
    return $EC_INVALID_ARG
  fi

  local _candidate
  for _candidate in "$KGSM_INSTANCES_DIR"/*/"$_instance"; do
    if [[ -L "$_candidate" ]]; then
      echo "$_candidate"
      return $EC_SUCCESS
    fi
  done

  return $EC_NOT_FOUND
}

export -f __logic_instance_symlink

# Echoes the state of the library an instance is placed in: online, offline or
# unregistered.
#
# Everything here is read from the symlink's target rather than through it. An
# instance on an unmounted library is precisely an instance whose every file is
# unreadable, so a check that opened its config could report only that it was
# gone — the one thing that is not true. The blueprint and the working directory
# are recoverable from the registry alone, and they are the whole of what can
# honestly be said about the instance until its disk is back.
#
# Args: $1 = instance name
# Outputs (globals, always assigned):
#   __instance_library_state_out  the state, echoed as well so that a caller
#                                 needing only it can use a subshell
#   __instance_library_name_out   the library's name, empty when unregistered
#   __instance_library_path_out   the library's registered root, empty likewise
#   __instance_working_dir_out    the directory the registry points at
#   __instance_blueprint_out      the blueprint the instance was made from
# Returns: EC_SUCCESS, EC_INVALID_ARG, or EC_NOT_FOUND when the instance is not
#          in the registry at all
function __logic_instance_library_state() {
  local _instance="$1"

  __instance_library_state_out=""
  __instance_library_name_out=""
  __instance_library_path_out=""
  __instance_working_dir_out=""
  __instance_blueprint_out=""

  if [[ -z "$_instance" ]]; then
    return $EC_INVALID_ARG
  fi

  local _symlink
  _symlink="$(__logic_instance_symlink "$_instance")" || return $EC_NOT_FOUND

  __instance_blueprint_out="$(basename "$(dirname "$_symlink")")"
  __instance_working_dir_out="$(readlink "$_symlink")"

  local _library
  if ! _library="$(__logic_library_for_working_dir "$__instance_working_dir_out")"; then
    __instance_library_state_out="unregistered"
    echo "unregistered"
    return $EC_SUCCESS
  fi

  __instance_library_name_out="$_library"
  __instance_library_path_out="$(__logic_library_path "$_library")"

  if __logic_library_is_online "$_library"; then
    __instance_library_state_out="online"
  else
    __instance_library_state_out="offline"
  fi

  echo "$__instance_library_state_out"
  return $EC_SUCCESS
}

export -f __logic_instance_library_state

# Adds the library measurement to a status object.
#
# The field has to read the same on an instance whose disk is there as on one
# whose disk is not: a key present in only one of the two cases is a key a
# consumer cannot join on, and its absence would look like the unknown it is not.
# It also has to read the same whichever verb was asked, so this is the one
# definition both `instances status` and the `status` shorthand overlay with.
# The human form is the management script's own and is left as it wrote it.
#
# Args: $1 = json flag, $2 = the measured state, $3 = the status output
function __overlay_library_state() {
  local json_flag="$1"
  local state="$2"
  local raw="$3"

  if [[ -z "$json_flag" ]] || [[ -z "$state" ]]; then
    printf '%s' "$raw"
    return 0
  fi

  local out
  if out=$(printf '%s' "$raw" | jq --arg s "$state" '. + {library_state: $s}' 2> /dev/null) \
    && [[ -n "$out" ]]; then
    printf '%s' "$out"
  else
    printf '%s' "$raw"
  fi
}

export -f __overlay_library_state

# =============================================================================
# PLACEMENT
# =============================================================================

# The directory a library holds its instances under. The library's top level
# carries the marker and this namespace and nothing else, so a disk that is also
# used for other things stays legible.
function __library_instances_subdir() {
  local _path="${1%/}"

  if [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  echo "${_path}/instances"
  return $EC_SUCCESS
}

export -f __library_instances_subdir

# Echoes the library a new instance is placed in.
#
# Three sources, in order: the name the caller asked for, the configured
# default, and — only when the host has exactly one — the sole registered
# library. A host with several libraries and no default is asked rather than
# guessed at: which disk a server lands on is a decision, not a detail.
#
# Args: $1 = requested name (optional)
# Outputs (globals, always assigned):
#   __library_resolve_name_out    the name that was asked for or configured,
#                                 echoed back so a refusal can name it
#   __library_resolve_source_out  flag|default|sole
# Returns: EC_SUCCESS (name echoed), EC_LIBRARY_NOT_FOUND (the named library is
#          not registered), EC_NOT_FOUND (no libraries registered at all), or
#          EC_MISSING_ARG (several registered and none chosen)
function __logic_library_resolve_placement() {
  local _requested="${1:-}"

  __library_resolve_name_out=""
  __library_resolve_source_out=""

  if [[ -n "$_requested" ]]; then
    __library_resolve_name_out="$_requested"
    __library_resolve_source_out="flag"
    if ! __logic_library_exists "$_requested"; then
      return $EC_LIBRARY_NOT_FOUND
    fi
    echo "$_requested"
    return $EC_SUCCESS
  fi

  # shellcheck disable=SC2154
  local _default="${config_default_library:-}"
  if [[ -n "$_default" ]]; then
    __library_resolve_name_out="$_default"
    __library_resolve_source_out="default"
    if ! __logic_library_exists "$_default"; then
      return $EC_LIBRARY_NOT_FOUND
    fi
    echo "$_default"
    return $EC_SUCCESS
  fi

  local -a _registered=()
  __library_registry_name_list _registered

  if [[ ${#_registered[@]} -eq 0 ]]; then
    return $EC_NOT_FOUND
  fi

  if [[ ${#_registered[@]} -gt 1 ]]; then
    return $EC_MISSING_ARG
  fi

  __library_resolve_name_out="${_registered[0]}"
  __library_resolve_source_out="sole"
  echo "${_registered[0]}"
  return $EC_SUCCESS
}

export -f __logic_library_resolve_placement

# Reports whether a library has room for a game that declares what it needs.
#
# The requirement is the blueprint's advisory base_disk_mb plus a margin, and
# the margin is what keeps the check honest: a download lands in a temp
# directory inside the same library before it is deployed, and a disk filled to
# the last byte fails a game server in ways that look like corruption.
#
# A blueprint declaring no figure leaves this unable to answer. It says so
# rather than inventing a requirement, and the caller carries on — a fabricated
# number would refuse installs that would have worked.
#
# Args: $1 = library root, $2 = required MB (empty/null = undeclared),
#       $3 = margin MB
# Outputs (globals, always assigned):
#   __library_space_free_out      free bytes measured on the root
#   __library_space_required_out  bytes the check wanted to see free
# Returns: EC_SUCCESS (room), EC_INSUFFICIENT_DISK (not enough),
#          EC_NOT_FOUND (nothing declared, nothing checked), or the capacity
#          error when the root could not be measured
function __logic_library_space_check() {
  local _path="$1"
  local _required_mb="$2"
  local _margin_mb="${3:-0}"

  __library_space_free_out=""
  __library_space_required_out=""

  if [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! "$_required_mb" =~ ^[0-9]+$ ]] || [[ "$_required_mb" -le 0 ]]; then
    return $EC_NOT_FOUND
  fi

  [[ "$_margin_mb" =~ ^[0-9]+$ ]] || _margin_mb=0

  local _free _total
  read -r _free _total < <(__logic_library_capacity "$_path") || return $EC_ERROR

  if [[ ! "$_free" =~ ^[0-9]+$ ]]; then
    return $EC_ERROR
  fi

  local _required=$(((_required_mb + _margin_mb) * 1024 * 1024))

  __library_space_free_out="$_free"
  __library_space_required_out="$_required"

  if [[ "$_free" -lt "$_required" ]]; then
    return $EC_INSUFFICIENT_DISK
  fi

  return $EC_SUCCESS
}

export -f __logic_library_space_check

# Records the library root of an instance created before instances recorded one.
#
# Every instance that predates the key sits flat at <root>/<blueprint>/<name>,
# so the root is the working directory minus two components. New instances are
# stamped when they are created, which is what keeps that rule from ever having
# to guess about the nested layout below a library.
#
# Idempotent: an instance already carrying the key is left alone.
#
# Args: $1 = instance config file
# Returns: EC_SUCCESS (present or stamped), EC_INVALID_ARG,
#          EC_FILE_NOT_FOUND, EC_FAILED_UPDATE_CONFIG
function __logic_stamp_instance_library_dir() {
  local _config_file="$1"

  if [[ -z "$_config_file" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -f "$_config_file" ]]; then
    return $EC_FILE_NOT_FOUND
  fi

  # Read forkless: this runs on every lifecycle command, and the answer for an
  # instance that already carries the key is on one of the first lines.
  local _key _value _library_dir="" _working_dir=""
  while IFS='=' read -r _key _value || [[ -n "$_key" ]]; do
    case "$_key" in
      library_dir)
        _library_dir="$_value"
        ;;
      working_dir)
        _working_dir="$_value"
        ;;
      *)
        continue
        ;;
    esac
  done < "$_config_file"

  _library_dir="${_library_dir#\"}"
  _library_dir="${_library_dir%\"}"
  _working_dir="${_working_dir#\"}"
  _working_dir="${_working_dir%\"}"

  if [[ -n "$_library_dir" ]]; then
    return $EC_SUCCESS
  fi

  if [[ -z "$_working_dir" ]] || [[ "$_working_dir" != /* ]]; then
    return $EC_INVALID_ARG
  fi

  local _root="${_working_dir%/*}"
  _root="${_root%/*}"

  if [[ -z "$_root" ]]; then
    return $EC_INVALID_ARG
  fi

  if ! __add_or_update_config "$_config_file" "library_dir" "\"$_root\"" > /dev/null 2>&1; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  return $EC_SUCCESS
}

export -f __logic_stamp_instance_library_dir

# =============================================================================
# VERBS
# =============================================================================

# Registers a library at a path.
#
# A directory that already carries a marker is ADOPTED: it keeps the identity
# written in it, so a disk moved between hosts — or re-mounted after being
# deregistered — is recognised as the library it already is rather than made
# into a new one. A directory with no marker gets a fresh id and, unless one is
# supplied, its own basename as its name.
#
# Args: $1 = path, $2 = requested name (optional)
# Outputs (globals, always assigned):
#   __library_add_name_out     the resulting name, or the conflicting library's
#   __library_add_path_out     the canonical root that was registered
#   __library_add_adopted_out  true when an existing marker supplied the id
#   __library_add_conflict_out path|id|name when EC_LIBRARY_EXISTS is returned
# Returns: EC_SUCCESS_LIBRARY_ADDED, or an error code
function __logic_library_add() {
  local _path="$1"
  local _requested_name="${2:-}"

  __library_add_name_out=""
  __library_add_path_out=""
  __library_add_adopted_out=false
  __library_add_conflict_out=""

  if [[ -z "$_path" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -n "$_requested_name" ]] && ! __logic_validate_library_name "$_requested_name"; then
    return $EC_INVALID_ARG
  fi

  if [[ ! -d "$_path" ]] && ! mkdir -p "$_path" 2> /dev/null; then
    return $EC_FAILED_MKDIR
  fi

  # The registry stores the canonical path so that two spellings of one
  # directory cannot become two libraries, and so an instance's working
  # directory prefix-matches it.
  local _canonical
  _canonical="$(realpath -e "$_path" 2> /dev/null)" || return $EC_DIRECTORY_NOT_FOUND

  if [[ ! -d "$_canonical" ]]; then
    return $EC_DIRECTORY_NOT_FOUND
  fi

  if [[ ! -w "$_canonical" ]]; then
    return $EC_PERMISSION
  fi

  local _conflict
  if _conflict="$(__library_by_path "$_canonical")"; then
    __library_add_name_out="$_conflict"
    __library_add_conflict_out="path"
    return $EC_LIBRARY_EXISTS
  fi

  local _id="" _name="" _marker_id="" _marker_name=""
  if _marker_id="$(__library_marker_read "$_canonical" id)" && [[ -n "$_marker_id" ]]; then
    __library_add_adopted_out=true
    _id="$_marker_id"

    if _conflict="$(__library_by_id "$_id")"; then
      __library_add_name_out="$_conflict"
      __library_add_conflict_out="id"
      return $EC_LIBRARY_EXISTS
    fi

    _marker_name="$(__library_marker_read "$_canonical" name)" || _marker_name=""
    _name="${_requested_name:-$_marker_name}"
  else
    _id="$(__library_generate_id)" || return $EC_ERROR
    _name="${_requested_name:-$(basename "$_canonical")}"
  fi

  if ! __logic_validate_library_name "$_name"; then
    return $EC_INVALID_ARG
  fi

  if __logic_library_exists "$_name"; then
    __library_add_name_out="$_name"
    __library_add_conflict_out="name"
    return $EC_LIBRARY_EXISTS
  fi

  if ! __library_marker_write "$_canonical" "$_id" "$_name"; then
    return $EC_FAILED_TOUCH
  fi

  if ! __library_registry_append "$_name" "$_id" "$_canonical"; then
    __library_marker_remove "$_canonical"
    return $EC_FAILED_UPDATE_CONFIG
  fi

  __library_add_name_out="$_name"
  __library_add_path_out="$_canonical"
  return $EC_SUCCESS_LIBRARY_ADDED
}

export -f __logic_library_add

# Deregisters a library.
#
# Files are never touched: removal takes the library out of the registry and
# takes the marker off the root when the root is reachable. A library holding
# instances is refused unless forced — deregistering it would leave them placed
# in a root this host no longer knows about.
#
# Args: $1 = library name, $2 = force ("true" to deregister anyway)
# Outputs (globals, always assigned):
#   __library_remove_path_out       the root that was deregistered
#   __library_remove_instances_out  the blocking instance names, newline-separated
# Returns: EC_SUCCESS_LIBRARY_REMOVED, or an error code
function __logic_library_remove() {
  local _name="$1"
  local _force="${2:-false}"

  __library_remove_path_out=""
  __library_remove_instances_out=""

  if [[ -z "$_name" ]]; then
    return $EC_INVALID_ARG
  fi

  if ! __logic_library_exists "$_name"; then
    return $EC_LIBRARY_NOT_FOUND
  fi

  local _path
  _path="$(__library_registry_field "$_name" path)" || return $EC_LIBRARY_NOT_FOUND

  local _instances
  _instances="$(__logic_library_instances "$_name")"

  if [[ -n "$_instances" ]] && [[ "$_force" != "true" ]]; then
    __library_remove_instances_out="$_instances"
    return $EC_LIBRARY_IN_USE
  fi

  # The marker goes only when the library is online. An unmounted disk keeps its
  # identity, so re-adding it later adopts the library it already holds instead
  # of minting a second one over the same instances.
  if __logic_library_is_online "$_name"; then
    if ! __library_marker_remove "$_path"; then
      return $EC_FAILED_RM
    fi
  fi

  if ! __library_registry_delete "$_name"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  __library_remove_path_out="$_path"
  __library_remove_instances_out="$_instances"
  return $EC_SUCCESS_LIBRARY_REMOVED
}

export -f __logic_library_remove

# Renames a library in the registry and in its marker.
#
# Instances are unaffected: they record the library's path, and the registry is
# the only place a name lives. A library that is offline is renamed in the
# registry alone — its marker carries the old name until the root is reachable,
# which changes nothing, because online is decided by the id.
#
# Args: $1 = current name, $2 = new name
# Outputs (globals, always assigned):
#   __library_rename_marker_out  true when the marker was rewritten too
# Returns: EC_SUCCESS, or an error code
function __logic_library_rename() {
  local _old="$1"
  local _new="$2"

  __library_rename_marker_out=false

  if [[ -z "$_old" ]] || [[ -z "$_new" ]]; then
    return $EC_INVALID_ARG
  fi

  if ! __logic_validate_library_name "$_new"; then
    return $EC_INVALID_ARG
  fi

  if ! __logic_library_exists "$_old"; then
    return $EC_LIBRARY_NOT_FOUND
  fi

  if [[ "$_old" != "$_new" ]] && __logic_library_exists "$_new"; then
    return $EC_LIBRARY_EXISTS
  fi

  local _path _id
  _path="$(__library_registry_field "$_old" path)" || return $EC_LIBRARY_NOT_FOUND
  _id="$(__library_registry_field "$_old" id)" || return $EC_LIBRARY_NOT_FOUND

  if ! __library_registry_rename "$_old" "$_new"; then
    return $EC_FAILED_UPDATE_CONFIG
  fi

  if __logic_library_is_online "$_new"; then
    if ! __library_marker_write "$_path" "$_id" "$_new"; then
      return $EC_FAILED_TOUCH
    fi
    __library_rename_marker_out=true
  fi

  return $EC_SUCCESS
}

export -f __logic_library_rename

# Mark module as loaded
declare -g KGSM_LOGIC_LIBRARIES_LOADED=1
export KGSM_LOGIC_LIBRARIES_LOADED
