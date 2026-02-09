#!/usr/bin/env bash

# KGSM Install Module
#
# Orchestrates the installation of a new game server instance across multiple
# modules (instances, directories, files, lifecycle). This module handles the
# complete installation workflow from blueprint selection to deployed instance.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# =============================================================================
# HELP / USAGE FUNCTIONS
# =============================================================================

function show_usage() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Install Module for Krystal Game Server Manager${END}

Install a new game server instance from a blueprint.

${UNDERLINE}Usage:${END}
  ${self} <blueprint> [options]

${UNDERLINE}Arguments:${END}
  <blueprint>                 Blueprint name to install from

${UNDERLINE}Options:${END}
  --install-dir <path>        Installation directory (default: from config)
  --version <version>         Specific version to install (default: latest)
  --name <name>               Custom instance name (default: auto-generated)
  -h, --help                  Display this help information

${UNDERLINE}Examples:${END}
  ${self} factorio
  ${self} factorio --install-dir /opt/servers
  ${self} factorio --install-dir /opt/servers --name factorio-prod
  ${self} factorio --install-dir /opt/servers --version 1.1.87
"
}

# =============================================================================
# MAIN INSTALL FUNCTION
# =============================================================================

function _cmd_install() {
  local blueprint=$1
  shift

  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    show_usage
    return $EC_MISSING_ARG
  fi

  # shellcheck disable=SC2154
  local install_dir=$config_default_install_directory
  local version=0 # 0 means get latest
  local identifier

  # Parse optional arguments
  while [[ $# -ne 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage
        return 0
        ;;
      --install-dir)
        shift
        if [[ -z "$1" ]]; then
          __print_error "Missing argument for --install-dir"
          return $EC_MISSING_ARG
        fi
        install_dir="$1"
        ;;
      --version)
        shift
        if [[ -z "$1" ]]; then
          __print_error "Missing argument for --version"
          return $EC_MISSING_ARG
        fi
        version=$1
        ;;
      --name)
        shift
        if [[ -z "$1" ]]; then
          __print_error "Missing argument for --name"
          return $EC_MISSING_ARG
        fi
        identifier=$1
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  if [[ -z "$install_dir" ]]; then
    __print_error "Installation directory not specified and no default configured"
    return $EC_MISSING_ARG
  fi

  # Check if install_dir is relative or absolute path
  if [[ "$install_dir" != /* ]]; then
    install_dir="${KGSM_ROOT}/$install_dir"
  fi

  __print_info "Creating a new instance of $blueprint in $install_dir..."

  directories.sh ensure-created "$install_dir" || {
    __print_error "Failed to ensure installation directory exists and is writable: $install_dir"
    return $?
  }

  # Generate instance name early (before any config/file creation)
  local instance
  instance="$(instances.sh generate-id "$blueprint" ${identifier:+--name $identifier})" || {
    exit_code=$?
    __print_error "Failed to generate instance identifier"
    return $exit_code
  }

  # Calculate working directory path
  local working_dir="${install_dir}/${blueprint}/${instance}"

  # Create the working directory first (symlink target must exist)
  directories.sh ensure-created "$working_dir" || {
    __print_error "Failed to create instance working directory: $working_dir"
    return $?
  }

  # Create symlink from KGSM instances directory to working directory
  # This must happen before instance config creation so the config can be
  # written through the symlink into the actual working directory
  directories.sh link-instance "$blueprint" "$instance" "$working_dir" || {
    __print_error "Failed to create instance symlink"
    return $?
  }

  # Create instance configuration (name is now pre-determined)
  # Config will be created at $KGSM_INSTANCES_DIR/$blueprint/$instance/$instance.config.ini
  # which resolves through the symlink to $working_dir/$instance.config.ini
  instance="$(instances.sh create "$blueprint" --install-dir "$install_dir" --name "$instance")" || {
    exit_code=$?
    __print_error "Failed to create instance configuration"
    # Clean up on failure
    directories.sh unlink-instance "$blueprint" "$instance" 2>/dev/null || true
    rm -rf "$working_dir" 2>/dev/null || true
    return $exit_code
  }


  # Emit after the instance has been created, so we can use the identifier
  events.sh emit instance-installation-started "${instance}" "${blueprint}"

  # Create directory structure
  directories.sh create "$instance" || {
    __print_error "Failed to create directory structure"
    return $?
  }

  # Create instance files
  files.sh create "$instance" || {
    __print_error "Failed to create instance files"
    return $?
  }

  # Load instance config to access variables
  __source_instance "$instance"

  # Determine version
  if [[ "$version" == 0 ]]; then
    # shellcheck disable=SC2154
    version=$("$instance_management_file" --version --latest)
  fi

  # Download game files
  events.sh emit instance-download-started "${instance}"
  "$instance_management_file" --download "${version}" || {
    __print_error "Failed to download game files"
    events.sh emit instance-download-failed "${instance}"
    return $EC_FAILED_DOWNLOAD
  }
  events.sh emit instance-download-finished "${instance}"
  events.sh emit instance-downloaded "${instance}"

  # Deploy the instance
  events.sh emit instance-deploy-started "${instance}"
  "$instance_management_file" --deploy || {
    __print_error "Failed to deploy instance"
    events.sh emit instance-deploy-failed "${instance}"
    return $EC_FAILED_DEPLOY
  }
  events.sh emit instance-deploy-finished "${instance}"
  events.sh emit instance-deployed "${instance}"

  # Save version
  "$instance_management_file" --version --save "$version" || {
    __print_error "Failed to save version information"
    return $EC_FAILED_VERSION_SAVE
  }
  events.sh emit instance-version-updated "${instance}" "0" "${version}"

  events.sh emit instance-installation-finished "${instance}" "${blueprint}"

  __print_success "Instance '${instance}', version '${version}', has been created in '${install_dir}'"
  events.sh emit instance-installed "${instance}" "${blueprint}"

  return 0
}

# Handle help flag before positional arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h | --help | help)
      show_usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
  shift
done

# Execute installation
_cmd_install "$@"
exit $?
