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

  echo -e "${UNDERLINE}Blueprint Management for Krystal Game Server Manager${END}

Manages game server blueprints - the templates used to create server instances.

${UNDERLINE}Usage:${END}
  $self [command] [arguments] [options]

${UNDERLINE}Commands:${END}
  list [filter]               List available blueprints
  info <blueprint>            Display blueprint contents
  find <blueprint>            Get blueprint file path
  validate <blueprint|path>   Check a blueprint's format
  help [command]              Show help information

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  -h, --help                  Show help and exit

${UNDERLINE}Examples:${END}
  $self list
  $self list default
  $self list custom
  $self list detailed
  $self list --json
  $self info factorio
  $self info terraria --json
  $self find minecraft
  $self find minecraft --all
  $self validate factorio
  $self validate /tmp/draft.bp.yaml --json
  $self help list

${UNDERLINE}Notes:${END}
  • Blueprints define server configuration templates
  • Use 'default' filter to show official blueprints
  • Use 'custom' filter to show user-created blueprints
  • Create new blueprints by copying templates/blueprint.tp
  • Both native and container blueprints are supported
"
}

function show_usage_list() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}List Blueprints${END}

List all available game server blueprints with optional filtering.

${UNDERLINE}Usage:${END}
  $self list [filter] [options]

${UNDERLINE}Filters:${END}
  (none)                      List all blueprints
  default                     Show only official default blueprints
  custom                      Show only user-created custom blueprints
  detailed                    Show detailed information for each blueprint

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Lists available blueprints from both native and container directories.
Default blueprints are provided by KGSM, while custom blueprints are
user-created. The detailed filter shows additional metadata for each blueprint.

${UNDERLINE}Examples:${END}
  $self list
  $self list default
  $self list custom --json
  $self list detailed
"
}

function show_usage_info() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Blueprint Info${END}

Display the contents of a specific blueprint file.

${UNDERLINE}Usage:${END}
  $self info <blueprint> [options]

${UNDERLINE}Arguments:${END}
  blueprint                   Name of the blueprint to display

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Displays the complete contents of a blueprint file, including all
configuration parameters. Blueprints are unified <name>.bp.yaml files;
the runtime field distinguishes native from container.

${UNDERLINE}Examples:${END}
  $self info factorio
  $self info terraria --json
  $self info minecraft
"
}

function show_usage_find() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Find Blueprint${END}

Locate the absolute path to a blueprint file.

${UNDERLINE}Usage:${END}
  $self find <blueprint> [options]

${UNDERLINE}Arguments:${END}
  blueprint                   Name of the blueprint to find

${UNDERLINE}Options:${END}
  --all                       Show every path the name could resolve to
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Returns the absolute file path to the specified blueprint. This is
useful for scripting and debugging. The command validates that the
blueprint exists and is valid before returning the path.

With --all or --json, every candidate path is reported in precedence
order (user before system) along with whether it exists, so a caller can
tell a custom blueprint apart from a user copy shadowing a shipped one.
These modes report on existence alone and skip the format check — a
malformed blueprint still has to be findable in order to be repaired.

${UNDERLINE}Examples:${END}
  $self find factorio
  $self find terraria
  $self find factorio --all
  $self find factorio --json
  path=\$($self find minecraft)
"
}

function show_usage_validate() {
  local UNDERLINE="\e[4m"
  local END="\e[0m"

  echo -e "${UNDERLINE}Validate Blueprint${END}

Check a blueprint's format and required fields.

${UNDERLINE}Usage:${END}
  $self validate <blueprint|path> [options]

${UNDERLINE}Arguments:${END}
  blueprint|path              Blueprint name, or a path to a blueprint file

${UNDERLINE}Options:${END}
  --json                      Output in JSON format
  --help                      Display this help information

${UNDERLINE}Description:${END}
Checks YAML syntax and required fields: 'name' and 'runtime' on every
blueprint, 'native.executable_file' for native ones, and a
'container.compose' with at least one service — all on 'network_mode:
host' — for container ones.

An argument naming an existing file is checked as a path; anything else
is resolved as a blueprint name. The path form allows a file to be
checked before it is committed under a blueprint's real name.

Nothing is written and no event is emitted. --json reports every problem
found rather than only the first:

  { \"Valid\": false, \"Path\": \"...\", \"Errors\": [\"...\"] }

${UNDERLINE}Examples:${END}
  $self validate factorio
  $self validate vrising --json
  $self validate /tmp/draft.bp.yaml --json
"
}

# Source logic library
logic_library=$(__find_command_handler blueprints.sh)
# shellcheck source=handlers/blueprints.sh
source "$logic_library" || {
  __print_error "Failed to load blueprints logic library"
  exit $EC_FAILED_SOURCE
}

# Command handler functions
function _cmd_list() {
  local filter=""
  local json_opt=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_list
        return 0
        ;;
      --json)
        json_opt="--json"
        shift
        ;;
      default | custom | detailed)
        filter="$1"
        shift
        ;;
      *)
        __print_error "Invalid argument: $1"
        __print_error "Use '$self list --help' for usage information"
        return $EC_INVALID_ARG
        ;;
    esac
  done

  # Map the user-facing filter to a discovery source. `detailed` is a
  # presentation mode over the full (all) set.
  local source="all"
  case "$filter" in
    default) source="default" ;;
    custom) source="custom" ;;
  esac

  local names
  names=$(__logic_list_blueprints "$source" 2> /dev/null)

  if [[ "$filter" == "detailed" ]]; then
    local name info rc
    if [[ -n "$json_opt" ]]; then
      # Object keyed by blueprint name -> full info object.
      local obj="{}"
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        info=$(__logic_get_blueprint_info_json "$name" 2> /dev/null)
        # The handler signals success via EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED
        # (a 200-range event code), not 0 — only a genuine error skips the entry.
        rc=$?
        [[ $rc -ne 0 && $rc -ne $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED ]] && continue
        obj=$(jq --arg k "$name" --argjson v "$info" '. + {($k): $v}' <<< "$obj")
      done <<< "$names"
      echo "$obj"
    else
      # One human-readable line per blueprint: name, runtime, display name.
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        info=$(__logic_get_blueprint_info_json "$name" 2> /dev/null)
        # The handler signals success via EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED
        # (a 200-range event code), not 0 — only a genuine error skips the entry.
        rc=$?
        [[ $rc -ne 0 && $rc -ne $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED ]] && continue
        echo "$info" | jq -r '"\(.Name)\t\(.BlueprintType)\t\(.Metadata.DisplayName // "—")"'
      done <<< "$names"
    fi
  elif [[ -n "$json_opt" ]]; then
    if [[ -z "$names" ]]; then
      echo "[]"
    else
      printf '%s\n' "$names" | jq -R . | jq -s 'map(select(length > 0))'
    fi
  else
    [[ -n "$names" ]] && printf '%s\n' "$names"
  fi

  __dispatch_event_from_exit_code $EC_SUCCESS_BLUEPRINT_LISTED "system" "all" > /dev/null 2>&1
  return 0
}

function _cmd_info() {
  local blueprint=""
  local json_opt=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_info
        return 0
        ;;
      --json)
        json_opt="--json"
        ;;
      -*)
        __print_error "Invalid option: $1"
        __print_error "Use '$self info --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        blueprint="$1"
        ;;
    esac
    shift
  done

  # Validate blueprint argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '$self info --help' for usage information"
    return $EC_MISSING_ARG
  fi

  # Validate blueprint exists
  validate_blueprint "$blueprint"
  local validation_result=$?
  if [[ $validation_result -ne 0 ]]; then
    return $validation_result
  fi

  if [[ -n "$json_opt" ]]; then
    # Canonical JSON object (with the nested Metadata block).
    __logic_get_blueprint_info_json "$blueprint"
    if [[ $? -ne $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED ]]; then
      __print_error "Blueprint not found: $blueprint"
      return $EC_BLUEPRINT_NOT_FOUND
    fi
  else
    # Human view: the raw unified blueprint file.
    local blueprint_path
    if ! blueprint_path=$(__find_blueprint "$blueprint"); then
      __print_error "Blueprint not found: $blueprint"
      return $EC_BLUEPRINT_NOT_FOUND
    fi
    cat "$blueprint_path"
  fi

  __dispatch_event_from_exit_code $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED "system" "$blueprint" > /dev/null 2>&1
  return 0
}

function _cmd_find() {
  local blueprint=""
  local all_opt=""
  local json_opt=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_find
        return 0
        ;;
      --all)
        all_opt="--all"
        ;;
      --json)
        json_opt="--json"
        ;;
      -*)
        __print_error "Invalid option: $1"
        __print_error "Use '$self find --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        blueprint="$1"
        ;;
    esac
    shift
  done

  # Validate blueprint argument
  if [[ -z "$blueprint" ]]; then
    __print_error "Missing required argument: <blueprint>"
    __print_error "Use '$self find --help' for usage information"
    return $EC_MISSING_ARG
  fi

  # Candidate reporting answers "where could this live, and what is actually
  # there" — existence only, no format check, so a malformed blueprint can
  # still be located and repaired.
  if [[ -n "$all_opt" || -n "$json_opt" ]]; then
    local candidates
    candidates=$(__logic_get_blueprint_candidates_json "$blueprint")
    local candidates_result=$?

    if [[ $candidates_result -ne $EC_SUCCESS_BLUEPRINT_FOUND ]]; then
      __print_error "Blueprint not found: $blueprint"
      return $EC_BLUEPRINT_NOT_FOUND
    fi

    if [[ -n "$json_opt" ]]; then
      echo "$candidates"
    else
      echo "$candidates" \
        | jq -r '.Candidates[] | "\(.Tier)\t\(.Path)\t\(.Exists)"'
    fi

    __dispatch_event_from_exit_code $EC_SUCCESS_BLUEPRINT_FOUND "system" "$blueprint" > /dev/null 2>&1
    return 0
  fi

  # Validate blueprint exists
  validate_blueprint "$blueprint"
  local validation_result=$?
  if [[ $validation_result -ne 0 ]]; then
    return $validation_result
  fi

  # Get blueprint path
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint")
  echo "$blueprint_path"
  __dispatch_event_from_exit_code $EC_SUCCESS_BLUEPRINT_FOUND "system" "$blueprint" > /dev/null 2>&1
  return 0
}

function _cmd_validate() {
  local target=""
  local json_opt=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help | help)
        show_usage_validate
        return 0
        ;;
      --json)
        json_opt="--json"
        ;;
      -*)
        __print_error "Invalid option: $1"
        __print_error "Use '$self validate --help' for usage information"
        return $EC_INVALID_ARG
        ;;
      *)
        target="$1"
        ;;
    esac
    shift
  done

  # Validate target argument
  if [[ -z "$target" ]]; then
    __print_error "Missing required argument: <blueprint|path>"
    __print_error "Use '$self validate --help' for usage information"
    return $EC_MISSING_ARG
  fi

  local blueprint_path
  if ! blueprint_path=$(__logic_resolve_blueprint_target "$target"); then
    __print_error "Blueprint not found: $target"
    __print_error "Searched in:"
    __print_error "  - User: $KGSM_USER_BLUEPRINTS_DIR"
    __print_error "  - System: $KGSM_SYSTEM_BLUEPRINTS_DIR"
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  if [[ ! -r "$blueprint_path" ]]; then
    __print_error "Blueprint file is not readable: $blueprint_path"
    return $EC_PERMISSION
  fi

  local verdict_result
  if [[ -n "$json_opt" ]]; then
    # The verdict object carries the errors, so the validator's own stderr
    # would only duplicate them.
    __logic_get_blueprint_validation_json "$blueprint_path"
    verdict_result=$?
  else
    # Human mode: every problem is printed by the validator as it is found.
    validate_blueprint_format "$blueprint_path"
    verdict_result=$?
    if [[ $verdict_result -eq 0 ]]; then
      verdict_result=$EC_SUCCESS_BLUEPRINT_VALIDATED
      __print_success "Blueprint is valid: $blueprint_path"
    elif [[ $verdict_result -ne $EC_MISSING_DEPENDENCY ]]; then
      verdict_result=$EC_INVALID_BLUEPRINT
    fi
  fi

  if [[ $verdict_result -ne $EC_SUCCESS_BLUEPRINT_VALIDATED ]]; then
    return $verdict_result
  fi

  __dispatch_event_from_exit_code $EC_SUCCESS_BLUEPRINT_VALIDATED "system" "$target" > /dev/null 2>&1
  return 0
}

function _cmd_help() {
  local command="$1"

  if [[ -z "$command" ]]; then
    show_usage
    return 0
  fi

  case "$command" in
    list)
      show_usage_list
      ;;
    info)
      show_usage_info
      ;;
    find)
      show_usage_find
      ;;
    validate)
      show_usage_validate
      ;;
    *)
      __print_error "Unknown command: $command"
      __print_error "Use '$self help' for available commands"
      return $EC_INVALID_ARG
      ;;
  esac

  return 0
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
  list)
    # `list detailed[ --json]` reads metadata via yq; `info` always does.
    __require_yq || exit $EC_MISSING_DEPENDENCY
    _cmd_list "$@"
    exit $?
    ;;
  info)
    __require_yq || exit $EC_MISSING_DEPENDENCY
    _cmd_info "$@"
    exit $?
    ;;
  find)
    # `find --all|--json` reads the candidate set via jq; the plain form does
    # not, so yq/jq are only required for the structured modes.
    _cmd_find "$@"
    exit $?
    ;;
  validate)
    __require_yq || exit $EC_MISSING_DEPENDENCY
    _cmd_validate "$@"
    exit $?
    ;;
  *)
    __print_error "Unknown command: $command"
    __print_error "Use '$self help' for available commands"
    exit $EC_INVALID_ARG
    ;;
esac
