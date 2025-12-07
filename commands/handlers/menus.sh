#!/usr/bin/env bash

# KGSM Pure Logic Layer - Menu Navigation
#
# This module provides declarative menu definitions and centralized navigation
# logic for the interactive mode. It implements a menu stack for hierarchical
# navigation and standardizes menu rendering and input handling.
#
# Exit Code Conventions:
# - 0: Normal return to parent menu
# - 2: Quit signal (propagate up to exit application)

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Prevent multiple sourcing
if [[ -n "${KGSM_LOGIC_MENUS_LOADED:-}" ]]; then
  return 0
fi
export KGSM_LOGIC_MENUS_LOADED=true

# =============================================================================
# MENU NAVIGATION CONSTANTS
# =============================================================================

# Return codes for menu navigation
export MENU_NAV_CONTINUE=0  # Continue in current menu
export MENU_NAV_BACK=1      # Return to parent menu
export MENU_NAV_QUIT=2      # Exit application

# =============================================================================
# MENU ITEM EXECUTION
# =============================================================================

# Execute a menu action and handle its return code
#
# Args:
#   $1 - action_function (name of function to call)
#   $@ - additional arguments to pass to action_function
#
# Returns:
#   0 to continue in current menu
#   2 to propagate quit signal
#
# Example:
#   __menu_execute_action "__action_install_server"
function __menu_execute_action() {
  local action_function="$1"
  shift

  # Execute the action
  "$action_function" "$@"
  local result=$?

  # Handle quit signal
  if [[ $result -eq $MENU_NAV_QUIT ]]; then
    return $MENU_NAV_QUIT
  fi

  # All other results (including errors) stay in current menu
  return $MENU_NAV_CONTINUE
}
export -f __menu_execute_action

# =============================================================================
# MENU RENDERING HELPERS
# =============================================================================

# Display a menu and get user choice
#
# This is the core menu rendering function that:
# 1. Displays the menu with __show_* function
# 2. Gets user input
# 3. Validates input
# 4. Returns the selected choice
#
# Args:
#   $1 - show_menu_function (function that displays the menu)
#   $2 - valid_choices (space-separated list of valid choices)
#
# Output:
#   Prints selected choice to stdout
#
# Returns:
#   0 if valid choice selected
#   1 if invalid choice
#
# Example:
#   if choice=$(__menu_get_choice "__show_main_menu" "1 2 3 4 h q"); then
#     # Process choice
#   fi
function __menu_get_choice() {
  local show_menu_function="$1"
  local valid_choices="$2"

  # Display the menu
  "$show_menu_function"

  # Get user choice using UI library
  __ui_get_menu_choice "$valid_choices"
  return $?
}
export -f __menu_get_choice

# =============================================================================
# STANDARD MENU LOOP
# =============================================================================

# Run a standard menu loop
#
# This function implements the common menu pattern:
# - Display menu
# - Get user choice
# - Execute action based on choice
# - Handle navigation (back, quit)
# - Repeat until user exits
#
# Args:
#   $1 - show_menu_function (function that displays the menu)
#   $2 - valid_choices (space-separated list of valid choices)
#   $3 - handle_choice_function (function that processes the choice)
#
# Returns:
#   0 when returning to parent menu
#   2 when quit signal received
#
# The handle_choice_function receives the user's choice as $1 and should:
# - Return 0 to continue in current menu
# - Return 1 to go back to parent menu
# - Return 2 to propagate quit signal
#
# Example:
#   __menu_run_loop "__show_main_menu" "1 2 3 q" "__handle_main_menu_choice"
function __menu_run_loop() {
  local show_menu_function="$1"
  local valid_choices="$2"
  local handle_choice_function="$3"

  while true; do
    # Display the menu
    "$show_menu_function"

    # Get user choice using REPLY variable (not command substitution to preserve stdin)
    if __ui_get_menu_choice "$valid_choices"; then
      local choice="$REPLY"

      # Execute the choice handler
      "$handle_choice_function" "$choice"
      local result=$?

      case $result in
        "$MENU_NAV_CONTINUE")
          # Stay in current menu
          continue
          ;;
        "$MENU_NAV_BACK")
          # Return to parent menu
          return 0
          ;;
        "$MENU_NAV_QUIT")
          # Propagate quit signal
          return 2
          ;;
      esac
    else
      # Invalid choice - show error and retry
      __ui_wait_for_key "Invalid selection. Press any key to try again..."
    fi
  done
}
export -f __menu_run_loop

# =============================================================================
# SUBMENU INVOCATION
# =============================================================================

# Invoke a submenu and handle its return
#
# This helper standardizes calling submenus and handling their return codes.
# It's used when a menu choice leads to another menu.
#
# Args:
#   $1 - submenu_function (function that runs the submenu)
#   $@ - additional arguments to pass to submenu
#
# Returns:
#   0 to continue in current menu (submenu returned normally)
#   2 to propagate quit signal
#
# Example:
#   __menu_invoke_submenu "__handle_server_management_menu"
function __menu_invoke_submenu() {
  local submenu_function="$1"
  shift

  "$submenu_function" "$@"
  local result=$?

  # Propagate quit signal
  if [[ $result -eq $MENU_NAV_QUIT ]]; then
    return $MENU_NAV_QUIT
  fi

  # All other results continue in current menu
  return $MENU_NAV_CONTINUE
}
export -f __menu_invoke_submenu

# =============================================================================
# STANDARD NAVIGATION HANDLERS
# =============================================================================

# Handle standard navigation choices (back, main, quit)
#
# This helper processes common navigation options that appear in most menus.
#
# Args:
#   $1 - choice (user's menu selection)
#
# Returns:
#   0 if not a navigation choice (caller should handle it)
#   1 for back/main menu
#   2 for quit
#
# Example:
#   if ! __menu_handle_navigation "$choice"; then
#     # It was a navigation choice, result already returned
#     return $?
#   fi
#   # Not a navigation choice, handle it normally
function __menu_handle_navigation() {
  local choice="$1"

  case "$choice" in
    b | m)
      # Back or Main menu
      return $MENU_NAV_BACK
      ;;
    q)
      # Quit
      return $MENU_NAV_QUIT
      ;;
    *)
      # Not a navigation choice
      return 0
      ;;
  esac
}
export -f __menu_handle_navigation

# =============================================================================
# USAGE PATTERNS
# =============================================================================
#
# This library provides building blocks for menu-driven interfaces.
# Here are the recommended usage patterns:
#
# PATTERN 1: Simple Menu with Direct Actions
# ------------------------------------------
# function __handle_simple_menu() {
#   function __handle_choice() {
#     case "$1" in
#       1) __action_do_something ;;
#       2) __action_do_something_else ;;
#       *) __menu_handle_navigation "$1"; return $? ;;
#     esac
#     return $MENU_NAV_CONTINUE
#   }
#
#   __menu_run_loop "__show_simple_menu" "1 2 b q" "__handle_choice"
# }
#
# PATTERN 2: Menu with Submenus
# -----------------------------
# function __handle_main_menu() {
#   function __handle_choice() {
#     case "$1" in
#       1) __menu_invoke_submenu "__handle_server_menu"; return $? ;;
#       2) __menu_invoke_submenu "__handle_settings_menu"; return $? ;;
#       *) __menu_handle_navigation "$1"; return $? ;;
#     esac
#   }
#
#   __menu_run_loop "__show_main_menu" "1 2 q" "__handle_choice"
# }
#
# PATTERN 3: Menu with Actions and Error Handling
# -----------------------------------------------
# function __handle_action_menu() {
#   function __handle_choice() {
#     case "$1" in
#       1)
#         if __menu_execute_action "__action_install"; then
#           return $MENU_NAV_CONTINUE
#         else
#           return $?  # Propagate quit if returned
#         fi
#         ;;
#       *) __menu_handle_navigation "$1"; return $? ;;
#     esac
#   }
#
#   __menu_run_loop "__show_action_menu" "1 b q" "__handle_choice"
# }
#
# BENEFITS:
# - Centralized menu loop logic (no duplication)
# - Consistent navigation handling
# - Clear separation between menu structure and actions
# - Easy to add new menus following established patterns
# - Standardized quit signal propagation
#
# =============================================================================
