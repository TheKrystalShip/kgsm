#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load boot auto-start logic (pulls in the watchdog routing helpers).
logic_library=$(__find_command_handler autostart.sh)
# shellcheck source=handlers/autostart.sh
source "$logic_library" || {
  __print_error "Failed to load autostart logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Boot Auto-start for Krystal Game Server Manager${END}

Control whether instances are automatically started on boot, like systemctl's
enable/disable. This is the boot axis, INDEPENDENT of start/stop: enabling does
not start an instance now, disabling does not stop it — they only change what
comes back after a reboot.

Auto-start is owned by the resident kgsm-watchdog daemon, so these commands
require it to be running.

${UNDERLINE}Usage:${END}
  ${self} <command> [instance]

${UNDERLINE}Commands:${END}
  enable <instance>           Auto-start the instance on boot
  disable <instance>          Do not auto-start the instance on boot
  status <instance>           Show the instance's enabled + running state
  list                        List all instances enabled for boot auto-start
  help                        Display this help

${UNDERLINE}Examples:${END}
  ${self} enable 7dtd
  ${self} disable 7dtd
  ${self} status 7dtd
  ${self} list
"
}

# Guard: every verb needs the daemon. Returns 0 if usable, else prints why and
# returns EC_ERROR.
function _require_watchdog() {
  if ! __watchdog_available; then
    __print_error "Boot auto-start requires the kgsm-watchdog daemon, which is not running or reachable."
    __print_info "Start it (e.g. 'sudo systemctl start kgsm-watchdog') and try again."
    return $EC_ERROR
  fi
  return 0
}

function _cmd_enable() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    return $EC_MISSING_ARG
  fi

  _require_watchdog || return $?

  __logic_autostart_enable "$instance_name"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_AUTOSTART_ENABLED)
      __print_success "Instance '$instance_name' enabled for boot auto-start"
      return 0
      ;;
    $EC_INVALID_INSTANCE)
      __print_error "Instance '$instance_name' not found"
      return $exit_code
      ;;
    *)
      __print_error "Failed to enable boot auto-start for '$instance_name' (daemon error)"
      return $exit_code
      ;;
  esac
}

function _cmd_disable() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    return $EC_MISSING_ARG
  fi

  _require_watchdog || return $?

  __logic_autostart_disable "$instance_name"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_AUTOSTART_DISABLED)
      __print_success "Instance '$instance_name' disabled for boot auto-start"
      return 0
      ;;
    *)
      __print_error "Failed to disable boot auto-start for '$instance_name' (daemon error)"
      return $exit_code
      ;;
  esac
}

function _cmd_status() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    return $EC_MISSING_ARG
  fi

  _require_watchdog || return $?

  local enabled_str running_str
  __logic_autostart_is_enabled "$instance_name"
  case $? in
    0) enabled_str="enabled" ;;
    1) enabled_str="disabled" ;;
    *)
      __print_error "Could not query the watchdog for '$instance_name'"
      return $EC_ERROR
      ;;
  esac

  # Running state from the daemon (untracked / unknown -> not running).
  __watchdog_is_active "$instance_name"
  case $? in
    0) running_str="running" ;;
    *) running_str="stopped" ;;
  esac

  __print_info "$instance_name: $enabled_str, $running_str"
  return 0
}

function _cmd_list() {
  _require_watchdog || return $?

  local names
  names="$(__logic_autostart_list)"
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    __print_error "Could not query the watchdog for the enabled set"
    return $EC_ERROR
  fi

  if [[ -z "$names" ]]; then
    __print_info "No instances are enabled for boot auto-start"
    return 0
  fi

  echo "$names"
  return 0
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

case "$command" in
  "" | -h | --help | help)
    show_usage
    [[ -z "$command" ]] && exit $EC_ERROR
    exit 0
    ;;
  enable)
    _cmd_enable "$@"
    exit $?
    ;;
  disable)
    _cmd_disable "$@"
    exit $?
    ;;
  status)
    _cmd_status "$@"
    exit $?
    ;;
  list)
    _cmd_list "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    echo ""
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
