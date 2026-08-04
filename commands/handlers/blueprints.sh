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
    RawgSlug: .rawg_slug,
    MaxPlayers: .max_players,
    MinRamMb: .min_ram_mb,
    RecommendedRamMb: .recommended_ram_mb,
    BaseDiskMb: .base_disk_mb
  }')

  # Ports as the canonical structured array [{start,end,protocol}] — the SAME shape
  # `instances info --json` emits — so no machine consumer (kgsm-lib Blueprint.Ports,
  # kgsm-api's library catalog) re-parses an opaque port string. Native ports come from the
  # blueprint's UFW-style spec; container ports are derived into the same spec by
  # __source_blueprint. An empty or malformed spec yields "[]" (always valid JSON).
  local ports_json
  ports_json=$(__ufw_ports_to_json "$blueprint_ports")

  # Other top-level fields stay strings (--arg); only Ports moved to the structured array
  # and the Metadata object is nested.
  jq -n \
    --arg name "$blueprint_name" \
    --argjson ports "$ports_json" \
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
    --arg kick_command "$blueprint_kick_command" \
    --arg ban_command "$blueprint_ban_command" \
    --arg unban_command "$blueprint_unban_command" \
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
      KickCommand: $kick_command,
      BanCommand: $ban_command,
      UnbanCommand: $unban_command,
      Metadata: $metadata
    }'

  return $EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED
}

export -f __logic_get_blueprint_info_json

# =============================================================================
# BLUEPRINT VALIDATION VERDICT
# =============================================================================

# Resolves a validate argument to a blueprint file path. An argument naming an
# existing file is taken as a path; anything else is resolved as a blueprint
# name through the normal user-shadows-system lookup. The path form is what lets
# a not-yet-committed file be checked before it takes a blueprint's real name.
# Args: $1 = blueprint_name_or_path
# Returns: 0 and echoes the path, or EC_BLUEPRINT_NOT_FOUND.
function __logic_resolve_blueprint_target() {
  local target="$1"

  if [[ -z "$target" ]]; then
    return $EC_INVALID_ARG
  fi

  if [[ -f "$target" ]]; then
    echo "$target"
    return 0
  fi

  local blueprint_path
  if ! blueprint_path=$(__find_blueprint "$target" 2> /dev/null); then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  echo "$blueprint_path"
  return 0
}

export -f __logic_resolve_blueprint_target

# Emits a blueprint's validation verdict as JSON: {valid, path, errors[]}.
# `errors` holds every problem found, not just the first, so a caller rejecting
# a save can report all of them in one pass.
#
# validate_blueprint_format records into a bash array, which does not survive a
# subshell, so this function calls it directly rather than through $(...).
# Args: $1 = blueprint_path
# Returns: EC_SUCCESS_BLUEPRINT_VALIDATED when valid, EC_INVALID_BLUEPRINT when
#          not, or EC_MISSING_DEPENDENCY when yq is unavailable.
function __logic_get_blueprint_validation_json() {
  local blueprint_path="$1"

  if [[ -z "$blueprint_path" ]]; then
    return $EC_INVALID_ARG
  fi

  validate_blueprint_format "$blueprint_path" 2> /dev/null
  local format_result=$?

  local errors_json="[]"
  if [[ ${#KGSM_BLUEPRINT_VALIDATION_ERRORS[@]} -gt 0 ]]; then
    errors_json=$(printf '%s\n' "${KGSM_BLUEPRINT_VALIDATION_ERRORS[@]}" \
      | jq -R . | jq -s .)
  fi

  local valid="false"
  [[ $format_result -eq 0 ]] && valid="true"

  # PascalCase keys, matching `blueprints info --json` — kgsm-lib deserializes
  # both through the same source-generated context.
  jq -n \
    --argjson valid "$valid" \
    --arg path "$blueprint_path" \
    --argjson errors "$errors_json" \
    '{
      Valid: $valid,
      Path: $path,
      Errors: $errors
    }'

  if [[ $format_result -eq $EC_MISSING_DEPENDENCY ]]; then
    return $EC_MISSING_DEPENDENCY
  fi

  if [[ $format_result -ne 0 ]]; then
    return $EC_INVALID_BLUEPRINT
  fi

  return $EC_SUCCESS_BLUEPRINT_VALIDATED
}

export -f __logic_get_blueprint_validation_json

# =============================================================================
# BLUEPRINT PATH CANDIDATES
# =============================================================================

# Emits every path a blueprint name could resolve to, in precedence order, as
# JSON: {name, resolved, candidates:[{tier, path, exists}]}.
#
# `resolved` is the winning path (user shadows system), or null when the name
# matches nothing. A caller learns from one call both where the file is and
# whether a user copy is shadowing a system one — the pair of facts a surface
# needs to tell "custom blueprint" apart from "local override of a shipped one".
#
# Unlike `__logic_get_blueprint_path` this reports on existence alone and never
# consults the format validator: its job is locating files, and a malformed
# blueprint still has to be findable in order to be repaired.
# Args: $1 = blueprint_name
# Returns: EC_SUCCESS_BLUEPRINT_FOUND when at least one candidate exists,
#          EC_BLUEPRINT_NOT_FOUND when none does.
function __logic_get_blueprint_candidates_json() {
  local blueprint_name="$1"

  if [[ -z "$blueprint_name" ]]; then
    return $EC_INVALID_ARG
  fi

  local user_path="$KGSM_USER_BLUEPRINTS_DIR/${blueprint_name}.bp.yaml"
  local system_path="$KGSM_SYSTEM_BLUEPRINTS_DIR/${blueprint_name}.bp.yaml"

  local user_exists="false" system_exists="false"
  [[ -f "$user_path" ]] && user_exists="true"
  [[ -f "$system_path" ]] && system_exists="true"

  # Precedence, not preference: whichever of these comes first and exists is
  # the file KGSM loads. Mirrors __find_blueprint.
  local resolved="null"
  if [[ "$user_exists" == "true" ]]; then
    resolved=$(jq -n --arg p "$user_path" '$p')
  elif [[ "$system_exists" == "true" ]]; then
    resolved=$(jq -n --arg p "$system_path" '$p')
  fi

  jq -n \
    --arg name "$blueprint_name" \
    --argjson resolved "$resolved" \
    --arg user_path "$user_path" \
    --argjson user_exists "$user_exists" \
    --arg system_path "$system_path" \
    --argjson system_exists "$system_exists" \
    '{
      Name: $name,
      Resolved: $resolved,
      Candidates: [
        { Tier: "user",   Path: $user_path,   Exists: $user_exists },
        { Tier: "system", Path: $system_path, Exists: $system_exists }
      ]
    }'

  if [[ "$resolved" == "null" ]]; then
    return $EC_BLUEPRINT_NOT_FOUND
  fi

  return $EC_SUCCESS_BLUEPRINT_FOUND
}

export -f __logic_get_blueprint_candidates_json

# Mark module as loaded
export KGSM_LOGIC_BLUEPRINTS_LOADED=1
