#!/usr/bin/env bash

# shellcheck disable=SC2086
# shellcheck disable=SC2254
# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Directory Management for Krystal Game Server Manager${END}

Creates and manages the directory structure needed for game server instances.

${UNDERLINE}Usage:${END}
  ${self} <command> [options]

${UNDERLINE}Commands:${END}
  create <instance>           Create directory structure for an instance.
                              Creates installation, data, logs, and backup
                              directories.
  remove <instance>           Remove directory structure for an instance.
                              Warning: This will delete all instance data.
  link-instance <blueprint> <instance> <working-dir>
                              Create symlink from KGSM instances directory
                              to instance working directory.
  unlink-instance <blueprint> <instance>
                              Remove symlink from KGSM instances directory.
  ensure-created <path>       Ensure the specified directory path exists,
                              creating it if necessary.
  help [command]              Display help information.

${UNDERLINE}Options:${END}
  <instance>                  Target instance name (required)
  -h | --help                 Display help for specific command.

${UNDERLINE}Examples:${END}
  ${self} create valheim-h1up6V
  ${self} remove valheim-h1up6V
  ${self} help create
  ${self} create --help
"
}

function show_usage_create() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Create Directory Structure${END}

Creates the complete directory structure for a game server instance.

${UNDERLINE}Usage:${END}
  ${self} create <instance>

${UNDERLINE}Options:${END}
  <instance>                  Target instance name (required)
  -h | --help                 Display this help information

${UNDERLINE}Description:${END}
This command creates the following directory structure:
  • working_dir/              Main instance directory
  • working_dir/backups/      Instance backup files
  • working_dir/install/      Game server installation files
  • working_dir/saves/        Game save files and world data
  • working_dir/temp/         Temporary files during operations
  • working_dir/logs/         Instance-specific log files

The directory paths are automatically added to the instance configuration file.

${UNDERLINE}Examples:${END}
  ${self} create valheim-h1up6V
  ${self} create minecraft-server
"
}

function show_usage_remove() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Remove Directory Structure${END}

Removes the complete directory structure for a game server instance.

${UNDERLINE}Usage:${END}
  ${self} remove <instance>

${UNDERLINE}Options:${END}
  <instance>                  Target instance name (required)
  -h | --help                 Display this help information

${UNDERLINE}Warning:${END}
This command will permanently delete ALL instance data including:
  • Game server files
  • Save files and world data
  • Backup files
  • Log files
  • Configuration data

This action cannot be undone!

${UNDERLINE}Examples:${END}
  ${self} remove valheim-h1up6V
  ${self} remove minecraft-server
"
}

function show_ensure_created_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Ensure Directory Exists${END}
Ensures that the specified directory path exists, creating it if necessary.

${UNDERLINE}Usage:${END}
  ${self} ensure-created <path>

${UNDERLINE}Options:${END}
  <path>                      Directory path to ensure exists (required)
  -h | --help                 Display this help information

${UNDERLINE}Examples:${END}
  ${self} ensure-created /var/kgsm/instances/minecraft-server
  ${self} ensure-created /opt/kgsm/backups
"
}

function show_usage_link_instance() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Link Instance${END}

Create a symlink from KGSM's instances directory to the instance working directory.

${UNDERLINE}Usage:${END}
  ${self} link-instance <blueprint> <instance> <working-dir>

${UNDERLINE}Arguments:${END}
  <blueprint>                 Blueprint name (required)
  <instance>                  Instance name (required)
  <working-dir>               Instance working directory path (required)

${UNDERLINE}Options:${END}
  -h | --help                 Display this help information

${UNDERLINE}Description:${END}
Creates a symlink at \$KGSM_INSTANCES_DIR/<blueprint>/<instance> that points
to the instance's working directory. This allows KGSM to track instances
regardless of where they are physically installed.

${UNDERLINE}Examples:${END}
  ${self} link-instance factorio factorio-01 /opt/servers/factorio-01
  ${self} link-instance minecraft mc-server /home/user/servers/mc-server
"
}

function show_usage_unlink_instance() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Unlink Instance${END}

Remove the symlink from KGSM's instances directory.

${UNDERLINE}Usage:${END}
  ${self} unlink-instance <blueprint> <instance>

${UNDERLINE}Arguments:${END}
  <blueprint>                 Blueprint name (required)
  <instance>                  Instance name (required)

${UNDERLINE}Options:${END}
  -h | --help                 Display this help information

${UNDERLINE}Description:${END}
Removes the symlink at \$KGSM_INSTANCES_DIR/<blueprint>/<instance>. This
does not delete the actual instance files, only the tracking symlink.

${UNDERLINE}Examples:${END}
  ${self} unlink-instance factorio factorio-01
  ${self} unlink-instance minecraft mc-server
"
}

# Load required libraries
logic_directories=$(__find_command_handler directories.sh)
# shellcheck source=handlers/directories.sh
source "$logic_directories" || {
  __print_error "Failed to load directories logic library"
  exit $EC_FAILED_SOURCE
}

events_library=$(__find_core_module events.sh)
# shellcheck source=../core/events.sh
source "$events_library" || {
  __print_error "Failed to load events library"
  exit $EC_FAILED_SOURCE
}

# Command wrapper for create
function _cmd_create() {
  local instance_name=""

  # Parse create command options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_create
        return 0
        ;;
      -*)
        __print_error "Invalid option for create command: $1"
        __print_error "Use '${self} create --help' for usage information"
        exit $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required option: <instance>"
    __print_error "Use '${self} create --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Validate instance name and get config file
  local instance_config_file
  if ! instance_config_file=$(validate_instance_name "$instance_name"); then
    exit $?
  fi

  # Validate working directory configuration
  local instance_working_dir
  if ! instance_working_dir=$(validate_working_directory "$instance_config_file"); then
    exit $?
  fi

  # Call pure logic function
  __print_info "Creating directories for instance $instance_name"
  local exit_code
  __logic_create_directories "$instance_name" "$instance_config_file" "$instance_working_dir"
  exit_code=$?

  # Handle result based on exit code
  case $exit_code in
    $EC_SUCCESS_DIRECTORIES_CREATED)
      __print_success "Directories created successfully for instance $instance_name"
      # Dispatch event
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      exit 0
      ;;
    *)
      __print_error "Failed to create directories for instance $instance_name"
      exit $exit_code
      ;;
  esac
}

# Command wrapper for remove
function _cmd_remove() {
  local instance_name=""

  # Parse remove command options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_remove
        return 0
        ;;
      -*)
        __print_error "Invalid option for remove command: $1"
        exit $EC_INVALID_ARG
        ;;
      *)
        instance_name="$1"
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required option: -i, --instance"
    __print_error "Use '${self} remove --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Validate instance name and get config file
  local instance_config_file
  if ! instance_config_file=$(validate_instance_name "$instance_name"); then
    exit $?
  fi

  # Validate working directory configuration
  local instance_working_dir
  if ! instance_working_dir=$(validate_working_directory "$instance_config_file"); then
    exit $?
  fi

  # Call pure logic function
  __print_info "Removing directories for instance $instance_name"
  local exit_code
  __logic_remove_directories "$instance_name" "$instance_working_dir"
  exit_code=$?

  # Handle result based on exit code
  case $exit_code in
    $EC_SUCCESS_DIRECTORIES_REMOVED)
      __print_success "Directories removed successfully for instance $instance_name"
      # Dispatch event
      __dispatch_event_from_exit_code "$exit_code" "$instance_name"
      exit 0
      ;;
    *)
      __print_error "Failed to remove directories for instance $instance_name"
      exit $exit_code
      ;;
  esac
}

function _cmd_ensure_created() {
  local dir_path=""

  # Parse ensure-created command options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_ensure_created_usage
        return 0
        ;;
      -*)
        __print_error "Invalid option for ensure-created command: $1"
        exit $EC_INVALID_ARG
        ;;
      *)
        dir_path="$1"
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$dir_path" ]]; then
    __print_error "Missing required option: <path>"
    __print_error "Use '${self} ensure-created --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Call pure logic function
  local exit_code
  __create_dir "$dir_path"
  exit_code=$?

  # Handle result based on exit code
  case $exit_code in
    $EC_SUCCESS_DIRECTORY_EXISTS | $EC_SUCCESS)
      exit 0
      ;;
    *)
      __print_error "Failed to ensure directory exists: $dir_path"
      exit $exit_code
      ;;
  esac
}

function _cmd_link_instance() {
  local blueprint_name=""
  local instance_name=""
  local working_dir=""

  # Parse link-instance command options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_link_instance
        return 0
        ;;
      -*)
        __print_error "Invalid option for link-instance command: $1"
        exit $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$blueprint_name" ]]; then
          blueprint_name="$1"
        elif [[ -z "$instance_name" ]]; then
          instance_name="$1"
        elif [[ -z "$working_dir" ]]; then
          working_dir="$1"
        else
          __print_error "Too many arguments"
          exit $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$blueprint_name" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '${self} link-instance --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} link-instance --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$working_dir" ]]; then
    __print_error "Missing required argument: <working-dir>"
    __print_error "Use '${self} link-instance --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Call pure logic function
  local exit_code
  __logic_create_instance_symlink "$blueprint_name" "$instance_name" "$working_dir"
  exit_code=$?

  # Handle result based on exit code
  case $exit_code in
    $EC_SUCCESS)
      exit 0
      ;;
    *)
      __print_error "Failed to create instance symlink"
      exit $exit_code
      ;;
  esac
}

function _cmd_unlink_instance() {
  local blueprint_name=""
  local instance_name=""

  # Parse unlink-instance command options
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -h | --help | help)
        show_usage_unlink_instance
        return 0
        ;;
      -*)
        __print_error "Invalid option for unlink-instance command: $1"
        exit $EC_INVALID_ARG
        ;;
      *)
        if [[ -z "$blueprint_name" ]]; then
          blueprint_name="$1"
        elif [[ -z "$instance_name" ]]; then
          instance_name="$1"
        else
          __print_error "Too many arguments"
          exit $EC_INVALID_ARG
        fi
        ;;
    esac
    shift
  done

  # Validate required parameters
  if [[ -z "$blueprint_name" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '${self} unlink-instance --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  if [[ -z "$instance_name" ]]; then
    __print_error "Missing required argument: <instance>"
    __print_error "Use '${self} unlink-instance --help' for usage information"
    exit $EC_MISSING_ARG
  fi

  # Call pure logic function
  local exit_code
  __logic_remove_instance_symlink "$blueprint_name" "$instance_name"
  exit_code=$?

  # Handle result based on exit code
  case $exit_code in
    $EC_SUCCESS)
      exit 0
      ;;
    *)
      __print_error "Failed to remove instance symlink"
      exit $exit_code
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
    create)
      show_usage_create
      ;;
    remove)
      show_usage_remove
      ;;
    link-instance)
      show_usage_link_instance
      ;;
    unlink-instance)
      show_usage_unlink_instance
      ;;
    ensure-created)
      show_ensure_created_usage
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
  create)
    _cmd_create "$@"
    exit $?
    ;;
  remove)
    _cmd_remove "$@"
    exit $?
    ;;
  link-instance)
    _cmd_link_instance "$@"
    exit $?
    ;;
  unlink-instance)
    _cmd_unlink_instance "$@"
    exit $?
    ;;
  ensure-created)
    _cmd_ensure_created "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $1"
    __print_error "Use '${self} --help' for usage information"
    exit $EC_INVALID_ARG
    ;;
esac
