#!/usr/bin/env bash

# shellcheck disable=SC2086
# shellcheck disable=SC2254
# The handler communicates a verb's resolved name, path and conflict through
# __library_*_out globals it always assigns; they are read here, never set.
# shellcheck disable=SC2154
# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Library Management for Krystal Game Server Manager${END}

A library is a named root that game server instances are placed in. Registering
several lets instances live across several disks on one host.

${UNDERLINE}Usage:${END}
  ${self} <command> [options]

${UNDERLINE}Commands:${END}
  add <path> [--name <name>]  Register a library at a path.
  remove <name> [--force]     Deregister a library. Files are never touched.
  list [--json]               List libraries with state, capacity and use.
  rename <old> <new>          Rename a library.
  help [command]              Display help information.

${UNDERLINE}Options:${END}
  -h | --help                 Display help for a specific command.

${UNDERLINE}Examples:${END}
  ${self} add /mnt/ssd/kgsm --name ssd
  ${self} list --json
  ${self} rename ssd fast
  ${self} remove ssd
"
}

function show_usage_add() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Add Library${END}

Registers a library at a path and writes the '.kgsm-library' marker into it.

${UNDERLINE}Usage:${END}
  ${self} add <path> [--name <name>]

${UNDERLINE}Arguments:${END}
  <path>                      Library root (created when it does not exist)

${UNDERLINE}Options:${END}
  --name <name>               Library name. Lowercase letters, digits and
                              dashes. Defaults to the directory's own name, or
                              to the name in an existing marker.
  -h | --help                 Display this help information

${UNDERLINE}Description:${END}
A directory that already carries a marker is adopted: it keeps the identity
written in it, so a disk that moves between hosts stays the same library. Pass
--name when the name it carries is already taken here.

${UNDERLINE}Examples:${END}
  ${self} add /mnt/ssd/kgsm --name ssd
  ${self} add /mnt/archive
"
}

function show_usage_remove() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Remove Library${END}

Deregisters a library and removes its marker when the root is reachable.

${UNDERLINE}Usage:${END}
  ${self} remove <name> [--force]

${UNDERLINE}Arguments:${END}
  <name>                      Library name (required)

${UNDERLINE}Options:${END}
  --force                     Deregister a library that holds instances
  -h | --help                 Display this help information

${UNDERLINE}Description:${END}
No file inside the library is removed, including the instances placed there.
A library holding instances is refused unless --force is passed.

${UNDERLINE}Examples:${END}
  ${self} remove ssd
  ${self} remove archive --force
"
}

function show_usage_list() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}List Libraries${END}

Lists every registered library with its state, free and total space, and the
number of instances placed in it.

${UNDERLINE}Usage:${END}
  ${self} list [--json]

${UNDERLINE}Options:${END}
  --json                      Machine-readable output
  -h | --help                 Display this help information

${UNDERLINE}Description:${END}
State is measured on every invocation: a library is online when its root exists
and carries a marker matching the registry, and offline otherwise. An offline
library reports no capacity figures rather than stale ones.

${UNDERLINE}Examples:${END}
  ${self} list
  ${self} list --json
"
}

function show_usage_rename() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Rename Library${END}

Renames a library in the registry and in its marker.

${UNDERLINE}Usage:${END}
  ${self} rename <old> <new>

${UNDERLINE}Arguments:${END}
  <old>                       Current library name (required)
  <new>                       New library name (required)

${UNDERLINE}Description:${END}
Instances are unaffected: they record the library's path, and the name lives
only in the registry. An offline library is renamed in the registry alone; its
marker catches up the next time the root is reachable.

${UNDERLINE}Examples:${END}
  ${self} rename ssd fast
"
}

# Load required libraries
logic_libraries=$(__find_command_handler libraries.sh)
# shellcheck source=handlers/libraries.sh
source "$logic_libraries" || {
  __print_error "Failed to load libraries logic library"
  exit $EC_FAILED_SOURCE
}

events_library=$(__find_core_module events.sh)
# shellcheck source=../core/events.sh
source "$events_library" || {
  __print_error "Failed to load events library"
  exit $EC_FAILED_SOURCE
}

# Renders a byte count for a person. A library that reports no figure prints a
# dash: an offline root has no measurement, and a zero would read as a full disk.
function _format_bytes() {
  local _bytes="$1"

  if [[ ! "$_bytes" =~ ^[0-9]+$ ]]; then
    echo "-"
    return 0
  fi

  awk -v bytes="$_bytes" 'BEGIN {
    split("B KB MB GB TB PB", unit, " ")
    i = 1
    while (bytes >= 1024 && i < 6) { bytes /= 1024; i++ }
    if (i == 1) printf "%d %s\n", bytes, unit[i]
    else printf "%.1f %s\n", bytes, unit[i]
  }'
}

function _cmd_add() {
  local path=""
  local name=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_add
        return 0
        ;;
      --name)
        shift
        if [[ -z "${1:-}" ]]; then
          __print_error "Missing argument for --name"
          return $EC_MISSING_ARG
        fi
        name="$1"
        ;;
      -*)
        __print_error "Invalid option for add command: $1"
        __print_error "Use '${self} add --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$path" ]]; then
          path="$1"
        else
          __print_error "Too many arguments"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$path" ]]; then
    __print_error "Missing required argument: <path>"
    __print_error "Use '${self} add --help' for usage information"
    return $EC_MISSING_ARG
  fi

  local exit_code
  __logic_library_add "$path" "$name"
  exit_code=$?

  case $exit_code in
    $EC_SUCCESS_LIBRARY_ADDED)
      if [[ "$__library_add_adopted_out" == "true" ]]; then
        __print_success "Adopted library '$__library_add_name_out' at $__library_add_path_out"
      else
        __print_success "Registered library '$__library_add_name_out' at $__library_add_path_out"
      fi
      __emit_event library-added "$__library_add_name_out" "$__library_add_path_out"
      return 0
      ;;
    $EC_LIBRARY_EXISTS)
      case "$__library_add_conflict_out" in
        path)
          __print_error "That path is already registered as library '$__library_add_name_out'"
          ;;
        id)
          __print_error "That root carries the marker of library '$__library_add_name_out', which is registered at another path"
          ;;
        name)
          __print_error "A library named '$__library_add_name_out' is already registered"
          __print_error "Pass --name to register this one under a different name"
          ;;
      esac
      return $exit_code
      ;;
    $EC_INVALID_ARG)
      if [[ -n "$name" ]]; then
        __print_error "Invalid library name: '$name'"
      else
        __print_error "The directory's name is not usable as a library name"
        __print_error "Pass --name <name>"
      fi
      __print_error "Expected: lowercase letters, digits and dashes, starting with a letter or digit"
      return $exit_code
      ;;
    $EC_FAILED_MKDIR)
      __print_error "Failed to create library root: $path"
      return $exit_code
      ;;
    $EC_DIRECTORY_NOT_FOUND)
      __print_error "Not a directory: $path"
      return $exit_code
      ;;
    $EC_PERMISSION)
      __print_error "Library root is not writable: $path"
      return $exit_code
      ;;
    *)
      __print_error "Failed to register library at $path"
      return $exit_code
      ;;
  esac
}

function _cmd_remove() {
  local name=""
  local force=false

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_remove
        return 0
        ;;
      --force)
        force=true
        ;;
      -*)
        __print_error "Invalid option for remove command: $1"
        __print_error "Use '${self} remove --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          __print_error "Too many arguments"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$name" ]]; then
    __print_error "Missing required argument: <name>"
    __print_error "Use '${self} remove --help' for usage information"
    return $EC_MISSING_ARG
  fi

  local exit_code
  __logic_library_remove "$name" "$force"
  exit_code=$?

  case $exit_code in
    $EC_SUCCESS_LIBRARY_REMOVED)
      __print_success "Deregistered library '$name' at $__library_remove_path_out"
      if [[ -n "$__library_remove_instances_out" ]]; then
        __print_warning "Instances left in place at that root:"
        local _instance
        while IFS= read -r _instance; do
          [[ -z "$_instance" ]] && continue
          __print_warning "  $_instance"
        done <<< "$__library_remove_instances_out"
      fi
      __emit_event library-removed "$name" "$__library_remove_path_out"
      return 0
      ;;
    $EC_LIBRARY_NOT_FOUND)
      __print_error "Library '$name' is not registered"
      return $exit_code
      ;;
    $EC_LIBRARY_IN_USE)
      __print_error "Library '$name' holds instances:"
      local _instance
      while IFS= read -r _instance; do
        [[ -z "$_instance" ]] && continue
        __print_error "  $_instance"
      done <<< "$__library_remove_instances_out"
      __print_error "Pass --force to deregister it and leave those instances where they are"
      return $exit_code
      ;;
    *)
      __print_error "Failed to deregister library '$name'"
      return $exit_code
      ;;
  esac
}

function _cmd_list() {
  local json=false

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_list
        return 0
        ;;
      --json)
        json=true
        ;;
      *)
        __print_error "Invalid argument for list command: $1"
        __print_error "Use '${self} list --help' for usage information"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local names
  names="$(__logic_library_list)"

  if [[ "$json" == true ]]; then
    if ! command -v jq > /dev/null 2>&1; then
      __print_error "JSON output requires jq to be installed"
      return $EC_MISSING_DEPENDENCY
    fi

    local output="[]"
    local name path state free total count entry
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      path="$(__logic_library_path "$name")"
      state="offline"
      free=""
      total=""
      if __logic_library_is_online "$name"; then
        state="online"
        read -r free total < <(__logic_library_capacity "$path")
      fi
      count="$(__logic_library_instances "$name" | grep -c .)"

      # An offline library has no capacity measurement, so it reports null
      # rather than a figure nothing measured.
      entry="$(jq -n \
        --arg name "$name" \
        --arg path "$path" \
        --arg state "$state" \
        --arg free "$free" \
        --arg total "$total" \
        --argjson count "$count" \
        '{
          name: $name,
          path: $path,
          state: $state,
          free_bytes: ($free | if . == "" then null else tonumber end),
          total_bytes: ($total | if . == "" then null else tonumber end),
          instance_count: $count
        }')" || return $EC_ERROR

      output="$(jq --argjson entry "$entry" '. + [$entry]' <<< "$output")" || return $EC_ERROR
    done <<< "$names"

    echo "$output"
    return 0
  fi

  if [[ -z "$names" ]]; then
    __print_info "No libraries registered"
    __print_info "Register one with '${self} add <path>'"
    return 0
  fi

  printf '%-16s %-8s %12s %12s %10s  %s\n' \
    "NAME" "STATE" "FREE" "TOTAL" "INSTANCES" "PATH"

  local name path state free total count
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    path="$(__logic_library_path "$name")"
    state="offline"
    free=""
    total=""
    if __logic_library_is_online "$name"; then
      state="online"
      read -r free total < <(__logic_library_capacity "$path")
    fi
    count="$(__logic_library_instances "$name" | grep -c .)"

    printf '%-16s %-8s %12s %12s %10s  %s\n' \
      "$name" "$state" "$(_format_bytes "$free")" "$(_format_bytes "$total")" \
      "$count" "$path"
  done <<< "$names"

  return 0
}

function _cmd_rename() {
  local old=""
  local new=""

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_rename
        return 0
        ;;
      -*)
        __print_error "Invalid option for rename command: $1"
        __print_error "Use '${self} rename --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$old" ]]; then
          old="$1"
        elif [[ -z "$new" ]]; then
          new="$1"
        else
          __print_error "Too many arguments"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$old" ]]; then
    __print_error "Missing required argument: <old>"
    __print_error "Use '${self} rename --help' for usage information"
    return $EC_MISSING_ARG
  fi

  if [[ -z "$new" ]]; then
    __print_error "Missing required argument: <new>"
    __print_error "Use '${self} rename --help' for usage information"
    return $EC_MISSING_ARG
  fi

  local exit_code
  __logic_library_rename "$old" "$new"
  exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      __print_success "Renamed library '$old' to '$new'"
      if [[ "$__library_rename_marker_out" != "true" ]]; then
        __print_warning "Library '$new' is offline; its marker keeps the old name until the root is reachable"
      fi
      return 0
      ;;
    $EC_LIBRARY_NOT_FOUND)
      __print_error "Library '$old' is not registered"
      return $exit_code
      ;;
    $EC_LIBRARY_EXISTS)
      __print_error "A library named '$new' is already registered"
      return $exit_code
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid library name: '$new'"
      __print_error "Expected: lowercase letters, digits and dashes, starting with a letter or digit"
      return $exit_code
      ;;
    *)
      __print_error "Failed to rename library '$old'"
      return $exit_code
      ;;
  esac
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return 0
  fi

  case "$command" in
    add)
      show_usage_add
      ;;
    remove)
      show_usage_remove
      ;;
    list)
      show_usage_list
      ;;
    rename)
      show_usage_rename
      ;;
    *)
      __print_error "Unknown command for help: $command"
      echo ""
      show_usage
      return $EC_INVALID_ARG
      ;;
  esac
}

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
    exit $?
    ;;
  add)
    _cmd_add "$@"
    exit $?
    ;;
  remove)
    _cmd_remove "$@"
    exit $?
    ;;
  list)
    _cmd_list "$@"
    exit $?
    ;;
  rename)
    _cmd_rename "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '${self} --help' for usage information"
    exit $EC_INVALID_ARG
    ;;
esac
