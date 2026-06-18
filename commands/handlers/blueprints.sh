#!/usr/bin/env bash

# KGSM Pure Logic Layer - Blueprint Management
#
# This module contains pure business logic functions for blueprint operations.
# These functions have no user-facing I/O and communicate results only via exit codes.
#
# Exit Code Conventions:
# - 0: Success (no event needed)
# - Standard error codes: EC_BLUEPRINT_NOT_FOUND, EC_INVALID_BLUEPRINT, EC_PERMISSION, etc.
#
# Blueprints are unified `<name>.bp.yaml` files in a single flat directory; the
# `runtime` field (native|container) discriminates the body. This handler reads
# them via yq — there is no longer a native/container split at the file level.

# Disabling SC2086 globally:
# Exit code variables are guaranteed to be numeric and safe for unquoted use.
# shellcheck disable=SC2086

if [[ -z "${KGSM_BLUEPRINT_TYPE_NATIVE}" ]]; then
  declare -g -r KGSM_BLUEPRINT_TYPE_NATIVE="native"
  export KGSM_BLUEPRINT_TYPE_NATIVE
fi

if [[ -z "${KGSM_BLUEPRINT_TYPE_CONTAINER}" ]]; then
  declare -g -r KGSM_BLUEPRINT_TYPE_CONTAINER="container"
  export KGSM_BLUEPRINT_TYPE_CONTAINER
fi

# Validates a blueprint name and returns its type (native or container)
# Args: $1 = blueprint_name
# Returns: 0 and echoes "native" or "container", or error code on failure
function __logic_get_blueprint_type() {
  local blueprint_name="$1"

  # Validate parameter
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate blueprint exists (using existing validation from core/validation.sh)
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint_name" 2> /dev/null)
  local validation_result=$?

  if [[ $validation_result -ne 0 ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Determine blueprint type from the `runtime` field (no longer the extension)
  local runtime
  runtime=$(yq -r '.runtime // ""' "$blueprint_path" 2>/dev/null)
  case "$runtime" in
    native)
      echo "$KGSM_BLUEPRINT_TYPE_NATIVE"
      return 0
      ;;
    container)
      echo "$KGSM_BLUEPRINT_TYPE_CONTAINER"
      return 0
      ;;
    *)
      return $EC_INVALID_BLUEPRINT
      ;;
  esac
}

export -f __logic_get_blueprint_type

# Validates that a blueprint exists and is properly formatted
# Args: $1 = blueprint_name
# Returns: 0 on success, error codes on failure
function __logic_validate_blueprint() {
  local blueprint_name="$1"

  # Validate parameter
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # This checks existence, readability, and format
  validate_blueprint "$blueprint_name" > /dev/null 2>&1
  exit_code=$?

  # Convert file not found to blueprint not found for consistency
  if [[ $exit_code -eq $EC_FILE_NOT_FOUND ]]; then
    exit_code=$EC_BLUEPRINT_NOT_FOUND
  fi

  return $exit_code
}

export -f __logic_validate_blueprint

# Gets the absolute path to a blueprint file
# Args: $1 = blueprint_name
# Returns: 0 and echoes path, or error code on failure
function __logic_get_blueprint_path() {
  local blueprint_name="$1"

  # Validate parameter
  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  # Validate blueprint and get path
  local blueprint_path
  blueprint_path=$(validate_blueprint_exists "$blueprint_name" 2> /dev/null)
  local validation_result=$?

  if [[ $validation_result -ne 0 ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  # Validate the blueprint is readable and properly formatted
  if ! validate_blueprint "$blueprint_name" > /dev/null 2>&1; then
    return $EC_INVALID_BLUEPRINT
  fi

  echo "$blueprint_path"
  return 0
}

export -f __logic_get_blueprint_path

# Lists blueprints by logical name from the unified flat directory.
# Args: $1 = source ("custom", "default", or "all") - optional, defaults to "all"
#       custom  -> user blueprints only ($KGSM_USER_BLUEPRINTS_DIR)
#       default -> system blueprints only ($KGSM_SYSTEM_BLUEPRINTS_DIR)
#       all     -> both (a user blueprint shadows a same-named system one)
# Returns: Success code and echoes newline-separated, de-duplicated list.
function __logic_list_blueprints() {
  local source="${1:-all}"

  local -a dirs=()
  case "$source" in
    custom) dirs=("$KGSM_USER_BLUEPRINTS_DIR") ;;
    default) dirs=("$KGSM_SYSTEM_BLUEPRINTS_DIR") ;;
    all | "") dirs=("$KGSM_USER_BLUEPRINTS_DIR" "$KGSM_SYSTEM_BLUEPRINTS_DIR") ;;
    *) return $EC_INVALID_ARG ;;
  esac

  local -a names=()
  local dir file base
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do
      base="${file##*/}"
      base="${base%.bp.yaml}"
      [[ -n "$base" ]] && names+=("$base")
    done < <(find "$dir" -maxdepth 1 -name "*.bp.yaml" -type f -print0 2>/dev/null)
  done

  if [[ ${#names[@]} -gt 0 ]]; then
    printf "%s\n" "${names[@]}" | sort -u
  fi

  return $EC_SUCCESS_BLUEPRINT_LISTED
}

export -f __logic_list_blueprints

# =============================================================================
# UNIFIED BLUEPRINT INFO
# =============================================================================

# Emits a blueprint's info as the canonical PascalCase JSON object, including the
# nested `Metadata` block. Reads the unified `.bp.yaml` directly (yq + jq) so the
# advisory metadata numbers keep their real types — unknown values serialize as
# JSON `null`, never an empty string or a fabricated 0.
# Args: $1 = blueprint_name
# Returns: EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED and echoes JSON, or an error code.
# The blueprint_* variables below are populated dynamically by __source_blueprint.
# shellcheck disable=SC2154
function __logic_get_blueprint_info_json() {
  local blueprint="$1"

  if [[ -z "$blueprint" ]]; then
    return $EC_INVALID_ARG
  fi

  local blueprint_path
  if ! blueprint_path=$(__find_blueprint "$blueprint"); then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  if [[ ! -r "$blueprint_path" ]]; then
    return $EC_PERMISSION
  fi

  # Populate blueprint_* (runtime-aware: native fields filled for native, empty
  # for container; ports derived from the embedded compose for container).
  if ! __source_blueprint "$blueprint_path" >/dev/null 2>&1; then
    return $EC_INVALID_BLUEPRINT
  fi

  local blueprint_type="Native"
  [[ "$blueprint_runtime" == "container" ]] && blueprint_type="Container"

  # Metadata: remap snake_case -> PascalCase while preserving null / int types.
  local metadata_json
  metadata_json=$(yq -o=json '.metadata // {}' "$blueprint_path" 2>/dev/null | jq '{
    DisplayName: .display_name,
    Description: .description,
    MaxPlayers: .max_players,
    MinRamMb: .min_ram_mb,
    RecommendedRamMb: .recommended_ram_mb,
    BaseDiskMb: .base_disk_mb
  }')

  # Top-level fields are emitted exactly as before (strings via --arg) so existing
  # C# consumers bind unchanged; only the Metadata object is added.
  jq -n \
    --arg name "$blueprint_name" \
    --arg ports "$blueprint_ports" \
    --arg blueprint_type "$blueprint_type" \
    --arg steam_app_id "$blueprint_steam_app_id" \
    --arg client_steam_app_id "$blueprint_client_steam_app_id" \
    --arg is_steam_account_required "$blueprint_is_steam_account_required" \
    --arg executable_file "$blueprint_executable_file" \
    --arg level_name "$blueprint_level_name" \
    --arg executable_subdirectory "$blueprint_executable_subdirectory" \
    --arg executable_arguments "$blueprint_executable_arguments" \
    --arg stop_command "$blueprint_stop_command" \
    --arg save_command "$blueprint_save_command" \
    --argjson metadata "$metadata_json" \
    '{
      Name: $name,
      Ports: $ports,
      BlueprintType: $blueprint_type,
      SteamAppId: $steam_app_id,
      ClientSteamAppId: $client_steam_app_id,
      IsSteamAccountRequired: $is_steam_account_required,
      ExecutableFile: $executable_file,
      LevelName: $level_name,
      ExecutableSubdirectory: $executable_subdirectory,
      ExecutableArguments: $executable_arguments,
      StopCommand: $stop_command,
      SaveCommand: $save_command,
      Metadata: $metadata
    }'

  return $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED
}

export -f __logic_get_blueprint_info_json

# Mark module as loaded
export KGSM_LOGIC_BLUEPRINTS_LOADED=1
