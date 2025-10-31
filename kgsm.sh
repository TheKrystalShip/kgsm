#!/usr/bin/env bash

# Disable shellcheck for double quotes, as it will complain about
# the variables being used in the functions below.
# shellcheck disable=SC2086

# Bootstrap the environment.
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/lib/bootstrap.sh"

# Load essential modules early
module_interactive=$(__find_module interactive.sh)

installer_script="$(__find_or_fail installer.sh)"

if [[ ! -f "$installer_script" ]]; then
  __print_error "installer.sh missing, won't be able to check for updates"
  __print_error "Installation might be compromised, please reinstall KGSM"
  exit $EC_GENERAL
fi

function check_for_update() {
  "$installer_script" --check-update
}

function update_script() {
  "$installer_script" --update
}

function get_version() {
  "$installer_script" --version
}

function usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"
  local BOLD="\e[1m"

  echo -e "Krystal Game Server Manager - $(get_version)

Create, install, and manage game servers on Linux.

If you have any problems while using KGSM, please don't hesitate to create an
issue on GitHub: https://github.com/TheKrystalShip/KGSM/issues"

  echo -e "
${UNDERLINE}Usage:${END}
  $(basename "$0") [OPTIONS] [COMMANDS]

${BOLD}${UNDERLINE}General Options:${END}
  -h, --help                  Display comprehensive help information
    [--interactive]           Show help specifically for interactive mode
  --interactive               Launch KGSM in user-friendly interactive menu mode
  -v, --version               Display the current KGSM version
  --check-update              Check if a newer version of KGSM is available
  --update                    Update KGSM to the latest version
    [--force]                 Skip version verification and force download of latest version
  --migrate                   Migrate existing game server instances to the latest KGSM version
  --ip                        Display this server's external IP address

${BOLD}${UNDERLINE}Configuration Management:${END}
  config                      Manage KGSM configuration settings
    [no subcommand]           Open configuration in editor (default behavior)
    set KEY=VALUE             Set a configuration value
                              Example: config set enable_logging=true
                              Example: config set instance_suffix_length=3
    get KEY                   Get a configuration value
                              Example: config get enable_systemd
    list                      List all configuration values
    list --json               Output configuration in JSON format
    reset                     Reset configuration to defaults
    validate                  Validate current configuration

${BOLD}${UNDERLINE}Event System Management:${END}
  --events                    Manage KGSM's event broadcasting system
    --status                  Show comprehensive event system status
    --test-all                Test all configured event transports
    --test-socket             Test Unix Domain Socket transport only
    --test-webhook            Test HTTP webhook transport only
    --socket COMMAND          Manage Unix Domain Socket transport
      --enable                Enable socket transport
      --disable               Disable socket transport
      --test                  Test socket functionality
      --status                Show socket transport status
    --webhook COMMAND         Manage HTTP webhook transport
      --enable                Enable webhook transport
      --disable               Disable webhook transport
      --configure             Interactive webhook configuration wizard
      --test                  Test webhook functionality
      --status                Show webhook transport status

${BOLD}${UNDERLINE}Blueprint Management:${END}
  blueprints                  Display a list of all available server blueprints
    [no subcommand]           Show basic blueprint list (default behavior)
    [-h, --help]              Display help information for the blueprint creation process
    default                   Show only default built-in blueprints
    custom                    Show only user-added custom blueprints
    detailed --json           Show detailed information about all available blueprints
                              (Output in JSON format, useful for scripting)

  ${BOLD}${UNDERLINE}Blueprint options:${END}
    --json                    Output blueprint list in JSON format

${BOLD}${UNDERLINE}Instance Management:${END}
  --remove <instance>         Remove a game server instance completely
  --uninstall <instance>      Alias for --remove
  --instances                 List all installed game server instances
  --instances <blueprint>     List instances of a specific blueprint/game type
  --instances detailed      Show detailed information about all instances
  --instances --status        Show runtime status for all instances
  --instances --json          Output instance list in JSON format
  --instances --json detailed
                              Output detailed instance information in JSON format
  --instances --json --status
                              Output runtime status for all instances in JSON format
  --instances --regenerate    Regenerate files for all instances
    --management-script       Regenerate only the management scripts
    --all                     Regenerate all instance files (management, systemd, ufw, etc.)

  -i, --instance <name> COMMAND   Interact with a specific instance:

    ${UNDERLINE}Information & Monitoring:${END}
    --logs                    Display the most recent log entries
      [-f, --follow]          Continuously monitor new log entries in real-time
    --status                  Show detailed runtime status and resource usage
    --info                    Display configuration information
      [--json]                Output information in JSON format
    --is-active               Check if the instance is currently running
    --backups                 List all created backups for this instance

    ${UNDERLINE}Server Control:${END}
    --start                   Launch the server instance
    --stop                    Gracefully stop the server
    --restart                 Perform a complete stop and start sequence
    --save                    Trigger a server save operation
    --input <command>         Send a command to the server's console
                              Shows the last 10 log lines after execution

    ${UNDERLINE}Maintenance:${END}
    -v, --version             Show version information for this instance
      [--installed]           Display currently installed version
      [--latest]              Check for the latest available version
    --check-update            Check if updates are available
    --update                  Perform update process to latest version
    --create-backup           Create a backup of the current installation
    --restore-backup NAME     Restore from a previously created backup
    --modify                  Modify instance configuration or integrations
      --add OPTION            Add functionality: ufw, systemd, or symlink
      --remove OPTION         Remove functionality: ufw, systemd, or symlink
"
}

# Check for updates if configuration allows it
if [[ -n "$config_auto_update_check" && "$config_auto_update_check" == "true" ]]; then
  check_for_update
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -h | --help)
    shift
    [[ -z "$1" ]] && usage && exit 0
    case "$1" in
    --interactive)
      "$module_interactive" --description
      exit $?
      ;;
    *)
      __print_error "Invalid argument $1" && exit $EC_INVALID_ARG
      ;;
    esac
    ;;
  --interactive)
    "$module_interactive" -i
    exit $?
    ;;
  --check-update)
    check_for_update
    exit $?
    ;;
  --update)
    update_script
    exit $?
    ;;
  *)
    break
    ;;
  esac
  shift
done

module_blueprints=$(__find_module blueprints.sh)
module_config=$(__find_module config.sh)
module_directories=$(__find_module directories.sh)
module_events=$(__find_module events.sh)
module_files=$(__find_module files.sh)
module_instances=$(__find_module instances.sh)
module_lifecycle=$(__find_module lifecycle.sh)
module_migrator=$(__find_module migrator.sh)
# module_interactive is already loaded earlier

function _create() {
  local blueprint=$1
  local install_dir=$2
  # Value of 0 means get latest
  local version=$3
  # Optional identifier for the instance, if not provided, KGSM will generate one
  local identifier=${4:-}

  __print_info "Creating a new instance of $blueprint in $install_dir..."

  local instance

  # The user can pass an instance identifier instead of having KGSM generate
  # one, for ease of use or easy identification. However it's not mandatory,
  # if the user doen't pass one, the $module_instances will generate one
  # and use it without any issues.
  instance="$(
    "$module_instances" \
      --create "$blueprint" \
      --install-dir "$install_dir" \
      ${identifier:+--name $identifier}
  )"

  # Emit after the instance has been created, so we can use the identifier
  "$module_events" --emit --instance-installation-started "${instance}" "${blueprint}"

  "$module_directories" create --instance "$instance" || return $?
  "$module_files" -i "$instance" --create || return $?

  # After generating the instance and the files, we need to load the instance
  # config file so we can use the variables defined in it.
  # From this point on, we will use the instance managment file to handle
  # the next installation steps.

  __source_instance "$instance"

  if [[ "$version" == 0 ]]; then
    # shellcheck disable=SC2154
    version=$("$instance_management_file" --version --latest)
  fi

  # The instance management file doesn't emit any events, so we need to
  # emit them manually during this process

  # Download the required files for the instance
  "$module_events" --emit --instance-download-started "${instance}"
  "$instance_management_file" --download "${version}" || return $EC_FAILED_DOWNLOAD
  "$module_events" --emit --instance-download-finished "${instance}"
  "$module_events" --emit --instance-downloaded "${instance}"

  # Deploy the instance
  "$module_events" --emit --instance-deploy-started "${instance}"
  "$instance_management_file" --deploy || return $EC_FAILED_DEPLOY
  "$module_events" --emit --instance-deploy-finished "${instance}"
  "$module_events" --emit --instance-deployed "${instance}"

  # Save the new version
  "$instance_management_file" --version --save "$version" || return $EC_FAILED_VERSION_SAVE
  "$module_events" --emit --instance-version-updated "${instance}" "0" "${version}"

  "$module_events" --emit --instance-installation-finished "${instance}" "${blueprint}"

  __print_success "Instance '${instance}', version '${version}', has been created in '${install_dir}'"
  "$module_events" --emit --instance-installed "${instance}" "${blueprint}"

  return 0
}

function _remove() {
  local instance=$1

  "$module_events" --emit --instance-uninstall-started "${instance}"

  "$module_files" -i "$instance" --remove || return $?
  "$module_directories" remove --instance "$instance" || return $?
  "$module_instances" --remove "$instance" || return $?

  "$module_events" --emit --instance-uninstall-finished "${instance}"

  __print_success "Instance '${instance}' uninstalled"

  "$module_events" --emit --instance-uninstalled "${instance}"

  return 0
}

# Interactive mode function moved to modules/interactive.sh
# If it's started with no args, default to interactive mode
if [[ "$#" -eq 0 ]]; then
  "$module_interactive" -i
  exit $?
fi

# shellcheck disable=SC2199
if [[ $@ =~ "--json" ]]; then
  export json_format=1
  for a; do
    shift
    case $a in
    --json) continue ;;
    *) set -- "$@" "$a" ;;
    esac
  done
fi

# Function to handle check for required arguments and exit with error if missing
function require_arg() {
  local arg_name="$1"
  local arg_value="$2"
  local exit_code="$3"

  if [[ -z "$arg_value" ]]; then
    __print_error "Missing argument $arg_name"
    exit ${exit_code:-$EC_MISSING_ARG}
  fi
}

# Process instance creation with options
function process_create_instance() {
  shift
  require_arg "<blueprint>" "$1"

  local bp_to_install="$1"
  # shellcheck disable=SC2154
  local bp_install_dir=$config_default_install_directory
  local bp_install_version=0
  local bp_id=
  shift

  # Parse optional arguments
  while [[ $# -ne 0 ]]; do
    case "$1" in
    --install-dir)
      shift
      require_arg "<install_dir>" "$1"
      bp_install_dir="$1"
      ;;
    --version)
      shift
      require_arg "<version>" "$1"
      bp_install_version=$1
      ;;
    --name)
      shift
      require_arg "<name>" "$1"
      bp_id=$1
      ;;
    *)
      __print_error "Invalid argument $1"
      exit $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  require_arg "<dir>" "$bp_install_dir"
  _create "$bp_to_install" "$bp_install_dir" $bp_install_version $bp_id
  exit $?
}

# Process blueprint listing with options
function process_blueprints() {
  shift
  
  local filter=

  # Parse optional flags
  while [[ $# -ne 0 ]]; do
    case "$1" in
    detailed | default | custom)
      # Extract the filter name without the dashes
      filter="${1#--}"
      ;;
    *)
      __print_error "Invalid argument $1"
      exit $EC_INVALID_ARG
      ;;
    esac
    shift
  done

  "$module_blueprints" list ${filter:+$filter} ${json_format:+--json}
  exit $?
}

# Process instance listing with options
function process_instances() {
  shift
  if [[ -z "$1" ]]; then
    "$module_instances" --list
    exit $?
  fi

  local detailed=
  local status=
  local blueprint=

  # Parse optional flags and blueprint
  while [[ $# -ne 0 ]]; do
    case "$1" in
    --detailed) detailed=1 ;;
    --status) status=1 ;;
    --regenerate)
      shift
      # Handle regenerate subcommands
      case "$1" in
      --management-script)
        "$module_instances" --regenerate --management-script
        exit $?
        ;;
      --all)
        "$module_instances" --regenerate --all
        exit $?
        ;;
      *)
        __print_error "Invalid regenerate option: $1"
        __print_error "Valid options: --management-script, --all"
        exit $EC_INVALID_ARG
        ;;
      esac
      ;;
    --list) ;; # Allowed but no action needed
    *)
      blueprint=$1
      break
      ;;
    esac
    shift
  done

  "$module_instances" --list ${detailed:+--detailed} ${status:+--status} ${json_format:+--json} $blueprint
  exit $?
}

# Process instance management commands
function process_instance() {
  shift
  require_arg "<instance>" "$1"
  local instance=$1

  __source_instance "$instance"
  shift
  require_arg "[OPTION]" "$1"

  case "$1" in
  # Information & Monitoring commands
  --logs)
    shift
    local follow=""
    if [[ "$1" == "-f" || "$1" == "--follow" ]]; then
      follow="--follow"
    fi
    "$module_lifecycle" --logs "$instance" $follow
    ;;
  --status)
    shift
    local additional_flags=""

    # Process additional status flags
    while [[ $# -gt 0 ]]; do
      case "$1" in
      --json | --fast)
        additional_flags="$additional_flags $1"
        shift
        ;;
      *)
        # Put the argument back for next iteration
        set -- "$1" "$@"
        break
        ;;
      esac
    done

    "$module_instances" --status "$instance" $additional_flags
    ;;
  --info)
    "$module_instances" --info "$instance" ${json_format:+--json}
    ;;
  --is-active)
    # Inactive instances return exit code 1.
    "$module_lifecycle" --is-active "$instance"
    ;;
  --backups)
    "$instance_management_file" --list-backups
    ;;

  # Server Control commands
  --start)
    "$module_lifecycle" --start "$instance"
    ;;
  --stop)
    "$module_lifecycle" --stop "$instance"
    ;;
  --restart)
    "$module_lifecycle" --restart "$instance"
    ;;
  --save)
    "$instance_management_file" --save
    ;;
  --input)
    shift
    require_arg "<command>" "$1"
    "$module_instances" --input "$instance" "$1"
    ;;

  # Version & Updates
  -v | --version)
    shift
    if [[ -z "$1" ]]; then
      "$instance_management_file" --version
    else
      case "$1" in
      --latest)
        "$instance_management_file" --version --latest
        ;;
      *)
        __print_error "Invalid argument $1"
        exit $EC_INVALID_ARG
        ;;
      esac
    fi
    ;;
  --check-update)
    "$instance_management_file" --version --compare
    ;;
  --update)
    "$instance_management_file" --update
    ;;
  --create-backup)
    "$instance_management_file" --create-backup
    ;;
  --restore-backup)
    shift
    require_arg "<backup>" "$1"
    "$instance_management_file" --restore-backup "$1"
    ;;

  # Modification options
  --modify)
    shift
    require_arg "<option>" "$1"
    case "$1" in
    --add)
      shift
      require_arg "<option>" "$1"
      case "$1" in
      ufw | systemd | symlink | upnp)
        "$module_files" -i "$instance" --create --"$1"
        ;;
      *)
        __print_error "Invalid argument $1"
        exit $EC_INVALID_ARG
        ;;
      esac
      ;;
    --remove)
      shift
      require_arg "<option>" "$1"
      case "$1" in
      ufw | systemd | symlink | upnp)
        "$module_files" -i "$instance" --remove --"$1"
        ;;
      *)
        __print_error "Invalid argument $1"
        exit $EC_INVALID_ARG
        ;;
      esac
      ;;
    *)
      __print_error "Invalid argument $1"
      exit $EC_INVALID_ARG
      ;;
    esac
    ;;
  *)
    __print_error "Invalid argument $1"
    exit $EC_INVALID_ARG
    ;;
  esac
  exit $?
}

# Main argument processing loop
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --create | --install)
    process_create_instance "$@"
    ;;
  --remove | --uninstall)
    shift
    require_arg "<instance>" "$1"
    _remove "$1"
    exit $?
    ;;
  blueprints)
    process_blueprints "$@"
    ;;
  # General options
  --ip)
    if command -v wget >/dev/null 2>&1; then
      wget -qO- https://icanhazip.com
    else
      __print_error "wget is required but not installed"
      exit $EC_MISSING_DEPENDENCY
    fi
    exit $?
    ;;
  config)
    shift
    "$module_config" "$@"
    exit $?
    ;;
  --events)
    shift
    "$module_events" "$@"
    exit $?
    ;;
  --update)
    update_script "$@"
    exit $?
    ;;
  --migrate)
    "$module_migrator" --all
    exit $?
    ;;
  # Instance commands
  --instances)
    process_instances "$@"
    ;;
  -i | --instance)
    process_instance "$@"
    ;;

  # Version information
  -v | --version)
    echo "KGSM, version $(get_version)
Copyright (C) 2024 TheKrystalShip
License GPL-3.0: GNU GPL version 3 <https://www.gnu.org/licenses/gpl-3.0.en.html>

This is free software; you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law."
    exit 0
    ;;
  *)
    __print_error "Invalid argument $1"
    exit $EC_INVALID_ARG
    ;;
  esac
  # Prevent infinite loops
  shift
done

exit 0
