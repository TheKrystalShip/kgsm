#!/usr/bin/env bash

# KGSM UI Library
#
# Provides reusable terminal user interface primitives for interactive
# features across KGSM modules. Includes color constants, box drawing,
# user prompting, confirmation dialogs, and list selection.
#
# This library is designed to be lightweight and extensible, allowing
# future additions like progress bars, tables, and multi-column layouts.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# Prevent multiple sourcing
if [[ -n "${KGSM_UI_LOADED:-}" ]]; then
  return 0
fi
export KGSM_UI_LOADED=true

# =============================================================================
# COLOR CONSTANTS
# =============================================================================

# ANSI color codes for terminal output formatting
# These can be disabled by setting KGSM_NO_COLOR=true
if [[ "${KGSM_NO_COLOR:-false}" == "true" ]]; then
  export UI_COLOR_HEADER=""
  export UI_COLOR_MENU=""
  export UI_COLOR_INFO=""
  export UI_COLOR_WARNING=""
  export UI_COLOR_ERROR=""
  export UI_COLOR_SUCCESS=""
  export UI_COLOR_PROMPT=""
  export UI_COLOR_RESET=""
else
  export UI_COLOR_HEADER="\033[1;36m"   # Bright cyan for headers
  export UI_COLOR_MENU="\033[1;32m"     # Bright green for menu items
  export UI_COLOR_INFO="\033[0;37m"     # White for info text
  export UI_COLOR_WARNING="\033[1;33m"  # Yellow for warnings
  export UI_COLOR_ERROR="\033[1;31m"    # Red for errors
  export UI_COLOR_SUCCESS="\033[1;32m"  # Green for success
  export UI_COLOR_PROMPT="\033[1;35m"   # Magenta for prompts
  export UI_COLOR_RESET="\033[0m"       # Reset to default
fi

# =============================================================================
# MENU NAVIGATION CONSTANTS
# =============================================================================

export UI_MENU_BACK="← Back"
export UI_MENU_MAIN="⌂ Main Menu"
export UI_MENU_QUIT="✗ Quit"
export UI_MENU_HELP="? Help"

# =============================================================================
# BOX DRAWING FUNCTIONS
# =============================================================================

# Draw the top border and optional title of a box
#
# Args:
#   $1 - title (optional, displayed centered in box)
#   $2 - width (optional, default: 75)
#
# Output:
#   Prints box top border to stderr
#
# Example:
#   __ui_draw_box "Main Menu"
#   __ui_draw_box "Settings" 80
function __ui_draw_box() {
  local title="$1"
  local width=${2:-75}

  # Top border
  echo -e "${UI_COLOR_HEADER}$(printf "%*s" $width | tr ' ' '=')${UI_COLOR_RESET}" >&2

  if [[ -n "$title" ]]; then
    local title_len=${#title}
    local padding=$(((width - title_len) / 2))
    printf "%*s${UI_COLOR_HEADER}${title}${UI_COLOR_RESET}\n" $padding "" >&2
    echo -e "${UI_COLOR_HEADER}$(printf "%*s" $width | tr ' ' '=')${UI_COLOR_RESET}" >&2
  fi
}
export -f __ui_draw_box

# Draw the bottom border of a box
#
# Args:
#   $1 - width (optional, default: 75)
#
# Output:
#   Prints box bottom border to stderr
#
# Example:
#   __ui_close_box
#   __ui_close_box 80
function __ui_close_box() {
  local width=${1:-75}
  echo -e "${UI_COLOR_HEADER}$(printf "%*s" $width | tr ' ' '=')${UI_COLOR_RESET}" >&2
}
export -f __ui_close_box

# Print a single line of text inside a box
#
# Args:
#   $1 - text to print
#   $2 - color code (optional, default: UI_COLOR_INFO)
#
# Output:
#   Prints formatted line to stderr
#
# Example:
#   __ui_print_box_line "Server is running"
#   __ui_print_box_line "Warning: Low disk space" "$UI_COLOR_WARNING"
function __ui_print_box_line() {
  local text="$1"
  local color="${2:-$UI_COLOR_INFO}"
  printf "  ${color}%s${UI_COLOR_RESET}\n" "$text" >&2
}
export -f __ui_print_box_line

# Print an empty line (for spacing in boxes)
#
# Output:
#   Prints blank line to stderr
#
# Example:
#   __ui_print_empty_line
function __ui_print_empty_line() {
  echo >&2
}
export -f __ui_print_empty_line

# =============================================================================
# MENU ITEM RENDERING
# =============================================================================

# Print a formatted menu item with number/letter and description
#
# Args:
#   $1 - item number/letter (e.g., "1", "a", "q")
#   $2 - item text
#   $3 - description (optional)
#
# Output:
#   Prints formatted menu item to stderr
#
# Example:
#   __ui_print_menu_item "1" "Install Server" "Deploy a new game server"
#   __ui_print_menu_item "q" "Quit" "Exit the program"
function __ui_print_menu_item() {
  local number="$1"
  local text="$2"
  local description="$3"

  printf "  ${UI_COLOR_MENU}%s)${UI_COLOR_RESET} %-20s" "$number" "$text" >&2
  if [[ -n "$description" ]]; then
    printf " ${UI_COLOR_INFO}%s${UI_COLOR_RESET}" "$description" >&2
  fi
  echo >&2
}
export -f __ui_print_menu_item

# =============================================================================
# USER INPUT FUNCTIONS
# =============================================================================

# Prompt user for input with optional default value
#
# Args:
#   $1 - prompt message
#   $2 - default value (optional)
#
# Output:
#   Prints user's response to stdout (for capture)
#   Prints prompt to stderr
#
# Returns:
#   0 always (user response may be empty)
#
# Example:
#   install_dir=$(__ui_prompt_user "Installation directory:" "/opt/servers")
#   version=$(__ui_prompt_user "Version (leave empty for latest):")
function __ui_prompt_user() {
  local prompt="$1"
  local default="$2"
  local response

  echo -e "${UI_COLOR_PROMPT}${prompt}${UI_COLOR_RESET}" >&2
  if [[ -n "$default" ]]; then
    echo -e "${UI_COLOR_INFO}(Press Enter for default: $default)${UI_COLOR_RESET}" >&2
  fi
  echo -n "> " >&2
  read -r response

  if [[ -z "$response" && -n "$default" ]]; then
    echo "$default"
  else
    echo "$response"
  fi
}
export -f __ui_prompt_user

# Ask user for confirmation (yes/no)
#
# Args:
#   $1 - confirmation message
#
# Output:
#   Prints prompt to stderr
#
# Returns:
#   0 if user confirms (y/Y)
#   1 if user declines (anything else)
#
# Example:
#   if __ui_confirm_action "Delete all data?"; then
#     # User confirmed
#   fi
function __ui_confirm_action() {
  local message="$1"
  local response

  echo -e "${UI_COLOR_WARNING}${message}${UI_COLOR_RESET}" >&2
  echo -e "${UI_COLOR_PROMPT}Are you sure? (y/N)${UI_COLOR_RESET}" >&2
  echo -n "> " >&2
  read -r response

  [[ "$response" =~ ^[Yy]$ ]]
}
export -f __ui_confirm_action

# Wait for user to press any key
#
# Args:
#   $1 - message to display (optional, default: "Press any key to continue...")
#
# Output:
#   Prints message to stderr and waits for keypress
#   Skips waiting if stdin is not a terminal (piped input)
#
# Example:
#   __ui_wait_for_key
#   __ui_wait_for_key "Press any key to return to menu..."
function __ui_wait_for_key() {
  local message="${1:-Press any key to continue...}"
  echo -e "${UI_COLOR_INFO}${message}${UI_COLOR_RESET}" >&2

  # Only wait for input if stdin is a terminal
  if [[ -t 0 ]]; then
    read -n 1 -s
  fi
}
export -f __ui_wait_for_key

# =============================================================================
# SCREEN CONTROL
# =============================================================================

# Clear the terminal screen
#
# Uses ANSI escape sequences for better compatibility
#
# Output:
#   Clears screen and positions cursor at top-left
#
# Example:
#   __ui_clear_screen
function __ui_clear_screen() {
  printf "\033[2J\033[H" >&2
}
export -f __ui_clear_screen

# =============================================================================
# MENU CHOICE INPUT
# =============================================================================

# Get and validate a menu choice from user
#
# Sets the REPLY variable to the user's choice (avoids command substitution issues)
#
# Args:
#   $1 - space-separated list of valid choices (e.g., "1 2 3 q")
#
# Output:
#   Sets REPLY to the selected choice
#   Prints prompt and errors to stderr
#
# Returns:
#   0 if valid choice selected (REPLY is set)
#   1 if invalid choice (REPLY is empty)
#
# Example:
#   if __ui_get_menu_choice "1 2 3 q"; then
#     case "$REPLY" in
#       1) action_one ;;
#       2) action_two ;;
#       3) action_three ;;
#       q) exit 0 ;;
#     esac
#   fi
function __ui_get_menu_choice() {
  local valid_choices="$1"
  local choice

  echo -e "${UI_COLOR_PROMPT}Choose an option:${UI_COLOR_RESET}" >&2
  echo -n "> " >&2
  read -r choice

  # Convert to lowercase for consistency
  choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

  # Validate choice - check if choice is in the space-separated list
  if [[ " $valid_choices " == *" $choice "* ]]; then
    REPLY="$choice"  # Set REPLY variable instead of echoing
    return 0
  else
    echo -e "${UI_COLOR_ERROR}Invalid choice: '$choice'${UI_COLOR_RESET}" >&2
    echo -e "${UI_COLOR_INFO}Valid options: $valid_choices${UI_COLOR_RESET}" >&2
    REPLY=""  # Clear REPLY on invalid input
    return 1
  fi
}
export -f __ui_get_menu_choice

# =============================================================================
# LIST SELECTION
# =============================================================================

# Display a list and let user select an item
#
# Args:
#   $1 - title for the selection menu
#   $2 - name of array variable containing items (passed by reference)
#   $3 - allow back option (optional, default: "true")
#
# Output:
#   Prints selected item to stdout (for capture)
#   Displays menu to stderr
#
# Returns:
#   0 if item selected
#   1 if back selected (only if allow_back=true)
#   2 if quit selected
#
# Example:
#   mapfile -t servers < <(get_server_list)
#   if selected=$(__ui_select_from_list "Choose Server" servers); then
#     echo "Selected: $selected"
#   fi
#
# Note:
#   Array must be passed by name (not expanded with @)
function __ui_select_from_list() {
  local title="$1"
  local -n items_ref=$2
  local allow_back="${3:-true}"
  local selected_item

  if [[ ${#items_ref[@]} -eq 0 ]]; then
    echo -e "${UI_COLOR_WARNING}No items available.${UI_COLOR_RESET}" >&2
    __ui_wait_for_key
    return 1
  fi

  while true; do
    __ui_clear_screen
    __ui_draw_box "$title"

    local i=1
    for item in "${items_ref[@]}"; do
      __ui_print_menu_item "$i" "$item"
      ((i++))
    done

    __ui_print_empty_line
    if [[ "$allow_back" == "true" ]]; then
      __ui_print_menu_item "b" "$UI_MENU_BACK" "Return to previous menu"
    fi
    __ui_print_menu_item "q" "$UI_MENU_QUIT" "Exit KGSM"
    __ui_close_box

    local valid_choices="q"
    [[ "$allow_back" == "true" ]] && valid_choices="${valid_choices} b"
    for ((j = 1; j < i; j++)); do
      valid_choices="$valid_choices $j"
    done

    if __ui_get_menu_choice "$valid_choices"; then
      case "$REPLY" in
        q) return 2 ;;                                  # Quit
        b) [[ "$allow_back" == "true" ]] && return 1 ;; # Back
        [0-9]*)
          if [[ $REPLY -ge 1 && $REPLY -lt $i ]]; then
            selected_item="${items_ref[$((REPLY - 1))]}"
            echo "$selected_item"
            return 0
          fi
          ;;
      esac
    fi

    __ui_wait_for_key "Invalid selection. Press any key to try again..."
  done
}
export -f __ui_select_from_list

# =============================================================================
# EXTENSIBILITY NOTES
# =============================================================================
#
# This library is designed to be extended with additional UI primitives:
#
# Future additions could include:
# - __ui_progress_bar() - Display progress with percentage
# - __ui_spinner() - Animated loading indicator
# - __ui_table() - Formatted table output
# - __ui_multi_column() - Multi-column layout
# - __ui_color_text() - Apply color to arbitrary text
# - __ui_styled_box() - Different box styles (single, double, rounded)
# - __ui_input_password() - Hidden password input
# - __ui_multi_select() - Multiple item selection from list
#
# When adding new functions:
# 1. Follow the __ui_* naming convention
# 2. Export functions with: export -f function_name
# 3. Send user-facing output to stderr
# 4. Return data via stdout (for capture)
# 5. Document args, returns, and examples in function header
# 6. Use existing color constants where applicable
#
# =============================================================================
