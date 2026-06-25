#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "${UNDERLINE}System Management for Krystal Game Server Manager${END}

Manages OS-level system operations and provides system information.

${UNDERLINE}Usage:${END}
  $self [command] [arguments] [options]

${UNDERLINE}Commands:${END}
  shutdown [time]             Schedule system shutdown
  restart [time]              Schedule system restart
  cancel                      Cancel scheduled shutdown/restart
  uptime                      Show system uptime
  load                        Show system load averages
  memory                      Show memory usage
  disk                        Show disk usage
  reboot-required             Check if system reboot is required
  info                        Display comprehensive system information
  setup-cgroups               Set up the delegated cgroup base for supervision
  help [command]              Show help information

${UNDERLINE}Options:${END}
  --json                      Output in JSON format (for info command)
  -h, --help                  Show help and exit
  --debug                     Enable debug output

${UNDERLINE}Examples:${END}
  ${BOLD}Power Management:${END}
  $self shutdown              Schedule immediate shutdown
  $self shutdown 10           Schedule shutdown in 10 minutes
  $self restart               Schedule immediate restart
  $self restart 5             Schedule restart in 5 minutes
  $self cancel                Cancel scheduled shutdown/restart

  ${BOLD}System Information:${END}
  $self uptime                Show system uptime
  $self load                  Show CPU load averages
  $self memory                Show memory usage
  $self disk                  Show disk usage
  $self reboot-required       Check if reboot is needed
  $self info                  Show all system information
  $self info --json           Show all system information in JSON format

${UNDERLINE}Notes:${END}
  • Shutdown and restart commands require sudo privileges
  • Time is specified in minutes (0 for immediate)
  • IP command shows both external and local addresses
  • System information commands are read-only
"
}

function show_usage_shutdown() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Schedule System Shutdown${END}

Schedules a system shutdown with optional delay.

${UNDERLINE}Usage:${END}
  $self shutdown [time]

${UNDERLINE}Arguments:${END}
  time                        Time delay in minutes (default: 0 for immediate)
                              Must be a positive integer

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Schedules a system shutdown. If no time is specified, the system will shut down
immediately. If a time is provided, the shutdown will be scheduled for that many
minutes in the future.

This command requires sudo privileges.

${UNDERLINE}Examples:${END}
  $self shutdown              Immediate shutdown
  $self shutdown 0            Immediate shutdown
  $self shutdown 10           Shutdown in 10 minutes
  $self shutdown 60           Shutdown in 1 hour
"
}

function show_usage_restart() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Schedule System Restart${END}

Schedules a system restart with optional delay.

${UNDERLINE}Usage:${END}
  $self restart [time]

${UNDERLINE}Arguments:${END}
  time                        Time delay in minutes (default: 0 for immediate)
                              Must be a positive integer

${UNDERLINE}Options:${END}
  --help                      Display this help information

${UNDERLINE}Description:${END}
Schedules a system restart (reboot). If no time is specified, the system will
restart immediately. If a time is provided, the restart will be scheduled for
that many minutes in the future.

This command requires sudo privileges.

${UNDERLINE}Examples:${END}
  $self restart               Immediate restart
  $self restart 0             Immediate restart
  $self restart 5             Restart in 5 minutes
  $self restart 30            Restart in 30 minutes
"
}

function show_usage_info() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Display Comprehensive System Information${END}

Shows all available system information in a single view.

${UNDERLINE}Usage:${END}
  $self info [options]

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Displays comprehensive system information including:
  • System uptime
  • CPU load averages
  • Memory usage
  • Disk usage
  • IP addresses (external and local)
  • Reboot required status

The --json flag outputs the information in a structured JSON format for
programmatic consumption. The JSON structure is always consistent, even
when some information cannot be retrieved (null values are used).

${UNDERLINE}Examples:${END}
  $self info
  $self info --json
"
}

logic_library=$(__find_command_handler system.sh)
# shellcheck source=handlers/system.sh
source "$logic_library" || {
  __print_error "Failed to load system logic library"
  exit $EC_FAILED_SOURCE
}

# Load network logic library for IP address functions used by info command
network_logic_library=$(__find_command_handler network.sh)
# shellcheck source=handlers/network.sh
source "$network_logic_library" || {
  __print_error "Failed to load network logic library"
  exit $EC_FAILED_SOURCE
}

function _cmd_shutdown() {
  local time_minutes=0

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --help)
        show_usage_shutdown
        return 0
        ;;
      *)
        # Argument should be time in minutes
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          time_minutes="$1"
        else
          __print_error "Invalid argument: $1"
          __print_error "Time must be a positive integer (minutes)"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  # Call logic function
  if [[ "$time_minutes" -eq 0 ]]; then
    __print_warning "Scheduling immediate system shutdown..."
  else
    __print_info "Scheduling system shutdown in $time_minutes minute(s)..."
  fi

  __logic_schedule_shutdown "$time_minutes"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_SYSTEM_SHUTDOWN)
      if [[ "$time_minutes" -eq 0 ]]; then
        __print_success "System shutdown initiated"
      else
        __print_success "System shutdown scheduled for $time_minutes minute(s)"
      fi
      __dispatch_event_from_exit_code "$exit_code" "system" "$time_minutes"
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid time argument"
      __print_error "Time must be a positive integer (minutes)"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied"
      __print_error "Shutdown requires sudo privileges"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "shutdown command not available"
      ;;
    *)
      __print_error "Failed to schedule shutdown"
      ;;
  esac

  return $exit_code
}

function _cmd_restart() {
  local time_minutes=0

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_restart
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_restart
        return $EC_INVALID_ARG
        ;;
      *)
        # Argument should be time in minutes
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          time_minutes="$1"
        else
          __print_error "Invalid argument: $1"
          __print_error "Time must be a positive integer (minutes)"
          return $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  # Call logic function
  if [[ "$time_minutes" -eq 0 ]]; then
    __print_warning "Scheduling immediate system restart..."
  else
    __print_info "Scheduling system restart in $time_minutes minute(s)..."
  fi

  __logic_schedule_restart "$time_minutes"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_SYSTEM_RESTART)
      if [[ "$time_minutes" -eq 0 ]]; then
        __print_success "System restart initiated"
      else
        __print_success "System restart scheduled for $time_minutes minute(s)"
      fi
      __dispatch_event_from_exit_code "$exit_code" "system" "$time_minutes"
      ;;
    $EC_INVALID_ARG)
      __print_error "Invalid time argument"
      __print_error "Time must be a positive integer (minutes)"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied"
      __print_error "Restart requires sudo privileges"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "shutdown command not available"
      ;;
    *)
      __print_error "Failed to schedule restart"
      ;;
  esac

  return $exit_code
}

function _cmd_cancel() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo "Cancel scheduled shutdown or restart"
        echo "Usage: $self cancel"
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        echo "Usage: $self cancel"
        return $EC_INVALID_ARG
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  __print_info "Cancelling scheduled shutdown/restart..."

  __logic_cancel_shutdown
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      __print_success "Scheduled shutdown/restart cancelled"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied"
      __print_error "Cancel requires sudo privileges"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "shutdown command not available"
      ;;
    *)
      __print_error "Failed to cancel shutdown/restart"
      ;;
  esac

  return $exit_code
}

function _cmd_uptime() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo "Display system uptime"
        echo "Usage: $self uptime"
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_uptime
        return $EC_INVALID_ARG
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local uptime_info
  uptime_info=$(__logic_get_uptime)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_SYSTEM_INFO_RETRIEVED)
      __print_success "System uptime: $uptime_info"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "uptime command not available"
      ;;
    *)
      __print_error "Failed to retrieve uptime information"
      ;;
  esac

  return $exit_code
}

function _cmd_load() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo "Display system load averages"
        echo "Usage: $self load"
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_load
        return $EC_INVALID_ARG
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local load_info
  load_info=$(__logic_get_load_average)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_SYSTEM_INFO_RETRIEVED)
      __print_success "Load average: $load_info"
      ;;
    *)
      __print_error "Failed to retrieve load average"
      ;;
  esac

  return $exit_code
}

function _cmd_memory() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo "Display memory usage information"
        echo "Usage: $self memory"
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_memory
        return $EC_INVALID_ARG
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local mem_info
  mem_info=$(__logic_get_memory_info)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_SYSTEM_INFO_RETRIEVED)
      __print_success "Memory usage:"
      echo "$mem_info"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "free command not available"
      ;;
    *)
      __print_error "Failed to retrieve memory information"
      ;;
  esac

  return $exit_code
}

function _cmd_disk() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo "Display disk usage information"
        echo "Usage: $self disk"
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_disk
        return $EC_INVALID_ARG
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local disk_info
  disk_info=$(__logic_get_disk_usage)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS_SYSTEM_INFO_RETRIEVED)
      __print_success "Root filesystem usage:"
      echo "$disk_info"
      ;;
    $EC_MISSING_DEPENDENCY)
      __print_error "Missing required dependency"
      __print_error "df command not available"
      ;;
    *)
      __print_error "Failed to retrieve disk usage"
      ;;
  esac

  return $exit_code
}

function _cmd_reboot_required() {
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        echo "Check if system reboot is required"
        echo "Usage: $self reboot-required"
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        echo "Usage: $self reboot-required"
        return $EC_INVALID_ARG
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  local reboot_required
  reboot_required=$(__logic_check_reboot_required)
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      if [[ "$reboot_required" == "true" ]]; then
        __print_warning "System reboot is required"
        return 0
      else
        __print_success "No system reboot required"
        return 0
      fi
      ;;
    *)
      __print_error "Failed to check reboot status"
      ;;
  esac

  return $exit_code
}

function _cmd_info() {
  local json_format=false

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_info
        return 0
        ;;
      --json)
        json_format=true
        ;;
      -*)
        __print_error "Unknown option: $1"
        echo ""
        show_usage_info
        return $EC_INVALID_ARG
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Collect all system information
  local uptime_info
  uptime_info=$(__logic_get_uptime 2> /dev/null)

  local load_info
  load_info=$(__logic_get_load_average 2> /dev/null)

  local mem_info
  mem_info=$(__logic_get_memory_info 2> /dev/null)

  local disk_info
  disk_info=$(__logic_get_disk_usage 2> /dev/null)

  local external_ip
  external_ip=$(__logic_get_external_ip 2> /dev/null)

  local local_ips
  local_ips=$(__logic_get_local_ip 2> /dev/null)

  local reboot_required
  reboot_required=$(__logic_check_reboot_required 2> /dev/null)

  # Parse memory info for JSON (if available)
  local mem_total=""
  local mem_used=""
  local mem_free=""
  local mem_available=""
  if [[ -n "$mem_info" ]]; then
    mem_total=$(echo "$mem_info" | awk '{print $2}')
    mem_used=$(echo "$mem_info" | awk '{print $3}')
    mem_free=$(echo "$mem_info" | awk '{print $4}')
    mem_available=$(echo "$mem_info" | awk '{print $7}')
  fi

  # Parse disk info for JSON (if available)
  local disk_filesystem=""
  local disk_size=""
  local disk_used=""
  local disk_available=""
  local disk_use_percent=""
  local disk_mount=""
  if [[ -n "$disk_info" ]]; then
    disk_filesystem=$(echo "$disk_info" | awk '{print $1}')
    disk_size=$(echo "$disk_info" | awk '{print $2}')
    disk_used=$(echo "$disk_info" | awk '{print $3}')
    disk_available=$(echo "$disk_info" | awk '{print $4}')
    disk_use_percent=$(echo "$disk_info" | awk '{print $5}')
    disk_mount=$(echo "$disk_info" | awk '{print $6}')
  fi

  # Parse load averages for JSON (if available)
  local load_1min=""
  local load_5min=""
  local load_15min=""
  if [[ -n "$load_info" ]]; then
    load_1min=$(echo "$load_info" | awk -F', ' '{print $1}')
    load_5min=$(echo "$load_info" | awk -F', ' '{print $2}')
    load_15min=$(echo "$load_info" | awk -F', ' '{print $3}')
  fi

  # Convert local IPs to array for JSON
  local -a local_ips_array=()
  if [[ -n "$local_ips" ]]; then
    while IFS= read -r ip; do
      [[ -n "$ip" ]] && local_ips_array+=("$ip")
    done <<< "$local_ips"
  fi

  # Output in requested format
  if [[ "$json_format" == true ]]; then
    # Check if jq is available
    if ! command -v jq > /dev/null 2>&1; then
      __print_error "Missing required dependency"
      __print_error "JSON formatting requires jq to be installed"
      return $EC_MISSING_DEPENDENCY
    fi

    # Build jq arguments
    local -a jq_args=(
      --arg uptime "${uptime_info:-null}"
      --arg load_1min "${load_1min:-null}"
      --arg load_5min "${load_5min:-null}"
      --arg load_15min "${load_15min:-null}"
      --arg mem_total "${mem_total:-null}"
      --arg mem_used "${mem_used:-null}"
      --arg mem_free "${mem_free:-null}"
      --arg mem_available "${mem_available:-null}"
      --arg disk_filesystem "${disk_filesystem:-null}"
      --arg disk_size "${disk_size:-null}"
      --arg disk_used "${disk_used:-null}"
      --arg disk_available "${disk_available:-null}"
      --arg disk_use_percent "${disk_use_percent:-null}"
      --arg disk_mount "${disk_mount:-null}"
      --arg external_ip "${external_ip:-null}"
      --arg reboot_required "${reboot_required:-null}"
    )

    # Add local IPs array
    if [[ ${#local_ips_array[@]} -gt 0 ]]; then
      local local_ips_json
      local_ips_json=$(printf '%s\n' "${local_ips_array[@]}" | jq -R . | jq -s .)
      jq_args+=(--argjson local_ips "$local_ips_json")
    else
      jq_args+=(--argjson local_ips "[]")
    fi

    # Generate JSON output
    jq -n "${jq_args[@]}" '{
      "uptime": (if $uptime == "null" then null else $uptime end),
      "load": {
        "1min": (if $load_1min == "null" then null else $load_1min end),
        "5min": (if $load_5min == "null" then null else $load_5min end),
        "15min": (if $load_15min == "null" then null else $load_15min end)
      },
      "memory": {
        "total": (if $mem_total == "null" then null else $mem_total end),
        "used": (if $mem_used == "null" then null else $mem_used end),
        "free": (if $mem_free == "null" then null else $mem_free end),
        "available": (if $mem_available == "null" then null else $mem_available end)
      },
      "disk": {
        "filesystem": (if $disk_filesystem == "null" then null else $disk_filesystem end),
        "size": (if $disk_size == "null" then null else $disk_size end),
        "used": (if $disk_used == "null" then null else $disk_used end),
        "available": (if $disk_available == "null" then null else $disk_available end),
        "use_percent": (if $disk_use_percent == "null" then null else $disk_use_percent end),
        "mount": (if $disk_mount == "null" then null else $disk_mount end)
      },
      "network": {
        "external_ip": (if $external_ip == "null" then null else $external_ip end),
        "local_ips": $local_ips
      },
      "reboot_required": (if $reboot_required == "true" then true elif $reboot_required == "false" then false else null end)
    }'
    return 0
  else
    # Human-readable format
    echo ""
    echo "==================================================================="
    echo "                    SYSTEM INFORMATION"
    echo "==================================================================="
    echo ""

    # Uptime
    if [[ -n "$uptime_info" ]]; then
      echo "Uptime: $uptime_info"
    fi

    # Load
    if [[ -n "$load_info" ]]; then
      echo "Load average: $load_info"
    fi

    # Memory
    if [[ -n "$mem_info" ]]; then
      echo ""
      echo "Memory:"
      echo "$mem_info"
    fi

    # Disk
    if [[ -n "$disk_info" ]]; then
      echo ""
      echo "Disk usage (root filesystem):"
      echo "$disk_info"
    fi

    # External IP
    echo ""
    if [[ -n "$external_ip" ]]; then
      echo "External IP: $external_ip"
    else
      echo "External IP: Unable to retrieve"
    fi

    # Local IPs
    if [[ -n "$local_ips" ]]; then
      echo "Local IP(s):"
      echo "$local_ips" | while read -r ip; do
        echo "  $ip"
      done
    fi

    # Reboot required
    echo ""
    if [[ "$reboot_required" == "true" ]]; then
      echo "Reboot required: YES"
    else
      echo "Reboot required: NO"
    fi

    echo ""
    echo "==================================================================="
    echo ""

    return 0
  fi
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
  else
    case "$command" in
      shutdown)
        show_usage_shutdown
        ;;
      restart)
        show_usage_restart
        ;;
      info)
        show_usage_info
        ;;
      *)
        __print_error "Unknown command: $command"
        __print_error "Use '$self help' for available commands"
        return $EC_INVALID_ARG
        ;;
    esac
  fi
  return 0
}

function show_usage_setup_cgroups() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Set up KGSM cgroup delegation (LEGACY)${END}

LEGACY / not needed under systemd: kgsm-watchdog now obtains its cgroup base via
systemd cgroup delegation (Slice=kgsm.slice, Delegate=yes) and manages the subtree
below its own service cgroup. Running this on a systemd host creates a manual
kgsm.slice that systemd then fights. Use it only on non-systemd hosts or for
diagnostics.

Creates KGSM's delegated cgroup v2 base and hands its ownership to a user, so
game-server instances can be supervised (crash detection, whole-tree teardown,
accurate metrics) without systemd. Run once, with privilege.

${UNDERLINE}Usage:${END}
  $self setup-cgroups [options]

${UNDERLINE}Options:${END}
  --user <name>               Delegate the base to this user
                              (default: the invoking user)
  -h, --help                  Show this help and exit

${UNDERLINE}Notes:${END}
  • Requires root (e.g. sudo): it enables cgroup controllers and changes
    ownership of the delegated base.
  • Requires a cgroup v2 host with kernel >= 5.14.
  • Idempotent: safe to run more than once."
}

function _cmd_setup_cgroups() {
  local target_user=""

  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_setup_cgroups
        return 0
        ;;
      --user)
        shift
        if [[ -z "${1:-}" ]]; then
          __print_error "--user requires a username"
          return $EC_INVALID_ARG
        fi
        target_user="$1"
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  __print_info "Setting up KGSM cgroup delegation base..."

  __logic_setup_cgroups "$target_user"
  local exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      __print_success "cgroup base ready: $(__cgroup_base)"
      __print_info "Delegated to user: ${target_user:-${SUDO_USER:-$USER}}"
      ;;
    $EC_CGROUP_UNSUPPORTED)
      __print_error "cgroup v2 is not mounted at ${config_cgroup_mount_point:-/sys/fs/cgroup}"
      __print_error "This host does not support cgroup v2 supervision"
      ;;
    $EC_PERMISSION)
      __print_error "Permission denied while enabling cgroup controllers"
      __print_error "Run with privilege, e.g.: sudo $self setup-cgroups"
      ;;
    *)
      __print_error "Failed to set up the cgroup base"
      ;;
  esac

  return $exit_code
}

# Parse command
command="${1:-}"
shift 2> /dev/null || true

# Command routing
case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  -h | --help | help)
    _cmd_help "$@"
    exit $?
    ;;
  shutdown)
    _cmd_shutdown "$@"
    exit $?
    ;;
  restart)
    _cmd_restart "$@"
    exit $?
    ;;
  cancel)
    _cmd_cancel "$@"
    exit $?
    ;;
  uptime)
    _cmd_uptime "$@"
    exit $?
    ;;
  load)
    _cmd_load "$@"
    exit $?
    ;;
  memory)
    _cmd_memory "$@"
    exit $?
    ;;
  disk)
    _cmd_disk "$@"
    exit $?
    ;;
  reboot-required)
    _cmd_reboot_required "$@"
    exit $?
    ;;
  info)
    _cmd_info "$@"
    exit $?
    ;;
  setup-cgroups)
    _cmd_setup_cgroups "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$self --help' for usage information"
    exit $EC_INVALID_ARG
    ;;
esac
