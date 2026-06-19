#!/usr/bin/env bash

# KGSM Blueprint Management End-to-End Tests
#
# Test Type: E2E
# Target: Complete blueprint discovery and management workflow via the unified
#         commands/blueprints.sh surface.
#
# Blueprints are unified `<name>.bp.yaml` files in a single flat directory; the
# `runtime` field (native|container) discriminates the body. There is no longer
# a native/container command split — everything goes through blueprints.sh.
#
# Covers: listing (all/default/custom, text + JSON), finding, info retrieval and
# field validation (via the canonical info JSON, including the Metadata block),
# native vs container runtime detection, Steam differentiation, and error paths.
# Standard blueprints: factorio, terraria, starbound, necesse (native), vrising
# (container).

# =============================================================================
# TEST SETUP
# =============================================================================

readonly TEST_NAME="blueprint_management_e2e"
readonly MODULE="$KGSM_ROOT/commands/blueprints.sh"

readonly NATIVE_BLUEPRINTS=("factorio" "terraria" "starbound" "necesse")
readonly CONTAINER_BLUEPRINTS=("vrising")

function setup_file() {
  log_test_step "Setting up blueprint management e2e tests"

  assert_not_null "$KGSM_ROOT" "KGSM_ROOT should be set"
  assert_file_exists "$MODULE" "blueprints.sh should exist"
  assert_file_executable "$MODULE" "blueprints.sh should be executable"

  # Single flat blueprints dir; runtime is a field, not a subdirectory.
  assert_dir_exists "$KGSM_SYSTEM_BLUEPRINTS_DIR" "Blueprints directory should exist"

  for bp in "${NATIVE_BLUEPRINTS[@]}" "${CONTAINER_BLUEPRINTS[@]}"; do
    assert_file_exists "$KGSM_SYSTEM_BLUEPRINTS_DIR/${bp}.bp.yaml" \
      "Standard blueprint '${bp}' should exist as ${bp}.bp.yaml"
  done

  log_test_step "Blueprint management e2e environment validated"
}

# =============================================================================
# WORKFLOW 1: List all blueprints
# =============================================================================

function test_list_all_blueprints() {
  log_test_step "Workflow: list returns all standard blueprints"

  local output
  output=$("$MODULE" list 2>&1)
  assert_equals 0 "$?" "blueprints list should succeed"

  for bp in "${NATIVE_BLUEPRINTS[@]}" "${CONTAINER_BLUEPRINTS[@]}"; do
    assert_contains "$output" "$bp" "list should include '${bp}'"
  done
}

# =============================================================================
# WORKFLOW 2: List default blueprints
# =============================================================================

function test_list_default_blueprints() {
  log_test_step "Workflow: list default returns shipped blueprints"

  local output
  output=$("$MODULE" list default 2>&1)
  assert_equals 0 "$?" "blueprints list default should succeed"
  assert_contains "$output" "factorio" "default list should include factorio"
}

# =============================================================================
# WORKFLOW 3: Find native blueprint
# =============================================================================

function test_find_native_blueprint() {
  log_test_step "Workflow: find native blueprint returns valid .bp.yaml path"

  local path
  path=$("$MODULE" find factorio 2>&1)
  assert_equals 0 "$?" "blueprints find factorio should succeed"
  assert_file_exists "$path" "found path should point to an existing file"
  assert_ends_with "$path" "factorio.bp.yaml" "native blueprint path should end with .bp.yaml"
}

# =============================================================================
# WORKFLOW 4: Find container blueprint
# =============================================================================

function test_find_container_blueprint() {
  log_test_step "Workflow: find container blueprint returns valid .bp.yaml path"

  local path
  path=$("$MODULE" find vrising 2>&1)
  assert_equals 0 "$?" "blueprints find vrising should succeed"
  assert_file_exists "$path" "found path should point to an existing file"
  assert_ends_with "$path" "vrising.bp.yaml" "container blueprint path should end with .bp.yaml"
}

# =============================================================================
# WORKFLOW 5: Runtime detection per blueprint (via info --json BlueprintType)
# =============================================================================

function test_runtime_detection() {
  log_test_step "Workflow: each blueprint reports its correct runtime"

  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    local bt
    bt=$("$MODULE" info "$bp" --json 2>&1 | jq -r '.BlueprintType')
    assert_equals "Native" "$bt" "${bp} should be Native"
  done

  for bp in "${CONTAINER_BLUEPRINTS[@]}"; do
    local bt
    bt=$("$MODULE" info "$bp" --json 2>&1 | jq -r '.BlueprintType')
    assert_equals "Container" "$bt" "${bp} should be Container"
  done
}

# =============================================================================
# WORKFLOW 6: Required fields populated for native blueprints (info --json)
# =============================================================================

function test_native_blueprints_have_required_fields() {
  log_test_step "Workflow: native blueprints expose name/executable_file/level_name"

  for bp in "${NATIVE_BLUEPRINTS[@]}"; do
    local info
    info=$("$MODULE" info "$bp" --json 2>&1)
    assert_equals 0 "$?" "blueprints info ${bp} --json should succeed"

    assert_equals "$bp" "$(echo "$info" | jq -r '.Name')" "${bp}: Name should match"
    assert_not_null "$(echo "$info" | jq -r '.ExecutableFile')" \
      "${bp}: ExecutableFile should not be empty"
    assert_not_null "$(echo "$info" | jq -r '.LevelName')" \
      "${bp}: LevelName should not be empty"
  done
}

# =============================================================================
# WORKFLOW 7: Metadata block present (nullable, never fabricated)
# =============================================================================

function test_metadata_block_present() {
  log_test_step "Workflow: info JSON carries the nullable Metadata block"

  local info
  info=$("$MODULE" info factorio --json 2>&1)

  # The block exists with the full key set...
  assert_equals "6" "$(echo "$info" | jq -r '.Metadata | keys | length')" \
    "Metadata should expose six keys"
  # ...and uncurated numeric values are null, never a fabricated 0.
  assert_equals "true" "$(echo "$info" | jq '.Metadata.MaxPlayers == null')" \
    "Uncurated MaxPlayers must be JSON null"
}

# =============================================================================
# WORKFLOW 8: Invalid blueprint returns error
# =============================================================================

function test_invalid_blueprint_returns_error() {
  log_test_step "Workflow: invalid blueprint name returns non-zero exit code"

  assert_command_fails "$MODULE find nonexistent_blueprint_xyz_abc" \
    "find with nonexistent blueprint should fail"
  assert_command_fails "$MODULE info nonexistent_blueprint_xyz_abc" \
    "info with nonexistent blueprint should fail"
}

# =============================================================================
# WORKFLOW 9: list/find consistency for every standard blueprint
# =============================================================================

function test_list_find_consistency() {
  log_test_step "Workflow: every standard blueprint resolves via find"

  for bp in "${NATIVE_BLUEPRINTS[@]}" "${CONTAINER_BLUEPRINTS[@]}"; do
    local path
    path=$("$MODULE" find "$bp" 2>&1)
    assert_equals 0 "$?" "find '${bp}' should succeed"
    assert_file_exists "$path" "find '${bp}' should return an existing file"
  done
}

# =============================================================================
# WORKFLOW 10: Steam vs non-Steam differentiation (via info --json SteamAppId)
# =============================================================================

function test_steam_blueprint_field_differentiation() {
  log_test_step "Workflow: Steam blueprints carry a steam_app_id and client_steam_app_id; factorio is 0"

  for bp in "starbound" "necesse"; do
    local steam_app_id client_steam_app_id
    steam_app_id=$("$MODULE" info "$bp" --json 2>&1 | jq -r '.SteamAppId')
    client_steam_app_id=$("$MODULE" info "$bp" --json 2>&1 | jq -r '.ClientSteamAppId')
    assert_not_null "$steam_app_id" "${bp}: SteamAppId should be set"
    assert_not_equals "0" "$steam_app_id" "${bp}: SteamAppId should be a real Steam id"
    assert_not_null "$client_steam_app_id" "${bp}: ClientSteamAppId should be set"
    assert_not_equals "0" "$client_steam_app_id" "${bp}: ClientSteamAppId should be a real Steam id"
  done

  local factorio_steam_id factorio_client_steam_id
  factorio_steam_id=$("$MODULE" info factorio --json 2>&1 | jq -r '.SteamAppId')
  factorio_client_steam_id=$("$MODULE" info factorio --json 2>&1 | jq -r '.ClientSteamAppId')
  assert_equals "0" "$factorio_steam_id" "factorio: SteamAppId should be 0 (non-Steam)"
  assert_equals "0" "$factorio_client_steam_id" "factorio: ClientSteamAppId should be 0 (non-Steam)"
}

# =============================================================================
# WORKFLOW 11: JSON output for list and info
# =============================================================================

function test_json_output() {
  log_test_step "Workflow: list and info --json produce expected data"

  local list_json
  list_json=$("$MODULE" list --json 2>&1)
  assert_equals 0 "$?" "blueprints list --json should succeed"
  assert_contains "$list_json" "factorio" "list --json should include factorio"
  assert_contains "$list_json" "vrising" "list --json should include vrising"

  local info_json
  info_json=$("$MODULE" info vrising --json 2>&1)
  assert_equals 0 "$?" "blueprints info vrising --json should succeed"
  # Container ports are derived from the embedded compose, emitted as the canonical
  # structured array [{start,end,protocol}] (the same shape `instances info --json` uses).
  assert_equals "array" "$(echo "$info_json" | jq -r '.Ports | type')" \
    "vrising info --json Ports should be a structured array"
  assert_equals "true" \
    "$(echo "$info_json" | jq -r 'any(.Ports[]; .start==9876 and .protocol=="udp")')" \
    "vrising info --json should expose derived ports as structured {start,end,protocol}"
}
