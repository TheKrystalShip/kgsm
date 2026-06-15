#!/usr/bin/env bash

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load UFW firewall logic library
logic_library=$(__find_command_handler files.ufw.sh)
# shellcheck source=handlers/files.ufw.sh
source "$logic_library" || {
  __print_error "Failed to load files.ufw logic library"
  exit $EC_FAILED_SOURCE
}

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}UFW Firewall Integration for Krystal Game Server Manager${END}

Enable and disable UFW firewall integration for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> <instance>

${UNDERLINE}Commands:${END}
  enable <instance>           Enable UFW firewall rules for the instance
  disable <instance>          Disable UFW firewall rules for the instance
  help [command]              Display help for a specific command

${UNDERLINE}Arguments:${END}
  <instance>                  Instance name (without .ini extension)

${UNDERLINE}Examples:${END}
  ${self} enable factorio-space-age
  ${self} disable factorio-space-age
  ${self} help enable

${UNDERLINE}Notes:${END}
  • UFW integration is optional for game server instances
  • Enable creates UFW rule file and enables the rule for instance ports
  • Disable removes UFW rules and deletes the rule file
  • Requires root/sudo permissions for UFW operations
  • All operations require a valid instance configuration
"
}

function show_usage_enable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Enable UFW Firewall Integration${END}

Creates UFW firewall rules for the instance's network ports.

${UNDERLINE}Usage:${END}
  ${self} enable <instance>

${UNDERLINE}Description:${END}
  Enables UFW firewall integration for the specified instance by creating
  a UFW application rule file and allowing traffic through the firewall.
  This ensures proper network connectivity for the game server.

  The instance configuration is updated to reflect that firewall
  management is enabled.

${UNDERLINE}Examples:${END}
  ${self} enable factorio-server
  ${self} enable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Root/sudo permissions
  • UFW installed and enabled
  • Valid instance configuration with port information
"
}

function show_usage_disable() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Disable UFW Firewall Integration${END}

Removes UFW firewall rules for the instance.

${UNDERLINE}Usage:${END}
  ${self} disable <instance>

${UNDERLINE}Description:${END}
  Disables UFW firewall integration for the specified instance by
  removing the UFW rule and deleting the application rule file.
  The instance configuration is updated to reflect that firewall
  management is disabled.

${UNDERLINE}Examples:${END}
  ${self} disable factorio-server
  ${self} disable minecraft-modded

${UNDERLINE}Requirements:${END}
  • Root/sudo permissions
  • UFW installed and enabled
"
}

# Command: enable
function _cmd_enable() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_enable
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_enable
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        ;;
    esac
  done

  # Validate instance name provided
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    show_usage_enable
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Enabling UFW firewall integration for instance '$instance_name'..."

  # Call logic function
  __logic_enable_ufw_integration "$instance_config_file"
  local exit_code=$?

  # Handle result
  case $exit_code in
    $EC_SUCCESS_UFW_ENABLED)
      __print_success "Firewall integration enabled successfully"
      __print_info "Ports opened via the kgsm-firewall authority"
      # Audit event: record which ports were opened. The payload carries them as
      # the canonical structured array; an instance with no ports opens nothing,
      # so no event is emitted.
      local _ports
      _ports=$(__get_config_value "$instance_config_file" "ports" 2> /dev/null)
      if [[ -n "$_ports" ]]; then
        events.sh emit instance-ports-opened "$instance_name" "$_ports"
      fi
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration - missing required fields"
      return $exit_code
      ;;
    $EC_FIREWALL_UNREACHABLE)
      # Hard-fail (B): a firewall-enabled install must NOT silently proceed when
      # the authority is down — be explicit and self-explanatory.
      __print_error "kgsm-firewall authority not reachable — cannot open ports for '$instance_name'"
      __print_error "The authority at $(__firewall_socket_path) is down or not installed"
      __print_error "Start/install kgsm-firewall (or disable firewall management) and retry"
      return $exit_code
      ;;
    $EC_UFW)
      __print_error "The firewall backend could not apply the rules for '$instance_name'"
      return $exit_code
      ;;
    $EC_ERROR)
      __print_error "Invalid port definition in instance configuration"
      return $exit_code
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to enable firewall integration (exit code: $exit_code)"
      return $exit_code
      ;;
  esac
}

# Command: disable
function _cmd_disable() {
  local instance_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_disable
        return 0
        ;;
      -*)
        __print_error "Unknown option: $1"
        show_usage_disable
        return $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        shift
        ;;
    esac
  done

  # Validate instance name provided
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    echo ""
    show_usage_disable
    return $EC_MISSING_ARG
  fi

  # Find instance config file
  local instance_config_file
  instance_config_file=$(__find_instance_config "$instance_name" 2> /dev/null)

  if [[ ! -f "$instance_config_file" ]]; then
    __print_error "Instance '$instance_name' not found"
    return $EC_INVALID_INSTANCE
  fi

  __print_info "Disabling UFW firewall integration for instance '$instance_name'..."

  # Call logic function
  __logic_disable_ufw_integration "$instance_config_file"
  local exit_code=$?

  # Handle result. Disable is best-effort: a down authority or backend error
  # warns but does NOT fail (it must never wedge uninstall) — and only a
  # confirmed removal emits the close event (never fabricate a closed port).
  case $exit_code in
    $EC_SUCCESS_UFW_DISABLED)
      __print_success "Firewall integration disabled successfully"
      __print_info "Ports closed via the kgsm-firewall authority"
      local _ports
      _ports=$(__get_config_value "$instance_config_file" "ports" 2> /dev/null)
      if [[ -n "$_ports" ]]; then
        events.sh emit instance-ports-closed "$instance_name" "$_ports"
      fi
      return 0
      ;;
    $EC_INVALID_CONFIG)
      __print_error "Invalid instance configuration"
      return $exit_code
      ;;
    $EC_FIREWALL_UNREACHABLE)
      __print_warning "kgsm-firewall authority not reachable — host rules for '$instance_name' were left in place"
      __print_info "Instance marked firewall-disabled; remove the rule manually if needed"
      return 0
      ;;
    $EC_UFW)
      __print_warning "The firewall backend could not remove the rules for '$instance_name'"
      __print_info "Instance marked firewall-disabled; remove the rule manually if needed"
      return 0
      ;;
    $EC_FAILED_UPDATE_CONFIG)
      __print_error "Failed to update instance configuration"
      return $exit_code
      ;;
    *)
      __print_error "Failed to disable firewall integration (exit code: $exit_code)"
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
    enable)
      show_usage_enable
      ;;
    disable)
      show_usage_disable
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
  enable)
    _cmd_enable "$@"
    exit $?
    ;;
  disable)
    _cmd_disable "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    echo ""
    show_usage
    exit $EC_INVALID_ARG
    ;;
esac
