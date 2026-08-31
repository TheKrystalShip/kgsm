#!/usr/bin/env bash

# KGSM Install Module
#
# Orchestrates the installation of a new game server instance across multiple
# modules (instances, directories, files, lifecycle). This module handles the
# complete installation workflow from blueprint selection to deployed instance.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

# shellcheck source=../core/bootstrap.sh
source "$(dirname "$(readlink -f "$0")")/../core/bootstrap.sh"

self="$(basename "$0")"

# Placement is expressed in libraries: which one an instance lands in, whether
# that library is reachable, and whether it has room for the game.
# shellcheck source=handlers/libraries.sh
source "$(__find_command_handler libraries.sh)" || {
  __print_error "Failed to load libraries logic library"
  exit $EC_FAILED_SOURCE
}

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
  --library <name>            Library to place the instance in (default: the
                              configured default_library, or the sole
                              registered library)
  --version <version>         Specific version to install (default: latest)
  --name <text>               Display name for the instance: free text, shown by
                              every surface, changed later with
                              'kgsm instances rename'
  --id <id>                   Set the instance id explicitly instead of letting
                              KGSM generate one. Letters, digits, '.', '_' and
                              '-', starting with a letter or digit, max 64
  --port <port>               Override the blueprint's primary game port (1-65535)
  --skip-space-check          Install even when the library has less free space
                              than the blueprint declares the game needs
  --start                     Start the server immediately after install
  -h, --help                  Display this help information

${UNDERLINE}Description:${END}
Instances are placed at <library>/instances/<blueprint>/<instance>. Register a
library with 'kgsm libraries add <path>' and list them with
'kgsm libraries list'.

The id is what every path, file name, event and downstream store keys on, and it
never changes; KGSM generates it from the blueprint name unless --id names one.
The display name is decoration — not unique, never part of a path — and defaults
to the id.

${UNDERLINE}Examples:${END}
  ${self} factorio
  ${self} factorio --library ssd
  ${self} factorio --library ssd --name \"Ana's Factory\"
  ${self} factorio --library ssd --id factorio-prod
  ${self} factorio --library ssd --version 1.1.87
  ${self} factorio --port 34200
  ${self} factorio --start
"
}

# =============================================================================
# PLACEMENT
# =============================================================================

# Echoes the name of the library to place a new instance in, or explains why
# there is no answer. Only errors are printed, because the caller reads this
# function's stdout.
#
# Args: $1 = the name passed to --library (may be empty)
function _resolve_placement_library() {
  local requested="$1"

  # Called without a command substitution: the handler reports which of the
  # three sources answered through globals, and a subshell would lose them.
  local resolved exit_code
  __logic_library_resolve_placement "$requested" > /dev/null
  exit_code=$?
  resolved="$__library_resolve_name_out"

  case $exit_code in
    $EC_SUCCESS)
      echo "$resolved"
      ;;
    $EC_LIBRARY_NOT_FOUND)
      if [[ "$__library_resolve_source_out" == "default" ]]; then
        __print_error "The configured default library '$__library_resolve_name_out' is not registered"
        __print_error "Register it, or pick another with --library <name>"
      else
        __print_error "No library named '$__library_resolve_name_out' is registered"
        __print_error "Run 'kgsm libraries list' to see the registered ones"
      fi
      return $exit_code
      ;;
    $EC_NOT_FOUND)
      __print_error "No libraries registered; run 'kgsm libraries add <path>'"
      return $EC_LIBRARY_NOT_FOUND
      ;;
    $EC_MISSING_ARG)
      __print_error "Several libraries are registered and none was chosen"
      __print_error "Pass --library <name>, or set default_library in the KGSM config"
      return $exit_code
      ;;
    *)
      __print_error "Could not determine which library to install into"
      return $exit_code
      ;;
  esac

  if ! __logic_library_is_online "$resolved"; then
    __print_error "Library '$resolved' is not reachable at $(__logic_library_path "$resolved")"
    __print_error "Mount it, or install into another library with --library <name>"
    return $EC_LIBRARY_OFFLINE
  fi

  return $EC_SUCCESS
}

# Refuses an install a library has no room for, before anything is created.
#
# The figure compared against is the blueprint's advisory base_disk_mb plus the
# configured margin. A blueprint that declares none leaves nothing to compare,
# and the install proceeds with that said out loud rather than on a number
# nobody measured.
#
# Args: $1 = blueprint, $2 = library name, $3 = library root, $4 = skip flag
function _space_gate() {
  local blueprint="$1"
  local library="$2"
  local library_dir="$3"
  local skip="$4"

  local blueprint_abs_path base_disk_mb=""
  if blueprint_abs_path="$(__find_blueprint "$blueprint")" &&
    command -v yq > /dev/null 2>&1; then
    base_disk_mb="$(yq -r '.metadata.base_disk_mb // ""' "$blueprint_abs_path" 2> /dev/null)"
  fi

  # shellcheck disable=SC2154
  local margin_mb="${config_install_free_space_margin_mb:-1024}"
  [[ "$margin_mb" =~ ^[0-9]+$ ]] || margin_mb=1024

  local exit_code
  __logic_library_space_check "$library_dir" "$base_disk_mb" "$margin_mb"
  exit_code=$?

  case $exit_code in
    $EC_SUCCESS)
      return 0
      ;;
    $EC_NOT_FOUND)
      __print_warning "Blueprint '$blueprint' declares no base_disk_mb; free space was not checked"
      return 0
      ;;
    $EC_INSUFFICIENT_DISK)
      local free_mb=$((__library_space_free_out / 1024 / 1024))
      local required_mb=$((__library_space_required_out / 1024 / 1024))
      local message="Library '$library' has ${free_mb}MB free at ${library_dir}; $blueprint needs ${base_disk_mb}MB plus a ${margin_mb}MB margin (${required_mb}MB)"

      if [[ "$skip" == true ]]; then
        __print_warning "$message"
        __print_warning "Installing anyway (--skip-space-check)"
        return 0
      fi

      __print_error "$message"
      __print_error "Free space in that library, install into another with --library <name>, or pass --skip-space-check"
      return $EC_INSUFFICIENT_DISK
      ;;
    *)
      __print_warning "Could not measure free space in library '$library'; free space was not checked"
      return 0
      ;;
  esac
}

# Refuses an install this account cannot complete or that no unit on the host
# would see.
#
# The engine derives its entire world from the invoking account: instances,
# blueprints, the library registry and the config all hang off that account's
# XDG paths. The event journal does not — it is one host-wide directory every
# producer appends to and every consumer tails. On a host where units run as a
# service account, those two facts are what disagree when the engine is run by
# somebody else: the install lands in a home the service account cannot enter,
# while the journal it must append to belongs to an account this one is not.
#
# The journal is the check because it is the shared thing, and its OWNER is what
# the check reads. Every account has its own instance registry under its own XDG
# paths, so a unit running as the journal's owner enumerates that account's
# registry and no other: an install by anybody else is invisible to it however
# the permissions are set. Writability cannot answer this — granting write on the
# journal by ACL, which is the narrowest and most careful way to unblock a
# person, lets the events through while leaving the instance in a registry the
# services never read. Ownership is the property that identifies whose registry
# this host's services actually enumerate.
#
# Writability is still asked, but only for the account that already owns the
# journal, where nothing is misdirected and a failed write is what it looks like.
#
# Absent journal directory is not a failure: a host that has never emitted an
# event, and a sandbox pointing event_journal_dir somewhere temporary, both
# arrive here legitimately.
function _ownership_gate() {
  # The journal dir is resolved by the events handler, which is otherwise loaded
  # lazily on the first emit — later than this gate, which has to run before
  # anything is created.
  if ! declare -F __logic_journal_dir > /dev/null; then
    # shellcheck source=handlers/events.sh
    source "$(__find_command_handler events.sh)" || return 0
  fi

  local journal_dir
  journal_dir="$(__logic_journal_dir)" || return 0

  [[ -d "$journal_dir" ]] || return 0

  local owner me
  owner="$(stat -c '%U' "$journal_dir" 2> /dev/null)" || owner=""
  me="$(id -un)"

  # Another account owns the shared journal, so this host's units run as that
  # account and enumerate its registry. Nothing this install creates lands
  # there. Decided before writability is looked at, because being able to write
  # the journal says only that the events would be recorded — never that the
  # instance they describe would be visible to anything that reads them.
  if [[ -n "$owner" ]] && [[ "$owner" != "$me" ]]; then
    __print_error "The event journal at ${journal_dir} belongs to '${owner}', and this install is running as '${me}'"
    __print_error "This host's KGSM services run as '${owner}' and enumerate that account's instances — an install run as '${me}' is recorded in a different registry and is invisible to all of them"
    __print_error "Run the engine as that account: sudo -u ${owner} -H kgsm install ${1:-<blueprint>}"
    return $EC_PERMISSION
  fi

  # The owning account, or a host with no owner to read: only the directory's
  # own permissions can stop the install being recorded.
  [[ -w "$journal_dir" ]] && return 0

  __print_error "The event journal at ${journal_dir} is not writable by '${me}'"
  __print_error "Restore write permission on it, or point event_journal_dir at a directory this account can write"

  return $EC_PERMISSION
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

  local library=""
  local version=0 # 0 means get latest
  local instance_id=""
  local display_name=""
  local port=""
  # Every failure below is reported by its own status, captured before anything else runs: a printer
  # succeeds, so reading $? after one reports that the step it was complaining about worked.
  local exit_code=0
  local start_after=false
  local skip_space_check=false

  # Parse optional arguments
  while [[ $# -ne 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage
        return 0
        ;;
      --port)
        shift
        if [[ -z "$1" ]]; then
          __print_error "Missing argument for --port"
          return $EC_MISSING_ARG
        fi
        if ! [[ "$1" =~ ^[0-9]+$ ]] || ((10#$1 < 1 || 10#$1 > 65535)); then
          __print_error "Invalid --port '$1' (expected 1-65535)"
          return $EC_INVALID_ARG
        fi
        port="$1"
        ;;
      --library)
        shift
        if [[ -z "$1" ]]; then
          __print_error "Missing argument for --library"
          return $EC_MISSING_ARG
        fi
        library="$1"
        ;;
      --skip-space-check)
        skip_space_check=true
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
        display_name=$1
        ;;
      --id)
        shift
        if [[ -z "$1" ]]; then
          __print_error "Missing argument for --id"
          return $EC_MISSING_ARG
        fi
        validate_instance_id_format "$1" || return $EC_INVALID_ARG
        instance_id=$1
        ;;
      --start)
        start_after=true
        ;;
      *)
        __print_error "Invalid argument: $1"
        return $EC_INVALID_ARG
        ;;
    esac
    shift
  done

  # Before the library is resolved and before anything is created: an account
  # that cannot record this install is an account whose instances no unit on
  # this host reads.
  _ownership_gate "$blueprint" || return $?

  library="$(_resolve_placement_library "$library")" || return $?

  local library_dir
  library_dir="$(__logic_library_path "$library")"

  _space_gate "$blueprint" "$library" "$library_dir" "$skip_space_check" || return $?

  __print_info "Creating a new instance of $blueprint in library '$library' ($library_dir)..."

  # Settle the id early (before any config/file creation): every directory, file
  # name and symlink below is derived from it. Assembled as an array because a
  # display name holds spaces, and an unquoted expansion would hand each word to
  # the command as its own argument.
  local -a generate_args=("$blueprint")
  [[ -n "$instance_id" ]] && generate_args+=(--id "$instance_id")

  local instance
  instance="$(instances.sh generate-id "${generate_args[@]}")" || {
    exit_code=$?
    __print_error "Failed to generate instance identifier"
    return $exit_code
  }

  # The id is settled but not yet trusted. Everything below turns it into a
  # directory, a symlink and a config file name, so a value that is not a legal
  # id must stop here rather than become a path.
  validate_instance_id_format "$instance" || {
    exit_code=$?
    __print_error "Refusing to install: the instance identifier is not usable"
    return $exit_code
  }

  # Calculate working directory path inside the library
  local working_dir
  working_dir="$(__library_instances_subdir "$library_dir")/${blueprint}/${instance}"

  # Create the working directory first (symlink target must exist)
  directories.sh ensure-created "$working_dir" || {
    exit_code=$?
    __print_error "Failed to create instance working directory: $working_dir"
    return $exit_code
  }

  # Create symlink from KGSM instances directory to working directory
  # This must happen before instance config creation so the config can be
  # written through the symlink into the actual working directory
  directories.sh link-instance "$blueprint" "$instance" "$working_dir" || {
    exit_code=$?
    __print_error "Failed to create instance symlink"
    return $exit_code
  }

  # Create instance configuration (name is now pre-determined)
  # Config will be created at $KGSM_INSTANCES_DIR/$blueprint/$instance/$instance.config.ini
  # which resolves through the symlink to $working_dir/$instance.config.ini
  local -a create_args=("$blueprint" --library "$library" --id "$instance")
  [[ -n "$display_name" ]] && create_args+=(--name "$display_name")
  [[ -n "$port" ]] && create_args+=(--port "$port")

  instance="$(instances.sh create "${create_args[@]}")" || {
    exit_code=$?
    __print_error "Failed to create instance configuration"
    # Clean up on failure
    directories.sh unlink-instance "$blueprint" "$instance" 2>/dev/null || true
    rm -rf "$working_dir" 2>/dev/null || true
    return $exit_code
  }


  # Emit after the instance has been created, so we can use the identifier
  __emit_event server.install.started "${instance}" "${blueprint}"

  # Create directory structure
  directories.sh create "$instance" || {
    exit_code=$?
    __print_error "Failed to create directory structure"
    return $exit_code
  }

  # Create instance files
  files.sh create "$instance" || {
    exit_code=$?
    __print_error "Failed to create instance files"
    return $exit_code
  }

  # Load instance config to access variables
  __source_instance "$instance"

  # Determine version. A remote that cannot be reached ends the install here:
  # carrying on would record an empty version, and an instance whose recorded
  # version is empty can never be compared against anything afterwards.
  if [[ "$version" == 0 ]]; then
    # shellcheck disable=SC2154
    version=$("$instance_management_file" version --latest)

    if [[ -z "$version" ]]; then
      __print_error "Could not determine the latest version to install"
      return $EC_FAILED_VERSION_SAVE
    fi
  fi

  # Download game files
  __emit_event server.download.started "${instance}"
  "$instance_management_file" download "${version}" || {
    __print_error "Failed to download game files"
    __emit_event server.download.failed "${instance}"
    return $EC_FAILED_DOWNLOAD
  }
  __emit_event server.download.finished "${instance}"
  __emit_event server.download.completed "${instance}"

  # Deploy the instance
  __emit_event server.deploy.started "${instance}"
  "$instance_management_file" deploy || {
    __print_error "Failed to deploy instance"
    __emit_event server.deploy.failed "${instance}"
    return $EC_FAILED_DEPLOY
  }
  __emit_event server.deploy.finished "${instance}"
  __emit_event server.deploy.completed "${instance}"

  # Save version. No server.updated here: that event states that an
  # existing instance moved from one build to another, and a fresh install has
  # no build to move from. The version an install lands on is part of the
  # instance the following events announce, readable from the instance itself.
  "$instance_management_file" version --save "$version" || {
    __print_error "Failed to save version information"
    return $EC_FAILED_VERSION_SAVE
  }

  __print_success "Instance '${instance}', version '${version}', has been created in '${working_dir}'"
  __emit_event server.installed "${instance}" "${blueprint}" "${library}"

  # Emitted LAST, after server.installed: a consumer that reads "the run ended"
  # and re-reads the roster must find the new instance already there rather than
  # the roster as it was before it. Same ordering as every other bracket.
  __emit_event server.install.finished "${instance}" "${blueprint}"

  # Start immediately after install when --start was passed (one-shot start,
  # not watchdog boot-autostart). A failure to start does not invalidate the
  # install — the server remains installed and can be started later.
  if [[ "$start_after" == true ]]; then
    lifecycle.sh start "$instance" || {
      __print_warning "Install succeeded but start failed; start the server manually."
    }
  fi

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
