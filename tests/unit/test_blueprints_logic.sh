#!/usr/bin/env bash

# KGSM Blueprint Logic Handler Unit Tests
#
# Test Type: UNIT
# Target: commands/handlers/blueprints.sh — the unified blueprint logic layer.
#
# Blueprints are unified `<name>.bp.yaml` files in a single flat directory; the
# `runtime` field (native|container) discriminates the body. These tests cover
# the unified handler API: type detection (from the runtime field), validation,
# path resolution, listing (all/custom/default with user-shadows-system), and
# the canonical info JSON (PascalCase + the nested, nullable Metadata block).

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprints_logic"
readonly HANDLER="$KGSM_ROOT/commands/handlers/blueprints.sh"

function setup_file() {
  log_test_step "Setting up blueprint logic tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$HANDLER" "Blueprint handler should exist"

  # shellcheck disable=SC1090
  source "$HANDLER"

  assert_not_null "$EC_INVALID_ARG" "EC_INVALID_ARG should be defined"
  assert_not_null "$EC_BLUEPRINT_NOT_FOUND" "EC_BLUEPRINT_NOT_FOUND should be defined"
  assert_not_null "$EC_INVALID_BLUEPRINT" "EC_INVALID_BLUEPRINT should be defined"
  assert_not_null "$EC_PERMISSION" "EC_PERMISSION should be defined"
  assert_not_null "$EC_SUCCESS_BLUEPRINT_LISTED" "EC_SUCCESS_BLUEPRINT_LISTED should be defined"
  assert_not_null "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED should be defined"
  assert_not_null "$EC_SUCCESS_BLUEPRINT_FOUND" "EC_SUCCESS_BLUEPRINT_FOUND should be defined"
  assert_not_null "$EC_SUCCESS_BLUEPRINT_VALIDATED" "EC_SUCCESS_BLUEPRINT_VALIDATED should be defined"

  # Scratch space for draft/malformed blueprints that must live outside both
  # blueprints dirs, so they are never picked up by name resolution.
  BLUEPRINT_TEST_TEMP_DIR=$(mktemp -d -t "kgsm-blueprint-logic-XXXXXX")
  export BLUEPRINT_TEST_TEMP_DIR

  # Single flat blueprints dir; runtime is a field, not a subdirectory.
  assert_dir_exists "$KGSM_SYSTEM_BLUEPRINTS_DIR" "System blueprints dir should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_DIR/factorio.bp.yaml" "factorio.bp.yaml should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_DIR/terraria.bp.yaml" "terraria.bp.yaml should exist"
  assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_DIR/vrising.bp.yaml" "vrising.bp.yaml should exist"

  # Unified handler API.
  assert_function_exists "__logic_get_blueprint_type" "get_blueprint_type should be exported"
  assert_function_exists "__logic_validate_blueprint" "validate_blueprint should be exported"
  assert_function_exists "__logic_get_blueprint_path" "get_blueprint_path should be exported"
  assert_function_exists "__logic_list_blueprints" "list_blueprints should be exported"
  assert_function_exists "__logic_get_blueprint_info_json" "get_blueprint_info_json should be exported"
  assert_function_exists "__logic_resolve_blueprint_target" "resolve_blueprint_target should be exported"
  assert_function_exists "__logic_get_blueprint_validation_json" "get_blueprint_validation_json should be exported"
  assert_function_exists "__logic_get_blueprint_candidates_json" "get_blueprint_candidates_json should be exported"

  log_test_step "Blueprint logic test environment validated"
}

function teardown_file() {
  if [[ -n "${BLUEPRINT_TEST_TEMP_DIR:-}" ]]; then
    rm -rf "$BLUEPRINT_TEST_TEMP_DIR"
  fi
}

# =============================================================================
# __logic_get_blueprint_type()  (reads the `runtime` field)
# =============================================================================

function test_get_blueprint_type_native() {
  local output
  output=$(__logic_get_blueprint_type "factorio")
  assert_equals "0" "$?" "Should return success for native blueprint"
  assert_equals "native" "$output" "Should identify factorio as native"
}

function test_get_blueprint_type_container() {
  local output
  output=$(__logic_get_blueprint_type "vrising")
  assert_equals "0" "$?" "Should return success for container blueprint"
  assert_equals "container" "$output" "Should identify vrising as container"
}

function test_get_blueprint_type_not_found() {
  __logic_get_blueprint_type "nonexistent-blueprint-xyz" 2> /dev/null
  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$?" "Should return blueprint not found error"
}

function test_get_blueprint_type_empty_param() {
  __logic_get_blueprint_type "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}

# =============================================================================
# __logic_validate_blueprint()
# =============================================================================

function test_validate_blueprint_valid_native() {
  __logic_validate_blueprint "terraria" 2> /dev/null
  assert_equals "0" "$?" "Should validate terraria successfully"
}

function test_validate_blueprint_valid_container() {
  __logic_validate_blueprint "vrising" 2> /dev/null
  assert_equals "0" "$?" "Should validate vrising successfully"
}

function test_validate_blueprint_container_host_net_with_ports_ok() {
  # A host-networked container with a `ports:` block is valid: under host
  # networking `ports:` is the firewall/UPnP source of truth, not a Docker
  # publish, so it is accepted.
  local custom_bp="$KGSM_USER_BLUEPRINTS_DIR/test-hostnet.bp.yaml"
  cat > "$custom_bp" << 'EOF'
schema_version: 1
name: test-hostnet
runtime: container
container:
  compose: |-
    services:
      game:
        image: example:latest
        network_mode: host
        ports:
          - 7777:7777/udp
EOF
  __logic_validate_blueprint "test-hostnet" 2> /dev/null
  local exit_code=$?
  rm -f "$custom_bp"
  assert_equals "0" "$exit_code" "Host-networked container with ports should validate"
}

function test_validate_blueprint_container_rejects_bridge_network() {
  # A bridge service's `ports:` become a DNAT publish that bypasses the host
  # firewall's INPUT chain — rejected so it can never reach an instance.
  local custom_bp="$KGSM_USER_BLUEPRINTS_DIR/test-bridge.bp.yaml"
  cat > "$custom_bp" << 'EOF'
schema_version: 1
name: test-bridge
runtime: container
container:
  compose: |-
    services:
      game:
        image: example:latest
        network_mode: bridge
        ports:
          - 7777:7777/udp
EOF
  __logic_validate_blueprint "test-bridge" 2> /dev/null
  local exit_code=$?
  rm -f "$custom_bp"
  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Bridge-networked container blueprint must be rejected"
}

function test_validate_blueprint_container_rejects_missing_network_mode() {
  # No `network_mode` at all defaults to bridge under Compose — same hazard,
  # same rejection.
  local custom_bp="$KGSM_USER_BLUEPRINTS_DIR/test-nonet.bp.yaml"
  cat > "$custom_bp" << 'EOF'
schema_version: 1
name: test-nonet
runtime: container
container:
  compose: |-
    services:
      game:
        image: example:latest
        ports:
          - 7777:7777/udp
EOF
  __logic_validate_blueprint "test-nonet" 2> /dev/null
  local exit_code=$?
  rm -f "$custom_bp"
  assert_equals "$EC_INVALID_ARG" "$exit_code" \
    "Container blueprint without network_mode: host must be rejected"
}

function test_validate_blueprint_not_found() {
  __logic_validate_blueprint "does-not-exist" 2> /dev/null
  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$?" "Should return blueprint not found error"
}

function test_validate_blueprint_empty_param() {
  __logic_validate_blueprint "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}

# =============================================================================
# __logic_get_blueprint_path()
# =============================================================================

function test_get_blueprint_path_native() {
  local output
  output=$(__logic_get_blueprint_path "starbound")
  assert_equals "0" "$?" "Should return success for starbound"
  assert_contains "$output" "starbound.bp.yaml" "Path should contain the unified filename"
  assert_file_exists "$output" "Returned path should exist"
}

function test_get_blueprint_path_container() {
  local output
  output=$(__logic_get_blueprint_path "vrising")
  assert_equals "0" "$?" "Should return success for vrising"
  assert_contains "$output" "vrising.bp.yaml" "Path should contain the unified filename"
  assert_file_exists "$output" "Returned path should exist"
}

function test_get_blueprint_path_not_found() {
  __logic_get_blueprint_path "missing-blueprint" 2> /dev/null
  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$?" "Should return blueprint not found error"
}

function test_get_blueprint_path_empty_param() {
  __logic_get_blueprint_path "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}

function test_get_blueprint_path_permission_denied() {
  local blueprint_path="$KGSM_SYSTEM_BLUEPRINTS_DIR/necesse.bp.yaml"
  local original_perms
  original_perms=$(stat -c "%a" "$blueprint_path")
  chmod 000 "$blueprint_path"
  __logic_get_blueprint_path "necesse" 2> /dev/null
  local exit_code=$?
  chmod "$original_perms" "$blueprint_path"
  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" "Should return invalid blueprint error for unreadable file"
}

# =============================================================================
# __logic_list_blueprints()  (single flat dir; user shadows system)
# =============================================================================

function test_list_blueprints_all() {
  local output
  output=$(__logic_list_blueprints "all")
  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$?" "Should return success code"
  assert_contains "$output" "factorio" "Should list factorio"
  assert_contains "$output" "terraria" "Should list terraria"
  assert_contains "$output" "starbound" "Should list starbound"
  assert_contains "$output" "necesse" "Should list necesse"
  assert_contains "$output" "vrising" "Should list vrising (container, same dir)"
}

function test_list_blueprints_default_source_arg() {
  local output
  output=$(__logic_list_blueprints)
  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$?" "Should return success code"
  assert_not_null "$output" "Should return a blueprint list"
}

function test_list_blueprints_default_filter() {
  local output
  output=$(__logic_list_blueprints "default")
  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$?" "Should return success code"
  assert_contains "$output" "factorio" "Default set should include shipped blueprints"
}

function test_list_blueprints_custom() {
  local custom_bp="$KGSM_USER_BLUEPRINTS_DIR/test-custom.bp.yaml"
  cat > "$custom_bp" << 'EOF'
schema_version: 1
name: test-custom
runtime: native
metadata:
  display_name: null
  description: null
  max_players: null
  min_ram_mb: null
  recommended_ram_mb: null
  base_disk_mb: null
native:
  executable_file: test.sh
EOF
  local output
  output=$(__logic_list_blueprints "custom")
  local exit_code=$?
  rm -f "$custom_bp"
  assert_equals "$EC_SUCCESS_BLUEPRINT_LISTED" "$exit_code" "Should return success code"
  assert_contains "$output" "test-custom" "Should list the custom blueprint"
}

function test_list_blueprints_invalid_source() {
  __logic_list_blueprints "invalid" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}

function test_list_blueprints_sorted() {
  local output sorted_output
  output=$(__logic_list_blueprints "all")
  sorted_output=$(echo "$output" | sort)
  assert_equals "$sorted_output" "$output" "Output should be sorted alphabetically"
}

function test_list_blueprints_user_shadows_system() {
  # A user blueprint named like a system one must shadow it (appear once, from
  # the user dir).
  local shadow="$KGSM_USER_BLUEPRINTS_DIR/factorio.bp.yaml"
  cat > "$shadow" << 'EOF'
schema_version: 1
name: factorio
runtime: native
metadata:
  display_name: null
native:
  executable_file: factorio
EOF
  local path count
  path=$(__logic_get_blueprint_path "factorio")
  count=$(__logic_list_blueprints "all" | grep -c '^factorio$')
  rm -f "$shadow"
  assert_contains "$path" "$KGSM_USER_BLUEPRINTS_DIR" "Resolved path should be the user blueprint"
  assert_equals "1" "$count" "Shadowed blueprint should appear exactly once"
}

# =============================================================================
# __logic_get_blueprint_info_json()
# =============================================================================

function test_info_json_native() {
  local output
  output=$(__logic_get_blueprint_info_json "factorio")
  assert_equals "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "$?" "Should return success code"
  assert_equals "factorio" "$(echo "$output" | jq -r '.Name')" "Name should be factorio"
  assert_equals "Native" "$(echo "$output" | jq -r '.BlueprintType')" "BlueprintType should be Native"
  assert_not_null "$(echo "$output" | jq -r '.ExecutableFile')" "ExecutableFile should be present"
  # Ports are the canonical structured array [{start,end,protocol}] — the same shape
  # `instances info --json` emits, not the legacy UFW string. factorio declares "34197"
  # (no protocol) so it expands to one tcp + one udp mapping.
  assert_equals "array" "$(echo "$output" | jq -r '.Ports | type')" "Ports should be a structured array"
  assert_equals "true" \
    "$(echo "$output" | jq -r 'any(.Ports[]; .start==34197 and .end==34197 and .protocol=="tcp")')" \
    "Ports should carry the structured 34197/tcp mapping"
  assert_equals "true" \
    "$(echo "$output" | jq -r 'any(.Ports[]; .start==34197 and .protocol=="udp")')" \
    "A protocol-less spec should expand to a udp mapping too"
}

function test_info_json_container_derives_ports() {
  local output
  output=$(__logic_get_blueprint_info_json "vrising")
  assert_equals "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "$?" "Should return success code"
  assert_equals "Container" "$(echo "$output" | jq -r '.BlueprintType')" "BlueprintType should be Container"
  # Container ports are derived from the embedded compose, then emitted as the SAME
  # canonical structured array [{start,end,protocol}] as native blueprints.
  assert_equals "array" "$(echo "$output" | jq -r '.Ports | type')" "Ports should be a structured array"
  assert_equals "true" \
    "$(echo "$output" | jq -r 'any(.Ports[]; .start==9876 and .protocol=="udp")')" \
    "Container ports should be derived from compose as structured {start,end,protocol}"
  assert_equals "" "$(echo "$output" | jq -r '.ExecutableFile')" "Native-only fields should be empty for containers"
}

function test_info_json_has_metadata_block() {
  local output meta
  output=$(__logic_get_blueprint_info_json "factorio")
  meta=$(echo "$output" | jq -r '.Metadata | keys | sort | join(",")')
  assert_equals "BaseDiskMb,Description,DisplayName,MaxPlayers,MinRamMb,RawgSlug,RecommendedRamMb" "$meta" \
    "Metadata should expose the full PascalCase key set"
}

function test_info_json_rawg_slug_curated() {
  # rawg_slug is the external-catalog (RAWG.io) lookup hint, emitted as a string
  # under the nested Metadata block when curated.
  local output
  output=$(__logic_get_blueprint_info_json "factorio")
  assert_equals "factorio" "$(echo "$output" | jq -r '.Metadata.RawgSlug')" \
    "Curated rawg_slug should round-trip as Metadata.RawgSlug"
  # The blueprint name is NOT assumed to equal the slug.
  output=$(__logic_get_blueprint_info_json "gmod")
  assert_equals "garrys-mod" "$(echo "$output" | jq -r '.Metadata.RawgSlug')" \
    "rawg_slug is independent of the blueprint name (gmod -> garrys-mod)"
}

function test_info_json_rawg_slug_absent_is_null() {
  # honest-null: a blueprint without rawg_slug emits JSON null, never a fabricated
  # value (e.g. never falling back to the blueprint name).
  local custom_bp="$KGSM_USER_BLUEPRINTS_DIR/test-noslug.bp.yaml"
  cat > "$custom_bp" << 'EOF'
schema_version: 1
name: test-noslug
runtime: native
metadata:
  display_name: null
  description: null
native:
  executable_file: test.sh
EOF
  local output
  output=$(__logic_get_blueprint_info_json "test-noslug")
  local exit_code=$?
  rm -f "$custom_bp"
  assert_equals "$EC_SUCCESS_BLUEPRINT_INFO_RETRIEVED" "$exit_code" "Should succeed"
  assert_equals "true" "$(echo "$output" | jq '.Metadata.RawgSlug == null')" \
    "Absent rawg_slug must be JSON null, never fabricated from the name"
}

function test_info_json_uncurated_metadata_is_null_not_zero() {
  # The no-fabricate invariant: an uncurated numeric field is JSON null, NEVER 0.
  # Use a synthetic blueprint with explicitly-null metadata so the assertion holds
  # regardless of how the shipped blueprints get curated over time (a real game's
  # min_ram/max_players can legitimately be filled in later).
  local custom_bp="$KGSM_USER_BLUEPRINTS_DIR/test-nullmeta.bp.yaml"
  cat > "$custom_bp" << 'EOF'
schema_version: 1
name: test-nullmeta
runtime: native
metadata:
  max_players: null
  min_ram_mb: null
native:
  executable_file: test.sh
EOF
  local output
  output=$(__logic_get_blueprint_info_json "test-nullmeta")
  rm -f "$custom_bp"
  assert_equals "null" "$(echo "$output" | jq -r '.Metadata.MaxPlayers')" \
    "Uncurated MaxPlayers must be null, not 0"
  assert_equals "true" "$(echo "$output" | jq '.Metadata.MinRamMb == null')" \
    "Uncurated MinRamMb must be JSON null"
}

function test_info_json_steam_fields_preserved() {
  # Top-level fields keep their existing string shape (consumers bind unchanged).
  local output
  output=$(__logic_get_blueprint_info_json "7dtd")
  assert_equals "294420" "$(echo "$output" | jq -r '.SteamAppId')" "SteamAppId preserved as string"
  assert_equals "251570" "$(echo "$output" | jq -r '.ClientSteamAppId')" "ClientSteamAppId preserved as string"
  assert_equals "false" "$(echo "$output" | jq -r '.IsSteamAccountRequired')" "Bool false preserved (not blanked)"
}

function test_info_json_not_found() {
  __logic_get_blueprint_info_json "nonexistent" 2> /dev/null
  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$?" "Should return blueprint not found error"
}

function test_info_json_empty_param() {
  __logic_get_blueprint_info_json "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}

function test_info_json_permission_denied() {
  local blueprint_path="$KGSM_SYSTEM_BLUEPRINTS_DIR/terraria.bp.yaml"
  local original_perms
  original_perms=$(stat -c "%a" "$blueprint_path")
  chmod 000 "$blueprint_path"
  __logic_get_blueprint_info_json "terraria" 2> /dev/null
  local exit_code=$?
  chmod "$original_perms" "$blueprint_path"
  assert_equals "$EC_PERMISSION" "$exit_code" "Should return permission error"
}

# =============================================================================
# __logic_resolve_blueprint_target()
# =============================================================================

function test_resolve_target_by_name() {
  local output
  output=$(__logic_resolve_blueprint_target "factorio")
  assert_equals "0" "$?" "Should resolve a blueprint name"
  assert_equals "$KGSM_SYSTEM_BLUEPRINTS_DIR/factorio.bp.yaml" "$output" \
    "Should resolve to the system blueprint path"
}

function test_resolve_target_by_path() {
  # A path is taken as-is, so a file that is not in either blueprints dir — and
  # therefore has no blueprint name yet — can still be checked.
  local draft="$BLUEPRINT_TEST_TEMP_DIR/draft.bp.yaml"
  cat > "$draft" << 'EOF'
schema_version: 1
name: draft
runtime: native
native:
  executable_file: draft.sh
EOF
  local output
  output=$(__logic_resolve_blueprint_target "$draft")
  local exit_code=$?
  rm -f "$draft"
  assert_equals "0" "$exit_code" "Should accept an existing file path"
  assert_equals "$draft" "$output" "Should echo the path unchanged"
}

function test_resolve_target_not_found() {
  __logic_resolve_blueprint_target "nonexistent_blueprint_xyz" 2> /dev/null
  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$?" "Should return blueprint not found"
}

function test_resolve_target_empty_param() {
  __logic_resolve_blueprint_target "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}

# =============================================================================
# __logic_get_blueprint_validation_json()
# =============================================================================

function test_validation_json_valid_native() {
  local output
  output=$(__logic_get_blueprint_validation_json \
    "$KGSM_SYSTEM_BLUEPRINTS_DIR/factorio.bp.yaml")
  local exit_code=$?
  assert_equals "$EC_SUCCESS_BLUEPRINT_VALIDATED" "$exit_code" \
    "Valid native blueprint should return the validated success code"
  assert_equals "true" "$(echo "$output" | jq -r '.Valid')" "Valid should be true"
  assert_equals "0" "$(echo "$output" | jq -r '.Errors | length')" \
    "A valid blueprint should report no errors"
}

function test_validation_json_valid_container() {
  local output
  output=$(__logic_get_blueprint_validation_json \
    "$KGSM_SYSTEM_BLUEPRINTS_DIR/vrising.bp.yaml")
  local exit_code=$?
  assert_equals "$EC_SUCCESS_BLUEPRINT_VALIDATED" "$exit_code" \
    "Valid container blueprint should return the validated success code"
  assert_equals "true" "$(echo "$output" | jq -r '.Valid')" "Valid should be true"
}

function test_validation_json_reports_every_error() {
  # Two independent problems: no `name`, and a native body with no
  # `executable_file`. Both must be reported, so an editor rejecting a save can
  # show the complete list instead of one problem per round-trip.
  local broken="$BLUEPRINT_TEST_TEMP_DIR/broken.bp.yaml"
  cat > "$broken" << 'EOF'
schema_version: 1
runtime: native
native:
  level_name: default
EOF
  local output
  output=$(__logic_get_blueprint_validation_json "$broken")
  local exit_code=$?
  rm -f "$broken"
  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" "Should return invalid blueprint"
  assert_equals "false" "$(echo "$output" | jq -r '.Valid')" "Valid should be false"
  assert_equals "2" "$(echo "$output" | jq -r '.Errors | length')" \
    "Should report both the missing name and the missing executable_file"
  assert_contains "$output" "name" "Errors should mention the missing name"
  assert_contains "$output" "executable_file" \
    "Errors should mention the missing executable_file"
}

function test_validation_json_invalid_runtime() {
  local broken="$BLUEPRINT_TEST_TEMP_DIR/runtime.bp.yaml"
  cat > "$broken" << 'EOF'
schema_version: 1
name: bogus-runtime
runtime: bogus
EOF
  local output
  output=$(__logic_get_blueprint_validation_json "$broken")
  local exit_code=$?
  rm -f "$broken"
  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" "Should return invalid blueprint"
  assert_contains "$output" "runtime" "Errors should mention the invalid runtime"
}

function test_validation_json_invalid_yaml_syntax() {
  local broken="$BLUEPRINT_TEST_TEMP_DIR/syntax.bp.yaml"
  printf 'name: x\n  bad: [unclosed\n' > "$broken"
  local output
  output=$(__logic_get_blueprint_validation_json "$broken")
  local exit_code=$?
  rm -f "$broken"
  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" "Should return invalid blueprint"
  assert_equals "1" "$(echo "$output" | jq -r '.Errors | length')" \
    "Unparseable YAML is a single fatal error; nothing further can be inspected"
  assert_contains "$output" "YAML syntax" "Errors should name the syntax failure"
}

function test_validation_json_empty_file() {
  local broken="$BLUEPRINT_TEST_TEMP_DIR/empty.bp.yaml"
  : > "$broken"
  local output
  output=$(__logic_get_blueprint_validation_json "$broken")
  local exit_code=$?
  rm -f "$broken"
  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" "Should return invalid blueprint"
  assert_contains "$output" "empty" "Errors should say the file is empty"
}

function test_validation_json_container_requires_host_networking() {
  # A bridge-networked service would DNAT-publish its ports past the host
  # firewall's INPUT chain, so it must be rejected.
  local broken="$BLUEPRINT_TEST_TEMP_DIR/bridge.bp.yaml"
  cat > "$broken" << 'EOF'
schema_version: 1
name: bridge-net
runtime: container
container:
  compose: |-
    services:
      bridge-net:
        image: example/image:latest
EOF
  local output
  output=$(__logic_get_blueprint_validation_json "$broken")
  local exit_code=$?
  rm -f "$broken"
  assert_equals "$EC_INVALID_BLUEPRINT" "$exit_code" "Should return invalid blueprint"
  assert_contains "$output" "network_mode" \
    "Errors should name the missing host networking"
}

function test_validation_json_empty_param() {
  __logic_get_blueprint_validation_json "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}

# =============================================================================
# __logic_get_blueprint_candidates_json()
# =============================================================================

function test_candidates_json_system_only() {
  local output
  output=$(__logic_get_blueprint_candidates_json "factorio")
  local exit_code=$?
  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should return found"
  assert_equals "$KGSM_SYSTEM_BLUEPRINTS_DIR/factorio.bp.yaml" \
    "$(echo "$output" | jq -r '.Resolved')" "Should resolve to the system blueprint"
  assert_equals "false" \
    "$(echo "$output" | jq -r '.Candidates[] | select(.Tier == "user") | .Exists')" \
    "No user copy should exist"
  assert_equals "true" \
    "$(echo "$output" | jq -r '.Candidates[] | select(.Tier == "system") | .Exists')" \
    "The system copy should exist"
}

function test_candidates_json_user_shadows_system() {
  # Both tiers present is what distinguishes a local override of a shipped
  # blueprint from a blueprint that only ever existed as a custom one.
  local shadow="$KGSM_USER_BLUEPRINTS_DIR/factorio.bp.yaml"
  cat > "$shadow" << 'EOF'
schema_version: 1
name: factorio
runtime: native
native:
  executable_file: factorio
EOF
  local output
  output=$(__logic_get_blueprint_candidates_json "factorio")
  local exit_code=$?
  rm -f "$shadow"
  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should return found"
  assert_equals "$KGSM_USER_BLUEPRINTS_DIR/factorio.bp.yaml" \
    "$(echo "$output" | jq -r '.Resolved')" "The user copy should win"
  assert_equals "true" \
    "$(echo "$output" | jq -r '.Candidates[] | select(.Tier == "user") | .Exists')" \
    "The user copy should exist"
  assert_equals "true" \
    "$(echo "$output" | jq -r '.Candidates[] | select(.Tier == "system") | .Exists')" \
    "The shadowed system copy should still be reported"
}

function test_candidates_json_user_only() {
  local custom="$KGSM_USER_BLUEPRINTS_DIR/test-candidate.bp.yaml"
  cat > "$custom" << 'EOF'
schema_version: 1
name: test-candidate
runtime: native
native:
  executable_file: test.sh
EOF
  local output
  output=$(__logic_get_blueprint_candidates_json "test-candidate")
  local exit_code=$?
  rm -f "$custom"
  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" "Should return found"
  assert_equals "false" \
    "$(echo "$output" | jq -r '.Candidates[] | select(.Tier == "system") | .Exists')" \
    "A custom blueprint has no system original to revert to"
}

function test_candidates_json_reports_malformed_blueprint() {
  # Locating a file is not the same as approving it: a malformed blueprint must
  # stay findable, or it could never be opened and repaired.
  local broken="$KGSM_USER_BLUEPRINTS_DIR/test-malformed.bp.yaml"
  printf 'name: test-malformed\nruntime: bogus\n' > "$broken"
  local output
  output=$(__logic_get_blueprint_candidates_json "test-malformed")
  local exit_code=$?
  rm -f "$broken"
  assert_equals "$EC_SUCCESS_BLUEPRINT_FOUND" "$exit_code" \
    "A malformed blueprint should still be located"
  assert_equals "$broken" "$(echo "$output" | jq -r '.Resolved')" \
    "Should resolve to the malformed file"
}

function test_candidates_json_not_found() {
  local output
  output=$(__logic_get_blueprint_candidates_json "nonexistent_blueprint_xyz")
  local exit_code=$?
  assert_equals "$EC_BLUEPRINT_NOT_FOUND" "$exit_code" "Should return not found"
  assert_equals "null" "$(echo "$output" | jq -r '.Resolved')" \
    "Resolved should be null when nothing matches, never a fabricated path"
  assert_equals "2" "$(echo "$output" | jq -r '.Candidates | length')" \
    "Both tiers should still be reported as searched"
}

function test_candidates_json_empty_param() {
  __logic_get_blueprint_candidates_json "" 2> /dev/null
  assert_equals "$EC_INVALID_ARG" "$?" "Should return invalid argument error"
}
