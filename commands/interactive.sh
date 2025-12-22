#!/usr/bin/env bash

# KGSM Interactive Mode CLI Orchestrator
#
# This module provides a terminal user interface (TUI) for managing game servers
# through an intuitive menu-driven interface. It follows the standard KGSM module
# pattern with command-based entry points and separation of UI/logic concerns.
#
# Architecture:
# - UI rendering: core/ui.sh (reusable primitives)
# - Business logic: commands/handlers/wizards.sh (installation, modification workflows)
# - Menu navigation: commands/handlers/menus.sh (hierarchical menu system)
# - This module: Orchestration and user interaction

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Disabling SC2329 globally:
# Functions in this script are called dynamically by name through callbacks.
# shellcheck disable=SC2329

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Load required libraries
ui_library=$(__find_core_module ui.sh)
# shellcheck disable=SC1090
source "$ui_library" || {
  __print_error "Failed to load UI library"
  exit $EC_FAILED_SOURCE
}

wizards_logic=$(__find_command_handler wizards.sh)
# shellcheck disable=SC1090
source "$wizards_logic" || {
  __print_error "Failed to load wizards logic library"
  exit $EC_FAILED_SOURCE
}

menus_logic=$(__find_command_handler menus.sh)
# shellcheck disable=SC1090
source "$menus_logic" || {
  __print_error "Failed to load menus logic library"
  exit $EC_FAILED_SOURCE
}

# =============================================================================
# HELP / USAGE FUNCTIONS
# =============================================================================

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Interactive Mode for Krystal Game Server Manager${END}

Provides a user-friendly menu-driven interface for managing game servers.

${UNDERLINE}Usage:${END}
  ${self} <command> [options]

${UNDERLINE}Commands:${END}
  launch                          Launch the interactive menu interface
  wizard install                  Run installation wizard
  wizard configure                Run configuration wizard
  wizard modify                   Run modification wizard
  help [command]                  Display help information

${UNDERLINE}Global Options:${END}
  -h, --help                      Display this help information
  --debug                         Enable debug output

${UNDERLINE}Examples:${END}
  ${self} launch
  ${self} wizard install
  ${self} help launch

For detailed help on a specific command, use:
  ${self} help <command>
"
}

function usage_launch() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Launch Command${END}

Start the interactive menu-driven interface for managing game servers.

${UNDERLINE}Usage:${END}
  ${self} launch

${UNDERLINE}Description:${END}
  Launches a full-screen terminal interface with hierarchical menus that
  mirror the CLI command structure. The interface provides:

  Built-in Commands:
  - Install/Uninstall servers
  - Update KGSM

  Module Commands (10 modules):
  - Blueprints - Manage server blueprints
  - Config - Manage KGSM configuration
  - Directories - Manage directory structures
  - Events - Manage event system
  - Files - Manage instance files (systemd, ufw, symlinks)
  - Instances - Manage server instances
  - Lifecycle - Control server lifecycle (start, stop, restart, logs)
  - Network - Manage network and ports
  - System - Manage system operations
  - Watcher - Monitor logs and ports

${UNDERLINE}Navigation:${END}
  Use numbers to select menu options
  Use 'b' to go back, 'm' for main menu, 'q' to quit
  Use 'h' for help when available
  Press Ctrl+C to exit at any time

${UNDERLINE}CLI Equivalents:${END}
  Each menu displays the equivalent CLI command, making it easy to
  learn the command-line interface while using the interactive mode.

${UNDERLINE}Examples:${END}
  ${self} launch
"
}

function usage_wizard() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Wizard Commands${END}

Run interactive wizards for specific tasks without the full menu interface.

${UNDERLINE}Usage:${END}
  ${self} wizard <type>

${UNDERLINE}Wizard Types:${END}
  install                         Installation wizard for new servers
  configure                       Configuration wizard for existing servers
  modify                          Modification wizard for server integrations

${UNDERLINE}Examples:${END}
  ${self} wizard install
  ${self} wizard modify
"
}

# =============================================================================
# SYSTEM INFORMATION DISPLAY
# =============================================================================

function __display_system_status() {
  local overview_data
  local instances_count=0
  local blueprints_count=0

  overview_data=$(__logic_get_system_overview)
  instances_count=$(echo "$overview_data" | grep "instances:" | cut -d: -f2)
  blueprints_count=$(echo "$overview_data" | grep "blueprints:" | cut -d: -f2)

  __ui_draw_box "KGSM System Overview"
  __ui_print_box_line "Version: $(__logic_get_kgsm_version)"
  __ui_print_box_line "Instances: $instances_count installed"
  __ui_print_box_line "Blueprints: $blueprints_count available"
  __ui_print_empty_line

  # Show running instances if any exist
  if [[ $instances_count -gt 0 ]]; then
    __ui_print_box_line "Recent Instance Activity:" "$UI_COLOR_WARNING"
    local instances
    mapfile -t instances < <(__logic_get_instances 2>/dev/null | head -3)
    if [[ ${#instances[@]} -gt 0 ]]; then
      for instance in "${instances[@]}"; do
        [[ -n "$instance" ]] && __ui_print_box_line "  • $instance"
      done
      [[ $instances_count -gt 3 ]] && __ui_print_box_line "  ... and $((instances_count - 3)) more"
    fi
  else
    __ui_print_box_line "No instances installed yet" "$UI_COLOR_WARNING"
    __ui_print_box_line "Use 'Install Server' to get started"
  fi

  __ui_print_empty_line
  __ui_close_box
}

# =============================================================================
# MENU DISPLAY FUNCTIONS
# =============================================================================

function __show_main_menu() {
  __ui_clear_screen
  __display_system_status
  echo

  __ui_draw_box "Main Menu"
  __ui_print_box_line "Built-in commands:" "$UI_COLOR_INFO"
  __ui_print_menu_item "01" "Update KGSM" "Update KGSM to latest version"
  __ui_print_menu_item "02" "Check for Update" "Check if KGSM updates available"
  __ui_print_empty_line
  __ui_print_box_line "Module commands:" "$UI_COLOR_INFO"
  __ui_print_menu_item "03" "Install Server" "Install a new game server instance"
  __ui_print_menu_item "04" "Uninstall Server" "Remove a game server instance"
  __ui_print_menu_item "05" "Blueprints" "Manage server blueprints"
  __ui_print_menu_item "06" "Config" "Manage KGSM configuration"
  __ui_print_menu_item "07" "Directories" "Manage directory structures"
  __ui_print_menu_item "08" "Events" "Manage event system"
  __ui_print_menu_item "09" "Files" "Manage instance files"
  __ui_print_menu_item "10" "Instances" "Manage server instances"
  __ui_print_menu_item "11" "Lifecycle" "Control server lifecycle"
  __ui_print_menu_item "12" "Network" "Manage network and ports"
  __ui_print_menu_item "13" "System" "Manage system operations"
  __ui_print_menu_item "14" "Watcher" "Manage monitoring watchers"
  __ui_print_empty_line
  __ui_print_menu_item "h" "$UI_MENU_HELP" "Show detailed help information"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM Interactive Mode"
  __ui_close_box
}

function __show_builtin_commands_menu() {
  __ui_clear_screen
  __ui_draw_box "Built-in Commands"
  __ui_print_box_line "Equivalent to: kgsm.sh <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "Install Server" "Install a new game server instance"
  __ui_print_menu_item "2" "Uninstall Server" "Remove a game server instance"
  __ui_print_menu_item "3" "Update KGSM" "Update KGSM to latest version"
  __ui_print_menu_item "4" "Check for Update" "Check if KGSM updates available"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_blueprints_menu() {
  __ui_clear_screen
  __ui_draw_box "Blueprints Module"
  __ui_print_box_line "Equivalent to: kgsm.sh blueprints <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "List Blueprints" "Show all available blueprints"
  __ui_print_menu_item "2" "Blueprint Info" "Show detailed blueprint information"
  __ui_print_menu_item "3" "Find Blueprint" "Search for a specific blueprint"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_config_menu() {
  __ui_clear_screen
  __ui_draw_box "Config Module"
  __ui_print_box_line "Equivalent to: kgsm.sh config <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "List Config" "Show all configuration values"
  __ui_print_menu_item "2" "Get Value" "Get a specific config value"
  __ui_print_menu_item "3" "Set Value" "Set a configuration value"
  __ui_print_menu_item "4" "Validate Config" "Check configuration validity"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_instances_menu() {
  __ui_clear_screen
  __ui_draw_box "Instances Module"
  __ui_print_box_line "Equivalent to: kgsm.sh instances <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "List Instances" "Show all server instances"
  __ui_print_menu_item "2" "Instance Info" "Show detailed instance information"
  __ui_print_menu_item "3" "Instance Status" "Check runtime status"
  __ui_print_menu_item "4" "Find Instance" "Get instance config file path"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_lifecycle_menu() {
  __ui_clear_screen
  __ui_draw_box "Lifecycle Module"
  __ui_print_box_line "Equivalent to: kgsm.sh lifecycle <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "Start Server" "Launch a server instance"
  __ui_print_menu_item "2" "Stop Server" "Stop a running server"
  __ui_print_menu_item "3" "Restart Server" "Restart a server instance"
  __ui_print_menu_item "4" "View Logs" "Show server logs"
  __ui_print_menu_item "5" "Status" "Check server status"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_network_menu() {
  __ui_clear_screen
  __ui_draw_box "Network Module"
  __ui_print_box_line "Equivalent to: kgsm.sh network <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "Show IP Address" "Display network IP address"
  __ui_print_menu_item "2" "Check Port" "Check if a port is in use"
  __ui_print_menu_item "3" "Port Conflicts" "Show all port conflicts"
  __ui_print_menu_item "4" "Test Port" "Test port connectivity"
  __ui_print_menu_item "5" "Test All Ports" "Test all instance ports"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_system_menu() {
  __ui_clear_screen
  __ui_draw_box "System Module"
  __ui_print_box_line "Equivalent to: kgsm.sh system <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "System Info" "Display system information"
  __ui_print_menu_item "2" "Uptime" "Show system uptime"
  __ui_print_menu_item "3" "Schedule Shutdown" "Schedule system shutdown"
  __ui_print_menu_item "4" "Schedule Restart" "Schedule system restart"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_files_menu() {
  __ui_clear_screen
  __ui_draw_box "Files Module"
  __ui_print_box_line "Equivalent to: kgsm.sh files <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "Create Systemd Service" "Generate systemd service file"
  __ui_print_menu_item "2" "Create UFW Rules" "Generate UFW firewall rules"
  __ui_print_menu_item "3" "Create Symlinks" "Create command shortcuts"
  __ui_print_menu_item "4" "Remove Files" "Remove generated files"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_directories_menu() {
  __ui_clear_screen
  __ui_draw_box "Directories Module"
  __ui_print_box_line "Equivalent to: kgsm.sh directories <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "Create Directories" "Create instance directory structure"
  __ui_print_menu_item "2" "Remove Directories" "Remove instance directories"
  __ui_print_menu_item "3" "List Directories" "Show instance directory tree"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_events_menu() {
  __ui_clear_screen
  __ui_draw_box "Events Module"
  __ui_print_box_line "Equivalent to: kgsm.sh events <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "Event Status" "Show event system status"
  __ui_print_menu_item "2" "Test All Events" "Test all event handlers"
  __ui_print_menu_item "3" "Configure Webhook" "Configure webhook settings"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_watcher_menu() {
  __ui_clear_screen
  __ui_draw_box "Watcher Module"
  __ui_print_box_line "Equivalent to: kgsm.sh watcher <command>" "$UI_COLOR_INFO"
  __ui_print_empty_line
  __ui_print_menu_item "1" "Watch Logs" "Monitor server logs in real-time"
  __ui_print_menu_item "2" "Watch Ports" "Monitor port status"
  __ui_print_menu_item "3" "Stop Watchers" "Stop all running watchers"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to modules menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_server_management_menu() {
  __ui_clear_screen
  __ui_draw_box "Server Management"
  __ui_print_menu_item "1" "Install New Server" "Deploy a game server from blueprint"
  __ui_print_menu_item "2" "Start Server" "Launch an installed server instance"
  __ui_print_menu_item "3" "Stop Server" "Gracefully shutdown a running server"
  __ui_print_menu_item "4" "Restart Server" "Stop and start a server instance"
  __ui_print_menu_item "5" "Uninstall Server" "Remove a server instance completely"
  __ui_print_menu_item "6" "Modify Server" "Change server integrations"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to main menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_information_menu() {
  __ui_clear_screen
  __ui_draw_box "Information & Monitoring"
  __ui_print_menu_item "1" "List All Blueprints" "Show available server types"
  __ui_print_menu_item "2" "List All Instances" "Show installed server instances"
  __ui_print_menu_item "3" "Server Status" "Detailed status of an instance"
  __ui_print_menu_item "4" "View Server Logs" "Show recent log entries"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to main menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_maintenance_menu() {
  __ui_clear_screen
  __ui_draw_box "Maintenance & Updates"
  __ui_print_menu_item "1" "Check for Updates" "Check if server updates available"
  __ui_print_menu_item "2" "Update Server" "Update a server to latest version"
  __ui_print_menu_item "3" "Create Backup" "Backup server data and config"
  __ui_print_menu_item "4" "Restore Backup" "Restore from a previous backup"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to main menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_system_tools_menu() {
  __ui_clear_screen
  __ui_draw_box "System Tools & Configuration"
  __ui_print_menu_item "1" "View Configuration" "Show current KGSM settings"
  __ui_print_menu_item "2" "System Information" "Display system details"
  __ui_print_menu_item "3" "Update KGSM" "Update KGSM itself"
  __ui_print_empty_line
  __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to main menu"
  __ui_print_menu_item "m" "$UI_MENU_MAIN" "Jump to main menu"
  __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
  __ui_close_box
}

function __show_detailed_help() {
  __ui_clear_screen
  __ui_draw_box "KGSM Interactive Mode - Help"
  __ui_print_box_line "Navigation:"
  __ui_print_box_line "  • Use numbers to select menu options"
  __ui_print_box_line "  • Use 'b' to go back to previous menu"
  __ui_print_box_line "  • Use 'm' to jump to main menu"
  __ui_print_box_line "  • Use 'q' to quit KGSM"
  __ui_print_box_line "  • Use 'h' for help (where available)"
  __ui_print_empty_line
  __ui_print_box_line "Menu Structure:"
  __ui_print_box_line "  The interactive mode mirrors the CLI structure:"
  __ui_print_box_line "  • Built-in Commands - install, uninstall, update"
  __ui_print_box_line "  • Module Commands - access all 10 KGSM modules"
  __ui_print_empty_line
  __ui_print_box_line "Available Modules:"
  __ui_print_box_line "  • Blueprints - Manage server blueprints"
  __ui_print_box_line "  • Config - Manage KGSM configuration"
  __ui_print_box_line "  • Directories - Manage directory structures"
  __ui_print_box_line "  • Events - Manage event system"
  __ui_print_box_line "  • Files - Manage instance files"
  __ui_print_box_line "  • Instances - Manage server instances"
  __ui_print_box_line "  • Lifecycle - Control server lifecycle"
  __ui_print_box_line "  • Network - Manage network and ports"
  __ui_print_box_line "  • System - Manage system operations"
  __ui_print_box_line "  • Watcher - Manage monitoring watchers"
  __ui_print_empty_line
  __ui_print_box_line "CLI Equivalents:"
  __ui_print_box_line "  Each menu shows the equivalent CLI command"
  __ui_print_box_line "  Use this to learn the command-line interface"
  __ui_print_empty_line
  __ui_print_box_line "For more information, visit:"
  __ui_print_box_line "  https://github.com/TheKrystalShip/KGSM"
  __ui_close_box
  __ui_wait_for_key
}

# =============================================================================
# WIZARD ACTION FUNCTIONS
# =============================================================================

function __wizard_install_server() {
  local blueprints
  local selected_blueprint
  local install_dir
  local version
  local instance_name

  # Get available blueprints
  mapfile -t blueprints < <(__logic_get_blueprints 2>/dev/null)

  if [[ ${#blueprints[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_ERROR}No blueprints available.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  # Select blueprint
  selected_blueprint=$(__ui_select_from_list "Select Blueprint to Install" blueprints)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  # Get installation directory
  install_dir=${config_default_install_directory:-}
  if [[ -z "$install_dir" ]]; then
    install_dir=$(__ui_prompt_user "Installation directory:")
    if [[ -z "$install_dir" ]]; then
      echo -e "${UI_COLOR_ERROR}Installation directory is required.${UI_COLOR_RESET}" >&2
      __ui_wait_for_key
      return 1
    fi
  else
    install_dir=$(__ui_prompt_user "Installation directory:" "$install_dir")
  fi

  # Get version (optional)
  version=$(__ui_prompt_user "Version (leave empty for latest):")

  # Get instance name (optional)
  instance_name=$(__ui_prompt_user "Instance name (leave empty for default):")

  # Confirm installation
  __ui_clear_screen
  __ui_draw_box "Installation Summary"
  __ui_print_box_line "Blueprint: $selected_blueprint"
  __ui_print_box_line "Directory: $install_dir"
  __ui_print_box_line "Version: ${version:-latest}"
  __ui_print_box_line "Name: ${instance_name:-default}"
  __ui_close_box

  if ! __ui_confirm_action "Proceed with installation?"; then
    echo -e "${UI_COLOR_INFO}Installation cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  # Execute installation via wizard logic
  echo -e "${UI_COLOR_INFO}Installing server instance...${UI_COLOR_RESET}" >&2

  local exit_code
  __logic_wizard_install "$selected_blueprint" "$install_dir" "$version" "$instance_name"
  exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${UI_COLOR_SUCCESS}Installation completed successfully!${UI_COLOR_RESET}" >&2
  else
    echo -e "${UI_COLOR_ERROR}Installation failed with exit code $exit_code.${UI_COLOR_RESET}" >&2
  fi

  __ui_wait_for_key
  return 0
}

function __wizard_lifecycle_operation() {
  local operation="$1"
  local operation_name="$2"
  local instances
  local selected_instance

  # Get available instances
  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    echo -e "${UI_COLOR_INFO}Install a server first using the 'Install New Server' option.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  # Select instance
  selected_instance=$(__ui_select_from_list "Select Instance to $operation_name" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  # Confirm operation for destructive actions
  if [[ "$operation" == "uninstall" ]]; then
    if ! __ui_confirm_action "This will permanently remove '$selected_instance' and all its data."; then
      echo -e "${UI_COLOR_INFO}Operation cancelled.${UI_COLOR_RESET}" >&2
      __ui_wait_for_key
      return 0
    fi
  fi

  # Execute operation via wizard logic
  echo -e "${UI_COLOR_INFO}${operation_name^} server instance...${UI_COLOR_RESET}" >&2

  local exit_code
  case "$operation" in
    start)
      __logic_wizard_start_instance "$selected_instance"
      exit_code=$?
      ;;
    stop)
      __logic_wizard_stop_instance "$selected_instance"
      exit_code=$?
      ;;
    restart)
      __logic_wizard_restart_instance "$selected_instance"
      exit_code=$?
      ;;
    status)
      __logic_wizard_instance_status "$selected_instance" "" "true"
      exit_code=$?
      ;;
    logs)
      __logic_wizard_instance_logs "$selected_instance" "false" "50"
      exit_code=$?
      ;;
    check-update)
      __logic_wizard_check_update "$selected_instance"
      exit_code=$?
      ;;
    update)
      __logic_wizard_update_instance "$selected_instance"
      exit_code=$?
      ;;
    create-backup)
      __logic_wizard_create_backup "$selected_instance"
      exit_code=$?
      ;;
    uninstall)
      __logic_wizard_uninstall_instance "$selected_instance"
      exit_code=$?
      ;;
    *)
      echo -e "${UI_COLOR_ERROR}Unknown operation: $operation${UI_COLOR_RESET}" >&2
      __ui_wait_for_key
      return 1
      ;;
  esac

  # Handle result
  if [[ $exit_code -eq 0 ]] || [[ $exit_code -ge 200 && $exit_code -lt 300 ]]; then
    echo -e "${UI_COLOR_SUCCESS}Operation completed successfully!${UI_COLOR_RESET}" >&2
  else
    echo -e "${UI_COLOR_ERROR}Operation failed with exit code $exit_code.${UI_COLOR_RESET}" >&2
  fi

  __ui_wait_for_key
  return 0
}

function __wizard_modify_server() {
  local instances
  local selected_instance

  # Get available instances
  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  # Select instance
  selected_instance=$(__ui_select_from_list "Select Instance to Modify" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  # Get modification options from logic layer
  local modify_data
  mapfile -t modify_data < <(__logic_get_modify_options "$selected_instance" 2>/dev/null)

  if [[ ${#modify_data[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_ERROR}Failed to load modification options.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  # Parse options and commands
  local modify_options=()
  local modify_commands=()
  for line in "${modify_data[@]}"; do
    modify_options+=("${line%%|*}")
    modify_commands+=("${line##*|}")
  done

  # Select modification
  local selected_option
  selected_option=$(__ui_select_from_list "Select Modification for $selected_instance" modify_options)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  # Find the corresponding command
  local selected_command=""
  local i=0
  for option in "${modify_options[@]}"; do
    if [[ "$option" == "$selected_option" ]]; then
      selected_command="${modify_commands[$i]}"
      break
    fi
    ((i++))
  done

  if [[ -z "$selected_command" ]]; then
    echo -e "${UI_COLOR_ERROR}Internal error: Could not find command for selected option.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  # Execute modification via wizard logic
  echo -e "${UI_COLOR_INFO}Modifying server instance...${UI_COLOR_RESET}" >&2

  local exit_code
  __logic_wizard_modify "$selected_instance" "$selected_command"
  exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${UI_COLOR_SUCCESS}Modification completed successfully!${UI_COLOR_RESET}" >&2
  else
    echo -e "${UI_COLOR_ERROR}Modification failed with exit code $exit_code.${UI_COLOR_RESET}" >&2
  fi

  __ui_wait_for_key
  return 0
}

function __wizard_list_items() {
  local list_type="$1"
  local title="$2"

  __ui_clear_screen
  __ui_draw_box "$title"
  __ui_print_empty_line

  if [[ "$list_type" == "blueprints" ]]; then
    __logic_get_blueprints
  else
    __logic_get_instances
  fi

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
}

function __wizard_restore_backup() {
  local instances
  local selected_instance
  local backups
  local selected_backup

  # Get available instances
  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  # Select instance
  selected_instance=$(__ui_select_from_list "Select Instance to Restore" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  # Get available backups
  mapfile -t backups < <(__logic_get_instance_backups "$selected_instance" 2>/dev/null)

  if [[ ${#backups[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No backups found for instance '$selected_instance'.${UI_COLOR_RESET}" >&2
    echo -e "${UI_COLOR_INFO}Create a backup first using the 'Create Backup' option.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  # Select backup
  selected_backup=$(__ui_select_from_list "Select Backup to Restore" backups)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  # Confirm restoration
  if ! __ui_confirm_action "This will overwrite current data for '$selected_instance' with backup '$selected_backup'."; then
    echo -e "${UI_COLOR_INFO}Restore cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  # Execute restoration via wizard logic
  echo -e "${UI_COLOR_INFO}Restoring backup...${UI_COLOR_RESET}" >&2

  local exit_code
  __logic_wizard_restore_backup "$selected_instance" "$selected_backup"
  exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${UI_COLOR_SUCCESS}Backup restored successfully!${UI_COLOR_RESET}" >&2
  else
    echo -e "${UI_COLOR_ERROR}Backup restoration failed with exit code $exit_code.${UI_COLOR_RESET}" >&2
  fi

  __ui_wait_for_key
  return 0
}

# =============================================================================
# MODULE ACTION FUNCTIONS
# =============================================================================

# Built-in command actions

function __action_update_kgsm() {
  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Checking for KGSM updates...${UI_COLOR_RESET}" >&2
  "$KGSM_ROOT/kgsm.sh" --update
  __ui_wait_for_key
  return 0
}

function __action_check_kgsm_update() {
  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Checking for KGSM updates...${UI_COLOR_RESET}" >&2
  "$KGSM_ROOT/kgsm.sh" --check-update
  __ui_wait_for_key
  return 0
}

# Blueprints module actions

function __action_list_blueprints() {
  __ui_clear_screen
  __ui_draw_box "Available Blueprints"
  __ui_print_empty_line
  __logic_get_blueprints
  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_blueprint_info() {
  local blueprints
  local selected_blueprint

  mapfile -t blueprints < <(__logic_get_blueprints 2>/dev/null)

  if [[ ${#blueprints[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_ERROR}No blueprints available.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_blueprint=$(__ui_select_from_list "Select Blueprint for Info" blueprints)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  __ui_draw_box "Blueprint Info: $selected_blueprint"
  __ui_print_empty_line

  # Get blueprint module
  local blueprints_module
  blueprints_module=$(__find_command blueprints.sh)
  "$blueprints_module" info "$selected_blueprint"

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_find_blueprint() {
  local blueprint_name
  blueprint_name=$(__ui_prompt_user "Blueprint name to find:")

  if [[ -z "$blueprint_name" ]]; then
    echo -e "${UI_COLOR_ERROR}Blueprint name is required.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  __ui_clear_screen
  __ui_draw_box "Finding Blueprint: $blueprint_name"
  __ui_print_empty_line

  local blueprints_module
  blueprints_module=$(__find_command blueprints.sh)
  "$blueprints_module" find "$blueprint_name"

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

# Config module actions

function __action_config_list() {
  __ui_clear_screen
  __ui_draw_box "KGSM Configuration"
  __ui_print_empty_line

  local config_module
  config_module=$(__find_command config.sh)
  "$config_module" list

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_config_get() {
  local key
  key=$(__ui_prompt_user "Config key to get:")

  if [[ -z "$key" ]]; then
    echo -e "${UI_COLOR_ERROR}Config key is required.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  __ui_clear_screen
  __ui_draw_box "Config Value: $key"
  __ui_print_empty_line

  local config_module
  config_module=$(__find_command config.sh)
  "$config_module" get "$key"

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_config_set() {
  local key
  local value

  key=$(__ui_prompt_user "Config key to set:")
  if [[ -z "$key" ]]; then
    echo -e "${UI_COLOR_ERROR}Config key is required.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  value=$(__ui_prompt_user "New value for $key:")
  if [[ -z "$value" ]]; then
    echo -e "${UI_COLOR_ERROR}Value is required.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  if ! __ui_confirm_action "Set $key=$value?"; then
    echo -e "${UI_COLOR_INFO}Operation cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Setting configuration...${UI_COLOR_RESET}" >&2

  local config_module
  config_module=$(__find_command config.sh)
  "$config_module" set "${key}=${value}"

  __ui_wait_for_key
  return 0
}

function __action_config_validate() {
  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Validating configuration...${UI_COLOR_RESET}" >&2

  local config_module
  config_module=$(__find_command config.sh)
  "$config_module" validate

  __ui_wait_for_key
  return 0
}

# Instances module actions

function __action_list_instances() {
  __ui_clear_screen
  __ui_draw_box "Installed Instances"
  __ui_print_empty_line
  __logic_get_instances
  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_instance_info() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance for Info" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  __ui_draw_box "Instance Info: $selected_instance"
  __ui_print_empty_line

  local instances_module
  instances_module=$(__find_command instances.sh)
  "$instances_module" info "$selected_instance"

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_find_instance() {
  local instance_name
  instance_name=$(__ui_prompt_user "Instance name to find:")

  if [[ -z "$instance_name" ]]; then
    echo -e "${UI_COLOR_ERROR}Instance name is required.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  __ui_clear_screen
  __ui_draw_box "Instance Config Path"
  __ui_print_empty_line

  local instances_module
  instances_module=$(__find_command instances.sh)
  "$instances_module" find "$instance_name"

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

# Network module actions

function __action_network_ip() {
  __ui_clear_screen
  __ui_draw_box "Network IP Address"
  __ui_print_empty_line

  local network_module
  network_module=$(__find_command network.sh)
  "$network_module" ip

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_network_check_port() {
  local port
  port=$(__ui_prompt_user "Port number to check:")

  if [[ -z "$port" ]]; then
    echo -e "${UI_COLOR_ERROR}Port number is required.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  __ui_clear_screen
  __ui_draw_box "Port Check: $port"
  __ui_print_empty_line

  local network_module
  network_module=$(__find_command network.sh)
  "$network_module" ports check "$port"

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_network_conflicts() {
  __ui_clear_screen
  __ui_draw_box "Port Conflicts"
  __ui_print_empty_line

  local network_module
  network_module=$(__find_command network.sh)
  "$network_module" ports conflicts

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_network_test_port() {
  local port
  port=$(__ui_prompt_user "Port number to test:")

  if [[ -z "$port" ]]; then
    echo -e "${UI_COLOR_ERROR}Port number is required.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Testing port $port...${UI_COLOR_RESET}" >&2

  local network_module
  network_module=$(__find_command network.sh)
  "$network_module" test-port "$port"

  __ui_wait_for_key
  return 0
}

function __action_network_test_all() {
  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Testing all instance ports...${UI_COLOR_RESET}" >&2

  local network_module
  network_module=$(__find_command network.sh)
  "$network_module" test-all

  __ui_wait_for_key
  return 0
}

# System module actions

function __action_system_info() {
  __ui_clear_screen
  __ui_draw_box "System Information"
  __ui_print_empty_line

  local system_module
  system_module=$(__find_command system.sh)
  "$system_module" info

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_system_uptime() {
  __ui_clear_screen
  __ui_draw_box "System Uptime"
  __ui_print_empty_line

  local system_module
  system_module=$(__find_command system.sh)
  "$system_module" uptime

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_system_shutdown() {
  local minutes
  minutes=$(__ui_prompt_user "Minutes until shutdown (default: 1):" "1")

  if ! __ui_confirm_action "Schedule system shutdown in $minutes minutes?"; then
    echo -e "${UI_COLOR_INFO}Operation cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  __ui_clear_screen
  echo -e "${UI_COLOR_WARNING}Scheduling system shutdown...${UI_COLOR_RESET}" >&2

  local system_module
  system_module=$(__find_command system.sh)
  "$system_module" shutdown "$minutes"

  __ui_wait_for_key
  return 0
}

function __action_system_restart() {
  local minutes
  minutes=$(__ui_prompt_user "Minutes until restart (default: 1):" "1")

  if ! __ui_confirm_action "Schedule system restart in $minutes minutes?"; then
    echo -e "${UI_COLOR_INFO}Operation cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  __ui_clear_screen
  echo -e "${UI_COLOR_WARNING}Scheduling system restart...${UI_COLOR_RESET}" >&2

  local system_module
  system_module=$(__find_command system.sh)
  "$system_module" restart "$minutes"

  __ui_wait_for_key
  return 0
}

# Files module actions

function __action_files_create_systemd() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Creating systemd service file...${UI_COLOR_RESET}" >&2

  local files_module
  files_module=$(__find_command files.sh)
  "$files_module" create systemd --instance "$selected_instance"

  __ui_wait_for_key
  return 0
}

function __action_files_create_ufw() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Creating UFW firewall rules...${UI_COLOR_RESET}" >&2

  local files_module
  files_module=$(__find_command files.sh)
  "$files_module" create ufw --instance "$selected_instance"

  __ui_wait_for_key
  return 0
}

function __action_files_create_symlinks() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Creating command symlinks...${UI_COLOR_RESET}" >&2

  local files_module
  files_module=$(__find_command files.sh)
  "$files_module" create symlink --instance "$selected_instance"

  __ui_wait_for_key
  return 0
}

function __action_files_remove() {
  local instances
  local selected_instance
  local file_types
  local selected_type

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  file_types=("systemd" "ufw" "symlink")
  selected_type=$(__ui_select_from_list "Select File Type to Remove" file_types)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  if ! __ui_confirm_action "Remove $selected_type files for $selected_instance?"; then
    echo -e "${UI_COLOR_INFO}Operation cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Removing files...${UI_COLOR_RESET}" >&2

  local files_module
  files_module=$(__find_command files.sh)
  "$files_module" remove "$selected_type" --instance "$selected_instance"

  __ui_wait_for_key
  return 0
}

# Directories module actions

function __action_directories_create() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Creating directory structure...${UI_COLOR_RESET}" >&2

  local directories_module
  directories_module=$(__find_command directories.sh)
  "$directories_module" create --instance "$selected_instance"

  __ui_wait_for_key
  return 0
}

function __action_directories_remove() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  if ! __ui_confirm_action "This will permanently remove all directories for '$selected_instance'."; then
    echo -e "${UI_COLOR_INFO}Operation cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  __ui_clear_screen
  echo -e "${UI_COLOR_WARNING}Removing directories...${UI_COLOR_RESET}" >&2

  local directories_module
  directories_module=$(__find_command directories.sh)
  "$directories_module" remove --instance "$selected_instance"

  __ui_wait_for_key
  return 0
}

function __action_directories_list() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  __ui_draw_box "Directory Structure: $selected_instance"
  __ui_print_empty_line

  local directories_module
  directories_module=$(__find_command directories.sh)
  "$directories_module" list --instance "$selected_instance"

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

# Events module actions

function __action_events_status() {
  __ui_clear_screen
  __ui_draw_box "Event System Status"
  __ui_print_empty_line

  local events_module
  events_module=$(__find_command events.sh)
  "$events_module" status

  __ui_print_empty_line
  __ui_close_box
  __ui_wait_for_key
  return 0
}

function __action_events_test_all() {
  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Testing all event handlers...${UI_COLOR_RESET}" >&2

  local events_module
  events_module=$(__find_command events.sh)
  "$events_module" test-all

  __ui_wait_for_key
  return 0
}

function __action_events_webhook_config() {
  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Configuring webhook...${UI_COLOR_RESET}" >&2

  local events_module
  events_module=$(__find_command events.sh)
  "$events_module" webhook configure

  __ui_wait_for_key
  return 0
}

# Watcher module actions

function __action_watcher_logs() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance to Watch" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Starting log watcher for $selected_instance...${UI_COLOR_RESET}" >&2
  echo -e "${UI_COLOR_INFO}Press Ctrl+C to stop watching.${UI_COLOR_RESET}" >&2
  echo

  local watcher_module
  watcher_module=$(__find_command watcher.sh)
  "$watcher_module" logs --instance "$selected_instance"

  return 0
}

function __action_watcher_ports() {
  local instances
  local selected_instance

  mapfile -t instances < <(__logic_get_instances 2>/dev/null)

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No server instances found.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  selected_instance=$(__ui_select_from_list "Select Instance to Watch" instances)
  case $? in
    1) return 0 ;; # Back
    2) return 2 ;; # Quit
  esac

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Starting port watcher for $selected_instance...${UI_COLOR_RESET}" >&2
  echo -e "${UI_COLOR_INFO}Press Ctrl+C to stop watching.${UI_COLOR_RESET}" >&2
  echo

  local watcher_module
  watcher_module=$(__find_command watcher.sh)
  "$watcher_module" ports --instance "$selected_instance"

  return 0
}

function __action_watcher_stop() {
  if ! __ui_confirm_action "Stop all running watchers?"; then
    echo -e "${UI_COLOR_INFO}Operation cancelled.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 0
  fi

  __ui_clear_screen
  echo -e "${UI_COLOR_INFO}Stopping watchers...${UI_COLOR_RESET}" >&2

  # Kill all watcher processes
  pkill -f "watcher.sh" 2>/dev/null || true

  echo -e "${UI_COLOR_SUCCESS}All watchers stopped.${UI_COLOR_RESET}" >&2
  __ui_wait_for_key
  return 0
}

# =============================================================================
# MENU HANDLER FUNCTIONS
# =============================================================================

# Choice handler for main menu
# shellcheck disable=SC2329
# This function is invoked as a callback
function __handle_main_menu_choice() {
  local choice="$1"

  case "$choice" in
    # Built-in commands
    1)
      __menu_execute_action "__action_update_kgsm"
      return $?
      ;;
    2)
      __menu_execute_action "__action_check_kgsm_update"
      return $?
      ;;
    # Module commands
    3)
      __menu_execute_action "__wizard_install_server"
      return $?
      ;;
    4)
      __menu_execute_action "__wizard_lifecycle_operation" "uninstall" "uninstall"
      return $?
      ;;
    5)
      __menu_invoke_submenu "__handle_blueprints_menu"
      return $?
      ;;
    6)
      __menu_invoke_submenu "__handle_config_menu"
      return $?
      ;;
    7)
      __menu_invoke_submenu "__handle_directories_menu"
      return $?
      ;;
    8)
      __menu_invoke_submenu "__handle_events_menu"
      return $?
      ;;
    9)
      __menu_invoke_submenu "__handle_files_menu"
      return $?
      ;;
    10)
      __menu_invoke_submenu "__handle_instances_menu"
      return $?
      ;;
    11)
      __menu_invoke_submenu "__handle_lifecycle_menu"
      return $?
      ;;
    12)
      __menu_invoke_submenu "__handle_network_menu"
      return $?
      ;;
    13)
      __menu_invoke_submenu "__handle_system_menu"
      return $?
      ;;
    14)
      __menu_invoke_submenu "__handle_watcher_menu"
      return $?
      ;;
    h)
      __show_detailed_help
      return $MENU_NAV_CONTINUE
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

function __handle_main_menu() {
  __menu_run_loop "__show_main_menu" "1 2 3 4 5 6 7 8 9 10 11 12 13 14 h q" "__handle_main_menu_choice"
}

# Choice handler for built-in commands menu
# shellcheck disable=SC2329
function __handle_builtin_commands_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__wizard_install_server"
      return $?
      ;;
    2)
      __menu_execute_action "__wizard_lifecycle_operation" "uninstall" "uninstall"
      return $?
      ;;
    3)
      __menu_execute_action "__action_update_kgsm"
      return $?
      ;;
    4)
      __menu_execute_action "__action_check_kgsm_update"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_builtin_commands_menu() {
  __menu_run_loop "__show_builtin_commands_menu" "1 2 3 4 b q" "__handle_builtin_commands_choice"
}

# Choice handler for modules menu
# shellcheck disable=SC2329
function __handle_modules_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_invoke_submenu "__handle_blueprints_menu"
      return $?
      ;;
    2)
      __menu_invoke_submenu "__handle_config_menu"
      return $?
      ;;
    3)
      __menu_invoke_submenu "__handle_directories_menu"
      return $?
      ;;
    4)
      __menu_invoke_submenu "__handle_events_menu"
      return $?
      ;;
    5)
      __menu_invoke_submenu "__handle_files_menu"
      return $?
      ;;
    6)
      __menu_invoke_submenu "__handle_instances_menu"
      return $?
      ;;
    7)
      __menu_invoke_submenu "__handle_lifecycle_menu"
      return $?
      ;;
    8)
      __menu_invoke_submenu "__handle_network_menu"
      return $?
      ;;
    9)
      __menu_invoke_submenu "__handle_system_menu"
      return $?
      ;;
    10)
      __menu_invoke_submenu "__handle_watcher_menu"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# Choice handler for blueprints menu
# shellcheck disable=SC2329
function __handle_blueprints_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_list_blueprints"
      return $?
      ;;
    2)
      __menu_execute_action "__action_blueprint_info"
      return $?
      ;;
    3)
      __menu_execute_action "__action_find_blueprint"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_blueprints_menu() {
  __menu_run_loop "__show_blueprints_menu" "1 2 3 b m q" "__handle_blueprints_choice"
}

# Choice handler for config menu
# shellcheck disable=SC2329
function __handle_config_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_config_list"
      return $?
      ;;
    2)
      __menu_execute_action "__action_config_get"
      return $?
      ;;
    3)
      __menu_execute_action "__action_config_set"
      return $?
      ;;
    4)
      __menu_execute_action "__action_config_validate"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_config_menu() {
  __menu_run_loop "__show_config_menu" "1 2 3 4 b m q" "__handle_config_choice"
}

# Choice handler for instances menu
# shellcheck disable=SC2329
function __handle_instances_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_list_instances"
      return $?
      ;;
    2)
      __menu_execute_action "__action_instance_info"
      return $?
      ;;
    3)
      __menu_execute_action "__wizard_lifecycle_operation" "status" "view status"
      return $?
      ;;
    4)
      __menu_execute_action "__action_find_instance"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_instances_menu() {
  __menu_run_loop "__show_instances_menu" "1 2 3 4 b m q" "__handle_instances_choice"
}

# Choice handler for lifecycle menu
# shellcheck disable=SC2329
function __handle_lifecycle_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__wizard_lifecycle_operation" "start" "start"
      return $?
      ;;
    2)
      __menu_execute_action "__wizard_lifecycle_operation" "stop" "stop"
      return $?
      ;;
    3)
      __menu_execute_action "__wizard_lifecycle_operation" "restart" "restart"
      return $?
      ;;
    4)
      __menu_execute_action "__wizard_lifecycle_operation" "logs" "view logs"
      return $?
      ;;
    5)
      __menu_execute_action "__wizard_lifecycle_operation" "status" "view status"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_lifecycle_menu() {
  __menu_run_loop "__show_lifecycle_menu" "1 2 3 4 5 b m q" "__handle_lifecycle_choice"
}

# Choice handler for network menu
# shellcheck disable=SC2329
function __handle_network_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_network_ip"
      return $?
      ;;
    2)
      __menu_execute_action "__action_network_check_port"
      return $?
      ;;
    3)
      __menu_execute_action "__action_network_conflicts"
      return $?
      ;;
    4)
      __menu_execute_action "__action_network_test_port"
      return $?
      ;;
    5)
      __menu_execute_action "__action_network_test_all"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_network_menu() {
  __menu_run_loop "__show_network_menu" "1 2 3 4 5 b m q" "__handle_network_choice"
}

# Choice handler for system menu
# shellcheck disable=SC2329
function __handle_system_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_system_info"
      return $?
      ;;
    2)
      __menu_execute_action "__action_system_uptime"
      return $?
      ;;
    3)
      __menu_execute_action "__action_system_shutdown"
      return $?
      ;;
    4)
      __menu_execute_action "__action_system_restart"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_system_menu() {
  __menu_run_loop "__show_system_menu" "1 2 3 4 b m q" "__handle_system_choice"
}

# Choice handler for files menu
# shellcheck disable=SC2329
function __handle_files_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_files_create_systemd"
      return $?
      ;;
    2)
      __menu_execute_action "__action_files_create_ufw"
      return $?
      ;;
    3)
      __menu_execute_action "__action_files_create_symlinks"
      return $?
      ;;
    4)
      __menu_execute_action "__action_files_remove"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_files_menu() {
  __menu_run_loop "__show_files_menu" "1 2 3 4 b m q" "__handle_files_choice"
}

# Choice handler for directories menu
# shellcheck disable=SC2329
function __handle_directories_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_directories_create"
      return $?
      ;;
    2)
      __menu_execute_action "__action_directories_remove"
      return $?
      ;;
    3)
      __menu_execute_action "__action_directories_list"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_directories_menu() {
  __menu_run_loop "__show_directories_menu" "1 2 3 b m q" "__handle_directories_choice"
}

# Choice handler for events menu
# shellcheck disable=SC2329
function __handle_events_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_events_status"
      return $?
      ;;
    2)
      __menu_execute_action "__action_events_test_all"
      return $?
      ;;
    3)
      __menu_execute_action "__action_events_webhook_config"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_events_menu() {
  __menu_run_loop "__show_events_menu" "1 2 3 b m q" "__handle_events_choice"
}

# Choice handler for watcher menu
# shellcheck disable=SC2329
function __handle_watcher_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__action_watcher_logs"
      return $?
      ;;
    2)
      __menu_execute_action "__action_watcher_ports"
      return $?
      ;;
    3)
      __menu_execute_action "__action_watcher_stop"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_watcher_menu() {
  __menu_run_loop "__show_watcher_menu" "1 2 3 b m q" "__handle_watcher_choice"
}

# Choice handler for server management menu
# shellcheck disable=SC2329
# This function is invoked as a callback
function __handle_server_management_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__wizard_install_server"
      return $?
      ;;
    2)
      __menu_execute_action "__wizard_lifecycle_operation" "start" "start"
      return $?
      ;;
    3)
      __menu_execute_action "__wizard_lifecycle_operation" "stop" "stop"
      return $?
      ;;
    4)
      __menu_execute_action "__wizard_lifecycle_operation" "restart" "restart"
      return $?
      ;;
    5)
      __menu_execute_action "__wizard_lifecycle_operation" "uninstall" "uninstall"
      return $?
      ;;
    6)
      __menu_execute_action "__wizard_modify_server"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_server_management_menu() {
  __menu_run_loop "__show_server_management_menu" "1 2 3 4 5 6 b m q" "__handle_server_management_choice"
}

# Choice handler for information menu
# shellcheck disable=SC2329
function __handle_information_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__wizard_list_items" "blueprints" "Available Blueprints"
      return $?
      ;;
    2)
      __menu_execute_action "__wizard_list_items" "instances" "Installed Instances"
      return $?
      ;;
    3)
      __menu_execute_action "__wizard_lifecycle_operation" "status" "view status"
      return $?
      ;;
    4)
      __menu_execute_action "__wizard_lifecycle_operation" "logs" "view logs"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_information_menu() {
  __menu_run_loop "__show_information_menu" "1 2 3 4 b m q" "__handle_information_choice"
}

# shellcheck disable=SC2329
# Choice handler for maintenance menu
function __handle_maintenance_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __menu_execute_action "__wizard_lifecycle_operation" "check-update" "check for updates"
      return $?
      ;;
    2)
      __menu_execute_action "__wizard_lifecycle_operation" "update" "update"
      return $?
      ;;
    3)
      __menu_execute_action "__wizard_lifecycle_operation" "create-backup" "create backup"
      return $?
      ;;
    4)
      __menu_execute_action "__wizard_restore_backup"
      return $?
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_maintenance_menu() {
  __menu_run_loop "__show_maintenance_menu" "1 2 3 4 b m q" "__handle_maintenance_choice"
}

# Choice handler for system tools menu
# shellcheck disable=SC2329
function __handle_system_tools_choice() {
  local choice="$1"

  case "$choice" in
    1)
      __ui_clear_screen
      __ui_draw_box "KGSM Configuration"
      __ui_print_empty_line
      [[ -f "$KGSM_ROOT/config.ini" ]] && cat "$KGSM_ROOT/config.ini" || echo "No configuration file found."
      __ui_print_empty_line
      __ui_close_box
      __ui_wait_for_key
      return $MENU_NAV_CONTINUE
      ;;
    2)
      __ui_clear_screen
      __ui_draw_box "System Information"
      __ui_print_box_line "KGSM Version: $(__logic_get_kgsm_version)"
      __ui_print_box_line "KGSM Root: $KGSM_ROOT"
      __ui_print_box_line "System: $(uname -s) $(uname -r)"
      __ui_print_box_line "Architecture: $(uname -m)"
      __ui_print_box_line "User: $(whoami)"
      __ui_print_box_line "Shell: $SHELL"
      __ui_close_box
      __ui_wait_for_key
      return $MENU_NAV_CONTINUE
      ;;
    3)
      echo -e "${UI_COLOR_INFO}Updating KGSM...${UI_COLOR_RESET}" >&2
      "$KGSM_ROOT/kgsm.sh" --update
      __ui_wait_for_key
      return $MENU_NAV_CONTINUE
      ;;
    *)
      __menu_handle_navigation "$choice"
      return $?
      ;;
  esac
}

# shellcheck disable=SC2329
function __handle_system_tools_menu() {
  __menu_run_loop "__show_system_tools_menu" "1 2 3 b m q" "__handle_system_tools_choice"
}

# =============================================================================
# COMMAND IMPLEMENTATIONS
# =============================================================================

function _cmd_launch() {
  # Welcome message
  __ui_clear_screen
  __ui_draw_box "Welcome to KGSM Interactive Mode"
  __ui_print_box_line "Krystal Game Server Manager - $(__logic_get_kgsm_version)"
  __ui_print_empty_line
  __ui_print_box_line "Create, install, and manage game servers on Linux."
  __ui_print_empty_line
  __ui_print_box_line "Navigation Tips:"
  __ui_print_box_line "  • Use numbers to select options"
  __ui_print_box_line "  • Use 'b' to go back, 'q' to quit"
  __ui_print_box_line "  • Use 'h' for help when available"
  __ui_print_box_line "  • Press Ctrl+C to exit at any time"
  __ui_close_box

  __ui_wait_for_key "Press any key to continue..."

  # Start main menu loop
  __handle_main_menu

  # Exit message
  __ui_clear_screen
  echo -e "${UI_COLOR_SUCCESS}Thank you for using KGSM!${UI_COLOR_RESET}" >&2
  echo -e "${UI_COLOR_INFO}For command-line usage, run: ./kgsm.sh --help${UI_COLOR_RESET}" >&2
  echo >&2

  exit 0
}

function _cmd_wizard() {
  local wizard_type="$1"

  if [[ -z "$wizard_type" ]]; then
    __print_error "Missing wizard type"
    __print_error "Use '${self} wizard <type>' or '${self} help wizard' for usage information"
    exit $EC_MISSING_ARG
  fi

  case "$wizard_type" in
    install)
      __wizard_install_server
      exit $?
      ;;
    configure)
      __print_info "Configuration wizard not yet implemented"
      exit $EC_NOT_IMPLEMENTED
      ;;
    modify)
      __wizard_modify_server
      exit $?
      ;;
    *)
      __print_error "Unknown wizard type: $wizard_type"
      __print_error "Valid types: install, configure, modify"
      exit $EC_INVALID_ARG
      ;;
  esac
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    exit 0
  fi

  case "$command" in
    launch)
      usage_launch
      exit 0
      ;;
    wizard)
      usage_wizard
      exit 0
      ;;
    *)
      __print_error "Unknown command: $command"
      __print_error "Use '${self} help' for available commands"
      exit $EC_INVALID_ARG
      ;;
  esac
}

# =============================================================================
# MAIN COMMAND ROUTING
# =============================================================================

command="$1"
shift

case "$command" in
  "")
    show_usage
    exit $EC_ERROR
    ;;
  launch)
    _cmd_launch
    ;;
  wizard)
    _cmd_wizard "$@"
    ;;
  -h | --help | help)
    _cmd_help "$@"
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '${self} help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac
